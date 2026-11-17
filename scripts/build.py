#!/usr/bin/env python3
"""Safely build or migrate the database, with environment checks and timestamped logs."""

import argparse
import getpass
import os
from pathlib import Path
import re
import subprocess
import sys

from database import checksum, RunLog, Session, source_revision, verify_environment
from migrate import HISTORY_FILE, load_migrations, run_migrations


PROJECT_DATABASE = "vehicle_service_maintenance"
DEMO_FILE = "08_demo_accounts.sql"
DEMO_PRINCIPALS = (
    "role_service_advisor", "role_technician", "role_manager",
    "sa_amy", "tech_ben", "mgr_mike",
)


def load_inputs(sql_dir):
    """Validate and read the single ordered manifest before connecting."""
    manifest = (sql_dir / "build.sql").read_text()
    names = re.findall(r"^SOURCE\s+((?:migrations/)?[0-9]{2,3}_[a-z0-9_]+\.sql)\s*$",
                       manifest, re.MULTILINE)
    if not names or len(names) != len(set(names)):
        raise ValueError("Build input list is empty or contains duplicates")
    if len(re.findall(r"^SOURCE\b.*$", manifest, re.MULTILINE)) != len(names):
        raise ValueError("Invalid SOURCE entry in sql/build.sql")
    inputs = {}
    for name in names:
        data = (sql_dir / name).read_bytes()
        if re.search(r"^\s*SOURCE\b", data.decode("utf-8"), re.MULTILINE | re.IGNORECASE):
            raise ValueError(f"Nested SOURCE is not supported: {name}")
        inputs[name] = data
    return inputs


def load_build(sql_dir, database, with_demo_accounts, inputs=None):
    """Flatten the existing SQL build into one fail-fast batch."""
    inputs = load_inputs(sql_dir) if inputs is None else inputs
    chunks = [f"SET @build_with_demo_accounts = {int(with_demo_accounts)};\n"]
    for name, data in inputs.items():
        if name == HISTORY_FILE or name.startswith("migrations/"):
            continue  # The migration runner records and applies these separately.
        if name == DEMO_FILE and not with_demo_accounts:
            chunks.append(f"SELECT 'SKIP optional {name}';\n")
            continue
        sql = re.sub(r"\b" + PROJECT_DATABASE + r"\b", database, data.decode("utf-8"))
        chunks.append(f"\nSELECT 'OPERATION {name} sha256={checksum(data)}';\n{sql}\n")
    return "".join(chunks)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", default=PROJECT_DATABASE)
    parser.add_argument("--dev-reset", action="store_true",
                        help="Delete/recreate only a database named vsm_dev_*")
    parser.add_argument("--with-demo-accounts", action="store_true",
                        help="Opt in to demo users/roles; existing principals cause refusal")
    parser.add_argument("--mysql", default=os.environ.get("MYSQL_BIN", "mysql"))
    parser.add_argument("-u", "--user", default="root")
    parser.add_argument("-p", "--password", action="store_true", help="Prompt for a password")
    parser.add_argument("--socket")
    parser.add_argument("--host")
    parser.add_argument("--port", type=int)
    parser.add_argument("--migrate", action="store_true", help="Upgrade an existing database; never load sample data/tests")
    parser.add_argument("--baseline", action="store_true", help="Verify/register an unversioned database before upgrading")
    parser.add_argument("--target-version", type=int, help="Stop at this migration version (default: latest)")
    parser.add_argument("--log-dir", type=Path, help="Build log directory (default: repository logs/)")
    args = parser.parse_args(argv)

    if not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", args.database):
        parser.error("Database names must use lowercase letters, digits, and underscores (max 64)")
    if args.dev_reset and not re.fullmatch(r"vsm_dev_[a-z0-9_]+", args.database):
        parser.error("--dev-reset is development-only and requires a vsm_dev_* database")

    if args.migrate and (args.dev_reset or args.with_demo_accounts):
        parser.error("--migrate cannot reset a database or provision demo accounts")
    if args.baseline and not args.migrate:
        parser.error("--baseline is only valid with --migrate")

    root = Path(__file__).resolve().parent.parent
    log = None
    status = "FAILED"
    try:
        log = RunLog(args.log_dir or root / "logs")
        log.write(f"MODE: {'migrate' if args.migrate else 'build'}; DATABASE: {args.database}")
        sha, dirty = source_revision(root)
        log.write(f"SOURCE COMMIT: {sha}; WORKTREE DIRTY: {str(dirty).lower()}")
        inputs = load_inputs(root / "sql")
        migrations, snapshot = load_migrations(root / "sql", inputs)
        if args.target_version is not None and args.target_version not in [m[0] for m in migrations]:
            raise ValueError("Target version is not in sql/build.sql")
        sql = load_build(root / "sql", args.database, args.with_demo_accounts, inputs)
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
        if args.password:
            env["MYSQL_PWD"] = getpass.getpass("MySQL password: ")

        with Session(client, env, log) as session:
            verify_environment(session, client_version, log)
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
                    names = ", ".join(f"'{name}'" for name in DEMO_PRINCIPALS)
                    collisions = session.run(f"SELECT User, Host FROM mysql.user WHERE User IN ({names});")
                    if collisions:
                        raise ValueError("Refusing demo provisioning: existing users/roles would collide:\n" + collisions)
                if args.dev_reset:
                    log.write(f"OPERATION DEVELOPMENT RESET: {args.database}")
                    sql = f"DROP DATABASE IF EXISTS `{args.database}`;\n" + sql
                # CREATE without IF NOT EXISTS also guards concurrent creators.
                log.write(f"Building {args.database}")
                session.run(sql, echo=True)
                log.write("DATABASE TEST SUITE: PASS (see individual results and summary above)")
            run_migrations(session, client, env, log, args.database, inputs, migrations, snapshot,
                           sha, dirty, baseline=(not args.migrate or args.baseline), target=args.target_version)
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
