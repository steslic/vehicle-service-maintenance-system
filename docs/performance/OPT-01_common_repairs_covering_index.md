# OPT-01: Common Repairs report (RQ-03), covering index

**Target:** RQ-03, an aggregate reporting query (satisfies the "reporting view or aggregate query" requirement)
**Pattern:** Missing index → covering index
**Data volume:** 20,008 Repair rows (10,004 Completed) after `perf_data.sql`
**Script:** [`OPT-01_common_repairs_covering_index.sql`](OPT-01_common_repairs_covering_index.sql) · **Raw output:** [`OPT-01_output.txt`](OPT-01_output.txt)

## Query

```sql
SELECT RepairType, COUNT(*) AS TotalRepairs
FROM Repair
WHERE Status = 'Completed'
GROUP BY RepairType
ORDER BY TotalRepairs DESC;
```

## Hypothesis

Without an index on `Status`, MySQL must read every Repair row to find the completed ones (full table scan), then group them in a temporary table. An index on `(Status, RepairType)` contains both columns the query uses, so MySQL can answer it from the index alone (a covering index) without reading the table rows. Because index entries for `Status = 'Completed'` are already ordered by `RepairType`, MySQL can also count each group as it reads, with no temporary table.

## Before (index removed)

```sql
ALTER TABLE Repair DROP INDEX idx_Repair_Status_Type;
ANALYZE TABLE Repair;
-- then EXPLAIN and EXPLAIN ANALYZE on the query
```

EXPLAIN ANALYZE output:

```
-> Sort: TotalRepairs DESC  (actual time=7.84..7.84 rows=6 loops=1)
    -> Table scan on <temporary>  (actual time=7.61..7.62 rows=6 loops=1)
        -> Aggregate using temporary table  (actual time=7.61..7.61 rows=6 loops=1)
            -> Filter: (`repair`.`Status` = 'Completed')  (cost=2103 rows=2046) (actual time=0.135..5.35 rows=10004 loops=1)
                -> Table scan on Repair  (cost=2103 rows=20463) (actual time=0.132..4.22 rows=20008 loops=1)
```

| Measure           | Result                          |
| ----------------- | ------------------------------- |
| Access path       | Full table scan on Repair       |
| Index used        | None                            |
| Rows read         | 20,008 (every row)              |
| Grouping          | Aggregate using temporary table |
| Estimated cost    | 2103                            |
| Total actual time | 7.84 ms                         |

## Change (one change only)

```sql
CREATE INDEX idx_Repair_Status_Type ON Repair (Status, RepairType);
ANALYZE TABLE Repair;
```

## After

EXPLAIN ANALYZE output:

```
-> Sort: TotalRepairs DESC  (actual time=2.21..2.21 rows=6 loops=1)
    -> Stream results  (cost=3407 rows=140) (actual time=0.615..2.2 rows=6 loops=1)
        -> Group aggregate: count(0)  (cost=3407 rows=140) (actual time=0.614..2.2 rows=6 loops=1)
            -> Covering index lookup on Repair using idx_Repair_Status_Type (Status = 'Completed')  (cost=1132 rows=9870) (actual time=0.00988..1.42 rows=10004 loops=1)
```

| Measure                            | Result                                                 |
| ---------------------------------- | ------------------------------------------------------ |
| Access path                        | Covering index lookup (index only, no table rows read) |
| Index used                         | `idx_Repair_Status_Type`                               |
| Rows read                          | 10,004 (only Completed entries)                        |
| Grouping                           | Group aggregate while streaming (no temporary table)   |
| Estimated cost (index lookup step) | 1132                                                   |
| Total actual time                  | 2.21 ms                                                |

## Conclusion

Adding the composite index on `(Status, RepairType)` changed the plan from a full table scan of 20,008 rows to a covering index lookup that reads only the 10,004 completed entries, and removed the temporary table because the index already delivers rows grouped by `RepairType`. Total run time dropped from 7.84 ms to 2.21 ms (about 3.5× faster). The index is kept in `02_indexes.sql`. Its trade-off is a small extra cost on every Repair insert and status update, which is acceptable because repairs change status only a few times in their life while reports read them repeatedly.

**Live demo:** run `OPT-01_common_repairs_covering_index.sql` after loading `perf_data.sql`, and compare "Table scan on Repair" (before) with "Covering index lookup … using idx_Repair_Status_Type" (after).
