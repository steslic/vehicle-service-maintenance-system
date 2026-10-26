-- Vehicle Service and Maintenance Management System
-- docs/performance/perf_data.sql
-- Generates a large data set for performance measurement.
-- from the repo root
-- /usr/local/mysql/bin/mysql -u root -p < docs/performance/perf_data.sql
-- /usr/local/mysql/bin/mysql -t -u root -p < docs/performance/OPT-01_common_repairs_covering_index.sql

USE vehicle_service_maintenance;

SET SESSION cte_max_recursion_depth = 100000;
SET @app_user_id = 1;      -- Manager performs the bulk load (audited)
SET @rows = 20000;         -- number of appointments and repairs to generate

-- ---------------------------------------------------------------------
-- Step 1: 20,000 appointments (one large INSERT ... SELECT batch)
-- About 25 per day starting 2024-01-01, spread across vehicles 1-5 and
-- technicians 1-2. Inserted as In Progress so repairs can be attached.
-- ---------------------------------------------------------------------
INSERT INTO ServiceAppointment (VehicleID, TechnicianID, CreatedByUserID,
        AppointmentDateTime, Status, ServiceRequestDescription,
        EstimatedDuration, CreationTimestamp)
WITH RECURSIVE seq (n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < @rows
)
SELECT 1 + MOD(n, 5),
       1 + MOD(n, 2),
       2,
       TIMESTAMP('2024-01-01 08:00:00')
           + INTERVAL (n DIV 25) DAY
           + INTERVAL (MOD(n, 25) * 20) MINUTE,
       'In Progress',
       CONCAT('Perf test appointment ', n),
       60,
       NOW()
FROM seq;

-- ---------------------------------------------------------------------
-- Step 2: one Open repair per performance appointment
-- Eight repair types so the Common Repairs report has groups to count.
-- ---------------------------------------------------------------------
INSERT INTO Repair (AppointmentID, RepairDateTime, RepairType,
                    RepairDescription, LaborHours, Status)
SELECT AppointmentID,
       AppointmentDateTime,
       ELT(1 + MOD(AppointmentID, 8),
           'Oil Change', 'Brake Service', 'Tire Rotation', 'Battery Replacement',
           'Diagnostic', 'Tune-Up', 'Filter Replacement', 'Ignition Service'),
       'Perf test repair',
       1.00,
       'Open'
FROM ServiceAppointment
WHERE ServiceRequestDescription LIKE 'Perf test appointment%';

-- ---------------------------------------------------------------------
-- Step 3: large batch update (Open -> In Progress) through the triggers
-- ---------------------------------------------------------------------
UPDATE Repair
SET Status = 'In Progress'
WHERE RepairDescription = 'Perf test repair';

-- ---------------------------------------------------------------------
-- Step 4: complete half of them (In Progress -> Completed)
-- ---------------------------------------------------------------------
UPDATE Repair r
JOIN ServiceAppointment sa ON sa.AppointmentID = r.AppointmentID
SET r.Status = 'Completed',
    r.CompletedByTechnicianID = sa.TechnicianID,
    r.CompletionDateTime = r.RepairDateTime + INTERVAL 1 HOUR
WHERE r.RepairDescription = 'Perf test repair'
  AND MOD(r.RepairID, 2) = 0;

-- ---------------------------------------------------------------------
-- Step 5: refresh optimizer statistics after the bulk load
-- ---------------------------------------------------------------------
ANALYZE TABLE ServiceAppointment, Repair, AuditLog;

SET @app_user_id = NULL;

-- ---------------------------------------------------------------------
-- Data volume after the load (record these in README.md)
-- ---------------------------------------------------------------------
SELECT 'ServiceAppointment' AS TableName, COUNT(*) AS RowsNow FROM ServiceAppointment
UNION ALL SELECT 'Repair',   COUNT(*) FROM Repair
UNION ALL SELECT 'AuditLog', COUNT(*) FROM AuditLog;
