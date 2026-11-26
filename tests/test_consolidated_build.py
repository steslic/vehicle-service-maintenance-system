"""Independent tagged-release comparisons on private disposable MySQL servers."""

import json
from pathlib import Path
import re
import shutil
import subprocess
import time
import unittest

import mysql_test_support as support
from database import Session
from migrate import schema_fingerprints
import test_reference_identity as identity

CHECKPOINT = '71696139e84a4e9b69f4baa6f89a6a8d20505561'


class ConsolidatedBuildTests(support.Version006TestCase):
    remove_demo_accounts = identity.ReferenceIdentityTests.remove_demo_accounts

    def tagged_checkout(self):
        target = self.server_dir / ('reference_' + self.database)
        target.mkdir()
        archive = subprocess.check_output(['git', '-C', str(support.ROOT), 'archive', CHECKPOINT])
        subprocess.run(['tar', '-x', '-C', str(target)], input=archive, check=True)
        # Source revision logging needs a Git checkout, independently of our implementation.
        subprocess.run(['git', '-C', str(target), 'init', '-q'], check=True)
        subprocess.run(['git', '-C', str(target), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(target), '-c', 'user.name=Reference Tests', '-c',
                        'user.email=tests@example.invalid', '-c', 'commit.gpgsign=false',
                        'commit', '-qm', 'Tagged reference fixture'], check=True)
        self.addCleanup(lambda: shutil.rmtree(target))
        return target

    def fingerprints(self, database):
        class QuietLog:
            def write(self, message): pass
        command = [self.mysql, '--no-defaults', '--protocol=SOCKET', f'--socket={self.socket}',
                   '--user=vsm_developer', '--batch', '--raw', '--skip-column-names', '--skip-force', '--unbuffered']
        with Session(command, self.build_env(), QuietLog()) as session:
            session.run(f'USE `{database}`;')
            return schema_fingerprints(session, database)

    def security(self, database):
        result = {}
        for kind, name, schema in (('ROUTINES', 'ROUTINE_NAME', 'ROUTINE_SCHEMA'),
                                   ('VIEWS', 'TABLE_NAME', 'TABLE_SCHEMA'),
                                   ('TRIGGERS', 'TRIGGER_NAME', 'TRIGGER_SCHEMA')):
            extra = ', ACTION_ORDER' if kind == 'TRIGGERS' else ', SECURITY_TYPE'
            result[kind] = self.scalar(f'SELECT {name}, DEFINER{extra} FROM information_schema.{kind} '
                                      f"WHERE {schema} = '{database}' ORDER BY {name};")
        for user, password, role in (('sa_amy', 'Advisor#2026', 'role_service_advisor'),
                                      ('tech_ben', 'Tech#2026', 'role_technician'),
                                      ('mgr_mike', 'Manager#2026', 'role_manager')):
            grants = self.account_sql(user, password, f"SHOW GRANTS FOR CURRENT_USER USING '{role}';").stdout
            # This expands the user's assigned role, including table/column/routine grants.
            result[user] = grants.replace(database, 'DATABASE')
        return result

    def data(self, database, catalog=None):
        result = {}
        tables = self.scalar("SELECT TABLE_NAME FROM information_schema.TABLES "
            f"WHERE TABLE_SCHEMA = '{database}' AND TABLE_TYPE = 'BASE TABLE' "
            "AND TABLE_NAME NOT IN ('schema_migrations', 'schema_object_versions') ORDER BY TABLE_NAME;")
        for table in (catalog if catalog is not None else tables.splitlines()):
            columns = catalog[table] if catalog is not None else self.scalar(
                "SELECT COLUMN_NAME, DATA_TYPE FROM information_schema.COLUMNS "
                f"WHERE TABLE_SCHEMA = '{database}' AND TABLE_NAME = '{table}' ORDER BY ORDINAL_POSITION;")
            projection = ', '.join(f'HEX(`{name}`)' if kind in ('binary','varbinary','bit') else f'`{name}`'
                for name, kind in (row.split('\t') for row in columns.splitlines()))
            rows = self.scalar(f'SELECT JSON_ARRAY({projection}) FROM `{database}`.`{table}`;')
            result[table] = sorted(rows.splitlines())
        return result

    def logical_data(self, data):
        # Runtime observation clocks and random correlation UUIDs differ across executions.
        # Business dates, amounts, keys, payloads, actors and NULL provenance remain compared.
        today = self.scalar('SELECT CURDATE();')
        contexts = {}
        def replace(text):
            def correlation(match):
                return contexts.setdefault(match[0], f'<context:{len(contexts) + 1}>')
            text = re.sub(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', correlation, text)
            text = re.sub(re.escape(today) + r'[ T]\d\d:\d\d:\d\d(?:\.\d+)?', '<runtime-clock>', text)
            return text
        return {table: sorted(replace(row) for row in rows) for table, rows in data.items()}

    def audit_json_types(self, database):
        """Serialization alone cannot distinguish JSON DATETIME/DECIMAL from strings/doubles."""
        result = {}
        for column in ('PreviousValue', 'NewValue'):
            values = self.scalar(f'SELECT JSON_ARRAY(AuditLogID, `{column}`) FROM `{database}`.AuditLog;')
            paths = set()
            def walk(value, path='$'):
                paths.add(path)
                if isinstance(value, dict):
                    for key, child in value.items():
                        walk(child, path + '.' + json.dumps(key))
                elif isinstance(value, list):
                    for index, child in enumerate(value):
                        walk(child, path + f'[{index}]')
            for row in values.splitlines():
                walk(json.loads(row)[1])
            paths = sorted(paths)
            expression = ', '.join(f'JSON_TYPE(JSON_EXTRACT(`{column}`, {support.accounts.literal(path)}))' for path in paths)
            rows = self.scalar(f'SELECT JSON_ARRAY(AuditLogID, {expression}) FROM `{database}`.AuditLog ORDER BY AuditLogID;')
            result[column] = (paths, rows)
        return result

    def add_database(self, name):
        self.grant_database(name)
        self.addCleanup(lambda: self.sql(f'DROP DATABASE IF EXISTS `{name}`;'))
        return name

    def workflow(self, database):
        def actor(user, password, statements):
            return self.account_sql(user, password, f'USE `{database}`; ' + statements).stdout.strip()
        actor('sa_amy', 'Advisor#2026', "CALL sp_CreateServiceAppointment(1, 5, 1, NULL, "
              "TIMESTAMP(CURDATE() + INTERVAL 150 DAY, '10:00:00'), 'Cross-path workflow', 60);")
        appointment = self.scalar(f"SELECT AppointmentID FROM `{database}`.ServiceAppointment WHERE ServiceRequestDescription = 'Cross-path workflow';")
        actor('sa_amy', 'Advisor#2026', f"UPDATE ServiceAppointment SET Status = 'Checked In' WHERE AppointmentID = {appointment}; "
              f"UPDATE ServiceAppointment SET Status = 'In Progress' WHERE AppointmentID = {appointment}; "
              f"INSERT INTO Repair (AppointmentID, RepairDateTime, RepairType, RepairDescription, Status) "
              f"VALUES ({appointment}, NOW(), 'Oil Change', 'Cross-path repair', 'Open');")
        repair = self.scalar(f"SELECT RepairID FROM `{database}`.Repair WHERE RepairDescription = 'Cross-path repair';")
        actor('tech_ben', 'Tech#2026', f"UPDATE vw_MyRepairs SET Status = 'In Progress' WHERE RepairID = {repair}; "
              f"CALL sp_CompleteRepair({repair}, 1, NULL, '[{{\"partId\":1,\"qty\":1}}]');")
        return appointment, repair

    def test_tagged_schema_security_data_and_object_versions_are_equivalent(self):
        tagged = self.tagged_checkout()
        old = self.add_database(self.database + '_tag')
        self.addCleanup(self.remove_demo_accounts)
        self.assert_success(self.build('--with-demo-accounts', root=tagged, database=old))
        expected_objects = self.fingerprints(old)
        self.assertEqual(len(expected_objects), 246)
        expected_security = self.security(old)
        expected_data = self.logical_data(self.data(old))
        expected_json_types = self.audit_json_types(old)
        expected_ids = self.workflow(old)
        expected_workflow = self.logical_data(self.data(old))
        expected_workflow_types = self.audit_json_types(old)
        self.remove_demo_accounts()
        self.assert_success(self.build('--with-demo-accounts'))
        self.assertEqual(self.fingerprints(self.database), expected_objects)
        self.assertEqual(self.security(self.database), expected_security)
        actual_data = self.logical_data(self.data(self.database))
        self.assertEqual(self.audit_json_types(self.database), expected_json_types)
        for table in expected_data:
            with self.subTest(table=table):
                self.assertEqual(actual_data[table], expected_data[table])
        query = 'SELECT object_type, object_name, migration_version, definition_checksum FROM `{}`.schema_object_versions ORDER BY object_type, object_name;'
        self.assertEqual(self.scalar(query.format(self.database)), self.scalar(query.format(old)))
        self.assertEqual(self.scalar(f"SELECT GROUP_CONCAT(DISTINCT status), COUNT(applied_at), COUNT(covered_at) FROM `{self.database}`.schema_migrations;"), 'covered\t0\t6')
        self.assertEqual(self.scalar(f"SELECT GROUP_CONCAT(DISTINCT status), COUNT(applied_at) FROM `{old}`.schema_migrations;"), 'applied\t6')
        self.assertEqual(self.workflow(self.database), expected_ids)
        actual_workflow = self.logical_data(self.data(self.database))
        self.assertEqual(self.audit_json_types(self.database), expected_workflow_types)
        for table in expected_workflow:
            with self.subTest(workflow_table=table):
                self.assertEqual(actual_workflow[table], expected_workflow[table])

    def test_normal_install_does_not_read_or_execute_historical_sql(self):
        shutil.rmtree(self.fixture / 'sql/legacy')
        shutil.rmtree(self.fixture / 'sql/migrations')
        (self.fixture / 'sql/09_schema_migrations.sql').unlink()
        result = self.build('--admin-user', 'unavailable_admin')
        self.assert_success(result)
        self.assertNotIn('OPERATION migration', result.stdout)
        self.assertNotIn('ADMINISTRATIVE ACCOUNT', result.stdout)
        self.assertEqual(len(self.fingerprints(self.database)), 246)

    def test_clean_clone_default_build_records_actual_coverage_provenance(self):
        clone = self.server_dir / ('clone_' + self.database)
        subprocess.run(['git', 'clone', '--quiet', str(self.fixture), str(clone)], check=True)
        self.addCleanup(lambda: shutil.rmtree(clone))
        result = self.build(root=clone, cwd=self.server_dir)
        self.assert_success(result)
        sha = subprocess.check_output(['git', '-C', str(clone), 'rev-parse', 'HEAD'], text=True).strip()
        log = next((clone / 'logs').glob('*-build.log')).read_text()
        for expected in ('SOURCE COMMIT: ' + sha, 'WORKTREE DIRTY: false', 'PASS\t41',
                         'CONSOLIDATED BASELINE 006: VERIFIED', 'FINAL STATUS: SUCCESS'):
            self.assertIn(expected, log)
        self.assertNotIn('OPERATION migration', log)
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.schema_migrations "
            f"WHERE status = 'covered' AND applied_at IS NULL AND covered_at IS NOT NULL "
            f"AND source_commit_sha = '{sha}' AND source_dirty = 0;"), '6')

    def test_every_older_version_upgrades_without_reseeding(self):
        tagged = self.tagged_checkout()
        self.assert_success(self.build())
        expected = self.fingerprints(self.database)
        for version in range(1, 7):
            with self.subTest(version=version):
                old = self.add_database(self.database + f'_v{version}')
                self.assert_success(self.build('--target-version', str(version), root=tagged, database=old))
                self.sql(f"INSERT INTO `{old}`.Customer (CustomerID, Name) VALUES (9990, 'Preserve across upgrade');")
                # Existing values (including all historical bytes) must survive.
                catalog = {table: self.scalar("SELECT COLUMN_NAME, DATA_TYPE FROM information_schema.COLUMNS "
                    f"WHERE TABLE_SCHEMA = '{old}' AND TABLE_NAME = '{table}' ORDER BY ORDINAL_POSITION;")
                    for table in self.data(old)}
                before = self.data(old, catalog)
                result = self.build('--migrate', database=old)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.fingerprints(old), expected)
                after = self.data(old, catalog)
                for table, rows in before.items():
                    self.assertEqual(after[table], rows, table)
                self.assertEqual(self.scalar(f"SELECT Name FROM `{old}`.Customer WHERE CustomerID = 9990;"), 'Preserve across upgrade')
                history = self.scalar(f'SELECT * FROM `{old}`.schema_migrations ORDER BY version;')
                self.assertEqual(self.build('--migrate', database=old).returncode, 0)
                self.assertEqual(self.scalar(f'SELECT * FROM `{old}`.schema_migrations ORDER BY version;'), history)

    def test_future_migration_executes_once_after_both_installation_paths(self):
        self.assert_success(self.build())
        old = self.add_database(self.database + '_legacy')
        self.assert_success(self.build('--build-profile', 'legacy', database=old))
        self.add_migration('007_next.sql', 'CREATE TABLE NextVersion (ID INT PRIMARY KEY);\n')
        for database in (old, self.database):
            self.assertEqual(self.build('--migrate', database=database).returncode, 0)
            history = self.scalar(f'SELECT * FROM `{database}`.schema_migrations ORDER BY version;')
            self.assertEqual(self.build('--migrate', database=database).returncode, 0)
            self.assertEqual(self.scalar(f'SELECT * FROM `{database}`.schema_migrations ORDER BY version;'), history)
            self.assertEqual(self.scalar(f'SELECT status, applied_at IS NOT NULL FROM `{database}`.schema_migrations WHERE version = 7;'), 'applied\t1')
        self.assertEqual(self.fingerprints(old), self.fingerprints(self.database))
        fresh = self.add_database(self.database + '_fresh7')
        result = self.build(database=fresh)
        self.assert_success(result)
        self.assertEqual(self.fingerprints(fresh), self.fingerprints(old))
        self.assertEqual(self.scalar(f"SELECT status, applied_at IS NOT NULL FROM `{fresh}`.schema_migrations WHERE version = 7;"), 'applied\t1')

    def test_contract_and_schema_drift_fail_closed(self):
        path = self.fixture / 'sql/consolidated/006_baseline.json'
        path.write_text(path.read_text() + '\n')
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('contract checksum mismatch', result.stderr)
        self.assertFalse(self.database_exists())

    def test_wrong_final_object_is_never_registered_as_covered(self):
        path = self.fixture / 'sql/04_procedures.sql'
        path.write_text(path.read_text().replace("RETURN 'retry_transaction';", "RETURN 'wrong_action';"))
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Consolidated baseline schema mismatch', result.stderr)
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.schema_migrations WHERE status = 'covered';"), '0')
        self.assertNotEqual(self.build('--migrate').returncode, 0)

    def test_current_assertion_failure_blocks_registration(self):
        path = self.fixture / 'sql/07_tests.sql'
        path.write_text(path.read_text().replace("'stable error code', IF(", "'stable error code', IF(FALSE AND "))
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Test suite failed', result.stderr)
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.schema_migrations WHERE status = 'covered';"), '0')

    def test_covered_history_cannot_be_forged_or_partially_registered(self):
        self.assert_success(self.build())
        before = self.data(self.database)
        self.sql(f"UPDATE `{self.database}`.schema_migrations SET status = 'applied', applied_at = NOW() WHERE version = 1;")
        result = self.build('--migrate')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('baseline coverage', result.stderr)
        self.assertEqual(self.data(self.database), before)
        self.sql(f"UPDATE `{self.database}`.schema_migrations SET status = 'applied', applied_at = NOW();")
        self.assertNotEqual(self.build('--migrate').returncode, 0)

    def test_default_build_refuses_existing_and_missing_inputs_before_reset(self):
        self.assert_success(self.build())
        before = self.data(self.database)
        self.assertNotEqual(self.build().returncode, 0)
        self.assertEqual(self.data(self.database), before)
        (self.fixture / 'sql/06_sample_data.sql').unlink()
        self.assertNotEqual(self.build('--dev-reset').returncode, 0)
        self.assertEqual(self.data(self.database), before)

    def test_sql_error_stops_default_build_before_seeding_or_registration(self):
        path = self.fixture / 'sql/02_indexes.sql'
        path.write_text(path.read_text() + '\nINVALID SQL;\nCREATE TABLE ShouldNotRun (ID INT);\n')
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ERROR 1064', result.stderr)
        self.assertEqual(self.scalar(f'SELECT COUNT(*) FROM `{self.database}`.Customer;'), '0')
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.schema_migrations WHERE status = 'covered';"), '0')
        self.assertEqual(self.scalar("SELECT COUNT(*) FROM information_schema.TABLES "
            f"WHERE TABLE_SCHEMA = '{self.database}' AND TABLE_NAME = 'ShouldNotRun';"), '0')

    def test_manifest_order_and_nested_sources_fail_before_database_creation(self):
        path = self.fixture / 'sql/build.sql'
        original = path.read_text()
        path.write_text(original.replace('SOURCE 04_procedures.sql\nSOURCE 03_views_reports.sql',
                                         'SOURCE 03_views_reports.sql\nSOURCE 04_procedures.sql'))
        self.assertNotEqual(self.build().returncode, 0)
        self.assertFalse(self.database_exists())
        path.write_text(original)
        path = self.fixture / 'sql/02_indexes.sql'
        path.write_text(path.read_text() + '\nSOURCE anything.sql\n')
        self.assertNotEqual(self.build().returncode, 0)
        self.assertFalse(self.database_exists())

    def test_default_noop_and_drift_checks_preserve_coverage_and_data(self):
        self.assert_success(self.build())
        before = self.data(self.database)
        history = self.migration_history()
        result = self.build('--migrate', '--admin-user', 'unavailable_admin')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.migration_history(), history)
        self.assertEqual(self.data(self.database), before)
        self.sql(f'DROP PROCEDURE `{self.database}`.sp_CompleteRepair;')
        result = self.build('--migrate')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Deployed object schema mismatch', result.stderr)
        self.assertEqual(self.migration_history(), history)

    def test_killed_installation_remains_incomplete_and_is_not_replayed(self):
        path = self.fixture / 'sql/02_indexes.sql'
        path.write_text('SELECT SLEEP(30);\n' + path.read_text())
        process = subprocess.Popen(self.build_command(), env=self.build_env(), stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True)
        connection = None
        try:
            for _ in range(200):
                connection = self.scalar("SELECT ID FROM information_schema.PROCESSLIST "
                    f"WHERE DB = '{self.database}' AND INFO LIKE 'SELECT SLEEP(30)%';")
                if connection:
                    break
                time.sleep(0.05)
            else:
                self.fail('Installation did not reach its durable applying checkpoint')
            process.kill()
            process.communicate(timeout=10)
            self.sql(f'KILL CONNECTION {int(connection)};')
            self.assertEqual(self.scalar(f"SELECT GROUP_CONCAT(DISTINCT status) FROM `{self.database}`.schema_migrations;"), 'applying')
            result = self.build('--migrate')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Incomplete migration', result.stderr)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=10)

    def prepare_permission_roles(self, database, target_grants, other_grants=()):
        """Model table grants that survive DROP DATABASE, without provisioning demo users."""
        roles = ('role_service_advisor', 'role_technician', 'role_manager')
        self.admin_sql('CREATE ROLE ' + ', '.join(support.accounts.literal(role) for role in roles) + ';')
        for role in roles:
            user = 'permission_' + role.removeprefix('role_')
            self.admin_sql(f"CREATE USER '{user}'@'localhost' IDENTIFIED BY 'Permission#2026'; "
                f"GRANT '{role}' TO '{user}'@'localhost'; SET DEFAULT ROLE '{role}' TO '{user}'@'localhost';")
        self.sql(f'CREATE DATABASE `{database}`; CREATE TABLE `{database}`.Customer (ID INT); '
                 f'CREATE TABLE `{database}`.AuditLog (ID INT);')
        for role, table in target_grants:
            self.admin_sql(f"GRANT SELECT ON `{database}`.`{table}` TO '{role}';")
        for other, role, table in other_grants:
            self.admin_sql(f"GRANT SELECT ON `{other}`.`{table}` TO '{role}';")
        self.sql(f'DROP DATABASE `{database}`;')

    def remove_permission_roles(self):
        self.admin_sql("DROP USER IF EXISTS 'permission_service_advisor'@'localhost', "
            "'permission_technician'@'localhost', 'permission_manager'@'localhost'; "
            "DROP ROLE IF EXISTS 'role_service_advisor', 'role_technician', 'role_manager';")

    def permission_readers(self, database):
        routines = self.admin_scalar("SELECT User, Host, Routine_name, Proc_priv FROM mysql.procs_priv "
            f"WHERE Db = '{database}' AND User IN ('role_service_advisor', 'role_technician', 'role_manager') "
            "ORDER BY User, Host, Routine_name;")
        view = self.admin_scalar("SELECT User, Host, Table_name FROM mysql.tables_priv "
            f"WHERE Db = '{database}' AND User = 'role_manager' AND LOWER(Table_name) = 'vw_audittrail';")
        return routines, view

    def test_permission_qualified_existing_roles_match_tag_without_demo_provisioning(self):
        self.addCleanup(self.remove_permission_roles)
        tagged = self.tagged_checkout()
        expected = None
        for label, root in (('tag', tagged), ('consolidated', None)):
            with self.subTest(profile=label):
                database = self.add_database(self.database + '_' + label)
                self.prepare_permission_roles(database, (('role_service_advisor', 'Customer'),
                    ('role_technician', 'Customer'), ('role_manager', 'AuditLog')))
                result = self.build(database=database, root=root)
                self.assert_success(result)
                readers = self.permission_readers(database)
                self.assertEqual(readers[0].lower().count('sp_listindicatorvalues'), 3)
                self.assertEqual(readers[0].lower().count('sp_listaudittrail'), 1)
                self.assertIn('vw_audittrail', readers[1].lower())
                effective = {}
                for role in ('role_service_advisor', 'role_technician', 'role_manager'):
                    user = 'permission_' + role.removeprefix('role_')
                    effective[role] = self.account_sql(user, 'Permission#2026',
                        f"SHOW GRANTS FOR CURRENT_USER USING '{role}';").stdout.replace(database, 'DATABASE')
                    self.account_sql(user, 'Permission#2026',
                        f"USE `{database}`; CALL sp_ListIndicatorValues('repair_status');")
                self.account_sql('permission_manager', 'Permission#2026', f'USE `{database}`; '
                    'SELECT COUNT(*) FROM vw_AuditTrail; CALL sp_ListAuditTrail(NULL, NULL, NULL, NULL, NULL, NULL, 10);')
                denied = self.account_sql('permission_service_advisor', 'Permission#2026',
                    f'USE `{database}`; CALL sp_ListAuditTrail(NULL, NULL, NULL, NULL, NULL, NULL, 10);', check=False)
                self.assertIn('ERROR 1370', denied.stderr)
                for table, schema_column in (('TRIGGERS', 'TRIGGER_SCHEMA'), ('ROUTINES', 'ROUTINE_SCHEMA')):
                    self.assertEqual(self.scalar(f'SELECT DISTINCT DEFINER FROM information_schema.{table} '
                        f"WHERE {schema_column} = '{database}';"), 'vsm_developer@localhost')
                self.assertEqual(self.admin_scalar("SELECT COUNT(*) FROM mysql.procs_priv "
                    "WHERE User = 'vsm_developer' AND FIND_IN_SET('Grant', Proc_priv);"), '0')
                self.assertNotIn('WITH GRANT OPTION', self.scalar('SHOW GRANTS;'))
                self.assertEqual(self.admin_scalar("SELECT COUNT(*) FROM mysql.user "
                    "WHERE User IN ('sa_amy', 'tech_ben', 'mgr_mike');"), '0')
                if expected is None:
                    expected = (readers, effective, self.fingerprints(database))
                else:
                    self.assertEqual((readers, effective, self.fingerprints(database)), expected)
                    self.assertIn('ADMIN existing role reader grants:', result.stdout)
                    self.assertNotIn('ADMIN temporary routine authority:', result.stdout)
                self.remove_permission_roles()

    def test_permission_unrelated_roles_receive_no_target_grants_or_admin_connection(self):
        self.addCleanup(self.remove_permission_roles)
        tagged = self.tagged_checkout()
        for label, root in (('tag', tagged), ('consolidated', None)):
            database = self.add_database(self.database + '_' + label)
            other = self.add_database(database + '_other')
            self.sql(f'CREATE DATABASE `{other}`; CREATE TABLE `{other}`.AuditLog (ID INT);')
            self.prepare_permission_roles(database, (), tuple((other, role, 'AuditLog') for role in
                ('role_service_advisor', 'role_technician', 'role_manager')))
            before = self.admin_scalar("SELECT User, Host, Db, Table_name FROM mysql.tables_priv "
                "WHERE User IN ('role_service_advisor', 'role_technician', 'role_manager') ORDER BY User, Host, Db, Table_name;")
            options = ('--admin-user', 'unavailable_admin') if label == 'consolidated' else ()
            result = self.build(*options, database=database, root=root)
            self.assert_success(result)
            self.assertEqual(self.permission_readers(database), ('', ''))
            self.assertEqual(self.admin_scalar("SELECT User, Host, Db, Table_name FROM mysql.tables_priv "
                "WHERE User IN ('role_service_advisor', 'role_technician', 'role_manager') ORDER BY User, Host, Db, Table_name;"), before)
            if label == 'consolidated':
                self.assertNotIn('ADMINISTRATIVE ACCOUNT:', result.stdout)
            self.remove_permission_roles()

    def test_permission_manager_requires_auditlog_grant_in_the_target_schema(self):
        self.addCleanup(self.remove_permission_roles)
        tagged = self.tagged_checkout()
        expected = None
        for label, root in (('tag', tagged), ('consolidated', None)):
            database = self.add_database(self.database + '_' + label)
            other = self.add_database(database + '_other')
            self.sql(f'CREATE DATABASE `{other}`; CREATE TABLE `{other}`.AuditLog (ID INT);')
            self.prepare_permission_roles(database, (('role_manager', 'Customer'),),
                                          ((other, 'role_manager', 'AuditLog'),))
            self.assert_success(self.build(database=database, root=root))
            readers = self.permission_readers(database)
            self.assertEqual(readers[0].lower().count('sp_listindicatorvalues'), 1)
            self.assertNotIn('sp_listaudittrail', readers[0].lower())
            self.assertEqual(readers[1], '')
            denied = self.account_sql('permission_manager', 'Permission#2026', f'USE `{database}`; '
                'CALL sp_ListAuditTrail(NULL, NULL, NULL, NULL, NULL, NULL, 10);', check=False)
            self.assertIn('ERROR 1370', denied.stderr)
            if expected is None:
                expected = readers
            else:
                self.assertEqual(readers, expected)
            self.remove_permission_roles()

    def test_permission_demo_collisions_refuse_before_reset_and_leave_principals_unchanged(self):
        self.addCleanup(self.remove_demo_accounts)
        tagged = self.tagged_checkout()
        for label, root in (('tag', tagged), ('consolidated', None)):
            for principal in ('role_service_advisor', 'sa_amy'):
                with self.subTest(profile=label, principal=principal):
                    database = self.add_database(self.database + '_' + label + ('_role' if principal.startswith('role_') else '_user'))
                    self.sql(f'CREATE DATABASE `{database}`; CREATE TABLE `{database}`.Sentinel (ID INT); '
                             f'INSERT INTO `{database}`.Sentinel VALUES (42);')
                    self.admin_sql("CREATE ROLE 'role_service_advisor';" if principal.startswith('role_') else
                                   "CREATE USER 'sa_amy'@'localhost' IDENTIFIED BY 'Unrelated#2026';")
                    before = self.admin_scalar("SELECT User, Host FROM mysql.user WHERE User IN "
                        "('role_service_advisor', 'role_technician', 'role_manager', 'sa_amy', 'tech_ben', 'mgr_mike') ORDER BY User, Host;")
                    result = self.build('--with-demo-accounts', '--dev-reset', database=database, root=root)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('existing users/roles would collide', result.stderr)
                    self.assertEqual(self.scalar(f'SELECT ID FROM `{database}`.Sentinel;'), '42')
                    self.assertEqual(self.admin_scalar("SELECT User, Host FROM mysql.user WHERE User IN "
                        "('role_service_advisor', 'role_technician', 'role_manager', 'sa_amy', 'tech_ben', 'mgr_mike') ORDER BY User, Host;"), before)
                    self.remove_demo_accounts()

    def test_permission_bad_admin_refuses_before_creation_or_development_reset(self):
        self.addCleanup(self.remove_permission_roles)
        for reset in (False, True):
            with self.subTest(reset=reset):
                database = self.add_database(self.database + ('_reset' if reset else '_fresh'))
                self.prepare_permission_roles(database, (('role_manager', 'AuditLog'),))
                if reset:
                    self.sql(f'CREATE DATABASE `{database}`; CREATE TABLE `{database}`.Sentinel (ID INT); '
                             f'INSERT INTO `{database}`.Sentinel VALUES (42);')
                result = self.build('--admin-user', 'unavailable_admin', *(['--dev-reset'] if reset else []), database=database)
                self.assertNotEqual(result.returncode, 0)
                if reset:
                    self.assertEqual(self.scalar(f'SELECT ID FROM `{database}`.Sentinel;'), '42')
                else:
                    self.assertFalse(self.database_exists(database))
                self.assertEqual(self.permission_readers(database), ('', ''))
                self.remove_permission_roles()

    def test_permission_grant_failure_does_not_cover_baseline_or_escalate_developer(self):
        self.addCleanup(self.remove_permission_roles)
        self.prepare_permission_roles(self.database, (('role_manager', 'AuditLog'),))
        # Valid administrative identity but no grant authority: never fall back to developer/root.
        self.admin_sql(f"CREATE USER 'permission_limited_admin'@'localhost' IDENTIFIED BY '{self.admin_password}';")
        self.addCleanup(lambda: self.admin_sql("DROP USER 'permission_limited_admin'@'localhost';"))
        result = self.build('--admin-user', 'permission_limited_admin')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ADMINISTRATIVE ACCOUNT: permission_limited_admin@localhost', result.stdout)
        self.assertEqual(self.scalar(f"SELECT COUNT(*) FROM `{self.database}`.schema_migrations WHERE status = 'covered';"), '0')
        self.assertEqual(self.scalar(f"SELECT GROUP_CONCAT(DISTINCT status) FROM `{self.database}`.schema_migrations;"), 'failed')
        self.assertEqual(self.permission_readers(self.database), ('', ''))
        self.assertNotIn('WITH GRANT OPTION', self.scalar('SHOW GRANTS;'))

    def test_historical_files_and_generators_remain_exact(self):
        for path in (support.ROOT / 'sql/migrations').glob('[0-9][0-9][0-9]_*.sql'):
            with self.subTest(path=path.name):
                self.assertEqual(path.read_bytes(), subprocess.check_output(['git', '-C', str(support.ROOT), 'show', f'{CHECKPOINT}:sql/migrations/{path.name}']))
        for path in (support.ROOT / 'sql/legacy/v001').glob('*.sql'):
            self.assertEqual(path.read_bytes(), subprocess.check_output(['git', '-C', str(support.ROOT), 'show', f'{CHECKPOINT}:sql/{path.name}']))
        import generate_standardized_errors as errors
        import generate_temporal_history as temporal
        self.assertEqual(errors.generate(), (support.ROOT / 'sql/migrations/006_standardized_error_handling.sql').read_text())
        self.assertEqual(temporal.generate(), (support.ROOT / 'sql/migrations/005_temporal_history.sql').read_text())


if __name__ == '__main__':
    unittest.main()
