#!/usr/bin/env python3
"""Safely execute the SQL build; reset only explicitly disposable dev databases."""

import argparse
import getpass
import os
from pathlib import Path
import re
import subprocess
import sys


PROJECT_DATABASE = "vehicle_service_maintenance"
DEMO_FILE = "08_demo_accounts.sql"
DEMO_PRINCIPALS = (
    "role_service_advisor", "role_technician", "role_manager",
    "sa_amy", "tech_ben", "mgr_mike",
)


def load_build(sql_dir, database, with_demo_accounts):
    """Read every input before connecting, and flatten SOURCE into one batch."""
    manifest = (sql_dir / "build.sql").read_text()
    names = re.findall(r"^SOURCE\s+([0-9]{2}_[a-z_]+\.sql)\s*$", manifest, re.MULTILINE)
    if not names or len(names) != len(set(names)):
        raise ValueError("Build input list is empty or contains duplicates")
    source_lines = re.findall(r"^SOURCE\b.*$", manifest, re.MULTILINE)
    if len(source_lines) != len(names):
        raise ValueError("Invalid SOURCE entry in sql/build.sql")
    chunks = [f"SET @build_with_demo_accounts = {int(with_demo_accounts)};\n"]
    for name in names:
        sql = (sql_dir / name).read_text()  # Missing inputs fail before any DDL.
        if re.search(r"^\s*SOURCE\b", sql, re.MULTILINE | re.IGNORECASE):
            raise ValueError(f"Nested SOURCE is not supported: {name}")
        if name == DEMO_FILE and not with_demo_accounts:
            continue
        sql = re.sub(r"\b" + PROJECT_DATABASE + r"\b", database, sql)
        chunks.append(f"\n-- Build input: {name}\n{sql}\n")
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
    args = parser.parse_args(argv)

    if not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", args.database):
        parser.error("Database names must use lowercase letters, digits, and underscores (max 64)")
    if args.dev_reset and not re.fullmatch(r"vsm_dev_[a-z0-9_]+", args.database):
        parser.error("--dev-reset is development-only and requires a vsm_dev_* database")

    try:
        sql_dir = Path(__file__).resolve().parent.parent / "sql"
        sql = load_build(sql_dir, args.database, args.with_demo_accounts)
        # Keep client option files from enabling --force or selecting another server.
        client = [args.mysql, "--no-defaults", "--batch", "--raw", "--skip-column-names",
                  "--skip-force", "--skip-reconnect", f"--user={args.user}"]
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

        def query(statement):
            result = subprocess.run(client, input=statement, text=True, env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode:
                raise RuntimeError(result.stderr.strip() or "MySQL preflight failed")
            return result.stdout.strip()

        exists = query("SELECT COUNT(*) FROM information_schema.SCHEMATA "
                       f"WHERE SCHEMA_NAME = '{args.database}';")
        if exists != "0" and not args.dev_reset:
            raise ValueError(f"Refusing existing database '{args.database}'; contents were not changed")

        if args.with_demo_accounts:
            names = ", ".join(f"'{name}'" for name in DEMO_PRINCIPALS)
            collisions = query(f"SELECT User, Host FROM mysql.user WHERE User IN ({names});")
            if collisions:
                raise ValueError("Refusing demo provisioning: existing users/roles would collide:\n"
                                 + collisions)

        if args.dev_reset:
            sql = f"DROP DATABASE IF EXISTS `{args.database}`;\n" + sql
        # CREATE DATABASE deliberately has no IF NOT EXISTS, closing the race
        # between the preflight and another build creating the same database.
        print(f"Building {args.database}" + (" (DEVELOPMENT RESET)" if args.dev_reset else ""), flush=True)
        result = subprocess.run(client, input=sql, text=True, env=env)
        if result.returncode:
            print("Build failed; stopped at the first unhandled SQL error. "
                  "A partially built database is retained for inspection.", file=sys.stderr)
            return result.returncode if result.returncode > 0 else 1
        print(f"Build succeeded: {args.database}")
        return 0
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Build refused: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
