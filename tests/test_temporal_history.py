"""Temporal versions and audit-reader regressions on private MySQL servers only."""

import json
import os
import subprocess

import mysql_test_support as support
import test_reference_identity as identity
from generate_temporal_history import TABLES


class TemporalHistoryTests(support.Version006TestCase):
    actor = identity.ReferenceIdentityTests.actor
    service = identity.ReferenceIdentityTests.service
    book = identity.ReferenceIdentityTests.book
    open_repair = identity.ReferenceIdentityTests.open_repair
    remove_demo_accounts = identity.ReferenceIdentityTests.remove_demo_accounts

    def setUp(self):
        super().setUp()
        self.addCleanup(self.remove_demo_accounts)
        self.assert_success(self.build('--with-demo-accounts'))

    def value(self, query):
        return self.scalar(f'USE `{self.database}`; ' + query)

    def customer(self, identifier=7001):
        self.actor('sa_amy', f"INSERT INTO Customer (CustomerID, Name) VALUES ({identifier}, 'Temporal Customer');")

    def test_every_business_and_durable_metadata_table_has_a_mirrored_snapshot(self):
        for table, keys, _, _ in TABLES:
            with self.subTest(table=table):
                self.assertEqual(self.value(f'SELECT COUNT(*) FROM `{table}`;'),
                                 self.value(f'SELECT COUNT(*) FROM `{table}History` WHERE HistoryIsCurrent = 1;'))
                self.assertEqual(self.value(f"SELECT COUNT(*) FROM `{table}History` WHERE HistoryOrigin <> 'Snapshot' "
                    'OR HistoryValidFrom IS NOT NULL OR HistoryUserID IS NOT NULL OR HistorySessionAccount IS NOT NULL;'), '0')
                actual_columns = self.value("SELECT COLUMN_NAME FROM information_schema.COLUMNS "
                    f"WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '{table}' ORDER BY ORDINAL_POSITION;").splitlines()
                for column in actual_columns:
                    self.assertEqual(self.value("SELECT CONCAT(COUNT(*), ':', COUNT(DISTINCT CONCAT(COLUMN_TYPE, ':', COALESCE(COLLATION_NAME, '')))) "
                        "FROM information_schema.COLUMNS "
                        f"WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('{table}', '{table}History') "
                        f"AND COLUMN_NAME = '{column}';"), '2:1')
                projection = 'JSON_OBJECT(' + ', '.join(f"'{c}', `{c}`" for c in actual_columns) + ')'
                order = ', '.join(f'`{c}`' for c in keys.split())
                self.assertEqual(self.value(f'SELECT {projection} FROM `{table}` ORDER BY {order};').splitlines(),
                                 self.value(f'SELECT {projection} FROM `{table}History` WHERE HistoryIsCurrent = 1 ORDER BY {order};').splitlines())
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalEvent;'), '0')
        self.assertEqual(self.value("SELECT COUNT(*) FROM information_schema.REFERENTIAL_CONSTRAINTS "
                                   "WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME LIKE '%History';"), '0')

    def test_insert_uses_verified_person_session_and_real_utc_clock(self):
        self.actor('sa_amy', "SET timestamp = 946684800; SET time_zone = '+12:00'; SET @context_id = 'forged'; "
                   "INSERT INTO Customer (CustomerID, Name) VALUES (7001, 'Temporal Customer');")
        self.assertEqual(self.value("SELECT CONCAT(HistoryVersion, ':', HistoryUserID, ':', HistorySessionAccount) "
                                    "FROM CustomerHistory WHERE CustomerID = 7001;"), '1:2:sa_amy@localhost')
        self.assertEqual(self.value("SELECT ABS(TIMESTAMPDIFF(SECOND, HistoryValidFrom, UTC_TIMESTAMP())) < 10 "
                                    "AND HistoryContextID IS NULL FROM CustomerHistory WHERE CustomerID = 7001;"), '1')

    def test_successive_updates_close_versions_without_gaps_and_capture_case_changes(self):
        self.customer()
        self.actor('sa_amy', "UPDATE Customer SET Name = 'temporal customer', Phone = '123' WHERE CustomerID = 7001; "
                   "UPDATE Customer SET Email = 'new@example.invalid', Phone = NULL WHERE CustomerID = 7001;")
        rows = self.value("SELECT HistoryVersion, COALESCE(HistoryValidTo, 'current'), Name FROM CustomerHistory "
                          "WHERE CustomerID = 7001 ORDER BY HistoryVersion;").splitlines()
        self.assertEqual([r.split('\t')[0] for r in rows], ['1', '2', '3'])
        self.assertEqual(self.value("SELECT COUNT(*) FROM CustomerHistory a JOIN CustomerHistory b "
            "ON b.CustomerID = a.CustomerID AND b.HistoryVersion = a.HistoryVersion + 1 "
            "WHERE a.CustomerID = 7001 AND a.HistoryValidTo = b.HistoryValidFrom AND a.HistoryValidFrom < a.HistoryValidTo;"), '2')
        attrs = json.loads(self.value("SELECT ChangedAttributes FROM TemporalEvent WHERE EntityType = 'Customer' "
                                      "AND OperationType = 'Update' ORDER BY EventID LIMIT 1;"))
        self.assertEqual(attrs, ['Name', 'Phone'])
        self.assertEqual(self.value('SELECT COUNT(*) FROM CustomerHistory WHERE CustomerID = 7001 AND HistoryIsCurrent = 1;'), '1')

    def test_noop_updates_create_neither_versions_nor_events(self):
        self.customer()
        before = self.value('SELECT COUNT(*) FROM TemporalEvent;')
        self.actor('sa_amy', 'UPDATE Customer SET Name = Name, Phone = Phone WHERE CustomerID = 7001;')
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalEvent;'), before)
        self.assertEqual(self.value('SELECT COUNT(*) FROM CustomerHistory WHERE CustomerID = 7001;'), '1')

    def test_delete_closes_and_retains_row_with_verified_deletion_attribution(self):
        self.actor('sa_amy', "INSERT INTO InvoiceLineItem (InvoiceLineItemID, InvoiceID, Description, Quantity, UnitPrice, LineTotal) "
                   "VALUES (7001, 3, 'Disposable line', 1, 12, 12); DELETE FROM InvoiceLineItem WHERE InvoiceLineItemID = 7001;")
        self.assertEqual(self.value('SELECT COUNT(*) FROM InvoiceLineItem WHERE InvoiceLineItemID = 7001;'), '0')
        self.assertEqual(self.value("SELECT CONCAT(Description, ':', HistoryCloseOperation, ':', HistoryClosedByUserID, ':', HistoryClosedBySession) "
                                    "FROM InvoiceLineItemHistory WHERE InvoiceLineItemID = 7001;"),
                         'Disposable line:Delete:2:sa_amy@localhost')
        self.assertEqual(self.value('SELECT COUNT(*) FROM InvoiceLineItemHistory WHERE InvoiceLineItemID = 7001 AND HistoryIsCurrent = 1;'), '0')
        row = json.loads(self.value("SELECT JSON_ARRAY(PreviousValue, NewValue) FROM vw_AuditTrail "
                                    "WHERE EntityType = 'InvoiceLineItem' AND OperationType = 'Delete' ORDER BY EventID DESC LIMIT 1;"))
        self.assertEqual(row[0]['Description'], 'Disposable line')
        self.assertIsNone(row[1])

    def test_reused_primary_key_continues_version_sequence(self):
        self.customer()
        self.sql(f'DELETE FROM `{self.database}`.Customer WHERE CustomerID = 7001;')
        self.customer()
        self.assertEqual(self.value('SELECT GROUP_CONCAT(HistoryVersion ORDER BY HistoryVersion) FROM CustomerHistory WHERE CustomerID = 7001;'), '1,2')
        self.assertEqual(self.value('SELECT COUNT(*) FROM CustomerHistory WHERE CustomerID = 7001 AND HistoryIsCurrent = 1;'), '1')
        self.assertEqual(self.value('SELECT a.HistoryValidTo < b.HistoryValidFrom FROM CustomerHistory a '
            'JOIN CustomerHistory b ON a.CustomerID = b.CustomerID AND a.HistoryVersion = 1 AND b.HistoryVersion = 2 '
            'WHERE a.CustomerID = 7001;'), '1')

    def test_transaction_rollback_removes_business_history_and_event_changes(self):
        self.customer()
        before = self.value('SELECT COUNT(*) FROM TemporalEvent;')
        self.actor('sa_amy', "START TRANSACTION; UPDATE Customer SET Name = 'Rolled back' WHERE CustomerID = 7001; "
                   "INSERT INTO Customer (CustomerID, Name) VALUES (7002, 'Rolled back insert'); ROLLBACK;")
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalEvent;'), before)
        self.assertEqual(self.value('SELECT COUNT(*) FROM CustomerHistory WHERE CustomerID IN (7001, 7002);'), '1')
        self.assertEqual(self.value('SELECT Name FROM Customer WHERE CustomerID = 7001;'), 'Temporal Customer')
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalWriteContext;'), '0')

        # The read interface must not commit a caller's business transaction.
        self.actor('mgr_mike', "START TRANSACTION; UPDATE Customer SET Phone = 'Reader rollback' WHERE CustomerID = 7001; "
                   "CALL sp_ListAuditTrail('Customer', NULL, NULL, NULL, NULL, NULL, 10); ROLLBACK;")
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalEvent;'), before)
        self.assertEqual(self.value('SELECT COUNT(*) FROM CustomerHistory WHERE CustomerID = 7001;'), '1')

    def test_history_failure_rolls_back_the_entire_business_statement(self):
        self.sql(f"USE `{self.database}`; CREATE TRIGGER test_HistoryFault BEFORE INSERT ON CustomerHistory "
                 "FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Injected history failure';")
        self.actor('sa_amy', "INSERT INTO Customer (CustomerID, Name) VALUES (7001, 'Atomic failure');", 'Injected history failure')
        self.assertEqual(self.value('SELECT COUNT(*) FROM Customer WHERE CustomerID = 7001;'), '0')
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalEvent;'), '0')
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalWriteContext;'), '0')

    def test_concurrent_updates_serialize_history_versions(self):
        self.customer()
        env = os.environ.copy()
        env['MYSQL_PWD'] = 'Advisor#2026'
        first = subprocess.Popen([self.mysql, '--no-defaults', '--protocol=SOCKET', f'--socket={self.socket}',
            '--user=sa_amy', f'--database={self.database}', '--batch', '--raw', '--skip-column-names', '--skip-force', '--unbuffered'],
            env=env, text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            first.stdin.write("START TRANSACTION; UPDATE Customer SET Phone = 'first' WHERE CustomerID = 7001; "
                              "SELECT 'locked'; SELECT SLEEP(1); COMMIT;\n")
            first.stdin.close()
            first.stdin = None
            self.assertEqual(first.stdout.readline().strip(), 'locked')
            self.actor('sa_amy', "UPDATE Customer SET Phone = 'second' WHERE CustomerID = 7001;")
            out, err = first.communicate(timeout=10)
            self.assertEqual(first.returncode, 0, out + err)
        finally:
            if first.poll() is None:
                first.kill()
                first.communicate(timeout=10)
        self.assertEqual(self.value('SELECT GROUP_CONCAT(HistoryVersion ORDER BY HistoryVersion) FROM CustomerHistory WHERE CustomerID = 7001;'), '1,2,3')
        self.assertEqual(self.value("SELECT Phone FROM CustomerHistory WHERE CustomerID = 7001 AND HistoryIsCurrent = 1;"), 'second')
        self.assertEqual(self.value("SELECT COUNT(*) FROM CustomerHistory a JOIN CustomerHistory b "
            "ON a.CustomerID = b.CustomerID AND b.HistoryVersion = a.HistoryVersion + 1 "
            "WHERE a.CustomerID = 7001 AND a.HistoryValidTo = b.HistoryValidFrom;"), '2')

    def test_history_is_protected_even_after_accidental_direct_dml_grants(self):
        self.customer()
        self.actor('mgr_mike', 'UPDATE CustomerHistory SET Name = Name WHERE CustomerID = 7001;', 'ERROR 1142')
        self.admin_sql(f"GRANT SELECT, INSERT, UPDATE, DELETE ON `{self.database}`.CustomerHistory TO 'sa_amy'@'localhost'; "
                       f"GRANT INSERT, UPDATE, DELETE ON `{self.database}`.TemporalEvent TO 'sa_amy'@'localhost';")
        self.actor('sa_amy', "SET @history_authorized = 1; UPDATE CustomerHistory SET Name = 'Forged' WHERE CustomerID = 7001;", 'VSM_HISTORY_WRITE_DENIED')
        self.actor('sa_amy', 'DELETE FROM CustomerHistory WHERE CustomerID = 7001;', 'VSM_HISTORY_WRITE_DENIED')
        self.actor('sa_amy', "INSERT INTO CustomerHistory (CustomerID, Name, HistoryVersion, HistoryRecordedAt, HistoryOrigin) "
                   "VALUES (7002, 'Forged', 1, NOW(), 'Insert');", 'VSM_HISTORY_WRITE_DENIED')
        self.actor('sa_amy', 'DELETE FROM TemporalEvent;', 'VSM_HISTORY_WRITE_DENIED')
        self.actor('sa_amy', "UPDATE TemporalEvent SET SessionAccount = 'forged';", 'VSM_HISTORY_WRITE_DENIED')
        self.actor('sa_amy', "INSERT INTO TemporalWriteContext VALUES (CONNECTION_ID(), USER(), 'Customer');", 'ERROR 1142')
        self.actor('sa_amy', "CALL sp_BeginTemporalEvent('Customer', JSON_OBJECT(), 'Insert', JSON_ARRAY(), NULL, NULL, @id, @time, @user, @context);", 'ERROR 1370')

    def test_unregistered_actor_with_accidental_business_grant_is_rejected(self):
        self.admin_sql("CREATE USER 'unknown_test'@'localhost' IDENTIFIED BY 'Unknown#2026'; "
                       f"GRANT INSERT ON `{self.database}`.Customer TO 'unknown_test'@'localhost';")
        self.actor('unknown_test', "SET @app_user_id = 1; INSERT INTO Customer (CustomerID, Name) VALUES (7001, 'Forged');", 'VSM_UNREGISTERED_SESSION')
        self.assertEqual(self.value('SELECT COUNT(*) FROM Customer WHERE CustomerID = 7001;'), '0')

    def test_maintenance_metadata_changes_have_system_attribution_not_a_forged_person(self):
        self.sql(f"USE `{self.database}`; SET @app_user_id = 1; SET @context_id = 'forged'; "
                 "INSERT INTO IndicatorValue VALUES ('history_category', 'X', 'System change', 1);")
        self.assertEqual(self.value("SELECT CONCAT(COALESCE(ResponsibleUserID, 'NULL'), ':', SessionAccount, ':', COALESCE(ContextID, 'NULL')) "
                                    "FROM TemporalEvent WHERE EntityType = 'IndicatorValue';"), 'NULL:vsm_developer@localhost:NULL')

    def test_reference_and_identity_policy_insert_update_delete_are_all_covered(self):
        self.sql(f"USE `{self.database}`; "
            "INSERT INTO IndicatorValue VALUES ('user_role', 'Dispatcher', 'Dispatcher', 40); "
            "UPDATE IndicatorValue SET Description = 'Dispatch team' WHERE IndicatorName = 'user_role' AND ValueCode = 'Dispatcher'; "
            "INSERT INTO UserRolePolicy (RoleType, RequiresTechnician) VALUES ('Dispatcher', 0); "
            "UPDATE UserRolePolicy SET RequiresTechnician = 1 WHERE RoleType = 'Dispatcher'; "
            "INSERT INTO RoleProcedurePermission (RoleType, ProcedureName) VALUES ('Dispatcher', 'sp_CreateServiceAppointment'); "
            "UPDATE RoleProcedurePermission SET ProcedureName = 'sp_CompleteRepair' WHERE RoleType = 'Dispatcher'; "
            "INSERT INTO DatabasePrincipal (SessionAccount, PrincipalType) VALUES ('history_service@localhost', 'Service'); "
            "UPDATE DatabasePrincipal SET SessionAccount = 'history_service_new@localhost' WHERE SessionAccount = 'history_service@localhost'; "
            "INSERT INTO PrincipalDelegation (SessionAccount, UserID, ProcedureName) VALUES ('history_service_new@localhost', 2, 'sp_CreateServiceAppointment'); "
            "UPDATE PrincipalDelegation SET UserID = 1 WHERE SessionAccount = 'history_service_new@localhost'; "
            "DELETE FROM PrincipalDelegation WHERE SessionAccount = 'history_service_new@localhost'; "
            "DELETE FROM DatabasePrincipal WHERE SessionAccount = 'history_service_new@localhost'; "
            "DELETE FROM RoleProcedurePermission WHERE RoleType = 'Dispatcher'; "
            "DELETE FROM UserRolePolicy WHERE RoleType = 'Dispatcher'; "
            "DELETE FROM IndicatorValue WHERE IndicatorName = 'user_role' AND ValueCode = 'Dispatcher';")
        for table in ('IndicatorValue', 'UserRolePolicy', 'RoleProcedurePermission', 'DatabasePrincipal', 'PrincipalDelegation'):
            with self.subTest(table=table):
                self.assertEqual(self.value(f"SELECT GROUP_CONCAT(DISTINCT OperationType ORDER BY OperationType) FROM TemporalEvent WHERE EntityType = '{table}';"), 'Delete,Insert,Update')
                self.assertEqual(self.value(f"SELECT COUNT(*) FROM `{table}History` WHERE HistoryOrigin <> 'Snapshot' AND HistoryUserID IS NOT NULL;"), '0')

    def test_master_data_prices_stock_roles_and_activation_are_recorded(self):
        self.actor('sa_amy', "UPDATE Customer SET Phone = '555' WHERE CustomerID = 1; UPDATE Vehicle SET Model = 'History model' WHERE VehicleID = 1;")
        self.actor('mgr_mike', "UPDATE Technician SET ActiveStatus = 1 WHERE TechnicianID = 3; "
                   "UPDATE Part SET UnitCost = UnitCost + 1, UnitSellingPrice = UnitSellingPrice + 2 WHERE PartID = 1; "
                   "SET @adj_reason = 'History cycle count'; UPDATE Part SET QuantityOnHand = QuantityOnHand + 1 WHERE PartID = 1;")
        self.sql(f"UPDATE `{self.database}`.UserAccount SET RoleType = 'Manager', TechnicianID = NULL WHERE UserID = 4;")
        for table in ('Customer', 'Vehicle', 'Technician', 'Part', 'UserAccount'):
            self.assertNotEqual(self.value(f"SELECT COUNT(*) FROM TemporalEvent WHERE EntityType = '{table}';"), '0')
        self.assertEqual(self.value("SELECT Reason FROM TemporalEvent WHERE EntityType = 'Part' ORDER BY EventID DESC LIMIT 1;"), 'History cycle count')
        self.assertEqual(json.loads(self.value("SELECT ChangedAttributes FROM TemporalEvent WHERE EntityType = 'Part' ORDER BY EventID LIMIT 1;")), ['UnitCost', 'UnitSellingPrice'])

    def test_delegated_completion_records_both_identities_and_shared_context(self):
        self.service()
        appointment = self.book('svc_test', '2')
        repair = self.open_repair(appointment)
        self.actor('tech_ben', f"UPDATE vw_MyRepairs SET Status = 'In Progress' WHERE RepairID = {repair};")
        self.actor('svc_test', f"CALL sp_CompleteRepair({repair}, 1, 3, '[{{\"partId\":1,\"qty\":1}}]');")
        self.assertEqual(self.value("SELECT CONCAT(COUNT(*), ':', COUNT(DISTINCT ContextID), ':', MIN(ResponsibleUserID)) "
            "FROM TemporalEvent WHERE SessionAccount = 'svc_test@localhost' AND EntityType IN ('Repair', 'Part', 'PartsUsage');"), '3:1:3')
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalWriteContext;'), '0')

    def test_late_procedure_failure_rolls_back_history_but_retains_existing_rejection_log(self):
        self.service()
        appointment = self.book()
        repair = self.open_repair(appointment)
        self.actor('tech_ben', f"UPDATE vw_MyRepairs SET Status = 'In Progress' WHERE RepairID = {repair};")
        before = self.value('SELECT COUNT(*) FROM TemporalEvent;')
        self.sql(f"USE `{self.database}`; CREATE TRIGGER test_RepairAfterFault AFTER UPDATE ON Repair "
                 "FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Injected late repair failure';")
        self.actor('svc_test', f"CALL sp_CompleteRepair({repair}, 1, 3, '[{{\"partId\":1,\"qty\":1}}]');", 'Injected late repair failure')
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalEvent;'), before)
        self.assertEqual(self.value("SELECT CONCAT(SessionAccount, ':', UserID) FROM AuditLog WHERE Action = 'Rejected' ORDER BY AuditLogID DESC LIMIT 1;"), 'svc_test@localhost:3')
        self.assertEqual(self.value('SELECT COUNT(*) FROM TemporalWriteContext;'), '0')

    def test_audit_view_payloads_filters_and_keyset_pages_match_the_event_directory(self):
        self.customer()
        self.actor('sa_amy', "UPDATE Customer SET Phone = 'first' WHERE CustomerID = 7001; UPDATE Customer SET Phone = 'second' WHERE CustomerID = 7001;")
        self.customer(7002)
        first = self.actor('mgr_mike', "CALL sp_ListAuditTrail('Customer', JSON_OBJECT('CustomerID', 7001), 2, '2000-01-01', '2100-01-01', NULL, 2);").splitlines()
        self.assertEqual(len(first), 2)
        ids = [int(row.split('\t')[0]) for row in first]
        self.assertEqual(ids, sorted(ids, reverse=True))
        second = self.actor('mgr_mike', f"CALL sp_ListAuditTrail('Customer', JSON_OBJECT('CustomerID', 7001), 2, NULL, NULL, {ids[-1]}, 2);").splitlines()
        self.assertEqual(len(second), 1)
        all_ids = ids + [int(second[0].split('\t')[0])]
        expected = self.value("SELECT EventID FROM TemporalEvent WHERE EntityType = 'Customer' AND RecordIdentifier = "
            "CAST(JSON_OBJECT('CustomerID', 7001) AS CHAR CHARACTER SET utf8mb4) ORDER BY EventID DESC;")
        self.assertEqual(all_ids, list(map(int, expected.splitlines())))
        payload = json.loads(self.value(f'SELECT JSON_ARRAY(PreviousValue, NewValue) FROM vw_AuditTrail WHERE EventID = {ids[0]};'))
        self.assertEqual([p['Phone'] for p in payload], ['first', 'second'])
        self.assertEqual(self.actor('mgr_mike', "CALL sp_ListAuditTrail('Customer', NULL, 3, NULL, NULL, NULL, 10);"), '')

    def test_audit_reader_rejects_invalid_filters_and_unauthorized_readers(self):
        self.actor('sa_amy', 'SELECT * FROM vw_AuditTrail;', 'ERROR 1142')
        self.actor('tech_ben', 'CALL sp_ListAuditTrail(NULL, NULL, NULL, NULL, NULL, NULL, 10);', 'ERROR 1370')
        for args in ("NULL, NULL, NULL, NULL, NULL, NULL, 201", "NULL, NULL, NULL, NULL, NULL, NULL, 0",
                     "NULL, NULL, NULL, '2030-01-02', '2030-01-01', NULL, 10"):
            self.actor('mgr_mike', f'CALL sp_ListAuditTrail({args});', 'VSM_INVALID_AUDIT_QUERY')
        self.actor('mgr_mike', "CALL sp_ListAuditTrail('Missing', NULL, NULL, NULL, NULL, NULL, 10);", 'VSM_INVALID_AUDIT_QUERY')

    def test_upgrade_from_version_four_preserves_all_business_and_generic_audit_rows(self):
        legacy = self.database + '_old'
        self.addCleanup(lambda: self.sql(f'DROP DATABASE IF EXISTS `{legacy}`;'))
        self.assert_success(self.build('--target-version', '4', database=legacy))
        # A role with a basic table grant in this schema is not automatically an
        # audit reader merely because it has the same name as the manager role.
        self.admin_sql(f"GRANT SELECT ON `{legacy}`.Customer TO 'role_manager';")
        probe = type(self)('runTest')
        probe.database = legacy
        before = probe.snapshot()
        result = self.build('--migrate', database=legacy)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, probe.snapshot())
        self.assertEqual(self.scalar(f'SELECT COUNT(*) FROM `{legacy}`.TemporalEvent;'), '0')
        denied = self.account_sql('mgr_mike', 'Manager#2026', f'USE `{legacy}`; CALL sp_ListAuditTrail(NULL, NULL, NULL, NULL, NULL, NULL, 10);', check=False)
        self.assertNotEqual(denied.returncode, 0)
        self.assertIn('ERROR 1370', denied.stderr)
        before_history = self.scalar(f'SELECT COUNT(*) FROM `{legacy}`.CustomerHistory;')
        result = self.build('--migrate', database=legacy)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before_history, self.scalar(f'SELECT COUNT(*) FROM `{legacy}`.CustomerHistory;'))

    def test_pagination_uses_indexed_event_keys_before_hydrating_version_payloads(self):
        self.sql(f"USE `{self.database}`; INSERT INTO Customer (CustomerID, Name) "
            "WITH RECURSIVE n AS (SELECT 7100 AS id UNION ALL SELECT id + 1 FROM n WHERE id < 7399) "
            "SELECT id, CONCAT('History scale ', id) FROM n;")
        plan = self.value("EXPLAIN FORMAT=JSON SELECT EventID FROM TemporalEvent "
                          "WHERE EntityType = 'Customer' AND EventID < 250 ORDER BY EventID DESC LIMIT 20;")
        def index_names(node):
            if isinstance(node, dict):
                for key, value in node.items():
                    if key in ('key', 'index_name'):
                        yield value
                    yield from index_names(value)
            elif isinstance(node, list):
                for value in node:
                    yield from index_names(value)
        self.assertTrue(set(index_names(json.loads(plan))) & {'PRIMARY', 'idx_TemporalEvent_Entity'}, plan)
        rows = self.actor('mgr_mike', 'CALL sp_ListAuditTrail(NULL, NULL, NULL, NULL, NULL, NULL, 20);').splitlines()
        self.assertEqual(len(rows), 20)
        self.assertEqual([int(row.split('\t')[0]) for row in rows], list(range(300, 280, -1)))
