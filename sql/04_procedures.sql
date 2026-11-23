-- Final routines through schema version 006. No upgrade-only helpers.
USE vehicle_service_maintenance;
DELIMITER //

CREATE FUNCTION fn_IndicatorDescription(p_IndicatorName VARCHAR(64), p_Code VARCHAR(100))
RETURNS VARCHAR(255) READS SQL DATA
BEGIN
    RETURN COALESCE((SELECT Description FROM IndicatorValue
                    WHERE IndicatorName = p_IndicatorName AND ValueCode = p_Code),
                    CONCAT('[INVALID: ', COALESCE(p_Code, 'NULL'), ']'));
END //

CREATE PROCEDURE sp_ActorForWrite(OUT p_UserID INT)
BEGIN
    DECLARE v_UserID INT DEFAULT NULL;
    DECLARE v_Procedure VARCHAR(64) DEFAULT NULL;
    SELECT MAX(UserID), MAX(ProcedureName) INTO v_UserID, v_Procedure FROM OperationContext
    WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER();
    CALL sp_ResolveActor(COALESCE(v_UserID, @app_user_id), v_Procedure, p_UserID);
    -- Compatibility hint for the existing role/workflow triggers. The value
    -- has just been authenticated; setting this variable alone grants nothing.
    SET @app_user_id = p_UserID;
END //

CREATE PROCEDURE sp_WriteAuditLog(
    IN p_Action VARCHAR(50), IN p_AffectedEntity VARCHAR(100), IN p_AffectedRecordID INT,
    IN p_PreviousValue JSON, IN p_NewValue JSON
)
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_Context CHAR(36) DEFAULT NULL;
    CALL sp_ActorForWrite(v_UserID);
    SELECT MAX(ContextID) INTO v_Context FROM OperationContext
    WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER();
    INSERT INTO AuditLog (UserID, `Timestamp`, Action, AffectedEntity, AffectedRecordID,
                          PreviousValue, NewValue, ContextID, SessionAccount)
    VALUES (v_UserID, UTC_TIMESTAMP(), p_Action, p_AffectedEntity, p_AffectedRecordID,
            p_PreviousValue, p_NewValue, v_Context, USER());
END //

CREATE PROCEDURE sp_RecordRejectedAttempt(
    IN p_RequestedUserID INT, IN p_Procedure VARCHAR(64), IN p_Entity VARCHAR(100),
    IN p_RecordID INT, IN p_Error TEXT, IN p_Request JSON, IN p_Context CHAR(36)
)
BEGIN
    DECLARE v_UserID INT DEFAULT NULL;
    SET timestamp = 0;
    SELECT MAX(UserID) INTO v_UserID FROM DatabasePrincipal
    WHERE SessionAccount = USER() AND PrincipalType = 'Person';
    IF v_UserID IS NULL AND EXISTS (
        SELECT 1 FROM DatabasePrincipal d JOIN PrincipalDelegation x ON x.SessionAccount = d.SessionAccount
        JOIN UserAccount u ON u.UserID = x.UserID
        JOIN RoleProcedurePermission r ON r.RoleType = u.RoleType AND r.ProcedureName = x.ProcedureName
        WHERE d.SessionAccount = USER() AND d.PrincipalType = 'Service'
          AND x.UserID = p_RequestedUserID AND x.ProcedureName = p_Procedure
    ) THEN SET v_UserID = p_RequestedUserID; END IF;
    INSERT INTO AuditLog (UserID, `Timestamp`, Action, AffectedEntity, AffectedRecordID,
                          NewValue, ContextID, SessionAccount)
    VALUES (v_UserID, UTC_TIMESTAMP(), 'Rejected', p_Entity, p_RecordID,
            JSON_MERGE_PATCH(COALESCE(p_Request, JSON_OBJECT()),
                JSON_OBJECT('Procedure', p_Procedure, 'Error', p_Error, 'RequestedUserID', p_RequestedUserID)),
            COALESCE(p_Context, UUID()), USER());
END //

CREATE PROCEDURE sp_BeginTemporalEvent(
    IN p_Entity VARCHAR(64), IN p_Key JSON, IN p_Operation VARCHAR(10),
    IN p_Changed JSON, IN p_PreviousTime DATETIME(6), IN p_Reason VARCHAR(500),
    OUT p_EventID BIGINT UNSIGNED, OUT p_Time DATETIME(6),
    OUT p_UserID INT, OUT p_Context CHAR(36)
)
BEGIN
    SET timestamp = 0;
    SET p_UserID = NULL;
    SET p_Context = NULL;
    -- Physical maintenance accounts have no on-behalf-of person. Do not use
    -- @app_user_id to manufacture one. Every other account uses migration 004.
    IF USER() NOT IN ('vsm_developer@localhost', 'vsm_admin@localhost') THEN
        CALL sp_ActorForWrite(p_UserID);
        SELECT MAX(ContextID) INTO p_Context FROM OperationContext
        WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER();
    END IF;
    SET p_Time = UTC_TIMESTAMP(6);
    IF p_PreviousTime IS NOT NULL AND p_Time <= p_PreviousTime THEN
        SET p_Time = p_PreviousTime + INTERVAL 1 MICROSECOND;
    END IF;
    INSERT INTO TemporalWriteContext VALUES (CONNECTION_ID(), USER(), p_Entity);
    INSERT INTO TemporalEvent (EntityType, RecordIdentifier, OperationType, ChangedAttributes,
        ResponsibleUserID, SessionAccount, EventTimestamp, ContextID, Reason)
    VALUES (p_Entity, CAST(p_Key AS CHAR CHARACTER SET utf8mb4), p_Operation, p_Changed,
        p_UserID, USER(), p_Time, p_Context, p_Reason);
    SET p_EventID = LAST_INSERT_ID();
END //

