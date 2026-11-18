"""Build and migration tests. Always start a private, disposable MySQL server.

Run: python3 -B -m unittest discover -s tests -v
MYSQL_BIN and MYSQLD_BIN may select executables, never an existing server.
"""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import accounts

LATEST_VERSION = max(int(p.name[:3]) for p in (ROOT / "sql" / "migrations").glob("[0-9][0-9][0-9]_*.sql"))
NEXT_VERSION = LATEST_VERSION + 1
BUSINESS_TABLES = ("customer", "vehicle", "technician", "part", "useraccount", "serviceappointment",
                   "repair", "repairestimate", "estimatelineitem", "invoice", "invoicelineitem", "partsusage", "auditlog")


def executable(env_name, name):
    candidate = os.environ.get(env_name) or shutil.which(name)
    if candidate is None:
        candidate = f"/usr/local/mysql/bin/{name}"
    if not Path(candidate).is_file():
        raise RuntimeError(f"Set {env_name} to an installed {name} executable")
    return candidate


class DisposableMySQLTestCase(unittest.TestCase):
    binary_logging = False
    legacy_routine_inspection = False
    @classmethod
    def setUpClass(cls):
        cls.mysql = executable("MYSQL_BIN", "mysql")
        cls.mysqld = executable("MYSQLD_BIN", "mysqld")
        cls.temp = tempfile.TemporaryDirectory(prefix="vsm-stage1-", dir="/tmp")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.server_dir = Path(cls.temp.name)
        cls.socket = str(cls.server_dir / "mysql.sock")
        cls.developer_password = uuid.uuid4().hex
        cls.admin_password = uuid.uuid4().hex
        cls.authorized_databases = set()
        datadir = cls.server_dir / "data"
        datadir.mkdir()
        init = subprocess.run(
            [cls.mysqld, "--no-defaults", "--initialize-insecure", f"--datadir={datadir}"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
        )
        if init.returncode:
            raise RuntimeError("Disposable MySQL initialization failed:\n" + init.stdout)
        log = open(cls.server_dir / "server.log", "w+")
        cls.addClassCleanup(log.close)
        cls.server = subprocess.Popen(
            [cls.mysqld, "--no-defaults", f"--datadir={datadir}", f"--socket={cls.socket}",
             f"--pid-file={cls.server_dir / 'mysql.pid'}", "--skip-networking", "--mysqlx=OFF",
             "--innodb-buffer-pool-size=64M",
             f"--log-bin={cls.server_dir / 'binlog'}" if cls.binary_logging else "--skip-log-bin"],
            stdout=log, stderr=subprocess.STDOUT,
        )

        def stop():
            if cls.server.poll() is None:
                cls.server.terminate()
                try:
                    cls.server.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    cls.server.kill()
                    cls.server.wait(timeout=10)

        cls.addClassCleanup(stop)
        for _ in range(200):
            if cls.server.poll() is not None:
                log.seek(0)
                raise RuntimeError("Disposable MySQL exited:\n" + log.read())
            if Path(cls.socket).exists():
                # The only root connection: provision the administrator on this
                # newly initialized private server, then lock root immediately.
                probe = subprocess.run(
                    [cls.mysql, "--no-defaults", "--protocol=SOCKET", f"--socket={cls.socket}",
                     "--user=root", "--batch", "--skip-force"],
                    input=accounts.bootstrap_admin(cls.admin_password, test_namespace=True, lock_root=True,
                                                   legacy_routine_inspection=cls.legacy_routine_inspection),
                    env={key: value for key, value in os.environ.items() if key != "MYSQL_PWD"},
                    text=True, capture_output=True, timeout=30)
                if probe.returncode == 0:
                    cls.admin_sql(accounts.create_developer(cls.developer_password))
                    return
                if "ERROR 2002" not in probe.stderr:
                    raise RuntimeError("Private account bootstrap failed:\n" + probe.stderr)
            time.sleep(0.1)
        raise RuntimeError("Disposable MySQL did not become ready")


    @classmethod
    def sql(cls, statement, check=True):
        return cls.account_sql("vsm_developer", cls.developer_password, statement, check)

    @classmethod
    def admin_sql(cls, statement, check=True):
        return cls.account_sql("vsm_admin", cls.admin_password, statement, check)

    @classmethod
    def account_sql(cls, user, password, statement, check=True):
        if user == "root":
            raise ValueError("Root is allowed only in private-server bootstrap")
        env = os.environ.copy()
        env["MYSQL_PWD"] = password
        result = subprocess.run(
            [cls.mysql, "--no-defaults", "--protocol=SOCKET", f"--socket={cls.socket}",
             f"--user={user}", "--batch", "--raw", "--skip-column-names", "--skip-force"],
            env=env, input=statement, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60,
        )
        if check and result.returncode:
            raise AssertionError(result.stderr)
        return result

    @classmethod
    def grant_database(cls, database):
        if not database.startswith("vsm_"):
            raise ValueError("Tests may authorize only private vsm_* databases")
        if database not in cls.authorized_databases:
            cls.admin_sql(accounts.grant_developer_schema(database))
            cls.authorized_databases.add(database)


    def setUp(self):
        self.database = "vsm_dev_" + uuid.uuid4().hex[:12]
        self.grant_database(self.database)
        self.fixture = self.server_dir / ("fixture_" + uuid.uuid4().hex[:8])
        shutil.copytree(ROOT / "sql", self.fixture / "sql")
        shutil.copytree(ROOT / "scripts", self.fixture / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
        shutil.copy2(ROOT / ".gitignore", self.fixture / ".gitignore")
        shutil.copy2(ROOT / ".gitattributes", self.fixture / ".gitattributes")
        # Each fixture is a disposable Git clone source, never the project repository.
        subprocess.run(["git", "-C", str(self.fixture), "init", "-q"], check=True)
        subprocess.run(["git", "-C", str(self.fixture), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.fixture), "-c", "user.name=Build Tests",
                        "-c", "user.email=tests@example.invalid", "-c", "commit.gpgsign=false",
                        "commit", "-qm", "Disposable build fixture"], check=True)
        # Cleanup is restricted to databases generated by this test on its own server.
        self.addCleanup(lambda: self.sql(f"DROP DATABASE IF EXISTS `{self.database}`;"))
        self.addCleanup(lambda: shutil.rmtree(self.fixture))


    def build_command(self, *options, database=None, root=None):
        self.grant_database(database or self.database)
        return [sys.executable, "-B", str((root or self.fixture) / "scripts" / "build.py"),
                "--mysql", self.mysql, "--socket", self.socket,
                "--database", database or self.database, *options]

    def build_env(self):
        env = os.environ.copy()
        env["MYSQL_PWD"] = self.developer_password
        env["VSM_ADMIN_PASSWORD"] = self.admin_password
        return env


    def build(self, *options, database=None, root=None, cwd=None):
        return subprocess.run(self.build_command(*options, database=database, root=root),
                              env=self.build_env(), cwd=cwd, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=60)


    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Build succeeded:", result.stdout)


    def scalar(self, statement):
        return self.sql(statement).stdout.strip()

    def admin_scalar(self, statement):
        return self.admin_sql(statement).stdout.strip()


    def database_exists(self, database=None):
        return self.scalar("SELECT COUNT(*) FROM information_schema.SCHEMATA "
                           f"WHERE SCHEMA_NAME = '{database or self.database}';") == "1"


    def snapshot(self):
        keys = self.scalar("SELECT TABLE_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION) "
                           "FROM information_schema.KEY_COLUMN_USAGE "
                           f"WHERE TABLE_SCHEMA = '{self.database}' AND CONSTRAINT_NAME = 'PRIMARY' "
                           "AND LOWER(TABLE_NAME) IN (" + ",".join("'" + name + "'" for name in BUSINESS_TABLES) + ") "
                           "GROUP BY TABLE_NAME ORDER BY TABLE_NAME;")
        result = []
        for row in keys.splitlines():
            table, columns = row.split("\t")
            order = ", ".join(f"`{column}`" for column in columns.split(","))
            columns = self.scalar("SELECT COLUMN_NAME FROM information_schema.COLUMNS "
                                  f"WHERE TABLE_SCHEMA = '{self.database}' AND TABLE_NAME = '{table}' "
                                  "AND EXTRA NOT LIKE '%GENERATED%' AND COLUMN_NAME <> 'SessionAccount' "
                                  "ORDER BY ORDINAL_POSITION;")
            selected = ", ".join(f"`{column}`" for column in columns.splitlines())
            result.append((table, self.scalar(f"SELECT {selected} FROM `{self.database}`.`{table}` ORDER BY {order};")))
        return result


    def migration_history(self):
        return self.scalar(f"SELECT * FROM `{self.database}`.schema_migrations ORDER BY version;")


    def remove_version_metadata(self):
        self.sql(f"DROP TABLE `{self.database}`.schema_object_versions; "
                 f"DROP TABLE `{self.database}`.schema_migrations;")


    def add_migration(self, name, sql, listed=True):
        (self.fixture / "sql" / "migrations" / name).write_text(sql)
        if listed:
            path = self.fixture / "sql" / "build.sql"
            path.write_text(path.read_text() + f"\nSOURCE migrations/{name}\n")

