# Vehicle Service and Maintenance Management System

A MySQL database for an auto repair shop. It tracks customers, vehicles, service appointments, repairs, parts inventory, repair estimates, and invoices. Business rules are enforced inside the database through constraints, stored procedures, triggers, and role-based privileges, and every important change is written to an append-only audit log.

Rutgers University, 01:198:437 Database Systems, Fall 2026.

## Repository Contents

```
README.md                  This file
docs/
  tdd.md                   Technical Design Document
  FRD.md                   Functional Requirements Document
  build-accounts.md        Detailed account privileges and provisioning reference
  temporal-audit.md        Temporal history, audit reader, and coverage reference
  error-handling.md        Stable error codes, diagnostics, and caller/retry contract
  vehicle-service-erd.drawio  Data model / ER diagram (draw.io)
  vehicle-service-erd.svg  Data model / ER diagram (svg)
  erd.md                   ER diagram explanation
  performance/             Performance analysis and optimization records
sql/
  build.sql                Ordered inputs for the safe build runner
  01_schema.sql            Database, tables, keys, CHECK constraints
  02_indexes.sql           Secondary indexes
  03_views_reports.sql     Views and report queries (RQ-01 to RQ-06)
  04_procedures.sql        sp_CreateServiceAppointment, sp_CompleteRepair
  05_triggers_roles.sql    Audit and validation triggers
  06_sample_data.sql       Sample data
  07_tests.sql             Automated test suite
  08_demo_accounts.sql     Optional demo roles and accounts
scripts/build.py           Safe, fail-fast build runner
scripts/database.py        MySQL session, preflight checks, and timestamped logging
scripts/migrate.py         Ordered migration and schema verification helpers
scripts/accounts.py        Explicit bootstrap and administrator account provisioning
scripts/generate_temporal_history.py  Development-only generator for frozen migration 005
scripts/error_contract.py   Explicit error identifiers and offline migration mapping
scripts/generate_standardized_errors.py  Development-only recipe for migration 006
sql/09_schema_migrations.sql  Migration history table
sql/migrations/            Baseline and ordered upgrades through reference/identity metadata
tests/test_build.py        Build and migration regression tests
tests/test_build_accounts.py  Developer/admin separation and denied-operation tests
tests/test_reference_identity.py  Reference, actor, and provenance regressions
tests/test_temporal_history.py  Temporal versions, audit coverage, and pagination regressions
tests/test_error_handling.py  Error contracts, native failures, and upgrade regressions
tests/mysql_test_support.py  Shared private disposable MySQL server harness
```

## Prerequisites

| Requirement               | Version / Notes                                                                                 |
| ------------------------- | ----------------------------------------------------------------------------------------------- |
| MySQL Server              | MySQL 8.0.18 or later; tested on MySQL Community Server 26.7.0. |
| MySQL command-line client | MySQL 8.0.18 or later, with a successful connection to the selected server; MariaDB is refused. On macOS: `/usr/local/mysql/bin/mysql`. |
| Python                    | 3.9 or later, for the build runner and build regression tests.                                |
| Git                       | Any recent version                                                                              |
| Platform                  | Developed and tested on macOS. Any OS that runs MySQL 8 works.                                  |
| Accounts                  | Schema-scoped `vsm_developer` for builds/migrations; separate `vsm_admin` for provisioning and temporary routine permissions. See [account setup](docs/build-accounts.md). |

MySQL Workbench is optional and is only used for viewing results.

## Build From the Repository

### 1. Get the files

After these changes are committed and available in Git, clone the repository and replace `YOUR_RELEASE_COMMIT` with that exact commit:

```bash
git clone https://github.com/steslic/vehicle-service-maintenance-system.git
cd vehicle-service-maintenance-system
git checkout --detach YOUR_RELEASE_COMMIT
git rev-parse HEAD
git status --porcelain  # must be empty for clean-clone evidence
```

### 2. Select the server and provision setup accounts

The MySQL server must already be running. Select its Unix socket using the path in that instance's `--socket` startup option or server configuration. For development, use a private, disposable server with its own data directory and socket; do not select the installed project server accidentally. Replace the path below with the intended server's actual absolute socket path, choose the schema name, and keep these variables in the same terminal for the following commands:

