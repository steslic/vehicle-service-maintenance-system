"""Reference, session identity, and provenance regressions on a private server."""

import os
import subprocess
import unittest

import mysql_test_support as support


class ReferenceIdentityTests(support.DisposableMySQLTestCase):
    def setUp(self):
        super().setUp()
        self.addCleanup(self.remove_demo_accounts)
        self.assert_success(self.build("--with-demo-accounts"))

    def remove_demo_accounts(self):
        self.admin_sql("DROP USER IF EXISTS 'sa_amy'@'localhost', 'tech_ben'@'localhost', 'mgr_mike'@'localhost', "
                 "'svc_test'@'localhost', 'unknown_test'@'localhost'; "
                 "DROP ROLE IF EXISTS 'role_service_advisor', 'role_technician', 'role_manager', 'role_test_service';")

    def actor(self, user, sql, error=None):
        password = {"sa_amy": "Advisor#2026", "tech_ben": "Tech#2026", "mgr_mike": "Manager#2026",
                    "svc_test": "Service#2026", "unknown_test": "Unknown#2026"}[user]
        env = os.environ.copy()
        env["MYSQL_PWD"] = password
        result = subprocess.run([self.mysql, "--no-defaults", "--protocol=SOCKET", f"--socket={self.socket}",
                                 f"--user={user}", f"--database={self.database}", "--batch", "--raw",
                                 "--skip-column-names", "--skip-force"], env=env, input=sql, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        if error:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn(error, result.stderr)
        else:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def service(self):
        self.admin_sql(f"""
            CREATE USER 'svc_test'@'localhost' IDENTIFIED BY 'Service#2026';
            CREATE ROLE 'role_test_service';
            GRANT EXECUTE ON PROCEDURE `{self.database}`.sp_CreateServiceAppointment TO 'role_test_service';
            GRANT EXECUTE ON PROCEDURE `{self.database}`.sp_CompleteRepair TO 'role_test_service';
            GRANT EXECUTE ON PROCEDURE `{self.database}`.sp_ListIndicatorValues TO 'role_test_service';
            GRANT 'role_test_service' TO 'svc_test'@'localhost';
            SET DEFAULT ROLE 'role_test_service' TO 'svc_test'@'localhost';
        """)
        self.sql(f"""
            INSERT INTO `{self.database}`.DatabasePrincipal (SessionAccount, PrincipalType, UserID)
            VALUES ('svc_test@localhost', 'Service', NULL);
            INSERT INTO `{self.database}`.PrincipalDelegation (SessionAccount, UserID, ProcedureName) VALUES
              ('svc_test@localhost', 2, 'sp_CreateServiceAppointment'),
              ('svc_test@localhost', 3, 'sp_CompleteRepair');
        """)

    def book(self, user="sa_amy", person="NULL", vehicle=5):
        return int(self.actor(user, f"CALL sp_CreateServiceAppointment(1, {vehicle}, 1, {person}, "
                                   "TIMESTAMP(CURDATE() + INTERVAL 120 DAY, '08:00:00'), 'Reference test', 60);"))

    def open_repair(self, appointment, repair_type="Oil Change"):
        self.actor("sa_amy", f"UPDATE ServiceAppointment SET Status = 'Checked In' WHERE AppointmentID = {appointment}; "
                   f"UPDATE ServiceAppointment SET Status = 'In Progress' WHERE AppointmentID = {appointment};")
        return int(self.actor("sa_amy", "INSERT INTO Repair (AppointmentID, RepairDateTime, RepairType, "
                             "RepairDescription, LaborHours, Status) VALUES "
                             f"({appointment}, NOW(), '{repair_type}', 'Valid repair', 0.5, 'Open'); SELECT LAST_INSERT_ID();"))

    def test_catalog_covers_existing_domains_and_ordered_dropdowns(self):
        domains = self.scalar(f"SELECT DISTINCT IndicatorName FROM `{self.database}`.IndicatorValue ORDER BY IndicatorName;")
        for domain in ("appointment_status", "repair_status", "estimate_status", "invoice_status", "repair_type",
                       "user_role", "active_status", "audit_action", "audit_entity", "principal_type", "procedure_name"):
            self.assertIn(domain, domains.splitlines())
        result = self.actor("sa_amy", "CALL sp_ListIndicatorValues('appointment_status');")
        self.assertEqual([line.split("\t")[1] for line in result.splitlines()],
                         ["Scheduled", "Checked In", "In Progress", "Completed", "Cancelled", "No Show"])
        self.actor("tech_ben", "CALL sp_ListIndicatorValues('missing_domain');", "Unknown indicator domain")

    def test_insert_adds_a_legal_repair_type_without_code_changes(self):
        before = self.actor("sa_amy", "CALL sp_ListIndicatorValues('repair_type');")
        self.assertNotIn("Wheel Alignment", before)
        self.sql(f"INSERT INTO `{self.database}`.IndicatorValue (IndicatorName, ValueCode, Description, DisplayOrder) "
                 "VALUES ('repair_type', 'Wheel Alignment', 'Wheel alignment and balancing', 25);")
        after = self.actor("sa_amy", "CALL sp_ListIndicatorValues('repair_type');")
        self.assertIn("repair_type\tWheel Alignment\tWheel alignment and balancing\t25", after)
        repair = int(self.actor("sa_amy", "INSERT INTO Repair (AppointmentID, RepairDateTime, RepairType, RepairDescription, Status) "
                                "VALUES (9, NOW(), 'Wheel Alignment', 'Alignment', 'Open'); SELECT LAST_INSERT_ID();"))
        self.assertEqual(self.scalar(f"SELECT RepairTypeDescription FROM `{self.database}`.vw_RepairReferenceLabels "
                                     f"WHERE RepairID = {repair};"), "Wheel alignment and balancing")

    def test_unknown_and_wrong_domain_codes_are_rejected(self):
        for status, repair_type, domain in (("Draft", "Oil Change", "repair_status"),
                                           ("Open", "Finalized", "repair_type"),
                                           ("Open", "Unknown repair", "repair_type")):
            with self.subTest(domain=domain, code=repair_type, status=status):
                self.actor("sa_amy", "INSERT INTO Repair (AppointmentID, RepairDateTime, RepairType, RepairDescription, Status) "
                           f"VALUES (9, NOW(), '{repair_type}', 'Rejected', '{status}');", "Invalid indicator value for " + domain)
        self.actor("mgr_mike", "UPDATE Part SET ActiveStatus = 2 WHERE PartID = 1;", "active_status")
        self.actor("mgr_mike", "SET foreign_key_checks = 0; UPDATE Part SET ActiveStatus = 2 WHERE PartID = 1;", "active_status")

    def test_referenced_codes_cannot_be_removed_and_invalid_labels_are_visible(self):
        result = self.sql(f"DELETE FROM `{self.database}`.IndicatorValue WHERE IndicatorName = 'repair_status' AND ValueCode = 'Open';", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.scalar(f"SELECT `{self.database}`.fn_IndicatorDescription('repair_type', 'Missing');"), "[INVALID: Missing]")

    def test_new_status_membership_does_not_create_a_workflow_edge(self):
        self.sql(f"INSERT INTO `{self.database}`.IndicatorValue VALUES ('invoice_status', 'Paid', 'Paid', 3);")
        self.actor("sa_amy", "UPDATE Invoice SET Status = 'Paid' WHERE InvoiceID = 3;", "Invalid invoice status transition")
        self.assertEqual(self.scalar(f"SELECT Status FROM `{self.database}`.Invoice WHERE InvoiceID = 3;"), "Draft")

    def test_named_user_is_derived_and_system_person_are_recorded(self):
        appointment = self.book()
        self.assertEqual(self.scalar(f"SELECT CreatedByUserID FROM `{self.database}`.ServiceAppointment WHERE AppointmentID = {appointment};"), "2")
        self.assertEqual(self.scalar(f"SELECT CONCAT(UserID, ':', SessionAccount) FROM `{self.database}`.AuditLog "
                                     f"WHERE AffectedEntity = 'ServiceAppointment' AND AffectedRecordID = {appointment};"), "2:sa_amy@localhost")
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.OperationContext;"), "0")

    def test_forged_person_is_rejected_and_real_session_is_audited(self):
        self.actor("sa_amy", "CALL sp_CreateServiceAppointment(1, 5, 1, 1, CURDATE() + INTERVAL 130 DAY, 'Forged', 60);",
                   "Acting user must be the logged-in user")
        self.assertEqual(self.scalar(f"SELECT CONCAT(UserID, ':', SessionAccount) FROM `{self.database}`.AuditLog "
                                     "WHERE Action = 'Rejected' ORDER BY AuditLogID DESC LIMIT 1;"), "2:sa_amy@localhost")
        self.actor("sa_amy", "SET @app_user_id = 1; UPDATE RepairEstimate SET Status = 'Approved', ApprovedByUserID = 1 WHERE EstimateID = 3;",
                   "Acting user must be the logged-in user")

    def test_unmapped_login_and_invalid_responsible_actor_fail_closed(self):
        self.admin_sql(f"CREATE USER 'unknown_test'@'localhost' IDENTIFIED BY 'Unknown#2026'; "
                 f"GRANT EXECUTE ON PROCEDURE `{self.database}`.sp_CreateServiceAppointment TO 'unknown_test'@'localhost';")
        self.actor("unknown_test", "SET @app_user_id = 1; CALL sp_CreateServiceAppointment(1, 5, 1, 2, CURDATE() + INTERVAL 130 DAY, 'Unknown', 60);",
                   "not a registered principal")
        self.assertEqual(self.scalar(f"SELECT CONCAT(COALESCE(UserID, 'NULL'), ':', SessionAccount) FROM `{self.database}`.AuditLog "
                                     "WHERE Action = 'Rejected' ORDER BY AuditLogID DESC LIMIT 1;"), "NULL:unknown_test@localhost")
        self.actor("sa_amy", "CALL sp_CreateServiceAppointment(1, 5, 1, 99999, CURDATE() + INTERVAL 130 DAY, 'Unknown actor', 60);",
                   "Acting user must be the logged-in user")

    def test_host_mapping_and_active_native_roles_are_enforced(self):
        self.actor("sa_amy", "SET ROLE NONE; CALL sp_CreateServiceAppointment(1, 5, 1, 2, CURDATE() + INTERVAL 130 DAY, 'No role', 60);", "ERROR 1370")
        self.sql(f"UPDATE `{self.database}`.DatabasePrincipal SET SessionAccount = 'tech_ben@elsewhere' WHERE UserID = 3;")
        self.assertEqual(self.actor("tech_ben", "SELECT COUNT(*) FROM vw_MyRepairs;"), "0")
        self.actor("tech_ben", "CALL sp_CompleteRepair(9, 1, 3, NULL);", "not a registered principal")

    def test_service_delegation_is_scoped_and_cannot_escalate_person_permissions(self):
        self.service()
        appointment = self.book("svc_test", "2")
        self.assertEqual(self.scalar(f"SELECT CONCAT(UserID, ':', SessionAccount) FROM `{self.database}`.AuditLog "
                                     f"WHERE AffectedEntity = 'ServiceAppointment' AND AffectedRecordID = {appointment};"), "2:svc_test@localhost")
        self.actor("svc_test", "CALL sp_CreateServiceAppointment(1, 5, 1, 1, CURDATE() + INTERVAL 130 DAY, 'Denied', 60);", "not authorized to act")
        self.actor("svc_test", "CALL sp_CreateServiceAppointment(1, 5, 1, NULL, CURDATE() + INTERVAL 130 DAY, 'Missing person', 60);", "not authorized to act")
        self.sql(f"INSERT INTO `{self.database}`.PrincipalDelegation (SessionAccount, UserID, ProcedureName) "
                 "VALUES ('svc_test@localhost', 3, 'sp_CreateServiceAppointment');")
        self.actor("svc_test", "CALL sp_CreateServiceAppointment(1, 5, 1, 3, CURDATE() + INTERVAL 130 DAY, 'Role escalation', 60);", "not entitled")

    def test_service_context_cannot_be_forged_with_variables_or_direct_writes(self):
        self.service()
        self.actor("svc_test", "SET @app_user_id = 1; UPDATE Part SET UnitCost = 0 WHERE PartID = 1;", "ERROR 1142")
        self.actor("svc_test", "INSERT INTO OperationContext (ConnectionID, SessionAccount, UserID, ProcedureName, ContextID) "
                   "VALUES (CONNECTION_ID(), USER(), 1, 'sp_CompleteRepair', UUID());", "ERROR 1142")
        self.actor("svc_test", "CALL sp_ResolveActor(1, 'sp_CompleteRepair', @u);", "ERROR 1370")
        # Even an accidental direct grant cannot give a service an operation context.
        self.admin_sql(f"GRANT UPDATE ON `{self.database}`.ServiceAppointment TO 'svc_test'@'localhost'; "
                 f"GRANT SELECT ON `{self.database}`.ServiceAppointment TO 'svc_test'@'localhost';")
        self.actor("svc_test", "SET @app_user_id = 2; UPDATE ServiceAppointment SET EstimatedDuration = 61 WHERE AppointmentID = 9;", "not authorized to act")

    def test_delegated_repair_completion_keeps_stock_and_all_audit_attribution(self):
        self.service()
        appointment = self.book("svc_test", "2")
        repair = self.open_repair(appointment)
        self.actor("tech_ben", f"UPDATE vw_MyRepairs SET Status = 'In Progress' WHERE RepairID = {repair};")
        stock = int(self.scalar(f"SELECT QuantityOnHand FROM `{self.database}`.Part WHERE PartID = 1;"))
        boundary = self.scalar(f"SELECT MAX(AuditLogID) FROM `{self.database}`.AuditLog;")
        self.actor("svc_test", f"CALL sp_CompleteRepair({repair}, 1, 3, '[{{\"partId\":1,\"qty\":1}}]');")
        self.assertEqual(self.scalar(f"SELECT QuantityOnHand FROM `{self.database}`.Part WHERE PartID = 1;"), str(stock - 1))
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.AuditLog WHERE AuditLogID > {boundary} "
                                     "AND UserID = 3 AND SessionAccount = 'svc_test@localhost' AND ContextID IS NOT NULL;"), "3")
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.OperationContext;"), "0")
        self.actor("sa_amy", f"UPDATE ServiceAppointment SET Status = 'Completed' WHERE AppointmentID = {appointment};")

    def test_rejected_service_request_has_correct_attribution_and_leaves_no_context(self):
        self.service()
        self.actor("svc_test", "CALL sp_CompleteRepair(99999, 1, 3, NULL);", "Repair does not exist")
        self.assertEqual(self.scalar(f"SELECT CONCAT(UserID, ':', SessionAccount) FROM `{self.database}`.AuditLog "
                                     "WHERE Action = 'Rejected' ORDER BY AuditLogID DESC LIMIT 1;"), "3:svc_test@localhost")
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.OperationContext;"), "0")

    def test_role_technician_links_and_required_text_are_validated(self):
        for role, tech in (("Technician", "NULL"), ("Manager", "1")):
            with self.subTest(role=role):
                result = self.sql(f"INSERT INTO `{self.database}`.UserAccount (Username, Name, RoleType, TechnicianID) "
                                  f"VALUES ('invalid_profile', 'Invalid', '{role}', {tech});", check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("profile do not match", result.stderr)
        for statement in ("INSERT INTO Customer (Name) VALUES ('   ');", "UPDATE Vehicle SET Make = '' WHERE VehicleID = 1;"):
            self.actor("sa_amy", statement, "cannot be blank")
        self.sql(f"UPDATE `{self.database}`.Technician SET ActiveStatus = 0 WHERE TechnicianID = 1;")
        self.actor("tech_ben", "CALL sp_CompleteRepair(9, 1, 3, NULL);", "invalid or inactive")

    def test_creators_and_premature_completion_metadata_cannot_be_forged(self):
        self.actor("sa_amy", "INSERT INTO Invoice (AppointmentID, CreatedByUserID, InvoiceDate, Status, TotalAmount) "
                   "VALUES (9, 1, CURDATE(), 'Draft', 0);", "Creating user must match")
        self.actor("sa_amy", "INSERT INTO Repair (AppointmentID, RepairDateTime, RepairType, RepairDescription, Status, "
                   "CompletedByTechnicianID, CompletionDateTime) VALUES (9, NOW(), 'Diagnostic', 'Forged', 'Open', 1, NOW());", "cannot contain completion metadata")
        self.actor("mgr_mike", "UPDATE Repair SET CompletedByTechnicianID = 1, CompletionDateTime = NOW() WHERE RepairID = 9;", "only be set by completion")
        self.actor("sa_amy", "UPDATE ServiceAppointment SET CreationTimestamp = '1900-01-01' WHERE AppointmentID = 9;", "Creation timestamp cannot be changed")

    def test_draft_decision_metadata_is_rejected_and_event_clocks_are_database_owned(self):
        self.actor("sa_amy", "INSERT INTO RepairEstimate (AppointmentID, CreatedByUserID, EstimateDate, Status, TotalAmount, ApprovedByUserID) "
                   "VALUES (9, 2, CURDATE(), 'Draft', 0, 1);", "Draft estimates cannot contain approval metadata")
        self.actor("sa_amy", "UPDATE Invoice SET FinalizedByUserID = 1, FinalizationDateTime = '1900-01-01' WHERE InvoiceID = 3;", "only be set by finalization")
        self.actor("mgr_mike", "UPDATE RepairEstimate SET Status = 'Approved', ApprovalDateTime = '1900-01-01' WHERE EstimateID = 3;")
        self.assertEqual(self.scalar(f"SELECT ABS(TIMESTAMPDIFF(SECOND, ApprovalDateTime, UTC_TIMESTAMP())) < 10 FROM `{self.database}`.RepairEstimate WHERE EstimateID = 3;"), "1")
        # The existing baseline suite deliberately edits a draft line's price.
        self.actor("sa_amy", "UPDATE Invoice SET TotalAmount = (SELECT SUM(LineTotal) FROM InvoiceLineItem WHERE InvoiceID = 3) WHERE InvoiceID = 3;")
        self.actor("sa_amy", "UPDATE Invoice SET Status = 'Finalized', FinalizationDateTime = '1900-01-01' WHERE InvoiceID = 3;")
        self.assertEqual(self.scalar(f"SELECT ABS(TIMESTAMPDIFF(SECOND, FinalizationDateTime, UTC_TIMESTAMP())) < 10 FROM `{self.database}`.Invoice WHERE InvoiceID = 3;"), "1")

    def test_upgrade_preserves_legacy_rows_and_old_migrations_are_immutable(self):
        # A separate database at the previous version, on this same private server.
        legacy = self.database + "_old"
        self.addCleanup(lambda: self.sql(f"DROP DATABASE IF EXISTS `{legacy}`;"))
        self.assert_success(self.build("--target-version", "2", database=legacy))
        probe = type(self)("runTest")
        probe.database = legacy
        before = probe.snapshot()
        self.assertEqual(self.build("--migrate", database=legacy).returncode, 0)
        self.assertEqual(probe.snapshot(), before)
        versions = "SELECT object_type, object_name, definition_checksum FROM `{}`.schema_object_versions ORDER BY object_type, object_name;"
        self.assertEqual(self.scalar(versions.format(legacy)), self.scalar(versions.format(self.database)))
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{legacy}`.AuditLog WHERE SessionAccount IS NOT NULL;"), "0")
        self.assertEqual(self.scalar(f"SELECT GROUP_CONCAT(version ORDER BY version) FROM `{legacy}`.schema_migrations;"),
                         ','.join(str(v) for v in range(1, support.LATEST_VERSION + 1)))

    def test_role_policy_cannot_invalidate_referenced_profiles(self):
        result = self.sql(f"UPDATE `{self.database}`.UserRolePolicy SET RequiresTechnician = 0 WHERE RoleType = 'Technician';", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalidate existing user profiles", result.stderr)
        result = self.sql(f"DELETE FROM `{self.database}`.UserRolePolicy WHERE RoleType = 'Technician';", check=False)
        self.assertNotEqual(result.returncode, 0)

    def test_previously_unconstrained_legacy_codes_are_preserved(self):
        legacy = self.database + "_legacy"
        self.addCleanup(lambda: self.sql(f"DROP DATABASE IF EXISTS `{legacy}`;"))
        self.assert_success(self.build("--target-version", "2", database=legacy))
        self.sql(f"USE `{legacy}`; SET @app_user_id = 2; "
                 "INSERT INTO Repair (AppointmentID, RepairDateTime, RepairType, RepairDescription, Status) "
                 "VALUES (9, NOW(), 'Legacy Special', 'Existing custom category', 'Open'); "
                 "INSERT INTO AuditLog (UserID, `Timestamp`, Action, AffectedEntity) "
                 "VALUES (1, NOW(), 'Legacy Import', 'Customer');")
        probe = type(self)("runTest")
        probe.database = legacy
        before = probe.snapshot()
        result = self.build("--migrate", database=legacy)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(probe.snapshot(), before)
        self.assertEqual(self.scalar(f"SELECT ValueCode FROM `{legacy}`.IndicatorValue "
                                     "WHERE IndicatorName = 'repair_type' AND ValueCode = 'Legacy Special';"), "Legacy Special")
        self.assertEqual(self.scalar(f"SELECT ValueCode FROM `{legacy}`.IndicatorValue "
                                     "WHERE IndicatorName = 'audit_action' AND ValueCode = 'Legacy Import';"), "Legacy Import")

    def test_late_repair_failure_rolls_back_context_stock_and_success_audits(self):
        self.service()
        appointment = self.book()
        repair = self.open_repair(appointment)
        self.actor("tech_ben", f"UPDATE vw_MyRepairs SET Status = 'In Progress' WHERE RepairID = {repair};")
        before = self.snapshot()
        # This fault is installed only in the private test database, after parts
        # writes but before the completion update can commit.
        self.sql(f"USE `{self.database}`;\nDELIMITER //\n"
                 f"CREATE TRIGGER test_CompletionFault BEFORE UPDATE ON Repair FOR EACH ROW "
                 "BEGIN IF NEW.Status = 'Completed' THEN SIGNAL SQLSTATE '45000' "
                 "SET MESSAGE_TEXT = 'Injected final-step failure'; END IF; END //\nDELIMITER ;\n")
        self.actor("svc_test", f"CALL sp_CompleteRepair({repair}, 1, 3, '[{{\"partId\":1,\"qty\":1}}]');", "Injected final-step failure")
        after = self.snapshot()
        self.assertEqual([row for row in after if row[0].lower() != 'auditlog'],
                         [row for row in before if row[0].lower() != 'auditlog'])
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.OperationContext;"), "0")
        self.assertEqual(self.scalar(f"SELECT CONCAT(UserID, ':', SessionAccount) FROM `{self.database}`.AuditLog "
                                     "WHERE Action = 'Rejected' ORDER BY AuditLogID DESC LIMIT 1;"), "3:svc_test@localhost")

    def test_manager_override_preserves_assignment_and_database_clock(self):
        appointment = self.book()
        repair = self.open_repair(appointment)
        self.actor("tech_ben", f"UPDATE vw_MyRepairs SET Status = 'In Progress' WHERE RepairID = {repair};")
        self.actor("mgr_mike", f"UPDATE Repair SET Status = 'Completed', CompletedByTechnicianID = 2 WHERE RepairID = {repair};", "must be assigned")
        self.actor("mgr_mike", f"UPDATE Repair SET Status = 'Completed', CompletedByTechnicianID = 1, "
                   f"CompletionDateTime = '1900-01-01' WHERE RepairID = {repair};")
        self.assertEqual(self.scalar(f"SELECT CompletedByTechnicianID = 1 AND ABS(TIMESTAMPDIFF(SECOND, CompletionDateTime, UTC_TIMESTAMP())) < 10 "
                                     f"FROM `{self.database}`.Repair WHERE RepairID = {repair};"), "1")
        self.assertEqual(self.scalar(f"SELECT CONCAT(UserID, ':', SessionAccount) FROM `{self.database}`.AuditLog "
                                     f"WHERE AffectedEntity = 'Repair' AND AffectedRecordID = {repair} ORDER BY AuditLogID DESC LIMIT 1;"), "1:mgr_mike@localhost")

    def test_caller_timestamp_and_time_zone_cannot_forge_event_or_audit_times(self):
        self.actor("mgr_mike", "SET time_zone = '+12:00'; SET timestamp = 946684800; "
                   "UPDATE RepairEstimate SET Status = 'Approved', ApprovalDateTime = '1900-01-01' WHERE EstimateID = 3;")
        self.assertEqual(self.scalar(f"SELECT ABS(TIMESTAMPDIFF(SECOND, ApprovalDateTime, UTC_TIMESTAMP())) < 10 "
                                     f"FROM `{self.database}`.RepairEstimate WHERE EstimateID = 3;"), "1")
        self.assertEqual(self.scalar(f"SELECT ABS(TIMESTAMPDIFF(SECOND, `Timestamp`, UTC_TIMESTAMP())) < 10 "
                                     f"FROM `{self.database}`.AuditLog WHERE SessionAccount = 'mgr_mike@localhost' "
                                     "ORDER BY AuditLogID DESC LIMIT 1;"), "1")
