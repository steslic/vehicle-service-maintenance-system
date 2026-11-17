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
tests/test_build.py        B1/B2 tests using a private disposable MySQL server
```

## Prerequisites

| Requirement               | Version / Notes                                                                                 |
| ------------------------- | ----------------------------------------------------------------------------------------------- |
| MySQL Server              | 8.0.16 or later (CHECK constraints are enforced starting in 8.0.16). Developed on MySQL 26.7.0. |
| MySQL command-line client | Included with MySQL Server. On macOS it is at `/usr/local/mysql/bin/mysql`.                     |
| Python                    | 3.9 or later, for the build runner and build regression tests.                                |
| Git                       | Any recent version                                                                              |
| Platform                  | Developed and tested on macOS. Any OS that runs MySQL 8 works.                                  |
| Account                   | A MySQL account with privileges to create databases, users, and roles (for example, `root`).    |

MySQL Workbench is optional and is only used for viewing results.

## Build From the Repository

### 1. Get the files

Clone the repository and check out the revision you want to build:

```bash
git clone https://github.com/steslic/vehicle-service-maintenance-system.git
cd vehicle-service-maintenance-system
```

### 2. Build the database, load the data, and run the tests

```bash
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u root -p
```

The runner refuses an existing `vehicle_service_maintenance` database and leaves its business data and audit history unchanged. It validates every input file before executing SQL, then runs one batch with continue-on-error disabled. Missing files, SQL errors, and failed test suites produce a nonzero exit code. A failed build retains its partial database for inspection; it is never silently deleted or reused.

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

Use the runner instead of piping `build.sql` or concatenating SQL files into the client. Direct execution of `build.sql` raises an error directing you to the runner.

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

The default build reports **65 PASS, 1 SKIP**: T-49 inspects demo-role grants and is explicitly skipped when provisioning is disabled. With `--with-demo-accounts`, all **66 existing automated checks** run. T-11 remains the existing manual login test. Test failures are printed with their diagnostics before the failure gate aborts the build.

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

-- Tables (expect 13)
SHOW TABLES;

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
