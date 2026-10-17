-- Vehicle Service and Maintenance Management System
-- 06_sample_data.sql
-- Loads fictional sample data through the triggers and procedures.
--
-- Run after 05_triggers_roles.sql, as the administrative (root) account.
-- Every audited write runs with @app_user_id set to the acting user, so
-- the AuditLog is populated with realistic attribution.
--
-- Load order follows the validation rules:
--   * Technician, UserAccount, Customer, Vehicle, Part are not audited.
--   * Repairs move Open -> In Progress -> Completed (FRD transitions).
--   * Historical repairs are completed through sp_CompleteRepair, so parts
--     usage and inventory reductions are recorded exactly as in production.
--   * Estimates and invoices are inserted as Draft, given line items, and
--     then moved through their allowed transitions.
--
-- Note: sp_CompleteRepair sets CompletionDateTime and RecordedDateTime to
-- the time this script runs.

USE vehicle_service_maintenance;

SET @app_user_id = NULL;
SET @adj_reason  = NULL;


-- =====================================================================
-- 1. TECHNICIANS (not audited)
-- =====================================================================
INSERT INTO Technician (TechnicianID, Name, Phone, Email, ActiveStatus) VALUES
    (1, 'Ben Carter', '555-0101', 'ben.carter@example.com',  1),
    (2, 'Carla Diaz', '555-0102', 'carla.diaz@example.com',  1),
    (3, 'Dan Evans',  '555-0103', 'dan.evans@example.com',   0);   -- inactive


-- =====================================================================
-- 2. USER ACCOUNTS (not audited)
-- Usernames match the demo MySQL accounts created in 05_triggers_roles.sql
-- =====================================================================
INSERT INTO UserAccount (UserID, Username, Name, RoleType, TechnicianID) VALUES
    (1, 'mgr_mike',   'Mike Johnson', 'Manager',         NULL),
    (2, 'sa_amy',     'Amy Lee',      'Service Advisor', NULL),
    (3, 'tech_ben',   'Ben Carter',   'Technician',      1),
    (4, 'tech_carla', 'Carla Diaz',   'Technician',      2);


-- =====================================================================
-- 3. CUSTOMERS AND VEHICLES (not audited)
-- =====================================================================
INSERT INTO Customer (CustomerID, Name, Phone, Email) VALUES
    (1, 'Laura Martinez', '555-0201', 'laura.martinez@example.com'),
    (2, 'James Wilson',   '555-0202', 'james.wilson@example.com'),
    (3, 'Priya Shah',     '555-0203', 'priya.shah@example.com'),
    (4, 'Tom Becker',     '555-0204', NULL);

INSERT INTO Vehicle (VehicleID, CustomerID, VIN, Make, Model, `Year`) VALUES
    (1, 1, '1HGCV1F34LA012345', 'Honda',     'Accord',  2020),
    (2, 2, '1FTFW1E50MFA23456', 'Ford',      'F-150',   2021),
    (3, 3, '4T1B11HK5KU456789', 'Toyota',    'Camry',   2019),
    (4, 4, '1G1ZD5ST8JF567890', 'Chevrolet', 'Malibu',  2018),
    (5, 1, '2T3P1RFV0MW678901', 'Toyota',    'RAV4',    2021);   -- Laura owns two vehicles


-- =====================================================================
-- 4. PARTS (inserts are not audited; quantity updates are)
-- Starting quantities are chosen so that, after the historical repairs
-- below, Brake Rotor and Spark Plug fall under their minimum (RQ-04).
-- =====================================================================
INSERT INTO Part (PartID, PartNumber, PartName, QuantityOnHand, UnitCost,
                  UnitSellingPrice, MinimumInventoryLevel, ActiveStatus) VALUES
    (1, 'OF-100', 'Oil Filter',        26,  4.50,  9.99, 10, 1),
    (2, 'BP-200', 'Front Brake Pads',   9, 22.00, 49.99,  4, 1),
    (3, 'BR-300', 'Brake Rotor',        4, 35.00, 79.99,  4, 1),
    (4, 'AF-400', 'Engine Air Filter', 16,  6.00, 16.99,  5, 1),
    (5, 'SP-500', 'Spark Plug',         7,  3.00,  8.99,  8, 1),
    (6, 'WB-600', 'Wiper Blade',       10,  5.00, 14.99,  4, 0);   -- inactive


-- =====================================================================
-- 5. SERVICE APPOINTMENTS (audited; created by the service advisor)
-- Historical appointments are inserted directly because
-- sp_CreateServiceAppointment only accepts future dates.
-- =====================================================================
SET @app_user_id = 2;   -- Amy Lee, Service Advisor

