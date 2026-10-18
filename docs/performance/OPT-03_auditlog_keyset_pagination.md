# OPT-03: Paging through the audit log, OFFSET → keyset pagination

**Target:** Reading the AuditLog 20 rows at a time (large data extract / reads)
**Pattern:** OFFSET → keyset
**Data volume:** more than 50,020 AuditLog rows after `perf_data.sql` (exact count in `perf_data_output.txt`)
**Script:** [`OPT-03_auditlog_keyset_pagination.sql`](OPT-03_auditlog_keyset_pagination.sql) · **Raw output:** [`OPT-03_output.txt`](OPT-03_output.txt)

## Query

A manager or auditor reviewing or exporting the audit trail reads it one page at a time, oldest first. The common way to fetch page N is `LIMIT` with `OFFSET`:

```sql
-- Page 2,501 at 20 rows per page (skip 50,000 rows)
SELECT AuditLogID, UserID, Action, AffectedEntity, AffectedRecordID, `Timestamp`
FROM AuditLog
ORDER BY AuditLogID
LIMIT 20 OFFSET 50000;
```

AuditLog grows with every audited change and is never deleted (it is append-only), so deep pages become more common as the system is used. This record compares OFFSET paging with keyset paging on the same page.

## Hypothesis

`LIMIT 20 OFFSET 50000` makes MySQL read and throw away 50,000 rows before returning 20, so each page gets slower the deeper you go. Keyset pagination remembers the last `AuditLogID` from the previous page and asks for the next 20 after it; the primary key index jumps straight there, so every page costs about the same.

## Before (OFFSET)

```sql
ANALYZE TABLE AuditLog;

EXPLAIN ANALYZE
SELECT AuditLogID, UserID, Action, AffectedEntity, AffectedRecordID, `Timestamp`
FROM AuditLog
ORDER BY AuditLogID
LIMIT 20 OFFSET 50000;
```

EXPLAIN ANALYZE output:

```
-> Limit/Offset: 20/50000 row(s)  (cost=3967 rows=20) (actual time=24.2..24.2 rows=20 loops=1)
    -> Index scan on AuditLog using PRIMARY  (cost=3967 rows=50020) (actual time=1.53..22.5 rows=50020 loops=1)
```

| Measure                   | Result                                             |
| ------------------------- | -------------------------------------------------- |
| Access path               | Index scan on PRIMARY from the first row           |
| Rows read                 | 50,020 (50,000 skipped and discarded, 20 returned) |
| Total actual time         | 24.2 ms                                            |
| First AuditLogID returned | 50001                                              |

## Change (one change only): filter on the last seen key instead of skipping rows

The script sets `@last_seen_id` to the last ID of the previous page (here 50000), then:

```sql
EXPLAIN ANALYZE
SELECT AuditLogID, UserID, Action, AffectedEntity, AffectedRecordID, `Timestamp`
FROM AuditLog
WHERE AuditLogID > @last_seen_id
ORDER BY AuditLogID
LIMIT 20;
```

## After

EXPLAIN ANALYZE output:

```
-> Limit: 20 row(s)  (cost=6753 rows=20) (actual time=0.159..0.163 rows=20 loops=1)
    -> Filter: (auditlog.AuditLogID > <cache>((@last_seen_id)))  (cost=6753 rows=33708) (actual time=0.158..0.161 rows=20 loops=1)
        -> Index range scan on AuditLog using PRIMARY over (50000 < AuditLogID)  (cost=6753 rows=33708) (actual time=0.155..0.158 rows=20 loops=1)
```

| Measure                                       | Result                                                   |
| --------------------------------------------- | -------------------------------------------------------- |
| Access path                                   | Index range scan on PRIMARY starting at AuditLogID 50001 |
| Rows read                                     | 20                                                       |
| Total actual time                             | 0.163 ms                                                 |
| First AuditLogID returned (must match Before) | 50001                                                    |

## Conclusion

The OFFSET query read 50,020 rows through the primary key and discarded 50,000 of them to return one page of 20, taking 24.2 ms. The keyset query used the primary key to start directly after AuditLogID 50000 and read only the 20 rows it returned, taking 0.163 ms (about 150× faster). Both returned the same page, starting at AuditLogID 50001. OFFSET cost grows with page depth, while keyset cost stays constant, which matters for large audit extracts. The optimizer's estimated cost is higher for the keyset plan (6753 vs 3967) because the estimate assumes it may read all remaining rows and does not account for `LIMIT` stopping early; the actual rows and time show the real behavior. Trade-off: keyset needs a stable, unique sort key (here the primary key) and supports next/previous page navigation, not jumping directly to an arbitrary page number.
