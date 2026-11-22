"""Machine-readable error contracts on isolated disposable MySQL servers."""

import json
import os
import re
import subprocess
import time

import mysql_test_support as support
import test_reference_identity as identity
from error_contract import ERRORS


class ErrorHandlingTests(support.DisposableMySQLTestCase):
    actor = identity.ReferenceIdentityTests.actor
    service = identity.ReferenceIdentityTests.service
    book = identity.ReferenceIdentityTests.book
    open_repair = identity.ReferenceIdentityTests.open_repair
    remove_demo_accounts = identity.ReferenceIdentityTests.remove_demo_accounts

    def setUp(self):
        super().setUp()
        self.addCleanup(self.remove_demo_accounts)
        self.assert_success(self.build('--with-demo-accounts'))
        self.sql(f"""USE `{self.database}`;
DELIMITER //
CREATE PROCEDURE test_CaptureDiagnostic(IN p_SQL TEXT)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_State CHAR(5);
    DECLARE v_Number INT;
    DECLARE v_Message TEXT;
    DECLARE v_Count INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET STACKED DIAGNOSTICS v_Count = NUMBER;
        GET STACKED DIAGNOSTICS CONDITION v_Count v_State = RETURNED_SQLSTATE,
            v_Number = MYSQL_ERRNO, v_Message = MESSAGE_TEXT;
        SELECT JSON_OBJECT('state', v_State, 'number', v_Number, 'message', v_Message);
    END;
    SET @test_error_sql = p_SQL;
    PREPARE test_error_statement FROM @test_error_sql;
    EXECUTE test_error_statement;
    DEALLOCATE PREPARE test_error_statement;
END //
DELIMITER ;
""")

    def value(self, sql):
        return self.scalar(f'USE `{self.database}`; ' + sql)

    def diagnostic(self, sql, user='sa_amy'):
        self.admin_sql(f"GRANT EXECUTE ON PROCEDURE `{self.database}`.test_CaptureDiagnostic TO '{user}'@'localhost';")
        text = self.actor(user, 'CALL test_CaptureDiagnostic(' + support.accounts.literal(sql) + ');')
        return json.loads(text.splitlines()[-1])

    def assert_application(self, diagnostic, identifier):
        code, category = ERRORS[identifier]
        self.assertEqual(diagnostic['number'], code, diagnostic)
        self.assertEqual(diagnostic['state'], '45000')
        self.assertEqual(self.value(f"SELECT fn_ApplicationErrorID({code}), fn_ErrorClass({code}, '45000', FALSE);"), identifier + '\t' + category)

    def rejection(self):
        return json.loads(self.value("SELECT JSON_OBJECT('number', ErrorNumber, 'state', ErrorSQLSTATE, 'message', ErrorMessage, "
            "'identifier', ApplicationErrorID, 'class', ErrorClass, 'outcome', TransactionOutcome, 'user', UserID, 'session', SessionAccount) "
            "FROM AuditLog WHERE Action = 'Rejected' ORDER BY AuditLogID DESC LIMIT 1;"))

    def appointment_sql(self, customer=1, vehicle=5, tech=1, description='Error test', duration=60):
        return (f"CALL sp_CreateServiceAppointment({customer}, {vehicle}, {tech}, NULL, "
                f"TIMESTAMP(CURDATE() + INTERVAL 120 DAY, '08:00:00'), '{description}', {duration})")

    def test_every_application_identifier_is_unique_and_classified_without_message_text(self):
        self.assertEqual(len({code for code, _ in ERRORS.values()}), len(ERRORS))
        for identifier, (code, category) in ERRORS.items():
            with self.subTest(identifier=identifier):
                self.assertEqual(self.value(f"SELECT fn_ApplicationErrorID({code}), fn_ErrorClass({code}, '45000', FALSE);"), identifier + '\t' + category)
        self.assertEqual(self.value("SELECT fn_ErrorClass(1213, '40001', FALSE);"), 'retryable')
        self.assertEqual(self.value("SELECT fn_ErrorClass(1064, '42000', FALSE);"), 'critical')

    def test_invalid_appointment_records_exact_original_diagnostics(self):
        diagnostic = self.diagnostic(self.appointment_sql(duration=0))
        self.assert_application(diagnostic, 'VSM_INVALID_APPOINTMENT')
        audit = self.rejection()
        for field in ('number', 'state', 'message'):
            self.assertEqual(audit[field], diagnostic[field])
        self.assertEqual((audit['identifier'], audit['class'], audit['outcome'], audit['user'], audit['session']),
                         ('VSM_INVALID_APPOINTMENT', 'validation', 'rolled_back', 2, 'sa_amy@localhost'))

    def test_unknown_business_records_have_stable_not_found_codes(self):
        for sql, identifier in ((self.appointment_sql(customer=99999), 'VSM_CUSTOMER_NOT_FOUND'),
                                (self.appointment_sql(vehicle=99999), 'VSM_VEHICLE_NOT_FOUND'),
                                (self.appointment_sql(tech=99999), 'VSM_TECHNICIAN_NOT_FOUND'),
                                ('CALL sp_CompleteRepair(99999, 1, NULL, NULL)', 'VSM_REPAIR_NOT_FOUND')):
            with self.subTest(identifier=identifier):
                self.assert_application(self.diagnostic(sql, 'tech_ben' if 'CompleteRepair' in sql else 'sa_amy'), identifier)

    def test_unauthorized_person_and_native_permission_errors_remain_distinct(self):
        diagnostic = self.diagnostic("CALL sp_CreateServiceAppointment(1, 5, 1, 1, CURDATE() + INTERVAL 120 DAY, 'Forged', 60)")
        self.assert_application(diagnostic, 'VSM_ACTOR_MISMATCH')
        self.assertEqual(self.rejection()['outcome'], 'not_started')
        self.actor('sa_amy', 'CALL sp_CompleteRepair(9, 1, 2, NULL);', 'ERROR 1370')
        self.assertEqual(self.value("SELECT fn_ErrorClass(1370, '42000', FALSE);"), 'forbidden')

    def test_scheduling_and_workflow_conflicts_use_conflict_identifiers(self):
        self.book()
        self.assert_application(self.diagnostic(self.appointment_sql()), 'VSM_SCHEDULE_CONFLICT')
        self.assert_application(self.diagnostic("UPDATE Invoice SET TotalAmount = TotalAmount + 1 WHERE InvoiceID = 1"), 'VSM_FINAL_STATE_IMMUTABLE')
        self.assert_application(self.diagnostic("UPDATE Invoice SET Status = 'Draft' WHERE InvoiceID = 1"), 'VSM_INVALID_TRANSITION')

    def test_indicator_and_temporal_query_validation_have_stable_codes(self):
        self.assert_application(self.diagnostic("CALL sp_ListIndicatorValues('missing')"), 'VSM_UNKNOWN_INDICATOR')
        self.assert_application(self.diagnostic("UPDATE Part SET ActiveStatus = 2 WHERE PartID = 1", 'mgr_mike'), 'VSM_INVALID_INDICATOR')
        self.assert_application(self.diagnostic("CALL sp_ListAuditTrail(NULL, NULL, NULL, NULL, NULL, NULL, 201)", 'mgr_mike'), 'VSM_INVALID_AUDIT_QUERY')

    def test_temporal_history_protection_has_a_stable_forbidden_identifier(self):
        self.admin_sql(f"GRANT SELECT, DELETE ON `{self.database}`.CustomerHistory TO 'sa_amy'@'localhost';")
        self.assert_application(self.diagnostic('DELETE FROM CustomerHistory WHERE CustomerID = 1'), 'VSM_HISTORY_WRITE_DENIED')

    def test_missing_current_history_is_classified_as_critical_and_rolls_back(self):
        # Privileged DDL corruption only in this disposable test database.
        self.sql(f'TRUNCATE TABLE `{self.database}`.CustomerHistory;')
        before = self.value('SELECT Name FROM Customer WHERE CustomerID = 1;')
        diagnostic = self.diagnostic("UPDATE Customer SET Name = 'Must roll back' WHERE CustomerID = 1")
        self.assert_application(diagnostic, 'VSM_HISTORY_INCONSISTENT')
        self.assertEqual(self.value('SELECT Name FROM Customer WHERE CustomerID = 1;'), before)

    def test_changing_human_message_does_not_change_the_error_contract(self):
        self.sql(f"USE `{self.database}`; DROP TRIGGER trg_Customer_Provenance_bi; "
                 "CREATE TRIGGER trg_Customer_Provenance_bi BEFORE INSERT ON Customer FOR EACH ROW "
                 "SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Localized or revised explanation';")
        diagnostic = self.diagnostic("INSERT INTO Customer (Name) VALUES ('Anything')")
        self.assert_application(diagnostic, 'VSM_REQUIRED_FIELD')
        self.assertEqual(diagnostic['message'], 'Localized or revised explanation')

    def test_native_constraint_errors_are_not_replaced(self):
        diagnostic = self.diagnostic("INSERT INTO Customer (CustomerID, Name) VALUES (1, 'Duplicate')")
        self.assertEqual((diagnostic['number'], diagnostic['state']), (1062, '23000'))
        self.assertIn('Duplicate', diagnostic['message'])
        self.assertEqual(self.value("SELECT fn_ApplicationErrorID(1062) IS NULL, fn_ErrorClass(1062, '23000', FALSE);"), '1\tconflict')

    def test_secondary_logger_failure_does_not_replace_original_exception(self):
        self.sql(f"USE `{self.database}`;\nDELIMITER //\nDROP PROCEDURE sp_RecordRejectedDiagnostic //\n"
                 "CREATE PROCEDURE sp_RecordRejectedDiagnostic(IN a INT, IN b VARCHAR(64), IN c VARCHAR(100), IN d INT, "
                 "IN e TEXT, IN f JSON, IN g CHAR(36), IN h CHAR(5), IN i INT, IN j VARCHAR(16)) "
                 "BEGIN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59999, MESSAGE_TEXT = 'Injected logger failure'; END //\nDELIMITER ;\n")
        diagnostic = self.diagnostic(self.appointment_sql(duration=0))
        self.assert_application(diagnostic, 'VSM_INVALID_APPOINTMENT')
        self.assertEqual(diagnostic['message'], 'Invalid appointment information')
        self.assertEqual(self.value("SELECT COUNT(*) FROM AuditLog WHERE ErrorNumber = 59999;"), '0')

    def test_failed_completion_preserves_all_business_and_temporal_records(self):
        appointment = self.book()
        repair = self.open_repair(appointment)
        self.actor('tech_ben', f"UPDATE vw_MyRepairs SET Status = 'In Progress' WHERE RepairID = {repair};")
        before = self.snapshot()
        history = self.value('SELECT COUNT(*) FROM TemporalEvent;')
        diagnostic = self.diagnostic(f"CALL sp_CompleteRepair({repair}, 1, NULL, '[{{\"partId\":1,\"qty\":999999}}]')", 'tech_ben')
        self.assert_application(diagnostic, 'VSM_INSUFFICIENT_STOCK')
        after = self.snapshot()
        self.assertEqual([row for row in before if row[0].lower() != 'auditlog'], [row for row in after if row[0].lower() != 'auditlog'])
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalEvent;'), history)
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalWriteContext;'), '0')
        self.assertEqual(self.rejection()['outcome'], 'rolled_back')

    def test_missing_part_is_not_found_rather_than_insufficient_stock(self):
        appointment = self.book()
        repair = self.open_repair(appointment)
        self.actor('tech_ben', f"UPDATE vw_MyRepairs SET Status = 'In Progress' WHERE RepairID = {repair};")
        self.assert_application(self.diagnostic(f"CALL sp_CompleteRepair({repair}, 1, NULL, '[{{\"partId\":99999,\"qty\":1}}]')", 'tech_ben'), 'VSM_PART_NOT_FOUND')

    def process(self, user='vsm_developer', password=None):
        env = os.environ.copy()
        env['MYSQL_PWD'] = self.developer_password if password is None else password
        return subprocess.Popen([self.mysql, '--no-defaults', '--protocol=SOCKET', f'--socket={self.socket}',
            f'--user={user}', f'--database={self.database}', '--batch', '--raw', '--skip-column-names', '--skip-force', '--unbuffered'],
            env=env, text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def finish(self, process):
        if process.poll() is None:
            process.kill()
        process.communicate(timeout=10)

    def test_native_lock_timeout_diagnostics_survive_the_public_handler(self):
        blocker = self.process()
        try:
            blocker.stdin.write("START TRANSACTION; SELECT TechnicianID FROM Technician WHERE TechnicianID = 1 FOR UPDATE; SELECT 'locked';\n")
            blocker.stdin.flush()
            self.assertEqual(blocker.stdout.readline().strip(), '1')
            self.assertEqual(blocker.stdout.readline().strip(), 'locked')
            self.actor('sa_amy', 'SET SESSION innodb_lock_wait_timeout = 1; ' + self.appointment_sql() + ';', 'ERROR 1205')
            audit = self.rejection()
            self.assertEqual((audit['number'], audit['state'], audit['class'], audit['outcome']), (1205, 'HY000', 'retryable', 'rolled_back'))
            self.assertIsNone(audit['identifier'])
            self.assertIn('Lock wait timeout', audit['message'])
        finally:
            self.finish(blocker)

    def test_native_deadlock_keeps_its_number_and_transaction_rollback_semantics(self):
        self.sql(f"INSERT INTO `{self.database}`.Customer (CustomerID, Name) VALUES (7001, 'First'), (7002, 'Second');")
        first, second = self.process(), self.process()
        try:
            # Different history tables keep the setup independent of history
            # index gap locks; the cycle below is on the two business rows.
            for process, table, key in ((first, 'Customer', 'CustomerID = 7001'),
                                        (second, 'Technician', 'TechnicianID = 2')):
                process.stdin.write(f"START TRANSACTION; UPDATE {table} SET Phone = 'first write' WHERE {key}; SELECT 'ready';\n")
                process.stdin.flush()
                self.assertEqual(process.stdout.readline().strip(), 'ready')
            first.stdin.write("UPDATE Technician SET Phone = 'survivor' WHERE TechnicianID = 2; COMMIT;\n")
            first.stdin.flush()
            # Wait until the first connection has submitted its blocked UPDATE.
            for _ in range(100):
                waiting = self.value("SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE DB = DATABASE() "
                                     "AND INFO LIKE 'UPDATE Technician SET Phone%';")
                if waiting != '0': break
                time.sleep(0.01)
            self.assertNotEqual(waiting, '0')
            second.stdin.write("UPDATE Customer SET Phone = 'survivor' WHERE CustomerID = 7001; COMMIT;\n")
            second.stdin.flush()
            for process in (first, second):
                process.stdin.close()
                process.stdin = None
            results = [process.communicate(timeout=10) for process in (first, second)]
            errors = [stderr for _, stderr in results if stderr]
            self.assertEqual(len(errors), 1, results)
            self.assertRegex(errors[0], r'ERROR 1213 \(40001\)')
            self.assertEqual(self.value("SELECT fn_ErrorClass(1213, '40001', FALSE);"), 'retryable')
            self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalEvent;'), '4')
        finally:
            for process in (first, second): self.finish(process)

    def test_real_deadlock_in_public_procedure_retains_exact_rejection_diagnostics(self):
        # Add an observable synchronization point to this disposable copy only.
        # The marker follows repair/appointment locks and precedes all part reads.
        appointment = self.book()
        repair = self.open_repair(appointment)
        self.actor('tech_ben', f"UPDATE vw_MyRepairs SET Status = 'In Progress' WHERE RepairID = {repair};")
        migration = (self.fixture / 'sql/migrations/006_standardized_error_handling.sql').read_text()
        procedure = re.search(r'CREATE PROCEDURE sp_CompleteRepair\([\s\S]*?\nEND //', migration)[0]
        marker = '    -- Reject any non-array JSON, including {}'
        self.assertEqual(procedure.count(marker), 1)
        procedure = procedure.replace(marker, "    SELECT 'repair_locked';\n" + marker)
        self.sql(f'USE `{self.database}`;\nDELIMITER //\nDROP PROCEDURE sp_CompleteRepair //\n' + procedure + '\nDELIMITER ;\n')
        self.admin_sql(f"GRANT EXECUTE ON PROCEDURE `{self.database}`.sp_CompleteRepair TO 'role_technician';")
        blocker = self.process()
        caller = self.process('tech_ben', 'Tech#2026')
        try:
            # Make the blocker transaction much heavier so InnoDB selects the
            # small public-procedure transaction as the deadlock victim.
            blocker.stdin.write("START TRANSACTION; INSERT INTO Customer (CustomerID, Name) "
                "WITH RECURSIVE n AS (SELECT 8000 AS id UNION ALL SELECT id + 1 FROM n WHERE id < 8099) "
                "SELECT id, CONCAT('Deadlock fixture ', id) FROM n; "
                "SELECT PartID FROM Part WHERE PartID = 1 FOR UPDATE; SELECT 'locked';\n")
            blocker.stdin.flush()
            self.assertEqual(blocker.stdout.readline().strip(), '1')
            self.assertEqual(blocker.stdout.readline().strip(), 'locked')
            caller.stdin.write(f"CALL sp_CompleteRepair({repair}, 1, NULL, '[{{\"partId\":1,\"qty\":1}}]');\n")
            caller.stdin.close()
            caller.stdin = None
            self.assertEqual(caller.stdout.readline().strip(), 'repair_locked')
            blocker.stdin.write(f'SELECT RepairID FROM Repair WHERE RepairID = {repair} FOR UPDATE; COMMIT;\n')
            blocker.stdin.close()
            blocker.stdin = None
            out, error = caller.communicate(timeout=15)
            self.assertNotEqual(caller.returncode, 0, out)
            diagnostic = re.search(r'ERROR (\d+) \((\w+)\) at line \d+: (.*)', error)
            self.assertIsNotNone(diagnostic, error)
            self.assertEqual((int(diagnostic[1]), diagnostic[2]), (1213, '40001'))
            out, error = blocker.communicate(timeout=15)
            self.assertEqual(blocker.returncode, 0, out + error)
            audit = self.rejection()
            self.assertEqual((audit['number'], audit['state'], audit['message']), (1213, '40001', diagnostic[3]))
            self.assertEqual((audit['class'], audit['outcome'], audit['session']), ('retryable', 'rolled_back', 'tech_ben@localhost'))
        finally:
            self.finish(caller)
            self.finish(blocker)

    def test_retry_budget_and_unknown_commit_outcomes_require_explicit_decisions(self):
        for number, state in ((1205, 'HY000'), (1213, '40001')):
            for attempt, expected in ((1, 'retry_transaction'), (2, 'retry_transaction'), (3, 'stop_retry_budget')):
                self.assertEqual(self.value(f"SELECT fn_ErrorCallerAction({number}, '{state}', FALSE, 'rolled_back', {attempt});"), expected)
            self.assertEqual(self.value(f"SELECT fn_ErrorCallerAction({number}, '{state}', FALSE, 'not_started', 1);"), 'confirm_full_rollback')
            self.assertEqual(self.value(f"SELECT fn_ErrorCallerAction({number}, '{state}', FALSE, 'unknown', 1);"), 'reconcile_outcome')
        self.assertEqual(self.value("SELECT fn_ErrorCallerAction(2013, 'HY000', FALSE, 'rolled_back', 1);"), 'reconcile_outcome')
        self.assertEqual(self.value("SELECT fn_ErrorCallerAction(51001, '45000', FALSE, 'rolled_back', 1);"), 'correct_input')
        self.assertEqual(self.value("SELECT fn_ErrorCallerAction(51001, '45000', FALSE, 'committed', 1);"), 'review_completed_result')
        self.assertEqual(self.value("SELECT fn_ErrorCallerAction(1213, '40001', FALSE, 'unrecognized', 1);"), 'reconcile_outcome')
        self.assertEqual(self.value("SELECT fn_ErrorClass(0, '00000', FALSE) IS NULL;"), '1')

    def test_warning_condition_allows_success_and_preserves_warning_diagnostics(self):
        self.sql(f"""USE `{self.database}`;
DELIMITER //
CREATE PROCEDURE test_Warning()
BEGIN
    DECLARE v_Number INT;
    DECLARE v_State CHAR(5);
    DECLARE v_Message TEXT;
    DECLARE v_Completed BOOLEAN DEFAULT FALSE;
    DECLARE CONTINUE HANDLER FOR SQLWARNING
        GET STACKED DIAGNOSTICS CONDITION 1 v_Number = MYSQL_ERRNO, v_State = RETURNED_SQLSTATE, v_Message = MESSAGE_TEXT;
    SIGNAL SQLSTATE '01000' SET MYSQL_ERRNO = 55001, MESSAGE_TEXT = 'Nonfatal test notice';
    SET v_Completed = TRUE;
    SELECT JSON_OBJECT('completed', v_Completed, 'number', v_Number, 'state', v_State, 'message', v_Message);
END //
DELIMITER ;
""")
        result = json.loads(self.value('CALL test_Warning();'))
        self.assertEqual((result['completed'], result['number'], result['state']), (1, 55001, '01000'))
        self.assertEqual(self.value("SELECT fn_ErrorCallerAction(55001, '01000', TRUE, 'completed', 1);"), 'accept_with_warning')
        self.assertEqual(self.value("SELECT fn_ErrorClass(1292, '22007', TRUE), fn_ErrorClass(1292, '22007', FALSE);"), 'warning\tvalidation')

    def test_upgrade_preserves_every_existing_data_history_and_audit_value(self):
        old = self.database + '_old'
        self.addCleanup(lambda: self.sql(f'DROP DATABASE IF EXISTS `{old}`;'))
        self.assert_success(self.build('--target-version', '5', database=old))
        self.sql(f"USE `{old}`; INSERT INTO Customer (CustomerID, Name) VALUES (9990, 'Existing temporal record'); "
                 "UPDATE Customer SET Phone = 'Existing version' WHERE CustomerID = 9990; "
                 "DELETE FROM Customer WHERE CustomerID = 9990; "
                 "CALL sp_RecordRejectedAttempt(NULL, 'sp_CreateServiceAppointment', 'ServiceAppointment', NULL, "
                 "'Legacy rejection without structured diagnostics', JSON_OBJECT(), NULL);")
        def snapshot():
            rows = self.scalar("SELECT TABLE_NAME FROM information_schema.TABLES "
                f"WHERE TABLE_SCHEMA = '{old}' AND TABLE_TYPE = 'BASE TABLE' "
                "AND TABLE_NAME NOT IN ('schema_migrations', 'schema_object_versions') ORDER BY TABLE_NAME;")
            result = []
            for table in rows.splitlines():
                columns = self.scalar("SELECT COLUMN_NAME, DATA_TYPE FROM information_schema.COLUMNS "
                    f"WHERE TABLE_SCHEMA = '{old}' AND TABLE_NAME = '{table}' AND COLUMN_NAME NOT IN "
                    "('ApplicationErrorID', 'ErrorClass', 'ErrorSQLSTATE', 'ErrorNumber', 'ErrorMessage', 'TransactionOutcome') ORDER BY ORDINAL_POSITION;").splitlines()
                # History key hashes contain arbitrary bytes; compare their hex
                # representation without asking subprocess to decode binary UTF-8.
                projection = ', '.join(
                    f'HEX(`{name}`)' if kind in ('binary', 'varbinary', 'tinyblob', 'blob', 'mediumblob', 'longblob', 'bit')
                    else f'`{name}`' for name, kind in (column.split('\t') for column in columns))
                result.append((table, self.scalar(f'SELECT {projection} FROM `{old}`.`{table}` ORDER BY {projection};')))
            return result
        before = snapshot()
        result = self.build('--migrate', database=old)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, snapshot())
        self.assertEqual(self.scalar(f'SELECT COUNT(*) FROM `{old}`.AuditLog WHERE ErrorNumber IS NOT NULL OR ErrorSQLSTATE IS NOT NULL OR ErrorClass IS NOT NULL;'), '0')

    def test_recreation_retains_trigger_order_security_signatures_and_grants(self):
        old = self.database + '_old'
        self.addCleanup(lambda: self.sql(f'DROP DATABASE IF EXISTS `{old}`;'))
        self.assert_success(self.build('--target-version', '5', database=old))
        self.admin_sql("CREATE USER 'error_grant_receiver'@'localhost' ACCOUNT LOCK;")
        self.addCleanup(lambda: self.admin_sql("DROP USER 'error_grant_receiver'@'localhost';"))
        for routine in ('sp_ListIndicatorValues', 'sp_ValidateIndicator', 'sp_ResolveActor',
                        'sp_CreateServiceAppointment', 'sp_CompleteRepair', 'sp_ListAuditTrail'):
            self.admin_sql(f"GRANT EXECUTE, ALTER ROUTINE ON PROCEDURE `{old}`.`{routine}` "
                           "TO 'error_grant_receiver'@'localhost' WITH GRANT OPTION;")
        grant_query = ("SELECT User, Host, Routine_name, Proc_priv FROM mysql.procs_priv "
                       f"WHERE Db = '{old}' AND User <> 'vsm_developer' ORDER BY User, Host, Routine_name;")
        grants_before = self.admin_scalar(grant_query)
        query = ("SELECT TRIGGER_NAME, ACTION_ORDER, DEFINER FROM information_schema.TRIGGERS "
                 f"WHERE TRIGGER_SCHEMA = '{old}' ORDER BY TRIGGER_NAME;")
        before = self.scalar(query)
        signatures = ("SELECT SPECIFIC_NAME, ORDINAL_POSITION, PARAMETER_MODE, PARAMETER_NAME, DTD_IDENTIFIER FROM information_schema.PARAMETERS "
                      f"WHERE SPECIFIC_SCHEMA = '{old}' ORDER BY SPECIFIC_NAME, ORDINAL_POSITION;")
        original_signatures = self.scalar(signatures)
        self.assertEqual(self.build('--migrate', database=old).returncode, 0)
        self.assertEqual(self.scalar(query), before)
        self.assertEqual(self.admin_scalar(grant_query), grants_before)
        actual = self.scalar(signatures).splitlines()
        self.assertTrue(all(row in actual for row in original_signatures.splitlines()))
        self.assertEqual(self.admin_scalar("SELECT COUNT(*) FROM mysql.procs_priv WHERE User = 'vsm_developer' AND FIND_IN_SET('Grant', Proc_priv);"), '0')
        self.assertEqual(self.value("SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND SECURITY_TYPE <> 'DEFINER';"), '1')  # test-only invoker diagnostic helper
