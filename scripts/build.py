#!/usr/bin/env python3
"""Safely build or migrate the database, with environment checks and timestamped logs."""

import argparse
import getpass
import os
from pathlib import Path
import re
import subprocess
import sys
from contextlib import ExitStack

from database import checksum, RunLog, Session, source_revision, verify_environment
from migrate import HISTORY_FILE, load_migrations, run_migrations


PROJECT_DATABASE = "vehicle_service_maintenance"
DEMO_FILE = "08_demo_accounts.sql"
DEMO_PRINCIPALS = (
    "role_service_advisor", "role_technician", "role_manager",
    "sa_amy", "tech_ben", "mgr_mike",
)
FIXTURE_PRINCIPALS = (*DEMO_PRINCIPALS, 'tech_carla')
CONSOLIDATED_FILES = ('01_schema.sql', '02_indexes.sql', '04_procedures.sql',
                      '03_views_reports.sql', '06_sample_data.sql', '05_triggers_roles.sql',
                      '08_demo_accounts.sql', '07_tests.sql')


def load_inputs(sql_dir, legacy=False, historical=False):
    """Validate and read the single ordered manifest before connecting."""
    manifest = (sql_dir / "build.sql").read_text()
    names = re.findall(r"^SOURCE\s+((?:migrations/)?[0-9]{2,3}_[a-z0-9_]+\.sql)\s*$",
                       manifest, re.MULTILINE)
    if not names or len(names) != len(set(names)):
        raise ValueError("Build input list is empty or contains duplicates")
    if len(re.findall(r"^SOURCE\b.*$", manifest, re.MULTILINE)) != len(names):
        raise ValueError("Invalid SOURCE entry in sql/build.sql")
    if [name for name in names if not name.startswith('migrations/')] != [*CONSOLIDATED_FILES, HISTORY_FILE]:
        raise ValueError('Invalid build input order; expected consolidated 01–08 and history registry')
    if legacy:
        # The old build order is part of the historical release contract.
        names = [f'{n:02d}_{suffix}.sql' for n, suffix in (
            (1, 'schema'), (2, 'indexes'), (3, 'views_reports'), (4, 'procedures'),
            (5, 'triggers_roles'), (6, 'sample_data'), (8, 'demo_accounts'), (7, 'tests'))] + [
                name for name in names if name == HISTORY_FILE or name.startswith('migrations/')]
    inputs = {}
    for name in names:
        if not historical and (name == HISTORY_FILE or
                (name.startswith('migrations/') and int(Path(name).name[:3]) <= 6)):
            continue
        path = sql_dir / ('legacy/v001/' + name if legacy and '/' not in name and name != HISTORY_FILE else name)
        data = path.read_bytes()
        if re.search(r"^\s*SOURCE\b", data.decode("utf-8"), re.MULTILINE | re.IGNORECASE):
            raise ValueError(f"Nested SOURCE is not supported: {name}")
        inputs[name] = data
    return inputs


