-- Vehicle Service and Maintenance Management System
-- 03_views_reports.sql

USE vehicle_service_maintenance;

-- View 1: Vehicle service history
-- Shows completed repairs and parts used for each vehicle
CREATE OR REPLACE VIEW vw_VehicleServiceHistory AS
SELECT
    v.VehicleID,
    v.VIN,
    v.Make,
    v.Model,
    v.Year,
    sa.AppointmentID,
    r.RepairID,
    r.RepairType,
    r.RepairDescription,
    r.CompletionDateTime,
    p.PartID,
    p.PartName,
    pu.QuantityUsed
FROM Vehicle v
JOIN ServiceAppointment sa
    ON v.VehicleID = sa.VehicleID
JOIN Repair r
    ON sa.AppointmentID = r.AppointmentID
LEFT JOIN PartsUsage pu
    ON r.RepairID = pu.RepairID
LEFT JOIN Part p
    ON pu.PartID = p.PartID
WHERE r.Status = 'Completed';


-- View 2: Technician workload
-- Shows service appointments assigned to each technician
CREATE OR REPLACE VIEW vw_TechnicianWorkload AS
SELECT
    t.TechnicianID,
    t.Name AS TechnicianName,
    t.ActiveStatus,
    sa.AppointmentID,
    sa.AppointmentDateTime,
    sa.Status AS AppointmentStatus
FROM Technician t
LEFT JOIN ServiceAppointment sa
    ON t.TechnicianID = sa.TechnicianID;


-- RQ-01: Daily service appointments
-- Shows appointments for a selected date
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


-- RQ-02: Vehicle service history
-- Shows completed repairs for a selected vehicle
SELECT
    VehicleID,
    VIN,
    Make,
    Model,
    RepairID,
    RepairType,
    RepairDescription,
    CompletionDateTime,
    PartName,
    QuantityUsed
FROM vw_VehicleServiceHistory
WHERE VehicleID = 1
ORDER BY CompletionDateTime DESC;


-- RQ-03: Common repairs report
-- Counts completed repairs by repair type
SELECT
    RepairType,
    COUNT(*) AS TotalRepairs
FROM Repair
WHERE `Status` = 'Completed'
GROUP BY RepairType
ORDER BY TotalRepairs DESC;


-- RQ-04: Low parts inventory report
-- Shows parts below their minimum inventory level
SELECT
    PartID,
    PartNumber,
    PartName,
    QuantityOnHand,
    MinimumInventoryLevel
FROM Part
WHERE QuantityOnHand < MinimumInventoryLevel
ORDER BY QuantityOnHand;


-- RQ-05: Shop workload report
-- Counts active appointments assigned to each technician
SELECT
    TechnicianID,
    TechnicianName,
    COUNT(
        CASE
            WHEN AppointmentStatus IN (
                'Scheduled',
                'Checked In',
                'In Progress'
            )
            THEN AppointmentID
        END
    ) AS ActiveAppointments
FROM vw_TechnicianWorkload
GROUP BY TechnicianID, TechnicianName
ORDER BY ActiveAppointments DESC;


-- RQ-06: Parts revenue report
-- Calculates total quantity used and revenue for each part
SELECT
    p.PartID,
    p.PartNumber,
    p.PartName,
    SUM(pu.QuantityUsed) AS TotalQuantityUsed,
    SUM(
        pu.QuantityUsed * pu.UnitSellingPriceAtTimeOfUse
    ) AS TotalRevenue
FROM Part p
JOIN PartsUsage pu
    ON p.PartID = pu.PartID
JOIN Repair r
    ON pu.RepairID = r.RepairID
WHERE r.Status = 'Completed'
GROUP BY
    p.PartID,
    p.PartNumber,
    p.PartName
ORDER BY TotalRevenue DESC;