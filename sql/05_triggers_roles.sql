-- Vehicle Service and Maintenance Management System
-- 05_triggers_roles.sql
-- Audit triggers, validation triggers, and role-based access control
--
-- Audit attribution: every audited write must run with the session variable
-- @app_user_id set to a valid UserAccount.UserID (FR-08, SEC-03).
-- Inventory quantity changes also require @adj_reason (FRD audit requirements).

USE vehicle_service_maintenance;

DELIMITER //

-- =====================================================================
-- 1. AUDIT HELPER
-- Called only by the audit triggers below. Not granted to any role, so
-- users cannot write AuditLog rows directly. Triggers run with their
-- definer's privileges, which allows them to call it.
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_WriteAuditLog //

CREATE PROCEDURE sp_WriteAuditLog(
    IN p_Action           VARCHAR(50),
    IN p_AffectedEntity   VARCHAR(100),
    IN p_AffectedRecordID INT,
    IN p_PreviousValue    JSON,
    IN p_NewValue         JSON
)
BEGIN
    -- Every audit row must identify the acting user (T-25)
    IF @app_user_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Acting user not set: SET @app_user_id before writing audited data';
    END IF;

    INSERT INTO AuditLog (
        UserID, `Timestamp`, Action, AffectedEntity,
        AffectedRecordID, PreviousValue, NewValue, ContextID
    )
    VALUES (
        @app_user_id, NOW(), p_Action, p_AffectedEntity,
        p_AffectedRecordID, p_PreviousValue, p_NewValue, @context_id
    );
END //


-- =====================================================================
-- 2. AUDIT TRIGGERS (FR-08, SEC-03, BR-07)
-- AFTER UPDATE triggers compare the before/after JSON images and skip
-- updates that change nothing (T-23). AFTER DELETE triggers store the
-- full deleted row, since it is the only remaining copy.
-- =====================================================================

-- ---------------------------------------------------------------------
-- trg_ServiceAppointment_Audit
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_ServiceAppointment_Audit_ai //
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

DROP TRIGGER IF EXISTS trg_ServiceAppointment_Audit_au //
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

DROP TRIGGER IF EXISTS trg_ServiceAppointment_Audit_ad //
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


-- ---------------------------------------------------------------------
-- trg_Repair_Audit
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_Repair_Audit_ai //
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

DROP TRIGGER IF EXISTS trg_Repair_Audit_au //
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

DROP TRIGGER IF EXISTS trg_Repair_Audit_ad //
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


-- ---------------------------------------------------------------------
-- trg_RepairEstimate_Audit
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_RepairEstimate_Audit_ai //
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

DROP TRIGGER IF EXISTS trg_RepairEstimate_Audit_au //
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

DROP TRIGGER IF EXISTS trg_RepairEstimate_Audit_ad //
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


-- ---------------------------------------------------------------------
-- trg_Invoice_Audit
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_Invoice_Audit_ai //
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

DROP TRIGGER IF EXISTS trg_Invoice_Audit_au //
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

DROP TRIGGER IF EXISTS trg_Invoice_Audit_ad //
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


-- ---------------------------------------------------------------------
-- trg_PartInventory_Audit
-- Only quantity changes are inventory adjustments, so only AFTER UPDATE
-- is needed. A reason is required (FRD audit table: adjustment reason).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_PartInventory_Audit_au //
CREATE TRIGGER trg_PartInventory_Audit_au
AFTER UPDATE ON Part
FOR EACH ROW
BEGIN
    IF NOT (OLD.QuantityOnHand <=> NEW.QuantityOnHand) THEN
        IF @adj_reason IS NULL OR TRIM(@adj_reason) = '' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Inventory adjustments require @adj_reason';
        END IF;

        CALL sp_WriteAuditLog('Inventory Adjustment', 'Part', NEW.PartID,
            JSON_OBJECT('QuantityOnHand', OLD.QuantityOnHand),
            JSON_OBJECT('QuantityOnHand', NEW.QuantityOnHand,
                        'Reason',         @adj_reason));
    END IF;
END //


-- ---------------------------------------------------------------------
-- trg_PartsUsage_Audit
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_PartsUsage_Audit_ai //
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

DROP TRIGGER IF EXISTS trg_PartsUsage_Audit_au //
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

DROP TRIGGER IF EXISTS trg_PartsUsage_Audit_ad //
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

-- ---------------------------------------------------------------------
-- trg_EstimateLineItem_Audit
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_EstimateLineItem_Audit_ai //
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

