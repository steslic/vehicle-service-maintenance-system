# Vehicle Service and Maintenance Management System

A MySQL database for an auto repair shop. It tracks customers, vehicles, service appointments, repairs, parts inventory, repair estimates, and invoices. Business rules are enforced inside the database through constraints, stored procedures, triggers, and role-based privileges, and every important change is written to an append-only audit log.

Rutgers University, 01:198:437 Database Systems, Fall 2026.

## Repository Contents

```
README.md                  This file
docs/
  tdd.md                   Technical Design Document
  FRD.md                   Functional Requirements Document
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
sql/09_schema_migrations.sql  Migration history table
sql/migrations/            Baseline fingerprints and ordered SQL upgrades
tests/test_build.py        Build and migration tests on a private disposable server
```

## Prerequisites

| Requirement               | Version / Notes                                                                                 |
| ------------------------- | ----------------------------------------------------------------------------------------------- |
| MySQL Server              | MySQL 8.0.18 or later; tested on MySQL Community Server 26.7.0. |
| MySQL command-line client | MySQL 8.0.18 or later, with a successful connection to the selected server; MariaDB is refused. On macOS: `/usr/local/mysql/bin/mysql`. |
| Python                    | 3.9 or later, for the build runner and build regression tests.                                |
| Git                       | Any recent version                                                                              |
| Platform                  | Developed and tested on macOS. Any OS that runs MySQL 8 works.                                  |
| Account                   | A MySQL account with privileges to create databases, users, and roles (for example, `root`).    |

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

### 2. Build the database, load the data, and run the tests

```bash
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u root -p
```

Run the command with the absolute path to `scripts/build.py` if your shell is in another directory. SQL paths, Git metadata, and the default log directory are resolved relative to the checkout, not the shell directory.

The runner refuses an existing `vehicle_service_maintenance` database and leaves its business data and audit history unchanged. It validates every manifest input and migration checksum before executing SQL, then runs the existing schema/data/test batch with continue-on-error disabled. Verified migrations follow on the same connection. Missing files, SQL errors, and failed test suites produce a nonzero exit code. A failed build retains its partial database for inspection; it is never silently deleted or reused.

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

Use the runner instead of piping `build.sql` or concatenating SQL files into the client. Direct execution of `build.sql` raises an error directing you to the runner.

### Environment checks and logs

Before database creation, reset, or migration, the runner checks the client/server versions and requires InnoDB, `REPEATABLE-READ`, autocommit, foreign-key checks, unique checks, a writable server, and `innodb_flush_log_at_trx_commit = 1` for durable migration checkpoints. SQL mode must include `STRICT_TRANS_TABLES` and `NO_ENGINE_SUBSTITUTION`, with `ANSI_QUOTES` and `NO_BACKSLASH_ESCAPES` disabled. After these checks, it pins the session SQL mode to `ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION`, so stored-object definitions are reproducible. The connection uses `utf8mb4`; new databases use `utf8mb4_0900_ai_ci`; operation timestamps use a UTC session. Existing databases are checked against their recorded object definitions.

Every run writes `logs/<UTC timestamp>-<process ID>-build.log`, including refusals and SQL/test failures. The log records the source Git SHA, dirty-worktree flag, MySQL client/server/settings, executed SQL filenames and checksums, existing test results, migration operations, schema version, and final `SUCCESS`, `FAILED`, or `INTERRUPTED` status. An abrupt process/server death can leave no final status; the durable migration history then identifies unfinished work. Passwords are not placed in commands or logs.

`--log-dir /absolute/path` selects another log directory. Logs are ignored by Git by default; retain a chosen clean-clone run as submission evidence. A dirty-worktree log identifies the base commit but does not claim the uncommitted changes are reproducible from that SHA. No release tag or commit is created by the runner.

### Explicit development resets

Only disposable databases whose names begin with `vsm_dev_` can be reset:

```bash
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u root -p \
    --database vsm_dev_local --dev-reset
```

`--dev-reset` deletes all business and audit data in that named development database. It is refused for `vehicle_service_maintenance` and every other non-development name. Without the flag, even an existing `vsm_dev_*` database is protected. Database resets never reset users or roles.

### Optional demo accounts

Server-wide demo roles and accounts are excluded by default. To provision them on a disposable server where those names are unused:

```bash
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u root -p \
    --database vsm_dev_demo --with-demo-accounts
```

Provisioning refuses any existing demo username or role before creating or resetting a database. It never drops accounts, changes existing passwords, or adds grants to existing principals. Repeating a demo build on the same server therefore requires separately managing its demo principals or using a fresh disposable server.