def load_build(sql_dir, database, with_demo_accounts, inputs=None):
    """Yield manifest-ordered files; demo administration uses its own connection."""
    inputs = load_inputs(sql_dir) if inputs is None else inputs
    for name, data in inputs.items():
        if name == HISTORY_FILE or name.startswith("migrations/"):
            continue  # The migration runner records and applies these separately.
        if name == DEMO_FILE and not with_demo_accounts:
            yield name, f"SELECT 'SKIP optional {name}';\n"
            continue
        sql = re.sub(r"\b" + PROJECT_DATABASE + r"\b", database, data.decode("utf-8"))
        yield name, f"\nSELECT 'OPERATION {name} sha256={checksum(data)}';\n{sql}\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", default=PROJECT_DATABASE)
    parser.add_argument("--dev-reset", action="store_true",
                        help="Delete/recreate only a database named vsm_dev_*")
    parser.add_argument("--with-demo-accounts", action="store_true",
                        help="Opt in to demo users/roles; existing principals cause refusal")
    parser.add_argument("--mysql", default=os.environ.get("MYSQL_BIN", "mysql"))
    parser.add_argument("-u", "--user", default="vsm_developer")
    parser.add_argument("-p", "--password", action="store_true", help="Prompt for a password")
    parser.add_argument("--admin-user", default="vsm_admin",
                        help="Separate account for principal preflight, demo provisioning, and legacy routine grants")
    parser.add_argument("--admin-password", action="store_true",
                        help="Prompt for admin password (otherwise VSM_ADMIN_PASSWORD)")
    parser.add_argument("--socket")
    parser.add_argument("--host")
    parser.add_argument("--port", type=int)
    parser.add_argument("--migrate", action="store_true", help="Upgrade an existing database; never load sample data/tests")
    parser.add_argument("--baseline", action="store_true", help="Verify/register an unversioned database before upgrading")
    parser.add_argument("--target-version", type=int, help="Stop at this migration version (default: latest)")
    parser.add_argument('--build-profile', choices=('auto', 'consolidated', 'legacy'), default='auto',
                        help='Fresh installation source; migration targets through 006 automatically use legacy')
    parser.add_argument("--log-dir", type=Path, help="Build log directory (default: repository logs/)")
    args = parser.parse_args(argv)

    if "root" in (args.user, args.admin_user):
        parser.error("Root is reserved for initial bootstrapping; use developer/admin accounts")
    if args.user == "vsm_admin" or args.user == args.admin_user:
        parser.error("Builds require a developer account separate from the administrative account")

    if not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", args.database):
        parser.error("Database names must use lowercase letters, digits, and underscores (max 64)")
    if args.dev_reset and not re.fullmatch(r"vsm_dev_[a-z0-9_]+", args.database):
        parser.error("--dev-reset is development-only and requires a vsm_dev_* database")

    if args.migrate and (args.dev_reset or args.with_demo_accounts):
        parser.error("--migrate cannot reset a database or provision demo accounts")
    if args.baseline and not args.migrate:
        parser.error("--baseline is only valid with --migrate")
    if args.migrate and args.build_profile != 'auto':
        parser.error('--build-profile is only valid for fresh builds')
    if args.build_profile == 'consolidated' and args.target_version is not None and args.target_version <= 6:
        parser.error('Current consolidated installations use revision 007; use the legacy profile for migration targets through 006')

    root = Path(__file__).resolve().parent.parent
    log = None
    status = "FAILED"
    try:
        log = RunLog(args.log_dir or root / "logs")
        log.write(f"MODE: {'migrate' if args.migrate else 'build'}; DATABASE: {args.database}")
        sha, dirty = source_revision(root)
        log.write(f"SOURCE COMMIT: {sha}; WORKTREE DIRTY: {str(dirty).lower()}")
        legacy = args.build_profile == 'legacy' or (args.target_version is not None and args.target_version <= 6)
        consolidated = not args.migrate and not legacy
        inputs = load_inputs(root / 'sql', legacy=legacy, historical=not consolidated)
        if consolidated:
            from consolidated_baseline import load_contract, load_current_migrations, install, existing_reader_grants
            contract = load_contract(root / 'sql')
            migrations = load_current_migrations(root / 'sql', inputs, contract)
            snapshot = None
        else:
            migrations, snapshot = load_migrations(root / 'sql', inputs)
        log.write('BUILD PROFILE: ' + ('consolidated' if consolidated else 'legacy/upgrades'))
        if args.target_version is not None and args.target_version not in [m[0] for m in migrations]:
            raise ValueError("Target version is not in sql/build.sql")
        client_version = subprocess.check_output([args.mysql, "--no-defaults", "--version"], text=True).strip()
        # Explicit options override local defaults and keep failures from continuing/reconnecting.
        client = [args.mysql, "--no-defaults", "--batch", "--raw", "--skip-column-names",
                  "--skip-force", "--skip-reconnect", "--unbuffered", "--binary-mode",
                  "--default-character-set=utf8mb4", f"--user={args.user}"]
        if args.socket:
            client += ["--protocol=SOCKET", f"--socket={args.socket}"]
        else:
            if args.host:
                client.append(f"--host={args.host}")
            if args.port is not None:
                client.append(f"--port={args.port}")
        env = os.environ.copy()
        env.pop("VSM_ADMIN_PASSWORD", None)
        if args.password:
            env["MYSQL_PWD"] = getpass.getpass("MySQL password: ")

        with ExitStack() as connections:
            session = connections.enter_context(Session(client, env, log))
            verify_environment(session, client_version, log)
            admin = None

            def get_admin():
                nonlocal admin
                if admin is None:
                    admin_env = env.copy()
                    # Never reuse the developer password for administration.
                    admin_env.pop("MYSQL_PWD", None)
                    if args.admin_password:
                        admin_env["MYSQL_PWD"] = getpass.getpass("Administrative MySQL password: ")
                    elif "VSM_ADMIN_PASSWORD" in os.environ:
                        admin_env["MYSQL_PWD"] = os.environ["VSM_ADMIN_PASSWORD"]
                    admin_client = [f"--user={args.admin_user}" if option.startswith("--user=") else option
                                    for option in client]
                    admin = connections.enter_context(Session(admin_client, admin_env, log))
                    identity = admin.run("SELECT CURRENT_USER();")
                    if identity.split("@", 1)[0] == "root":
                        raise ValueError("Root is not an administrative build identity")
                    log.write(f"ADMINISTRATIVE ACCOUNT: {identity}")
                return admin
            exists = session.run("SELECT COUNT(*) FROM information_schema.SCHEMATA "
                                 f"WHERE SCHEMA_NAME = '{args.database}';") != "0"
            if args.migrate:
                if not exists:
                    raise ValueError("Migration requires an existing database")
                log.write("TESTS: not run during migration (existing business data is preserved)")
            else:
                if exists and not args.dev_reset:
                    raise ValueError(f"Refusing existing database '{args.database}'; contents were not changed")
                if args.with_demo_accounts:
                    names = ", ".join(f"'{name}'" for name in FIXTURE_PRINCIPALS)
                    collisions = get_admin().run(f"SELECT User, Host FROM mysql.user WHERE User IN ({names});")
                    if collisions:
                        raise ValueError("Refusing demo provisioning: existing users/roles would collide:\n" + collisions)
                if not consolidated and (args.target_version or migrations[-1][0]) >= 3:
                    get_admin()  # Fail authentication before creating/resetting a database.
                reader_grants = ()
                if consolidated and not args.with_demo_accounts:
                    # Table-recipient metadata cannot reveal schema/global or column DML grants.
                    # Refuse existing fixture principals rather than silently preserve a native bypass.
                    names = ", ".join(f"'{name}'" for name in FIXTURE_PRINCIPALS)
                    collisions = get_admin().run(f"SELECT User, Host FROM mysql.user WHERE User IN ({names});")
                    log.write('ADMIN inspection: revision-007 native-principal collision preflight')
                    if collisions:
                        raise ValueError('Revision 007 refuses existing application principals; explicit privilege conversion is required before a fresh build:\n' + collisions)
                if args.dev_reset:
                    log.write(f"OPERATION DEVELOPMENT RESET: {args.database}")
                    session.run(f"DROP DATABASE IF EXISTS `{args.database}`;")
                # CREATE without IF NOT EXISTS also guards concurrent creators.
                log.write(f"Building {args.database}")
                session.run(f"SET @build_with_demo_accounts = {int(args.with_demo_accounts)};")
                if consolidated:
                    install(session, client, env, log, args.database, inputs, contract, sha, dirty,
                            args.with_demo_accounts, get_admin, reader_grants)
                else:
                    for name, sql in load_build(root / "sql", args.database, args.with_demo_accounts, inputs):
                        operation_session = get_admin() if name == DEMO_FILE and args.with_demo_accounts else session
                        if operation_session is not session:
                            log.write(f"ADMIN OPERATION: {name}")
                        operation_session.run(sql, echo=True)
                    log.write("DATABASE TEST SUITE: PASS (see individual results and summary above)")
            run_migrations(session, client, env, log, args.database, inputs, migrations, snapshot,
                           sha, dirty, baseline=(not args.migrate or args.baseline), target=args.target_version,
                           get_admin=get_admin)
        log.write(f"{'Migration' if args.migrate else 'Build'} succeeded: {args.database}")
        status = "SUCCESS"
        return 0
    except KeyboardInterrupt:
        status = "INTERRUPTED"
        if log:
            log.write("Interrupted; inspect migration history before retrying")
        return 130
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        message = f"{'Migration' if args.migrate else 'Build'} refused/failed: {error}"
        if log:
            log.write(message)
        print(message, file=sys.stderr)
        return 1
    finally:
        if log:
            log.close(status)


if __name__ == "__main__":
    sys.exit(main())
