# Vehicle Service and Maintenance Management System

A MySQL database for an auto repair shop. It tracks customers, vehicles, service appointments, repairs, parts inventory, repair estimates, and invoices. Business rules are enforced through constraints, stored procedures, triggers, and role-based privileges. Successful business and durable policy changes have protected temporal history; the separate append-only `AuditLog` retains operational events and attempted rejection diagnostics. See [audit coverage and limits](docs/temporal-audit.md).

Fresh installations use consolidated **revision 007**, adding procedure-only business operations to the verified v006 foundation. Historical migrations 001–006 and the v006 contract remain immutable. See [business procedure interfaces and entitlements](docs/procedure-operations.md) for all operations, native grant changes, transaction limitations, and versioning.

Rutgers University, 01:198:437 Database Systems, Fall 2026.

## Current application integration

Application mutations use authorized stored procedures; native business table and writable-view writes are removed from optional application roles. Existing reporting SELECT access is retained. Call procedures on clean connections with autocommit enabled, `completion_type=0`, and no caller-owned transaction; A2 detection remains deferred.

Normal fresh installation uses revision 007 with 45 SQL assertions and a separate pinned 276-object contract. The original v006 contract still verifies its 246-object foundation independently. The admin now performs principal-collision inspection before every current fresh build; existing fixture principals require explicit conversion and are refused before creation/reset. Historical `--migrate` upgrades still stop at migration 006 and do not convert an existing database to revision 007. See the [operation guide](docs/procedure-operations.md).

The professor's thin-trigger requirement remains incomplete and is separate follow-up work after this PR is merged. This branch preserves the existing business rules and validations in triggers; its scope is procedure-only application access, authorization, permissions, and related tests. See [remaining scope](docs/procedure-operations.md#remaining-scope).

## Repository Contents

```
README.md                  This file
docs/
  tdd.md                   Technical Design Document
  FRD.md                   Functional Requirements Document
  build-accounts.md        Detailed account privileges and provisioning reference
  reference-and-identity.md  Indicator values, session identity, delegation, and provenance
  sql-consolidation.md     Consolidated baseline, historical paths, and equivalence evidence
  procedure-operations.md  Revision-007 API inventory, role matrix, contracts, and tests
  temporal-audit.md        Temporal history, audit reader, and coverage reference
  error-handling.md        Stable error codes, diagnostics, and caller/retry contract
  instructor_feedback_response.md  Requirements/design changes responding to feedback
  Midterm Follow-up Questions.pdf  Supporting course questions
  vehicle-service-erd.drawio  Data model / ER diagram (draw.io)
  vehicle-service-erd.svg  Data model / ER diagram (svg)
  erd.md                   ER diagram explanation
  performance/             Performance analysis and optimization records
sql/
  build.sql                Ordered inputs for the safe build runner
  01_schema.sql            Database, tables, keys, CHECK constraints
  02_indexes.sql           Secondary indexes
  03_views_reports.sql     Views and report queries (RQ-01 to RQ-06)
  04_procedures.sql        Business, identity, temporal, and diagnostic routines/functions
  05_triggers_roles.sql    Current validation, identity, audit, and history triggers
  06_sample_data.sql       Consolidated fictional fixture and observed history snapshots
  07_tests.sql             Read-only business/fixture assertions and failure gate
  08_demo_accounts.sql     Optional demo roles and accounts
  demo.sql                 Historical workflow demonstration; not a build input
scripts/build.py           Safe, fail-fast build runner
scripts/database.py        MySQL session, preflight checks, and timestamped logging
scripts/migrate.py         Ordered migration and schema verification helpers
scripts/accounts.py        Explicit bootstrap and administrator account provisioning
scripts/generate_temporal_history.py  Development-only generator for frozen migration 005
scripts/error_contract.py   Frozen v006 identifiers and offline migration mapping
scripts/operation_contract.py  Current typed interface/role catalog and additional identifiers
scripts/generate_standardized_errors.py  Development-only recipe for migration 006
sql/09_schema_migrations.sql  Historical migration metadata DDL (fresh metadata is in 01)
sql/migrations/            Immutable historical baseline and ordered upgrades
sql/legacy/v001/           Frozen original 01–08 files for historical builds
sql/consolidated/006_baseline.json  Immutable version-006 reference contract
sql/consolidated/007_procedure_only.json  Pinned current revision and explicit v006 delta
scripts/consolidated_baseline.py  Verified installation and explicit coverage bookkeeping
tests/test_build.py        Build and migration regression tests
tests/test_build_accounts.py  Developer/admin separation and denied-operation tests
tests/test_reference_identity.py  Reference, actor, and provenance regressions
tests/test_temporal_history.py  Temporal versions, audit coverage, and pagination regressions
tests/test_error_handling.py  Error contracts, native failures, and upgrade regressions
tests/test_consolidated_build.py  Tagged schema/security/data/upgrade comparisons (v006)
tests/test_procedure_operations.py  Current procedure-only operations and revision checks
tests/mysql_test_support.py  Shared private disposable MySQL server harness
```