CREATE FUNCTION fn_ApplicationErrorID(p_Number INT)
RETURNS VARCHAR(64) DETERMINISTIC NO SQL
BEGIN
    RETURN CASE p_Number
        WHEN 51001 THEN 'VSM_INVALID_APPOINTMENT'
        WHEN 51002 THEN 'VSM_INVALID_INDICATOR'
        WHEN 51003 THEN 'VSM_UNKNOWN_INDICATOR'
        WHEN 51004 THEN 'VSM_REQUIRED_FIELD'
        WHEN 51005 THEN 'VSM_INVALID_PROFILE'
        WHEN 51006 THEN 'VSM_INVALID_PARTS_DOCUMENT'
        WHEN 51007 THEN 'VSM_INVALID_PART_ITEM'
        WHEN 51008 THEN 'VSM_PREMATURE_PROVENANCE'
        WHEN 51009 THEN 'VSM_INVALID_AUDIT_QUERY'
        WHEN 51010 THEN 'VSM_INVENTORY_REASON_REQUIRED'
        WHEN 52001 THEN 'VSM_UNREGISTERED_SESSION'
        WHEN 52002 THEN 'VSM_ACTOR_MISMATCH'
        WHEN 52003 THEN 'VSM_LOGIN_MAPPING_MISMATCH'
        WHEN 52004 THEN 'VSM_DELEGATION_DENIED'
        WHEN 52005 THEN 'VSM_ACTOR_INACTIVE'
        WHEN 52006 THEN 'VSM_OPERATION_DENIED'
        WHEN 52007 THEN 'VSM_PROVENANCE_IMMUTABLE'
        WHEN 52008 THEN 'VSM_HISTORY_WRITE_DENIED'
        WHEN 52009 THEN 'VSM_AUDIT_IMMUTABLE'
        WHEN 52010 THEN 'VSM_COMPLETION_ENTRY_REQUIRED'
        WHEN 53001 THEN 'VSM_REPAIR_NOT_FOUND'
        WHEN 53002 THEN 'VSM_VEHICLE_NOT_FOUND'
        WHEN 53003 THEN 'VSM_TECHNICIAN_NOT_FOUND'
        WHEN 53004 THEN 'VSM_PART_NOT_FOUND'
        WHEN 53005 THEN 'VSM_CUSTOMER_NOT_FOUND'
        WHEN 53006 THEN 'VSM_USER_NOT_FOUND'
        WHEN 54001 THEN 'VSM_SCHEDULE_CONFLICT'
        WHEN 54002 THEN 'VSM_INVALID_TRANSITION'
        WHEN 54003 THEN 'VSM_FINAL_STATE_IMMUTABLE'
        WHEN 54004 THEN 'VSM_INSUFFICIENT_STOCK'
        WHEN 54005 THEN 'VSM_RELATED_STATE_CONFLICT'
        WHEN 54006 THEN 'VSM_ROLE_POLICY_CONFLICT'
        WHEN 54007 THEN 'VSM_FINANCIAL_TOTAL_CONFLICT'
        WHEN 55001 THEN 'VSM_NOTICE'
        WHEN 59001 THEN 'VSM_HISTORY_INCONSISTENT'
        WHEN 59002 THEN 'VSM_PARENT_INCONSISTENT'
        WHEN 59003 THEN 'VSM_PRINCIPAL_INCONSISTENT'
        ELSE NULL END;
END //

CREATE FUNCTION fn_ErrorClass(p_Number INT, p_State CHAR(5), p_IsWarning BOOLEAN)
RETURNS VARCHAR(16) DETERMINISTIC NO SQL
BEGIN
    RETURN CASE
        WHEN p_Number IS NULL AND p_State IS NULL THEN NULL
        WHEN p_Number = 0 AND p_State = '00000' AND NOT COALESCE(p_IsWarning, FALSE) THEN NULL
        WHEN p_IsWarning = TRUE OR LEFT(p_State, 2) = '01' THEN 'warning'
        WHEN p_Number IN (51001, 51002, 51003, 51004, 51005, 51006, 51007, 51008, 51009, 51010) THEN 'validation'
        WHEN p_Number IN (52001, 52002, 52003, 52004, 52005, 52006, 52007, 52008, 52009, 52010) THEN 'forbidden'
        WHEN p_Number IN (53001, 53002, 53003, 53004, 53005, 53006) THEN 'not_found'
        WHEN p_Number IN (54001, 54002, 54003, 54004, 54005, 54006, 54007) THEN 'conflict'
        WHEN p_Number IN (55001) THEN 'warning'
        WHEN p_Number IN (59001, 59002, 59003) THEN 'critical'
        WHEN p_Number IN (1205, 1213) THEN 'retryable'
        WHEN p_Number IN (1044, 1045, 1142, 1143, 1227, 1370, 1698, 3118) THEN 'forbidden'
        WHEN p_Number IN (1062, 1169, 1451) THEN 'conflict'
        WHEN p_Number IN (1048, 1264, 1265, 1292, 1364, 1452, 3140, 3141, 3143, 3146, 3819)
          OR LEFT(p_State, 2) IN ('22', '23') THEN 'validation'
        ELSE 'critical' END;
END //

CREATE FUNCTION fn_ErrorCallerAction(p_Number INT, p_State CHAR(5), p_IsWarning BOOLEAN,
    p_Outcome VARCHAR(16), p_Attempt INT)
RETURNS VARCHAR(32) DETERMINISTIC NO SQL
BEGIN
    DECLARE v_Class VARCHAR(16);
    SET v_Class = fn_ErrorClass(p_Number, p_State, p_IsWarning);
    IF p_Outcome IS NULL OR p_Outcome NOT IN ('rolled_back', 'not_started', 'completed', 'committed') OR LEFT(p_State, 2) = '08'
       OR p_Number IN (2006, 2013, 2055) THEN RETURN 'reconcile_outcome'; END IF;
    IF v_Class = 'warning' AND p_Outcome IN ('completed', 'committed') THEN RETURN 'accept_with_warning'; END IF;
    IF p_Outcome IN ('completed', 'committed') THEN RETURN 'review_completed_result'; END IF;
    IF v_Class = 'retryable' THEN
        IF p_Outcome <> 'rolled_back' THEN RETURN 'confirm_full_rollback'; END IF;
        IF p_Attempt IS NULL OR p_Attempt < 1 THEN RETURN 'review_retry_state'; END IF;
        IF p_Attempt >= 3 THEN RETURN 'stop_retry_budget'; END IF;
        RETURN 'retry_transaction';
    END IF;
    RETURN CASE v_Class WHEN 'validation' THEN 'correct_input' WHEN 'forbidden' THEN 'stop_and_authorize'
        WHEN 'not_found' THEN 'refresh_record' WHEN 'conflict' THEN 'refresh_state' ELSE 'stop_and_report' END;
END //