INSERT INTO ServiceAppointment (AppointmentID, VehicleID, TechnicianID, CreatedByUserID,
        AppointmentDateTime, Status, ServiceRequestDescription, EstimatedDuration, CreationTimestamp) VALUES
    -- History (completed below)
    (1, 1, 1, 2, '2026-10-15 09:00:00', 'In Progress', 'Oil change',                            60, '2026-10-10 08:30:00'),
    (2, 2, 2, 2, '2026-10-15 10:00:00', 'In Progress', 'Grinding noise when braking',          120, '2026-10-10 09:00:00'),
    (3, 3, 1, 2, '2026-10-15 13:00:00', 'In Progress', 'Check engine light, rough idle',        90, '2026-10-11 10:15:00'),
    (4, 1, 2, 2, '2026-09-20 10:00:00', 'In Progress', 'Engine air filter replacement',         60, '2026-09-15 14:00:00'),
    -- Cancelled
    (5, 4, 1, 2, '2026-10-10 11:00:00', 'Scheduled',   'Tire rotation',                         60, '2026-10-05 16:20:00'),
    -- Active work in progress
    (6, 5, 1, 2, '2026-10-16 09:00:00', 'In Progress', 'Brake inspection and pad replacement', 120, '2026-10-12 11:00:00'),
    (7, 3, 2, 2, '2026-10-16 10:00:00', 'In Progress', 'Tune-up',                               60, '2026-10-13 09:45:00'),
    -- Upcoming
    (8, 4, 2, 2, '2026-11-03 14:00:00', 'Scheduled',   'Oil change',                            60, '2026-10-14 13:00:00'),
    (9, 2, 1, 2, '2026-11-04 09:00:00', 'Scheduled',   'Diagnose dashboard warning light',      60, '2026-10-14 15:30:00'),
    (10, 1, 2, 2, '2026-11-05 11:00:00', 'Scheduled',  'Replace wiper blades',                  45, '2026-10-15 10:00:00');

-- Customer cancelled appointment 5 (Scheduled -> Cancelled)
UPDATE ServiceAppointment
SET Status = 'Cancelled',
    CancellationDate = '2026-10-08',
    CancellationReason = 'Customer rescheduled with another shop'
WHERE AppointmentID = 5;


-- =====================================================================
-- 6. REPAIRS (audited; created by the service advisor as Open)
-- =====================================================================
INSERT INTO Repair (RepairID, AppointmentID, RepairDateTime, RepairType,
                    RepairDescription, LaborHours, Status) VALUES
    (1, 1, '2026-10-15 09:00:00', 'Oil Change',        'Drain and replace engine oil and filter',          0.50, 'Open'),
    (2, 2, '2026-10-15 10:00:00', 'Brake Service',     'Replace front brake pads and rotors',              2.00, 'Open'),
    (3, 3, '2026-10-15 13:00:00', 'Ignition Service',  'Replace spark plugs to correct misfire',           1.00, 'Open'),
    (4, 4, '2026-09-20 10:00:00', 'Filter Replacement','Replace engine air filter',                        0.25, 'Open'),
    (6, 6, '2026-10-16 09:00:00', 'Brake Service',     'Inspect brakes and replace front pads and rotors', 2.00, 'Open'),
    (7, 7, '2026-10-16 10:00:00', 'Tune-Up',           'Replace air filter and spark plugs',               1.00, 'Open'),
    (8, 8, '2026-11-03 14:00:00', 'Oil Change',        'Drain and replace engine oil and filter',          NULL, 'Open'),
    (9, 9, '2026-11-04 09:00:00', 'Diagnostic',        'Scan codes and diagnose warning light',            NULL, 'Open');

-- Technicians start their own repairs (Open -> In Progress).
-- The ownership check in trg_Repair_Status_Validate_bu applies here.
SET @app_user_id = 3;   -- Ben Carter, Technician 1
UPDATE Repair SET Status = 'In Progress' WHERE RepairID IN (1, 3, 6);

SET @app_user_id = 4;   -- Carla Diaz, Technician 2
UPDATE Repair SET Status = 'In Progress' WHERE RepairID IN (2, 4, 7);


-- =====================================================================
-- 7. COMPLETE HISTORICAL REPAIRS THROUGH sp_CompleteRepair
-- Each call records parts usage, reduces inventory, completes the repair,
-- and writes audit rows. The procedure sets and clears @app_user_id itself.
-- =====================================================================
CALL sp_CompleteRepair(1, 1, 3, '[{"partId": 1, "qty": 1}]');
CALL sp_CompleteRepair(2, 2, 4, '[{"partId": 2, "qty": 1}, {"partId": 3, "qty": 2}]');
CALL sp_CompleteRepair(3, 1, 3, '[{"partId": 5, "qty": 4}]');
CALL sp_CompleteRepair(4, 2, 4, '[{"partId": 4, "qty": 1}]');

-- Close the completed appointments (In Progress -> Completed)
SET @app_user_id = 2;   -- Amy Lee, Service Advisor
UPDATE ServiceAppointment SET Status = 'Completed' WHERE AppointmentID IN (1, 2, 3, 4);


-- =====================================================================
-- 8. MANUAL INVENTORY ADJUSTMENT (audited with a reason)
-- =====================================================================
SET @app_user_id = 1;   -- Mike Johnson, Manager
SET @adj_reason  = 'Received supplier shipment of 10 air filters';

UPDATE Part SET QuantityOnHand = QuantityOnHand + 10 WHERE PartID = 4;

