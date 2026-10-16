-- Vehicle Service and Maintenance Management System
-- 04_procedures.sql

USE vehicle_service_maintenance;

DELIMITER //

-- Procedure 1: Create service appointment
-- Validates appointment data, vehicle ownership, technician status,
-- and vehicle/technician scheduling conflicts (FR-02, FR-05, FR-15, FR-16, BR-04, BR-09)
DROP PROCEDURE IF EXISTS sp_CreateServiceAppointment //

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

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET @app_user_id = NULL;
        RESIGNAL;
    END;

    START TRANSACTION;

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

    COMMIT;
    SET @app_user_id = NULL;

    SELECT v_AppointmentID AS AppointmentID;
END //


-- Procedure 2: Complete repair
-- Records usage for zero or more parts (JSON array), reduces inventory,
-- and completes the repair as one transaction
-- (FR-03, FR-12, FR-13, FR-20, BR-03, BR-08, BR-10)
--
-- Example:
--   CALL sp_CompleteRepair(12, 3, 5, '[{"partId": 4, "qty": 2}, {"partId": 9, "qty": 1}]');
--   CALL sp_CompleteRepair(13, 3, 5, NULL);   -- labor-only repair
DROP PROCEDURE IF EXISTS sp_CompleteRepair //

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

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_RepairParts;
        SET @app_user_id = NULL;
        SET @adj_reason = NULL;
        RESIGNAL;
    END;

    START TRANSACTION;

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

    IF v_AppointmentStatus IN ('Cancelled', 'No Show', 'Completed') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Appointment is cancelled, completed, or marked no show';
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

    COMMIT;
    SET @app_user_id = NULL;
    SET @adj_reason = NULL;

    SELECT p_RepairID AS CompletedRepairID;
END //

DELIMITER ;