CREATE PROCEDURE sp_RecordRejectedDiagnostic(
    IN p_RequestedUserID INT, IN p_Procedure VARCHAR(64), IN p_Entity VARCHAR(100),
    IN p_RecordID INT, IN p_Error TEXT, IN p_Request JSON, IN p_Context CHAR(36),
    IN p_ErrorState CHAR(5), IN p_ErrorNumber INT, IN p_Outcome VARCHAR(16)
)
BEGIN
    DECLARE v_UserID INT DEFAULT NULL;
    SET timestamp = 0;
    SELECT MAX(UserID) INTO v_UserID FROM DatabasePrincipal
    WHERE SessionAccount = USER() AND PrincipalType = 'Person';
    IF v_UserID IS NULL AND EXISTS (
        SELECT 1 FROM DatabasePrincipal d JOIN PrincipalDelegation x ON x.SessionAccount = d.SessionAccount
        JOIN UserAccount u ON u.UserID = x.UserID
        JOIN RoleProcedurePermission r ON r.RoleType = u.RoleType AND r.ProcedureName = x.ProcedureName
        WHERE d.SessionAccount = USER() AND d.PrincipalType = 'Service'
          AND x.UserID = p_RequestedUserID AND x.ProcedureName = p_Procedure
    ) THEN SET v_UserID = p_RequestedUserID; END IF;
    INSERT INTO AuditLog (UserID, `Timestamp`, Action, AffectedEntity, AffectedRecordID,
                          NewValue, ContextID, SessionAccount, ApplicationErrorID, ErrorClass, ErrorSQLSTATE, ErrorNumber, ErrorMessage, TransactionOutcome)
    VALUES (v_UserID, UTC_TIMESTAMP(), 'Rejected', p_Entity, p_RecordID,
            JSON_MERGE_PATCH(COALESCE(p_Request, JSON_OBJECT()),
                JSON_OBJECT('Procedure', p_Procedure, 'Error', p_Error, 'RequestedUserID', p_RequestedUserID)),
            COALESCE(p_Context, UUID()), USER(), fn_ApplicationErrorID(p_ErrorNumber),
            fn_ErrorClass(p_ErrorNumber, p_ErrorState, FALSE), p_ErrorState, p_ErrorNumber, p_Error, p_Outcome);
END //

CREATE PROCEDURE sp_ListIndicatorValues(IN p_IndicatorName VARCHAR(64))
READS SQL DATA
BEGIN
    IF p_IndicatorName IS NULL OR NOT EXISTS (
        SELECT 1 FROM IndicatorValue WHERE IndicatorName = p_IndicatorName
    ) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51003, MESSAGE_TEXT = 'Unknown indicator domain';
    END IF;
    SELECT IndicatorName, ValueCode, Description, DisplayOrder
    FROM IndicatorValue WHERE IndicatorName = p_IndicatorName
    ORDER BY DisplayOrder, ValueCode;
END //

CREATE PROCEDURE sp_ValidateIndicator(IN p_IndicatorName VARCHAR(64), IN p_Code VARCHAR(100))
READS SQL DATA
BEGIN
    DECLARE v_Message VARCHAR(128);
    IF p_Code IS NULL OR NOT EXISTS (
        SELECT 1 FROM IndicatorValue WHERE IndicatorName = p_IndicatorName AND ValueCode = p_Code
    ) THEN
        SET v_Message = CONCAT('Invalid indicator value for ', p_IndicatorName);
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51002, MESSAGE_TEXT = v_Message;
    END IF;
END //

CREATE PROCEDURE sp_ResolveActor(IN p_RequestedUserID INT, IN p_ProcedureName VARCHAR(64), OUT p_UserID INT)
READS SQL DATA
BEGIN
    DECLARE v_Type VARCHAR(20);
    -- SET timestamp is caller-writable; restore the real database clock.
    SET timestamp = 0;
    SET p_UserID = NULL;
    SELECT MAX(PrincipalType), MAX(UserID) INTO v_Type, p_UserID
    FROM DatabasePrincipal WHERE SessionAccount = USER();
    IF v_Type IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52001, MESSAGE_TEXT = 'Database session is not a registered principal';
    END IF;
    IF v_Type = 'Person' THEN
        IF p_RequestedUserID IS NOT NULL AND NOT (p_RequestedUserID <=> p_UserID) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52002, MESSAGE_TEXT = 'Acting user must be the logged-in user';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM UserAccount WHERE UserID = p_UserID
                       AND BINARY Username = BINARY SUBSTRING_INDEX(USER(), '@', 1)) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52003, MESSAGE_TEXT = 'Login mapping does not match the person';
        END IF;
    ELSEIF v_Type = 'Service' THEN
        IF p_ProcedureName IS NULL OR p_RequestedUserID IS NULL OR NOT EXISTS (
            SELECT 1 FROM PrincipalDelegation WHERE SessionAccount = USER()
              AND UserID = p_RequestedUserID AND ProcedureName = p_ProcedureName
        ) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52004, MESSAGE_TEXT = 'Service is not authorized to act for this person and operation';
        END IF;
        SET p_UserID = p_RequestedUserID;
    ELSE
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59003, MESSAGE_TEXT = 'Unsupported principal type';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM UserAccount u JOIN UserRolePolicy p ON p.RoleType = u.RoleType
                   LEFT JOIN Technician t ON t.TechnicianID = u.TechnicianID
                   WHERE u.UserID = p_UserID
                     AND ((p.RequiresTechnician = 0 AND u.TechnicianID IS NULL)
                       OR (p.RequiresTechnician = 1 AND t.ActiveStatus = 1))) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52005, MESSAGE_TEXT = 'Responsible actor is invalid or inactive';
    END IF;
    IF p_ProcedureName IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM UserAccount u JOIN RoleProcedurePermission r ON r.RoleType = u.RoleType
        WHERE u.UserID = p_UserID AND r.ProcedureName = p_ProcedureName
    ) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52006, MESSAGE_TEXT = 'Responsible person is not entitled to this operation';
    END IF;
END //

