-- Final views and unchanged report queries. Run after 04 (label function).
USE vehicle_service_maintenance;

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
    pu.QuantityUsed,
    fn_IndicatorDescription('repair_type', r.RepairType) AS RepairTypeDescription,
    fn_IndicatorDescription('repair_status', r.Status) AS RepairStatusDescription
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

CREATE OR REPLACE VIEW vw_TechnicianWorkload AS
SELECT
    t.TechnicianID,
    t.Name AS TechnicianName,
    t.ActiveStatus,
    sa.AppointmentID,
    sa.AppointmentDateTime,
    sa.Status AS AppointmentStatus,
    fn_IndicatorDescription('active_status', CAST(t.ActiveStatus AS CHAR)) AS ActiveStatusDescription,
    CASE WHEN sa.Status IS NULL THEN NULL ELSE fn_IndicatorDescription('appointment_status', sa.Status) END AS AppointmentStatusDescription
FROM Technician t
LEFT JOIN ServiceAppointment sa
    ON t.TechnicianID = sa.TechnicianID;

CREATE OR REPLACE VIEW vw_MyAppointments AS
SELECT
    sa.AppointmentID,
    sa.AppointmentDateTime,
    sa.EstimatedDuration,
    sa.Status,
    sa.ServiceRequestDescription,
    v.VehicleID,
    v.VIN,
    v.Make,
    v.Model,
    v.`Year`
FROM ServiceAppointment sa
JOIN Vehicle v
    ON v.VehicleID = sa.VehicleID
JOIN UserAccount ua
    ON ua.TechnicianID = sa.TechnicianID
WHERE EXISTS (SELECT 1 FROM DatabasePrincipal dp WHERE dp.SessionAccount = USER()
          AND dp.PrincipalType = 'Person' AND dp.UserID = ua.UserID);

CREATE OR REPLACE VIEW vw_MyRepairs AS
SELECT
    r.RepairID,
    r.AppointmentID,
    r.RepairDateTime,
    r.RepairType,
    r.RepairDescription,
    r.LaborHours,
    r.Status,
    r.CompletedByTechnicianID,
    r.CompletionDateTime
FROM Repair r
WHERE r.AppointmentID IN (
    SELECT sa.AppointmentID
    FROM ServiceAppointment sa
    JOIN UserAccount ua
        ON ua.TechnicianID = sa.TechnicianID
    WHERE EXISTS (SELECT 1 FROM DatabasePrincipal dp WHERE dp.SessionAccount = USER()
          AND dp.PrincipalType = 'Person' AND dp.UserID = ua.UserID)
)
WITH CHECK OPTION;

CREATE OR REPLACE VIEW vw_RepairReferenceLabels AS
SELECT RepairID, RepairType,
       fn_IndicatorDescription('repair_type', RepairType) AS RepairTypeDescription,
       Status, fn_IndicatorDescription('repair_status', Status) AS StatusDescription
FROM Repair;