DROP TRIGGER IF EXISTS trg_EstimateLineItem_Audit_au //
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

DROP TRIGGER IF EXISTS trg_EstimateLineItem_Audit_ad //
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


-- ---------------------------------------------------------------------
-- trg_InvoiceLineItem_Audit
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_InvoiceLineItem_Audit_ai //
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

DROP TRIGGER IF EXISTS trg_InvoiceLineItem_Audit_au //
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

DROP TRIGGER IF EXISTS trg_InvoiceLineItem_Audit_ad //
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

-- =====================================================================
-- 3. VALIDATION TRIGGERS (FR-14, FR-18, FR-19, SEC-01, SEC-02, BR-05)
-- =====================================================================

-- ---------------------------------------------------------------------
-- trg_ServiceAppointment_Status_Validate
-- FRD transitions: Scheduled -> Checked In -> In Progress -> Completed;
--                  Scheduled -> Cancelled; Scheduled -> No Show
-- FR-14: completed, cancelled, and no-show appointments cannot be modified
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_ServiceAppointment_Status_Validate_bu //
CREATE TRIGGER trg_ServiceAppointment_Status_Validate_bu
BEFORE UPDATE ON ServiceAppointment
FOR EACH ROW
BEGIN
    -- Record IDs never change 
    IF NOT (OLD.AppointmentID <=> NEW.AppointmentID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Record IDs cannot be changed';
    END IF;

    -- The creating user is a historical fact and never changes
    IF NOT (OLD.CreatedByUserID <=> NEW.CreatedByUserID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'The creating user cannot be changed';
    END IF;

    IF OLD.Status IN ('Completed', 'Cancelled', 'No Show') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Completed, cancelled, or no-show appointments cannot be modified';
    END IF;

    -- The vehicle is fixed when the appointment is booked, so it cannot be changed later (FR-14)
    IF NOT (OLD.VehicleID <=> NEW.VehicleID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'An appointment cannot be moved to another vehicle';
    END IF;

    IF NOT (OLD.Status <=> NEW.Status) THEN
        IF NOT (
            (OLD.Status = 'Scheduled'   AND NEW.Status IN ('Checked In', 'Cancelled', 'No Show')) OR
            (OLD.Status = 'Checked In'  AND NEW.Status = 'In Progress') OR
            (OLD.Status = 'In Progress' AND NEW.Status = 'Completed')
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid appointment status transition';
        END IF;

        -- An appointment cannot be closed while it still has unfinished work:
        -- every repair must be Completed or Cancelled first
        IF NEW.Status IN ('Completed', 'Cancelled', 'No Show')
           AND EXISTS (SELECT 1 FROM Repair
                       WHERE AppointmentID = OLD.AppointmentID
                         AND Status IN ('Open', 'In Progress')) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Appointment has open repairs: complete or cancel them first';
        END IF;

        -- Record the cancellation date if the caller did not supply one
        IF NEW.Status = 'Cancelled' THEN
            SET NEW.CancellationDate = COALESCE(NEW.CancellationDate, CURDATE());
        END IF;
    END IF;
END //

-- ---------------------------------------------------------------------
-- trg_ServiceAppointment_Schedule_Validate
-- Rescheduling, changing the duration, or reassigning the technician of an
-- active appointment runs the same checks as sp_CreateServiceAppointment
-- (FR-14, FR-16, BR-04, BR-09): valid duration, active technician, and no
-- overlap with another active appointment for the same vehicle or the
-- same technician. The appointment's own row is excluded from the check.
-- Runs after the status trigger, so closed appointments are rejected first.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_ServiceAppointment_Schedule_Validate_bu //
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
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid appointment information';
        END IF;

        -- Lock the technician and vehicle rows, as the booking procedure
        -- does, so a reschedule and a booking cannot both take one slot
        SELECT COUNT(*) INTO v_Count
        FROM Technician
        WHERE TechnicianID = NEW.TechnicianID AND ActiveStatus = 1
        FOR UPDATE;

        IF v_Count = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Technician does not exist or is inactive';
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
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Vehicle already has a conflicting appointment';
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
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Technician already has a conflicting appointment';
        END IF;
    END IF;
END //

-- ---------------------------------------------------------------------
-- trg_Repair_Status_Validate
-- FRD transitions: Open -> In Progress -> Completed; Open/In Progress -> Cancelled
-- Completed and cancelled repairs cannot be modified (FRD entitlements).
-- Technicians may only change repairs on their own assigned appointments.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_Repair_Status_Validate_bi //
CREATE TRIGGER trg_Repair_Status_Validate_bi
BEFORE INSERT ON Repair
FOR EACH ROW
BEGIN
    DECLARE v_ApptStatus VARCHAR(20) DEFAULT NULL;

    -- New repairs must start as Open (FRD transitions)
    IF NEW.Status <> 'Open' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'New repairs must start in Open status';
    END IF;

    -- Repairs cannot be added to a closed appointment
    SELECT Status INTO v_ApptStatus
    FROM ServiceAppointment
    WHERE AppointmentID = NEW.AppointmentID;

    IF v_ApptStatus IN ('Completed', 'Cancelled', 'No Show') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Repairs cannot be added to a completed, cancelled, or no-show appointment';
    END IF;
END //

DROP TRIGGER IF EXISTS trg_Repair_Status_Validate_bu //
CREATE TRIGGER trg_Repair_Status_Validate_bu
BEFORE UPDATE ON Repair
FOR EACH ROW
BEGIN
    DECLARE v_Role       VARCHAR(30) DEFAULT NULL;
    DECLARE v_UserTechID INT         DEFAULT NULL;
    DECLARE v_ApptTechID INT         DEFAULT NULL;

    -- Record IDs never change (a changed ID would also escape the audit trail)
    IF NOT (OLD.RepairID <=> NEW.RepairID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Record IDs cannot be changed';
    END IF;

    IF OLD.Status IN ('Completed', 'Cancelled') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Completed or cancelled repairs cannot be modified';
    END IF;

    -- A repair belongs to the appointment it was opened on
    IF NOT (OLD.AppointmentID <=> NEW.AppointmentID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A repair cannot be moved to another appointment';
    END IF;

    IF NOT (OLD.Status <=> NEW.Status) THEN
        IF NOT (
            (OLD.Status = 'Open'        AND NEW.Status IN ('In Progress', 'Cancelled')) OR
            (OLD.Status = 'In Progress' AND NEW.Status IN ('Completed', 'Cancelled'))
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid repair status transition';
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
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Technicians may only update their own assigned repairs';
            END IF;
        END IF;
    END IF;
END //


-- ---------------------------------------------------------------------
-- trg_RepairEstimate_Validate
-- FRD transitions: Draft -> Pending Approval -> Approved/Rejected/Expired;
--                  Approved -> Finalized
-- Approval or rejection requires a Manager (SEC-01).
-- Finalized estimates are locked (FR-18).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_RepairEstimate_Validate_bi //
CREATE TRIGGER trg_RepairEstimate_Validate_bi
BEFORE INSERT ON RepairEstimate
FOR EACH ROW
BEGIN
    IF NEW.Status <> 'Draft' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'New repair estimates must start in Draft status';
    END IF;
END //

DROP TRIGGER IF EXISTS trg_RepairEstimate_Validate_bu //
CREATE TRIGGER trg_RepairEstimate_Validate_bu
BEFORE UPDATE ON RepairEstimate
FOR EACH ROW
BEGIN
    DECLARE v_Role VARCHAR(30) DEFAULT NULL;

    -- Record IDs never change (a changed ID would also escape the audit trail)
    IF NOT (OLD.EstimateID <=> NEW.EstimateID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Record IDs cannot be changed';
    END IF;

    -- The creating user is a historical fact and never changes
    IF NOT (OLD.CreatedByUserID <=> NEW.CreatedByUserID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'The creating user cannot be changed';
    END IF;

    IF OLD.Status = 'Finalized' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Finalized estimates cannot be modified';
    END IF;

    -- An estimate belongs to the appointment it was created for
    IF NOT (OLD.AppointmentID <=> NEW.AppointmentID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'An estimate cannot be moved to another appointment';
    END IF;

    IF NOT (OLD.Status <=> NEW.Status) THEN
        IF NOT (
            (OLD.Status = 'Draft'            AND NEW.Status = 'Pending Approval') OR
            (OLD.Status = 'Pending Approval' AND NEW.Status IN ('Approved', 'Rejected', 'Expired')) OR
            (OLD.Status = 'Approved'         AND NEW.Status = 'Finalized')
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid estimate status transition';
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
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Estimates must be approved or rejected by a Manager';
            END IF;

            SET NEW.ApprovalDateTime = COALESCE(NEW.ApprovalDateTime, NOW());
        END IF;
    END IF;
END //

DROP TRIGGER IF EXISTS trg_RepairEstimate_Validate_bd //
CREATE TRIGGER trg_RepairEstimate_Validate_bd
BEFORE DELETE ON RepairEstimate
FOR EACH ROW
BEGIN
    IF OLD.Status = 'Finalized' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Finalized estimates cannot be deleted';
    END IF;
END //


-- ---------------------------------------------------------------------
-- trg_Invoice_Validate
-- FRD transition: Draft -> Finalized. Finalized invoices are locked (FR-18).
-- Finalizing user must be a Service Advisor or Manager (FRD entitlements).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_Invoice_Validate_bi //
CREATE TRIGGER trg_Invoice_Validate_bi
BEFORE INSERT ON Invoice
FOR EACH ROW
BEGIN
    IF NEW.Status <> 'Draft' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'New invoices must start in Draft status';
    END IF;
END //

DROP TRIGGER IF EXISTS trg_Invoice_Validate_bu //
CREATE TRIGGER trg_Invoice_Validate_bu
BEFORE UPDATE ON Invoice
FOR EACH ROW
BEGIN
    DECLARE v_Role VARCHAR(30) DEFAULT NULL;

    -- Record IDs never change (a changed ID would also escape the audit trail)
    IF NOT (OLD.InvoiceID <=> NEW.InvoiceID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Record IDs cannot be changed';
    END IF;

    -- The creating user is a historical fact and never changes
    IF NOT (OLD.CreatedByUserID <=> NEW.CreatedByUserID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'The creating user cannot be changed';
    END IF;

    IF OLD.Status = 'Finalized' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Finalized invoices cannot be modified';
    END IF;

    -- An invoice belongs to the appointment it was created for
    IF NOT (OLD.AppointmentID <=> NEW.AppointmentID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'An invoice cannot be moved to another appointment';
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
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invoices must be finalized by a Service Advisor or Manager';
        END IF;

        SET NEW.FinalizationDateTime = COALESCE(NEW.FinalizationDateTime, NOW());
    END IF;
END //

DROP TRIGGER IF EXISTS trg_Invoice_Validate_bd //
CREATE TRIGGER trg_Invoice_Validate_bd
BEFORE DELETE ON Invoice
FOR EACH ROW
BEGIN
    IF OLD.Status = 'Finalized' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Finalized invoices cannot be deleted';
    END IF;
END //


-- ---------------------------------------------------------------------
-- trg_InvoiceLineItem_Validate
-- Line items of a finalized invoice cannot be inserted, updated, or deleted
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_InvoiceLineItem_Validate_bi //
CREATE TRIGGER trg_InvoiceLineItem_Validate_bi
BEFORE INSERT ON InvoiceLineItem
FOR EACH ROW
BEGIN
    IF (SELECT Status FROM Invoice WHERE InvoiceID = NEW.InvoiceID) = 'Finalized' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot add line items to a finalized invoice';
    END IF;
END //

DROP TRIGGER IF EXISTS trg_InvoiceLineItem_Validate_bu //
CREATE TRIGGER trg_InvoiceLineItem_Validate_bu
BEFORE UPDATE ON InvoiceLineItem
FOR EACH ROW
BEGIN
    -- Record IDs never change (a changed ID would also escape the audit trail)
    IF NOT (OLD.InvoiceLineItemID <=> NEW.InvoiceLineItemID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Record IDs cannot be changed';
    END IF;

    -- A line item belongs to the invoice it was added to
    IF NOT (OLD.InvoiceID <=> NEW.InvoiceID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A line item cannot be moved to another invoice';
    END IF;

    IF (SELECT Status FROM Invoice WHERE InvoiceID = OLD.InvoiceID) = 'Finalized'
       OR (SELECT Status FROM Invoice WHERE InvoiceID = NEW.InvoiceID) = 'Finalized' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot modify line items of a finalized invoice';
    END IF;
END //

DROP TRIGGER IF EXISTS trg_InvoiceLineItem_Validate_bd //
CREATE TRIGGER trg_InvoiceLineItem_Validate_bd
BEFORE DELETE ON InvoiceLineItem
FOR EACH ROW
BEGIN
    IF (SELECT Status FROM Invoice WHERE InvoiceID = OLD.InvoiceID) = 'Finalized' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot delete line items of a finalized invoice';
    END IF;
END //


-- ---------------------------------------------------------------------
-- trg_EstimateLineItem_Validate
-- Line items of a finalized estimate cannot be inserted, updated, or deleted
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_EstimateLineItem_Validate_bi //
CREATE TRIGGER trg_EstimateLineItem_Validate_bi
BEFORE INSERT ON EstimateLineItem
FOR EACH ROW
BEGIN
    IF (SELECT Status FROM RepairEstimate WHERE EstimateID = NEW.EstimateID) = 'Finalized' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot add line items to a finalized estimate';
    END IF;
END //

DROP TRIGGER IF EXISTS trg_EstimateLineItem_Validate_bu //
CREATE TRIGGER trg_EstimateLineItem_Validate_bu
BEFORE UPDATE ON EstimateLineItem
FOR EACH ROW
BEGIN
    -- A line item belongs to the estimate it was added to
    IF NOT (OLD.EstimateID <=> NEW.EstimateID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A line item cannot be moved to another estimate';
    END IF;
    
    IF (SELECT Status FROM RepairEstimate WHERE EstimateID = OLD.EstimateID) = 'Finalized'
       OR (SELECT Status FROM RepairEstimate WHERE EstimateID = NEW.EstimateID) = 'Finalized' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot modify line items of a finalized estimate';
    END IF;
END //

DROP TRIGGER IF EXISTS trg_EstimateLineItem_Validate_bd //
CREATE TRIGGER trg_EstimateLineItem_Validate_bd
BEFORE DELETE ON EstimateLineItem
FOR EACH ROW
BEGIN
    IF (SELECT Status FROM RepairEstimate WHERE EstimateID = OLD.EstimateID) = 'Finalized' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot delete line items of a finalized estimate';
    END IF;
END //


-- ---------------------------------------------------------------------
-- trg_AuditLog_Protect
-- Audit rows are append-only: they cannot be modified or deleted
-- (BR-07, SEC-03, T-22)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_AuditLog_Protect_bu //
CREATE TRIGGER trg_AuditLog_Protect_bu
BEFORE UPDATE ON AuditLog
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Audit records cannot be modified';
END //

DROP TRIGGER IF EXISTS trg_AuditLog_Protect_bd //
CREATE TRIGGER trg_AuditLog_Protect_bd
BEFORE DELETE ON AuditLog
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Audit records cannot be deleted';
END //

DELIMITER ;


-- =====================================================================
-- 4. ROLES AND PRIVILEGES (FR-07, BR-06, SEC-01, SEC-02)
-- Roles live at the server level, so DROP DATABASE does not remove them.
-- Stored procedures run with their definer's privileges, so roles need
-- only EXECUTE on them, not write access to the underlying tables.
-- sp_WriteAuditLog is intentionally not granted to any role.
-- =====================================================================

DROP ROLE IF EXISTS 'role_service_advisor', 'role_technician', 'role_manager';
CREATE ROLE 'role_service_advisor', 'role_technician', 'role_manager';

-- ---------------------------------------------------------------------
-- Service Advisor
-- Creates/updates customers, vehicles, appointments through
-- sp_CreateServiceAppointment (no direct INSERT), technician assignments,
-- non-finalized estimates and invoices; creates repair records; finalizes
-- invoices. Cannot approve or reject estimates (trigger), modify repairs
-- after creation, or access AuditLog.
-- ---------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE         ON vehicle_service_maintenance.Customer           TO 'role_service_advisor';
GRANT SELECT, INSERT, UPDATE         ON vehicle_service_maintenance.Vehicle            TO 'role_service_advisor';
GRANT SELECT, UPDATE                 ON vehicle_service_maintenance.ServiceAppointment TO 'role_service_advisor';
GRANT SELECT, INSERT                 ON vehicle_service_maintenance.Repair             TO 'role_service_advisor';
GRANT SELECT, INSERT, UPDATE         ON vehicle_service_maintenance.RepairEstimate     TO 'role_service_advisor';
GRANT SELECT, INSERT, UPDATE, DELETE ON vehicle_service_maintenance.EstimateLineItem   TO 'role_service_advisor';
GRANT SELECT, INSERT, UPDATE         ON vehicle_service_maintenance.Invoice            TO 'role_service_advisor';
GRANT SELECT, INSERT, UPDATE, DELETE ON vehicle_service_maintenance.InvoiceLineItem    TO 'role_service_advisor';
GRANT SELECT                         ON vehicle_service_maintenance.Technician         TO 'role_service_advisor';
GRANT SELECT                         ON vehicle_service_maintenance.Part               TO 'role_service_advisor';
GRANT SELECT                         ON vehicle_service_maintenance.PartsUsage         TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.vw_VehicleServiceHistory TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.vw_TechnicianWorkload    TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateServiceAppointment TO 'role_service_advisor';

-- ---------------------------------------------------------------------
-- Technician
-- Row-level access (SEC-02): reads only their own appointments and repairs
-- through vw_MyAppointments and vw_MyRepairs, and changes Repair.Status only
-- through vw_MyRepairs. No direct access to the ServiceAppointment or Repair
-- tables. Transitions and ownership are still enforced by trigger; repairs
-- are completed through sp_CompleteRepair. Views vehicles and parts.
-- No access to customers, estimates, or invoices (SEC-02).
-- ---------------------------------------------------------------------
GRANT SELECT                  ON vehicle_service_maintenance.vw_MyAppointments  TO 'role_technician';
GRANT SELECT, UPDATE (Status) ON vehicle_service_maintenance.vw_MyRepairs       TO 'role_technician';
GRANT SELECT                  ON vehicle_service_maintenance.Vehicle            TO 'role_technician';
GRANT SELECT                  ON vehicle_service_maintenance.Part               TO 'role_technician';
GRANT SELECT                  ON vehicle_service_maintenance.PartsUsage         TO 'role_technician';
GRANT SELECT ON vehicle_service_maintenance.vw_VehicleServiceHistory TO 'role_technician';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CompleteRepair TO 'role_technician';

-- ---------------------------------------------------------------------
-- Manager
-- Broad operational and reporting access: creates appointments
-- through sp_CreateServiceAppointment, reassigns technicians, approves
-- or rejects estimates, finalizes invoices, adjusts inventory.
-- SELECT-only on AuditLog. Finalized records and audit rows remain
-- protected by triggers.
-- ---------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE         ON vehicle_service_maintenance.Customer           TO 'role_manager';
GRANT SELECT, INSERT, UPDATE         ON vehicle_service_maintenance.Vehicle            TO 'role_manager';
GRANT SELECT, INSERT, UPDATE         ON vehicle_service_maintenance.Technician         TO 'role_manager';
GRANT SELECT, UPDATE                 ON vehicle_service_maintenance.ServiceAppointment TO 'role_manager';
GRANT SELECT, INSERT, UPDATE         ON vehicle_service_maintenance.Repair             TO 'role_manager';
GRANT SELECT, INSERT, UPDATE         ON vehicle_service_maintenance.RepairEstimate     TO 'role_manager';
GRANT SELECT, INSERT, UPDATE, DELETE ON vehicle_service_maintenance.EstimateLineItem   TO 'role_manager';
GRANT SELECT, INSERT, UPDATE         ON vehicle_service_maintenance.Invoice            TO 'role_manager';
GRANT SELECT, INSERT, UPDATE, DELETE ON vehicle_service_maintenance.InvoiceLineItem    TO 'role_manager';
GRANT SELECT, INSERT, UPDATE         ON vehicle_service_maintenance.Part               TO 'role_manager';
GRANT SELECT                         ON vehicle_service_maintenance.PartsUsage         TO 'role_manager';
GRANT SELECT                         ON vehicle_service_maintenance.UserAccount        TO 'role_manager';
GRANT SELECT                         ON vehicle_service_maintenance.AuditLog           TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.vw_VehicleServiceHistory TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.vw_TechnicianWorkload    TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateServiceAppointment TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CompleteRepair           TO 'role_manager';


-- =====================================================================
-- 5. DEMO ACCOUNTS (for role tests T-11, T-27, T-29, T-31)
-- Usernames must match UserAccount.Username values in 06_sample_data.sql.
-- Fictional sample credentials for local testing only.
-- =====================================================================

DROP USER IF EXISTS 'sa_amy'@'localhost', 'tech_ben'@'localhost', 'mgr_mike'@'localhost';

CREATE USER 'sa_amy'@'localhost'   IDENTIFIED BY 'Advisor#2026';
CREATE USER 'tech_ben'@'localhost' IDENTIFIED BY 'Tech#2026';
CREATE USER 'mgr_mike'@'localhost' IDENTIFIED BY 'Manager#2026';

GRANT 'role_service_advisor' TO 'sa_amy'@'localhost';
GRANT 'role_technician'      TO 'tech_ben'@'localhost';
GRANT 'role_manager'         TO 'mgr_mike'@'localhost';

SET DEFAULT ROLE 'role_service_advisor' TO 'sa_amy'@'localhost';
SET DEFAULT ROLE 'role_technician'      TO 'tech_ben'@'localhost';
SET DEFAULT ROLE 'role_manager'         TO 'mgr_mike'@'localhost';