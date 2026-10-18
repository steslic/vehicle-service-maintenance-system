-- OPT-03: Paging through the audit log, OFFSET -> keyset pagination
-- Run after perf_data.sql.

USE vehicle_service_maintenance;
ANALYZE TABLE AuditLog;

-- ===== BEFORE: skip 50,000 rows with OFFSET =====
EXPLAIN ANALYZE
SELECT AuditLogID, UserID, Action, AffectedEntity, AffectedRecordID, `Timestamp`
FROM AuditLog
ORDER BY AuditLogID
LIMIT 20 OFFSET 50000;

-- Remember where that page starts (the last ID of the previous page)
SELECT AuditLogID - 1 INTO @last_seen_id
FROM AuditLog
ORDER BY AuditLogID
LIMIT 1 OFFSET 50000;

SELECT @last_seen_id AS LastSeenID;

-- ===== CHANGE + AFTER: continue from the last seen key (one change) =====
EXPLAIN ANALYZE
SELECT AuditLogID, UserID, Action, AffectedEntity, AffectedRecordID, `Timestamp`
FROM AuditLog
WHERE AuditLogID > @last_seen_id
ORDER BY AuditLogID
LIMIT 20;

-- Both pages must start at the same row
SELECT
    (SELECT AuditLogID FROM AuditLog ORDER BY AuditLogID LIMIT 1 OFFSET 50000) AS FirstID_Offset,
    (SELECT AuditLogID FROM AuditLog WHERE AuditLogID > @last_seen_id
     ORDER BY AuditLogID LIMIT 1) AS FirstID_Keyset;