CREATE PROCEDURE sp_CreateServiceAppointment(
    IN p_CustomerID INT,
    IN p_VehicleID INT,
    IN p_TechnicianID INT,
    IN p_CreatedByUserID INT,
    IN p_AppointmentDateTime DATETIME,
    IN p_ServiceRequestDescription VARCHAR(500),
    IN p_EstimatedDuration INT
)
BEGIN
    DECLARE v_Count INT DEFAULT 0;
    DECLARE v_AppointmentID INT;
    DECLARE v_EndDateTime DATETIME;
    DECLARE v_ErrorMessage TEXT DEFAULT NULL;

    DECLARE v_ActorUserID INT;
    DECLARE v_RequestedUserID INT;
    DECLARE v_TransactionStarted BOOLEAN DEFAULT FALSE;
    DECLARE v_CallContext CHAR(36);
    DECLARE v_ErrorState CHAR(5);
    DECLARE v_ErrorNumber INT;
    DECLARE v_ConditionCount INT;
    DECLARE v_ConditionIndex INT;
    DECLARE v_ConditionState CHAR(5);
    DECLARE v_ConditionNumber INT;
    DECLARE v_ConditionMessage TEXT;
    DECLARE v_CommitAttempted BOOLEAN DEFAULT FALSE;
    DECLARE v_RollbackSucceeded BOOLEAN DEFAULT TRUE;
    DECLARE v_Outcome VARCHAR(16) DEFAULT 'unknown';

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET STACKED DIAGNOSTICS v_ConditionCount = NUMBER;
        GET STACKED DIAGNOSTICS CONDITION 1
            v_ErrorState = RETURNED_SQLSTATE, v_ErrorNumber = MYSQL_ERRNO, v_ErrorMessage = MESSAGE_TEXT;
        -- Engine rollback can append HY000 warnings after the actual exception.
        -- Preserve an exception, not a trailing temporary-table rollback notice.
        SET v_ConditionIndex = 1;
        WHILE v_ConditionIndex <= v_ConditionCount DO
            GET STACKED DIAGNOSTICS CONDITION v_ConditionIndex
                v_ConditionState = RETURNED_SQLSTATE, v_ConditionNumber = MYSQL_ERRNO,
                v_ConditionMessage = MESSAGE_TEXT;
            IF LEFT(v_ConditionState, 2) NOT IN ('00', '01', '02')
               AND v_ConditionNumber NOT IN (1196, 1751, 1752) THEN
                SET v_ErrorState = v_ConditionState, v_ErrorNumber = v_ConditionNumber,
                    v_ErrorMessage = v_ConditionMessage;
            END IF;
            SET v_ConditionIndex = v_ConditionIndex + 1;
        END WHILE;
        IF v_TransactionStarted THEN
            BEGIN
                DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_RollbackSucceeded = FALSE;
                ROLLBACK;
            END;
            IF v_RollbackSucceeded AND NOT v_CommitAttempted THEN SET v_Outcome = 'rolled_back'; END IF;
        ELSE
            SET v_Outcome = 'not_started';
        END IF;
        BEGIN
            DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
            
        END;
        -- Never let logger/cleanup failures replace the original diagnostics.
        -- A failed rollback must not be followed by a commit of partial work.
        IF v_RollbackSucceeded THEN
            BEGIN
                DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
                CALL sp_RecordRejectedDiagnostic(v_RequestedUserID, 'sp_CreateServiceAppointment', 'ServiceAppointment',
                    NULL, v_ErrorMessage, JSON_OBJECT('CustomerID', p_CustomerID, 'VehicleID', p_VehicleID, 'TechnicianID', p_TechnicianID, 'AppointmentDateTime', p_AppointmentDateTime), v_CallContext, v_ErrorState, v_ErrorNumber, v_Outcome);
                IF v_TransactionStarted THEN COMMIT; END IF;
            END;
        END IF;
        SET @app_user_id = NULL;
        SET @adj_reason = NULL;
        SET @context_id = NULL;
        RESIGNAL;
    END;

    SET v_RequestedUserID = p_CreatedByUserID;
    SET v_CallContext = UUID();
    CALL sp_ResolveActor(p_CreatedByUserID, 'sp_CreateServiceAppointment', v_ActorUserID);
    SET p_CreatedByUserID = v_ActorUserID;
    START TRANSACTION;
    SET v_TransactionStarted = TRUE;
    SET @app_user_id = v_ActorUserID;
    INSERT INTO OperationContext (ConnectionID, SessionAccount, UserID, ProcedureName, ContextID)
    VALUES (CONNECTION_ID(), USER(), v_ActorUserID, 'sp_CreateServiceAppointment', v_CallContext);

    -- one ID shared by every audit row written by the triggers during this procedure call
    SET @context_id = v_CallContext;

    -- Validate required appointment information
    IF p_AppointmentDateTime IS NULL
       OR p_AppointmentDateTime <= NOW()
       OR p_EstimatedDuration IS NULL
       OR p_EstimatedDuration <= 0
       OR p_EstimatedDuration > 1440 
       OR p_ServiceRequestDescription IS NULL
       OR TRIM(p_ServiceRequestDescription) = '' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51001, MESSAGE_TEXT = 'Invalid appointment information';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM Customer WHERE CustomerID = p_CustomerID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 53005, MESSAGE_TEXT = 'Customer does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Vehicle WHERE VehicleID = p_VehicleID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 53002, MESSAGE_TEXT = 'Vehicle does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Technician WHERE TechnicianID = p_TechnicianID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 53003, MESSAGE_TEXT = 'Technician does not exist';
    END IF;

    -- Check that the creating user exists
    SELECT COUNT(*)
    INTO v_Count
    FROM UserAccount
    WHERE UserID = p_CreatedByUserID;

    IF v_Count = 0 THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 53006, MESSAGE_TEXT = 'Creating user does not exist';
    END IF;

    -- Audit triggers read the acting user from this variable
    SET @app_user_id = p_CreatedByUserID;

    -- Check that the vehicle belongs to the customer (lock the vehicle row)
    SELECT COUNT(*)
    INTO v_Count
    FROM Vehicle
    WHERE VehicleID = p_VehicleID
      AND CustomerID = p_CustomerID
    FOR UPDATE;

    IF v_Count = 0 THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51001, MESSAGE_TEXT = 'Vehicle does not belong to the customer';
    END IF;

    -- Check that the technician is active (lock the technician row so
    -- concurrent bookings for the same technician are serialized)
    SELECT COUNT(*)
    INTO v_Count
    FROM Technician
    WHERE TechnicianID = p_TechnicianID
      AND ActiveStatus = 1
    FOR UPDATE;

    IF v_Count = 0 THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54005, MESSAGE_TEXT = 'Technician does not exist or is inactive';
    END IF;

    SET v_EndDateTime = DATE_ADD(
        p_AppointmentDateTime,
        INTERVAL p_EstimatedDuration MINUTE
    );

    -- Check for overlapping active appointments for the same vehicle
    -- (locking read so it sees the latest committed appointments)
    SELECT COUNT(*)
    INTO v_Count
    FROM ServiceAppointment
    WHERE VehicleID = p_VehicleID
      AND Status IN ('Scheduled', 'Checked In', 'In Progress')
      AND AppointmentDateTime < v_EndDateTime
      AND DATE_ADD(AppointmentDateTime, INTERVAL EstimatedDuration MINUTE)
          > p_AppointmentDateTime
    FOR UPDATE;

    IF v_Count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54001, MESSAGE_TEXT = 'Vehicle already has a conflicting appointment';
    END IF;

    -- Check for overlapping active appointments for the technician
    SELECT COUNT(*)
    INTO v_Count
    FROM ServiceAppointment
    WHERE TechnicianID = p_TechnicianID
      AND Status IN ('Scheduled', 'Checked In', 'In Progress')
      AND AppointmentDateTime < v_EndDateTime
      AND DATE_ADD(AppointmentDateTime, INTERVAL EstimatedDuration MINUTE)
          > p_AppointmentDateTime
    FOR UPDATE;

    IF v_Count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54001, MESSAGE_TEXT = 'Technician already has a conflicting appointment';
    END IF;

    -- Create the service appointment
    INSERT INTO ServiceAppointment (
        VehicleID,
        TechnicianID,
        CreatedByUserID,
        AppointmentDateTime,
        Status,
        ServiceRequestDescription,
        EstimatedDuration,
        CreationTimestamp
    )
    VALUES (
        p_VehicleID,
        p_TechnicianID,
        p_CreatedByUserID,
        p_AppointmentDateTime,
        'Scheduled',
        p_ServiceRequestDescription,
        p_EstimatedDuration,
        NOW()
    );

    SET v_AppointmentID = LAST_INSERT_ID();

    DELETE FROM OperationContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER();
    SET v_CommitAttempted = TRUE;
    COMMIT;
    SET @app_user_id = NULL;
    SET @context_id = NULL;

    SELECT v_AppointmentID AS AppointmentID;
