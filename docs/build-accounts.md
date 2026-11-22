# Build and test accounts

`scripts/build.py` remains the single build/migration entry point, and `sql/build.sql` remains its ordered manifest. `scripts/accounts.py` is an explicit provisioning utility; it does not build or migrate business schemas. No provisioning runs against the installed project server in automated tests.

## Responsibilities and privileges

| Account | Responsibility | Assigned privileges |
| --- | --- | --- |
| `vsm_developer@localhost` | Schema creation/reset, schema migrations, sample/test data, SQL assertions, schema fingerprints, migration-history updates | On each explicitly approved schema: SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, REFERENCES, INDEX, ALTER, CREATE TEMPORARY TABLES, EXECUTE, CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, TRIGGER. No permanent GRANT OPTION. |
| `vsm_admin@localhost` | Create/manage accounts and roles, assign scoped privileges, optional demo provisioning, temporary legacy routine grant authority | CREATE USER and ROLE_ADMIN globally; the same schema privileges WITH GRANT OPTION on approved schemas. Only the metadata column reads listed below. Optional SHOW_ROUTINE for legacy-definer inspection. The private test harness additionally grants SYSTEM_VARIABLES_ADMIN solely for environment-preflight tests. |
| Named business users and application services | Ordinary application operations | Existing restricted role/view/procedure grants, unchanged. Services remain EXECUTE-only in the reference/identity examples. |
| Root | Initial provisioning of `vsm_admin` on a newly initialized private server | Used only by the explicit bootstrap utility path or test-server startup. The harness locks root at the end of that initial connection. |

Developer grants use exact schema names, including escaped underscores when MySQL interprets database grants as patterns. There is no `*.*` data/DDL grant, wildcard development-schema grant, CREATE USER, ROLE_ADMIN, SUPER, FILE, PROCESS, CONNECTION_ADMIN, SYSTEM_VARIABLES_ADMIN, SET_ANY_DEFINER, or global SHOW_ROUTINE on the developer. It cannot delegate schema privileges. A physical schema owner can alter its schema and guards, so it is a trusted development account, never an application login.

MySQL account/role administration is inherently server-scoped. `vsm_admin` is trusted with these operations; its CREATE USER/ROLE_ADMIN rights cannot be restricted to a username prefix. The optional demo path still refuses existing principal names and never resets unrelated accounts. Neither account receives mysql-table write permissions, password-hash reads, global data access, SUPER, FILE, or arbitrary definer privileges. The admin's schema grants are exact names in the provisioning CLI; only the private harness authorizes its admin for the escaped `vsm\_%` test namespace so it can provision newly generated test schemas. Each developer grant is still exact.

## Required privilege-metadata reads

The unchanged baseline test and migrations require these SELECT columns:

- `mysql.tables_priv`: User, Host, Db, Table_name (baseline role/view check and migration 003 reference-reader recipients).
- `mysql.procs_priv`: User, Host, Db, Routine_name, Proc_priv (migrations 004 and 006 capture and restore existing native routine grants).