```bash
DEV_SOCKET=/absolute/path/to/intended/mysql.sock
VSM_DATABASE=vehicle_service_maintenance
```

The examples use `/usr/local/mysql/bin/mysql`; substitute your installed client path if different. See [build-accounts.md](docs/build-accounts.md) for private-server settings, exact privileges, and legacy-definer administrative exceptions. If you only want to run automated regression tests, skip manual account provisioning and follow [Build regression tests](#build-regression-tests).

First, authenticate as the selected server's existing root account to create `vsm_admin` and authorize it for the intended schema:

```bash
python3 scripts/accounts.py --mysql /usr/local/mysql/bin/mysql \
    --socket "$DEV_SOCKET" --database "$VSM_DATABASE" --bootstrap-admin
```

At `root connection password:`, enter the **existing root password for that server**. For a freshly initialized disposable server configured with an empty root password, press Enter at this prompt. At `New vsm_admin password:`, **choose a new password for the new administrative account** and retain it for later steps. This command does not change the root password or create the business database. Root is used only for this initial administrative provisioning.

Next, authenticate as the newly created administrator to create `vsm_developer` and grant its schema permissions:

```bash
python3 scripts/accounts.py --mysql /usr/local/mysql/bin/mysql \
    --socket "$DEV_SOCKET" --database "$VSM_DATABASE" --create-developer
```

At `vsm_admin connection password:`, enter the **admin password created in the preceding command**. At `New vsm_developer password:`, **choose a new, separate developer password** and retain it for builds and migrations.

Account creation is required **once per MySQL server**, not for each clone, build, or migration. On an already provisioned server, use the existing credentials and skip both account-creation commands; existing account names are refused rather than overwritten. Additional schemas need additional authorization. The admin must have authority for each exact schema: include all known intended schemas with repeated `--database` options during initial admin bootstrap, or have the server owner approve an additional scope before granting it to the developer. Then authorize the existing developer without a creation flag:

```bash
# Later, only after vsm_admin has authority for this additional schema:
ADDITIONAL_DATABASE=vsm_dev_upgrade
python3 scripts/accounts.py --mysql /usr/local/mysql/bin/mysql \
    --socket "$DEV_SOCKET" --database "$ADDITIONAL_DATABASE"
```

This later command asks only for the **existing admin password**; it creates no account or password. The optional reset, demo, and upgrade examples below likewise require authorization for their named schemas.

### 3. Build the database, load the data, and run the tests

```bash
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql \
    --socket "$DEV_SOCKET" --database "$VSM_DATABASE" \
    -u vsm_developer -p --admin-user vsm_admin --admin-password
```

At `MySQL password:`, enter the **existing developer password from step 2**. If administrative work is required, `Administrative MySQL password:` asks for the **existing admin password from step 2**. The standard command above creates no account passwords; optional demo-account creation is a separate opt-in below. The developer performs schema/data/test operations; the separate admin connection performs optional demo provisioning, temporary routine grants required by migrations 003, 004, and 006, and the scoped audit-reader grants in migration 005. The build defaults to these two account names, refuses root, and never falls back to another account.

Run the command with the absolute path to `scripts/build.py` if your shell is in another directory. SQL paths, Git metadata, and the default log directory are resolved relative to the checkout, not the shell directory.

The runner refuses an existing database with the selected name and leaves its business data and audit history unchanged. It validates every manifest input and migration checksum before executing SQL, then runs the existing schema/data/test batch with continue-on-error disabled. Verified migrations follow on the same connection. Missing files, SQL errors, and failed test suites produce a nonzero exit code. A failed build retains its partial database for inspection; it is never silently deleted or reused.

Schema creation, sample data, SQL assertions, migrations, and failure-history updates use the developer session. The optional `08_demo_accounts.sql` file alone uses the admin session, while retaining its position in the same manifest. Build logs identify both authenticated accounts and the temporary routine-authority grants and cleanup. Previously applied migration files and checksums are unchanged.

### 4. Apply later migrations to an existing database

When new numbered migrations are available, upgrade the same selected schema instead of building it again:

```bash
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql \
    --socket "$DEV_SOCKET" --database "$VSM_DATABASE" --migrate \
    -u vsm_developer -p --admin-user vsm_admin --admin-password
```

Enter the **existing developer password**, then the **existing admin password if prompted**. Migration does not create accounts or passwords and never reloads sample data or runs data-changing SQL acceptance tests. A fresh build already applies all migrations through version 006; running this command immediately afterward verifies the schema and makes no changes. Baseline builds through version 002 without demo accounts and already-current migrations with developer-owned routines need no admin connection, so the admin prompt is not shown. Legacy-definer metadata inspection may require the admin as explained in [the technical reference](docs/build-accounts.md).

### Build manifest

`sql/build.sql` lists the files in execution order:

| Step | File                    | What it creates                                      |
| ---- | ----------------------- | ---------------------------------------------------- |
| 1    | `01_schema.sql`         | A new database and all 13 tables                      |
| 2    | `02_indexes.sql`        | Secondary indexes                                    |
| 3    | `03_views_reports.sql`  | Views and report queries                             |
| 4    | `04_procedures.sql`     | Stored procedures                                    |
| 5    | `05_triggers_roles.sql` | Audit and validation triggers                        |
| 6    | `06_sample_data.sql`    | Sample data                                          |
| 7    | `08_demo_accounts.sql`  | Demo roles/accounts, only with `--with-demo-accounts` |
| 8    | `07_tests.sql`          | Existing automated tests and a failure gate           |
| 9    | `09_schema_migrations.sql` | History table after baseline verification         |
| 10   | `migrations/001_baseline.sql` | Register the baseline and object versions       |
| 11   | `migrations/002_customer_name_index.sql` | Add a customer-name index             |
| 12   | `migrations/003_indicator_values.sql` | Reference catalog, domain bindings, dropdowns/report labels |
| 13   | `migrations/004_session_identity_and_provenance.sql` | Verified actors and provenance guards |
| 14   | `migrations/005_temporal_history.sql` | Mirrored temporal history, complete data-change coverage, and paginated audit reader |
| 15   | `migrations/006_standardized_error_handling.sql` | Stable error contract and original rejection diagnostics |

Use the runner instead of piping `build.sql` or concatenating SQL files into the client. Direct execution of `build.sql` raises an error directing you to the runner.

### Environment checks and logs

Before database creation, reset, or migration, the runner checks the client/server versions and requires InnoDB, `REPEATABLE-READ`, autocommit, foreign-key checks, unique checks, a writable server, and `innodb_flush_log_at_trx_commit = 1` for durable migration checkpoints. SQL mode must include `STRICT_TRANS_TABLES` and `NO_ENGINE_SUBSTITUTION`, with `ANSI_QUOTES` and `NO_BACKSLASH_ESCAPES` disabled. After these checks, it pins the session SQL mode to `ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION`, so stored-object definitions are reproducible. The connection uses `utf8mb4`; new databases use `utf8mb4_0900_ai_ci`; operation timestamps use a UTC session. Existing databases are checked against their recorded object definitions.

When binary logging is enabled, routine/trigger creation also requires administrator-approved `log_bin_trust_function_creators=ON`. The runner refuses an incompatible configuration before DDL; it never requests SUPER or changes server globals itself. Private regression servers normally disable binary logging; a separate test verifies the enabled case.

Every run writes `logs/<UTC timestamp>-<process ID>-build.log`, including refusals and SQL/test failures. The log records the source Git SHA, dirty-worktree flag, MySQL client/server/settings, executed SQL filenames and checksums, existing test results, migration operations, schema version, and final `SUCCESS`, `FAILED`, or `INTERRUPTED` status. An abrupt process/server death can leave no final status; the durable migration history then identifies unfinished work. Passwords are not placed in commands or logs.

`--log-dir /absolute/path` selects another log directory. Logs are ignored by Git by default; retain a chosen clean-clone run as submission evidence. A dirty-worktree log identifies the base commit but does not claim the uncommitted changes are reproducible from that SHA. No release tag or commit is created by the runner.

### Explicit development resets

Only disposable databases whose names begin with `vsm_dev_` can be reset:

```bash
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u vsm_developer -p --admin-password \
    --socket "$DEV_SOCKET" --database vsm_dev_local --dev-reset
```

`--dev-reset` deletes all business and audit data in that named development database. It is refused for `vehicle_service_maintenance` and every other non-development name. Without the flag, even an existing `vsm_dev_*` database is protected. Database resets never reset users or roles.

### Optional demo accounts

Server-wide demo roles and accounts are excluded by default. To provision them on a disposable server where those names are unused:

```bash
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u vsm_developer -p --admin-password \
    --socket "$DEV_SOCKET" --database vsm_dev_demo --with-demo-accounts
```

Provisioning refuses any existing demo username or role before creating or resetting a database. It never drops accounts, changes existing passwords, or adds grants to existing principals. Repeating a demo build on the same server therefore requires separately managing its demo principals or using a fresh disposable server.

The default build reports **65 PASS, 1 SKIP**: T-49 inspects demo-role grants and is explicitly skipped when provisioning is disabled. With `--with-demo-accounts`, all **66 existing automated checks** run. T-11 remains available as a separate login demonstration; the regression suite also executes its six original permission cases using real logins. Test failures are printed with their diagnostics before the failure gate aborts the build.

### Schema versions and non-destructive upgrades

Use the same entry point for builds and migrations. `--migrate` never runs the destructive build, sample-data loader, demo provisioning, or data-changing test suite.

To demonstrate an upgrade on a new disposable database:

```bash
# Build the current baseline (version 1), including the existing database tests.
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u vsm_developer -p --admin-password \
    --socket "$DEV_SOCKET" --database vsm_dev_upgrade --target-version 1

# Upgrade to the latest version (currently 6).
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u vsm_developer -p --admin-password \
    --socket "$DEV_SOCKET" --database vsm_dev_upgrade --migrate

# Repeat: no migration SQL executes again and application timestamps stay unchanged.
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u vsm_developer -p --admin-password \
    --socket "$DEV_SOCKET" --database vsm_dev_upgrade --migrate
```

A normal new build without `--target-version` finishes at the latest manifest version (currently 006). Migrations 001 through 006 must remain immutable once applied; the next new migration is 007. Migrations 003 and 004 add reference/identity metadata and provenance guards; migration 005 adds temporal history; migration 006 adds error codes and nullable rejection diagnostics while retaining existing rows, historical evidence, and lifecycle transitions. See [Reference values, identity, and provenance](docs/reference-and-identity.md), [Temporal history and audit trail](docs/temporal-audit.md), and [Error handling](docs/error-handling.md).

For an **unversioned existing database**, first stop application writes and take a backup. Explicitly request adoption:

```bash
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u vsm_developer -p --admin-password \
    --socket "$DEV_SOCKET" --database "$VSM_DATABASE" --migrate --baseline
```

This compares every business table definition (columns, keys, indexes, checks, engine, collation), view, procedure signature/body/settings, and trigger against `sql/migrations/baseline.json`. Data and AUTO_INCREMENT counters are excluded, and creator/definer account names can vary. Any missing, extra, or changed object prevents registration before any metadata DDL. Existing metadata without a valid history is also refused. The snapshot is bound by a SHA-256 digest in the baseline migration; the history-table DDL is bound the same way. Do not regenerate the snapshot to bypass a mismatch: investigate the schema difference. `--target-version 1` can register a verified baseline without applying later upgrades.

For inspection, connect to the chosen database and run:

```sql
SELECT version, filename, checksum, started_at, applied_at,
       source_commit_sha, source_dirty, status, error_message
FROM schema_migrations ORDER BY version;

SELECT object_type, object_name, migration_version,
       definition_checksum, source_commit_sha, source_dirty
FROM schema_object_versions ORDER BY object_type, object_name;
```

The first table records migration versions, exact file digests, database timestamps, source revisions, and status. The second exposes the last migration that changed each deployed table, view, procedure/function, or trigger. Unchanged objects retain their earlier version. For an adopted database, the source SHA identifies the verified baseline registration, not an invented historical deployment date. Later runs also reject object-definition drift outside migrations.

### Reference values and responsible actors

The latest schema provides `IndicatorValue` and `sp_ListIndicatorValues` for database-backed dropdowns. For example:

```sql
INSERT INTO IndicatorValue (IndicatorName, ValueCode, Description, DisplayOrder)
VALUES ('repair_type', 'Wheel Alignment', 'Wheel alignment and balancing', 25);
CALL sp_ListIndicatorValues('repair_type');
```

Registered people are resolved from the full database session login. A caller-supplied person ID can only assert that identity; service calls need explicit person/operation delegations, and the service should have EXECUTE only. An unmapped administrative connection is no longer an operational acting-user fallback. Audit rows record the session account separately from the responsible person; old session identities remain unknown. Follow the [identity and reference guide](docs/reference-and-identity.md) for direct-user, service-account, and provenance details.

After migration 004, `@app_user_id` is a checked compatibility hint, **not a trusted identity source**. Setting it cannot authenticate a person, impersonate another user, authorize a service delegation, or bypass session identity validation. Public procedures resolve the actor from the registered session and use protected operation context for authorized service calls.

### Temporal history and audit trail

Migration 005 creates a mirrored history table for each of the 12 business tables and five durable reference/security metadata tables. Inserts open versions, real updates close and replace them, and deletes close versions while retaining their data and deletion attribution. No-op updates create no history. Every live record has one current history version; historical rows have no foreign keys back to deletable business records.

Existing rows are initialized as observed snapshots with NULL historical start times and actors, rather than invented creation events. New events record database-owned UTC microsecond times, the actual session, verified person or explicit system-only maintenance attribution, and protected procedure context. History and business changes roll back together. Existing generic AuditLog records, successful operational event counts, rejection handling, and inventory reasons are retained.

The manager audit role can read the denormalized view `vw_AuditTrail` or use the bounded keyset reader:

```sql
CALL sp_ListAuditTrail('Part', JSON_OBJECT('PartID', 1), NULL,
                      NULL, NULL, NULL, 50);
-- Next page: replace 123 with the smallest EventID returned above.
CALL sp_ListAuditTrail('Part', JSON_OBJECT('PartID', 1), NULL,
                      NULL, NULL, 123, 50);
```

Arguments are entity, JSON record key, responsible user, inclusive UTC start, exclusive UTC end, exclusive EventID cursor, and page size (1–200). NULL omits a filter. Results are ordered by EventID descending. The reader selects indexed event IDs before fetching version payloads; native roles receive no direct history-write permissions. No GUI or service is implemented. See [the temporal audit reference](docs/temporal-audit.md) for the complete object inventory, validity semantics, security boundaries, migration precautions, and remaining server-audit limitations.

### Stable errors and rejection diagnostics

Migration 006 assigns stable MySQL application error numbers to validation, forbidden, not-found, conflict, warning, and critical conditions. Native deadlocks and lock timeouts remain errors 1213 and 1205, classified as retryable. Runtime classification never matches human-readable messages. Existing procedure parameters, role grants, trigger order, and verified attribution are preserved.

```sql
-- Developer/authorized diagnostic context; application adapters can implement
-- the same published numeric contract without additional database grants.
SELECT fn_ApplicationErrorID(51001), fn_ErrorClass(51001, '45000', FALSE);
-- VSM_INVALID_APPOINTMENT | validation

SELECT AuditLogID, ApplicationErrorID, ErrorClass, ErrorSQLSTATE,
       ErrorNumber, ErrorMessage, TransactionOutcome, UserID, SessionAccount
FROM AuditLog WHERE Action = 'Rejected' ORDER BY AuditLogID DESC;
```

The two public business procedures capture the original error before cleanup and use bare `RESIGNAL` to preserve it. Earlier audit rows retain NULL diagnostics. Retry the entire business transaction only after its rollback is confirmed, with at most three total attempts and bounded backoff. Unknown commit/connection outcomes require reconciliation before another submission. Nonfatal warnings after a completed operation do not request a replay. See [error-handling.md](docs/error-handling.md) for all 37 identifiers, classifier interfaces, examples, warning handling, upgrade precautions, and remaining rejection-durability/transaction-ownership limits.

### Adding a migration and recovering failures

Keep the baseline SQL and successful migrations immutable. With migrations 001–006 already present, add `007_descriptive_change.sql` next and append `SOURCE migrations/007_descriptive_change.sql` to **the existing `sql/build.sql` manifest**. There is no separate migration manifest. Every SQL migration must be listed exactly once in numeric order; gaps, unlisted files, missing historical files, changed applied checksums, and downgrade targets are refused. Migration SQL uses the database selected by the runner; it must not switch databases or manage accounts. Restore `DELIMITER ;` at the end of routine definitions.

The runner holds a connection-level advisory lock throughout verification and migration, preventing two runners from upgrading the same database concurrently. Before executing each migration, it commits an `applying` history row. Only successful DDL and an atomic object-version/history update produce `applied`. SQL failure records `failed` when the server remains reachable; abrupt termination leaves `applying`. An empty history table indicates interruption during initial setup. All these incomplete states block further migrations and are never automatically replayed.

MySQL DDL implicitly commits, so an index or column created before a later error may remain even though the migration failed. A transaction cannot make a whole multi-statement DDL migration atomic. See the [MySQL implicit-commit rules](https://dev.mysql.com/doc/refman/8.0/en/implicit-commit.html) and [connection-level lock behavior](https://dev.mysql.com/doc/refman/8.0/en/locking-functions.html).

For this course implementation, recovery is deliberately manual: inspect the log, `schema_migrations`, and actual object definitions; restore a verified pre-run backup of the disposable target; fix an unapplied migration if necessary; rerun. Do not delete a failed history row, mark partial DDL as applied, edit an applied checksum, or assume `ROLLBACK` removed DDL. The runner offers no force/repair switch that can silently bless partial changes. Stopping application writes and retaining the backup are part of the upgrade procedure, so restoring it does not discard later user work.

### Build regression tests

```bash
python3 -B -m unittest discover -s tests -v
```

These tests require **no manual account provisioning or password entry**, including when launched from a terminal. They initialize their own temporary MySQL data directories, start private servers with networking disabled, provision their own admin/developer and restricted test accounts, and generate disposable credentials automatically. Root is used only for each private server's initial admin bootstrap and is then locked. The manual account-provisioning commands in step 2 still prompt normally.

The tests connect only through their own temporary Unix sockets; they do not use `DEV_SOCKET`, connect to the installed project server, or require that server's credentials. `MYSQL_BIN` and `MYSQLD_BIN` may select the client/server executable paths. The private servers and their data are removed afterward. The suite contains **104 tests**: the original 64, 20 temporal-history regressions, and 20 error-handling regressions. These include real concurrent deadlocks and lock timeouts, exact rejection diagnostics, warning and retry decisions, restricted-user authorization, and preservation of business/audit/history values during upgrades.

## Verify the Build

### Test results

The build prints a test summary. A successful build with optional demo provisioning shows:

```
PASS    66
```

and no `FAIL` rows. To see each test individually, look at the full result table printed just before the summary.

### Objects and row counts

Connect to the socket selected in step 2 with `/usr/local/mysql/bin/mysql --protocol=SOCKET --socket="$DEV_SOCKET" -u vsm_developer -p`. The following SQL assumes the default `vehicle_service_maintenance` schema; substitute your chosen `VSM_DATABASE` if different.

```sql
USE vehicle_service_maintenance;

-- Base tables (expect 40: 12 business + generic AuditLog + 2 versioning
-- + 6 reference/identity + 17 history + TemporalEvent + TemporalWriteContext)
SHOW FULL TABLES WHERE Table_type = 'BASE TABLE';

-- Views, procedures, and triggers
SHOW FULL TABLES WHERE Table_type = 'VIEW';
SHOW PROCEDURE STATUS WHERE Db = 'vehicle_service_maintenance';
SHOW TRIGGERS;

-- Indexes
SELECT TABLE_NAME, INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS Columns
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'vehicle_service_maintenance'
GROUP BY TABLE_NAME, INDEX_NAME;

-- Constraints (PK, FK, UNIQUE, CHECK)
SELECT TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM information_schema.TABLE_CONSTRAINTS
WHERE TABLE_SCHEMA = 'vehicle_service_maintenance'
ORDER BY TABLE_NAME, CONSTRAINT_TYPE;

-- Current account's grants. Each demo user can inspect their own role grants.
-- Inspecting arbitrary accounts would need broader mysql access, which setup
-- accounts deliberately do not receive.
SHOW GRANTS;

-- Row counts
SELECT 'Customer' AS TableName, COUNT(*) AS RowCount FROM Customer
UNION ALL SELECT 'Vehicle',            COUNT(*) FROM Vehicle
UNION ALL SELECT 'Technician',         COUNT(*) FROM Technician
UNION ALL SELECT 'UserAccount',        COUNT(*) FROM UserAccount
UNION ALL SELECT 'Part',               COUNT(*) FROM Part
UNION ALL SELECT 'ServiceAppointment', COUNT(*) FROM ServiceAppointment
UNION ALL SELECT 'Repair',             COUNT(*) FROM Repair
UNION ALL SELECT 'RepairEstimate',     COUNT(*) FROM RepairEstimate
UNION ALL SELECT 'Invoice',            COUNT(*) FROM Invoice
UNION ALL SELECT 'PartsUsage',         COUNT(*) FROM PartsUsage
UNION ALL SELECT 'AuditLog',           COUNT(*) FROM AuditLog;
```

After building files 01 to 06 only, the sample data contains 4 customers, 5 vehicles, 3 technicians, 4 user accounts, 6 parts, 10 appointments, 8 repairs, 4 estimates, and 4 invoices.

## Demo Accounts

`08_demo_accounts.sql`, enabled only with `--with-demo-accounts`, creates one local MySQL account per role. These passwords are for local demonstration only. For a development database, substitute its name in the verification and login examples below.

| MySQL account        | Password       | Role                   | App user (UserAccount)                |
| -------------------- | -------------- | ---------------------- | ------------------------------------- |
| `sa_amy@localhost`   | `Advisor#2026` | `role_service_advisor` | UserID 2, Service Advisor             |
| `tech_ben@localhost` | `Tech#2026`    | `role_technician`      | UserID 3, Technician (TechnicianID 1) |
| `mgr_mike@localhost` | `Manager#2026` | `role_manager`         | UserID 1, Manager                     |

Log in as a demo user:

```bash
/usr/local/mysql/bin/mysql --protocol=SOCKET --socket="$DEV_SOCKET" \
    -u tech_ben -p "$VSM_DATABASE"
```

After migration 004, logging in as `tech_ben` resolves UserID 3 through the registered session identity. You do not need to set `@app_user_id` to identify yourself. Older baseline-only examples use that variable; on the current schema it is checked against the authenticated person and cannot select a different actor. See [Reference values and responsible actors](#reference-values-and-responsible-actors) for the service-delegation distinction.

### Role summary

| Role            | Can                                                                                                                                                                            | Cannot                                                                      |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| Service Advisor | Manage customers, vehicles, and appointments; book appointments through `sp_CreateServiceAppointment`; create estimates and invoices; finalize approved estimates and invoices | Approve or reject estimates; complete repairs; read the audit log           |
| Technician      | View work data; change the status of repairs assigned to them; complete repairs through `sp_CompleteRepair`                                                                    | Access customers, estimates, or invoices; change other technicians' repairs |
| Manager         | Everything above, plus approve or reject estimates and read the audit log                                                                                                      | Modify or delete audit records (no one can)                                 |

See TDD section 10 for the full entitlement matrix.

## Running Report Queries

Report queries RQ-01 to RQ-06 are in `03_views_reports.sql`. Open the file in MySQL Workbench (or copy a query into the `mysql` client) and run it against `vehicle_service_maintenance`. In Workbench, turn off Safe Updates (Settings → SQL Editor) and reconnect before running scripts that update data.

## Performance Analysis

See [`docs/performance/README.md`](docs/performance/README.md). It describes how to load a 20,000-row data set (`perf_data.sql`) and contains three optimization records with `EXPLAIN` / `EXPLAIN ANALYZE` before-and-after results. Rebuild the database afterwards to remove the performance data.

## AI Assistance

AI tools (Claude) were used to help draft SQL scripts, sample and performance data, and documentation. All code was reviewed, run, and tested to verify correctness.

## Author

Sebastian Teslic ([steslic](https://github.com/steslic))
