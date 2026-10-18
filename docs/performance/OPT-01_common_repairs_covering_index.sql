-- OPT-01: Common Repairs report (RQ-03), covering index
-- Run after perf_data.sql. Live demo: run this whole file top to bottom.
-- If your RQ-03 query in 03_views_reports.sql differs, paste yours in all four places.

USE vehicle_service_maintenance;

-- ===== BEFORE: remove the index =====
ALTER TABLE Repair DROP INDEX idx_Repair_Status_Type;
ANALYZE TABLE Repair;

EXPLAIN
SELECT RepairType, COUNT(*) AS TotalRepairs
FROM Repair WHERE Status = 'Completed'
GROUP BY RepairType ORDER BY TotalRepairs DESC;

EXPLAIN ANALYZE
SELECT RepairType, COUNT(*) AS TotalRepairs
FROM Repair WHERE Status = 'Completed'
GROUP BY RepairType ORDER BY TotalRepairs DESC;

-- ===== CHANGE: add the covering index back (one change) =====
CREATE INDEX idx_Repair_Status_Type ON Repair (Status, RepairType);
ANALYZE TABLE Repair;

-- ===== AFTER: same measurement =====
EXPLAIN
SELECT RepairType, COUNT(*) AS TotalRepairs
FROM Repair WHERE Status = 'Completed'
GROUP BY RepairType ORDER BY TotalRepairs DESC;

EXPLAIN ANALYZE
SELECT RepairType, COUNT(*) AS TotalRepairs
FROM Repair WHERE Status = 'Completed'
GROUP BY RepairType ORDER BY TotalRepairs DESC;