The default build reports **65 PASS, 1 SKIP**: T-49 inspects demo-role grants and is explicitly skipped when provisioning is disabled. With `--with-demo-accounts`, all **66 existing automated checks** run. T-11 remains available as a separate login demonstration; the regression suite also executes its six original permission cases using real logins. Test failures are printed with their diagnostics before the failure gate aborts the build.

### Schema versions and non-destructive upgrades

Use the same entry point for builds and migrations. `--migrate` never runs the destructive build, sample-data loader, demo provisioning, or data-changing test suite.

To demonstrate an upgrade on a new disposable database:

```bash
# Build the current baseline (version 1), including the existing database tests.
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u root -p \
    --database vsm_dev_upgrade --target-version 1

# Upgrade to the latest version (version 2 adds only idx_Customer_Name).
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u root -p \
    --database vsm_dev_upgrade --migrate

# Repeat: no migration SQL executes again and application timestamps stay unchanged.
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u root -p \
    --database vsm_dev_upgrade --migrate
```

A normal new build without `--target-version` finishes at the latest manifest version. The original 13 business tables, procedures, triggers, sample data, and existing indexes remain; versioning adds two metadata tables and one customer-name index.

For an **unversioned existing database**, first stop application writes and take a backup. Explicitly request adoption:

```bash
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u root -p \
    --database YOUR_EXISTING_DATABASE --migrate --baseline
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

### Adding a migration and recovering failures

Keep the baseline SQL and successful migrations immutable. Add the next contiguous numbered SQL file (for example, `003_descriptive_change.sql`) and append its `SOURCE migrations/...` entry to **the existing `sql/build.sql` manifest**. There is no separate migration manifest. Every SQL migration must be listed exactly once in numeric order; gaps, unlisted files, missing historical files, changed applied checksums, and downgrade targets are refused. Migration SQL uses the database selected by the runner; it must not switch databases or manage accounts. Restore `DELIMITER ;` at the end of routine definitions.

The runner holds a connection-level advisory lock throughout verification and migration, preventing two runners from upgrading the same database concurrently. Before executing each migration, it commits an `applying` history row. Only successful DDL and an atomic object-version/history update produce `applied`. SQL failure records `failed` when the server remains reachable; abrupt termination leaves `applying`. An empty history table indicates interruption during initial setup. All these incomplete states block further migrations and are never automatically replayed.

MySQL DDL implicitly commits, so an index or column created before a later error may remain even though the migration failed. A transaction cannot make a whole multi-statement DDL migration atomic. See the [MySQL implicit-commit rules](https://dev.mysql.com/doc/refman/8.0/en/implicit-commit.html) and [connection-level lock behavior](https://dev.mysql.com/doc/refman/8.0/en/locking-functions.html).

For this course implementation, recovery is deliberately manual: inspect the log, `schema_migrations`, and actual object definitions; restore a verified pre-run backup of the disposable target; fix an unapplied migration if necessary; rerun. Do not delete a failed history row, mark partial DDL as applied, edit an applied checksum, or assume `ROLLBACK` removed DDL. The runner offers no force/repair switch that can silently bless partial changes. Stopping application writes and retaining the backup are part of the upgrade procedure, so restoring it does not discard later user work.

### Build regression tests

```bash
python3 -B -m unittest discover -s tests -v
```

These tests initialize their own temporary MySQL data directory, start a private server with networking disabled, and connect only through its temporary Unix socket. They do not connect to the installed project server. `MYSQL_BIN` and `MYSQLD_BIN` may select the client/server executable paths. The private server and its data are removed afterward.

## Verify the Build

### Test results

The build prints a test summary. A successful build with optional demo provisioning shows:

```
PASS    66
```

and no `FAIL` rows. To see each test individually, look at the full result table printed just before the summary.

### Objects and row counts

Connect with `/usr/local/mysql/bin/mysql -u root -p` and run:

```sql
USE vehicle_service_maintenance;

-- Base tables (expect 15: 13 business + 2 versioning metadata tables)
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

-- Roles and demo users
SHOW GRANTS FOR role_service_advisor;
SHOW GRANTS FOR role_technician;
SHOW GRANTS FOR role_manager;
SHOW GRANTS FOR 'sa_amy'@'localhost' USING role_service_advisor;

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
/usr/local/mysql/bin/mysql -u tech_ben -p vehicle_service_maintenance
```

Before making changes, identify the application user for auditing:

```sql
SET @app_user_id = 3;   -- tech_ben
```

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
