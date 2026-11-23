-- All final triggers, in deployed ACTION_ORDER. Native grants belong to 08.
USE vehicle_service_maintenance;
DELIMITER //

CREATE TRIGGER trg_ServiceAppointment_Audit_ai
AFTER INSERT ON ServiceAppointment
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Create', 'ServiceAppointment', NEW.AppointmentID, NULL,
        JSON_OBJECT('VehicleID',                 NEW.VehicleID,
                    'TechnicianID',              NEW.TechnicianID,
                    'CreatedByUserID',           NEW.CreatedByUserID,
                    'AppointmentDateTime',       NEW.AppointmentDateTime,
                    'Status',                    NEW.Status,
                    'ServiceRequestDescription', NEW.ServiceRequestDescription,
                    'EstimatedDuration',         NEW.EstimatedDuration,
                    'CreationTimestamp',         NEW.CreationTimestamp,
                    'CancellationDate',          NEW.CancellationDate,
                    'CancellationReason',        NEW.CancellationReason));
END //

CREATE TRIGGER `trg_ServiceAppointment_History_ai` AFTER INSERT ON `ServiceAppointment` FOR EACH ROW
FOLLOWS trg_ServiceAppointment_Audit_ai
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('AppointmentID', 'VehicleID', 'TechnicianID', 'CreatedByUserID', 'AppointmentDateTime', 'Status', 'ServiceRequestDescription', 'EstimatedDuration', 'CreationTimestamp', 'CancellationDate', 'CancellationReason');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `ServiceAppointmentHistory` WHERE `AppointmentID` = NEW.`AppointmentID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('ServiceAppointment', JSON_OBJECT('AppointmentID', NEW.`AppointmentID`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `ServiceAppointmentHistory` (`AppointmentID`, `VehicleID`, `TechnicianID`, `CreatedByUserID`, `AppointmentDateTime`, `Status`, `ServiceRequestDescription`, `EstimatedDuration`, `CreationTimestamp`, `CancellationDate`, `CancellationReason`, `StatusIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`AppointmentID`, NEW.`VehicleID`, NEW.`TechnicianID`, NEW.`CreatedByUserID`, NEW.`AppointmentDateTime`, NEW.`Status`, NEW.`ServiceRequestDescription`, NEW.`EstimatedDuration`, NEW.`CreationTimestamp`, NEW.`CancellationDate`, NEW.`CancellationReason`, NEW.`StatusIndicator`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'ServiceAppointment';
END //

CREATE TRIGGER trg_ServiceAppointment_Audit_au
AFTER UPDATE ON ServiceAppointment
FOR EACH ROW
BEGIN
    DECLARE v_Old JSON;
    DECLARE v_New JSON;
    DECLARE v_Action VARCHAR(50);

    SET v_Old = JSON_OBJECT('VehicleID',                 OLD.VehicleID,
                            'TechnicianID',              OLD.TechnicianID,
                            'CreatedByUserID',           OLD.CreatedByUserID,
                            'AppointmentDateTime',       OLD.AppointmentDateTime,
                            'EstimatedDuration',         OLD.EstimatedDuration,
                            'Status',                    OLD.Status,
                            'ServiceRequestDescription', OLD.ServiceRequestDescription,
                            'CreationTimestamp',         OLD.CreationTimestamp,
                            'CancellationDate',          OLD.CancellationDate,
                            'CancellationReason',        OLD.CancellationReason);
    SET v_New = JSON_OBJECT('VehicleID',                 NEW.VehicleID,
                            'TechnicianID',              NEW.TechnicianID,
                            'CreatedByUserID',           NEW.CreatedByUserID,
                            'AppointmentDateTime',       NEW.AppointmentDateTime,
                            'EstimatedDuration',         NEW.EstimatedDuration,
                            'Status',                    NEW.Status,
                            'ServiceRequestDescription', NEW.ServiceRequestDescription,
                            'CreationTimestamp',         NEW.CreationTimestamp,
                            'CancellationDate',          NEW.CancellationDate,
                            'CancellationReason',        NEW.CancellationReason);

    IF v_Old <> v_New THEN
        SET v_Action = CASE
            WHEN NOT (OLD.Status <=> NEW.Status) AND NEW.Status = 'Cancelled' THEN 'Cancel'
            WHEN NOT (OLD.Status <=> NEW.Status) AND NEW.Status = 'Completed' THEN 'Complete'
            WHEN NOT (OLD.Status <=> NEW.Status)                              THEN 'Status Change'
            WHEN NOT (OLD.TechnicianID <=> NEW.TechnicianID)                  THEN 'Technician Reassignment'
            WHEN NOT (OLD.AppointmentDateTime <=> NEW.AppointmentDateTime)    THEN 'Reschedule'
            ELSE 'Update'
        END;

        CALL sp_WriteAuditLog(v_Action, 'ServiceAppointment', NEW.AppointmentID, v_Old, v_New);
    END IF;
END //

