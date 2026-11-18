#!/usr/bin/env python3
"""Explicit account provisioning, separate from the canonical database build."""

import argparse
import getpass
import os
import re
import subprocess

from database import BUILD_SQL_MODE
from migrate import literal


SCHEMA_PRIVILEGES = ("SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, REFERENCES, INDEX, ALTER, "
                     "CREATE TEMPORARY TABLES, EXECUTE, CREATE VIEW, SHOW VIEW, "
                     "CREATE ROUTINE, ALTER ROUTINE, TRIGGER")
METADATA_COLUMNS = {
    "tables_priv": "User, Host, Db, Table_name",
    "procs_priv": "User, Host, Db, Routine_name, Proc_priv",
}
DEVELOPER = "'vsm_developer'@'localhost'"
ADMIN = "'vsm_admin'@'localhost'"


def database_scope(database, partial_revokes=False):
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", database):
        raise ValueError("Invalid database name")
    # Database-level GRANT names are patterns even inside backticks.
    return database if partial_revokes else database.replace("_", r"\_")


def bootstrap_admin(password, databases=(), *, test_namespace=False, lock_root=False,
                    legacy_routine_inspection=False):
    """SQL for one initial root connection; it creates no developer or business data."""
    scopes = [database_scope(name) for name in databases]
    if test_namespace:
        scopes.append(r"vsm\_%")
    if not scopes:
        raise ValueError("Explicit database scopes are required")
    statements = [f"CREATE USER {ADMIN} IDENTIFIED BY {literal(password)};",
                  f"GRANT CREATE USER, ROLE_ADMIN ON *.* TO {ADMIN};"]
    if test_namespace:
        # Only negative environment-preflight tests change server variables.
        statements.append(f"GRANT SYSTEM_VARIABLES_ADMIN ON *.* TO {ADMIN};")
    if legacy_routine_inspection:
        statements.append(f"GRANT SHOW_ROUTINE ON *.* TO {ADMIN};")
    for scope in scopes:
        statements.append(f"GRANT {SCHEMA_PRIVILEGES} ON `{scope}`.* TO {ADMIN} WITH GRANT OPTION;")
    for table, columns in METADATA_COLUMNS.items():
        statements.append(f"GRANT SELECT ({columns}) ON mysql.{table} TO {ADMIN} WITH GRANT OPTION;")
    statements.append(f"GRANT SELECT (User, Host) ON mysql.user TO {ADMIN};")
    if lock_root:
        statements.append("ALTER USER 'root'@'localhost' ACCOUNT LOCK;")
    return "\n".join(statements)


def create_developer(password):
    statements = [f"CREATE USER {DEVELOPER} IDENTIFIED BY {literal(password)};"]
    for table, columns in METADATA_COLUMNS.items():
        statements.append(f"GRANT SELECT ({columns}) ON mysql.{table} TO {DEVELOPER};")
    return "\n".join(statements)


def grant_developer_schema(database, partial_revokes=False):
    scope = database_scope(database, partial_revokes)
    return f"GRANT {SCHEMA_PRIVILEGES} ON `{scope}`.* TO {DEVELOPER};"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mysql", default=os.environ.get("MYSQL_BIN", "mysql"))
    parser.add_argument("--socket", required=True, help="Explicit socket of the selected server")
    parser.add_argument("--database", action="append", required=True,
                        help="Exact schema to authorize; repeat for multiple schemas")
    parser.add_argument("--bootstrap-admin", action="store_true",
                        help="One initial root connection to create vsm_admin only")
    parser.add_argument("--create-developer", action="store_true",
                        help="Create vsm_developer; existing account names are refused")
    parser.add_argument("--legacy-routine-inspection", action="store_true",
                        help="Bootstrap admin with SHOW_ROUTINE to verify schemas owned by another definer (MySQL 8.0.20+)")
    args = parser.parse_args()
    try:
        for name in args.database:
            database_scope(name)
        if args.bootstrap_admin and args.create_developer:
            parser.error("Create the developer in a separate vsm_admin invocation")
        if args.legacy_routine_inspection and not args.bootstrap_admin:
            parser.error("--legacy-routine-inspection is an initial admin-bootstrap option")
        user = "root" if args.bootstrap_admin else "vsm_admin"
        env = os.environ.copy()
        env["MYSQL_PWD"] = getpass.getpass(f"{user} connection password: ")
        command = [args.mysql, "--no-defaults", "--protocol=SOCKET", f"--socket={args.socket}",
                   f"--user={user}", "--batch", "--raw", "--skip-column-names", "--skip-force"]
        # Escaped schema patterns have different semantics when partial_revokes is ON.
        probe = subprocess.run(command, env=env, input="SELECT @@partial_revokes; SELECT VERSION();", text=True,
                               capture_output=True, check=True)
        settings = probe.stdout.splitlines()
        partial = settings[0] == "1"
        if args.legacy_routine_inspection and tuple(map(int, re.match(r"(\d+)\.(\d+)\.(\d+)", settings[1]).groups())) < (8, 0, 20):
            raise ValueError("Legacy routine inspection requires MySQL 8.0.20+ SHOW_ROUTINE")
        if args.bootstrap_admin:
            if partial:
                raise ValueError("Bootstrap requires partial_revokes=OFF; see account provisioning documentation")
            sql = bootstrap_admin(getpass.getpass("New vsm_admin password: "), args.database,
                                  legacy_routine_inspection=args.legacy_routine_inspection)
        else:
            sql = create_developer(getpass.getpass("New vsm_developer password: ")) if args.create_developer else ""
            sql += "\n" + "\n".join(grant_developer_schema(name, partial) for name in args.database)
        subprocess.run(command, env=env, input=f"SET SESSION sql_mode = '{BUILD_SQL_MODE}';\n" + sql,
                       text=True, check=True)
        print(f"Account provisioning completed as {user}")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Account provisioning failed: {error}\n")


if __name__ == "__main__":
    main()
