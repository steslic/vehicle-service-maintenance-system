-- Session identity is authoritative. Caller IDs are optional assertions (people)
-- or explicitly authorized delegation requests (services), never authentication.
CREATE TABLE UserRolePolicy (
    RoleType VARCHAR(30) NOT NULL PRIMARY KEY,
    RequiresTechnician BOOLEAN NOT NULL,
    RoleIndicator VARCHAR(64) GENERATED ALWAYS AS ('user_role') STORED,
    FOREIGN KEY (RoleIndicator, RoleType) REFERENCES IndicatorValue (IndicatorName, ValueCode),
    CHECK (RequiresTechnician IN (0, 1))
) ENGINE=InnoDB;
INSERT INTO UserRolePolicy (RoleType, RequiresTechnician) VALUES
    ('Service Advisor', 0), ('Technician', 1), ('Manager', 0);

CREATE TABLE DatabasePrincipal (
    SessionAccount VARCHAR(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL PRIMARY KEY,
    PrincipalType VARCHAR(20) NOT NULL,
    UserID INT NULL,
    TypeIndicator VARCHAR(64) GENERATED ALWAYS AS ('principal_type') STORED,
    FOREIGN KEY (TypeIndicator, PrincipalType) REFERENCES IndicatorValue (IndicatorName, ValueCode),
    FOREIGN KEY (UserID) REFERENCES UserAccount(UserID),
    CHECK ((PrincipalType = 'Person' AND UserID IS NOT NULL)
        OR (PrincipalType = 'Service' AND UserID IS NULL)),
    CHECK (TRIM(SessionAccount) <> '')
) ENGINE=InnoDB;
-- Register the existing local identity model, without creating MySQL accounts.
-- Other hosts and service identities require explicit administrator registration.
INSERT INTO DatabasePrincipal (SessionAccount, PrincipalType, UserID)
SELECT CONCAT(Username, '@localhost'), 'Person', UserID FROM UserAccount;

CREATE TABLE RoleProcedurePermission (
    RoleType VARCHAR(30) NOT NULL,
    ProcedureName VARCHAR(64) NOT NULL,
    RoleIndicator VARCHAR(64) GENERATED ALWAYS AS ('user_role') STORED,
    ProcedureIndicator VARCHAR(64) GENERATED ALWAYS AS ('procedure_name') STORED,
    PRIMARY KEY (RoleType, ProcedureName),
    FOREIGN KEY (RoleIndicator, RoleType) REFERENCES IndicatorValue (IndicatorName, ValueCode),
    FOREIGN KEY (ProcedureIndicator, ProcedureName) REFERENCES IndicatorValue (IndicatorName, ValueCode)
) ENGINE=InnoDB;
INSERT INTO RoleProcedurePermission (RoleType, ProcedureName) VALUES
    ('Service Advisor', 'sp_CreateServiceAppointment'), ('Manager', 'sp_CreateServiceAppointment'),
    ('Technician', 'sp_CompleteRepair'), ('Manager', 'sp_CompleteRepair');

CREATE TABLE PrincipalDelegation (
    SessionAccount VARCHAR(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
    UserID INT NOT NULL,
    ProcedureName VARCHAR(64) NOT NULL,
    ProcedureIndicator VARCHAR(64) GENERATED ALWAYS AS ('procedure_name') STORED,
    PRIMARY KEY (SessionAccount, UserID, ProcedureName),
    FOREIGN KEY (SessionAccount) REFERENCES DatabasePrincipal(SessionAccount),
    FOREIGN KEY (UserID) REFERENCES UserAccount(UserID),
    FOREIGN KEY (ProcedureIndicator, ProcedureName) REFERENCES IndicatorValue (IndicatorName, ValueCode)
) ENGINE=InnoDB;

-- Written only by the definer procedures; no application principal receives DML.
-- The row is inserted and removed in the business transaction, so disconnects
-- cannot leave committed authority on a pooled or reused connection.
CREATE TABLE OperationContext (
    ConnectionID BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    SessionAccount VARCHAR(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
    UserID INT NOT NULL,
    ProcedureName VARCHAR(64) NOT NULL,
    ContextID CHAR(36) NOT NULL,
    FOREIGN KEY (SessionAccount) REFERENCES DatabasePrincipal(SessionAccount),
    FOREIGN KEY (UserID) REFERENCES UserAccount(UserID)
) ENGINE=InnoDB;

-- Legacy audit rows retain NULL system identity: their source cannot be inferred.
ALTER TABLE AuditLog
    MODIFY COLUMN UserID INT NULL,
    ADD COLUMN SessionAccount VARCHAR(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NULL,
    ADD CONSTRAINT chk_AuditLog_ResponsiblePerson CHECK (Action = 'Rejected' OR UserID IS NOT NULL);

DELIMITER //
CREATE PROCEDURE sp_VerifyIdentityProfiles()
BEGIN
    IF EXISTS (SELECT 1 FROM UserAccount u LEFT JOIN UserRolePolicy p ON p.RoleType = u.RoleType
               WHERE p.RoleType IS NULL OR (p.RequiresTechnician = 1 AND u.TechnicianID IS NULL)
                  OR (p.RequiresTechnician = 0 AND u.TechnicianID IS NOT NULL)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Existing user profiles do not match their roles';
    END IF;
    IF EXISTS (SELECT 1 FROM Customer WHERE TRIM(Name) = '')
       OR EXISTS (SELECT 1 FROM Vehicle WHERE TRIM(VIN) = '' OR TRIM(Make) = '' OR TRIM(Model) = '')
       OR EXISTS (SELECT 1 FROM Technician WHERE TRIM(Name) = '')
       OR EXISTS (SELECT 1 FROM Part WHERE TRIM(PartNumber) = '' OR TRIM(PartName) = '')
       OR EXISTS (SELECT 1 FROM UserAccount WHERE TRIM(Username) = '' OR TRIM(Name) = '')
       OR EXISTS (SELECT 1 FROM ServiceAppointment WHERE TRIM(ServiceRequestDescription) = '' OR EstimatedDuration > 1440)
       OR EXISTS (SELECT 1 FROM Repair WHERE TRIM(RepairDescription) = '')
       OR EXISTS (SELECT 1 FROM EstimateLineItem WHERE TRIM(Description) = '')
       OR EXISTS (SELECT 1 FROM InvoiceLineItem WHERE TRIM(Description) = '') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Existing required fields need review before applying provenance rules';
    END IF;
    IF EXISTS (SELECT 1 FROM Repair WHERE Status <> 'Completed'
               AND (CompletedByTechnicianID IS NOT NULL OR CompletionDateTime IS NOT NULL))
       OR EXISTS (SELECT 1 FROM RepairEstimate WHERE Status IN ('Draft', 'Pending Approval')
                  AND (ApprovedByUserID IS NOT NULL OR ApprovalDateTime IS NOT NULL))
       OR EXISTS (SELECT 1 FROM Invoice WHERE Status = 'Draft'
                  AND (FinalizedByUserID IS NOT NULL OR FinalizationDateTime IS NOT NULL)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Existing premature decision metadata needs review';
    END IF;
END //
DELIMITER ;
CALL sp_VerifyIdentityProfiles();
DROP PROCEDURE sp_VerifyIdentityProfiles;

ALTER TABLE UserAccount ADD CONSTRAINT fk_UserAccount_RolePolicy
    FOREIGN KEY (RoleType) REFERENCES UserRolePolicy(RoleType);

DELIMITER //
CREATE TRIGGER trg_UserRolePolicy_ProfileGuard_bu
BEFORE UPDATE ON UserRolePolicy FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM UserAccount WHERE RoleType = OLD.RoleType
               AND ((NEW.RequiresTechnician = 1 AND TechnicianID IS NULL)
                 OR (NEW.RequiresTechnician = 0 AND TechnicianID IS NOT NULL))) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Role policy would invalidate existing user profiles';
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
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Database session is not a registered principal';
    END IF;
    IF v_Type = 'Person' THEN
        IF p_RequestedUserID IS NOT NULL AND NOT (p_RequestedUserID <=> p_UserID) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Acting user must be the logged-in user';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM UserAccount WHERE UserID = p_UserID
                       AND BINARY Username = BINARY SUBSTRING_INDEX(USER(), '@', 1)) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Login mapping does not match the person';
        END IF;
    ELSEIF v_Type = 'Service' THEN
        IF p_ProcedureName IS NULL OR p_RequestedUserID IS NULL OR NOT EXISTS (
            SELECT 1 FROM PrincipalDelegation WHERE SessionAccount = USER()
              AND UserID = p_RequestedUserID AND ProcedureName = p_ProcedureName
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Service is not authorized to act for this person and operation';
        END IF;
        SET p_UserID = p_RequestedUserID;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unsupported principal type';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM UserAccount u JOIN UserRolePolicy p ON p.RoleType = u.RoleType
                   LEFT JOIN Technician t ON t.TechnicianID = u.TechnicianID
                   WHERE u.UserID = p_UserID
                     AND ((p.RequiresTechnician = 0 AND u.TechnicianID IS NULL)
                       OR (p.RequiresTechnician = 1 AND t.ActiveStatus = 1))) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Responsible actor is invalid or inactive';
    END IF;
    IF p_ProcedureName IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM UserAccount u JOIN RoleProcedurePermission r ON r.RoleType = u.RoleType
        WHERE u.UserID = p_UserID AND r.ProcedureName = p_ProcedureName
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Responsible person is not entitled to this operation';
    END IF;
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

DROP PROCEDURE sp_WriteAuditLog //
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

-- Internal failure writer: retain the authenticated session even when no
-- responsible human can be verified. The requested identity stays in JSON.
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
DELIMITER ;

-- DROP PROCEDURE removes native routine grants. Retain existing public
-- EXECUTE/ALTER ROUTINE grants (including role activation gates) exactly.
CREATE TEMPORARY TABLE tmp_PublicRoutineGrants AS
SELECT User, Host, Routine_name, Proc_priv FROM mysql.procs_priv
WHERE Db = DATABASE() AND LOWER(Routine_name) IN ('sp_createserviceappointment', 'sp_completerepair');

DELIMITER //
DROP PROCEDURE sp_CreateServiceAppointment //
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

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_ErrorMessage = MESSAGE_TEXT;
        IF v_TransactionStarted THEN ROLLBACK; END IF;
        CALL sp_RecordRejectedAttempt(v_RequestedUserID, 'sp_CreateServiceAppointment', 'ServiceAppointment',
            NULL, v_ErrorMessage, JSON_OBJECT('CustomerID', p_CustomerID, 'VehicleID', p_VehicleID, 'TechnicianID', p_TechnicianID, 'AppointmentDateTime', p_AppointmentDateTime), v_CallContext);
        IF v_TransactionStarted THEN COMMIT; END IF;
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
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid appointment information';
    END IF;

    -- Check that the creating user exists
    SELECT COUNT(*)
    INTO v_Count
    FROM UserAccount
    WHERE UserID = p_CreatedByUserID;

    IF v_Count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Creating user does not exist';
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
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Vehicle does not belong to the customer';
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
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Technician does not exist or is inactive';
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
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Vehicle already has a conflicting appointment';
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
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Technician already has a conflicting appointment';
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
    COMMIT;
    SET @app_user_id = NULL;
    SET @context_id = NULL;

    SELECT v_AppointmentID AS AppointmentID;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE sp_CompleteRepair //
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

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_ErrorMessage = MESSAGE_TEXT;
        IF v_TransactionStarted THEN ROLLBACK; END IF;
        DROP TEMPORARY TABLE IF EXISTS tmp_RepairParts;
        CALL sp_RecordRejectedAttempt(v_RequestedUserID, 'sp_CompleteRepair', 'Repair',
            p_RepairID, v_ErrorMessage, JSON_OBJECT('TechnicianID', p_TechnicianID, 'Parts', p_Parts), v_CallContext);
        IF v_TransactionStarted THEN COMMIT; END IF;
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
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Repair does not exist';
    END IF;

    -- FRD: only an In Progress repair can be completed
    IF v_RepairStatus <> 'In Progress' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Repair must be In Progress to be completed';
    END IF;

    -- Lock the appointment and check its status and assigned technician
    SELECT Status, TechnicianID
    INTO v_AppointmentStatus, v_AssignedTechnicianID
    FROM ServiceAppointment
    WHERE AppointmentID = v_AppointmentID
    FOR UPDATE;

    IF v_AppointmentStatus IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Appointment for this repair does not exist';
    END IF;

    -- Work can only be completed while the vehicle is in the shop: the
    -- appointment must be In Progress (not Scheduled, Checked In, or closed)
    IF v_AppointmentStatus <> 'In Progress' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Appointment must be In Progress to complete a repair';
    END IF;

        IF p_TechnicianID IS NULL OR NOT (v_AssignedTechnicianID <=> p_TechnicianID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Technician is not assigned to this appointment';
    END IF;

    -- Recording user must be the assigned technician's own account, or a Manager
    SELECT COUNT(*)
    INTO v_Count
    FROM UserAccount
    WHERE UserID = p_RecordedByUserID
      AND (RoleType = 'Manager'
           OR (RoleType = 'Technician' AND TechnicianID = p_TechnicianID));

    IF v_Count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Recording user is not authorized to complete this repair';
    END IF;

    -- Audit triggers read these variables
    SET @app_user_id = p_RecordedByUserID;
    SET @adj_reason = CONCAT('Parts usage for repair ', p_RepairID);

    -- Reject any non-array JSON, including {}
    IF p_Parts IS NOT NULL AND JSON_TYPE(p_Parts) <> 'ARRAY' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Parts must be a JSON array';
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
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Each part needs an integer partId and a positive integer qty';
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

        -- Lock every requested part; all must exist and be active
        SELECT COUNT(*)
        INTO v_Count
        FROM Part p
        JOIN tmp_RepairParts t ON t.PartID = p.PartID
        WHERE p.ActiveStatus = 1
        FOR UPDATE OF p;

        IF v_Count <> v_PartCount THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A part does not exist or is inactive';
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
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Insufficient parts inventory';
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
    COMMIT;
    SET @app_user_id = NULL;
    SET @adj_reason = NULL;
    SET @context_id = NULL;

    SELECT p_RepairID AS CompletedRepairID;
END //
DELIMITER ;

DELIMITER //

CREATE TRIGGER trg_Customer_Provenance_bi
BEFORE INSERT ON `Customer` FOR EACH ROW
BEGIN
    IF TRIM(NEW.`Name`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Customer.Name cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Customer_Provenance_bu
BEFORE UPDATE ON `Customer` FOR EACH ROW
BEGIN
    IF TRIM(NEW.`Name`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Customer.Name cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Vehicle_Provenance_bi
BEFORE INSERT ON `Vehicle` FOR EACH ROW
BEGIN
    IF TRIM(NEW.`VIN`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Vehicle.VIN cannot be blank'; END IF;
    IF TRIM(NEW.`Make`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Vehicle.Make cannot be blank'; END IF;
    IF TRIM(NEW.`Model`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Vehicle.Model cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Vehicle_Provenance_bu
BEFORE UPDATE ON `Vehicle` FOR EACH ROW
BEGIN
    IF TRIM(NEW.`VIN`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Vehicle.VIN cannot be blank'; END IF;
    IF TRIM(NEW.`Make`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Vehicle.Make cannot be blank'; END IF;
    IF TRIM(NEW.`Model`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Vehicle.Model cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Technician_Provenance_bi
BEFORE INSERT ON `Technician` FOR EACH ROW
PRECEDES trg_Technician_Indicator_bi
BEGIN
    IF TRIM(NEW.`Name`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Technician.Name cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Technician_Provenance_bu
BEFORE UPDATE ON `Technician` FOR EACH ROW
PRECEDES trg_Technician_Indicator_bu
BEGIN
    IF TRIM(NEW.`Name`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Technician.Name cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Part_Provenance_bi
BEFORE INSERT ON `Part` FOR EACH ROW
PRECEDES trg_Part_Indicator_bi
BEGIN
    IF TRIM(NEW.`PartNumber`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Part.PartNumber cannot be blank'; END IF;
    IF TRIM(NEW.`PartName`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Part.PartName cannot be blank'; END IF;
END //

CREATE TRIGGER trg_Part_Provenance_bu
BEFORE UPDATE ON `Part` FOR EACH ROW
PRECEDES trg_Part_Indicator_bu
BEGIN
    IF TRIM(NEW.`PartNumber`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Part.PartNumber cannot be blank'; END IF;
    IF TRIM(NEW.`PartName`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Part.PartName cannot be blank'; END IF;
END //

CREATE TRIGGER trg_UserAccount_Provenance_bi
BEFORE INSERT ON `UserAccount` FOR EACH ROW
PRECEDES trg_UserAccount_Indicator_bi
BEGIN
    IF TRIM(NEW.`Username`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'UserAccount.Username cannot be blank'; END IF;
    IF TRIM(NEW.`Name`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'UserAccount.Name cannot be blank'; END IF;
    IF NOT EXISTS (SELECT 1 FROM UserRolePolicy p WHERE p.RoleType = NEW.RoleType
                   AND ((p.RequiresTechnician = 1 AND NEW.TechnicianID IS NOT NULL)
                     OR (p.RequiresTechnician = 0 AND NEW.TechnicianID IS NULL))) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User role and technician profile do not match';
    END IF;
END //

CREATE TRIGGER trg_UserAccount_Provenance_bu
BEFORE UPDATE ON `UserAccount` FOR EACH ROW
PRECEDES trg_UserAccount_Indicator_bu
BEGIN
    IF TRIM(NEW.`Username`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'UserAccount.Username cannot be blank'; END IF;
    IF TRIM(NEW.`Name`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'UserAccount.Name cannot be blank'; END IF;
    IF NOT EXISTS (SELECT 1 FROM UserRolePolicy p WHERE p.RoleType = NEW.RoleType
                   AND ((p.RequiresTechnician = 1 AND NEW.TechnicianID IS NOT NULL)
                     OR (p.RequiresTechnician = 0 AND NEW.TechnicianID IS NULL))) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User role and technician profile do not match';
    END IF;
    IF NOT (OLD.UserID <=> NEW.UserID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User identifiers cannot be changed';
    END IF;
    IF NOT (OLD.Username <=> NEW.Username) AND EXISTS (SELECT 1 FROM DatabasePrincipal WHERE UserID = OLD.UserID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Re-register login mappings before renaming a user';
    END IF;
END //

CREATE TRIGGER trg_ServiceAppointment_Provenance_bi
BEFORE INSERT ON `ServiceAppointment` FOR EACH ROW
PRECEDES trg_ServiceAppointment_Indicator_bi
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`ServiceRequestDescription`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ServiceAppointment.ServiceRequestDescription cannot be blank'; END IF;
    IF NEW.CreatedByUserID IS NOT NULL AND NOT (NEW.CreatedByUserID <=> v_UserID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Creating user must match the responsible actor';
    END IF;
    SET NEW.CreatedByUserID = v_UserID;
    IF NEW.EstimatedDuration > 1440 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid appointment information';
    END IF;
    IF NEW.Status <> 'Scheduled' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'New appointments must start in Scheduled status';
    END IF;
    IF NEW.CancellationDate IS NOT NULL OR NEW.CancellationReason IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cancellation information belongs to cancellation';
    END IF;
    SET NEW.CreationTimestamp = UTC_TIMESTAMP();
END //

CREATE TRIGGER trg_ServiceAppointment_Provenance_bu
BEFORE UPDATE ON `ServiceAppointment` FOR EACH ROW
PRECEDES trg_ServiceAppointment_Indicator_bu
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`ServiceRequestDescription`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ServiceAppointment.ServiceRequestDescription cannot be blank'; END IF;
    IF NEW.EstimatedDuration > 1440 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid appointment information';
    END IF;
    IF NOT (OLD.CreationTimestamp <=> NEW.CreationTimestamp) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Creation timestamp cannot be changed';
    END IF;
    IF NEW.Status = 'Cancelled' AND OLD.Status <> 'Cancelled' THEN
        SET NEW.CancellationDate = UTC_DATE();
    ELSEIF NOT (OLD.CancellationDate <=> NEW.CancellationDate) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cancellation date can only be set by cancellation';
    END IF;
END //

CREATE TRIGGER trg_Repair_Provenance_bi
BEFORE INSERT ON `Repair` FOR EACH ROW
PRECEDES trg_Repair_Indicator_bi
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`RepairDescription`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Repair.RepairDescription cannot be blank'; END IF;
    IF NEW.CompletedByTechnicianID IS NOT NULL OR NEW.CompletionDateTime IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'New repairs cannot contain completion metadata';
    END IF;
END //

CREATE TRIGGER trg_Repair_Provenance_bu
BEFORE UPDATE ON `Repair` FOR EACH ROW
PRECEDES trg_Repair_Indicator_bu
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`RepairDescription`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Repair.RepairDescription cannot be blank'; END IF;
    IF NEW.Status = 'Completed' AND OLD.Status <> 'Completed' THEN
        IF NOT EXISTS (SELECT 1 FROM OperationContext WHERE ConnectionID = CONNECTION_ID()
                       AND SessionAccount = USER() AND ProcedureName = 'sp_CompleteRepair')
           AND NOT EXISTS (SELECT 1 FROM UserAccount WHERE UserID = v_UserID AND RoleType = 'Manager') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Repair completion requires its procedure or a Manager';
        END IF;
        SELECT TechnicianID INTO v_AssignedTech FROM ServiceAppointment WHERE AppointmentID = OLD.AppointmentID;
        IF NEW.CompletedByTechnicianID IS NOT NULL AND NOT (NEW.CompletedByTechnicianID <=> v_AssignedTech) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Completing technician must be assigned to the appointment';
        END IF;
        SET NEW.CompletedByTechnicianID = v_AssignedTech;
        SET NEW.CompletionDateTime = UTC_TIMESTAMP();
    ELSEIF NOT (OLD.CompletedByTechnicianID <=> NEW.CompletedByTechnicianID)
        OR NOT (OLD.CompletionDateTime <=> NEW.CompletionDateTime) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Completion fields can only be set by completion';
    END IF;
END //

CREATE TRIGGER trg_RepairEstimate_Provenance_bi
BEFORE INSERT ON `RepairEstimate` FOR EACH ROW
PRECEDES trg_RepairEstimate_Indicator_bi
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF NEW.CreatedByUserID IS NOT NULL AND NOT (NEW.CreatedByUserID <=> v_UserID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Creating user must match the responsible actor';
    END IF;
    SET NEW.CreatedByUserID = v_UserID;
    IF NEW.ApprovedByUserID IS NOT NULL OR NEW.ApprovalDateTime IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Draft estimates cannot contain approval metadata';
    END IF;
END //

CREATE TRIGGER trg_RepairEstimate_Provenance_bu
BEFORE UPDATE ON `RepairEstimate` FOR EACH ROW
PRECEDES trg_RepairEstimate_Indicator_bu
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF NEW.Status IN ('Approved', 'Rejected') AND NOT (OLD.Status <=> NEW.Status) THEN
        IF NEW.ApprovedByUserID IS NOT NULL AND NOT (NEW.ApprovedByUserID <=> v_UserID) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Approver must match the responsible actor';
        END IF;
        SET NEW.ApprovedByUserID = v_UserID;
        SET NEW.ApprovalDateTime = UTC_TIMESTAMP();
    END IF;
END //

CREATE TRIGGER trg_Invoice_Provenance_bi
BEFORE INSERT ON `Invoice` FOR EACH ROW
PRECEDES trg_Invoice_Indicator_bi
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF NEW.CreatedByUserID IS NOT NULL AND NOT (NEW.CreatedByUserID <=> v_UserID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Creating user must match the responsible actor';
    END IF;
    SET NEW.CreatedByUserID = v_UserID;
    IF NEW.FinalizedByUserID IS NOT NULL OR NEW.FinalizationDateTime IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Draft invoices cannot contain finalization metadata';
    END IF;
END //

CREATE TRIGGER trg_Invoice_Provenance_bu
BEFORE UPDATE ON `Invoice` FOR EACH ROW
PRECEDES trg_Invoice_Indicator_bu
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF NEW.Status = 'Finalized' AND OLD.Status <> 'Finalized' THEN
        IF NEW.FinalizedByUserID IS NOT NULL AND NOT (NEW.FinalizedByUserID <=> v_UserID) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Finalizer must match the responsible actor';
        END IF;
        SET NEW.FinalizedByUserID = v_UserID;
        SET NEW.FinalizationDateTime = UTC_TIMESTAMP();
    ELSEIF NOT (OLD.FinalizedByUserID <=> NEW.FinalizedByUserID)
        OR NOT (OLD.FinalizationDateTime <=> NEW.FinalizationDateTime) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Finalization fields can only be set by finalization';
    END IF;
END //

CREATE TRIGGER trg_PartsUsage_Provenance_bi
BEFORE INSERT ON `PartsUsage` FOR EACH ROW
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF NOT (NEW.RecordedByUserID <=> v_UserID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Recording user must match the responsible actor';
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
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Parts usage provenance cannot be changed';
    END IF;
END //

CREATE TRIGGER trg_EstimateLineItem_Provenance_bi
BEFORE INSERT ON `EstimateLineItem` FOR EACH ROW
PRECEDES trg_EstimateLineItem_Validate_bi
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`Description`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'EstimateLineItem.Description cannot be blank'; END IF;
END //

CREATE TRIGGER trg_EstimateLineItem_Provenance_bu
BEFORE UPDATE ON `EstimateLineItem` FOR EACH ROW
PRECEDES trg_EstimateLineItem_Validate_bu
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`Description`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'EstimateLineItem.Description cannot be blank'; END IF;
END //

CREATE TRIGGER trg_InvoiceLineItem_Provenance_bi
BEFORE INSERT ON `InvoiceLineItem` FOR EACH ROW
PRECEDES trg_InvoiceLineItem_Validate_bi
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`Description`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'InvoiceLineItem.Description cannot be blank'; END IF;
END //

CREATE TRIGGER trg_InvoiceLineItem_Provenance_bu
BEFORE UPDATE ON `InvoiceLineItem` FOR EACH ROW
PRECEDES trg_InvoiceLineItem_Validate_bu
BEGIN
    DECLARE v_UserID INT;
    DECLARE v_AssignedTech INT;
    CALL sp_ActorForWrite(v_UserID);
    IF TRIM(NEW.`Description`) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'InvoiceLineItem.Description cannot be blank'; END IF;
END //

CREATE PROCEDURE sp_RestorePublicRoutineGrants()
BEGIN
    DECLARE v_Done BOOLEAN DEFAULT FALSE;
    DECLARE v_User VARCHAR(32);
    DECLARE v_Host VARCHAR(255);
    DECLARE v_Name VARCHAR(64);
    DECLARE v_Priv VARCHAR(128);
    DECLARE v_Grant TEXT;
    DECLARE grants_cursor CURSOR FOR SELECT User, Host, Routine_name, Proc_priv FROM tmp_PublicRoutineGrants;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_Done = TRUE;
    OPEN grants_cursor;
    restore_loop: LOOP
        FETCH grants_cursor INTO v_User, v_Host, v_Name, v_Priv;
        IF v_Done THEN LEAVE restore_loop; END IF;
        SET v_Grant = CONCAT_WS(', ', IF(FIND_IN_SET('Execute', v_Priv), 'EXECUTE', NULL),
                                     IF(FIND_IN_SET('Alter Routine', v_Priv), 'ALTER ROUTINE', NULL));
        IF v_Grant <> '' THEN
            SET @restore_sql = CONCAT('GRANT ', v_Grant, ' ON PROCEDURE `', DATABASE(), '`.`', v_Name,
                '` TO ', QUOTE(v_User), '@', QUOTE(v_Host), IF(FIND_IN_SET('Grant', v_Priv), ' WITH GRANT OPTION', ''));
            PREPARE restore_stmt FROM @restore_sql; EXECUTE restore_stmt; DEALLOCATE PREPARE restore_stmt;
        END IF;
    END LOOP;
    CLOSE grants_cursor;
END //
DELIMITER ;
CALL sp_RestorePublicRoutineGrants();
DROP PROCEDURE sp_RestorePublicRoutineGrants;
DROP TEMPORARY TABLE tmp_PublicRoutineGrants;

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