END //

CREATE PROCEDURE sp_CompleteRepair(
    IN p_RepairID INT,
    IN p_TechnicianID INT,
    IN p_RecordedByUserID INT,
    IN p_Parts JSON
)
BEGIN
    DECLARE v_Count INT DEFAULT 0;
    DECLARE v_PartCount INT DEFAULT 0;
    DECLARE v_AppointmentID INT DEFAULT NULL;
    DECLARE v_RepairStatus VARCHAR(20);
    DECLARE v_AppointmentStatus VARCHAR(20);
    DECLARE v_AssignedTechnicianID INT;
    DECLARE v_ErrorMessage TEXT DEFAULT NULL;

    DECLARE v_ActorUserID INT;
    DECLARE v_RequestedUserID INT;
    DECLARE v_TransactionStarted BOOLEAN DEFAULT FALSE;
    DECLARE v_CallContext CHAR(36);
    DECLARE v_ErrorState CHAR(5);
    DECLARE v_ErrorNumber INT;
    DECLARE v_ConditionCount INT;
    DECLARE v_ConditionIndex INT;
    DECLARE v_ConditionState CHAR(5);
    DECLARE v_ConditionNumber INT;
    DECLARE v_ConditionMessage TEXT;
    DECLARE v_CommitAttempted BOOLEAN DEFAULT FALSE;
    DECLARE v_RollbackSucceeded BOOLEAN DEFAULT TRUE;
    DECLARE v_Outcome VARCHAR(16) DEFAULT 'unknown';

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET STACKED DIAGNOSTICS v_ConditionCount = NUMBER;
        GET STACKED DIAGNOSTICS CONDITION 1
            v_ErrorState = RETURNED_SQLSTATE, v_ErrorNumber = MYSQL_ERRNO, v_ErrorMessage = MESSAGE_TEXT;
        -- Engine rollback can append HY000 warnings after the actual exception.
        -- Preserve an exception, not a trailing temporary-table rollback notice.
        SET v_ConditionIndex = 1;
        WHILE v_ConditionIndex <= v_ConditionCount DO
            GET STACKED DIAGNOSTICS CONDITION v_ConditionIndex
                v_ConditionState = RETURNED_SQLSTATE, v_ConditionNumber = MYSQL_ERRNO,
                v_ConditionMessage = MESSAGE_TEXT;
            IF LEFT(v_ConditionState, 2) NOT IN ('00', '01', '02')
               AND v_ConditionNumber NOT IN (1196, 1751, 1752) THEN
                SET v_ErrorState = v_ConditionState, v_ErrorNumber = v_ConditionNumber,
                    v_ErrorMessage = v_ConditionMessage;
            END IF;
            SET v_ConditionIndex = v_ConditionIndex + 1;
        END WHILE;
        IF v_TransactionStarted THEN
            BEGIN
                DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_RollbackSucceeded = FALSE;
                ROLLBACK;
            END;
            IF v_RollbackSucceeded AND NOT v_CommitAttempted THEN SET v_Outcome = 'rolled_back'; END IF;
        ELSE
            SET v_Outcome = 'not_started';
        END IF;
        BEGIN
            DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
            DROP TEMPORARY TABLE IF EXISTS tmp_RepairParts;
        END;
        -- Never let logger/cleanup failures replace the original diagnostics.
        -- A failed rollback must not be followed by a commit of partial work.
        IF v_RollbackSucceeded THEN
            BEGIN
                DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
                CALL sp_RecordRejectedDiagnostic(v_RequestedUserID, 'sp_CompleteRepair', 'Repair',
                    p_RepairID, v_ErrorMessage, JSON_OBJECT('TechnicianID', p_TechnicianID, 'Parts', p_Parts), v_CallContext, v_ErrorState, v_ErrorNumber, v_Outcome);
                IF v_TransactionStarted THEN COMMIT; END IF;
            END;
        END IF;
        SET @app_user_id = NULL;
        SET @adj_reason = NULL;
        SET @context_id = NULL;
        RESIGNAL;
    END;

    SET v_RequestedUserID = p_RecordedByUserID;
    SET v_CallContext = UUID();
    CALL sp_ResolveActor(p_RecordedByUserID, 'sp_CompleteRepair', v_ActorUserID);
    SET p_RecordedByUserID = v_ActorUserID;
    START TRANSACTION;
    SET v_TransactionStarted = TRUE;
    SET @app_user_id = v_ActorUserID;
    INSERT INTO OperationContext (ConnectionID, SessionAccount, UserID, ProcedureName, ContextID)
    VALUES (CONNECTION_ID(), USER(), v_ActorUserID, 'sp_CompleteRepair', v_CallContext);

    SET @context_id = v_CallContext;

    -- Lock the repair and check that it exists
    SELECT AppointmentID, Status
    INTO v_AppointmentID, v_RepairStatus
    FROM Repair
    WHERE RepairID = p_RepairID
    FOR UPDATE;

    IF v_AppointmentID IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 53001, MESSAGE_TEXT = 'Repair does not exist';
    END IF;

    -- FRD: only an In Progress repair can be completed
    IF v_RepairStatus <> 'In Progress' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54005, MESSAGE_TEXT = 'Repair must be In Progress to be completed';
    END IF;

    -- Lock the appointment and check its status and assigned technician
    SELECT Status, TechnicianID
    INTO v_AppointmentStatus, v_AssignedTechnicianID
    FROM ServiceAppointment
    WHERE AppointmentID = v_AppointmentID
    FOR UPDATE;

    IF v_AppointmentStatus IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 59002, MESSAGE_TEXT = 'Appointment for this repair does not exist';
    END IF;

    -- Work can only be completed while the vehicle is in the shop: the
    -- appointment must be In Progress (not Scheduled, Checked In, or closed)
    IF v_AppointmentStatus <> 'In Progress' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54005, MESSAGE_TEXT = 'Appointment must be In Progress to complete a repair';
    END IF;

        IF p_TechnicianID IS NULL OR NOT (v_AssignedTechnicianID <=> p_TechnicianID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52006, MESSAGE_TEXT = 'Technician is not assigned to this appointment';
    END IF;

    -- Recording user must be the assigned technician's own account, or a Manager
    SELECT COUNT(*)
    INTO v_Count
    FROM UserAccount
    WHERE UserID = p_RecordedByUserID
      AND (RoleType = 'Manager'
           OR (RoleType = 'Technician' AND TechnicianID = p_TechnicianID));

    IF v_Count = 0 THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 52006, MESSAGE_TEXT = 'Recording user is not authorized to complete this repair';
    END IF;

    -- Audit triggers read these variables
    SET @app_user_id = p_RecordedByUserID;
    SET @adj_reason = CONCAT('Parts usage for repair ', p_RepairID);

    -- Reject any non-array JSON, including {}
    IF p_Parts IS NOT NULL AND JSON_TYPE(p_Parts) <> 'ARRAY' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51006, MESSAGE_TEXT = 'Parts must be a JSON array';
    END IF;

    -- Record parts usage if any parts were provided
    IF p_Parts IS NOT NULL AND JSON_LENGTH(p_Parts) > 0 THEN

        -- Validate every entry BEFORE combining duplicates:
        -- missing, null, non-numeric, zero, or negative values are rejected
        IF EXISTS (
            SELECT 1
            FROM JSON_TABLE(p_Parts, '$[*]' COLUMNS (
                     PartIDRaw JSON PATH '$.partId',
                     QtyRaw    JSON PATH '$.qty')) AS jt
            WHERE jt.PartIDRaw IS NULL
               OR jt.QtyRaw IS NULL
               OR JSON_TYPE(jt.PartIDRaw) <> 'INTEGER'
               OR JSON_TYPE(jt.QtyRaw) <> 'INTEGER'
               OR CAST(jt.QtyRaw AS SIGNED) <= 0
        ) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51007, MESSAGE_TEXT = 'Each part needs an integer partId and a positive integer qty';
        END IF;

        -- All entries are valid; combine duplicate PartIDs into one row
        DROP TEMPORARY TABLE IF EXISTS tmp_RepairParts;
        CREATE TEMPORARY TABLE tmp_RepairParts AS
        SELECT jt.PartID, SUM(jt.Qty) AS Qty
        FROM JSON_TABLE(p_Parts, '$[*]' COLUMNS (
                 PartID INT PATH '$.partId',
                 Qty    INT PATH '$.qty')) AS jt
        GROUP BY jt.PartID;

        SELECT COUNT(*) INTO v_PartCount FROM tmp_RepairParts;

        IF EXISTS (SELECT 1 FROM tmp_RepairParts t LEFT JOIN Part p ON p.PartID = t.PartID WHERE p.PartID IS NULL) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 53004, MESSAGE_TEXT = 'Part does not exist';
        END IF;
        -- Lock every requested part; all must exist and be active
        SELECT COUNT(*)
        INTO v_Count
        FROM Part p
        JOIN tmp_RepairParts t ON t.PartID = p.PartID
        WHERE p.ActiveStatus = 1
        FOR UPDATE OF p;

        IF v_Count <> v_PartCount THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54005, MESSAGE_TEXT = 'A part does not exist or is inactive';
        END IF;

        -- Check inventory for every part before changing anything
        -- (locking read so it sees the latest committed quantities)
        SELECT COUNT(*)
        INTO v_Count
        FROM Part p
        JOIN tmp_RepairParts t ON t.PartID = p.PartID
        WHERE p.QuantityOnHand < t.Qty
        FOR UPDATE OF p;

        IF v_Count > 0 THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 54004, MESSAGE_TEXT = 'Insufficient parts inventory';
        END IF;

        -- Record all parts, capturing the current price and cost
        INSERT INTO PartsUsage (
            RepairID,
            PartID,
            RecordedByUserID,
            QuantityUsed,
            UnitSellingPriceAtTimeOfUse,
            UnitCostAtTimeOfUse,
            RecordedDateTime
        )
        SELECT p_RepairID, p.PartID, p_RecordedByUserID, t.Qty,
               p.UnitSellingPrice, p.UnitCost, NOW()
        FROM Part p
        JOIN tmp_RepairParts t ON t.PartID = p.PartID;

        -- Reduce inventory for all parts
        UPDATE Part p
        JOIN tmp_RepairParts t ON t.PartID = p.PartID
        SET p.QuantityOnHand = p.QuantityOnHand - t.Qty;

        DROP TEMPORARY TABLE tmp_RepairParts;
    END IF;

    -- Mark the repair as completed
    UPDATE Repair
    SET Status = 'Completed',
        CompletedByTechnicianID = p_TechnicianID,
        CompletionDateTime = NOW()
    WHERE RepairID = p_RepairID;

    DELETE FROM OperationContext WHERE ConnectionID = CONNECTION_ID() AND SessionAccount = USER();
    SET v_CommitAttempted = TRUE;
    COMMIT;
    SET @app_user_id = NULL;
    SET @adj_reason = NULL;
    SET @context_id = NULL;

    SELECT p_RepairID AS CompletedRepairID;
END //

CREATE PROCEDURE sp_ListAuditTrail(
    IN p_Entity VARCHAR(64), IN p_RecordIdentifier JSON, IN p_UserID INT,
    IN p_From DATETIME(6), IN p_To DATETIME(6),
    IN p_BeforeEventID BIGINT UNSIGNED, IN p_Limit INT
)
READS SQL DATA
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        BEGIN
            DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
            DROP TEMPORARY TABLE IF EXISTS tmp_TemporalPage, tmp_TemporalPageIDs;
        END;
        RESIGNAL;
    END;
    IF p_Limit IS NULL OR p_Limit < 1 OR p_Limit > 200
       OR (p_From IS NOT NULL AND p_To IS NOT NULL AND p_From >= p_To) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51009, MESSAGE_TEXT = 'Invalid audit page size or date range';
    END IF;
    IF p_Entity IS NOT NULL AND p_Entity NOT IN ('Customer', 'Vehicle', 'Technician', 'Part', 'UserAccount', 'ServiceAppointment', 'Repair', 'RepairEstimate', 'EstimateLineItem', 'Invoice', 'InvoiceLineItem', 'PartsUsage', 'IndicatorValue', 'UserRolePolicy', 'DatabasePrincipal', 'RoleProcedurePermission', 'PrincipalDelegation') THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 51009, MESSAGE_TEXT = 'Unknown temporal audit entity';
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_TemporalPage, tmp_TemporalPageIDs;
    CREATE TEMPORARY TABLE tmp_TemporalPageIDs (EventID BIGINT UNSIGNED PRIMARY KEY) ENGINE=InnoDB;
    INSERT INTO tmp_TemporalPageIDs
    SELECT EventID FROM TemporalEvent
    WHERE (p_Entity IS NULL OR EntityType = p_Entity)
      AND (p_RecordIdentifier IS NULL OR
          (RecordHash = UNHEX(SHA2(CAST(p_RecordIdentifier AS CHAR CHARACTER SET utf8mb4), 256))
           AND RecordIdentifier = CAST(p_RecordIdentifier AS CHAR CHARACTER SET utf8mb4)))
      AND (p_UserID IS NULL OR ResponsibleUserID = p_UserID)
      AND (p_From IS NULL OR EventTimestamp >= p_From)
      AND (p_To IS NULL OR EventTimestamp < p_To)
      AND (p_BeforeEventID IS NULL OR EventID < p_BeforeEventID)
    ORDER BY EventID DESC LIMIT p_Limit;
    CREATE TEMPORARY TABLE tmp_TemporalPage AS SELECT * FROM vw_AuditTrail WHERE FALSE;

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('CustomerID', old.`CustomerID`, 'Name', old.`Name`, 'Phone', old.`Phone`, 'Email', old.`Email`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('CustomerID', new.`CustomerID`, 'Name', new.`Name`, 'Phone', new.`Phone`, 'Email', new.`Email`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `CustomerHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `CustomerHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'Customer';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('VehicleID', old.`VehicleID`, 'CustomerID', old.`CustomerID`, 'VIN', old.`VIN`, 'Make', old.`Make`, 'Model', old.`Model`, 'Year', old.`Year`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('VehicleID', new.`VehicleID`, 'CustomerID', new.`CustomerID`, 'VIN', new.`VIN`, 'Make', new.`Make`, 'Model', new.`Model`, 'Year', new.`Year`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `VehicleHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `VehicleHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'Vehicle';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('TechnicianID', old.`TechnicianID`, 'Name', old.`Name`, 'Phone', old.`Phone`, 'Email', old.`Email`, 'ActiveStatus', old.`ActiveStatus`, 'ActiveIndicator', old.`ActiveIndicator`, 'ActiveCode', old.`ActiveCode`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('TechnicianID', new.`TechnicianID`, 'Name', new.`Name`, 'Phone', new.`Phone`, 'Email', new.`Email`, 'ActiveStatus', new.`ActiveStatus`, 'ActiveIndicator', new.`ActiveIndicator`, 'ActiveCode', new.`ActiveCode`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `TechnicianHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `TechnicianHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'Technician';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('PartID', old.`PartID`, 'PartNumber', old.`PartNumber`, 'PartName', old.`PartName`, 'QuantityOnHand', old.`QuantityOnHand`, 'UnitCost', old.`UnitCost`, 'UnitSellingPrice', old.`UnitSellingPrice`, 'MinimumInventoryLevel', old.`MinimumInventoryLevel`, 'ActiveStatus', old.`ActiveStatus`, 'ActiveIndicator', old.`ActiveIndicator`, 'ActiveCode', old.`ActiveCode`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('PartID', new.`PartID`, 'PartNumber', new.`PartNumber`, 'PartName', new.`PartName`, 'QuantityOnHand', new.`QuantityOnHand`, 'UnitCost', new.`UnitCost`, 'UnitSellingPrice', new.`UnitSellingPrice`, 'MinimumInventoryLevel', new.`MinimumInventoryLevel`, 'ActiveStatus', new.`ActiveStatus`, 'ActiveIndicator', new.`ActiveIndicator`, 'ActiveCode', new.`ActiveCode`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `PartHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `PartHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'Part';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('UserID', old.`UserID`, 'Username', old.`Username`, 'Name', old.`Name`, 'RoleType', old.`RoleType`, 'TechnicianID', old.`TechnicianID`, 'RoleIndicator', old.`RoleIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('UserID', new.`UserID`, 'Username', new.`Username`, 'Name', new.`Name`, 'RoleType', new.`RoleType`, 'TechnicianID', new.`TechnicianID`, 'RoleIndicator', new.`RoleIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `UserAccountHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `UserAccountHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'UserAccount';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('AppointmentID', old.`AppointmentID`, 'VehicleID', old.`VehicleID`, 'TechnicianID', old.`TechnicianID`, 'CreatedByUserID', old.`CreatedByUserID`, 'AppointmentDateTime', old.`AppointmentDateTime`, 'Status', old.`Status`, 'ServiceRequestDescription', old.`ServiceRequestDescription`, 'EstimatedDuration', old.`EstimatedDuration`, 'CreationTimestamp', old.`CreationTimestamp`, 'CancellationDate', old.`CancellationDate`, 'CancellationReason', old.`CancellationReason`, 'StatusIndicator', old.`StatusIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('AppointmentID', new.`AppointmentID`, 'VehicleID', new.`VehicleID`, 'TechnicianID', new.`TechnicianID`, 'CreatedByUserID', new.`CreatedByUserID`, 'AppointmentDateTime', new.`AppointmentDateTime`, 'Status', new.`Status`, 'ServiceRequestDescription', new.`ServiceRequestDescription`, 'EstimatedDuration', new.`EstimatedDuration`, 'CreationTimestamp', new.`CreationTimestamp`, 'CancellationDate', new.`CancellationDate`, 'CancellationReason', new.`CancellationReason`, 'StatusIndicator', new.`StatusIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `ServiceAppointmentHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `ServiceAppointmentHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'ServiceAppointment';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('RepairID', old.`RepairID`, 'AppointmentID', old.`AppointmentID`, 'CompletedByTechnicianID', old.`CompletedByTechnicianID`, 'RepairDateTime', old.`RepairDateTime`, 'RepairType', old.`RepairType`, 'RepairDescription', old.`RepairDescription`, 'LaborHours', old.`LaborHours`, 'Status', old.`Status`, 'CompletionDateTime', old.`CompletionDateTime`, 'StatusIndicator', old.`StatusIndicator`, 'TypeIndicator', old.`TypeIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('RepairID', new.`RepairID`, 'AppointmentID', new.`AppointmentID`, 'CompletedByTechnicianID', new.`CompletedByTechnicianID`, 'RepairDateTime', new.`RepairDateTime`, 'RepairType', new.`RepairType`, 'RepairDescription', new.`RepairDescription`, 'LaborHours', new.`LaborHours`, 'Status', new.`Status`, 'CompletionDateTime', new.`CompletionDateTime`, 'StatusIndicator', new.`StatusIndicator`, 'TypeIndicator', new.`TypeIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `RepairHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `RepairHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'Repair';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('EstimateID', old.`EstimateID`, 'AppointmentID', old.`AppointmentID`, 'CreatedByUserID', old.`CreatedByUserID`, 'ApprovedByUserID', old.`ApprovedByUserID`, 'EstimateDate', old.`EstimateDate`, 'Status', old.`Status`, 'TotalAmount', old.`TotalAmount`, 'ApprovalDateTime', old.`ApprovalDateTime`, 'StatusIndicator', old.`StatusIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('EstimateID', new.`EstimateID`, 'AppointmentID', new.`AppointmentID`, 'CreatedByUserID', new.`CreatedByUserID`, 'ApprovedByUserID', new.`ApprovedByUserID`, 'EstimateDate', new.`EstimateDate`, 'Status', new.`Status`, 'TotalAmount', new.`TotalAmount`, 'ApprovalDateTime', new.`ApprovalDateTime`, 'StatusIndicator', new.`StatusIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `RepairEstimateHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `RepairEstimateHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'RepairEstimate';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('EstimateID', old.`EstimateID`, 'LineNumber', old.`LineNumber`, 'Description', old.`Description`, 'Quantity', old.`Quantity`, 'UnitPrice', old.`UnitPrice`, 'LineTotal', old.`LineTotal`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('EstimateID', new.`EstimateID`, 'LineNumber', new.`LineNumber`, 'Description', new.`Description`, 'Quantity', new.`Quantity`, 'UnitPrice', new.`UnitPrice`, 'LineTotal', new.`LineTotal`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `EstimateLineItemHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `EstimateLineItemHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'EstimateLineItem';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('InvoiceID', old.`InvoiceID`, 'AppointmentID', old.`AppointmentID`, 'CreatedByUserID', old.`CreatedByUserID`, 'FinalizedByUserID', old.`FinalizedByUserID`, 'InvoiceDate', old.`InvoiceDate`, 'Status', old.`Status`, 'TotalAmount', old.`TotalAmount`, 'FinalizationDateTime', old.`FinalizationDateTime`, 'StatusIndicator', old.`StatusIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('InvoiceID', new.`InvoiceID`, 'AppointmentID', new.`AppointmentID`, 'CreatedByUserID', new.`CreatedByUserID`, 'FinalizedByUserID', new.`FinalizedByUserID`, 'InvoiceDate', new.`InvoiceDate`, 'Status', new.`Status`, 'TotalAmount', new.`TotalAmount`, 'FinalizationDateTime', new.`FinalizationDateTime`, 'StatusIndicator', new.`StatusIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `InvoiceHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `InvoiceHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'Invoice';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('InvoiceLineItemID', old.`InvoiceLineItemID`, 'InvoiceID', old.`InvoiceID`, 'Description', old.`Description`, 'Quantity', old.`Quantity`, 'UnitPrice', old.`UnitPrice`, 'LineTotal', old.`LineTotal`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('InvoiceLineItemID', new.`InvoiceLineItemID`, 'InvoiceID', new.`InvoiceID`, 'Description', new.`Description`, 'Quantity', new.`Quantity`, 'UnitPrice', new.`UnitPrice`, 'LineTotal', new.`LineTotal`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `InvoiceLineItemHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `InvoiceLineItemHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'InvoiceLineItem';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('PartsUsageID', old.`PartsUsageID`, 'RepairID', old.`RepairID`, 'PartID', old.`PartID`, 'RecordedByUserID', old.`RecordedByUserID`, 'QuantityUsed', old.`QuantityUsed`, 'UnitSellingPriceAtTimeOfUse', old.`UnitSellingPriceAtTimeOfUse`, 'UnitCostAtTimeOfUse', old.`UnitCostAtTimeOfUse`, 'RecordedDateTime', old.`RecordedDateTime`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('PartsUsageID', new.`PartsUsageID`, 'RepairID', new.`RepairID`, 'PartID', new.`PartID`, 'RecordedByUserID', new.`RecordedByUserID`, 'QuantityUsed', new.`QuantityUsed`, 'UnitSellingPriceAtTimeOfUse', new.`UnitSellingPriceAtTimeOfUse`, 'UnitCostAtTimeOfUse', new.`UnitCostAtTimeOfUse`, 'RecordedDateTime', new.`RecordedDateTime`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `PartsUsageHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `PartsUsageHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'PartsUsage';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('IndicatorName', old.`IndicatorName`, 'ValueCode', old.`ValueCode`, 'Description', old.`Description`, 'DisplayOrder', old.`DisplayOrder`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('IndicatorName', new.`IndicatorName`, 'ValueCode', new.`ValueCode`, 'Description', new.`Description`, 'DisplayOrder', new.`DisplayOrder`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `IndicatorValueHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `IndicatorValueHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'IndicatorValue';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('RoleType', old.`RoleType`, 'RequiresTechnician', old.`RequiresTechnician`, 'RoleIndicator', old.`RoleIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('RoleType', new.`RoleType`, 'RequiresTechnician', new.`RequiresTechnician`, 'RoleIndicator', new.`RoleIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `UserRolePolicyHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `UserRolePolicyHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'UserRolePolicy';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('SessionAccount', old.`SessionAccount`, 'PrincipalType', old.`PrincipalType`, 'UserID', old.`UserID`, 'TypeIndicator', old.`TypeIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('SessionAccount', new.`SessionAccount`, 'PrincipalType', new.`PrincipalType`, 'UserID', new.`UserID`, 'TypeIndicator', new.`TypeIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `DatabasePrincipalHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `DatabasePrincipalHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'DatabasePrincipal';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('RoleType', old.`RoleType`, 'ProcedureName', old.`ProcedureName`, 'RoleIndicator', old.`RoleIndicator`, 'ProcedureIndicator', old.`ProcedureIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('RoleType', new.`RoleType`, 'ProcedureName', new.`ProcedureName`, 'RoleIndicator', new.`RoleIndicator`, 'ProcedureIndicator', new.`ProcedureIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `RoleProcedurePermissionHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `RoleProcedurePermissionHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'RoleProcedurePermission';

    INSERT INTO tmp_TemporalPage
SELECT e.EventID, e.EntityType, e.RecordIdentifier, e.OperationType, e.ChangedAttributes,
    IF(old.HistoryID IS NULL, NULL, JSON_OBJECT('SessionAccount', old.`SessionAccount`, 'UserID', old.`UserID`, 'ProcedureName', old.`ProcedureName`, 'ProcedureIndicator', old.`ProcedureIndicator`)) AS PreviousValue,
    IF(new.HistoryID IS NULL, NULL, JSON_OBJECT('SessionAccount', new.`SessionAccount`, 'UserID', new.`UserID`, 'ProcedureName', new.`ProcedureName`, 'ProcedureIndicator', new.`ProcedureIndicator`)) AS NewValue,
    e.ResponsibleUserID, e.SessionAccount, e.EventTimestamp, e.ContextID, e.Reason
FROM tmp_TemporalPageIDs page STRAIGHT_JOIN TemporalEvent e ON page.EventID = e.EventID
LEFT JOIN `PrincipalDelegationHistory` old ON old.HistoryEndEventID = e.EventID
LEFT JOIN `PrincipalDelegationHistory` new ON new.HistoryStartEventID = e.EventID
WHERE e.EntityType = 'PrincipalDelegation';

    SELECT * FROM tmp_TemporalPage ORDER BY EventID DESC;
    DROP TEMPORARY TABLE tmp_TemporalPage, tmp_TemporalPageIDs;
END //
DELIMITER ;