CREATE VIEW vw_AuditTrail AS
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('CustomerID', old.`CustomerID`, 'Name', old.`Name`, 'Phone', old.`Phone`, 'Email', old.`Email`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('CustomerID', new.`CustomerID`, 'Name', new.`Name`, 'Phone', new.`Phone`, 'Email', new.`Email`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `CustomerHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `CustomerHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'Customer'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('VehicleID', old.`VehicleID`, 'CustomerID', old.`CustomerID`, 'VIN', old.`VIN`, 'Make', old.`Make`, 'Model', old.`Model`, 'Year', old.`Year`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('VehicleID', new.`VehicleID`, 'CustomerID', new.`CustomerID`, 'VIN', new.`VIN`, 'Make', new.`Make`, 'Model', new.`Model`, 'Year', new.`Year`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `VehicleHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `VehicleHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'Vehicle'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('TechnicianID', old.`TechnicianID`, 'Name', old.`Name`, 'Phone', old.`Phone`, 'Email', old.`Email`, 'ActiveStatus', old.`ActiveStatus`, 'ActiveIndicator', old.`ActiveIndicator`, 'ActiveCode', old.`ActiveCode`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('TechnicianID', new.`TechnicianID`, 'Name', new.`Name`, 'Phone', new.`Phone`, 'Email', new.`Email`, 'ActiveStatus', new.`ActiveStatus`, 'ActiveIndicator', new.`ActiveIndicator`, 'ActiveCode', new.`ActiveCode`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `TechnicianHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `TechnicianHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'Technician'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('PartID', old.`PartID`, 'PartNumber', old.`PartNumber`, 'PartName', old.`PartName`, 'QuantityOnHand', old.`QuantityOnHand`, 'UnitCost', old.`UnitCost`, 'UnitSellingPrice', old.`UnitSellingPrice`, 'MinimumInventoryLevel', old.`MinimumInventoryLevel`, 'ActiveStatus', old.`ActiveStatus`, 'ActiveIndicator', old.`ActiveIndicator`, 'ActiveCode', old.`ActiveCode`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('PartID', new.`PartID`, 'PartNumber', new.`PartNumber`, 'PartName', new.`PartName`, 'QuantityOnHand', new.`QuantityOnHand`, 'UnitCost', new.`UnitCost`, 'UnitSellingPrice', new.`UnitSellingPrice`, 'MinimumInventoryLevel', new.`MinimumInventoryLevel`, 'ActiveStatus', new.`ActiveStatus`, 'ActiveIndicator', new.`ActiveIndicator`, 'ActiveCode', new.`ActiveCode`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `PartHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `PartHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'Part'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('UserID', old.`UserID`, 'Username', old.`Username`, 'Name', old.`Name`, 'RoleType', old.`RoleType`, 'TechnicianID', old.`TechnicianID`, 'RoleIndicator', old.`RoleIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('UserID', new.`UserID`, 'Username', new.`Username`, 'Name', new.`Name`, 'RoleType', new.`RoleType`, 'TechnicianID', new.`TechnicianID`, 'RoleIndicator', new.`RoleIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `UserAccountHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `UserAccountHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'UserAccount'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('AppointmentID', old.`AppointmentID`, 'VehicleID', old.`VehicleID`, 'TechnicianID', old.`TechnicianID`, 'CreatedByUserID', old.`CreatedByUserID`, 'AppointmentDateTime', old.`AppointmentDateTime`, 'Status', old.`Status`, 'ServiceRequestDescription', old.`ServiceRequestDescription`, 'EstimatedDuration', old.`EstimatedDuration`, 'CreationTimestamp', old.`CreationTimestamp`, 'CancellationDate', old.`CancellationDate`, 'CancellationReason', old.`CancellationReason`, 'StatusIndicator', old.`StatusIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('AppointmentID', new.`AppointmentID`, 'VehicleID', new.`VehicleID`, 'TechnicianID', new.`TechnicianID`, 'CreatedByUserID', new.`CreatedByUserID`, 'AppointmentDateTime', new.`AppointmentDateTime`, 'Status', new.`Status`, 'ServiceRequestDescription', new.`ServiceRequestDescription`, 'EstimatedDuration', new.`EstimatedDuration`, 'CreationTimestamp', new.`CreationTimestamp`, 'CancellationDate', new.`CancellationDate`, 'CancellationReason', new.`CancellationReason`, 'StatusIndicator', new.`StatusIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `ServiceAppointmentHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `ServiceAppointmentHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'ServiceAppointment'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('RepairID', old.`RepairID`, 'AppointmentID', old.`AppointmentID`, 'CompletedByTechnicianID', old.`CompletedByTechnicianID`, 'RepairDateTime', old.`RepairDateTime`, 'RepairType', old.`RepairType`, 'RepairDescription', old.`RepairDescription`, 'LaborHours', old.`LaborHours`, 'Status', old.`Status`, 'CompletionDateTime', old.`CompletionDateTime`, 'StatusIndicator', old.`StatusIndicator`, 'TypeIndicator', old.`TypeIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('RepairID', new.`RepairID`, 'AppointmentID', new.`AppointmentID`, 'CompletedByTechnicianID', new.`CompletedByTechnicianID`, 'RepairDateTime', new.`RepairDateTime`, 'RepairType', new.`RepairType`, 'RepairDescription', new.`RepairDescription`, 'LaborHours', new.`LaborHours`, 'Status', new.`Status`, 'CompletionDateTime', new.`CompletionDateTime`, 'StatusIndicator', new.`StatusIndicator`, 'TypeIndicator', new.`TypeIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `RepairHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `RepairHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'Repair'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('EstimateID', old.`EstimateID`, 'AppointmentID', old.`AppointmentID`, 'CreatedByUserID', old.`CreatedByUserID`, 'ApprovedByUserID', old.`ApprovedByUserID`, 'EstimateDate', old.`EstimateDate`, 'Status', old.`Status`, 'TotalAmount', old.`TotalAmount`, 'ApprovalDateTime', old.`ApprovalDateTime`, 'StatusIndicator', old.`StatusIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('EstimateID', new.`EstimateID`, 'AppointmentID', new.`AppointmentID`, 'CreatedByUserID', new.`CreatedByUserID`, 'ApprovedByUserID', new.`ApprovedByUserID`, 'EstimateDate', new.`EstimateDate`, 'Status', new.`Status`, 'TotalAmount', new.`TotalAmount`, 'ApprovalDateTime', new.`ApprovalDateTime`, 'StatusIndicator', new.`StatusIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `RepairEstimateHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `RepairEstimateHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'RepairEstimate'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('EstimateID', old.`EstimateID`, 'LineNumber', old.`LineNumber`, 'Description', old.`Description`, 'Quantity', old.`Quantity`, 'UnitPrice', old.`UnitPrice`, 'LineTotal', old.`LineTotal`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('EstimateID', new.`EstimateID`, 'LineNumber', new.`LineNumber`, 'Description', new.`Description`, 'Quantity', new.`Quantity`, 'UnitPrice', new.`UnitPrice`, 'LineTotal', new.`LineTotal`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `EstimateLineItemHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `EstimateLineItemHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'EstimateLineItem'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('InvoiceID', old.`InvoiceID`, 'AppointmentID', old.`AppointmentID`, 'CreatedByUserID', old.`CreatedByUserID`, 'FinalizedByUserID', old.`FinalizedByUserID`, 'InvoiceDate', old.`InvoiceDate`, 'Status', old.`Status`, 'TotalAmount', old.`TotalAmount`, 'FinalizationDateTime', old.`FinalizationDateTime`, 'StatusIndicator', old.`StatusIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('InvoiceID', new.`InvoiceID`, 'AppointmentID', new.`AppointmentID`, 'CreatedByUserID', new.`CreatedByUserID`, 'FinalizedByUserID', new.`FinalizedByUserID`, 'InvoiceDate', new.`InvoiceDate`, 'Status', new.`Status`, 'TotalAmount', new.`TotalAmount`, 'FinalizationDateTime', new.`FinalizationDateTime`, 'StatusIndicator', new.`StatusIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `InvoiceHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `InvoiceHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'Invoice'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('InvoiceLineItemID', old.`InvoiceLineItemID`, 'InvoiceID', old.`InvoiceID`, 'Description', old.`Description`, 'Quantity', old.`Quantity`, 'UnitPrice', old.`UnitPrice`, 'LineTotal', old.`LineTotal`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('InvoiceLineItemID', new.`InvoiceLineItemID`, 'InvoiceID', new.`InvoiceID`, 'Description', new.`Description`, 'Quantity', new.`Quantity`, 'UnitPrice', new.`UnitPrice`, 'LineTotal', new.`LineTotal`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `InvoiceLineItemHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `InvoiceLineItemHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'InvoiceLineItem'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('PartsUsageID', old.`PartsUsageID`, 'RepairID', old.`RepairID`, 'PartID', old.`PartID`, 'RecordedByUserID', old.`RecordedByUserID`, 'QuantityUsed', old.`QuantityUsed`, 'UnitSellingPriceAtTimeOfUse', old.`UnitSellingPriceAtTimeOfUse`, 'UnitCostAtTimeOfUse', old.`UnitCostAtTimeOfUse`, 'RecordedDateTime', old.`RecordedDateTime`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('PartsUsageID', new.`PartsUsageID`, 'RepairID', new.`RepairID`, 'PartID', new.`PartID`, 'RecordedByUserID', new.`RecordedByUserID`, 'QuantityUsed', new.`QuantityUsed`, 'UnitSellingPriceAtTimeOfUse', new.`UnitSellingPriceAtTimeOfUse`, 'UnitCostAtTimeOfUse', new.`UnitCostAtTimeOfUse`, 'RecordedDateTime', new.`RecordedDateTime`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `PartsUsageHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `PartsUsageHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'PartsUsage'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('IndicatorName', old.`IndicatorName`, 'ValueCode', old.`ValueCode`, 'Description', old.`Description`, 'DisplayOrder', old.`DisplayOrder`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('IndicatorName', new.`IndicatorName`, 'ValueCode', new.`ValueCode`, 'Description', new.`Description`, 'DisplayOrder', new.`DisplayOrder`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `IndicatorValueHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `IndicatorValueHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'IndicatorValue'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('RoleType', old.`RoleType`, 'RequiresTechnician', old.`RequiresTechnician`, 'RoleIndicator', old.`RoleIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('RoleType', new.`RoleType`, 'RequiresTechnician', new.`RequiresTechnician`, 'RoleIndicator', new.`RoleIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `UserRolePolicyHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `UserRolePolicyHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'UserRolePolicy'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('SessionAccount', old.`SessionAccount`, 'PrincipalType', old.`PrincipalType`, 'UserID', old.`UserID`, 'TypeIndicator', old.`TypeIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('SessionAccount', new.`SessionAccount`, 'PrincipalType', new.`PrincipalType`, 'UserID', new.`UserID`, 'TypeIndicator', new.`TypeIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `DatabasePrincipalHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `DatabasePrincipalHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'DatabasePrincipal'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('RoleType', old.`RoleType`, 'ProcedureName', old.`ProcedureName`, 'RoleIndicator', old.`RoleIndicator`, 'ProcedureIndicator', old.`ProcedureIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('RoleType', new.`RoleType`, 'ProcedureName', new.`ProcedureName`, 'RoleIndicator', new.`RoleIndicator`, 'ProcedureIndicator', new.`ProcedureIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `RoleProcedurePermissionHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `RoleProcedurePermissionHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'RoleProcedurePermission'
UNION ALL
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('SessionAccount', old.`SessionAccount`, 'UserID', old.`UserID`, 'ProcedureName', old.`ProcedureName`, 'ProcedureIndicator', old.`ProcedureIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('SessionAccount', new.`SessionAccount`, 'UserID', new.`UserID`, 'ProcedureName', new.`ProcedureName`, 'ProcedureIndicator', new.`ProcedureIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM TemporalEvent e
LEFT JOIN `PrincipalDelegationHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `PrincipalDelegationHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'PrincipalDelegation';

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