CREATE TRIGGER `trg_ServiceAppointment_History_au` AFTER UPDATE ON `ServiceAppointment` FOR EACH ROW
FOLLOWS trg_ServiceAppointment_Audit_au
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('AppointmentID', OLD.`AppointmentID`, 'VehicleID', OLD.`VehicleID`, 'TechnicianID', OLD.`TechnicianID`, 'CreatedByUserID', OLD.`CreatedByUserID`, 'AppointmentDateTime', OLD.`AppointmentDateTime`, 'Status', OLD.`Status`, 'ServiceRequestDescription', OLD.`ServiceRequestDescription`, 'EstimatedDuration', OLD.`EstimatedDuration`, 'CreationTimestamp', OLD.`CreationTimestamp`, 'CancellationDate', OLD.`CancellationDate`, 'CancellationReason', OLD.`CancellationReason`) AS BINARY) <=> CAST(JSON_OBJECT('AppointmentID', NEW.`AppointmentID`, 'VehicleID', NEW.`VehicleID`, 'TechnicianID', NEW.`TechnicianID`, 'CreatedByUserID', NEW.`CreatedByUserID`, 'AppointmentDateTime', NEW.`AppointmentDateTime`, 'Status', NEW.`Status`, 'ServiceRequestDescription', NEW.`ServiceRequestDescription`, 'EstimatedDuration', NEW.`EstimatedDuration`, 'CreationTimestamp', NEW.`CreationTimestamp`, 'CancellationDate', NEW.`CancellationDate`, 'CancellationReason', NEW.`CancellationReason`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`AppointmentID` AS BINARY) <=> CAST(NEW.`AppointmentID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'AppointmentID'); END IF;
    IF NOT (CAST(OLD.`VehicleID` AS BINARY) <=> CAST(NEW.`VehicleID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'VehicleID'); END IF;
    IF NOT (CAST(OLD.`TechnicianID` AS BINARY) <=> CAST(NEW.`TechnicianID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'TechnicianID'); END IF;
    IF NOT (CAST(OLD.`CreatedByUserID` AS BINARY) <=> CAST(NEW.`CreatedByUserID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'CreatedByUserID'); END IF;
    IF NOT (CAST(OLD.`AppointmentDateTime` AS BINARY) <=> CAST(NEW.`AppointmentDateTime` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'AppointmentDateTime'); END IF;
    IF NOT (CAST(OLD.`Status` AS BINARY) <=> CAST(NEW.`Status` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Status'); END IF;
    IF NOT (CAST(OLD.`ServiceRequestDescription` AS BINARY) <=> CAST(NEW.`ServiceRequestDescription` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'ServiceRequestDescription'); END IF;
    IF NOT (CAST(OLD.`EstimatedDuration` AS BINARY) <=> CAST(NEW.`EstimatedDuration` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'EstimatedDuration'); END IF;
    IF NOT (CAST(OLD.`CreationTimestamp` AS BINARY) <=> CAST(NEW.`CreationTimestamp` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'CreationTimestamp'); END IF;
    IF NOT (CAST(OLD.`CancellationDate` AS BINARY) <=> CAST(NEW.`CancellationDate` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'CancellationDate'); END IF;
    IF NOT (CAST(OLD.`CancellationReason` AS BINARY) <=> CAST(NEW.`CancellationReason` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'CancellationReason'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `ServiceAppointmentHistory`
    WHERE `AppointmentID` = OLD.`AppointmentID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `ServiceAppointmentHistory` WHERE `AppointmentID` = NEW.`AppointmentID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('ServiceAppointment', JSON_OBJECT('AppointmentID', NEW.`AppointmentID`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `ServiceAppointmentHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `ServiceAppointmentHistory` (`AppointmentID`, `VehicleID`, `TechnicianID`, `CreatedByUserID`, `AppointmentDateTime`, `Status`, `ServiceRequestDescription`, `EstimatedDuration`, `CreationTimestamp`, `CancellationDate`, `CancellationReason`, `StatusIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`AppointmentID`, NEW.`VehicleID`, NEW.`TechnicianID`, NEW.`CreatedByUserID`, NEW.`AppointmentDateTime`, NEW.`Status`, NEW.`ServiceRequestDescription`, NEW.`EstimatedDuration`, NEW.`CreationTimestamp`, NEW.`CancellationDate`, NEW.`CancellationReason`, NEW.`StatusIndicator`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'ServiceAppointment';
    END IF;
END //

CREATE TRIGGER trg_ServiceAppointment_Audit_ad
AFTER DELETE ON ServiceAppointment
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Delete', 'ServiceAppointment', OLD.AppointmentID,
        JSON_OBJECT('VehicleID',                 OLD.VehicleID,
                    'TechnicianID',              OLD.TechnicianID,
                    'CreatedByUserID',           OLD.CreatedByUserID,
                    'AppointmentDateTime',       OLD.AppointmentDateTime,
                    'Status',                    OLD.Status,
                    'ServiceRequestDescription', OLD.ServiceRequestDescription,
                    'EstimatedDuration',         OLD.EstimatedDuration,
                    'CreationTimestamp',         OLD.CreationTimestamp,
                    'CancellationDate',          OLD.CancellationDate,
                    'CancellationReason',        OLD.CancellationReason),
        NULL);
END //

CREATE TRIGGER `trg_ServiceAppointment_History_ad` AFTER DELETE ON `ServiceAppointment` FOR EACH ROW
FOLLOWS trg_ServiceAppointment_Audit_ad
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('AppointmentID', 'VehicleID', 'TechnicianID', 'CreatedByUserID', 'AppointmentDateTime', 'Status', 'ServiceRequestDescription', 'EstimatedDuration', 'CreationTimestamp', 'CancellationDate', 'CancellationReason');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `ServiceAppointmentHistory`
    WHERE `AppointmentID` = OLD.`AppointmentID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('ServiceAppointment', JSON_OBJECT('AppointmentID', OLD.`AppointmentID`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `ServiceAppointmentHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'ServiceAppointment';
END //

CREATE TRIGGER trg_Repair_Audit_ai
AFTER INSERT ON Repair
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Create', 'Repair', NEW.RepairID, NULL,
        JSON_OBJECT('AppointmentID',     NEW.AppointmentID,
                    'CompletedByTechnicianID', NEW.CompletedByTechnicianID,
                    'RepairDateTime',        NEW.RepairDateTime,
                    'RepairType',        NEW.RepairType,
                    'RepairDescription', NEW.RepairDescription,
                    'LaborHours',        NEW.LaborHours,
                    'Status',            NEW.Status,
                    'CompletionDateTime', NEW.CompletionDateTime));
END //

CREATE TRIGGER `trg_Repair_History_ai` AFTER INSERT ON `Repair` FOR EACH ROW
FOLLOWS trg_Repair_Audit_ai
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('RepairID', 'AppointmentID', 'CompletedByTechnicianID', 'RepairDateTime', 'RepairType', 'RepairDescription', 'LaborHours', 'Status', 'CompletionDateTime');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `RepairHistory` WHERE `RepairID` = NEW.`RepairID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('Repair', JSON_OBJECT('RepairID', NEW.`RepairID`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `RepairHistory` (`RepairID`, `AppointmentID`, `CompletedByTechnicianID`, `RepairDateTime`, `RepairType`, `RepairDescription`, `LaborHours`, `Status`, `CompletionDateTime`, `StatusIndicator`, `TypeIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`RepairID`, NEW.`AppointmentID`, NEW.`CompletedByTechnicianID`, NEW.`RepairDateTime`, NEW.`RepairType`, NEW.`RepairDescription`, NEW.`LaborHours`, NEW.`Status`, NEW.`CompletionDateTime`, NEW.`StatusIndicator`, NEW.`TypeIndicator`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Repair';
END //

CREATE TRIGGER trg_Repair_Audit_au
AFTER UPDATE ON Repair
FOR EACH ROW
BEGIN
    DECLARE v_Old JSON;
    DECLARE v_New JSON;
    DECLARE v_Action VARCHAR(50);

    SET v_Old = JSON_OBJECT('AppointmentID',           OLD.AppointmentID,
                            'RepairDateTime',          OLD.RepairDateTime,
                            'RepairType',              OLD.RepairType,
                            'RepairDescription',       OLD.RepairDescription,
                            'LaborHours',              OLD.LaborHours,
                            'Status',                  OLD.Status,
                            'CompletedByTechnicianID', OLD.CompletedByTechnicianID,
                            'CompletionDateTime',      OLD.CompletionDateTime);
    SET v_New = JSON_OBJECT('AppointmentID',           NEW.AppointmentID,
                            'RepairDateTime',          NEW.RepairDateTime,
                            'RepairType',              NEW.RepairType,
                            'RepairDescription',       NEW.RepairDescription,
                            'LaborHours',              NEW.LaborHours,
                            'Status',                  NEW.Status,
                            'CompletedByTechnicianID', NEW.CompletedByTechnicianID,
                            'CompletionDateTime',      NEW.CompletionDateTime);

    IF v_Old <> v_New THEN
        SET v_Action = CASE
            WHEN NOT (OLD.Status <=> NEW.Status) AND NEW.Status = 'Completed' THEN 'Complete'
            WHEN NOT (OLD.Status <=> NEW.Status) AND NEW.Status = 'Cancelled' THEN 'Cancel'
            WHEN NOT (OLD.Status <=> NEW.Status)                              THEN 'Status Change'
            ELSE 'Update'
        END;

        CALL sp_WriteAuditLog(v_Action, 'Repair', NEW.RepairID, v_Old, v_New);
    END IF;
END //

CREATE TRIGGER `trg_Repair_History_au` AFTER UPDATE ON `Repair` FOR EACH ROW
FOLLOWS trg_Repair_Audit_au
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('RepairID', OLD.`RepairID`, 'AppointmentID', OLD.`AppointmentID`, 'CompletedByTechnicianID', OLD.`CompletedByTechnicianID`, 'RepairDateTime', OLD.`RepairDateTime`, 'RepairType', OLD.`RepairType`, 'RepairDescription', OLD.`RepairDescription`, 'LaborHours', OLD.`LaborHours`, 'Status', OLD.`Status`, 'CompletionDateTime', OLD.`CompletionDateTime`) AS BINARY) <=> CAST(JSON_OBJECT('RepairID', NEW.`RepairID`, 'AppointmentID', NEW.`AppointmentID`, 'CompletedByTechnicianID', NEW.`CompletedByTechnicianID`, 'RepairDateTime', NEW.`RepairDateTime`, 'RepairType', NEW.`RepairType`, 'RepairDescription', NEW.`RepairDescription`, 'LaborHours', NEW.`LaborHours`, 'Status', NEW.`Status`, 'CompletionDateTime', NEW.`CompletionDateTime`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`RepairID` AS BINARY) <=> CAST(NEW.`RepairID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'RepairID'); END IF;
    IF NOT (CAST(OLD.`AppointmentID` AS BINARY) <=> CAST(NEW.`AppointmentID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'AppointmentID'); END IF;
    IF NOT (CAST(OLD.`CompletedByTechnicianID` AS BINARY) <=> CAST(NEW.`CompletedByTechnicianID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'CompletedByTechnicianID'); END IF;
    IF NOT (CAST(OLD.`RepairDateTime` AS BINARY) <=> CAST(NEW.`RepairDateTime` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'RepairDateTime'); END IF;
    IF NOT (CAST(OLD.`RepairType` AS BINARY) <=> CAST(NEW.`RepairType` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'RepairType'); END IF;
    IF NOT (CAST(OLD.`RepairDescription` AS BINARY) <=> CAST(NEW.`RepairDescription` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'RepairDescription'); END IF;
    IF NOT (CAST(OLD.`LaborHours` AS BINARY) <=> CAST(NEW.`LaborHours` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'LaborHours'); END IF;
    IF NOT (CAST(OLD.`Status` AS BINARY) <=> CAST(NEW.`Status` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Status'); END IF;
    IF NOT (CAST(OLD.`CompletionDateTime` AS BINARY) <=> CAST(NEW.`CompletionDateTime` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'CompletionDateTime'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `RepairHistory`
    WHERE `RepairID` = OLD.`RepairID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `RepairHistory` WHERE `RepairID` = NEW.`RepairID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('Repair', JSON_OBJECT('RepairID', NEW.`RepairID`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `RepairHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `RepairHistory` (`RepairID`, `AppointmentID`, `CompletedByTechnicianID`, `RepairDateTime`, `RepairType`, `RepairDescription`, `LaborHours`, `Status`, `CompletionDateTime`, `StatusIndicator`, `TypeIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`RepairID`, NEW.`AppointmentID`, NEW.`CompletedByTechnicianID`, NEW.`RepairDateTime`, NEW.`RepairType`, NEW.`RepairDescription`, NEW.`LaborHours`, NEW.`Status`, NEW.`CompletionDateTime`, NEW.`StatusIndicator`, NEW.`TypeIndicator`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Repair';
    END IF;
END //

CREATE TRIGGER trg_Repair_Audit_ad
AFTER DELETE ON Repair
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Delete', 'Repair', OLD.RepairID,
        JSON_OBJECT('AppointmentID',           OLD.AppointmentID,
                    'CompletedByTechnicianID', OLD.CompletedByTechnicianID,
                    'RepairDateTime',          OLD.RepairDateTime,
                    'RepairType',              OLD.RepairType,
                    'RepairDescription',       OLD.RepairDescription,
                    'LaborHours',              OLD.LaborHours,
                    'Status',                  OLD.Status,
                    'CompletionDateTime',      OLD.CompletionDateTime),
        NULL);
END //

CREATE TRIGGER `trg_Repair_History_ad` AFTER DELETE ON `Repair` FOR EACH ROW
FOLLOWS trg_Repair_Audit_ad
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('RepairID', 'AppointmentID', 'CompletedByTechnicianID', 'RepairDateTime', 'RepairType', 'RepairDescription', 'LaborHours', 'Status', 'CompletionDateTime');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `RepairHistory`
    WHERE `RepairID` = OLD.`RepairID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('Repair', JSON_OBJECT('RepairID', OLD.`RepairID`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `RepairHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Repair';
END //

CREATE TRIGGER trg_RepairEstimate_Audit_ai
AFTER INSERT ON RepairEstimate
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Create', 'RepairEstimate', NEW.EstimateID, NULL,
        JSON_OBJECT('AppointmentID', NEW.AppointmentID,
                    'CreatedByUserID', NEW.CreatedByUserID,
                    'ApprovedByUserID', NEW.ApprovedByUserID,
                    'EstimateDate',  NEW.EstimateDate,
                    'TotalAmount',   NEW.TotalAmount,
                    'Status',        NEW.Status,
                    'ApprovalDateTime', NEW.ApprovalDateTime));
END //

CREATE TRIGGER `trg_RepairEstimate_History_ai` AFTER INSERT ON `RepairEstimate` FOR EACH ROW
FOLLOWS trg_RepairEstimate_Audit_ai
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('EstimateID', 'AppointmentID', 'CreatedByUserID', 'ApprovedByUserID', 'EstimateDate', 'Status', 'TotalAmount', 'ApprovalDateTime');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `RepairEstimateHistory` WHERE `EstimateID` = NEW.`EstimateID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('RepairEstimate', JSON_OBJECT('EstimateID', NEW.`EstimateID`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `RepairEstimateHistory` (`EstimateID`, `AppointmentID`, `CreatedByUserID`, `ApprovedByUserID`, `EstimateDate`, `Status`, `TotalAmount`, `ApprovalDateTime`, `StatusIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`EstimateID`, NEW.`AppointmentID`, NEW.`CreatedByUserID`, NEW.`ApprovedByUserID`, NEW.`EstimateDate`, NEW.`Status`, NEW.`TotalAmount`, NEW.`ApprovalDateTime`, NEW.`StatusIndicator`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'RepairEstimate';
END //

CREATE TRIGGER trg_RepairEstimate_Audit_au
AFTER UPDATE ON RepairEstimate
FOR EACH ROW
BEGIN
    DECLARE v_Old JSON;
    DECLARE v_New JSON;
    DECLARE v_Action VARCHAR(50);

    SET v_Old = JSON_OBJECT('AppointmentID',    OLD.AppointmentID,
                            'CreatedByUserID',  OLD.CreatedByUserID,
                            'EstimateDate',     OLD.EstimateDate,
                            'TotalAmount',      OLD.TotalAmount,
                            'Status',           OLD.Status,
                            'ApprovedByUserID', OLD.ApprovedByUserID,
                            'ApprovalDateTime', OLD.ApprovalDateTime);
    SET v_New = JSON_OBJECT('AppointmentID',    NEW.AppointmentID,
                            'CreatedByUserID',  NEW.CreatedByUserID,
                            'EstimateDate',     NEW.EstimateDate,
                            'TotalAmount',      NEW.TotalAmount,
                            'Status',           NEW.Status,
                            'ApprovedByUserID', NEW.ApprovedByUserID,
                            'ApprovalDateTime', NEW.ApprovalDateTime);

    IF v_Old <> v_New THEN
        SET v_Action = CASE
            WHEN NOT (OLD.Status <=> NEW.Status) AND NEW.Status = 'Approved'  THEN 'Approve'
            WHEN NOT (OLD.Status <=> NEW.Status) AND NEW.Status = 'Rejected'  THEN 'Reject'
            WHEN NOT (OLD.Status <=> NEW.Status) AND NEW.Status = 'Finalized' THEN 'Finalize'
            WHEN NOT (OLD.Status <=> NEW.Status)                              THEN 'Status Change'
            ELSE 'Update'
        END;

        CALL sp_WriteAuditLog(v_Action, 'RepairEstimate', NEW.EstimateID, v_Old, v_New);
    END IF;
END //

CREATE TRIGGER `trg_RepairEstimate_History_au` AFTER UPDATE ON `RepairEstimate` FOR EACH ROW
FOLLOWS trg_RepairEstimate_Audit_au
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('EstimateID', OLD.`EstimateID`, 'AppointmentID', OLD.`AppointmentID`, 'CreatedByUserID', OLD.`CreatedByUserID`, 'ApprovedByUserID', OLD.`ApprovedByUserID`, 'EstimateDate', OLD.`EstimateDate`, 'Status', OLD.`Status`, 'TotalAmount', OLD.`TotalAmount`, 'ApprovalDateTime', OLD.`ApprovalDateTime`) AS BINARY) <=> CAST(JSON_OBJECT('EstimateID', NEW.`EstimateID`, 'AppointmentID', NEW.`AppointmentID`, 'CreatedByUserID', NEW.`CreatedByUserID`, 'ApprovedByUserID', NEW.`ApprovedByUserID`, 'EstimateDate', NEW.`EstimateDate`, 'Status', NEW.`Status`, 'TotalAmount', NEW.`TotalAmount`, 'ApprovalDateTime', NEW.`ApprovalDateTime`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`EstimateID` AS BINARY) <=> CAST(NEW.`EstimateID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'EstimateID'); END IF;
    IF NOT (CAST(OLD.`AppointmentID` AS BINARY) <=> CAST(NEW.`AppointmentID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'AppointmentID'); END IF;
    IF NOT (CAST(OLD.`CreatedByUserID` AS BINARY) <=> CAST(NEW.`CreatedByUserID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'CreatedByUserID'); END IF;
    IF NOT (CAST(OLD.`ApprovedByUserID` AS BINARY) <=> CAST(NEW.`ApprovedByUserID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'ApprovedByUserID'); END IF;
    IF NOT (CAST(OLD.`EstimateDate` AS BINARY) <=> CAST(NEW.`EstimateDate` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'EstimateDate'); END IF;
    IF NOT (CAST(OLD.`Status` AS BINARY) <=> CAST(NEW.`Status` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Status'); END IF;
    IF NOT (CAST(OLD.`TotalAmount` AS BINARY) <=> CAST(NEW.`TotalAmount` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'TotalAmount'); END IF;
    IF NOT (CAST(OLD.`ApprovalDateTime` AS BINARY) <=> CAST(NEW.`ApprovalDateTime` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'ApprovalDateTime'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `RepairEstimateHistory`
    WHERE `EstimateID` = OLD.`EstimateID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `RepairEstimateHistory` WHERE `EstimateID` = NEW.`EstimateID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('RepairEstimate', JSON_OBJECT('EstimateID', NEW.`EstimateID`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `RepairEstimateHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `RepairEstimateHistory` (`EstimateID`, `AppointmentID`, `CreatedByUserID`, `ApprovedByUserID`, `EstimateDate`, `Status`, `TotalAmount`, `ApprovalDateTime`, `StatusIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`EstimateID`, NEW.`AppointmentID`, NEW.`CreatedByUserID`, NEW.`ApprovedByUserID`, NEW.`EstimateDate`, NEW.`Status`, NEW.`TotalAmount`, NEW.`ApprovalDateTime`, NEW.`StatusIndicator`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'RepairEstimate';
    END IF;
END //

CREATE TRIGGER trg_RepairEstimate_Audit_ad
AFTER DELETE ON RepairEstimate
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Delete', 'RepairEstimate', OLD.EstimateID,
        JSON_OBJECT('AppointmentID',    OLD.AppointmentID,
                    'CreatedByUserID',  OLD.CreatedByUserID,
                    'ApprovedByUserID', OLD.ApprovedByUserID,
                    'EstimateDate',     OLD.EstimateDate,
                    'Status',           OLD.Status,
                    'TotalAmount',      OLD.TotalAmount,
                    'ApprovalDateTime', OLD.ApprovalDateTime),
        NULL);
END //

CREATE TRIGGER `trg_RepairEstimate_History_ad` AFTER DELETE ON `RepairEstimate` FOR EACH ROW
FOLLOWS trg_RepairEstimate_Audit_ad
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('EstimateID', 'AppointmentID', 'CreatedByUserID', 'ApprovedByUserID', 'EstimateDate', 'Status', 'TotalAmount', 'ApprovalDateTime');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `RepairEstimateHistory`
    WHERE `EstimateID` = OLD.`EstimateID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('RepairEstimate', JSON_OBJECT('EstimateID', OLD.`EstimateID`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `RepairEstimateHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'RepairEstimate';
END //

CREATE TRIGGER trg_Invoice_Audit_ai
AFTER INSERT ON Invoice
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Create', 'Invoice', NEW.InvoiceID, NULL,
        JSON_OBJECT('AppointmentID', NEW.AppointmentID,
                    'CreatedByUserID', NEW.CreatedByUserID,
                    'FinalizedByUserID', NEW.FinalizedByUserID,
                    'InvoiceDate',   NEW.InvoiceDate,
                    'Status',        NEW.Status,
                    'TotalAmount',   NEW.TotalAmount,
                    'FinalizationDateTime', NEW.FinalizationDateTime));
END //

CREATE TRIGGER `trg_Invoice_History_ai` AFTER INSERT ON `Invoice` FOR EACH ROW
FOLLOWS trg_Invoice_Audit_ai
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('InvoiceID', 'AppointmentID', 'CreatedByUserID', 'FinalizedByUserID', 'InvoiceDate', 'Status', 'TotalAmount', 'FinalizationDateTime');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `InvoiceHistory` WHERE `InvoiceID` = NEW.`InvoiceID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('Invoice', JSON_OBJECT('InvoiceID', NEW.`InvoiceID`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `InvoiceHistory` (`InvoiceID`, `AppointmentID`, `CreatedByUserID`, `FinalizedByUserID`, `InvoiceDate`, `Status`, `TotalAmount`, `FinalizationDateTime`, `StatusIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`InvoiceID`, NEW.`AppointmentID`, NEW.`CreatedByUserID`, NEW.`FinalizedByUserID`, NEW.`InvoiceDate`, NEW.`Status`, NEW.`TotalAmount`, NEW.`FinalizationDateTime`, NEW.`StatusIndicator`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Invoice';
END //

CREATE TRIGGER trg_Invoice_Audit_au
AFTER UPDATE ON Invoice
FOR EACH ROW
BEGIN
    DECLARE v_Old JSON;
    DECLARE v_New JSON;
    DECLARE v_Action VARCHAR(50);

    SET v_Old = JSON_OBJECT('AppointmentID',        OLD.AppointmentID,
                            'CreatedByUserID',      OLD.CreatedByUserID,
                            'InvoiceDate',          OLD.InvoiceDate,
                            'TotalAmount',          OLD.TotalAmount,
                            'Status',               OLD.Status,
                            'FinalizedByUserID',    OLD.FinalizedByUserID,
                            'FinalizationDateTime', OLD.FinalizationDateTime);
    SET v_New = JSON_OBJECT('AppointmentID',        NEW.AppointmentID,
                            'CreatedByUserID',      NEW.CreatedByUserID,
                            'InvoiceDate',          NEW.InvoiceDate,
                            'TotalAmount',          NEW.TotalAmount,
                            'Status',               NEW.Status,
                            'FinalizedByUserID',    NEW.FinalizedByUserID,
                            'FinalizationDateTime', NEW.FinalizationDateTime);

    IF v_Old <> v_New THEN
        SET v_Action = CASE
            WHEN NOT (OLD.Status <=> NEW.Status) AND NEW.Status = 'Finalized' THEN 'Finalize'
            WHEN NOT (OLD.Status <=> NEW.Status)                              THEN 'Status Change'
            ELSE 'Update'
        END;

        CALL sp_WriteAuditLog(v_Action, 'Invoice', NEW.InvoiceID, v_Old, v_New);
    END IF;
END //

CREATE TRIGGER `trg_Invoice_History_au` AFTER UPDATE ON `Invoice` FOR EACH ROW
FOLLOWS trg_Invoice_Audit_au
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('InvoiceID', OLD.`InvoiceID`, 'AppointmentID', OLD.`AppointmentID`, 'CreatedByUserID', OLD.`CreatedByUserID`, 'FinalizedByUserID', OLD.`FinalizedByUserID`, 'InvoiceDate', OLD.`InvoiceDate`, 'Status', OLD.`Status`, 'TotalAmount', OLD.`TotalAmount`, 'FinalizationDateTime', OLD.`FinalizationDateTime`) AS BINARY) <=> CAST(JSON_OBJECT('InvoiceID', NEW.`InvoiceID`, 'AppointmentID', NEW.`AppointmentID`, 'CreatedByUserID', NEW.`CreatedByUserID`, 'FinalizedByUserID', NEW.`FinalizedByUserID`, 'InvoiceDate', NEW.`InvoiceDate`, 'Status', NEW.`Status`, 'TotalAmount', NEW.`TotalAmount`, 'FinalizationDateTime', NEW.`FinalizationDateTime`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`InvoiceID` AS BINARY) <=> CAST(NEW.`InvoiceID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'InvoiceID'); END IF;
    IF NOT (CAST(OLD.`AppointmentID` AS BINARY) <=> CAST(NEW.`AppointmentID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'AppointmentID'); END IF;
    IF NOT (CAST(OLD.`CreatedByUserID` AS BINARY) <=> CAST(NEW.`CreatedByUserID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'CreatedByUserID'); END IF;
    IF NOT (CAST(OLD.`FinalizedByUserID` AS BINARY) <=> CAST(NEW.`FinalizedByUserID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'FinalizedByUserID'); END IF;
    IF NOT (CAST(OLD.`InvoiceDate` AS BINARY) <=> CAST(NEW.`InvoiceDate` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'InvoiceDate'); END IF;
    IF NOT (CAST(OLD.`Status` AS BINARY) <=> CAST(NEW.`Status` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Status'); END IF;
    IF NOT (CAST(OLD.`TotalAmount` AS BINARY) <=> CAST(NEW.`TotalAmount` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'TotalAmount'); END IF;
    IF NOT (CAST(OLD.`FinalizationDateTime` AS BINARY) <=> CAST(NEW.`FinalizationDateTime` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'FinalizationDateTime'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `InvoiceHistory`
    WHERE `InvoiceID` = OLD.`InvoiceID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `InvoiceHistory` WHERE `InvoiceID` = NEW.`InvoiceID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('Invoice', JSON_OBJECT('InvoiceID', NEW.`InvoiceID`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `InvoiceHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `InvoiceHistory` (`InvoiceID`, `AppointmentID`, `CreatedByUserID`, `FinalizedByUserID`, `InvoiceDate`, `Status`, `TotalAmount`, `FinalizationDateTime`, `StatusIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`InvoiceID`, NEW.`AppointmentID`, NEW.`CreatedByUserID`, NEW.`FinalizedByUserID`, NEW.`InvoiceDate`, NEW.`Status`, NEW.`TotalAmount`, NEW.`FinalizationDateTime`, NEW.`StatusIndicator`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Invoice';
    END IF;
END //

CREATE TRIGGER trg_Invoice_Audit_ad
AFTER DELETE ON Invoice
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Delete', 'Invoice', OLD.InvoiceID,
        JSON_OBJECT('AppointmentID',        OLD.AppointmentID,
                    'CreatedByUserID',      OLD.CreatedByUserID,
                    'FinalizedByUserID',    OLD.FinalizedByUserID,
                    'InvoiceDate',          OLD.InvoiceDate,
                    'Status',               OLD.Status,
                    'TotalAmount',          OLD.TotalAmount,
                    'FinalizationDateTime', OLD.FinalizationDateTime),
        NULL);
END //

CREATE TRIGGER `trg_Invoice_History_ad` AFTER DELETE ON `Invoice` FOR EACH ROW
FOLLOWS trg_Invoice_Audit_ad
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('InvoiceID', 'AppointmentID', 'CreatedByUserID', 'FinalizedByUserID', 'InvoiceDate', 'Status', 'TotalAmount', 'FinalizationDateTime');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `InvoiceHistory`
    WHERE `InvoiceID` = OLD.`InvoiceID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('Invoice', JSON_OBJECT('InvoiceID', OLD.`InvoiceID`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `InvoiceHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Invoice';
END //

CREATE TRIGGER trg_PartInventory_Audit_au
AFTER UPDATE ON Part
FOR EACH ROW
BEGIN
    IF NOT (OLD.QuantityOnHand <=> NEW.QuantityOnHand) THEN
        IF @adj_reason IS NULL OR TRIM(@adj_reason) = '' THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51010, MESSAGE_TEXT = 'Inventory adjustments require @adj_reason';
        END IF;

        CALL sp_WriteAuditLog('Inventory Adjustment', 'Part', NEW.PartID,
            JSON_OBJECT('QuantityOnHand', OLD.QuantityOnHand),
            JSON_OBJECT('QuantityOnHand', NEW.QuantityOnHand,
                        'Reason',         @adj_reason));
    END IF;
END //

CREATE TRIGGER `trg_Part_History_au` AFTER UPDATE ON `Part` FOR EACH ROW
FOLLOWS trg_PartInventory_Audit_au
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('PartID', OLD.`PartID`, 'PartNumber', OLD.`PartNumber`, 'PartName', OLD.`PartName`, 'QuantityOnHand', OLD.`QuantityOnHand`, 'UnitCost', OLD.`UnitCost`, 'UnitSellingPrice', OLD.`UnitSellingPrice`, 'MinimumInventoryLevel', OLD.`MinimumInventoryLevel`, 'ActiveStatus', OLD.`ActiveStatus`) AS BINARY) <=> CAST(JSON_OBJECT('PartID', NEW.`PartID`, 'PartNumber', NEW.`PartNumber`, 'PartName', NEW.`PartName`, 'QuantityOnHand', NEW.`QuantityOnHand`, 'UnitCost', NEW.`UnitCost`, 'UnitSellingPrice', NEW.`UnitSellingPrice`, 'MinimumInventoryLevel', NEW.`MinimumInventoryLevel`, 'ActiveStatus', NEW.`ActiveStatus`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`PartID` AS BINARY) <=> CAST(NEW.`PartID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'PartID'); END IF;
    IF NOT (CAST(OLD.`PartNumber` AS BINARY) <=> CAST(NEW.`PartNumber` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'PartNumber'); END IF;
    IF NOT (CAST(OLD.`PartName` AS BINARY) <=> CAST(NEW.`PartName` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'PartName'); END IF;
    IF NOT (CAST(OLD.`QuantityOnHand` AS BINARY) <=> CAST(NEW.`QuantityOnHand` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'QuantityOnHand'); END IF;
    IF NOT (CAST(OLD.`UnitCost` AS BINARY) <=> CAST(NEW.`UnitCost` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'UnitCost'); END IF;
    IF NOT (CAST(OLD.`UnitSellingPrice` AS BINARY) <=> CAST(NEW.`UnitSellingPrice` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'UnitSellingPrice'); END IF;
    IF NOT (CAST(OLD.`MinimumInventoryLevel` AS BINARY) <=> CAST(NEW.`MinimumInventoryLevel` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'MinimumInventoryLevel'); END IF;
    IF NOT (CAST(OLD.`ActiveStatus` AS BINARY) <=> CAST(NEW.`ActiveStatus` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'ActiveStatus'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `PartHistory`
    WHERE `PartID` = OLD.`PartID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `PartHistory` WHERE `PartID` = NEW.`PartID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('Part', JSON_OBJECT('PartID', NEW.`PartID`), 'Update', v_Changed, v_PreviousTime, IF(NOT (OLD.QuantityOnHand <=> NEW.QuantityOnHand), @adj_reason, NULL), v_Event, v_Time, v_User, v_Context);
    UPDATE `PartHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = IF(NOT (OLD.QuantityOnHand <=> NEW.QuantityOnHand), @adj_reason, NULL), HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `PartHistory` (`PartID`, `PartNumber`, `PartName`, `QuantityOnHand`, `UnitCost`, `UnitSellingPrice`, `MinimumInventoryLevel`, `ActiveStatus`, `ActiveIndicator`, `ActiveCode`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`PartID`, NEW.`PartNumber`, NEW.`PartName`, NEW.`QuantityOnHand`, NEW.`UnitCost`, NEW.`UnitSellingPrice`, NEW.`MinimumInventoryLevel`, NEW.`ActiveStatus`, NEW.`ActiveIndicator`, NEW.`ActiveCode`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, IF(NOT (OLD.QuantityOnHand <=> NEW.QuantityOnHand), @adj_reason, NULL), v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Part';
    END IF;
END //

CREATE TRIGGER trg_PartsUsage_Audit_ai
AFTER INSERT ON PartsUsage
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Create', 'PartsUsage', NEW.PartsUsageID, NULL,
        JSON_OBJECT('RepairID',                    NEW.RepairID,
                    'PartID',                      NEW.PartID,
                    'RecordedByUserID',            NEW.RecordedByUserID,
                    'QuantityUsed',                NEW.QuantityUsed,
                    'UnitSellingPriceAtTimeOfUse', NEW.UnitSellingPriceAtTimeOfUse,
                    'UnitCostAtTimeOfUse',         NEW.UnitCostAtTimeOfUse,
                    'RecordedDateTime',            NEW.RecordedDateTime));
END //

CREATE TRIGGER `trg_PartsUsage_History_ai` AFTER INSERT ON `PartsUsage` FOR EACH ROW
FOLLOWS trg_PartsUsage_Audit_ai
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('PartsUsageID', 'RepairID', 'PartID', 'RecordedByUserID', 'QuantityUsed', 'UnitSellingPriceAtTimeOfUse', 'UnitCostAtTimeOfUse', 'RecordedDateTime');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `PartsUsageHistory` WHERE `PartsUsageID` = NEW.`PartsUsageID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('PartsUsage', JSON_OBJECT('PartsUsageID', NEW.`PartsUsageID`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `PartsUsageHistory` (`PartsUsageID`, `RepairID`, `PartID`, `RecordedByUserID`, `QuantityUsed`, `UnitSellingPriceAtTimeOfUse`, `UnitCostAtTimeOfUse`, `RecordedDateTime`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`PartsUsageID`, NEW.`RepairID`, NEW.`PartID`, NEW.`RecordedByUserID`, NEW.`QuantityUsed`, NEW.`UnitSellingPriceAtTimeOfUse`, NEW.`UnitCostAtTimeOfUse`, NEW.`RecordedDateTime`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'PartsUsage';
END //

CREATE TRIGGER trg_PartsUsage_Audit_au
AFTER UPDATE ON PartsUsage
FOR EACH ROW
BEGIN
    DECLARE v_Old JSON;
    DECLARE v_New JSON;

    SET v_Old = JSON_OBJECT('RepairID',                    OLD.RepairID,
                            'PartID',                      OLD.PartID,
                            'RecordedByUserID',            OLD.RecordedByUserID,
                            'QuantityUsed',                OLD.QuantityUsed,
                            'UnitSellingPriceAtTimeOfUse', OLD.UnitSellingPriceAtTimeOfUse,
                            'UnitCostAtTimeOfUse',         OLD.UnitCostAtTimeOfUse,
                            'RecordedDateTime',            OLD.RecordedDateTime);
    SET v_New = JSON_OBJECT('RepairID',                    NEW.RepairID,
                            'PartID',                      NEW.PartID,
                            'RecordedByUserID',            NEW.RecordedByUserID,
                            'QuantityUsed',                NEW.QuantityUsed,
                            'UnitSellingPriceAtTimeOfUse', NEW.UnitSellingPriceAtTimeOfUse,
                            'UnitCostAtTimeOfUse',         NEW.UnitCostAtTimeOfUse,
                            'RecordedDateTime',            NEW.RecordedDateTime);

    IF v_Old <> v_New THEN
        CALL sp_WriteAuditLog('Update', 'PartsUsage', NEW.PartsUsageID, v_Old, v_New);
    END IF;
END //

CREATE TRIGGER `trg_PartsUsage_History_au` AFTER UPDATE ON `PartsUsage` FOR EACH ROW
FOLLOWS trg_PartsUsage_Audit_au
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('PartsUsageID', OLD.`PartsUsageID`, 'RepairID', OLD.`RepairID`, 'PartID', OLD.`PartID`, 'RecordedByUserID', OLD.`RecordedByUserID`, 'QuantityUsed', OLD.`QuantityUsed`, 'UnitSellingPriceAtTimeOfUse', OLD.`UnitSellingPriceAtTimeOfUse`, 'UnitCostAtTimeOfUse', OLD.`UnitCostAtTimeOfUse`, 'RecordedDateTime', OLD.`RecordedDateTime`) AS BINARY) <=> CAST(JSON_OBJECT('PartsUsageID', NEW.`PartsUsageID`, 'RepairID', NEW.`RepairID`, 'PartID', NEW.`PartID`, 'RecordedByUserID', NEW.`RecordedByUserID`, 'QuantityUsed', NEW.`QuantityUsed`, 'UnitSellingPriceAtTimeOfUse', NEW.`UnitSellingPriceAtTimeOfUse`, 'UnitCostAtTimeOfUse', NEW.`UnitCostAtTimeOfUse`, 'RecordedDateTime', NEW.`RecordedDateTime`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`PartsUsageID` AS BINARY) <=> CAST(NEW.`PartsUsageID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'PartsUsageID'); END IF;
    IF NOT (CAST(OLD.`RepairID` AS BINARY) <=> CAST(NEW.`RepairID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'RepairID'); END IF;
    IF NOT (CAST(OLD.`PartID` AS BINARY) <=> CAST(NEW.`PartID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'PartID'); END IF;
    IF NOT (CAST(OLD.`RecordedByUserID` AS BINARY) <=> CAST(NEW.`RecordedByUserID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'RecordedByUserID'); END IF;
    IF NOT (CAST(OLD.`QuantityUsed` AS BINARY) <=> CAST(NEW.`QuantityUsed` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'QuantityUsed'); END IF;
    IF NOT (CAST(OLD.`UnitSellingPriceAtTimeOfUse` AS BINARY) <=> CAST(NEW.`UnitSellingPriceAtTimeOfUse` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'UnitSellingPriceAtTimeOfUse'); END IF;
    IF NOT (CAST(OLD.`UnitCostAtTimeOfUse` AS BINARY) <=> CAST(NEW.`UnitCostAtTimeOfUse` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'UnitCostAtTimeOfUse'); END IF;
    IF NOT (CAST(OLD.`RecordedDateTime` AS BINARY) <=> CAST(NEW.`RecordedDateTime` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'RecordedDateTime'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `PartsUsageHistory`
    WHERE `PartsUsageID` = OLD.`PartsUsageID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `PartsUsageHistory` WHERE `PartsUsageID` = NEW.`PartsUsageID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('PartsUsage', JSON_OBJECT('PartsUsageID', NEW.`PartsUsageID`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `PartsUsageHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `PartsUsageHistory` (`PartsUsageID`, `RepairID`, `PartID`, `RecordedByUserID`, `QuantityUsed`, `UnitSellingPriceAtTimeOfUse`, `UnitCostAtTimeOfUse`, `RecordedDateTime`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`PartsUsageID`, NEW.`RepairID`, NEW.`PartID`, NEW.`RecordedByUserID`, NEW.`QuantityUsed`, NEW.`UnitSellingPriceAtTimeOfUse`, NEW.`UnitCostAtTimeOfUse`, NEW.`RecordedDateTime`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'PartsUsage';
    END IF;
END //

CREATE TRIGGER trg_PartsUsage_Audit_ad
AFTER DELETE ON PartsUsage
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Reversal', 'PartsUsage', OLD.PartsUsageID,
        JSON_OBJECT('RepairID',                    OLD.RepairID,
                    'PartID',                      OLD.PartID,
                    'RecordedByUserID',            OLD.RecordedByUserID,
                    'QuantityUsed',                OLD.QuantityUsed,
                    'UnitSellingPriceAtTimeOfUse', OLD.UnitSellingPriceAtTimeOfUse,
                    'UnitCostAtTimeOfUse',         OLD.UnitCostAtTimeOfUse,
                    'RecordedDateTime',            OLD.RecordedDateTime),
        NULL);
END //

CREATE TRIGGER `trg_PartsUsage_History_ad` AFTER DELETE ON `PartsUsage` FOR EACH ROW
FOLLOWS trg_PartsUsage_Audit_ad
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('PartsUsageID', 'RepairID', 'PartID', 'RecordedByUserID', 'QuantityUsed', 'UnitSellingPriceAtTimeOfUse', 'UnitCostAtTimeOfUse', 'RecordedDateTime');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `PartsUsageHistory`
    WHERE `PartsUsageID` = OLD.`PartsUsageID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('PartsUsage', JSON_OBJECT('PartsUsageID', OLD.`PartsUsageID`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `PartsUsageHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'PartsUsage';
END //

CREATE TRIGGER trg_EstimateLineItem_Audit_ai
AFTER INSERT ON EstimateLineItem
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Create', 'EstimateLineItem', NEW.EstimateID, NULL,
        JSON_OBJECT('EstimateID',  NEW.EstimateID,
                    'LineNumber',  NEW.LineNumber,
                    'Description', NEW.Description,
                    'Quantity',    NEW.Quantity,
                    'UnitPrice',   NEW.UnitPrice,
                    'LineTotal',   NEW.LineTotal));
END //

CREATE TRIGGER `trg_EstimateLineItem_History_ai` AFTER INSERT ON `EstimateLineItem` FOR EACH ROW
FOLLOWS trg_EstimateLineItem_Audit_ai
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('EstimateID', 'LineNumber', 'Description', 'Quantity', 'UnitPrice', 'LineTotal');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `EstimateLineItemHistory` WHERE `EstimateID` = NEW.`EstimateID` AND `LineNumber` = NEW.`LineNumber`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('EstimateLineItem', JSON_OBJECT('EstimateID', NEW.`EstimateID`, 'LineNumber', NEW.`LineNumber`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `EstimateLineItemHistory` (`EstimateID`, `LineNumber`, `Description`, `Quantity`, `UnitPrice`, `LineTotal`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`EstimateID`, NEW.`LineNumber`, NEW.`Description`, NEW.`Quantity`, NEW.`UnitPrice`, NEW.`LineTotal`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'EstimateLineItem';
END //

CREATE TRIGGER trg_EstimateLineItem_Audit_au
AFTER UPDATE ON EstimateLineItem
FOR EACH ROW
BEGIN
    DECLARE v_Old JSON;
    DECLARE v_New JSON;

    SET v_Old = JSON_OBJECT('EstimateID',  OLD.EstimateID,
                            'LineNumber',  OLD.LineNumber,
                            'Description', OLD.Description,
                            'Quantity',    OLD.Quantity,
                            'UnitPrice',   OLD.UnitPrice,
                            'LineTotal',   OLD.LineTotal);
    SET v_New = JSON_OBJECT('EstimateID',  NEW.EstimateID,
                            'LineNumber',  NEW.LineNumber,
                            'Description', NEW.Description,
                            'Quantity',    NEW.Quantity,
                            'UnitPrice',   NEW.UnitPrice,
                            'LineTotal',   NEW.LineTotal);

    IF v_Old <> v_New THEN
        CALL sp_WriteAuditLog('Update', 'EstimateLineItem', NEW.EstimateID, v_Old, v_New);
    END IF;
END //

CREATE TRIGGER `trg_EstimateLineItem_History_au` AFTER UPDATE ON `EstimateLineItem` FOR EACH ROW
FOLLOWS trg_EstimateLineItem_Audit_au
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('EstimateID', OLD.`EstimateID`, 'LineNumber', OLD.`LineNumber`, 'Description', OLD.`Description`, 'Quantity', OLD.`Quantity`, 'UnitPrice', OLD.`UnitPrice`, 'LineTotal', OLD.`LineTotal`) AS BINARY) <=> CAST(JSON_OBJECT('EstimateID', NEW.`EstimateID`, 'LineNumber', NEW.`LineNumber`, 'Description', NEW.`Description`, 'Quantity', NEW.`Quantity`, 'UnitPrice', NEW.`UnitPrice`, 'LineTotal', NEW.`LineTotal`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`EstimateID` AS BINARY) <=> CAST(NEW.`EstimateID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'EstimateID'); END IF;
    IF NOT (CAST(OLD.`LineNumber` AS BINARY) <=> CAST(NEW.`LineNumber` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'LineNumber'); END IF;
    IF NOT (CAST(OLD.`Description` AS BINARY) <=> CAST(NEW.`Description` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Description'); END IF;
    IF NOT (CAST(OLD.`Quantity` AS BINARY) <=> CAST(NEW.`Quantity` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Quantity'); END IF;
    IF NOT (CAST(OLD.`UnitPrice` AS BINARY) <=> CAST(NEW.`UnitPrice` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'UnitPrice'); END IF;
    IF NOT (CAST(OLD.`LineTotal` AS BINARY) <=> CAST(NEW.`LineTotal` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'LineTotal'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `EstimateLineItemHistory`
    WHERE `EstimateID` = OLD.`EstimateID` AND `LineNumber` = OLD.`LineNumber` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `EstimateLineItemHistory` WHERE `EstimateID` = NEW.`EstimateID` AND `LineNumber` = NEW.`LineNumber`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('EstimateLineItem', JSON_OBJECT('EstimateID', NEW.`EstimateID`, 'LineNumber', NEW.`LineNumber`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `EstimateLineItemHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `EstimateLineItemHistory` (`EstimateID`, `LineNumber`, `Description`, `Quantity`, `UnitPrice`, `LineTotal`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`EstimateID`, NEW.`LineNumber`, NEW.`Description`, NEW.`Quantity`, NEW.`UnitPrice`, NEW.`LineTotal`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'EstimateLineItem';
    END IF;
END //

CREATE TRIGGER trg_EstimateLineItem_Audit_ad
AFTER DELETE ON EstimateLineItem
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Delete', 'EstimateLineItem', OLD.EstimateID,
        JSON_OBJECT('EstimateID', OLD.EstimateID,
                    'LineNumber',  OLD.LineNumber,
                    'Description', OLD.Description,
                    'Quantity',    OLD.Quantity,
                    'UnitPrice',   OLD.UnitPrice,
                    'LineTotal',   OLD.LineTotal),
        NULL);
END //

CREATE TRIGGER `trg_EstimateLineItem_History_ad` AFTER DELETE ON `EstimateLineItem` FOR EACH ROW
FOLLOWS trg_EstimateLineItem_Audit_ad
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('EstimateID', 'LineNumber', 'Description', 'Quantity', 'UnitPrice', 'LineTotal');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `EstimateLineItemHistory`
    WHERE `EstimateID` = OLD.`EstimateID` AND `LineNumber` = OLD.`LineNumber` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('EstimateLineItem', JSON_OBJECT('EstimateID', OLD.`EstimateID`, 'LineNumber', OLD.`LineNumber`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `EstimateLineItemHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'EstimateLineItem';
END //

CREATE TRIGGER trg_InvoiceLineItem_Audit_ai
AFTER INSERT ON InvoiceLineItem
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Create', 'InvoiceLineItem', NEW.InvoiceLineItemID, NULL,
        JSON_OBJECT('InvoiceID',   NEW.InvoiceID,
                    'Description', NEW.Description,
                    'Quantity',    NEW.Quantity,
                    'UnitPrice',   NEW.UnitPrice,
                    'LineTotal',   NEW.LineTotal));
END //

CREATE TRIGGER `trg_InvoiceLineItem_History_ai` AFTER INSERT ON `InvoiceLineItem` FOR EACH ROW
FOLLOWS trg_InvoiceLineItem_Audit_ai
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('InvoiceLineItemID', 'InvoiceID', 'Description', 'Quantity', 'UnitPrice', 'LineTotal');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `InvoiceLineItemHistory` WHERE `InvoiceLineItemID` = NEW.`InvoiceLineItemID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('InvoiceLineItem', JSON_OBJECT('InvoiceLineItemID', NEW.`InvoiceLineItemID`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `InvoiceLineItemHistory` (`InvoiceLineItemID`, `InvoiceID`, `Description`, `Quantity`, `UnitPrice`, `LineTotal`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`InvoiceLineItemID`, NEW.`InvoiceID`, NEW.`Description`, NEW.`Quantity`, NEW.`UnitPrice`, NEW.`LineTotal`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'InvoiceLineItem';
END //

CREATE TRIGGER trg_InvoiceLineItem_Audit_au
AFTER UPDATE ON InvoiceLineItem
FOR EACH ROW
BEGIN
    DECLARE v_Old JSON;
    DECLARE v_New JSON;

    SET v_Old = JSON_OBJECT('InvoiceID',   OLD.InvoiceID,
                            'Description', OLD.Description,
                            'Quantity',    OLD.Quantity,
                            'UnitPrice',   OLD.UnitPrice,
                            'LineTotal',   OLD.LineTotal);
    SET v_New = JSON_OBJECT('InvoiceID',   NEW.InvoiceID,
                            'Description', NEW.Description,
                            'Quantity',    NEW.Quantity,
                            'UnitPrice',   NEW.UnitPrice,
                            'LineTotal',   NEW.LineTotal);

    IF v_Old <> v_New THEN
        CALL sp_WriteAuditLog('Update', 'InvoiceLineItem', NEW.InvoiceLineItemID, v_Old, v_New);
    END IF;
END //

CREATE TRIGGER `trg_InvoiceLineItem_History_au` AFTER UPDATE ON `InvoiceLineItem` FOR EACH ROW
FOLLOWS trg_InvoiceLineItem_Audit_au
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('InvoiceLineItemID', OLD.`InvoiceLineItemID`, 'InvoiceID', OLD.`InvoiceID`, 'Description', OLD.`Description`, 'Quantity', OLD.`Quantity`, 'UnitPrice', OLD.`UnitPrice`, 'LineTotal', OLD.`LineTotal`) AS BINARY) <=> CAST(JSON_OBJECT('InvoiceLineItemID', NEW.`InvoiceLineItemID`, 'InvoiceID', NEW.`InvoiceID`, 'Description', NEW.`Description`, 'Quantity', NEW.`Quantity`, 'UnitPrice', NEW.`UnitPrice`, 'LineTotal', NEW.`LineTotal`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`InvoiceLineItemID` AS BINARY) <=> CAST(NEW.`InvoiceLineItemID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'InvoiceLineItemID'); END IF;
    IF NOT (CAST(OLD.`InvoiceID` AS BINARY) <=> CAST(NEW.`InvoiceID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'InvoiceID'); END IF;
    IF NOT (CAST(OLD.`Description` AS BINARY) <=> CAST(NEW.`Description` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Description'); END IF;
    IF NOT (CAST(OLD.`Quantity` AS BINARY) <=> CAST(NEW.`Quantity` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Quantity'); END IF;
    IF NOT (CAST(OLD.`UnitPrice` AS BINARY) <=> CAST(NEW.`UnitPrice` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'UnitPrice'); END IF;
    IF NOT (CAST(OLD.`LineTotal` AS BINARY) <=> CAST(NEW.`LineTotal` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'LineTotal'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `InvoiceLineItemHistory`
    WHERE `InvoiceLineItemID` = OLD.`InvoiceLineItemID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `InvoiceLineItemHistory` WHERE `InvoiceLineItemID` = NEW.`InvoiceLineItemID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('InvoiceLineItem', JSON_OBJECT('InvoiceLineItemID', NEW.`InvoiceLineItemID`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `InvoiceLineItemHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `InvoiceLineItemHistory` (`InvoiceLineItemID`, `InvoiceID`, `Description`, `Quantity`, `UnitPrice`, `LineTotal`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`InvoiceLineItemID`, NEW.`InvoiceID`, NEW.`Description`, NEW.`Quantity`, NEW.`UnitPrice`, NEW.`LineTotal`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'InvoiceLineItem';
    END IF;
END //

CREATE TRIGGER trg_InvoiceLineItem_Audit_ad
AFTER DELETE ON InvoiceLineItem
FOR EACH ROW
BEGIN
    CALL sp_WriteAuditLog('Delete', 'InvoiceLineItem', OLD.InvoiceLineItemID,
        JSON_OBJECT('InvoiceID',   OLD.InvoiceID,
                    'Description', OLD.Description,
                    'Quantity',    OLD.Quantity,
                    'UnitPrice',   OLD.UnitPrice,
                    'LineTotal',   OLD.LineTotal),
        NULL);
END //

CREATE TRIGGER `trg_InvoiceLineItem_History_ad` AFTER DELETE ON `InvoiceLineItem` FOR EACH ROW
FOLLOWS trg_InvoiceLineItem_Audit_ad
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('InvoiceLineItemID', 'InvoiceID', 'Description', 'Quantity', 'UnitPrice', 'LineTotal');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `InvoiceLineItemHistory`
    WHERE `InvoiceLineItemID` = OLD.`InvoiceLineItemID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('InvoiceLineItem', JSON_OBJECT('InvoiceLineItemID', OLD.`InvoiceLineItemID`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `InvoiceLineItemHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'InvoiceLineItem';
END //

CREATE TRIGGER trg_ServiceAppointment_Provenance_bu
BEFORE UPDATE ON `ServiceAppointment` FOR EACH ROW
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`ServiceRequestDescription`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'ServiceAppointment.ServiceRequestDescription cannot be blank'; END IF;
    IF NEW.EstimatedDuration > 1440 THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51001, MESSAGE_TEXT = 'Invalid appointment information';
    END IF;
    IF NOT (OLD.CreationTimestamp <=> NEW.CreationTimestamp) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'Creation timestamp cannot be changed';
    END IF;
    IF NEW.Status = 'Cancelled' AND OLD.Status <> 'Cancelled' THEN
        SET NEW.CancellationDate = UTC_DATE();
    ELSEIF NOT (OLD.CancellationDate <=> NEW.CancellationDate) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'Cancellation date can only be set by cancellation';
    END IF;
END //

CREATE TRIGGER trg_ServiceAppointment_Indicator_bu
BEFORE UPDATE ON `ServiceAppointment` FOR EACH ROW
FOLLOWS trg_ServiceAppointment_Provenance_bu
BEGIN
    CALL sp_ValidateIndicator('appointment_status', NEW.Status);
END //

CREATE TRIGGER trg_ServiceAppointment_Status_Validate_bu
BEFORE UPDATE ON ServiceAppointment
FOR EACH ROW
FOLLOWS trg_ServiceAppointment_Indicator_bu
BEGIN
    -- Record IDs never change 
    IF NOT (OLD.AppointmentID <=> NEW.AppointmentID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'Record IDs cannot be changed';
    END IF;

    -- The creating user is a historical fact and never changes
    IF NOT (OLD.CreatedByUserID <=> NEW.CreatedByUserID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'The creating user cannot be changed';
    END IF;

    IF OLD.Status IN ('Completed', 'Cancelled', 'No Show') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54003, MESSAGE_TEXT = 'Completed, cancelled, or no-show appointments cannot be modified';
    END IF;

    -- The vehicle is fixed when the appointment is booked, so it cannot be changed later (FR-14)
    IF NOT (OLD.VehicleID <=> NEW.VehicleID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'An appointment cannot be moved to another vehicle';
    END IF;

    IF NOT (OLD.Status <=> NEW.Status) THEN
        IF NOT (
            (OLD.Status = 'Scheduled'   AND NEW.Status IN ('Checked In', 'Cancelled', 'No Show')) OR
            (OLD.Status = 'Checked In'  AND NEW.Status = 'In Progress') OR
            (OLD.Status = 'In Progress' AND NEW.Status = 'Completed')
        ) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54002, MESSAGE_TEXT = 'Invalid appointment status transition';
        END IF;

        -- An appointment cannot be closed while it still has unfinished work:
        -- every repair must be Completed or Cancelled first
        IF NEW.Status IN ('Completed', 'Cancelled', 'No Show')
           AND EXISTS (SELECT 1 FROM Repair
                       WHERE AppointmentID = OLD.AppointmentID
                         AND Status IN ('Open', 'In Progress')) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54005, MESSAGE_TEXT = 'Appointment has open repairs: complete or cancel them first';
        END IF;

        -- Record the cancellation date if the caller did not supply one
        IF NEW.Status = 'Cancelled' THEN
            SET NEW.CancellationDate = COALESCE(NEW.CancellationDate, CURDATE());
        END IF;
    END IF;
END //

CREATE TRIGGER trg_ServiceAppointment_Schedule_Validate_bu
BEFORE UPDATE ON ServiceAppointment
FOR EACH ROW
FOLLOWS trg_ServiceAppointment_Status_Validate_bu
BEGIN
    DECLARE v_Count INT DEFAULT 0;
    DECLARE v_EndDateTime DATETIME; -- when the new appointment ends 

    -- appointment is active and the caller is changing the date/time, duration, or technician
    IF NEW.Status IN ('Scheduled', 'Checked In', 'In Progress')
       AND (NOT (OLD.AppointmentDateTime <=> NEW.AppointmentDateTime)
            OR NOT (OLD.EstimatedDuration <=> NEW.EstimatedDuration)
            OR NOT (OLD.TechnicianID      <=> NEW.TechnicianID)) THEN

        IF NEW.EstimatedDuration > 1440 THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51001, MESSAGE_TEXT = 'Invalid appointment information';
        END IF;

        -- Lock the technician and vehicle rows, as the booking procedure
        -- does, so a reschedule and a booking cannot both take one slot
        SELECT COUNT(*) INTO v_Count
        FROM Technician
        WHERE TechnicianID = NEW.TechnicianID AND ActiveStatus = 1
        FOR UPDATE;

        IF v_Count = 0 THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54005, MESSAGE_TEXT = 'Technician does not exist or is inactive';
        END IF;

        SELECT COUNT(*) INTO v_Count
        FROM Vehicle
        WHERE VehicleID = NEW.VehicleID
        FOR UPDATE;

        SET v_EndDateTime = DATE_ADD(NEW.AppointmentDateTime,
                                     INTERVAL NEW.EstimatedDuration MINUTE);

        -- Another active appointment for the same vehicle that overlaps
        SELECT COUNT(*) INTO v_Count
        FROM ServiceAppointment
        WHERE VehicleID = NEW.VehicleID
          AND AppointmentID <> NEW.AppointmentID
          AND Status IN ('Scheduled', 'Checked In', 'In Progress')
          AND AppointmentDateTime < v_EndDateTime
          AND DATE_ADD(AppointmentDateTime, INTERVAL EstimatedDuration MINUTE)
              > NEW.AppointmentDateTime;

        IF v_Count > 0 THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54001, MESSAGE_TEXT = 'Vehicle already has a conflicting appointment';
        END IF;

        -- Another active appointment for the same technician that overlaps
        SELECT COUNT(*) INTO v_Count
        FROM ServiceAppointment
        WHERE TechnicianID = NEW.TechnicianID
          AND AppointmentID <> NEW.AppointmentID
          AND Status IN ('Scheduled', 'Checked In', 'In Progress')
          AND AppointmentDateTime < v_EndDateTime
          AND DATE_ADD(AppointmentDateTime, INTERVAL EstimatedDuration MINUTE)
              > NEW.AppointmentDateTime;

        IF v_Count > 0 THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54001, MESSAGE_TEXT = 'Technician already has a conflicting appointment';
        END IF;
    END IF;
END //

CREATE TRIGGER trg_Repair_Provenance_bi
BEFORE INSERT ON `Repair` FOR EACH ROW
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`RepairDescription`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Repair.RepairDescription cannot be blank'; END IF;
    IF NEW.CompletedByTechnicianID IS NOT NULL OR NEW.CompletionDateTime IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51008, MESSAGE_TEXT = 'New repairs cannot contain completion metadata';
    END IF;
END //

CREATE TRIGGER trg_Repair_Indicator_bi
BEFORE INSERT ON `Repair` FOR EACH ROW
FOLLOWS trg_Repair_Provenance_bi
BEGIN
    CALL sp_ValidateIndicator('repair_status', NEW.Status);
    CALL sp_ValidateIndicator('repair_type', NEW.RepairType);
END //

CREATE TRIGGER trg_Repair_Status_Validate_bi
BEFORE INSERT ON Repair
FOR EACH ROW
FOLLOWS trg_Repair_Indicator_bi
BEGIN
    DECLARE v_ApptStatus VARCHAR(20) DEFAULT NULL;

    -- New repairs must start as Open (FRD transitions)
    IF NEW.Status <> 'Open' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54002, MESSAGE_TEXT = 'New repairs must start in Open status';
    END IF;

    -- Repairs cannot be added to a closed appointment
    SELECT Status INTO v_ApptStatus
    FROM ServiceAppointment
    WHERE AppointmentID = NEW.AppointmentID;

    IF v_ApptStatus IN ('Completed', 'Cancelled', 'No Show') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54005, MESSAGE_TEXT = 'Repairs cannot be added to a completed, cancelled, or no-show appointment';
    END IF;
END //

CREATE TRIGGER trg_Repair_Provenance_bu
BEFORE UPDATE ON `Repair` FOR EACH ROW
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`RepairDescription`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Repair.RepairDescription cannot be blank'; END IF;
    IF NEW.Status = 'Completed' AND OLD.Status <> 'Completed' THEN
        IF NOT EXISTS (SELECT 1 FROM OperationContext WHERE ConnectionID = CONNECTION_ID()
                       AND SessionAccount = USER() AND ProcedureName = 'sp_CompleteRepair')
           AND NOT EXISTS (SELECT 1 FROM UserAccount WHERE UserID = v_UserID AND RoleType = 'Manager') THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52010, MESSAGE_TEXT = 'Repair completion requires its procedure or a Manager';
        END IF;
        SELECT TechnicianID INTO v_AssignedTech FROM ServiceAppointment WHERE AppointmentID = OLD.AppointmentID;
        IF NEW.CompletedByTechnicianID IS NOT NULL AND NOT (NEW.CompletedByTechnicianID <=> v_AssignedTech) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52006, MESSAGE_TEXT = 'Completing technician must be assigned to the appointment';
        END IF;
        SET NEW.CompletedByTechnicianID = v_AssignedTech;
        SET NEW.CompletionDateTime = UTC_TIMESTAMP();
    ELSEIF NOT (OLD.CompletedByTechnicianID <=> NEW.CompletedByTechnicianID)
        OR NOT (OLD.CompletionDateTime <=> NEW.CompletionDateTime) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'Completion fields can only be set by completion';
    END IF;
END //

CREATE TRIGGER trg_Repair_Indicator_bu
BEFORE UPDATE ON `Repair` FOR EACH ROW
FOLLOWS trg_Repair_Provenance_bu
BEGIN
    CALL sp_ValidateIndicator('repair_status', NEW.Status);
    CALL sp_ValidateIndicator('repair_type', NEW.RepairType);
END //

CREATE TRIGGER trg_Repair_Status_Validate_bu
BEFORE UPDATE ON Repair
FOR EACH ROW
FOLLOWS trg_Repair_Indicator_bu
BEGIN
    DECLARE v_Role       VARCHAR(30) DEFAULT NULL;
    DECLARE v_UserTechID INT         DEFAULT NULL;
    DECLARE v_ApptTechID INT         DEFAULT NULL;

    -- Record IDs never change (a changed ID would also escape the audit trail)
    IF NOT (OLD.RepairID <=> NEW.RepairID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'Record IDs cannot be changed';
    END IF;

    IF OLD.Status IN ('Completed', 'Cancelled') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54003, MESSAGE_TEXT = 'Completed or cancelled repairs cannot be modified';
    END IF;

    -- A repair belongs to the appointment it was opened on
    IF NOT (OLD.AppointmentID <=> NEW.AppointmentID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'A repair cannot be moved to another appointment';
    END IF;

    IF NOT (OLD.Status <=> NEW.Status) THEN
        IF NOT (
            (OLD.Status = 'Open'        AND NEW.Status IN ('In Progress', 'Cancelled')) OR
            (OLD.Status = 'In Progress' AND NEW.Status IN ('Completed', 'Cancelled'))
        ) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54002, MESSAGE_TEXT = 'Invalid repair status transition';
        END IF;

        -- Technician ownership check (SEC-02, T-29): a technician cannot
        -- change the status of a repair assigned to another technician
        SELECT RoleType, TechnicianID
        INTO v_Role, v_UserTechID
        FROM UserAccount
        WHERE UserID = @app_user_id;

        IF v_Role = 'Technician' THEN
            SELECT TechnicianID
            INTO v_ApptTechID
            FROM ServiceAppointment
            WHERE AppointmentID = NEW.AppointmentID;

            IF v_UserTechID IS NULL OR NOT (v_UserTechID <=> v_ApptTechID) THEN
                SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52006, MESSAGE_TEXT = 'Technicians may only update their own assigned repairs';
            END IF;
        END IF;
    END IF;
END //

CREATE TRIGGER trg_RepairEstimate_Provenance_bi
BEFORE INSERT ON `RepairEstimate` FOR EACH ROW
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF NEW.CreatedByUserID IS NOT NULL AND NOT (NEW.CreatedByUserID <=> v_UserID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52002, MESSAGE_TEXT = 'Creating user must match the responsible actor';
    END IF;
    SET NEW.CreatedByUserID = v_UserID;
    IF NEW.ApprovedByUserID IS NOT NULL OR NEW.ApprovalDateTime IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51008, MESSAGE_TEXT = 'Draft estimates cannot contain approval metadata';
    END IF;
END //

CREATE TRIGGER trg_RepairEstimate_Indicator_bi
BEFORE INSERT ON `RepairEstimate` FOR EACH ROW
FOLLOWS trg_RepairEstimate_Provenance_bi
BEGIN
    CALL sp_ValidateIndicator('estimate_status', NEW.Status);
END //

CREATE TRIGGER trg_RepairEstimate_Validate_bi
BEFORE INSERT ON RepairEstimate
FOR EACH ROW
FOLLOWS trg_RepairEstimate_Indicator_bi
BEGIN
    IF NEW.Status <> 'Draft' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54002, MESSAGE_TEXT = 'New repair estimates must start in Draft status';
    END IF;
END //

CREATE TRIGGER trg_RepairEstimate_Provenance_bu
BEFORE UPDATE ON `RepairEstimate` FOR EACH ROW
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF NEW.Status IN ('Approved', 'Rejected') AND NOT (OLD.Status <=> NEW.Status) THEN
        IF NEW.ApprovedByUserID IS NOT NULL AND NOT (NEW.ApprovedByUserID <=> v_UserID) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52002, MESSAGE_TEXT = 'Approver must match the responsible actor';
        END IF;
        SET NEW.ApprovedByUserID = v_UserID;
        SET NEW.ApprovalDateTime = UTC_TIMESTAMP();
    END IF;
END //

CREATE TRIGGER trg_RepairEstimate_Indicator_bu
BEFORE UPDATE ON `RepairEstimate` FOR EACH ROW
FOLLOWS trg_RepairEstimate_Provenance_bu
BEGIN
    CALL sp_ValidateIndicator('estimate_status', NEW.Status);
END //

CREATE TRIGGER trg_RepairEstimate_Validate_bu
BEFORE UPDATE ON RepairEstimate
FOR EACH ROW
FOLLOWS trg_RepairEstimate_Indicator_bu
BEGIN
    DECLARE v_Role VARCHAR(30) DEFAULT NULL;

    -- The approval record is set only by the Manager's decision below:
    -- it cannot be written or rewritten by any other update
    IF NOT (NEW.Status IN ('Approved', 'Rejected') AND NOT (OLD.Status <=> NEW.Status))
       AND (NOT (OLD.ApprovedByUserID <=> NEW.ApprovedByUserID)
            OR NOT (OLD.ApprovalDateTime <=> NEW.ApprovalDateTime)) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'Approval fields can only be set by the approval itself';
    END IF;

    -- Record IDs never change (a changed ID would also escape the audit trail)
    IF NOT (OLD.EstimateID <=> NEW.EstimateID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'Record IDs cannot be changed';
    END IF;

    -- The creating user is a historical fact and never changes
    IF NOT (OLD.CreatedByUserID <=> NEW.CreatedByUserID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'The creating user cannot be changed';
    END IF;

    IF OLD.Status = 'Finalized' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54003, MESSAGE_TEXT = 'Finalized estimates cannot be modified';
    END IF;

    -- An estimate belongs to the appointment it was created for
    IF NOT (OLD.AppointmentID <=> NEW.AppointmentID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'An estimate cannot be moved to another appointment';
    END IF;

    IF NOT (OLD.Status <=> NEW.Status) THEN
        IF NOT (
            (OLD.Status = 'Draft'            AND NEW.Status = 'Pending Approval') OR
            (OLD.Status = 'Pending Approval' AND NEW.Status IN ('Approved', 'Rejected', 'Expired')) OR
            (OLD.Status = 'Approved'         AND NEW.Status = 'Finalized')
        ) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54002, MESSAGE_TEXT = 'Invalid estimate status transition';
        END IF;

        -- The manager's decision is recorded in ApprovedByUserID and ApprovalDateTime
        IF NEW.Status IN ('Approved', 'Rejected') THEN
            SET NEW.ApprovedByUserID = COALESCE(NEW.ApprovedByUserID, @app_user_id);

            SELECT RoleType
            INTO v_Role
            FROM UserAccount
            WHERE UserID = @app_user_id;

            IF v_Role IS NULL OR v_Role <> 'Manager'
               OR NOT (NEW.ApprovedByUserID <=> @app_user_id) THEN
                SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52006, MESSAGE_TEXT = 'Estimates must be approved or rejected by a Manager';
            END IF;

            SET NEW.ApprovalDateTime = COALESCE(NEW.ApprovalDateTime, NOW());
        END IF;

        -- finalized estimate's total must equal the sum of its line items
        IF NEW.Status = 'Finalized'
           AND NEW.TotalAmount <> (SELECT COALESCE(SUM(LineTotal), 0)
                                   FROM EstimateLineItem
                                   WHERE EstimateID = NEW.EstimateID) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54007, MESSAGE_TEXT = 'Estimate total must equal the sum of its line items';
        END IF;
    END IF;
END //

CREATE TRIGGER trg_RepairEstimate_Validate_bd
BEFORE DELETE ON RepairEstimate
FOR EACH ROW

BEGIN
    IF OLD.Status = 'Finalized' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54003, MESSAGE_TEXT = 'Finalized estimates cannot be deleted';
    END IF;
END //

CREATE TRIGGER trg_Invoice_Provenance_bi
BEFORE INSERT ON `Invoice` FOR EACH ROW
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF NEW.CreatedByUserID IS NOT NULL AND NOT (NEW.CreatedByUserID <=> v_UserID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52002, MESSAGE_TEXT = 'Creating user must match the responsible actor';
    END IF;
    SET NEW.CreatedByUserID = v_UserID;
    IF NEW.FinalizedByUserID IS NOT NULL OR NEW.FinalizationDateTime IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51008, MESSAGE_TEXT = 'Draft invoices cannot contain finalization metadata';
    END IF;
END //

CREATE TRIGGER trg_Invoice_Indicator_bi
BEFORE INSERT ON `Invoice` FOR EACH ROW
FOLLOWS trg_Invoice_Provenance_bi
BEGIN
    CALL sp_ValidateIndicator('invoice_status', NEW.Status);
END //

CREATE TRIGGER trg_Invoice_Validate_bi
BEFORE INSERT ON Invoice
FOR EACH ROW
FOLLOWS trg_Invoice_Indicator_bi
BEGIN
    IF NEW.Status <> 'Draft' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54002, MESSAGE_TEXT = 'New invoices must start in Draft status';
    END IF;
END //

CREATE TRIGGER trg_Invoice_Provenance_bu
BEFORE UPDATE ON `Invoice` FOR EACH ROW
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF NEW.Status = 'Finalized' AND OLD.Status <> 'Finalized' THEN
        IF NEW.FinalizedByUserID IS NOT NULL AND NOT (NEW.FinalizedByUserID <=> v_UserID) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52002, MESSAGE_TEXT = 'Finalizer must match the responsible actor';
        END IF;
        SET NEW.FinalizedByUserID = v_UserID;
        SET NEW.FinalizationDateTime = UTC_TIMESTAMP();
    ELSEIF NOT (OLD.FinalizedByUserID <=> NEW.FinalizedByUserID)
        OR NOT (OLD.FinalizationDateTime <=> NEW.FinalizationDateTime) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'Finalization fields can only be set by finalization';
    END IF;
END //

CREATE TRIGGER trg_Invoice_Indicator_bu
BEFORE UPDATE ON `Invoice` FOR EACH ROW
FOLLOWS trg_Invoice_Provenance_bu
BEGIN
    CALL sp_ValidateIndicator('invoice_status', NEW.Status);
END //

CREATE TRIGGER trg_Invoice_TransitionGuard_bu
BEFORE UPDATE ON Invoice FOR EACH ROW
FOLLOWS trg_Invoice_Indicator_bu
BEGIN
    IF NOT (OLD.Status <=> NEW.Status)
       AND NOT (OLD.Status = 'Draft' AND NEW.Status = 'Finalized') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54002, MESSAGE_TEXT = 'Invalid invoice status transition';
    END IF;
END //

CREATE TRIGGER trg_Invoice_Validate_bu
BEFORE UPDATE ON Invoice
FOR EACH ROW
FOLLOWS trg_Invoice_TransitionGuard_bu
BEGIN
    DECLARE v_Role VARCHAR(30) DEFAULT NULL;

    -- Record IDs never change (a changed ID would also escape the audit trail)
    IF NOT (OLD.InvoiceID <=> NEW.InvoiceID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'Record IDs cannot be changed';
    END IF;

    -- The creating user is a historical fact and never changes
    IF NOT (OLD.CreatedByUserID <=> NEW.CreatedByUserID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'The creating user cannot be changed';
    END IF;

    IF OLD.Status = 'Finalized' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54003, MESSAGE_TEXT = 'Finalized invoices cannot be modified';
    END IF;

    -- An invoice belongs to the appointment it was created for
    IF NOT (OLD.AppointmentID <=> NEW.AppointmentID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'An invoice cannot be moved to another appointment';
    END IF;

    -- The CHECK constraint allows only Draft and Finalized, so the only
    -- possible transition from here is Draft -> Finalized
    IF NEW.Status = 'Finalized' THEN
        SET NEW.FinalizedByUserID = COALESCE(NEW.FinalizedByUserID, @app_user_id);

        SELECT RoleType
        INTO v_Role
        FROM UserAccount
        WHERE UserID = @app_user_id;

        IF v_Role IS NULL OR v_Role NOT IN ('Service Advisor', 'Manager')
           OR NOT (NEW.FinalizedByUserID <=> @app_user_id) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52006, MESSAGE_TEXT = 'Invoices must be finalized by a Service Advisor or Manager';
        END IF;

        SET NEW.FinalizationDateTime = COALESCE(NEW.FinalizationDateTime, NOW());

        -- A finalized invoice's total must equal the sum of its line items
        IF NEW.TotalAmount <> (SELECT COALESCE(SUM(LineTotal), 0)
                               FROM InvoiceLineItem
                               WHERE InvoiceID = NEW.InvoiceID) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54007, MESSAGE_TEXT = 'Invoice total must equal the sum of its line items';
        END IF;
    END IF;
END //

CREATE TRIGGER trg_Invoice_Validate_bd
BEFORE DELETE ON Invoice
FOR EACH ROW

BEGIN
    IF OLD.Status = 'Finalized' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54003, MESSAGE_TEXT = 'Finalized invoices cannot be deleted';
    END IF;
END //

CREATE TRIGGER trg_InvoiceLineItem_Provenance_bi
BEFORE INSERT ON `InvoiceLineItem` FOR EACH ROW
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`Description`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'InvoiceLineItem.Description cannot be blank'; END IF;
END //

CREATE TRIGGER trg_InvoiceLineItem_Validate_bi
BEFORE INSERT ON InvoiceLineItem
FOR EACH ROW
FOLLOWS trg_InvoiceLineItem_Provenance_bi
BEGIN
    IF (SELECT Status FROM Invoice WHERE InvoiceID = NEW.InvoiceID) = 'Finalized' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54003, MESSAGE_TEXT = 'Cannot add line items to a finalized invoice';
    END IF;
END //

CREATE TRIGGER trg_InvoiceLineItem_Provenance_bu
BEFORE UPDATE ON `InvoiceLineItem` FOR EACH ROW
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`Description`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'InvoiceLineItem.Description cannot be blank'; END IF;
END //

CREATE TRIGGER trg_InvoiceLineItem_Validate_bu
BEFORE UPDATE ON InvoiceLineItem
FOR EACH ROW
FOLLOWS trg_InvoiceLineItem_Provenance_bu
BEGIN
    -- Record IDs never change (a changed ID would also escape the audit trail)
    IF NOT (OLD.InvoiceLineItemID <=> NEW.InvoiceLineItemID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'Record IDs cannot be changed';
    END IF;

    -- A line item belongs to the invoice it was added to
    IF NOT (OLD.InvoiceID <=> NEW.InvoiceID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'A line item cannot be moved to another invoice';
    END IF;

    IF (SELECT Status FROM Invoice WHERE InvoiceID = OLD.InvoiceID) = 'Finalized'
       OR (SELECT Status FROM Invoice WHERE InvoiceID = NEW.InvoiceID) = 'Finalized' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54003, MESSAGE_TEXT = 'Cannot modify line items of a finalized invoice';
    END IF;
END //

CREATE TRIGGER trg_InvoiceLineItem_Validate_bd
BEFORE DELETE ON InvoiceLineItem
FOR EACH ROW

BEGIN
    IF (SELECT Status FROM Invoice WHERE InvoiceID = OLD.InvoiceID) = 'Finalized' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54003, MESSAGE_TEXT = 'Cannot delete line items of a finalized invoice';
    END IF;
END //

CREATE TRIGGER trg_EstimateLineItem_Provenance_bi
BEFORE INSERT ON `EstimateLineItem` FOR EACH ROW
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`Description`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'EstimateLineItem.Description cannot be blank'; END IF;
END //

CREATE TRIGGER trg_EstimateLineItem_Validate_bi
BEFORE INSERT ON EstimateLineItem
FOR EACH ROW
FOLLOWS trg_EstimateLineItem_Provenance_bi
BEGIN
    IF (SELECT Status FROM RepairEstimate WHERE EstimateID = NEW.EstimateID) = 'Finalized' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54003, MESSAGE_TEXT = 'Cannot add line items to a finalized estimate';
    END IF;
END //

CREATE TRIGGER trg_EstimateLineItem_Provenance_bu
BEFORE UPDATE ON `EstimateLineItem` FOR EACH ROW
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`Description`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'EstimateLineItem.Description cannot be blank'; END IF;
END //

CREATE TRIGGER trg_EstimateLineItem_Validate_bu
BEFORE UPDATE ON EstimateLineItem
FOR EACH ROW
FOLLOWS trg_EstimateLineItem_Provenance_bu
BEGIN
    -- A line item belongs to the estimate it was added to
    IF NOT (OLD.EstimateID <=> NEW.EstimateID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'A line item cannot be moved to another estimate';
    END IF;

    IF (SELECT Status FROM RepairEstimate WHERE EstimateID = OLD.EstimateID) = 'Finalized'
       OR (SELECT Status FROM RepairEstimate WHERE EstimateID = NEW.EstimateID) = 'Finalized' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54003, MESSAGE_TEXT = 'Cannot modify line items of a finalized estimate';
    END IF;
END //

CREATE TRIGGER trg_EstimateLineItem_Validate_bd
BEFORE DELETE ON EstimateLineItem
FOR EACH ROW

BEGIN
    IF (SELECT Status FROM RepairEstimate WHERE EstimateID = OLD.EstimateID) = 'Finalized' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54003, MESSAGE_TEXT = 'Cannot delete line items of a finalized estimate';
    END IF;
END //

CREATE TRIGGER trg_AuditLog_Protect_bu
BEFORE UPDATE ON AuditLog
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52009, MESSAGE_TEXT = 'Audit records cannot be modified';
END //

CREATE TRIGGER trg_AuditLog_Indicator_bu
BEFORE UPDATE ON `AuditLog` FOR EACH ROW
FOLLOWS trg_AuditLog_Protect_bu
BEGIN
    CALL sp_ValidateIndicator('audit_action', NEW.Action);
    CALL sp_ValidateIndicator('audit_entity', NEW.AffectedEntity);
END //

CREATE TRIGGER trg_AuditLog_Protect_bd
BEFORE DELETE ON AuditLog
FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52009, MESSAGE_TEXT = 'Audit records cannot be deleted';
END //

CREATE TRIGGER trg_UserAccount_Provenance_bi
BEFORE INSERT ON `UserAccount` FOR EACH ROW
BEGIN
    IF TRIM(NEW.`Username`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'UserAccount.Username cannot be blank'; END IF;
    IF TRIM(NEW.`Name`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'UserAccount.Name cannot be blank'; END IF;
    IF NOT EXISTS (SELECT 1 FROM UserRolePolicy p WHERE p.RoleType = NEW.RoleType
                   AND ((p.RequiresTechnician = 1 AND NEW.TechnicianID IS NOT NULL)
                     OR (p.RequiresTechnician = 0 AND NEW.TechnicianID IS NULL))) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51005, MESSAGE_TEXT = 'User role and technician profile do not match';
    END IF;
END //

CREATE TRIGGER trg_UserAccount_Indicator_bi
BEFORE INSERT ON `UserAccount` FOR EACH ROW
FOLLOWS trg_UserAccount_Provenance_bi
BEGIN
    CALL sp_ValidateIndicator('user_role', NEW.RoleType);
END //

CREATE TRIGGER trg_UserAccount_Provenance_bu
BEFORE UPDATE ON `UserAccount` FOR EACH ROW
BEGIN
    IF TRIM(NEW.`Username`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'UserAccount.Username cannot be blank'; END IF;
    IF TRIM(NEW.`Name`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'UserAccount.Name cannot be blank'; END IF;
    IF NOT EXISTS (SELECT 1 FROM UserRolePolicy p WHERE p.RoleType = NEW.RoleType
                   AND ((p.RequiresTechnician = 1 AND NEW.TechnicianID IS NOT NULL)
                     OR (p.RequiresTechnician = 0 AND NEW.TechnicianID IS NULL))) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51005, MESSAGE_TEXT = 'User role and technician profile do not match';
    END IF;
    IF NOT (OLD.UserID <=> NEW.UserID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'User identifiers cannot be changed';
    END IF;
    IF NOT (OLD.Username <=> NEW.Username) AND EXISTS (SELECT 1 FROM DatabasePrincipal WHERE UserID = OLD.UserID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'Re-register login mappings before renaming a user';
    END IF;
END //

CREATE TRIGGER trg_UserAccount_Indicator_bu
BEFORE UPDATE ON `UserAccount` FOR EACH ROW
FOLLOWS trg_UserAccount_Provenance_bu
BEGIN
    CALL sp_ValidateIndicator('user_role', NEW.RoleType);
END //

CREATE TRIGGER trg_ServiceAppointment_Provenance_bi
BEFORE INSERT ON `ServiceAppointment` FOR EACH ROW
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`ServiceRequestDescription`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'ServiceAppointment.ServiceRequestDescription cannot be blank'; END IF;
    IF NEW.CreatedByUserID IS NOT NULL AND NOT (NEW.CreatedByUserID <=> v_UserID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52002, MESSAGE_TEXT = 'Creating user must match the responsible actor';
    END IF;
    SET NEW.CreatedByUserID = v_UserID;
    IF NEW.EstimatedDuration > 1440 THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51001, MESSAGE_TEXT = 'Invalid appointment information';
    END IF;
    IF NEW.Status <> 'Scheduled' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54002, MESSAGE_TEXT = 'New appointments must start in Scheduled status';
    END IF;
    IF NEW.CancellationDate IS NOT NULL OR NEW.CancellationReason IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51008, MESSAGE_TEXT = 'Cancellation information belongs to cancellation';
    END IF;
    SET NEW.CreationTimestamp = UTC_TIMESTAMP();
END //

CREATE TRIGGER trg_ServiceAppointment_Indicator_bi
BEFORE INSERT ON `ServiceAppointment` FOR EACH ROW
FOLLOWS trg_ServiceAppointment_Provenance_bi
BEGIN
    CALL sp_ValidateIndicator('appointment_status', NEW.Status);
END //

CREATE TRIGGER trg_Technician_Provenance_bi
BEFORE INSERT ON `Technician` FOR EACH ROW
BEGIN
    IF TRIM(NEW.`Name`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Technician.Name cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Technician_Indicator_bi
BEFORE INSERT ON `Technician` FOR EACH ROW
FOLLOWS trg_Technician_Provenance_bi
BEGIN
    CALL sp_ValidateIndicator('active_status', CAST(NEW.ActiveStatus AS CHAR));
END //

CREATE TRIGGER trg_Technician_Provenance_bu
BEFORE UPDATE ON `Technician` FOR EACH ROW
BEGIN
    IF TRIM(NEW.`Name`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Technician.Name cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Technician_Indicator_bu
BEFORE UPDATE ON `Technician` FOR EACH ROW
FOLLOWS trg_Technician_Provenance_bu
BEGIN
    CALL sp_ValidateIndicator('active_status', CAST(NEW.ActiveStatus AS CHAR));
END //

CREATE TRIGGER trg_Part_Provenance_bi
BEFORE INSERT ON `Part` FOR EACH ROW
BEGIN
    IF TRIM(NEW.`PartNumber`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Part.PartNumber cannot be blank'; END IF;
    IF TRIM(NEW.`PartName`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Part.PartName cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Part_Indicator_bi
BEFORE INSERT ON `Part` FOR EACH ROW
FOLLOWS trg_Part_Provenance_bi
BEGIN
    CALL sp_ValidateIndicator('active_status', CAST(NEW.ActiveStatus AS CHAR));
END //

CREATE TRIGGER trg_Part_Provenance_bu
BEFORE UPDATE ON `Part` FOR EACH ROW
BEGIN
    IF TRIM(NEW.`PartNumber`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Part.PartNumber cannot be blank'; END IF;
    IF TRIM(NEW.`PartName`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Part.PartName cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Part_Indicator_bu
BEFORE UPDATE ON `Part` FOR EACH ROW
FOLLOWS trg_Part_Provenance_bu
BEGIN
    CALL sp_ValidateIndicator('active_status', CAST(NEW.ActiveStatus AS CHAR));
END //

CREATE TRIGGER trg_AuditLog_Indicator_bi
BEFORE INSERT ON `AuditLog` FOR EACH ROW
BEGIN
    CALL sp_ValidateIndicator('audit_action', NEW.Action);
    CALL sp_ValidateIndicator('audit_entity', NEW.AffectedEntity);
END //

CREATE TRIGGER trg_UserRolePolicy_ProfileGuard_bu
BEFORE UPDATE ON UserRolePolicy FOR EACH ROW

BEGIN
    IF EXISTS (SELECT 1 FROM UserAccount WHERE RoleType = OLD.RoleType
               AND ((NEW.RequiresTechnician = 1 AND TechnicianID IS NULL)
                 OR (NEW.RequiresTechnician = 0 AND TechnicianID IS NOT NULL))) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54006, MESSAGE_TEXT = 'Role policy would invalidate existing user profiles';
    END IF;
END //

CREATE TRIGGER trg_Customer_Provenance_bi
BEFORE INSERT ON `Customer` FOR EACH ROW

BEGIN
    IF TRIM(NEW.`Name`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Customer.Name cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Customer_Provenance_bu
BEFORE UPDATE ON `Customer` FOR EACH ROW

BEGIN
    IF TRIM(NEW.`Name`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Customer.Name cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Vehicle_Provenance_bi
BEFORE INSERT ON `Vehicle` FOR EACH ROW

BEGIN
    IF TRIM(NEW.`VIN`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Vehicle.VIN cannot be blank'; END IF;
    IF TRIM(NEW.`Make`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Vehicle.Make cannot be blank'; END IF;
    IF TRIM(NEW.`Model`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Vehicle.Model cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Vehicle_Provenance_bu
BEFORE UPDATE ON `Vehicle` FOR EACH ROW

BEGIN
    IF TRIM(NEW.`VIN`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Vehicle.VIN cannot be blank'; END IF;
    IF TRIM(NEW.`Make`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Vehicle.Make cannot be blank'; END IF;
    IF TRIM(NEW.`Model`) = '' THEN SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51004, MESSAGE_TEXT = 'Vehicle.Model cannot be blank'; END IF;
END //

CREATE TRIGGER trg_PartsUsage_Provenance_bi
BEFORE INSERT ON `PartsUsage` FOR EACH ROW

BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF NOT (NEW.RecordedByUserID <=> v_UserID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52002, MESSAGE_TEXT = 'Recording user must match the responsible actor';
    END IF;
    SET NEW.RecordedDateTime = UTC_TIMESTAMP();
END //

CREATE TRIGGER trg_PartsUsage_Provenance_bu
BEFORE UPDATE ON `PartsUsage` FOR EACH ROW

BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF NOT (OLD.RecordedByUserID <=> NEW.RecordedByUserID)
       OR NOT (OLD.RecordedDateTime <=> NEW.RecordedDateTime)
       OR NOT (OLD.PartsUsageID <=> NEW.PartsUsageID)
       OR NOT (OLD.RepairID <=> NEW.RepairID) OR NOT (OLD.PartID <=> NEW.PartID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52007, MESSAGE_TEXT = 'Parts usage provenance cannot be changed';
    END IF;
END //

CREATE TRIGGER trg_TemporalEvent_InsertGuard BEFORE INSERT ON TemporalEvent FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID()
                   AND SessionAccount = USER() AND EntityType = NEW.EntityType) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'Temporal events require protected history maintenance';
    END IF;
END //

CREATE TRIGGER trg_TemporalEvent_UpdateGuard BEFORE UPDATE ON TemporalEvent FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'Temporal events are immutable';
END //

CREATE TRIGGER trg_TemporalEvent_DeleteGuard BEFORE DELETE ON TemporalEvent FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'Temporal events cannot be deleted';
END //

CREATE TRIGGER `trg_Customer_HistoryGuard_bi` BEFORE INSERT ON `CustomerHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'Customer') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_Customer_HistoryGuard_bu` BEFORE UPDATE ON `CustomerHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'Customer') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_Customer_HistoryGuard_bd` BEFORE DELETE ON `CustomerHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_Customer_History_ai` AFTER INSERT ON `Customer` FOR EACH ROW
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('CustomerID', 'Name', 'Phone', 'Email');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `CustomerHistory` WHERE `CustomerID` = NEW.`CustomerID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('Customer', JSON_OBJECT('CustomerID', NEW.`CustomerID`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `CustomerHistory` (`CustomerID`, `Name`, `Phone`, `Email`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`CustomerID`, NEW.`Name`, NEW.`Phone`, NEW.`Email`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Customer';
END //

CREATE TRIGGER `trg_Customer_History_au` AFTER UPDATE ON `Customer` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('CustomerID', OLD.`CustomerID`, 'Name', OLD.`Name`, 'Phone', OLD.`Phone`, 'Email', OLD.`Email`) AS BINARY) <=> CAST(JSON_OBJECT('CustomerID', NEW.`CustomerID`, 'Name', NEW.`Name`, 'Phone', NEW.`Phone`, 'Email', NEW.`Email`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`CustomerID` AS BINARY) <=> CAST(NEW.`CustomerID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'CustomerID'); END IF;
    IF NOT (CAST(OLD.`Name` AS BINARY) <=> CAST(NEW.`Name` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Name'); END IF;
    IF NOT (CAST(OLD.`Phone` AS BINARY) <=> CAST(NEW.`Phone` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Phone'); END IF;
    IF NOT (CAST(OLD.`Email` AS BINARY) <=> CAST(NEW.`Email` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Email'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `CustomerHistory`
    WHERE `CustomerID` = OLD.`CustomerID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `CustomerHistory` WHERE `CustomerID` = NEW.`CustomerID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('Customer', JSON_OBJECT('CustomerID', NEW.`CustomerID`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `CustomerHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `CustomerHistory` (`CustomerID`, `Name`, `Phone`, `Email`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`CustomerID`, NEW.`Name`, NEW.`Phone`, NEW.`Email`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Customer';
    END IF;
END //

CREATE TRIGGER `trg_Customer_History_ad` AFTER DELETE ON `Customer` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('CustomerID', 'Name', 'Phone', 'Email');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `CustomerHistory`
    WHERE `CustomerID` = OLD.`CustomerID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('Customer', JSON_OBJECT('CustomerID', OLD.`CustomerID`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `CustomerHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Customer';
END //

CREATE TRIGGER `trg_Vehicle_HistoryGuard_bi` BEFORE INSERT ON `VehicleHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'Vehicle') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_Vehicle_HistoryGuard_bu` BEFORE UPDATE ON `VehicleHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'Vehicle') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_Vehicle_HistoryGuard_bd` BEFORE DELETE ON `VehicleHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_Vehicle_History_ai` AFTER INSERT ON `Vehicle` FOR EACH ROW
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('VehicleID', 'CustomerID', 'VIN', 'Make', 'Model', 'Year');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `VehicleHistory` WHERE `VehicleID` = NEW.`VehicleID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('Vehicle', JSON_OBJECT('VehicleID', NEW.`VehicleID`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `VehicleHistory` (`VehicleID`, `CustomerID`, `VIN`, `Make`, `Model`, `Year`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`VehicleID`, NEW.`CustomerID`, NEW.`VIN`, NEW.`Make`, NEW.`Model`, NEW.`Year`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Vehicle';
END //

CREATE TRIGGER `trg_Vehicle_History_au` AFTER UPDATE ON `Vehicle` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('VehicleID', OLD.`VehicleID`, 'CustomerID', OLD.`CustomerID`, 'VIN', OLD.`VIN`, 'Make', OLD.`Make`, 'Model', OLD.`Model`, 'Year', OLD.`Year`) AS BINARY) <=> CAST(JSON_OBJECT('VehicleID', NEW.`VehicleID`, 'CustomerID', NEW.`CustomerID`, 'VIN', NEW.`VIN`, 'Make', NEW.`Make`, 'Model', NEW.`Model`, 'Year', NEW.`Year`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`VehicleID` AS BINARY) <=> CAST(NEW.`VehicleID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'VehicleID'); END IF;
    IF NOT (CAST(OLD.`CustomerID` AS BINARY) <=> CAST(NEW.`CustomerID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'CustomerID'); END IF;
    IF NOT (CAST(OLD.`VIN` AS BINARY) <=> CAST(NEW.`VIN` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'VIN'); END IF;
    IF NOT (CAST(OLD.`Make` AS BINARY) <=> CAST(NEW.`Make` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Make'); END IF;
    IF NOT (CAST(OLD.`Model` AS BINARY) <=> CAST(NEW.`Model` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Model'); END IF;
    IF NOT (CAST(OLD.`Year` AS BINARY) <=> CAST(NEW.`Year` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Year'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `VehicleHistory`
    WHERE `VehicleID` = OLD.`VehicleID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `VehicleHistory` WHERE `VehicleID` = NEW.`VehicleID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('Vehicle', JSON_OBJECT('VehicleID', NEW.`VehicleID`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `VehicleHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `VehicleHistory` (`VehicleID`, `CustomerID`, `VIN`, `Make`, `Model`, `Year`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`VehicleID`, NEW.`CustomerID`, NEW.`VIN`, NEW.`Make`, NEW.`Model`, NEW.`Year`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Vehicle';
    END IF;
END //

CREATE TRIGGER `trg_Vehicle_History_ad` AFTER DELETE ON `Vehicle` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('VehicleID', 'CustomerID', 'VIN', 'Make', 'Model', 'Year');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `VehicleHistory`
    WHERE `VehicleID` = OLD.`VehicleID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('Vehicle', JSON_OBJECT('VehicleID', OLD.`VehicleID`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `VehicleHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Vehicle';
END //

CREATE TRIGGER `trg_Technician_HistoryGuard_bi` BEFORE INSERT ON `TechnicianHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'Technician') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_Technician_HistoryGuard_bu` BEFORE UPDATE ON `TechnicianHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'Technician') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_Technician_HistoryGuard_bd` BEFORE DELETE ON `TechnicianHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_Technician_History_ai` AFTER INSERT ON `Technician` FOR EACH ROW
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('TechnicianID', 'Name', 'Phone', 'Email', 'ActiveStatus');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `TechnicianHistory` WHERE `TechnicianID` = NEW.`TechnicianID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('Technician', JSON_OBJECT('TechnicianID', NEW.`TechnicianID`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `TechnicianHistory` (`TechnicianID`, `Name`, `Phone`, `Email`, `ActiveStatus`, `ActiveIndicator`, `ActiveCode`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`TechnicianID`, NEW.`Name`, NEW.`Phone`, NEW.`Email`, NEW.`ActiveStatus`, NEW.`ActiveIndicator`, NEW.`ActiveCode`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Technician';
END //

CREATE TRIGGER `trg_Technician_History_au` AFTER UPDATE ON `Technician` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('TechnicianID', OLD.`TechnicianID`, 'Name', OLD.`Name`, 'Phone', OLD.`Phone`, 'Email', OLD.`Email`, 'ActiveStatus', OLD.`ActiveStatus`) AS BINARY) <=> CAST(JSON_OBJECT('TechnicianID', NEW.`TechnicianID`, 'Name', NEW.`Name`, 'Phone', NEW.`Phone`, 'Email', NEW.`Email`, 'ActiveStatus', NEW.`ActiveStatus`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`TechnicianID` AS BINARY) <=> CAST(NEW.`TechnicianID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'TechnicianID'); END IF;
    IF NOT (CAST(OLD.`Name` AS BINARY) <=> CAST(NEW.`Name` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Name'); END IF;
    IF NOT (CAST(OLD.`Phone` AS BINARY) <=> CAST(NEW.`Phone` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Phone'); END IF;
    IF NOT (CAST(OLD.`Email` AS BINARY) <=> CAST(NEW.`Email` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Email'); END IF;
    IF NOT (CAST(OLD.`ActiveStatus` AS BINARY) <=> CAST(NEW.`ActiveStatus` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'ActiveStatus'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `TechnicianHistory`
    WHERE `TechnicianID` = OLD.`TechnicianID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `TechnicianHistory` WHERE `TechnicianID` = NEW.`TechnicianID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('Technician', JSON_OBJECT('TechnicianID', NEW.`TechnicianID`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `TechnicianHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `TechnicianHistory` (`TechnicianID`, `Name`, `Phone`, `Email`, `ActiveStatus`, `ActiveIndicator`, `ActiveCode`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`TechnicianID`, NEW.`Name`, NEW.`Phone`, NEW.`Email`, NEW.`ActiveStatus`, NEW.`ActiveIndicator`, NEW.`ActiveCode`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Technician';
    END IF;
END //

CREATE TRIGGER `trg_Technician_History_ad` AFTER DELETE ON `Technician` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('TechnicianID', 'Name', 'Phone', 'Email', 'ActiveStatus');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `TechnicianHistory`
    WHERE `TechnicianID` = OLD.`TechnicianID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('Technician', JSON_OBJECT('TechnicianID', OLD.`TechnicianID`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `TechnicianHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Technician';
END //

CREATE TRIGGER `trg_Part_HistoryGuard_bi` BEFORE INSERT ON `PartHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'Part') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_Part_HistoryGuard_bu` BEFORE UPDATE ON `PartHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'Part') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_Part_HistoryGuard_bd` BEFORE DELETE ON `PartHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_Part_History_ai` AFTER INSERT ON `Part` FOR EACH ROW
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('PartID', 'PartNumber', 'PartName', 'QuantityOnHand', 'UnitCost', 'UnitSellingPrice', 'MinimumInventoryLevel', 'ActiveStatus');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `PartHistory` WHERE `PartID` = NEW.`PartID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('Part', JSON_OBJECT('PartID', NEW.`PartID`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `PartHistory` (`PartID`, `PartNumber`, `PartName`, `QuantityOnHand`, `UnitCost`, `UnitSellingPrice`, `MinimumInventoryLevel`, `ActiveStatus`, `ActiveIndicator`, `ActiveCode`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`PartID`, NEW.`PartNumber`, NEW.`PartName`, NEW.`QuantityOnHand`, NEW.`UnitCost`, NEW.`UnitSellingPrice`, NEW.`MinimumInventoryLevel`, NEW.`ActiveStatus`, NEW.`ActiveIndicator`, NEW.`ActiveCode`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Part';
END //

CREATE TRIGGER `trg_Part_History_ad` AFTER DELETE ON `Part` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('PartID', 'PartNumber', 'PartName', 'QuantityOnHand', 'UnitCost', 'UnitSellingPrice', 'MinimumInventoryLevel', 'ActiveStatus');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `PartHistory`
    WHERE `PartID` = OLD.`PartID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('Part', JSON_OBJECT('PartID', OLD.`PartID`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `PartHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'Part';
END //

CREATE TRIGGER `trg_UserAccount_HistoryGuard_bi` BEFORE INSERT ON `UserAccountHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'UserAccount') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_UserAccount_HistoryGuard_bu` BEFORE UPDATE ON `UserAccountHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'UserAccount') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_UserAccount_HistoryGuard_bd` BEFORE DELETE ON `UserAccountHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_UserAccount_History_ai` AFTER INSERT ON `UserAccount` FOR EACH ROW
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('UserID', 'Username', 'Name', 'RoleType', 'TechnicianID');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `UserAccountHistory` WHERE `UserID` = NEW.`UserID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('UserAccount', JSON_OBJECT('UserID', NEW.`UserID`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `UserAccountHistory` (`UserID`, `Username`, `Name`, `RoleType`, `TechnicianID`, `RoleIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`UserID`, NEW.`Username`, NEW.`Name`, NEW.`RoleType`, NEW.`TechnicianID`, NEW.`RoleIndicator`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'UserAccount';
END //

CREATE TRIGGER `trg_UserAccount_History_au` AFTER UPDATE ON `UserAccount` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('UserID', OLD.`UserID`, 'Username', OLD.`Username`, 'Name', OLD.`Name`, 'RoleType', OLD.`RoleType`, 'TechnicianID', OLD.`TechnicianID`) AS BINARY) <=> CAST(JSON_OBJECT('UserID', NEW.`UserID`, 'Username', NEW.`Username`, 'Name', NEW.`Name`, 'RoleType', NEW.`RoleType`, 'TechnicianID', NEW.`TechnicianID`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`UserID` AS BINARY) <=> CAST(NEW.`UserID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'UserID'); END IF;
    IF NOT (CAST(OLD.`Username` AS BINARY) <=> CAST(NEW.`Username` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Username'); END IF;
    IF NOT (CAST(OLD.`Name` AS BINARY) <=> CAST(NEW.`Name` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Name'); END IF;
    IF NOT (CAST(OLD.`RoleType` AS BINARY) <=> CAST(NEW.`RoleType` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'RoleType'); END IF;
    IF NOT (CAST(OLD.`TechnicianID` AS BINARY) <=> CAST(NEW.`TechnicianID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'TechnicianID'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `UserAccountHistory`
    WHERE `UserID` = OLD.`UserID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `UserAccountHistory` WHERE `UserID` = NEW.`UserID`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('UserAccount', JSON_OBJECT('UserID', NEW.`UserID`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `UserAccountHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `UserAccountHistory` (`UserID`, `Username`, `Name`, `RoleType`, `TechnicianID`, `RoleIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`UserID`, NEW.`Username`, NEW.`Name`, NEW.`RoleType`, NEW.`TechnicianID`, NEW.`RoleIndicator`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'UserAccount';
    END IF;
END //

CREATE TRIGGER `trg_UserAccount_History_ad` AFTER DELETE ON `UserAccount` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('UserID', 'Username', 'Name', 'RoleType', 'TechnicianID');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `UserAccountHistory`
    WHERE `UserID` = OLD.`UserID` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('UserAccount', JSON_OBJECT('UserID', OLD.`UserID`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `UserAccountHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'UserAccount';
END //

CREATE TRIGGER `trg_ServiceAppointment_HistoryGuard_bi` BEFORE INSERT ON `ServiceAppointmentHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'ServiceAppointment') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_ServiceAppointment_HistoryGuard_bu` BEFORE UPDATE ON `ServiceAppointmentHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'ServiceAppointment') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_ServiceAppointment_HistoryGuard_bd` BEFORE DELETE ON `ServiceAppointmentHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_Repair_HistoryGuard_bi` BEFORE INSERT ON `RepairHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'Repair') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_Repair_HistoryGuard_bu` BEFORE UPDATE ON `RepairHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'Repair') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_Repair_HistoryGuard_bd` BEFORE DELETE ON `RepairHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_RepairEstimate_HistoryGuard_bi` BEFORE INSERT ON `RepairEstimateHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'RepairEstimate') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_RepairEstimate_HistoryGuard_bu` BEFORE UPDATE ON `RepairEstimateHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'RepairEstimate') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_RepairEstimate_HistoryGuard_bd` BEFORE DELETE ON `RepairEstimateHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_EstimateLineItem_HistoryGuard_bi` BEFORE INSERT ON `EstimateLineItemHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'EstimateLineItem') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_EstimateLineItem_HistoryGuard_bu` BEFORE UPDATE ON `EstimateLineItemHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'EstimateLineItem') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_EstimateLineItem_HistoryGuard_bd` BEFORE DELETE ON `EstimateLineItemHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_Invoice_HistoryGuard_bi` BEFORE INSERT ON `InvoiceHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'Invoice') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_Invoice_HistoryGuard_bu` BEFORE UPDATE ON `InvoiceHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'Invoice') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_Invoice_HistoryGuard_bd` BEFORE DELETE ON `InvoiceHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_InvoiceLineItem_HistoryGuard_bi` BEFORE INSERT ON `InvoiceLineItemHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'InvoiceLineItem') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_InvoiceLineItem_HistoryGuard_bu` BEFORE UPDATE ON `InvoiceLineItemHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'InvoiceLineItem') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_InvoiceLineItem_HistoryGuard_bd` BEFORE DELETE ON `InvoiceLineItemHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_PartsUsage_HistoryGuard_bi` BEFORE INSERT ON `PartsUsageHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'PartsUsage') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_PartsUsage_HistoryGuard_bu` BEFORE UPDATE ON `PartsUsageHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'PartsUsage') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_PartsUsage_HistoryGuard_bd` BEFORE DELETE ON `PartsUsageHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_IndicatorValue_HistoryGuard_bi` BEFORE INSERT ON `IndicatorValueHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'IndicatorValue') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_IndicatorValue_HistoryGuard_bu` BEFORE UPDATE ON `IndicatorValueHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'IndicatorValue') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_IndicatorValue_HistoryGuard_bd` BEFORE DELETE ON `IndicatorValueHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_IndicatorValue_History_ai` AFTER INSERT ON `IndicatorValue` FOR EACH ROW
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('IndicatorName', 'ValueCode', 'Description', 'DisplayOrder');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `IndicatorValueHistory` WHERE `IndicatorName` = NEW.`IndicatorName` AND `ValueCode` = NEW.`ValueCode`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('IndicatorValue', JSON_OBJECT('IndicatorName', NEW.`IndicatorName`, 'ValueCode', NEW.`ValueCode`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `IndicatorValueHistory` (`IndicatorName`, `ValueCode`, `Description`, `DisplayOrder`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`IndicatorName`, NEW.`ValueCode`, NEW.`Description`, NEW.`DisplayOrder`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'IndicatorValue';
END //

CREATE TRIGGER `trg_IndicatorValue_History_au` AFTER UPDATE ON `IndicatorValue` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('IndicatorName', OLD.`IndicatorName`, 'ValueCode', OLD.`ValueCode`, 'Description', OLD.`Description`, 'DisplayOrder', OLD.`DisplayOrder`) AS BINARY) <=> CAST(JSON_OBJECT('IndicatorName', NEW.`IndicatorName`, 'ValueCode', NEW.`ValueCode`, 'Description', NEW.`Description`, 'DisplayOrder', NEW.`DisplayOrder`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`IndicatorName` AS BINARY) <=> CAST(NEW.`IndicatorName` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'IndicatorName'); END IF;
    IF NOT (CAST(OLD.`ValueCode` AS BINARY) <=> CAST(NEW.`ValueCode` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'ValueCode'); END IF;
    IF NOT (CAST(OLD.`Description` AS BINARY) <=> CAST(NEW.`Description` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'Description'); END IF;
    IF NOT (CAST(OLD.`DisplayOrder` AS BINARY) <=> CAST(NEW.`DisplayOrder` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'DisplayOrder'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `IndicatorValueHistory`
    WHERE `IndicatorName` = OLD.`IndicatorName` AND `ValueCode` = OLD.`ValueCode` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `IndicatorValueHistory` WHERE `IndicatorName` = NEW.`IndicatorName` AND `ValueCode` = NEW.`ValueCode`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('IndicatorValue', JSON_OBJECT('IndicatorName', NEW.`IndicatorName`, 'ValueCode', NEW.`ValueCode`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `IndicatorValueHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `IndicatorValueHistory` (`IndicatorName`, `ValueCode`, `Description`, `DisplayOrder`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`IndicatorName`, NEW.`ValueCode`, NEW.`Description`, NEW.`DisplayOrder`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'IndicatorValue';
    END IF;
END //

CREATE TRIGGER `trg_IndicatorValue_History_ad` AFTER DELETE ON `IndicatorValue` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('IndicatorName', 'ValueCode', 'Description', 'DisplayOrder');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `IndicatorValueHistory`
    WHERE `IndicatorName` = OLD.`IndicatorName` AND `ValueCode` = OLD.`ValueCode` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('IndicatorValue', JSON_OBJECT('IndicatorName', OLD.`IndicatorName`, 'ValueCode', OLD.`ValueCode`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `IndicatorValueHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'IndicatorValue';
END //

CREATE TRIGGER `trg_UserRolePolicy_HistoryGuard_bi` BEFORE INSERT ON `UserRolePolicyHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'UserRolePolicy') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_UserRolePolicy_HistoryGuard_bu` BEFORE UPDATE ON `UserRolePolicyHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'UserRolePolicy') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_UserRolePolicy_HistoryGuard_bd` BEFORE DELETE ON `UserRolePolicyHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_UserRolePolicy_History_ai` AFTER INSERT ON `UserRolePolicy` FOR EACH ROW
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('RoleType', 'RequiresTechnician');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `UserRolePolicyHistory` WHERE `RoleType` = NEW.`RoleType`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('UserRolePolicy', JSON_OBJECT('RoleType', NEW.`RoleType`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `UserRolePolicyHistory` (`RoleType`, `RequiresTechnician`, `RoleIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`RoleType`, NEW.`RequiresTechnician`, NEW.`RoleIndicator`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'UserRolePolicy';
END //

CREATE TRIGGER `trg_UserRolePolicy_History_au` AFTER UPDATE ON `UserRolePolicy` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('RoleType', OLD.`RoleType`, 'RequiresTechnician', OLD.`RequiresTechnician`) AS BINARY) <=> CAST(JSON_OBJECT('RoleType', NEW.`RoleType`, 'RequiresTechnician', NEW.`RequiresTechnician`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`RoleType` AS BINARY) <=> CAST(NEW.`RoleType` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'RoleType'); END IF;
    IF NOT (CAST(OLD.`RequiresTechnician` AS BINARY) <=> CAST(NEW.`RequiresTechnician` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'RequiresTechnician'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `UserRolePolicyHistory`
    WHERE `RoleType` = OLD.`RoleType` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `UserRolePolicyHistory` WHERE `RoleType` = NEW.`RoleType`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('UserRolePolicy', JSON_OBJECT('RoleType', NEW.`RoleType`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `UserRolePolicyHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `UserRolePolicyHistory` (`RoleType`, `RequiresTechnician`, `RoleIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`RoleType`, NEW.`RequiresTechnician`, NEW.`RoleIndicator`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'UserRolePolicy';
    END IF;
END //

CREATE TRIGGER `trg_UserRolePolicy_History_ad` AFTER DELETE ON `UserRolePolicy` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('RoleType', 'RequiresTechnician');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `UserRolePolicyHistory`
    WHERE `RoleType` = OLD.`RoleType` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('UserRolePolicy', JSON_OBJECT('RoleType', OLD.`RoleType`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `UserRolePolicyHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'UserRolePolicy';
END //

CREATE TRIGGER `trg_DatabasePrincipal_HistoryGuard_bi` BEFORE INSERT ON `DatabasePrincipalHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'DatabasePrincipal') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_DatabasePrincipal_HistoryGuard_bu` BEFORE UPDATE ON `DatabasePrincipalHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'DatabasePrincipal') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_DatabasePrincipal_HistoryGuard_bd` BEFORE DELETE ON `DatabasePrincipalHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_DatabasePrincipal_History_ai` AFTER INSERT ON `DatabasePrincipal` FOR EACH ROW
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('SessionAccount', 'PrincipalType', 'UserID');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `DatabasePrincipalHistory` WHERE `SessionAccount` = NEW.`SessionAccount`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('DatabasePrincipal', JSON_OBJECT('SessionAccount', NEW.`SessionAccount`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `DatabasePrincipalHistory` (`SessionAccount`, `PrincipalType`, `UserID`, `TypeIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`SessionAccount`, NEW.`PrincipalType`, NEW.`UserID`, NEW.`TypeIndicator`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'DatabasePrincipal';
END //

CREATE TRIGGER `trg_DatabasePrincipal_History_au` AFTER UPDATE ON `DatabasePrincipal` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('SessionAccount', OLD.`SessionAccount`, 'PrincipalType', OLD.`PrincipalType`, 'UserID', OLD.`UserID`) AS BINARY) <=> CAST(JSON_OBJECT('SessionAccount', NEW.`SessionAccount`, 'PrincipalType', NEW.`PrincipalType`, 'UserID', NEW.`UserID`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`SessionAccount` AS BINARY) <=> CAST(NEW.`SessionAccount` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'SessionAccount'); END IF;
    IF NOT (CAST(OLD.`PrincipalType` AS BINARY) <=> CAST(NEW.`PrincipalType` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'PrincipalType'); END IF;
    IF NOT (CAST(OLD.`UserID` AS BINARY) <=> CAST(NEW.`UserID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'UserID'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `DatabasePrincipalHistory`
    WHERE `SessionAccount` = OLD.`SessionAccount` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `DatabasePrincipalHistory` WHERE `SessionAccount` = NEW.`SessionAccount`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('DatabasePrincipal', JSON_OBJECT('SessionAccount', NEW.`SessionAccount`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `DatabasePrincipalHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `DatabasePrincipalHistory` (`SessionAccount`, `PrincipalType`, `UserID`, `TypeIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`SessionAccount`, NEW.`PrincipalType`, NEW.`UserID`, NEW.`TypeIndicator`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'DatabasePrincipal';
    END IF;
END //

CREATE TRIGGER `trg_DatabasePrincipal_History_ad` AFTER DELETE ON `DatabasePrincipal` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('SessionAccount', 'PrincipalType', 'UserID');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `DatabasePrincipalHistory`
    WHERE `SessionAccount` = OLD.`SessionAccount` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('DatabasePrincipal', JSON_OBJECT('SessionAccount', OLD.`SessionAccount`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `DatabasePrincipalHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'DatabasePrincipal';
END //

CREATE TRIGGER `trg_RoleProcedurePermission_HistoryGuard_bi` BEFORE INSERT ON `RoleProcedurePermissionHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'RoleProcedurePermission') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_RoleProcedurePermission_HistoryGuard_bu` BEFORE UPDATE ON `RoleProcedurePermissionHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'RoleProcedurePermission') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_RoleProcedurePermission_HistoryGuard_bd` BEFORE DELETE ON `RoleProcedurePermissionHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_RoleProcedurePermission_History_ai` AFTER INSERT ON `RoleProcedurePermission` FOR EACH ROW
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('RoleType', 'ProcedureName');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `RoleProcedurePermissionHistory` WHERE `RoleType` = NEW.`RoleType` AND `ProcedureName` = NEW.`ProcedureName`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('RoleProcedurePermission', JSON_OBJECT('RoleType', NEW.`RoleType`, 'ProcedureName', NEW.`ProcedureName`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `RoleProcedurePermissionHistory` (`RoleType`, `ProcedureName`, `RoleIndicator`, `ProcedureIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`RoleType`, NEW.`ProcedureName`, NEW.`RoleIndicator`, NEW.`ProcedureIndicator`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'RoleProcedurePermission';
END //

CREATE TRIGGER `trg_RoleProcedurePermission_History_au` AFTER UPDATE ON `RoleProcedurePermission` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('RoleType', OLD.`RoleType`, 'ProcedureName', OLD.`ProcedureName`) AS BINARY) <=> CAST(JSON_OBJECT('RoleType', NEW.`RoleType`, 'ProcedureName', NEW.`ProcedureName`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`RoleType` AS BINARY) <=> CAST(NEW.`RoleType` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'RoleType'); END IF;
    IF NOT (CAST(OLD.`ProcedureName` AS BINARY) <=> CAST(NEW.`ProcedureName` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'ProcedureName'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `RoleProcedurePermissionHistory`
    WHERE `RoleType` = OLD.`RoleType` AND `ProcedureName` = OLD.`ProcedureName` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `RoleProcedurePermissionHistory` WHERE `RoleType` = NEW.`RoleType` AND `ProcedureName` = NEW.`ProcedureName`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('RoleProcedurePermission', JSON_OBJECT('RoleType', NEW.`RoleType`, 'ProcedureName', NEW.`ProcedureName`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `RoleProcedurePermissionHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `RoleProcedurePermissionHistory` (`RoleType`, `ProcedureName`, `RoleIndicator`, `ProcedureIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`RoleType`, NEW.`ProcedureName`, NEW.`RoleIndicator`, NEW.`ProcedureIndicator`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'RoleProcedurePermission';
    END IF;
END //

CREATE TRIGGER `trg_RoleProcedurePermission_History_ad` AFTER DELETE ON `RoleProcedurePermission` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('RoleType', 'ProcedureName');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `RoleProcedurePermissionHistory`
    WHERE `RoleType` = OLD.`RoleType` AND `ProcedureName` = OLD.`ProcedureName` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('RoleProcedurePermission', JSON_OBJECT('RoleType', OLD.`RoleType`, 'ProcedureName', OLD.`ProcedureName`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `RoleProcedurePermissionHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'RoleProcedurePermission';
END //

CREATE TRIGGER `trg_PrincipalDelegation_HistoryGuard_bi` BEFORE INSERT ON `PrincipalDelegationHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'PrincipalDelegation') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History inserts require protected maintenance';
    END IF;
END //

CREATE TRIGGER `trg_PrincipalDelegation_HistoryGuard_bu` BEFORE UPDATE ON `PrincipalDelegationHistory` FOR EACH ROW

BEGIN
    IF NOT EXISTS (SELECT 1 FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER() AND EntityType = 'PrincipalDelegation') OR OLD.HistoryValidTo IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History versions are immutable outside protected closing';
    END IF;
END //

CREATE TRIGGER `trg_PrincipalDelegation_HistoryGuard_bd` BEFORE DELETE ON `PrincipalDelegationHistory` FOR EACH ROW

BEGIN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52008, MESSAGE_TEXT = 'History records cannot be deleted';
END //

CREATE TRIGGER `trg_PrincipalDelegation_History_ai` AFTER INSERT ON `PrincipalDelegation` FOR EACH ROW
BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('SessionAccount', 'UserID', 'ProcedureName');
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `PrincipalDelegationHistory` WHERE `SessionAccount` = NEW.`SessionAccount` AND `UserID` = NEW.`UserID` AND `ProcedureName` = NEW.`ProcedureName`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('PrincipalDelegation', JSON_OBJECT('SessionAccount', NEW.`SessionAccount`, 'UserID', NEW.`UserID`, 'ProcedureName', NEW.`ProcedureName`), 'Insert', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    INSERT INTO `PrincipalDelegationHistory` (`SessionAccount`, `UserID`, `ProcedureName`, `ProcedureIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`SessionAccount`, NEW.`UserID`, NEW.`ProcedureName`, NEW.`ProcedureIndicator`, v_Version + 1, v_Time, v_Time,
        'Insert', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'PrincipalDelegation';
END //

CREATE TRIGGER `trg_PrincipalDelegation_History_au` AFTER UPDATE ON `PrincipalDelegation` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    IF NOT (CAST(JSON_OBJECT('SessionAccount', OLD.`SessionAccount`, 'UserID', OLD.`UserID`, 'ProcedureName', OLD.`ProcedureName`) AS BINARY) <=> CAST(JSON_OBJECT('SessionAccount', NEW.`SessionAccount`, 'UserID', NEW.`UserID`, 'ProcedureName', NEW.`ProcedureName`) AS BINARY)) THEN
    SET v_Changed = JSON_ARRAY();
    IF NOT (CAST(OLD.`SessionAccount` AS BINARY) <=> CAST(NEW.`SessionAccount` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'SessionAccount'); END IF;
    IF NOT (CAST(OLD.`UserID` AS BINARY) <=> CAST(NEW.`UserID` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'UserID'); END IF;
    IF NOT (CAST(OLD.`ProcedureName` AS BINARY) <=> CAST(NEW.`ProcedureName` AS BINARY)) THEN SET v_Changed = JSON_ARRAY_APPEND(v_Changed, '$', 'ProcedureName'); END IF;
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `PrincipalDelegationHistory`
    WHERE `SessionAccount` = OLD.`SessionAccount` AND `UserID` = OLD.`UserID` AND `ProcedureName` = OLD.`ProcedureName` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    SET v_Version = 0;
    SELECT HistoryVersion, COALESCE(HistoryValidTo, HistoryValidFrom, HistoryRecordedAt)
    INTO v_Version, v_KeyTime FROM `PrincipalDelegationHistory` WHERE `SessionAccount` = NEW.`SessionAccount` AND `UserID` = NEW.`UserID` AND `ProcedureName` = NEW.`ProcedureName`
    ORDER BY HistoryVersion DESC LIMIT 1 FOR UPDATE;
    IF v_KeyTime IS NOT NULL THEN
        SET v_PreviousTime = GREATEST(COALESCE(v_PreviousTime, v_KeyTime), v_KeyTime);
    END IF;
    CALL sp_BeginTemporalEvent('PrincipalDelegation', JSON_OBJECT('SessionAccount', NEW.`SessionAccount`, 'UserID', NEW.`UserID`, 'ProcedureName', NEW.`ProcedureName`), 'Update', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `PrincipalDelegationHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Update'
    WHERE HistoryID = v_Current;
    INSERT INTO `PrincipalDelegationHistory` (`SessionAccount`, `UserID`, `ProcedureName`, `ProcedureIndicator`, HistoryVersion, HistoryValidFrom, HistoryRecordedAt,
        HistoryOrigin, HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason, HistoryStartEventID)
    VALUES (NEW.`SessionAccount`, NEW.`UserID`, NEW.`ProcedureName`, NEW.`ProcedureIndicator`, v_Version + 1, v_Time, v_Time,
        'Update', v_User, USER(), v_Context, NULL, v_Event);
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'PrincipalDelegation';
    END IF;
END //

CREATE TRIGGER `trg_PrincipalDelegation_History_ad` AFTER DELETE ON `PrincipalDelegation` FOR EACH ROW

BEGIN
    DECLARE v_Event BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_User INT;
    DECLARE v_Context CHAR(36);
    DECLARE v_Version BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_Current BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_PreviousTime DATETIME(6) DEFAULT NULL;
    DECLARE v_KeyTime DATETIME(6) DEFAULT NULL;
    DECLARE v_Changed JSON;
    SET v_Changed = JSON_ARRAY('SessionAccount', 'UserID', 'ProcedureName');
    SELECT HistoryID, HistoryVersion, COALESCE(HistoryValidFrom, HistoryRecordedAt)
    INTO v_Current, v_Version, v_PreviousTime FROM `PrincipalDelegationHistory`
    WHERE `SessionAccount` = OLD.`SessionAccount` AND `UserID` = OLD.`UserID` AND `ProcedureName` = OLD.`ProcedureName` AND HistoryIsCurrent = 1 FOR UPDATE;
    IF v_Current IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59001, MESSAGE_TEXT = 'Current temporal history version is missing';
    END IF;
    CALL sp_BeginTemporalEvent('PrincipalDelegation', JSON_OBJECT('SessionAccount', OLD.`SessionAccount`, 'UserID', OLD.`UserID`, 'ProcedureName', OLD.`ProcedureName`), 'Delete', v_Changed, v_PreviousTime, NULL, v_Event, v_Time, v_User, v_Context);
    UPDATE `PrincipalDelegationHistory` SET HistoryValidTo = v_Time, HistoryEndEventID = v_Event,
        HistoryClosedByUserID = v_User, HistoryClosedBySession = USER(),
        HistoryClosedContextID = v_Context, HistoryCloseReason = NULL, HistoryCloseOperation = 'Delete'
    WHERE HistoryID = v_Current;
    DELETE FROM TemporalWriteContext WHERE ConnectionID = CONNECTION_ID() AND EntityType = 'PrincipalDelegation';
END //
DELIMITER ;