## Prerequisites

| Requirement               | Version / Notes                                                                                 |
| ------------------------- | ----------------------------------------------------------------------------------------------- |
| MySQL Server              | The runner accepts MySQL 8.0.18 or later; regression-tested on MySQL Community Server 26.7.0 for macOS ARM64. Other versions are not validated by the recorded run. |
| MySQL command-line client | MySQL 8.0.18 or later; tested with 26.7.0. Must connect to the selected server; MariaDB is refused. Example macOS path: `/usr/local/mysql/bin/mysql`. |
| Python                    | Python 3, standard library only; verified environment: 3.14.2. Source syntax parses as Python 3.9, but runtime compatibility with older interpreters has not been tested. |
| Git                       | Any recent version                                                                              |
| Platform                  | Verified on macOS ARM64. Examples and disposable tests use Unix sockets and POSIX paths; other platforms, including Windows, have not been validated. |
| Accounts                  | Schema-scoped `vsm_developer` for builds/migrations; separate `vsm_admin` for principal inspection, provisioning, and historical reader/routine grants. See [account setup](docs/build-accounts.md). |

MySQL Workbench is optional and is only used for viewing results.

The full automated suite also needs the `mysqld` executable and permission to initialize/start disposable local servers; a command-line client alone is insufficient. See [environment checks](#environment-checks-and-logs) for required server settings. Initial admin bootstrap requires `partial_revokes=OFF`; existing-admin developer authorization handles either setting. Optional inspection of routines owned by a legacy definer uses `SHOW_ROUTINE`, requiring MySQL 8.0.20 or later.

## Build From the Repository

### 1. Get the files

For reproducible installation, use an exact commit containing the consolidated files described here. `YOUR_RELEASE_COMMIT` below is a placeholder to replace with the supplied, available commit; it does not identify a published consolidated release:

```bash
git clone https://github.com/steslic/vehicle-service-maintenance-system.git
cd vehicle-service-maintenance-system
git checkout --detach YOUR_RELEASE_COMMIT
git rev-parse HEAD
git status --porcelain  # must be empty for clean-clone evidence
```

If supplied a release tag, resolve it with `git rev-parse 'TAG_NAME^{commit}'` and verify the returned commit before checkout. The existing `pre-consolidation-2026-11` tag points to `71696139e84a4e9b69f4baa6f89a6a8d20505561`, the migration-based comparison implementation; it does not contain the consolidated fresh-build architecture. This README declares no new release tag. Uncommitted changes cannot be reproduced by checking out their base SHA alone.

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

At `MySQL password:`, enter the **existing developer password from step 2**. If administrative work is required, `Administrative MySQL password:` asks for the **existing admin password from step 2**. The standard command creates no accounts or passwords. Schema, fixture, assertion, trigger/routine creation, and version-bookkeeping work use `vsm_developer`. The separate admin handles current principal inspection and optional demo provisioning; consolidated fresh builds require no temporary developer grant authority. Historical migrations 003, 004, and 006 retain their temporary routine-grant mechanism, and migration 005 retains its conditional admin audit-reader step. See [historical exceptions](docs/build-accounts.md#immutable-migration-exceptions). The build defaults to these two account names, refuses root, and never falls back to another account.

Run the command with the absolute path to `scripts/build.py` if your shell is in another directory. SQL paths, Git metadata, and the default log directory are resolved relative to the checkout, not the shell directory.

The runner refuses an existing database with the selected name and leaves its business data and audit history unchanged. Fresh builds use authoritative SQL 01–08, verify revision 007 against its pinned parent v006 contract, and execute only later historical migrations if present. Historical SQL is not read during a normal current fresh installation. The legacy profile and existing-database upgrades retain strict historical checksum verification. Missing files, SQL errors, and failed test suites produce a nonzero exit code. A failed build retains its partial database for inspection; it is never silently deleted or reused.

The optional `08_demo_accounts.sql` file runs as admin and creates only unused native demo principals. Every revision-007 fresh build first uses the admin's existing User/Host metadata reads to refuse existing fixture principals before creation/reset. Current installation does not silently convert existing native grants or reuse identities. Full provisioning remains optional; schema/routine/trigger creation remains developer-owned. The v006 conditional-reader behavior is retained only by historical reproduction; see [current native policy](docs/procedure-operations.md#native-privileges-and-provisioning).

### 4. Apply later migrations to an existing database

When new numbered migrations are available, upgrade the same selected schema instead of building it again:

```bash
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql \
    --socket "$DEV_SOCKET" --database "$VSM_DATABASE" --migrate \
    -u vsm_developer -p --admin-user vsm_admin --admin-password
```

Enter the **existing developer password**, then the **existing admin password if prompted**. Migration does not create accounts or passwords and never reloads sample data or runs data-changing SQL acceptance tests. A fresh build installs revision 007 with independently verified v006 ancestry, without executing migrations 001–006; running this command immediately afterward verifies the schema and makes no changes. Current fresh builds require admin collision inspection. Historical builds through version 002 without demo accounts and already-current migrations with developer-owned routines need no admin connection. Legacy-definer metadata inspection may require the admin as explained in [the technical reference](docs/build-accounts.md).

### Build manifest

[sql/build.sql](sql/build.sql) lists authoritative fresh inputs and the separate historical migration registry. The runner validates inputs, environment settings, optional demo-name collisions, and any needed fresh-build admin authentication before creation/reset, then executes these phases. **The counts describe revision 007, not permanent totals for future schema versions.**

| Phase | Authoritative file | Contents |
| --- | --- | --- |
| 1 | `01_schema.sql` | New database, incomplete baseline metadata, all 41 tables, including separate revision metadata |
| 2 | `02_indexes.sql`, then the foreign-key section of `01_schema.sql` | Exact secondary-index order and final foreign keys |
| 3 | `04_procedures.sql`, `03_views_reports.sql` | 41 procedures, 4 functions, 6 views, existing report queries |
| 4 | `06_sample_data.sql` | Tagged fictional fixture, required reference/security rows, observed snapshots |
| 5 | `05_triggers_roles.sql` | All 187 final triggers in original action order |
| 6 | `08_demo_accounts.sql` | Optional native accounts and final grants, as admin |
| 7 | `07_tests.sql` | 45 current-state assertions; no business writes |
| 8 | `scripts/consolidated_baseline.py` | Verify 276 current objects, initial entitlements, v006 coverage and independent revision-007 provenance |
| 9 | Migration runner | Execute pending migrations above 006, if present; none are currently checked in |

The [v006 contract](sql/consolidated/006_baseline.json) remains immutable. The [revision-007 child](sql/consolidated/007_procedure_only.json) permits exactly 29 added business procedures, one private rejection-audit transaction helper, and two classifier updates; every other v006 definition remains exact. The 276 tracked objects exclude three administrative tables. Metadata records historical migrations as covered and current revision installation separately, preserving historical object origins without attributing new procedures to migration 006. See [versioning details](docs/procedure-operations.md#versioning-and-verification).

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

Demo provisioning does not change the consolidated build's **45 PASS** assertion count. Historical builds retain **65 PASS, 1 SKIP** without demo accounts or **66 PASS** with them; the skipped assertion is the native technician-grant check T-49. These legacy checks cover reports, rejection paths, workflows, and permissions. T-11 remains a separate login demonstration; the Python suite executes its six original permission cases using real logins. Test failures are printed with diagnostics before the failure gate aborts the build.

### Schema versions and non-destructive upgrades

Use the same entry point for builds and migrations. `--migrate` never runs the destructive build, sample-data loader, demo provisioning, or data-changing test suite.

To demonstrate an upgrade on a new disposable database:

```bash
# Build the historical version-001 baseline and run its SQL tests.
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u vsm_developer -p --admin-password \
    --socket "$DEV_SOCKET" --database vsm_dev_upgrade --target-version 1

# Upgrade to the latest version (currently 6).
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u vsm_developer -p --admin-password \
    --socket "$DEV_SOCKET" --database vsm_dev_upgrade --migrate

# Repeat: no migration SQL executes again and application timestamps stay unchanged.
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u vsm_developer -p --admin-password \
    --socket "$DEV_SOCKET" --database vsm_dev_upgrade --migrate
```

A normal new build installs consolidated revision 007 and then any later manifest migrations. Explicit `--target-version 1` through `6` selects historical reproduction; that option is a migration target, not a consolidated revision selector. `--build-profile legacy` reproduces the original ordered build through any supported target; `--target-version 1` through `6` selects legacy automatically. See [SQL consolidation](docs/sql-consolidation.md) for the comparison contract and initialization phases. Migrations 001 through 006 must remain immutable once applied; the next new migration is 007. Migrations 003 and 004 add reference/identity metadata and provenance guards; migration 005 adds temporal history; migration 006 adds error codes and nullable rejection diagnostics while retaining existing rows, historical evidence, and lifecycle transitions. See [Reference values, identity, and provenance](docs/reference-and-identity.md), [Temporal history and audit trail](docs/temporal-audit.md), and [Error handling](docs/error-handling.md).

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
       revision_version, definition_checksum, source_commit_sha, source_dirty
FROM schema_object_versions ORDER BY object_type, object_name;

-- Current revision installation is separate from historical migration execution.
SELECT revision, contract_file, contract_checksum, status, installed_at
FROM schema_revisions ORDER BY revision;
```

The first table records migration versions, exact file digests, database timestamps, source revisions, and status. `schema_revisions` is present only on current revision-007 installations; omit that query for historical schemas. On consolidated installs, versions 001–006 have status `covered`, NULL `applied_at`, and explicit `baseline_version`, `baseline_checksum`, and `covered_at`. Executed migrations retain status `applied` and an actual execution timestamp. Existing historical tables are not altered. The second exposes historical migration origins and current revision changes for each deployed object. New APIs have NULL migration origin and revision_version=7; changed classifiers retain their historical origin and add revision_version=7. The revision_version column is absent from historical schemas, so omit it when inspecting v006. Unchanged objects retain their earlier version. For an adopted database, the source SHA identifies the verified baseline registration, not an invented historical deployment date. Later runs also reject object-definition drift outside migrations.

### Reference values and responsible actors

The latest schema provides `IndicatorValue` and `sp_ListIndicatorValues` for database-backed dropdowns. For example:

```sql
INSERT INTO IndicatorValue (IndicatorName, ValueCode, Description, DisplayOrder)
VALUES ('repair_type', 'Wheel Alignment', 'Wheel alignment and balancing', 25);
CALL sp_ListIndicatorValues('repair_type');
```

Registered people are resolved from the full database session login. A caller-supplied person ID can only assert that identity; service calls need explicit person/operation delegations, and the service should have EXECUTE only. An unmapped administrative connection is no longer an operational acting-user fallback. Audit rows record the session account separately from the responsible person; old session identities remain unknown. Follow the [identity and reference guide](docs/reference-and-identity.md) for direct-user, service-account, and provenance details.

In the current consolidated schema (introduced historically by migration 004), `@app_user_id` is a checked compatibility hint, **not a trusted identity source**. Setting it cannot authenticate a person, impersonate another user, authorize a service delegation, or bypass session identity validation. Public procedures resolve the actor from the registered session and use protected operation context for authorized service calls.

### Temporal history and audit trail

Migration 005 historically introduced mirrored history for the 12 business tables and five durable reference/security metadata tables. Fresh version-006 builds create the current tables/indexes in files 01/02, load observed snapshots in file 06, and install the final triggers in file 05; pending historical upgrades initialize snapshots through migration 005 instead. Inserts open versions, real updates close and replace them, and deletes close versions while retaining their data and deletion attribution. No-op updates create no history. Every live mirrored source record has one current history version; historical rows have no foreign keys back to deletable business records.

Existing rows are initialized as observed snapshots with NULL historical start times and actors, rather than invented creation events. New events record database-owned UTC microsecond times, the actual session, verified person or explicit system-only maintenance attribution, and protected procedure context. History and business changes roll back together. Existing generic AuditLog records, successful operational event counts, rejection handling, and inventory reasons are retained.

A manager with the native reader grants described above can read `vw_AuditTrail` (file 03) or use the bounded keyset reader (file 04):

```sql
CALL sp_ListAuditTrail('Part', JSON_OBJECT('PartID', 1), NULL,
                      NULL, NULL, NULL, 50);
-- Next page: replace 123 with the smallest EventID returned above.
CALL sp_ListAuditTrail('Part', JSON_OBJECT('PartID', 1), NULL,
                      NULL, NULL, 123, 50);
```

Arguments are entity, JSON record key, responsible user, inclusive UTC start, exclusive UTC end, exclusive EventID cursor, and page size (1–200). NULL omits a filter. Results are ordered by EventID descending. The reader selects indexed event IDs before fetching version payloads; native roles receive no direct history-write permissions. No GUI or service is implemented. See [the temporal audit reference](docs/temporal-audit.md) for the complete object inventory, validity semantics, security boundaries, migration precautions, and remaining server-audit limitations.

### Stable errors and rejection diagnostics

The current standardized error definitions are in [sql/04_procedures.sql](sql/04_procedures.sql) and [sql/05_triggers_roles.sql](sql/05_triggers_roles.sql); migration 006 introduced them historically for upgrades. Stable MySQL application error numbers cover validation, forbidden, not-found, conflict, warning, and critical conditions. Native deadlocks and lock timeouts remain errors 1213 and 1205, classified as retryable. Runtime classification never matches human-readable messages. Existing procedure parameters, trigger order, and verified attribution are preserved. Revision 007 changes native entry-point grants while retaining the business entitlement matrix.

```sql
-- Developer/authorized diagnostic context; application adapters can implement
-- the same published numeric contract without additional database grants.
SELECT fn_ApplicationErrorID(51001), fn_ErrorClass(51001, '45000', FALSE);
-- VSM_INVALID_APPOINTMENT | validation

SELECT AuditLogID, ApplicationErrorID, ErrorClass, ErrorSQLSTATE,
       ErrorNumber, ErrorMessage, TransactionOutcome, UserID, SessionAccount
FROM AuditLog WHERE Action = 'Rejected' ORDER BY AuditLogID DESC;
```

The original business procedures and new typed interfaces capture the original error before cleanup and use bare `RESIGNAL` to preserve it. Earlier audit rows retain NULL diagnostics. Retry the entire business transaction only after its rollback is confirmed, with at most three total attempts and bounded backoff. Unknown commit/connection outcomes require reconciliation before another submission. Nonfatal warnings after a completed operation do not request a replay. See [error-handling.md](docs/error-handling.md) for all 38 current identifiers, classifier interfaces, examples, warning handling, upgrade precautions, and remaining rejection-durability/transaction-ownership limits.

### Adding a migration and recovering failures

Keep `sql/legacy/v001/`, `sql/migrations/baseline.json`, `sql/09_schema_migrations.sql`, and successful migrations immutable. The original files 01–08 now define the consolidated fresh schema; substantive future changes need a separately pinned revision contract and/or an explicit numbered upgrade, with cross-path and behavioral verification. Revision 007 is a fresh-installation revision, not a historical migration 007; it does not implicitly upgrade v006 databases. With migrations 001–006 already present, add `007_descriptive_change.sql` next and append `SOURCE migrations/007_descriptive_change.sql` to **the existing `sql/build.sql` manifest**. There is no separate migration manifest. Every SQL migration must be listed exactly once in numeric order; gaps, unlisted files, missing pending SQL files, changed applied checksums, and downgrade targets are refused. Historical reproduction and upgrades require historical files and verify their checksums. Current fresh installation instead obtains covered historical names/digests from the immutable v006 parent contract and does not require the covered historical SQL files. Migration SQL uses the database selected by the runner; it must not switch databases or manage accounts. Restore `DELIMITER ;` at the end of routine definitions.

The runner holds a connection-level advisory lock throughout verification and migration, preventing two runners from upgrading the same database concurrently. Before executing each migration, it commits an `applying` history row. Only successful DDL and an atomic object-version/history update produce `applied`. SQL failure records `failed` when the server remains reachable; abrupt termination leaves `applying`. An empty history table indicates interruption during initial setup. All these incomplete states block further migrations and are never automatically replayed.

MySQL DDL implicitly commits, so an index or column created before a later error may remain even though the migration failed. A transaction cannot make a whole multi-statement DDL migration atomic. See the [MySQL implicit-commit rules](https://dev.mysql.com/doc/refman/8.0/en/implicit-commit.html) and [connection-level lock behavior](https://dev.mysql.com/doc/refman/8.0/en/locking-functions.html).

For this course implementation, recovery is deliberately manual: inspect the log, `schema_migrations`, and actual object definitions; restore a verified pre-run backup of the disposable target; fix an unapplied migration if necessary; rerun. Do not delete a failed history row, mark partial DDL as applied, edit an applied checksum, or assume `ROLLBACK` removed DDL. The runner offers no force/repair switch that can silently bless partial changes. Stopping application writes and retaining the backup are part of the upgrade procedure, so restoring it does not discard later user work.

### Build regression tests

```bash
python3 -B -m unittest discover -s tests -v
```

These tests require **no manual account provisioning or password entry**, including when launched from a terminal. They initialize their own temporary MySQL data directories, start private servers with networking disabled, provision their own admin/developer and restricted test accounts, and generate disposable credentials automatically. Root is used only for each private server's initial admin bootstrap and is then locked. The manual account-provisioning commands in step 2 still prompt normally.

The tests connect only through their own temporary Unix sockets; they do not use `DEV_SOCKET`, connect to the installed project server, or require that server's credentials. `MYSQL_BIN` and `MYSQLD_BIN` may select the client/server executable paths. The private servers and their data are removed afterward. The suite currently contains **170 Python tests**: 125 preserved v006 regressions plus 45 current-revision regressions. These are separate from the SQL assertion counts above.

| Test module | Tests |
| --- | ---: |
| [test_build.py](tests/test_build.py) | 28 |
| [test_build_accounts.py](tests/test_build_accounts.py) | 14 |
| [test_reference_identity.py](tests/test_reference_identity.py) | 22 |
| [test_temporal_history.py](tests/test_temporal_history.py) | 20 |
| [test_error_handling.py](tests/test_error_handling.py) | 20 |
| [test_consolidated_build.py](tests/test_consolidated_build.py) | 21 |
| [test_procedure_operations.py](tests/test_procedure_operations.py) | 45 |

All original test assertions now use an immutable v006 fixture, preserving their historical permission and workflow checks. The 45 current tests exercise equivalent workflows through authorized procedures, native direct-write denial, and the current contract. See [current regression coverage](docs/procedure-operations.md#regression-coverage). Consolidation tests compare tagged definitions, trigger order/definers, native permissions, fixture JSON types, workflows, and upgrades from versions 001–006. They also cover qualified/unrelated existing roles, manager-specific audit grants, collisions, and least-privilege execution. Other regressions include real deadlocks and lock timeouts, exact rejection diagnostics, warning/retry decisions, restricted-user authorization, and preservation of business/audit/history values. The [recorded validation](docs/sql-consolidation.md#conditional-permission-correction) passed all 125 tests on disposable MySQL 26.7.0 servers; use the command above to verify your checkout.

## Verify the Build

### Test results

The build prints a test summary. A successful consolidated build shows:

```
PASS    45
```

and no `FAIL` rows. To see each test individually, look at the full result table printed just before the summary.

### Current revision objects and fixture row counts

Connect to the socket selected in step 2 with `/usr/local/mysql/bin/mysql --protocol=SOCKET --socket="$DEV_SOCKET" -u vsm_developer -p`. The following SQL assumes the default `vehicle_service_maintenance` schema; substitute your chosen `VSM_DATABASE` if different.

```sql
USE vehicle_service_maintenance;

-- Revision 007 only; future releases may change these counts.
-- Base tables (41: 12 business + generic AuditLog + 3 administrative
-- + 6 reference/identity + 17 history + TemporalEvent + TemporalWriteContext)
SHOW FULL TABLES WHERE Table_type = 'BASE TABLE';

-- Revision 007: 6 views, 41 procedures, 4 functions, and 187 triggers
SHOW FULL TABLES WHERE Table_type = 'VIEW';
SHOW PROCEDURE STATUS WHERE Db = 'vehicle_service_maintenance';
SHOW FUNCTION STATUS WHERE Db = 'vehicle_service_maintenance';
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
UNION ALL SELECT 'EstimateLineItem',   COUNT(*) FROM EstimateLineItem
UNION ALL SELECT 'Invoice',            COUNT(*) FROM Invoice
UNION ALL SELECT 'InvoiceLineItem',    COUNT(*) FROM InvoiceLineItem
UNION ALL SELECT 'PartsUsage',         COUNT(*) FROM PartsUsage
UNION ALL SELECT 'AuditLog',           COUNT(*) FROM AuditLog;
```

Immediately after a successful consolidated revision-007 fresh build, before any application/demo mutations or later migrations, the query above should return these fixture counts. File 06 imports the tagged implementation's final fictional state, including historical acceptance-check effects; the current file-07 assertions do not mutate business data. Running a numeric subset of files 01–06 is not a supported installation path.

| Table | Rows |
| --- | ---: |
| Customer | 5 |
| Vehicle | 6 |
| Technician | 3 |
| UserAccount | 4 |
| Part | 6 |
| ServiceAppointment | 16 |
| Repair | 10 |
| RepairEstimate | 4 |
| EstimateLineItem | 9 |
| Invoice | 4 |
| InvoiceLineItem | 9 |
| PartsUsage | 9 |
| AuditLog | 120 |

Reference/security fixtures contain 97 `IndicatorValue`, 3 `UserRolePolicy`, 4 `DatabasePrincipal`, 55 `RoleProcedurePermission`, and zero `PrincipalDelegation` rows. The 17 mirrored history tables each have one initial Snapshot per corresponding source row. `TemporalEvent`, `OperationContext`, and `TemporalWriteContext` are empty. These expectations are checked by [sql/07_tests.sql](sql/07_tests.sql) and the Python regressions; they are fixture expectations, not limits on application data.

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

On the consolidated schema, logging in as `tech_ben` resolves UserID 3 through the registered session identity, as introduced by migration 004. You do not need to set `@app_user_id` to identify yourself. Older baseline-only examples use that variable; on the current schema it is checked against the authenticated person and cannot select a different actor. See [Reference values and responsible actors](#reference-values-and-responsible-actors) for the service-delegation distinction.

### Role summary

| Role            | Can                                                                                                                                                                            | Cannot                                                                      |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| Service Advisor | Use authorized procedures for customers, vehicles, appointments, repairs, estimates, invoices, and line items; finalize approved estimates/invoices | Approve or reject estimates; complete repairs; read the audit log           |
| Technician      | Read permitted work data; call `sp_SetRepairStatus` for assigned repairs and `sp_CompleteRepair` for completion                                                                    | Access customers, estimates, or invoices; change other technicians' repairs |
| Manager         | Broad operational access, appointment booking, repair completion, inventory adjustments, estimate approval/rejection, and generic/temporal audit reads; lifecycle and identity guards still apply | Modify/delete audit rows through application privileges; bypass history guards |

All mutations in this summary mean procedure calls; application roles have no direct table/view writes. See [the full operation matrix](docs/procedure-operations.md#operation-inventory-and-entitlement-decisions) and [TDD section 10](docs/tdd.md#10-database-objects-and-sql-design) and [optional native grants](sql/08_demo_accounts.sql) for the entitlement details. Trusted schema owners retain DDL authority; these application restrictions do not make the database tamper-proof against its owner.

## Running Report Queries

Report queries RQ-01 to RQ-06 are in [sql/03_views_reports.sql](sql/03_views_reports.sql). Copy the report SELECT statements into Workbench or the `mysql` client and run them against your selected schema. The whole file also creates views and belongs in the runner's ordered build; report reads require no Safe Updates change.

## Performance Analysis

See [the performance reference](docs/performance/README.md) for three historical optimization records and the loader that adds 20,000 appointments and 20,000 repairs. That loader asserts legacy identities and requires a separate disposable version-002 legacy build; it is incompatible with current identity validation. New performance loaders must use registered actors. Discard the disposable measurement server afterward; do not reload these historical scripts into a consolidated or existing user database.

## AI Assistance

Claude and OpenAI Codex assisted with SQL, sample/performance data, build and migration tooling, regression tests, and documentation. Codex also assisted with SQL consolidation and tagged-equivalence verification. See [SQL consolidation](docs/sql-consolidation.md#conditional-permission-correction) for the recorded regression results, tested environment, and validation limits.

## Author

Sebastian Teslic ([steslic](https://github.com/steslic))
