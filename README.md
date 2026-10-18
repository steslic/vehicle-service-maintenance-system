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
  build.sql                Runs every script below in order
  01_schema.sql            Database, tables, keys, CHECK constraints
  02_indexes.sql           Secondary indexes
  03_views_reports.sql     Views and report queries (RQ-01 to RQ-06)
  04_procedures.sql        sp_CreateServiceAppointment, sp_CompleteRepair
  05_triggers_roles.sql    Audit and validation triggers, roles, demo users
  06_sample_data.sql       Sample data
  07_tests.sql             Automated test suite
```

## Prerequisites

| Requirement               | Version / Notes                                                                                 |
| ------------------------- | ----------------------------------------------------------------------------------------------- |
| MySQL Server              | 8.0.16 or later (CHECK constraints are enforced starting in 8.0.16). Developed on MySQL 26.7.0. |
| MySQL command-line client | Included with MySQL Server. On macOS it is at `/usr/local/mysql/bin/mysql`.                     |
| Git                       | Any recent version                                                                              |
| Platform                  | Developed and tested on macOS. Any OS that runs MySQL 8 works.                                  |
| Account                   | A MySQL account with privileges to create databases, users, and roles (for example, `root`).    |

MySQL Workbench is optional and is only used for viewing results.

## Build From the Repository

### 1. Get the files

Clone the tagged release so you build exactly the submitted version:

```bash
git clone --branch v1.0 https://github.com/steslic/vehicle-service-maintenance-system.git
cd vehicle-service-maintenance-system/sql
```

### 2. Build the database, load the data, and run the tests

Run this from inside the `sql` folder:

```bash
/usr/local/mysql/bin/mysql --commands=ON -u root -p < build.sql
```

- `--commands=ON` is required because `build.sql` uses `SOURCE` to run the other files.
- It must be run from the `sql` folder because the `SOURCE` paths are relative.
- If `mysql` is already on your PATH, you can use `mysql` instead of the full path.

`build.sql` runs the files in this order:

| Step | File                    | What it creates                                                                  |
| ---- | ----------------------- | -------------------------------------------------------------------------------- |
| 1    | `01_schema.sql`         | Drops and recreates the `vehicle_service_maintenance` database and all 13 tables |
| 2    | `02_indexes.sql`        | Secondary indexes                                                                |
| 3    | `03_views_reports.sql`  | Views and report queries                                                         |
| 4    | `04_procedures.sql`     | Stored procedures                                                                |
| 5    | `05_triggers_roles.sql` | Triggers, roles, and demo user accounts                                          |
| 6    | `06_sample_data.sql`    | Sample data                                                                      |
| 7    | `07_tests.sql`          | Automated tests                                                                  |

The build is repeatable: `01_schema.sql` starts with `DROP DATABASE IF EXISTS`, and the role and user statements use `IF EXISTS` / `IF NOT EXISTS`, so it can be run again at any time to return to a clean state.

### Build without the tests

The tests change some sample data. To get the database with only the original sample data (for a demo or for performance testing), run files 01 to 06:

```bash
cat 01_schema.sql 02_indexes.sql 03_views_reports.sql 04_procedures.sql \
    05_triggers_roles.sql 06_sample_data.sql | /usr/local/mysql/bin/mysql -u root -p
```

## Verify the Build

### Test results

The last output of the build is the test summary. A successful build shows:

```
PASS    44
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

`05_triggers_roles.sql` creates one local MySQL account per role. These passwords are for local demonstration only.

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
