-- =====================================================================
-- Vehicle Service and Maintenance Management System
-- demo.sql : live demonstration script
--
-- One example for every item in "Required Final Demonstration":
--   1. Fresh build and data initialization          (root terminal)
--   2. Core business workflow                       (root terminal)
--   3. Common queries and performance evidence      (root terminal)
--   4. Entitlement demonstration                    (sa_amy / tech_ben / mgr_mike terminals)
--   5. Audit and traceability                       (root terminal)
--   6. Resiliency                                   (root terminal)
--
--   Terminals (from the repository root):
--     root     : /usr/local/mysql/bin/mysql -u root -p vehicle_service_maintenance
--     sa_amy   : /usr/local/mysql/bin/mysql -u sa_amy   -p vehicle_service_maintenance   (Advisor#2026)
--     tech_ben : /usr/local/mysql/bin/mysql -u tech_ben -p vehicle_service_maintenance   (Tech#2026)
--     mgr_mike : /usr/local/mysql/bin/mysql -u mgr_mike -p vehicle_service_maintenance   (Manager#2026)
--
--   Section 4 uses the real logins to show the GRANTs.
-- =====================================================================


-- =====================================================================
-- SECTION 1. FRESH BUILD AND DATA INITIALIZATION
-- =====================================================================

-- 1.1 In shell (documented README process):
--   git clone --branch v1.2 https://github.com/steslic/vehicle-service-maintenance-system.git
--   cd vehicle-service-maintenance-system/sql
--   /usr/local/mysql/bin/mysql --commands=ON -u root -p < build.sql

-- run just the tests: /usr/local/mysql/bin/mysql -t -u root -p vehicle_service_maintenance < 07_tests.sql
-- Point 06 load summary and the final PASS count (no FAIL rows)

-- 1.2 Verification (root terminal)
USE vehicle_service_maintenance;

-- Objects created: tables, views, procedures, triggers, indexes, constraints
SELECT 'Tables'            AS ObjectType, COUNT(*) AS Total FROM information_schema.TABLES
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE'
UNION ALL SELECT 'Views',            COUNT(*) FROM information_schema.VIEWS
    WHERE TABLE_SCHEMA = DATABASE()
UNION ALL SELECT 'Stored procedures', COUNT(*) FROM information_schema.ROUTINES
    WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE = 'PROCEDURE' AND ROUTINE_NAME NOT LIKE 'tst\_%'
UNION ALL SELECT 'Triggers',          COUNT(*) FROM information_schema.TRIGGERS
    WHERE TRIGGER_SCHEMA = DATABASE()
UNION ALL SELECT 'Foreign keys',      COUNT(*) FROM information_schema.REFERENTIAL_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE()
UNION ALL SELECT 'CHECK constraints', COUNT(*) FROM information_schema.CHECK_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE();

-- Performance indexes
SELECT TABLE_NAME, INDEX_NAME,
       GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS IndexColumns
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE() AND INDEX_NAME LIKE 'idx\_%'
GROUP BY TABLE_NAME, INDEX_NAME
ORDER BY TABLE_NAME, INDEX_NAME;

-- Roles and the demo users that hold them
SELECT FROM_USER AS RoleName, TO_USER AS GrantedToUser
FROM mysql.role_edges
WHERE FROM_USER LIKE 'role\_%'
ORDER BY FROM_USER;

-- Row counts (sample data loaded)
SELECT 'Customer' AS TableName, COUNT(*) AS RowCount FROM Customer
UNION ALL SELECT 'Vehicle',            COUNT(*) FROM Vehicle
UNION ALL SELECT 'Technician',         COUNT(*) FROM Technician
UNION ALL SELECT 'UserAccount',        COUNT(*) FROM UserAccount
UNION ALL SELECT 'Part',               COUNT(*) FROM Part
UNION ALL SELECT 'ServiceAppointment', COUNT(*) FROM ServiceAppointment
UNION ALL SELECT 'Repair',             COUNT(*) FROM Repair
UNION ALL SELECT 'PartsUsage',         COUNT(*) FROM PartsUsage
UNION ALL SELECT 'RepairEstimate',     COUNT(*) FROM RepairEstimate
UNION ALL SELECT 'EstimateLineItem',   COUNT(*) FROM EstimateLineItem
UNION ALL SELECT 'Invoice',            COUNT(*) FROM Invoice
UNION ALL SELECT 'InvoiceLineItem',    COUNT(*) FROM InvoiceLineItem
UNION ALL SELECT 'AuditLog',           COUNT(*) FROM AuditLog;


-- =====================================================================
-- SECTION 2. CORE BUSINESS WORKFLOW (root terminal)
-- New customer -> book -> check in -> repair -> complete with parts
-- -> close the appointment
-- =====================================================================

-- 2.1 Amy registers a new customer and her vehicle (FR-01)
INSERT INTO Customer (Name, Phone, Email)
VALUES ('Maria Gonzalez', '555-0205', 'maria.gonzalez@example.com');
SET @cust = LAST_INSERT_ID();

-- Maria's vehicle (VIN is unique)
INSERT INTO Vehicle (CustomerID, VIN, Make, Model, `Year`)
VALUES (@cust, '5YJ3E1EA7PF123456', 'Hyundai', 'Elantra', 2022);
SET @veh = LAST_INSERT_ID();

-- Amy corrects Maria's phone number (FR-01 update)
UPDATE Customer SET Phone = '555-0299' WHERE CustomerID = @cust;

SELECT c.CustomerID, c.Name, c.Phone, v.VehicleID, v.VIN, v.Make, v.Model
FROM Customer c JOIN Vehicle v ON v.CustomerID = c.CustomerID
WHERE c.CustomerID = @cust;

-- 2.2 Amy books the appointment with Ben through the procedure
CALL sp_CreateServiceAppointment(
    @cust,                          -- p_CustomerID: Maria
    @veh,                           -- p_VehicleID: her Elantra
    1,                              -- p_TechnicianID: Ben Carter
    2,                              -- p_CreatedByUserID: Amy (Service Advisor)
    '2026-12-02 09:00:00',          -- p_AppointmentDateTime
    '30,000 mile service',          -- p_ServiceRequestDescription
    60);                            -- p_EstimatedDuration (minutes)
SET @appt = LAST_INSERT_ID();

-- Retrieve the appointment with names instead of IDs
SELECT sa.AppointmentID, c.Name AS Customer, CONCAT(v.Make, ' ', v.Model) AS Vehicle,
       t.Name AS Technician, u.Name AS CreatedBy,
       sa.AppointmentDateTime, sa.EstimatedDuration, sa.Status
FROM ServiceAppointment sa
JOIN Vehicle v     ON v.VehicleID    = sa.VehicleID
JOIN Customer c    ON c.CustomerID   = v.CustomerID
JOIN Technician t  ON t.TechnicianID = sa.TechnicianID
JOIN UserAccount u ON u.UserID       = sa.CreatedByUserID
WHERE sa.AppointmentID = @appt;

-- 2.3 EXPECTED: ERROR "Technician already has a conflicting appointment"
--     Ben is booked 09:00-10:00; another car at 09:30 overlaps (BR-09)
CALL sp_CreateServiceAppointment(4, 4, 1, 2, '2026-12-02 09:30:00', 'Tire rotation', 60);

-- EXPECTED: ERROR "Vehicle does not belong to the customer" (FR-05)
--     Vehicle 999 does not exist, so it cannot belong to customer 1
CALL sp_CreateServiceAppointment(1, 999, 1, 2, '2026-12-01 09:00:00', 'Oil change', 60);

-- 2.4 EXPECTED: ERROR "Invalid appointment status transition"
--     Scheduled cannot jump straight to Completed
SET @app_user_id = 2;    -- Amy
UPDATE ServiceAppointment SET Status = 'Completed' WHERE AppointmentID = @appt;

-- 2.5 Maria arrives: Scheduled -> Checked In -> In Progress
UPDATE ServiceAppointment SET Status = 'Checked In'  WHERE AppointmentID = @appt;
UPDATE ServiceAppointment SET Status = 'In Progress' WHERE AppointmentID = @appt;

-- 2.6 Amy opens the repair (must start as Open)
INSERT INTO Repair (AppointmentID, RepairDateTime, RepairType, RepairDescription, LaborHours, Status)
VALUES (@appt, '2026-12-02 09:00:00', 'Scheduled Maintenance',
        'Oil and filter change, replace engine air filter', 1.00, 'Open');
SET @repair = LAST_INSERT_ID();

-- 2.7 Ben starts the repair: Open -> In Progress
SET @app_user_id = 3;    -- Ben
UPDATE Repair SET Status = 'In Progress' WHERE RepairID = @repair;

-- 2.8 BEFORE: inventory and parts usage
SELECT PartID, PartName, QuantityOnHand FROM Part WHERE PartID IN (1, 4);
SELECT COUNT(*) AS PartsUsageRows FROM PartsUsage WHERE RepairID = @repair;

-- 2.9 Ben completes the repair in one transaction: records parts at
--     current prices, reduces inventory, marks the repair Completed
CALL sp_CompleteRepair(@repair, 1, 3,
    '[{"partId": 1, "qty": 1}, {"partId": 4, "qty": 1}]');

-- 2.10 AFTER: one less of each part, two PartsUsage rows, repair Completed
SELECT PartID, PartName, QuantityOnHand FROM Part WHERE PartID IN (1, 4);

SELECT PartsUsageID, PartID, QuantityUsed, UnitSellingPriceAtTimeOfUse
FROM PartsUsage WHERE RepairID = @repair;

-- 2.11 Amy closes the service appointment: In Progress -> Completed
SET @app_user_id = 2;    -- Amy
UPDATE ServiceAppointment SET Status = 'Completed' WHERE AppointmentID = @appt;

-- 2.12 Retrieve the appointment and repair
SELECT sa.AppointmentID, sa.Status AS AppointmentStatus,
       r.RepairID, r.Status AS RepairStatus, r.CompletedByTechnicianID, r.CompletionDateTime
FROM ServiceAppointment sa
JOIN Repair r ON r.AppointmentID = sa.AppointmentID
WHERE sa.AppointmentID = @appt;


-- =====================================================================
-- SECTION 3. COMMON QUERIES AND PERFORMANCE (root terminal)
-- For each plan: tables joined, predicate, index chosen, rows read,
-- and lookup / range scan / full scan / sort.
-- =====================================================================

-- 3.1 RQ-01 Daily Service Appointments
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

-- Plan: index range scan on idx_ServiceAppointment_DateTime, then
-- primary-key lookups into Vehicle and Technician. No sort step:
-- the index already returns rows in AppointmentDateTime order.
SET @ReportDate = '2026-10-15';
EXPLAIN ANALYZE
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
ORDER BY sa.AppointmentDateTime\G

-- 3.2 RQ-03 Common Repairs (aggregation)
SELECT RepairType, COUNT(*) AS TotalRepairs
FROM Repair WHERE `Status` = 'Completed'
GROUP BY RepairType ORDER BY TotalRepairs DESC;

-- Plan: covering index lookup on idx_Repair_Status_Type (Status, RepairType):
-- reads only the index, never the table.
EXPLAIN ANALYZE
SELECT RepairType, COUNT(*) AS TotalRepairs
FROM Repair WHERE `Status` = 'Completed'
GROUP BY RepairType ORDER BY TotalRepairs DESC\G

-- 3.3 RQ-04 Low Parts Inventory (exception report)
SELECT
    PartID,
    PartNumber,
    PartName,
    QuantityOnHand,
    MinimumInventoryLevel
FROM Part
WHERE QuantityOnHand < MinimumInventoryLevel
ORDER BY QuantityOnHand;

-- Plan: full table scan, by design. It compares two columns
-- of the same row, which index cannot answer
EXPLAIN
SELECT
    PartID,
    PartNumber,
    PartName,
    QuantityOnHand,
    MinimumInventoryLevel
FROM Part
WHERE QuantityOnHand < MinimumInventoryLevel
ORDER BY QuantityOnHand\G

-- END of the demo, from shell: 
--   /usr/local/mysql/bin/mysql -u root -p < docs/performance/perf_data.sql
--   /usr/local/mysql/bin/mysql -t -u root -p < docs/performance/OPT-01_common_repairs_covering_index.sql


-- =====================================================================
-- SECTION 4. ENTITLEMENTS (real role logins)
-- =====================================================================

-- 4.1 [root] What a technician is granted
SHOW GRANTS FOR 'tech_ben'@'localhost' USING 'role_technician';

SHOW GRANTS FOR 'sa_amy'@'localhost'   USING 'role_service_advisor';
SHOW GRANTS FOR 'mgr_mike'@'localhost' USING 'role_manager';

-- 4.2 Same action, authorized vs unauthorized role (SEC-01)
-- [sa_amy] ALLOWED: the advisor extends appointment 9 to 90 minutes
SET @app_user_id = 2;
UPDATE ServiceAppointment SET EstimatedDuration = 90 WHERE AppointmentID = 9;

-- [tech_ben] EXPECTED: ERROR "UPDATE command denied to user 'tech_ben'@'localhost'"
SET @app_user_id = 3;
UPDATE ServiceAppointment SET EstimatedDuration = 120 WHERE AppointmentID = 9;

-- [tech_ben] EXPECTED: ERROR "SELECT command denied ... for table 'Customer'" (SEC-02)
SELECT * FROM Customer;

-- 4.3 Row-level access: a technician sees and acts only on his own work (SEC-02)
--     (repair 8 is Carla's, repair 9 is Ben's)
-- [tech_ben] EXPECTED: ERROR "SELECT command denied ... for table 'Repair'"
SELECT * FROM Repair;

-- [tech_ben] ALLOWED: only his own appointments and repairs, through the views
SELECT AppointmentID, AppointmentDateTime, Status, Make, Model FROM vw_MyAppointments;
SELECT RepairID, AppointmentID, RepairType, Status FROM vw_MyRepairs;

-- [tech_ben] Carla's repair 8 is not visible to him: "0 rows affected"
UPDATE vw_MyRepairs SET Status = 'In Progress' WHERE RepairID = 8;

-- [tech_ben] ALLOWED: start his own repair
UPDATE vw_MyRepairs SET Status = 'In Progress' WHERE RepairID = 9;

-- [tech_ben] EXPECTED: ERROR "Check constraint 'chk_Repair_Completion' is violated."
--            Completing must go through the controlled procedure 
UPDATE vw_MyRepairs SET Status = 'Completed' WHERE RepairID = 9;

-- [tech_ben] EXPECTED: ERROR "Appointment must be In Progress to complete a repair"
--            Appointment 9 is still Scheduled: the car is not in the shop yet
CALL sp_CompleteRepair(9, 1, 3, NULL);

-- [sa_amy] The customer arrives: Amy checks in and starts appointment 9
SET @app_user_id = 2;
UPDATE ServiceAppointment SET Status = 'Checked In'  WHERE AppointmentID = 9;
UPDATE ServiceAppointment SET Status = 'In Progress' WHERE AppointmentID = 9;

-- [tech_ben] ALLOWED: complete it through the procedure (labor only).
--            He has no write access to PartsUsage or Part; the procedure
--            runs with its definer's privileges.
CALL sp_CompleteRepair(9, 1, 3, NULL);

-- 4.4 Approval is Manager-only (estimate 3 is Pending Approval)
-- [sa_amy] EXPECTED: ERROR "Estimates must be approved or rejected by a Manager"
UPDATE RepairEstimate SET Status = 'Approved', ApprovedByUserID = 2 WHERE EstimateID = 3;

-- [sa_amy] EXPECTED: ERROR "Acting user must be the logged-in user"
--          Amy cannot pretend to be Mike: @app_user_id is checked against her login
SET @app_user_id = 1;
UPDATE RepairEstimate SET Status = 'Approved', ApprovedByUserID = 1 WHERE EstimateID = 3;
SET @app_user_id = 2;

-- [mgr_mike] Allowed to approve estimate 3 
SET @app_user_id = 1;
UPDATE RepairEstimate SET Status = 'Approved', ApprovedByUserID = 1 WHERE EstimateID = 3;
SELECT EstimateID, Status, ApprovedByUserID, ApprovalDateTime FROM RepairEstimate WHERE EstimateID = 3;


-- =====================================================================
-- SECTION 5. AUDIT AND TRACEABILITY (root terminal, same session as Section 2)
-- =====================================================================

-- Only if the root terminal was reconnected since Section 2, restore the IDs:
-- SET @appt   = (SELECT sa.AppointmentID FROM ServiceAppointment sa JOIN Vehicle v ON v.VehicleID = sa.VehicleID
--                WHERE v.VIN = '5YJ3E1EA7PF123456' AND sa.AppointmentDateTime = '2026-12-02 09:00:00');
-- SET @repair = (SELECT RepairID FROM Repair WHERE AppointmentID = @appt);

-- 5.1 Lifecycle of customer Maria's appointment from the audit trail:
--     who did what, when, and the status before and after
SELECT a.AuditLogID, a.`Timestamp`, u.Username AS Actor,
       a.Action, a.AffectedEntity, a.AffectedRecordID,
       JSON_UNQUOTE(JSON_EXTRACT(a.PreviousValue, '$.Status')) AS OldStatus,
       JSON_UNQUOTE(JSON_EXTRACT(a.NewValue,      '$.Status')) AS NewStatus
FROM AuditLog a
JOIN UserAccount u ON u.UserID = a.UserID
WHERE (a.AffectedEntity = 'ServiceAppointment' AND a.AffectedRecordID = @appt)
   OR (a.AffectedEntity = 'Repair'     AND a.AffectedRecordID = @repair)
   OR (a.AffectedEntity = 'PartsUsage' AND a.AffectedRecordID IN
          (SELECT PartsUsageID FROM PartsUsage WHERE RepairID = @repair))
ORDER BY a.AuditLogID;

-- Raw rows 
SELECT * FROM AuditLog
WHERE AffectedEntity = 'ServiceAppointment' AND AffectedRecordID = @appt;

-- 5.2 Full before/after values for one change (the Manager's approval in 4.4)
-- Audit row in full 
SELECT a.AuditLogID, u.Username AS Actor, a.Action, a.PreviousValue, a.NewValue
FROM AuditLog a JOIN UserAccount u ON u.UserID = a.UserID
WHERE a.AffectedEntity = 'RepairEstimate' AND a.AffectedRecordID = 3 AND a.Action = 'Approve';

-- 5.3 Audit records cannot be altered or deleted, even by root
-- EXPECTED: ERROR "Audit records cannot be modified"
UPDATE AuditLog SET Action = 'Tampered' WHERE AuditLogID = 1;

-- EXPECTED: ERROR "Audit records cannot be deleted"
DELETE FROM AuditLog WHERE AuditLogID = 1;

-- 5.4 Finalized and completed records are locked
SET @app_user_id = 1;    -- Mike (Manager)

-- EXPECTED: ERROR "Finalized invoices cannot be modified" (invoice 1 is Finalized)
UPDATE Invoice SET TotalAmount = 1.00 WHERE InvoiceID = 1;

-- EXPECTED: ERROR "Completed, cancelled, or no-show appointments cannot be modified"
UPDATE ServiceAppointment SET EstimatedDuration = 30 WHERE AppointmentID = @appt;


-- =====================================================================
-- SECTION 6. RESILIENCY (root terminal)
-- =====================================================================

-- 6.1 Setup: Carla's appointment 8 is checked in and her repair 8 started
SET @app_user_id = 2;    -- Amy (sa)
UPDATE ServiceAppointment SET Status = 'Checked In'  WHERE AppointmentID = 8;
UPDATE ServiceAppointment SET Status = 'In Progress' WHERE AppointmentID = 8;
SET @app_user_id = 4;    -- Carla (tech)
UPDATE Repair SET Status = 'In Progress' WHERE RepairID = 8;

-- 6.2 BEFORE the failed transaction
-- snapshot of everything the failed transaction could change
SELECT PartID, PartName, QuantityOnHand FROM Part WHERE PartID IN (1, 3);
SELECT (SELECT Status FROM Repair WHERE RepairID = 8)          AS RepairStatus,
       (SELECT COUNT(*) FROM PartsUsage WHERE RepairID = 8)    AS PartsUsageRows,
       (SELECT COUNT(*) FROM AuditLog
         WHERE Action <> 'Rejected')                           AS DataAuditRows;

-- 6.3 EXPECTED: ERROR "Insufficient parts inventory"
--     1 oil filter (in stock) + 5 brake rotors (not in stock):
--     the whole call rolls back, including the oil filter
CALL sp_CompleteRepair(8, 2, 4, '[{"partId": 1, "qty": 1}, {"partId": 3, "qty": 5}]');

-- 6.4 AFTER: identical to 6.2 (no partial work, no data-change audit rows)
SELECT PartID, PartName, QuantityOnHand FROM Part WHERE PartID IN (1, 3);
SELECT (SELECT Status FROM Repair WHERE RepairID = 8)          AS RepairStatus,
       (SELECT COUNT(*) FROM PartsUsage WHERE RepairID = 8)    AS PartsUsageRows,
       (SELECT COUNT(*) FROM AuditLog
         WHERE Action <> 'Rejected')                           AS DataAuditRows;

-- 6.5 Failure audit: the rejected attempt itself is recorded, written
--     after the rollback so it survives (who, what, why)
SELECT a.AuditLogID, u.Username AS Actor, a.Action, a.AffectedEntity,
       a.AffectedRecordID, JSON_UNQUOTE(a.NewValue->'$.Error') AS Error, a.ContextID
FROM AuditLog a JOIN UserAccount u ON u.UserID = a.UserID
WHERE a.Action = 'Rejected' AND a.AffectedEntity = 'Repair' AND a.AffectedRecordID = 8;

-- 6.6 Correction and retry with the right part list: succeeds
CALL sp_CompleteRepair(8, 2, 4, '[{"partId": 1, "qty": 1}]');
SELECT RepairID, Status, CompletedByTechnicianID FROM Repair WHERE RepairID = 8;

-- 6.7 Cancellation: Amy cancels appointment 10 with a reason
--     (CancellationDate is filled in by the trigger)
SET @app_user_id = 2;    -- Amy
UPDATE ServiceAppointment
SET Status = 'Cancelled', CancellationReason = 'Customer sold the vehicle'
WHERE AppointmentID = 10;
SELECT AppointmentID, Status, CancellationDate, CancellationReason
FROM ServiceAppointment WHERE AppointmentID = 10;

-- EXPECTED: ERROR "Completed, cancelled, or no-show appointments cannot be modified"
UPDATE ServiceAppointment SET Status = 'Checked In' WHERE AppointmentID = 10;

SET @app_user_id = NULL;

-- =====================================================================
-- End of demo
-- =====================================================================