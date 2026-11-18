"""Build and migration tests. Always start a private, disposable MySQL server.

Run: python3 -B -m unittest discover -s tests -v
MYSQL_BIN and MYSQLD_BIN may select executables, never an existing server.
"""

import os
import shutil
import subprocess
import time
import unittest
import uuid


import mysql_test_support as support

ROOT = support.ROOT
LATEST_VERSION = support.LATEST_VERSION
NEXT_VERSION = support.NEXT_VERSION


class SafeBuildTests(support.DisposableMySQLTestCase):
    def test_existing_database_preserves_business_and_audit_rows(self):
        self.assert_success(self.build())
        self.sql(f"INSERT INTO `{self.database}`.Customer (CustomerID, Name) VALUES (9999, 'Keep me');")
        before = self.snapshot()
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing existing database", result.stderr)
        self.assertEqual(self.snapshot(), before)


    def test_explicit_development_reset_rebuilds_disposable_database(self):
        self.assert_success(self.build())
        self.sql(f"INSERT INTO `{self.database}`.Customer (CustomerID, Name) VALUES (9999, 'Reset me');")
        self.sql(f"INSERT INTO `{self.database}`.AuditLog (UserID, `Timestamp`, Action, AffectedEntity, NewValue) "
                 "VALUES (1, NOW(), 'Create', 'Customer', JSON_OBJECT('ResetMarker', TRUE));")
        self.assert_success(self.build("--dev-reset"))
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.Customer WHERE CustomerID = 9999;"), "0")
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.AuditLog "
                                     "WHERE JSON_EXTRACT(NewValue, '$.ResetMarker') = TRUE;"), "0")
        self.assertGreater(int(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.AuditLog;")), 0)


    def test_reset_rejects_non_development_database(self):
        protected = "vsm_keep_" + uuid.uuid4().hex[:12]
        self.addCleanup(lambda: self.sql(f"DROP DATABASE `{protected}`;"))
        self.sql(f"CREATE DATABASE `{protected}`; CREATE TABLE `{protected}`.Sentinel (ID INT); "
                 f"INSERT INTO `{protected}`.Sentinel VALUES (42);")
        result = self.build("--dev-reset", database=protected)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("development-only", result.stderr)
        self.assertEqual(self.scalar(f"SELECT ID FROM `{protected}`.Sentinel;"), "42")


    def test_failed_assertion_fails_build_and_stops_following_sql(self):
        path = self.fixture / "sql" / "07_tests.sql"
        text = path.read_text()
        self.assertIn("@c = 3,", text)
        path.write_text(text.replace("@c = 3,", "@c = -1,", 1)
                        + "\nCREATE TABLE ShouldNotRun (ID INT);\n")
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL", result.stdout)
        self.assertIn("Test suite failed", result.stderr)
        self.assertNotIn("Build succeeded:", result.stdout)
        log = next((self.fixture / "logs").glob("*-build.log")).read_text()
        self.assertIn("Test suite failed", log)
        self.assertIn("FINAL STATUS: FAILED", log)
        self.assertIn("WORKTREE DIRTY: true", log)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM information_schema.TABLES "
                                    f"WHERE TABLE_SCHEMA = '{self.database}' AND TABLE_NAME = 'ShouldNotRun';"), "0")


    def test_sql_error_stops_current_file_and_later_files(self):
        path = self.fixture / "sql" / "02_indexes.sql"
        path.write_text(path.read_text() + "\nTHIS IS INVALID SQL;\nCREATE TABLE ShouldNotRun (ID INT);\n")
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ERROR 1064", result.stderr)
        self.assertNotIn("Build succeeded:", result.stdout)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM information_schema.TABLES "
                                    f"WHERE TABLE_SCHEMA = '{self.database}' AND TABLE_NAME = 'ShouldNotRun';"), "0")
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM information_schema.VIEWS "
                                    f"WHERE TABLE_SCHEMA = '{self.database}';"), "0")
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.Customer;"), "0")


    def test_missing_file_refuses_before_even_an_explicit_reset(self):
        self.sql(f"CREATE DATABASE `{self.database}`; CREATE TABLE `{self.database}`.Sentinel (ID INT); "
                 f"INSERT INTO `{self.database}`.Sentinel VALUES (42);")
        (self.fixture / "sql" / "06_sample_data.sql").unlink()
        result = self.build("--dev-reset")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("06_sample_data.sql", result.stderr)
        self.assertEqual(self.scalar(f"SELECT ID FROM `{self.database}`.Sentinel;"), "42")


    def test_legacy_source_entry_point_refuses_before_any_ddl(self):
        result = self.sql((self.fixture / "sql" / "build.sql").read_text(), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("direct SOURCE builds are disabled", result.stderr)
        self.assertFalse(self.database_exists("vehicle_service_maintenance"))


    def test_schema_create_guard_preserves_an_existing_database(self):
        self.sql(f"CREATE DATABASE `{self.database}`; CREATE TABLE `{self.database}`.Sentinel (ID INT); "
                 f"INSERT INTO `{self.database}`.Sentinel VALUES (42);")
        schema = (self.fixture / "sql" / "01_schema.sql").read_text()
        result = self.sql(schema.replace("vehicle_service_maintenance", self.database), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ERROR 1007", result.stderr)
        self.assertEqual(self.scalar(f"SELECT ID FROM `{self.database}`.Sentinel;"), "42")
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM information_schema.TABLES "
                                    f"WHERE TABLE_SCHEMA = '{self.database}';"), "1")


    def test_demo_principals_are_untouched_and_opt_in_refuses_collisions(self):
        self.sql("CREATE ROLE 'role_service_advisor'; "
                 "CREATE USER 'sa_amy'@'localhost' IDENTIFIED BY 'Unrelated-test-only';")
        self.addCleanup(lambda: self.sql("DROP USER 'sa_amy'@'localhost'; DROP ROLE 'role_service_advisor';"))
        before = self.scalar("SHOW GRANTS FOR 'role_service_advisor'; SHOW GRANTS FOR 'sa_amy'@'localhost'; "
                             "SELECT authentication_string FROM mysql.user WHERE User = 'sa_amy';")
        normal = self.build()
        self.assert_success(normal)
        self.assertIn("SKIP", normal.stdout)
        data_before = self.snapshot()
        result = self.build("--dev-reset", "--with-demo-accounts")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("existing users/roles would collide", result.stderr)
        after = self.scalar("SHOW GRANTS FOR 'role_service_advisor'; SHOW GRANTS FOR 'sa_amy'@'localhost'; "
                            "SELECT authentication_string FROM mysql.user WHERE User = 'sa_amy';")
        self.assertEqual(after, before)
        self.assertEqual(self.snapshot(), data_before)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM mysql.user WHERE User IN "
                                    "('role_technician', 'role_manager', 'tech_ben', 'mgr_mike');"), "0")


    def test_full_existing_suite_with_optional_demo_provisioning(self):
        self.addCleanup(lambda: self.sql("DROP USER IF EXISTS 'sa_amy'@'localhost', 'tech_ben'@'localhost', 'mgr_mike'@'localhost'; "
                                        "DROP ROLE IF EXISTS 'role_service_advisor', 'role_technician', 'role_manager';"))
        result = self.build("--with-demo-accounts")
        self.assert_success(result)
        self.assertIn("PASS\t66\n", result.stdout)
        self.assertNotIn("\tFAIL\t", result.stdout)
        self.assertNotIn("\tSKIP\t", result.stdout)
        # Also execute the existing manual T-11 permission cases using real logins.
        cases = [
            ("tech_ben", "Tech#2026", "SELECT COUNT(*) FROM Part;", None),
            ("tech_ben", "Tech#2026", "UPDATE Customer SET Name = 'Denied' WHERE CustomerID = 1;", "ERROR 1142"),
            ("tech_ben", "Tech#2026", "SELECT * FROM Invoice;", "ERROR 1142"),
            ("sa_amy", "Advisor#2026", "SELECT COUNT(*) FROM Customer;", None),
            ("sa_amy", "Advisor#2026", "CALL sp_CompleteRepair(6, 1, 2, NULL);", "ERROR 1370"),
            ("sa_amy", "Advisor#2026", "SELECT * FROM AuditLog;", "ERROR 1142"),
        ]
        for user, password, statement, error in cases:
            with self.subTest(user=user, statement=statement):
                env = os.environ.copy()
                env["MYSQL_PWD"] = password
                check = subprocess.run([self.mysql, "--no-defaults", "--protocol=SOCKET",
                                        f"--socket={self.socket}", f"--user={user}",
                                        f"--database={self.database}", "--batch", "--skip-force"],
                                       env=env, input=statement, text=True,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
                if error:
                    self.assertNotEqual(check.returncode, 0)
                    self.assertIn(error, check.stderr)
                else:
                    self.assertEqual(check.returncode, 0, check.stderr)


    def test_clean_clone_build_from_another_directory_has_revision_and_test_log(self):
        clone = self.server_dir / ("clone_" + uuid.uuid4().hex[:8])
        subprocess.run(["git", "clone", "--quiet", str(self.fixture), str(clone)], check=True)
        self.addCleanup(lambda: shutil.rmtree(clone))
        result = self.build(root=clone, cwd=self.server_dir)
        self.assert_success(result)
        sha = subprocess.check_output(["git", "-C", str(clone), "rev-parse", "HEAD"], text=True).strip()
        logs = list((clone / "logs").glob("*-build.log"))
        self.assertEqual(len(logs), 1)
        log = logs[0].read_text()
        for expected in ("SOURCE COMMIT: " + sha, "WORKTREE DIRTY: false", "MYSQL CLIENT:",
                         "MYSQL SERVER AND SETTINGS:", "PREFLIGHT: PASS", "OPERATION 01_schema.sql",
                         "OPERATION 07_tests.sql", "PASS\t65", "SKIP\t1", f"SCHEMA VERSION: {LATEST_VERSION}",
                         "MIGRATION 002: APPLIED", "FINAL STATUS: SUCCESS"):
            self.assertIn(expected, log)
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.schema_migrations "
                                     f"WHERE status = 'applied' AND source_commit_sha = '{sha}' AND source_dirty = 0;"), str(LATEST_VERSION))


    def test_migration_preserves_records_and_versions_changed_objects(self):
        self.assert_success(self.build("--target-version", "1"))
        self.sql(f"INSERT INTO `{self.database}`.Customer (CustomerID, Name) VALUES (9999, 'Keep through upgrade');")
        before = self.snapshot()
        result = self.build("--migrate")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM information_schema.STATISTICS "
                                     f"WHERE TABLE_SCHEMA = '{self.database}' AND INDEX_NAME = 'idx_Customer_Name';"), "1")
        self.assertEqual(self.scalar(f"SELECT migration_version FROM `{self.database}`.schema_object_versions "
                                     "WHERE object_type = 'TABLE' AND object_name = 'customer';"), "2")
        self.assertEqual(self.scalar(f"SELECT migration_version FROM `{self.database}`.schema_object_versions "
                                     "WHERE object_type = 'PROCEDURE' AND object_name = 'sp_completerepair';"), str(LATEST_VERSION))


    def test_migrating_twice_is_a_noop(self):
        self.assert_success(self.build("--target-version", "1"))
        self.assertEqual(self.build("--migrate").returncode, 0)
        before = self.migration_history()
        rows = self.snapshot()
        result = self.build("--migrate")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.migration_history(), before)
        self.assertEqual(self.snapshot(), rows)
        self.assertNotIn("OPERATION migration", result.stdout)


    def test_modified_applied_migration_is_rejected(self):
        self.assert_success(self.build())
        before = self.migration_history()
        path = self.fixture / "sql" / "migrations" / "002_customer_name_index.sql"
        path.write_text(path.read_text() + "\n-- Edited after deployment\n")
        result = self.build("--migrate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum/filename mismatch", result.stderr)
        self.assertEqual(self.migration_history(), before)


    def test_out_of_order_files_are_rejected(self):
        self.assert_success(self.build())
        before = self.snapshot()
        self.add_migration(f"{NEXT_VERSION + 1:03d}_skipped_version.sql", "CREATE TABLE ShouldNotRun (ID INT);\n")
        result = self.build("--migrate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Out-of-order", result.stderr)
        self.assertEqual(self.snapshot(), before)


    def test_unlisted_migration_is_rejected(self):
        self.assert_success(self.build())
        self.add_migration(f"{NEXT_VERSION:03d}_unlisted.sql", "CREATE TABLE ShouldNotRun (ID INT);\n", listed=False)
        result = self.build("--migrate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unlisted migration", result.stderr)


    def test_out_of_order_history_is_rejected(self):
        self.assert_success(self.build())
        self.sql(f"DELETE FROM `{self.database}`.schema_object_versions WHERE migration_version = 1; "
                 f"DELETE FROM `{self.database}`.schema_migrations WHERE version = 1;")
        result = self.build("--migrate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Out-of-order migration history", result.stderr)


    def test_verified_baseline_adoption_preserves_existing_rows(self):
        self.assert_success(self.build("--target-version", "1"))
        self.remove_version_metadata()  # Simulate the pre-versioning schema.
        before = self.snapshot()
        rejected = self.build("--migrate")
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn("Unversioned database", rejected.stderr)
        result = self.build("--migrate", "--baseline")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("BASELINE SCHEMA VERIFICATION: PASS", result.stdout)
        self.assertEqual(self.snapshot(), before)


    def test_baseline_rejects_schema_drift_without_creating_history(self):
        self.assert_success(self.build("--target-version", "1"))
        self.remove_version_metadata()
        self.sql(f"ALTER TABLE `{self.database}`.Customer ADD COLUMN Unexpected INT NULL;")
        before = self.snapshot()
        result = self.build("--migrate", "--baseline")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Baseline schema mismatch: TABLE:customer", result.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM information_schema.TABLES "
                                     f"WHERE TABLE_SCHEMA = '{self.database}' AND TABLE_NAME = 'schema_migrations';"), "0")


    def test_deployed_routine_drift_is_rejected(self):
        self.assert_success(self.build())
        self.sql(f"DROP PROCEDURE `{self.database}`.sp_CompleteRepair;")
        result = self.build("--migrate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Deployed object schema mismatch", result.stderr)
        self.assertIn("PROCEDURE:sp_completerepair", result.stderr)


    def test_failed_ddl_migration_is_recorded_and_never_retried(self):
        self.assert_success(self.build())
        before = self.snapshot()
        self.add_migration(f"{NEXT_VERSION:03d}_partial_failure.sql", "CREATE INDEX idx_Partial ON Customer (Phone);\nINVALID SQL;\n")
        result = self.build("--migrate")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.scalar(f"SELECT status FROM `{self.database}`.schema_migrations WHERE version = {NEXT_VERSION};"), "failed")
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM information_schema.STATISTICS "
                                     f"WHERE TABLE_SCHEMA = '{self.database}' AND INDEX_NAME = 'idx_Partial';"), "1")
        again = self.build("--migrate")
        self.assertNotEqual(again.returncode, 0)
        self.assertIn(f"Incomplete migration {NEXT_VERSION} (failed): no retry", again.stderr)
        self.assertEqual(self.snapshot(), before)


    def test_killed_runner_leaves_durable_interrupted_migration(self):
        self.assert_success(self.build())
        before = self.snapshot()
        self.add_migration(f"{NEXT_VERSION:03d}_interruption.sql", "CREATE INDEX idx_Interrupted ON Customer (Phone);\nSELECT SLEEP(15);\n")
        process = subprocess.Popen(self.build_command("--migrate"), text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        connection = None
        try:
            for _ in range(100):
                connection = self.scalar("SELECT ID FROM information_schema.PROCESSLIST "
                                         f"WHERE DB = '{self.database}' AND INFO LIKE 'SELECT SLEEP(15)%';")
                if connection:
                    break
                if process.poll() is not None:
                    self.fail("Migration exited before interruption: " + "".join(process.communicate()))
                time.sleep(0.05)
            self.assertTrue(connection, "Migration did not reach the post-DDL interruption point")
            process.kill()  # No Python cleanup/failure handler can run.
            process.communicate(timeout=10)
            self.sql(f"KILL CONNECTION {int(connection)};")  # Release only this private test session's lock.
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=10)
        self.assertEqual(self.scalar(f"SELECT status FROM `{self.database}`.schema_migrations WHERE version = {NEXT_VERSION};"), "applying")
        result = self.build("--migrate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"Incomplete migration {NEXT_VERSION} (applying): no retry", result.stderr)
        self.assertEqual(self.snapshot(), before)


    def test_interrupted_history_initialization_is_rejected(self):
        self.assert_success(self.build("--target-version", "1"))
        self.remove_version_metadata()
        ddl = (self.fixture / "sql" / "09_schema_migrations.sql").read_text()
        self.sql(f"USE `{self.database}`;\n" + ddl)
        result = self.build("--migrate", "--baseline")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Interrupted migration initialization", result.stderr)


    def test_baseline_refuses_orphan_metadata_without_modifying_it(self):
        self.assert_success(self.build("--target-version", "1"))
        self.remove_version_metadata()
        self.sql(f"CREATE TABLE `{self.database}`.schema_object_versions (Sentinel INT); "
                 f"INSERT INTO `{self.database}`.schema_object_versions VALUES (42);")
        result = self.build("--migrate", "--baseline")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Orphan migration metadata", result.stderr)
        self.assertEqual(self.scalar(f"SELECT Sentinel FROM `{self.database}`.schema_object_versions;"), "42")


    def test_migration_lock_prevents_concurrent_execution(self):
        self.assert_success(self.build())
        name = f"migrations/{NEXT_VERSION:03d}_lock_test.sql"
        self.add_migration(f"{NEXT_VERSION:03d}_lock_test.sql", "CREATE INDEX idx_LockTest ON Customer (Phone);\nSELECT SLEEP(15);\n")
        process = subprocess.Popen(self.build_command("--migrate"), text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                ready = self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.schema_migrations "
                                     f"WHERE filename = '{name}' AND status = 'applying';") == "1"
                if ready:
                    break
                time.sleep(0.05)
            self.assertTrue(ready)
            second = self.build("--migrate")
            self.assertNotEqual(second.returncode, 0)
            self.assertIn("holds the database migration lock", second.stderr)
        finally:
            connection = self.scalar("SELECT ID FROM information_schema.PROCESSLIST "
                                     f"WHERE DB = '{self.database}' AND INFO LIKE 'SELECT SLEEP(15)%';")
            if connection:
                self.sql(f"KILL CONNECTION {int(connection)};")
            process.communicate(timeout=10)


    def test_preflight_rejects_unsafe_server_defaults_before_ddl(self):
        old = self.scalar("SELECT @@global.sql_mode;")
        self.addCleanup(lambda: self.sql("SET GLOBAL sql_mode = '" + old + "';"))
        self.sql("SET GLOBAL sql_mode = 'NO_ENGINE_SUBSTITUTION';")
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Required SQL modes", result.stderr)
        self.assertFalse(self.database_exists())


    def test_compatible_sql_mode_defaults_create_reproducible_objects(self):
        old = self.scalar("SELECT @@global.sql_mode;")
        self.addCleanup(lambda: self.sql("SET GLOBAL sql_mode = '" + old + "';"))
        self.sql("SET GLOBAL sql_mode = 'STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION';")
        result = self.build()
        self.assert_success(result)
        self.assertIn("SESSION SETTINGS: sql_mode=ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES", result.stdout)


    def test_preflight_rejects_non_durable_checkpoints_before_ddl(self):
        old = self.scalar("SELECT @@global.innodb_flush_log_at_trx_commit;")
        self.addCleanup(lambda: self.sql("SET GLOBAL innodb_flush_log_at_trx_commit = " + old + ";"))
        self.sql("SET GLOBAL innodb_flush_log_at_trx_commit = 2;")
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Durable migration checkpoints", result.stderr)
        self.assertFalse(self.database_exists())



if __name__ == "__main__":
    unittest.main()