SET @adj_reason = NULL;


-- =====================================================================
-- 9. REPAIR ESTIMATES (audited)
-- Inserted as Draft, given line items, then moved through the FRD
-- transitions. Approval is performed by the Manager.
-- =====================================================================
SET @app_user_id = 2;   -- Amy Lee, Service Advisor

INSERT INTO RepairEstimate (EstimateID, AppointmentID, CreatedByUserID, EstimateDate,
                            Status, TotalAmount) VALUES
    (1, 1, 2, '2026-10-14', 'Draft',  49.98),
    (2, 2, 2, '2026-10-14', 'Draft', 399.97),
    (3, 6, 2, '2026-10-16', 'Draft', 239.99),
    (4, 7, 2, '2026-10-16', 'Draft', 130.96);

INSERT INTO EstimateLineItem (EstimateID, LineNumber, Description, Quantity, UnitPrice, LineTotal) VALUES
    (1, 1, 'Oil change labor',         1, 39.99,  39.99),
    (1, 2, 'Oil filter',               1,  9.99,   9.99),
    (2, 1, 'Brake service labor (hr)', 2, 95.00, 190.00),
    (2, 2, 'Front brake pads',         1, 49.99,  49.99),
    (2, 3, 'Brake rotor',              2, 79.99, 159.98),
    (3, 1, 'Brake service labor (hr)', 2, 95.00, 190.00),
    (3, 2, 'Front brake pads',         1, 49.99,  49.99),
    (4, 1, 'Tune-up labor (hr)',       1, 95.00,  95.00),
    (4, 2, 'Spark plug',               4,  8.99,  35.96);

-- Submit estimates 1-3 for approval (Draft -> Pending Approval)
UPDATE RepairEstimate SET Status = 'Pending Approval' WHERE EstimateID IN (1, 2, 3);

-- Manager approves estimates 1 and 2 (Pending Approval -> Approved)
SET @app_user_id = 1;   -- Mike Johnson, Manager
UPDATE RepairEstimate
SET Status = 'Approved',
    ApprovedByUserID = 1,
    ApprovalDateTime = '2026-10-14 16:00:00'
WHERE EstimateID IN (1, 2);

-- Advisor finalizes the approved estimates (Approved -> Finalized)
SET @app_user_id = 2;   -- Amy Lee, Service Advisor
UPDATE RepairEstimate SET Status = 'Finalized' WHERE EstimateID IN (1, 2);

-- Estimate 3 stays Pending Approval; estimate 4 stays Draft.


-- =====================================================================
-- 10. INVOICES (audited)
-- Inserted as Draft, given line items, then finalized.
-- =====================================================================
SET @app_user_id = 2;   -- Amy Lee, Service Advisor

INSERT INTO Invoice (InvoiceID, AppointmentID, CreatedByUserID, InvoiceDate,
                     Status, TotalAmount) VALUES
    (1, 1, 2, '2026-10-15', 'Draft',  49.98),
    (2, 2, 2, '2026-10-15', 'Draft', 399.97),
    (3, 3, 2, '2026-10-15', 'Draft', 130.96),
    (4, 4, 2, '2026-09-20', 'Draft',  41.99);

INSERT INTO InvoiceLineItem (InvoiceID, Description, Quantity, UnitPrice, LineTotal) VALUES
    (1, 'Oil change labor',         1, 39.99,  39.99),
    (1, 'Oil filter',               1,  9.99,   9.99),
    (2, 'Brake service labor (hr)', 2, 95.00, 190.00),
    (2, 'Front brake pads',         1, 49.99,  49.99),
    (2, 'Brake rotor',              2, 79.99, 159.98),
    (3, 'Ignition labor (hr)',      1, 95.00,  95.00),
    (3, 'Spark plug',               4,  8.99,  35.96),
    (4, 'Filter replacement labor', 1, 25.00,  25.00),
    (4, 'Engine air filter',        1, 16.99,  16.99);

-- Advisor finalizes invoices 1 and 4 (Draft -> Finalized)
UPDATE Invoice
SET Status = 'Finalized', FinalizedByUserID = 2, FinalizationDateTime = '2026-10-15 11:30:00'
WHERE InvoiceID = 1;

UPDATE Invoice
SET Status = 'Finalized', FinalizedByUserID = 2, FinalizationDateTime = '2026-09-20 12:00:00'
WHERE InvoiceID = 4;

-- Manager finalizes invoice 2
SET @app_user_id = 1;   -- Mike Johnson, Manager
UPDATE Invoice
SET Status = 'Finalized', FinalizedByUserID = 1, FinalizationDateTime = '2026-10-15 13:00:00'
WHERE InvoiceID = 2;

-- Invoice 3 stays Draft.


-- =====================================================================
-- 11. CLEAN UP SESSION VARIABLES
-- =====================================================================
SET @app_user_id = NULL;
SET @adj_reason  = NULL;


-- =====================================================================
-- 12. LOAD SUMMARY
-- =====================================================================
SELECT 'Customer' AS TableName, COUNT(*) AS RowsLoaded FROM Customer
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