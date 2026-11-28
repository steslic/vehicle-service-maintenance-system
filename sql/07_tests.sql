-- Current-schema acceptance assertions. Read-only business checks; no actor impersonation.
-- Original 66 workflow assertions remain in legacy/v001/07_tests.sql and run in regressions.
USE vehicle_service_maintenance;
CREATE TEMPORARY TABLE TestResult (Description VARCHAR(255), Result VARCHAR(4));
INSERT INTO TestResult SELECT 'AuditLog', IF((SELECT COUNT(*) FROM `AuditLog`) = 120, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'Customer', IF((SELECT COUNT(*) FROM `Customer`) = 5, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'DatabasePrincipal', IF((SELECT COUNT(*) FROM `DatabasePrincipal`) = 4, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'EstimateLineItem', IF((SELECT COUNT(*) FROM `EstimateLineItem`) = 9, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'IndicatorValue', IF((SELECT COUNT(*) FROM `IndicatorValue`) = 97, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'Invoice', IF((SELECT COUNT(*) FROM `Invoice`) = 4, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'InvoiceLineItem', IF((SELECT COUNT(*) FROM `InvoiceLineItem`) = 9, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'Part', IF((SELECT COUNT(*) FROM `Part`) = 6, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'PartsUsage', IF((SELECT COUNT(*) FROM `PartsUsage`) = 9, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'PrincipalDelegation', IF((SELECT COUNT(*) FROM `PrincipalDelegation`) = 0, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'Repair', IF((SELECT COUNT(*) FROM `Repair`) = 10, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'RepairEstimate', IF((SELECT COUNT(*) FROM `RepairEstimate`) = 4, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'RoleProcedurePermission', IF((SELECT COUNT(*) FROM `RoleProcedurePermission`) = 55, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'ServiceAppointment', IF((SELECT COUNT(*) FROM `ServiceAppointment`) = 16, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'Technician', IF((SELECT COUNT(*) FROM `Technician`) = 3, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'UserAccount', IF((SELECT COUNT(*) FROM `UserAccount`) = 4, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'UserRolePolicy', IF((SELECT COUNT(*) FROM `UserRolePolicy`) = 3, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'Vehicle', IF((SELECT COUNT(*) FROM `Vehicle`) = 6, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'initial temporal events', IF((SELECT COUNT(*) FROM TemporalEvent) = 0, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'clean operation context', IF((SELECT COUNT(*) FROM OperationContext) = 0, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'clean temporal context', IF((SELECT COUNT(*) FROM TemporalWriteContext) = 0, 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'stable error code', IF(fn_ApplicationErrorID(51001) = 'VSM_INVALID_APPOINTMENT', 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'native retry class', IF(fn_ErrorClass(1213, '40001', FALSE) = 'retryable', 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'unknown outcome', IF(fn_ErrorCallerAction(1213, '40001', FALSE, 'unknown', 1) = 'reconcile_outcome', 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'CustomerHistory snapshots', IF((SELECT COUNT(*) FROM `CustomerHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `Customer`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'DatabasePrincipalHistory snapshots', IF((SELECT COUNT(*) FROM `DatabasePrincipalHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `DatabasePrincipal`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'EstimateLineItemHistory snapshots', IF((SELECT COUNT(*) FROM `EstimateLineItemHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `EstimateLineItem`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'IndicatorValueHistory snapshots', IF((SELECT COUNT(*) FROM `IndicatorValueHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `IndicatorValue`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'InvoiceHistory snapshots', IF((SELECT COUNT(*) FROM `InvoiceHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `Invoice`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'InvoiceLineItemHistory snapshots', IF((SELECT COUNT(*) FROM `InvoiceLineItemHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `InvoiceLineItem`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'PartHistory snapshots', IF((SELECT COUNT(*) FROM `PartHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `Part`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'PartsUsageHistory snapshots', IF((SELECT COUNT(*) FROM `PartsUsageHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `PartsUsage`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'PrincipalDelegationHistory snapshots', IF((SELECT COUNT(*) FROM `PrincipalDelegationHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `PrincipalDelegation`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'RepairEstimateHistory snapshots', IF((SELECT COUNT(*) FROM `RepairEstimateHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `RepairEstimate`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'RepairHistory snapshots', IF((SELECT COUNT(*) FROM `RepairHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `Repair`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'RoleProcedurePermissionHistory snapshots', IF((SELECT COUNT(*) FROM `RoleProcedurePermissionHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `RoleProcedurePermission`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'ServiceAppointmentHistory snapshots', IF((SELECT COUNT(*) FROM `ServiceAppointmentHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `ServiceAppointment`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'TechnicianHistory snapshots', IF((SELECT COUNT(*) FROM `TechnicianHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `Technician`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'UserAccountHistory snapshots', IF((SELECT COUNT(*) FROM `UserAccountHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `UserAccount`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'UserRolePolicyHistory snapshots', IF((SELECT COUNT(*) FROM `UserRolePolicyHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `UserRolePolicy`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'VehicleHistory snapshots', IF((SELECT COUNT(*) FROM `VehicleHistory` WHERE HistoryOrigin = 'Snapshot' AND HistoryVersion = 1 AND HistoryValidFrom IS NULL AND HistoryUserID IS NULL AND HistorySessionAccount IS NULL AND HistoryStartEventID IS NULL) = (SELECT COUNT(*) FROM `Vehicle`), 'PASS', 'FAIL');
INSERT INTO TestResult SELECT 'revision 007 missing-record identifier', IF(fn_ApplicationErrorID(53007)='VSM_RECORD_NOT_FOUND','PASS','FAIL');
INSERT INTO TestResult SELECT 'revision 007 missing-record class', IF(fn_ErrorClass(53007,'45000',FALSE)='not_found','PASS','FAIL');
INSERT INTO TestResult SELECT 'procedure catalog matches routines', IF((SELECT COUNT(*) FROM IndicatorValue i JOIN information_schema.ROUTINES r ON r.ROUTINE_SCHEMA=DATABASE() AND r.ROUTINE_TYPE='PROCEDURE' AND r.ROUTINE_NAME=i.ValueCode WHERE i.IndicatorName='procedure_name')=31,'PASS','FAIL');
INSERT INTO TestResult SELECT 'technician has no customer mutation entitlement', IF(NOT EXISTS(SELECT 1 FROM RoleProcedurePermission WHERE RoleType='Technician' AND ProcedureName='sp_CreateCustomer'),'PASS','FAIL');
SELECT Description, Result FROM TestResult;
SELECT Result, COUNT(*) AS Checks FROM TestResult GROUP BY Result;
DELIMITER //
CREATE PROCEDURE tst_FailIfNeeded()
BEGIN
    IF EXISTS (SELECT 1 FROM TestResult WHERE Result = 'FAIL') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Test suite failed; see FAIL rows above';
    END IF;
END //
DELIMITER ;
CALL tst_FailIfNeeded();
DROP PROCEDURE tst_FailIfNeeded;
DROP TEMPORARY TABLE TestResult;
