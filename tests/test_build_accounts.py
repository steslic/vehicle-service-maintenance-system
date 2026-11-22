"""Least-privilege build checks, exclusively on private disposable servers."""

import subprocess
import sys
import uuid

import mysql_test_support as support


class BuildAccountTests(support.DisposableMySQLTestCase):
    legacy_routine_inspection = True

    def remove_demo_accounts(self):
        self.admin_sql("DROP USER IF EXISTS 'sa_amy'@'localhost', 'tech_ben'@'localhost', 'mgr_mike'@'localhost'; "
                       "DROP ROLE IF EXISTS 'role_service_advisor', 'role_technician', 'role_manager';")

    def assert_no_developer_grant_authority(self):
        self.assertEqual(self.admin_scalar(
            "SELECT COUNT(*) FROM mysql.procs_priv WHERE User = 'vsm_developer' "
            "AND FIND_IN_SET('Grant', Proc_priv);"), "0")
        self.assertNotIn("WITH GRANT OPTION", self.scalar("SHOW GRANTS;"))

    def test_default_build_and_all_object_definers_use_developer(self):
        result = self.build()
        self.assert_success(result)
        self.assertIn("DATABASE SESSION: vsm_developer@localhost", result.stdout)
        self.assertIn("ADMINISTRATIVE ACCOUNT: vsm_admin@localhost", result.stdout)
        self.assertIn("PASS\t65", result.stdout)
        self.assertNotIn("root@", result.stdout)
        for table in ("ROUTINES", "VIEWS", "TRIGGERS"):
            schema_column = {"ROUTINES": "ROUTINE_SCHEMA", "VIEWS": "TABLE_SCHEMA", "TRIGGERS": "TRIGGER_SCHEMA"}[table]
            self.assertEqual(self.scalar(f"SELECT DISTINCT DEFINER FROM information_schema.{table} "
                                         f"WHERE {schema_column} = '{self.database}';"), "vsm_developer@localhost")
        self.assert_no_developer_grant_authority()

    def test_upgrade_preserves_data_and_restores_routine_privileges(self):
        self.addCleanup(self.remove_demo_accounts)
        self.admin_sql("CREATE USER 'grant_receiver'@'localhost';")
        self.addCleanup(lambda: self.admin_sql("DROP USER 'grant_receiver'@'localhost';"))
        self.assert_success(self.build("--target-version", "2", "--with-demo-accounts"))
        self.admin_sql(f"GRANT EXECUTE, ALTER ROUTINE ON PROCEDURE `{self.database}`.sp_CompleteRepair "
                       "TO 'grant_receiver'@'localhost' WITH GRANT OPTION;")
        query = ("SELECT User, Host, Routine_name, Proc_priv FROM mysql.procs_priv "
                 f"WHERE Db = '{self.database}' AND User <> 'vsm_developer' ORDER BY User, Routine_name;")
        before_grants = self.admin_scalar(query)
        before = self.snapshot()
        result = self.build("--migrate")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("DATABASE SESSION: vsm_developer@localhost", result.stdout)
        self.assertEqual(before, self.snapshot())
        # The reference reader is deliberately added by migration 003.
        actual = self.admin_scalar(query)
        self.assertEqual([line for line in actual.splitlines()
                          if 'sp_listindicatorvalues' not in line.lower() and 'sp_listaudittrail' not in line.lower()],
                         before_grants.splitlines())
        self.assert_no_developer_grant_authority()

    def test_legacy_definer_upgrade_uses_admin_for_metadata_only(self):
        self.admin_sql("CREATE USER 'legacy_builder'@'localhost' IDENTIFIED BY 'Legacy#2026';")
        def cleanup():
            self.sql(f"DROP DATABASE IF EXISTS `{self.database}`;")
            self.admin_sql("DROP USER 'legacy_builder'@'localhost';")
        self.addCleanup(cleanup)
        schema = support.accounts.database_scope(self.database)
        self.admin_sql(f"GRANT {support.accounts.SCHEMA_PRIVILEGES} ON `{schema}`.* TO 'legacy_builder'@'localhost';")
        for table, columns in support.accounts.METADATA_COLUMNS.items():
            self.admin_sql(f"GRANT SELECT ({columns}) ON mysql.{table} TO 'legacy_builder'@'localhost';")
        env = self.build_env()
        env['MYSQL_PWD'] = 'Legacy#2026'
        result = subprocess.run(self.build_command('--user', 'legacy_builder', '--target-version', '2'),
                                env=env, text=True, capture_output=True, timeout=60)
        self.assert_success(result)
        self.assertNotEqual(self.scalar("SELECT COUNT(*) FROM information_schema.ROUTINES "
                                        f"WHERE ROUTINE_SCHEMA = '{self.database}' AND ROUTINE_DEFINITION IS NULL;"), '0')
        before = self.snapshot()
        result = self.build('--migrate')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('DATABASE SESSION: vsm_developer@localhost', result.stdout)
        self.assertIn('ADMIN metadata inspection:', result.stdout)
        self.assertEqual(before, self.snapshot())
        self.assertNotIn('SHOW_ROUTINE', self.scalar('SHOW GRANTS;'))
        self.assert_no_developer_grant_authority()

    def test_baseline_build_and_noop_upgrade_need_no_administrator_connection(self):
        result = self.build("--target-version", "2", "--admin-user", "unavailable_admin")
        self.assert_success(result)
        self.assertNotIn("ADMINISTRATIVE ACCOUNT", result.stdout)
        self.assertEqual(self.build("--migrate").returncode, 0)
        result = self.build("--migrate", "--admin-user", "unavailable_admin")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("ADMINISTRATIVE ACCOUNT", result.stdout)

    def test_bad_admin_credentials_refuse_build_and_upgrade_before_ddl(self):
        result = self.build("--admin-user", "unavailable_admin")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.database_exists())
        self.assert_success(self.build("--target-version", "2"))
        before = self.snapshot()
        history = self.migration_history()
        result = self.build("--migrate", "--admin-user", "unavailable_admin")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(before, self.snapshot())
        self.assertEqual(history, self.migration_history())

    def test_bad_developer_password_has_no_fallback(self):
        env = self.build_env()
        env['MYSQL_PWD'] = 'wrong-password'
        result = subprocess.run(self.build_command(), env=env, text=True, capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Access denied', result.stderr)
        self.assertFalse(self.database_exists())

    def test_root_and_admin_are_rejected_as_ordinary_build_accounts(self):
        for options in (("--user", "root"), ("--admin-user", "root"), ("--user", "vsm_admin")):
            with self.subTest(options=options):
                result = self.build(*options)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.database_exists())

    def test_developer_cannot_create_accounts_delegate_or_change_server_settings(self):
        self.assert_success(self.build())
        statements = [
            "CREATE USER 'denied_user'@'localhost';",
            "CREATE ROLE 'denied_role';",
            "ALTER USER 'vsm_admin'@'localhost' IDENTIFIED BY 'Denied';",
            f"GRANT SELECT ON `{self.database}`.* TO 'vsm_admin'@'localhost';",
            f"GRANT EXECUTE ON PROCEDURE `{self.database}`.sp_CompleteRepair TO 'vsm_admin'@'localhost';",
            "GRANT SELECT ON *.* TO 'vsm_developer'@'localhost';",
            "SET GLOBAL sql_mode = 'NO_ENGINE_SUBSTITUTION';",
            "UPDATE mysql.user SET User = 'denied' WHERE User = 'vsm_admin';",
            f"CREATE DEFINER='root'@'localhost' PROCEDURE `{self.database}`.denied_definer() SELECT 1;",
        ]
        for statement in statements:
            with self.subTest(statement=statement):
                result = self.sql(statement, check=False)
                self.assertNotEqual(result.returncode, 0, statement)
                self.assertIn('denied', result.stderr.lower())
        self.assert_no_developer_grant_authority()

    def test_developer_is_limited_to_exact_schema_names(self):
        neighbor = self.database + '_neighbor'
        self.admin_sql(f"CREATE DATABASE `{neighbor}`; CREATE TABLE `{neighbor}`.Sentinel (ID INT); "
                       f"INSERT INTO `{neighbor}`.Sentinel VALUES (42);")
        self.addCleanup(lambda: self.admin_sql(f"DROP DATABASE `{neighbor}`;"))
        # A schema GRANT containing unescaped underscores would admit this name.
        lookalike = self.database.replace('_', 'x')
        for statement in (f"CREATE DATABASE `{lookalike}`;", f"SELECT * FROM `{neighbor}`.Sentinel;",
                          f"INSERT INTO `{neighbor}`.Sentinel VALUES (1);", f"DROP DATABASE `{neighbor}`;"):
            with self.subTest(statement=statement):
                self.assertNotEqual(self.sql(statement, check=False).returncode, 0)
        self.assertEqual(self.admin_scalar(f"SELECT ID FROM `{neighbor}`.Sentinel;"), '42')
        self.assertNotEqual(self.admin_sql("CREATE DATABASE unrelated_store;", check=False).returncode, 0)

    def test_privilege_metadata_access_excludes_hashes_and_unneeded_columns(self):
        self.sql("SELECT User, Host, Db, Table_name FROM mysql.tables_priv; "
                 "SELECT User, Host, Db, Routine_name, Proc_priv FROM mysql.procs_priv;")
        for query in ("SELECT authentication_string FROM mysql.user;", "SELECT * FROM mysql.user;",
                      "SELECT Table_priv FROM mysql.tables_priv;", "SELECT * FROM mysql.procs_priv;"):
            with self.subTest(query=query):
                self.assertNotEqual(self.sql(query, check=False).returncode, 0)
        self.assertNotEqual(self.admin_sql("SELECT authentication_string FROM mysql.user;", check=False).returncode, 0)

    def test_developer_setup_account_has_no_operational_person_fallback(self):
        self.assert_success(self.build())
        result = self.sql(f"USE `{self.database}`; SET @app_user_id = 1; "
                          "CALL sp_CreateServiceAppointment(1, 5, 1, 1, CURDATE() + INTERVAL 130 DAY, 'Denied', 60);",
                          check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ERROR 52001 (', result.stderr)
        self.assertEqual(self.scalar(f"SELECT CONCAT(SessionAccount, ':', COALESCE(UserID, 'NULL')) "
                                     f"FROM `{self.database}`.AuditLog WHERE Action = 'Rejected' "
                                     "ORDER BY AuditLogID DESC LIMIT 1;"), 'vsm_developer@localhost:NULL')

    def test_admin_scope_provisioning_cli_uses_only_admin(self):
        database = "vsm_dev_cli_" + uuid.uuid4().hex[:8]
        # getpass reads /dev/tty when available, regardless of piped stdin.
        # Patch only this child process; manual accounts.py keeps real prompts.
        invoke_cli = """
import os
import runpy
import sys
from unittest.mock import patch

script = sys.argv.pop(1)
sys.path.insert(0, os.path.dirname(script))
with patch('getpass.getpass', return_value=os.environ['VSM_ADMIN_PASSWORD']) as prompt:
    runpy.run_path(script, run_name='__main__')
prompt.assert_called_once_with('vsm_admin connection password: ')
"""
        result = subprocess.run(
            [sys.executable, '-B', '-c', invoke_cli, str(self.fixture / 'scripts' / 'accounts.py'),
             '--mysql', self.mysql, '--socket', self.socket, '--database', database],
            stdin=subprocess.DEVNULL, env=self.build_env(), text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('completed as vsm_admin', result.stdout)
        self.assertNotIn('connection password:', result.stdout + result.stderr)
        self.assertNotIn(self.admin_password, result.stdout + result.stderr)
        self.sql(f"CREATE DATABASE `{database}`;")
        self.addCleanup(lambda: self.sql(f"DROP DATABASE `{database}`;"))

    def test_failed_migration_helper_removes_temporary_grant_authority(self):
        self.addCleanup(self.remove_demo_accounts)
        path = self.fixture / 'sql' / 'migrations' / '003_indicator_values.sql'
        sql = path.read_text()
        needle = '    CLOSE principals;'
        self.assertEqual(sql.count(needle), 1)
        path.write_text(sql.replace(needle, "    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Injected grant helper failure';\n" + needle))
        result = self.build('--with-demo-accounts')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Injected grant helper failure', result.stderr)
        self.assertEqual(self.scalar(f"SELECT status FROM `{self.database}`.schema_migrations WHERE version = 3;"), 'failed')
        self.assert_no_developer_grant_authority()


class BinaryLoggingBuildTests(support.DisposableMySQLTestCase):
    binary_logging = True

    def test_routine_creation_requires_admin_approved_binary_logging_setting(self):
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('log_bin_trust_function_creators', result.stderr)
        self.assertFalse(self.database_exists())
        self.admin_sql('SET GLOBAL log_bin_trust_function_creators = ON;')
        result = self.build()
        self.assert_success(result)
        self.assertIn('DATABASE SESSION: vsm_developer@localhost', result.stdout)