Both accounts receive only these columns. The admin can delegate those column reads when provisioning the developer. The admin additionally reads `mysql.user(User, Host)` to detect demo-account collisions; the developer has no mysql.user read access. These legacy queries necessarily expose grant-recipient metadata across the server, not business data or credential hashes. No broad `SELECT ON mysql.*` is granted to make arbitrary `SHOW GRANTS FOR other_account` commands work. Named users can inspect their own grants. See [MySQL GRANT semantics](https://dev.mysql.com/doc/refman/8.0/en/grant.html).

## Provision a chosen disposable server

Start a separate private MySQL instance with a new data directory, `--skip-networking`, `--mysqlx=OFF`, and its own socket. For a test server without replication, `--skip-log-bin` avoids elevated stored-function/trigger creation requirements. The automated harness does all this itself.

These commands explicitly select that socket. They never discover or connect to an installed server. Choose all intended exact schemas during bootstrap; repeat `--database` as needed. Commands work from any directory when the script path is absolute.

```bash
DEV_SOCKET=/absolute/path/to/private/mysql.sock

# Initial root exception: create vsm_admin and assign its bounded privileges.
# Prompts for the initial root password and a new admin password.
python3 scripts/accounts.py --mysql /usr/local/mysql/bin/mysql \
    --socket "$DEV_SOCKET" --database vsm_dev_example --bootstrap-admin

# Separate administrative operation: create the developer and authorize this schema.
# Prompts for the admin connection password and a new developer password.
python3 scripts/accounts.py --mysql /usr/local/mysql/bin/mysql \
    --socket "$DEV_SOCKET" --database vsm_dev_example --create-developer

# Routine build: schema/data/tests/migrations execute as vsm_developer.
# A separate admin connection services only the immutable routine-GRANT helpers.
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql \
    --socket "$DEV_SOCKET" --database vsm_dev_example -p --admin-password

# Upgrade using the same developer entry point; never reload business data.
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql \
    --socket "$DEV_SOCKET" --database vsm_dev_example --migrate -p --admin-password
```

Existing account names are refused when creating an account; no password or grants are silently reset. To authorize an additional schema that was already within the admin's initial scope, rerun `accounts.py --database ...` without either creation flag. Bootstrap currently requires `partial_revokes=OFF` to make the escaped initial scopes unambiguous; later developer grants also support exact names when partial revokes is enabled. Invalid names are rejected before connection.

The default build identity is `vsm_developer`, the default administrative identity is `vsm_admin`. Explicit root identities are rejected by the build parser, and the connected authenticated identity is checked too. There is no fallback account. Use `-p` and `--admin-password` for separate prompts. For automation, `MYSQL_PWD` is the developer password and `VSM_ADMIN_PASSWORD` is the admin password; the latter is removed from developer client environments and the developer password is never reused for admin authentication. Passwords are not logged or passed on command lines.

Baseline builds through version 2 without demo accounts, ordinary additive migrations without privilege statements, and already-current migrations do not open an admin connection when the developer owns the routine definitions. Legacy-definer metadata verification may need admin read access as described below. `--with-demo-accounts` runs only manifest file 08 as admin, after collision checks and before the original SQL tests. All other build files and migration/history operations run as developer. Logs identify the actual session and authenticated account, admin operations, and temporary grant cleanup.

Migration 005 adds a separate admin-only grant step after its developer-owned temporal DDL: SELECT on `vw_AuditTrail` and EXECUTE on `sp_ListAuditTrail` go only to an existing `role_manager` already granted access to `AuditLog` in that database. A basic grant on another table is insufficient. This step uses the admin's existing scoped grant privileges, adds no temporary or permanent developer grant authority, and never grants history/event/context DML to application roles. The internal writer has no application EXECUTE grant. See [temporal history](temporal-audit.md) for the history guards and explicit system-only attribution for physical maintenance accounts.

## Immutable migration exceptions

Migration 003 calls `sp_GrantReferenceReaders`; migration 004 calls `sp_RestorePublicRoutineGrants`; migration 006 calls `sp_RestoreErrorRoutineGrants`. They execute with the developer definer's privileges, and migrations 004 and 006 rely on temporary grant-snapshot tables in that same connection. Moving the entire migration to an admin session would change its owner and violate the account boundary; granting schema-level GRANT OPTION would allow delegation of every held schema privilege.

Instead the runner executes the unchanged SQL up to the existing helper call, and the admin temporarily grants the developer routine-level GRANT OPTION with:

- EXECUTE on `sp_ListIndicatorValues` for migration 003.
- EXECUTE and ALTER ROUTINE on `sp_CreateServiceAppointment` and `sp_CompleteRepair` for migration 004.
- EXECUTE and ALTER ROUTINE on `sp_ListIndicatorValues`, `sp_ValidateIndicator`, `sp_ResolveActor`, `sp_CreateServiceAppointment`, `sp_CompleteRepair`, and `sp_ListAuditTrail` for migration 006. These six procedures are recreated to assign stable error numbers and retain their native grants; internal procedures acquire no new application grants.

The developer runs the helper CALL, then the admin immediately restores the developer's prior routine grants before the remaining SQL runs. Existing recipients' EXECUTE/ALTER ROUTINE privileges and grant options are restored by the migration. No database/global GRANT OPTION is given to the developer. Applied migration files, complete-file checksums, ordering, and durable failure states are unchanged. Migration 006 adds no account privileges beyond this existing temporary, routine-scoped mechanism.

On ordinary errors and KeyboardInterrupt, a `finally` block removes this temporary authority. An OS kill or loss of the administrative connection during the short helper call can prevent cleanup. The database remains an interrupted/failed migration and must not be automatically retried. Before the existing manual backup/recovery process, reconnect as admin, inspect `mysql.procs_priv` for the developer on every routine listed for the interrupted migration, and revoke any unexpected GRANT OPTION. For example, after confirming the routine exists and no prior grant option was intended:

```sql
REVOKE GRANT OPTION ON PROCEDURE vsm_dev_example.sp_CompleteRepair
FROM 'vsm_developer'@'localhost';
```

Do not erase failed history/checksums or grant blanket privileges to get past a failure. Admin authentication is checked before fresh-build DDL or starting a migration that needs these exceptions.

Before migrations that recreate routines, retain a native routine-grant inventory as well as the database backup. Dropping a routine removes its routine-level grants; the in-session temporary snapshot cannot recover them after connection loss. Manual recovery must restore those original grants separately after restoring the schema. See [error-handling.md](error-handling.md) for migration 006 precautions.

## Other administrative boundaries

With binary logging enabled, MySQL requires extra authority for creating stored functions/triggers unless `log_bin_trust_function_creators=ON`. The runner checks this before DDL. It does not give the developer SUPER or change globals. A server operator must approve that setting in the disposable server configuration. A regression server with binary logging explicitly tests rejection first, then approval by its admin. See [MySQL stored-program binary logging](https://dev.mysql.com/doc/refman/8.4/en/stored-programs-logging.html).

Schema inspection requires visible routine definitions. Routines created by the developer are visible without global privileges. For legacy objects owned by another definer, MySQL may hide their bodies even with schema ALTER ROUTINE/EXECUTE. If such upgrades are needed, choose `--legacy-routine-inspection` during the initial `--bootstrap-admin` invocation (MySQL 8.0.20+). This explicitly gives only the admin global SHOW_ROUTINE, without grant option. MySQL offers no schema-level version of that read permission. The runner first inspects as developer and, only for hidden routine bodies, logs an administrative metadata query restricted to the selected schema. All migration SQL and history writes still execute as developer; the developer never receives global SHOW_ROUTINE. Without approved inspection access, verification fails closed rather than hashing hidden/NULL bodies. A regression upgrade from a different ordinary definer verifies data preservation and this account boundary. See [MySQL routine metadata visibility](https://dev.mysql.com/doc/refman/8.0/en/information-schema-routines-table.html).

Existing objects whose definer has SYSTEM_USER (commonly older root-created objects) can also require that security class to replace/drop. Neither setup account receives SYSTEM_USER or arbitrary-definer privileges. Those objects require a reviewed ownership handoff by the server owner before routine developer upgrades; this change does not silently reassign definers, broaden privileges, skip verification, or connect as root to bypass a refusal. The installed project database was not inspected or changed.

The startup bootstrap and explicit `accounts.py --bootstrap-admin` path are the only executable root connections. The test harness invokes the former once successfully per new server, locks root, provisions the developer as admin, and uses developer/admin/business logins thereafter. Server cleanup terminates its own OS process; no root SQL shutdown is used. Historical baseline comments and captured performance output mentioning root remain unchanged historical evidence, not current execution instructions. Negative tests mentioning a root DEFINER attempt to create one as developer and verify rejection; they never connect as root.

## Verification

```bash
python3 -B -m unittest discover -s tests -v
```

All servers, accounts, credentials, database scopes, and test data are disposable. Existing restricted-user authorization tests remain. Added checks cover real developer builds/migrations and object definers, exact schema boundaries, denied account and privilege operations, limited metadata visibility, no fallback on invalid credentials, admin-only provisioning, preservation of routine grants and business data, temporary-authority cleanup on failure, and binary-logging preflight. No test uses the installed project's server.
