# OPT-02: Daily Service Appointments (RQ-01), function on an indexed column

**Target:** RQ-01, daily appointment lookup
**Pattern:** Don't wrap indexed columns in functions
**Data volume:** 20,010 ServiceAppointment rows after `perf_data.sql`
**Script:** [`OPT-02_daily_appointments_range_filter.sql`](OPT-02_daily_appointments_range_filter.sql) · **Raw output:** [`OPT-02_output.txt`](OPT-02_output.txt)

## Query

RQ-01 (in `03_views_reports.sql`) lists one day's appointments with vehicle and technician details:

```sql
SET @ReportDate = '2026-10-15';
SELECT
    sa.AppointmentID,
    sa.AppointmentDateTime,
    sa.Status,
    v.VehicleID,
    v.VIN,
    v.Make,
    v.Model,
    t.TechnicianID,
    t.Name AS TechnicianName
FROM ServiceAppointment sa
JOIN Vehicle v
    ON sa.VehicleID = v.VehicleID
JOIN Technician t
    ON sa.TechnicianID = t.TechnicianID
WHERE sa.AppointmentDateTime >= @ReportDate
  AND sa.AppointmentDateTime < @ReportDate + INTERVAL 1 DAY
ORDER BY sa.AppointmentDateTime;
```

The cost of this report is driven by how the date filter finds rows in ServiceAppointment; the joins to Vehicle and Technician are primary key lookups for each matching row. To measure one change, this record isolates the date filter on ServiceAppointment and compares the common mistake, `DATE(AppointmentDateTime) = ...`, with the range form that RQ-01 uses. The test date is 2024-03-15 because that day has 25 appointments in the performance data.

## Hypothesis

`idx_ServiceAppointment_DateTime` indexes `AppointmentDateTime`. Writing the filter as `DATE(AppointmentDateTime) = ...` applies a function to every row's value, so MySQL cannot use the index and scans the whole table. Rewriting the same filter as a range on the raw column lets MySQL use the index to jump straight to that day, and because the index is already sorted by `AppointmentDateTime`, the separate sort step should also disappear.

## Before (function on the column)

```sql
ANALYZE TABLE ServiceAppointment;

EXPLAIN ANALYZE
SELECT AppointmentID, AppointmentDateTime, Status
FROM ServiceAppointment
WHERE DATE(AppointmentDateTime) = '2024-03-15'
ORDER BY AppointmentDateTime;
```

EXPLAIN ANALYZE output:

```
-> Sort: serviceappointment.AppointmentDateTime  (cost=2047 rows=20071) (actual time=7.23..7.23 rows=25 loops=1)
    -> Filter: (cast(serviceappointment.AppointmentDateTime as date) = '2024-03-15')  (cost=2047 rows=20071) (actual time=1.03..7.15 rows=25 loops=1)
        -> Table scan on ServiceAppointment  (cost=2047 rows=20071) (actual time=0.351..5.77 rows=20010 loops=1)
```

| Measure           | Result                                          |
| ----------------- | ----------------------------------------------- |
| Access path       | Full table scan on ServiceAppointment           |
| Index used        | None (`DATE()` hides the column from the index) |
| Rows read         | 20,010 (every row)                              |
| Extra steps       | Filter on every row, then a separate sort       |
| Estimated cost    | 2047                                            |
| Total actual time | 7.23 ms                                         |
| Rows returned     | 25                                              |

## Change (one change only): rewrite the filter as a range

```sql
EXPLAIN ANALYZE
SELECT AppointmentID, AppointmentDateTime, Status
FROM ServiceAppointment
WHERE AppointmentDateTime >= '2024-03-15'
  AND AppointmentDateTime <  '2024-03-16'
ORDER BY AppointmentDateTime;
```

## After

EXPLAIN ANALYZE output:

```
-> Index range scan on ServiceAppointment using idx_ServiceAppointment_DateTime over ('2024-03-15 00:00:00' <= AppointmentDateTime < '2024-03-16 00:00:00'), with index condition: ((serviceappointment.AppointmentDateTime >= TIMESTAMP'2024-03-15 00:00:00') and (serviceappointment.AppointmentDateTime < TIMESTAMP'2024-03-16 00:00:00'))  (cost=11.5 rows=25) (actual time=0.059..0.0635 rows=25 loops=1)
```

| Measure                           | Result                                                        |
| --------------------------------- | ------------------------------------------------------------- |
| Access path                       | Index range scan                                              |
| Index used                        | `idx_ServiceAppointment_DateTime`                             |
| Rows read                         | 25 (only that day's appointments)                             |
| Extra steps                       | None; rows come out of the index already in order, so no sort |
| Estimated cost                    | 11.5                                                          |
| Total actual time                 | 0.0635 ms                                                     |
| Rows returned (must equal Before) | 25                                                            |

## Conclusion

Wrapping `AppointmentDateTime` in `DATE()` forced a full table scan of 20,010 rows followed by a sort. Rewriting the same condition as a half-open range (`>= '2024-03-15' AND < '2024-03-16'`) let MySQL use `idx_ServiceAppointment_DateTime` to read only the 25 matching rows, already in order, so the sort step was removed. Both versions returned the same 25 rows. Estimated cost dropped from 2047 to 11.5 and actual time from 7.23 ms to 0.0635 ms (about 110× faster). No index was added; the existing index simply became usable. RQ-01 in `03_views_reports.sql` already uses the range form. The half-open range (`<` the next day) includes every time on 2024-03-15 without needing `23:59:59`.
