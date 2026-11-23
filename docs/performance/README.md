# Performance Analysis

Performance work for the Vehicle Service and Maintenance Management System.

## Method

For each optimization:

1. Pick a slow or high-traffic query.
2. Measure it with `EXPLAIN` (the plan) and `EXPLAIN ANALYZE` (actual time and rows).
3. Form a hypothesis for why it is slow.
4. Change **one** thing.
5. Re-measure the same way.
6. Document before, change, after, and conclusion.

Statistics are refreshed with `ANALYZE TABLE` before each measurement. MySQL 26.7.0 prints `EXPLAIN` in tree format, which names each access path directly (table scan, index lookup, range scan, sort, temporary table).

## Environment

| Item          | Value                                                                 |
| ------------- | --------------------------------------------------------------------- |
| MySQL version | 26.7.0                                                                |
| Machine       | Macbook Air                                                           |
| Data set      | `perf_data.sql` loaded on top of the normal sample data (files 01–06) |

## How to Reproduce

The captured outputs below are historical measurements from a sample-only build. Reproduce this historical loader using the archived legacy profile at schema version 2 using the schema-scoped `vsm_developer` setup account: it asserts human identities, which current session-identity validation correctly rejects. Provision that exact schema using [account setup](../build-accounts.md). New performance loaders must use registered actors. The canonical build also runs the database tests and installs migration metadata, so new row counts and timings can differ. Keep new output separate from that historical evidence.

These performance SQL files target `vehicle_service_maintenance` explicitly. Run them only on a **separate disposable MySQL server**, using its explicit Unix socket for every command. Do not point them at the installed project server. From the repository root:

```bash
# Replace this with the socket of your separate disposable MySQL server.
DEV_SOCKET=/absolute/path/to/disposable/mysql.sock

# The same safe entry point and manifest used by every normal build.
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u vsm_developer -p \
    --socket "$DEV_SOCKET" --database vehicle_service_maintenance --target-version 2

mkdir -p logs/performance
/usr/local/mysql/bin/mysql --protocol=SOCKET --socket="$DEV_SOCKET" -vvv -u vsm_developer -p \
    < docs/performance/perf_data.sql > logs/performance/perf_data_output.txt
/usr/local/mysql/bin/mysql --protocol=SOCKET --socket="$DEV_SOCKET" -t -u vsm_developer -p \
    < docs/performance/OPT-01_common_repairs_covering_index.sql > logs/performance/OPT-01_output.txt
/usr/local/mysql/bin/mysql --protocol=SOCKET --socket="$DEV_SOCKET" -t -u vsm_developer -p \
    < docs/performance/OPT-02_daily_appointments_range_filter.sql > logs/performance/OPT-02_output.txt
/usr/local/mysql/bin/mysql --protocol=SOCKET --socket="$DEV_SOCKET" -t -u vsm_developer -p \
    < docs/performance/OPT-03_auditlog_keyset_pagination.sql > logs/performance/OPT-03_output.txt
```

Discard the disposable server after measuring. The build runner refuses to overwrite an existing database; it never resets the project database. The index experiment temporarily changes the disposable schema, so it is not an input to subsequent migration verification.

## Data Volume

Row counts after `perf_data.sql` (from [`perf_data_output.txt`](perf_data_output.txt)):

| Table              | Rows                      |
| ------------------ | ------------------------- |
| ServiceAppointment | 20,010                    |
| Repair             | 20,008 (10,004 Completed) |
| AuditLog           | 70,062                    |

AuditLog grew by 70,000 rows: one for each appointment insert, repair insert, Open → In Progress update, and In Progress → Completed update (20,000 + 20,000 + 20,000 + 10,000), plus the 62 rows from the sample data. This confirms that every row in the bulk load went through the audit triggers.

## Optimization Records

| Record                                              | Query                    | Pattern                            | Before                    | After                              | Speed-up | Reporting / aggregate? |
| --------------------------------------------------- | ------------------------ | ---------------------------------- | ------------------------- | ---------------------------------- | -------- | ---------------------- |
| [OPT-01](OPT-01_common_repairs_covering_index.md)   | RQ-03 Common Repairs     | Missing index → covering index     | 7.84 ms, 20,008 rows read | 2.21 ms, 10,004 index entries read | ~3.5×    | **Yes**                |
| [OPT-02](OPT-02_daily_appointments_range_filter.md) | RQ-01 Daily Appointments | Function on indexed column → range | 7.23 ms, 20,010 rows read | 0.0635 ms, 25 rows read            | ~110×    | No                     |
| [OPT-03](OPT-03_auditlog_keyset_pagination.md)      | Audit log paging         | OFFSET → keyset                    | 24.2 ms, 50,020 rows read | 0.163 ms, 20 rows read             | ~150×    | No                     |

Live before/after demo: **OPT-01**.

## Workload Notes

### Large batch transactions

`perf_data.sql` inserts and updates rows in single large statements. Every row passes through the validation and audit triggers. Timings from [`perf_data_output.txt`](perf_data_output.txt):

| Step                                                         | Rows affected      | Duration   | Approx. rows/second |
| ------------------------------------------------------------ | ------------------ | ---------- | ------------------- |
| Insert appointments (`INSERT ... SELECT` with recursive CTE) | 20,000             | 0.519 s    | ~38,500             |
| Insert repairs (`INSERT ... SELECT`)                         | 20,000             | 0.613 s    | ~32,600             |
| Update Open → In Progress                                    | 20,000             | 0.886 s    | ~22,600             |
| Update In Progress → Completed (`UPDATE ... JOIN`)           | 10,000             | 0.481 s    | ~20,800             |
| **Total**                                                    | **70,000 changes** | **2.50 s** |                     |

Updates are slower per row than inserts because each row fires both a BEFORE trigger (status transition and ownership validation) and an AFTER trigger (audit row with before/after JSON). Triggers run once per row, so bulk statements cost more than they would without triggers. In production, very large loads would be split into smaller committed batches (for example 1,000–5,000 rows) to keep transactions and lock times short.

### Reads

Report queries use indexes on appointment date, technician/date, vehicle/date, repair status/type, and audit entity/record (see TDD section 10). OPT-01 and OPT-02 show the effect of indexes on report reads.

### Updates and deletes

Updates filter on indexed or primary key columns so they lock only the rows they change. Deletes of finalized estimates, finalized invoices, and audit rows are blocked by triggers, and foreign keys use RESTRICT, so parent rows with children cannot be deleted.

### Large volume of transactions

Each workflow (booking, repair completion) is a short transaction that locks only the rows it needs (`SELECT ... FOR UPDATE` on one technician, vehicle, repair, or set of parts), so unrelated work proceeds in parallel.

### Large data extracts

Large exports should be read in pages. OPT-03 shows keyset pagination keeping each page fast regardless of depth, while OFFSET paging slows down as the offset grows.
