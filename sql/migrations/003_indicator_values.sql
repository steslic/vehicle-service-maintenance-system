-- Reference values: domain membership is data; workflow transitions remain unchanged.
CREATE TABLE IndicatorValue (
    IndicatorName VARCHAR(64) NOT NULL,
    ValueCode VARCHAR(100) NOT NULL,
    Description VARCHAR(255) NOT NULL,
    DisplayOrder INT NOT NULL,
    PRIMARY KEY (IndicatorName, ValueCode),
    CHECK (TRIM(IndicatorName) <> '' AND TRIM(ValueCode) <> '' AND TRIM(Description) <> ''),
    CHECK (DisplayOrder >= 0)
) ENGINE=InnoDB;

INSERT INTO IndicatorValue (IndicatorName, ValueCode, Description, DisplayOrder) VALUES
    ('appointment_status', 'Scheduled', 'Scheduled', 1),
    ('appointment_status', 'Checked In', 'Checked In', 2),
    ('appointment_status', 'In Progress', 'In Progress', 3),
    ('appointment_status', 'Completed', 'Completed', 4),
    ('appointment_status', 'Cancelled', 'Cancelled', 5),
    ('appointment_status', 'No Show', 'No Show', 6),
    ('repair_status', 'Open', 'Open', 1),
    ('repair_status', 'In Progress', 'In Progress', 2),
    ('repair_status', 'Completed', 'Completed', 3),
    ('repair_status', 'Cancelled', 'Cancelled', 4),
    ('estimate_status', 'Draft', 'Draft', 1),
    ('estimate_status', 'Pending Approval', 'Pending Approval', 2),
    ('estimate_status', 'Approved', 'Approved', 3),
    ('estimate_status', 'Rejected', 'Rejected', 4),
    ('estimate_status', 'Expired', 'Expired', 5),
    ('estimate_status', 'Finalized', 'Finalized', 6),
    ('invoice_status', 'Draft', 'Draft', 1),
    ('invoice_status', 'Finalized', 'Finalized', 2),
    ('user_role', 'Service Advisor', 'Service Advisor', 1),
    ('user_role', 'Technician', 'Technician', 2),
    ('user_role', 'Manager', 'Manager', 3),
    ('active_status', '0', 'Inactive', 1),
    ('active_status', '1', 'Active', 2),
    ('repair_type', 'Oil Change', 'Oil Change', 1),
    ('repair_type', 'Brake Service', 'Brake Service', 2),
    ('repair_type', 'Ignition Service', 'Ignition Service', 3),
    ('repair_type', 'Filter Replacement', 'Filter Replacement', 4),
    ('repair_type', 'Tune-Up', 'Tune-Up', 5),
    ('repair_type', 'Diagnostic', 'Diagnostic', 6),
    ('repair_type', 'Tire Rotation', 'Tire Rotation', 7),
    ('repair_type', 'Battery Replacement', 'Battery Replacement', 8),
    ('repair_type', 'Scheduled Maintenance', 'Scheduled Maintenance', 9),
    ('audit_action', 'Create', 'Create', 1),
    ('audit_action', 'Update', 'Update', 2),
    ('audit_action', 'Delete', 'Delete', 3),
    ('audit_action', 'Cancel', 'Cancel', 4),
    ('audit_action', 'Complete', 'Complete', 5),
    ('audit_action', 'Status Change', 'Status Change', 6),
    ('audit_action', 'Technician Reassignment', 'Technician Reassignment', 7),
    ('audit_action', 'Reschedule', 'Reschedule', 8),
    ('audit_action', 'Approve', 'Approve', 9),
    ('audit_action', 'Reject', 'Reject', 10),
    ('audit_action', 'Finalize', 'Finalize', 11),
    ('audit_action', 'Inventory Adjustment', 'Inventory Adjustment', 12),
    ('audit_action', 'Reversal', 'Reversal', 13),
    ('audit_action', 'Rejected', 'Rejected', 14),
    ('audit_entity', 'Customer', 'Customer', 1),
    ('audit_entity', 'Vehicle', 'Vehicle', 2),
    ('audit_entity', 'Technician', 'Technician', 3),
    ('audit_entity', 'UserAccount', 'UserAccount', 4),
    ('audit_entity', 'Part', 'Part', 5),
    ('audit_entity', 'ServiceAppointment', 'ServiceAppointment', 6),
    ('audit_entity', 'Repair', 'Repair', 7),
    ('audit_entity', 'RepairEstimate', 'RepairEstimate', 8),
    ('audit_entity', 'EstimateLineItem', 'EstimateLineItem', 9),
    ('audit_entity', 'Invoice', 'Invoice', 10),
    ('audit_entity', 'InvoiceLineItem', 'InvoiceLineItem', 11),
    ('audit_entity', 'PartsUsage', 'PartsUsage', 12),
    ('audit_entity', 'IndicatorValue', 'IndicatorValue', 13),
    ('audit_entity', 'DatabasePrincipal', 'DatabasePrincipal', 14),
    ('audit_entity', 'PrincipalDelegation', 'PrincipalDelegation', 15),
    ('principal_type', 'Person', 'Person', 1),
    ('principal_type', 'Service', 'Service', 2),
    ('procedure_name', 'sp_CreateServiceAppointment', 'sp_CreateServiceAppointment', 1),
    ('procedure_name', 'sp_CompleteRepair', 'sp_CompleteRepair', 2),
    ('migration_status', 'applying', 'applying', 1),
    ('migration_status', 'applied', 'applied', 2),
    ('migration_status', 'failed', 'failed', 3);

-- Previously unconstrained legacy values are retained, not rewritten or discarded.
INSERT INTO IndicatorValue (IndicatorName, ValueCode, Description, DisplayOrder)
SELECT DISTINCT 'repair_type', t.`RepairType`, t.`RepairType`, 1000
FROM `Repair` t
WHERE NOT EXISTS (SELECT 1 FROM IndicatorValue iv
                  WHERE iv.IndicatorName = 'repair_type' AND iv.ValueCode = t.`RepairType`);

-- Previously unconstrained legacy values are retained, not rewritten or discarded.
INSERT INTO IndicatorValue (IndicatorName, ValueCode, Description, DisplayOrder)
SELECT DISTINCT 'audit_action', t.`Action`, t.`Action`, 1000
FROM `AuditLog` t
WHERE NOT EXISTS (SELECT 1 FROM IndicatorValue iv
                  WHERE iv.IndicatorName = 'audit_action' AND iv.ValueCode = t.`Action`);

-- Previously unconstrained legacy values are retained, not rewritten or discarded.
INSERT INTO IndicatorValue (IndicatorName, ValueCode, Description, DisplayOrder)
SELECT DISTINCT 'audit_entity', t.`AffectedEntity`, t.`AffectedEntity`, 1000
FROM `AuditLog` t
WHERE NOT EXISTS (SELECT 1 FROM IndicatorValue iv
                  WHERE iv.IndicatorName = 'audit_entity' AND iv.ValueCode = t.`AffectedEntity`);

DELIMITER //
CREATE PROCEDURE sp_ListIndicatorValues(IN p_IndicatorName VARCHAR(64))
READS SQL DATA
BEGIN
    IF p_IndicatorName IS NULL OR NOT EXISTS (
        SELECT 1 FROM IndicatorValue WHERE IndicatorName = p_IndicatorName
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown indicator domain';
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
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_Message;
    END IF;
END //

CREATE FUNCTION fn_IndicatorDescription(p_IndicatorName VARCHAR(64), p_Code VARCHAR(100))
RETURNS VARCHAR(255) READS SQL DATA
BEGIN
    RETURN COALESCE((SELECT Description FROM IndicatorValue
                    WHERE IndicatorName = p_IndicatorName AND ValueCode = p_Code),
                    CONCAT('[INVALID: ', COALESCE(p_Code, 'NULL'), ']'));
END //

-- Auto-named baseline CHECK names vary in letter case between MySQL platforms.
CREATE PROCEDURE sp_RemoveBaselineDomainCheck(IN p_Table VARCHAR(64))
BEGIN
    DECLARE v_Name VARCHAR(64);
    SELECT CONSTRAINT_NAME INTO v_Name FROM information_schema.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE() AND LOWER(TABLE_NAME) = LOWER(p_Table)
      AND CONSTRAINT_TYPE = 'CHECK' AND LOWER(CONSTRAINT_NAME) = CONCAT(LOWER(p_Table), '_chk_1');
    IF v_Name IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Expected baseline domain CHECK was not found';
    END IF;
    SET @domain_ddl = CONCAT('ALTER TABLE `', p_Table, '` DROP CHECK `', v_Name, '`');
    PREPARE domain_stmt FROM @domain_ddl;
    EXECUTE domain_stmt;
    DEALLOCATE PREPARE domain_stmt;
END //
DELIMITER ;

CALL sp_RemoveBaselineDomainCheck('UserAccount');

CALL sp_RemoveBaselineDomainCheck('ServiceAppointment');

CALL sp_RemoveBaselineDomainCheck('Repair');

CALL sp_RemoveBaselineDomainCheck('RepairEstimate');

CALL sp_RemoveBaselineDomainCheck('Invoice');

DROP PROCEDURE sp_RemoveBaselineDomainCheck;

ALTER TABLE `UserAccount`
    ADD COLUMN RoleIndicator VARCHAR(64) GENERATED ALWAYS AS ('user_role') STORED,
    ADD CONSTRAINT fk_UserAccount_RoleIndicator FOREIGN KEY (RoleIndicator, RoleType) REFERENCES IndicatorValue (IndicatorName, ValueCode);

ALTER TABLE `ServiceAppointment`
    ADD COLUMN StatusIndicator VARCHAR(64) GENERATED ALWAYS AS ('appointment_status') STORED,
    ADD CONSTRAINT fk_ServiceAppointment_StatusIndicator FOREIGN KEY (StatusIndicator, Status) REFERENCES IndicatorValue (IndicatorName, ValueCode);

ALTER TABLE `Repair`
    ADD COLUMN StatusIndicator VARCHAR(64) GENERATED ALWAYS AS ('repair_status') STORED,
    ADD CONSTRAINT fk_Repair_StatusIndicator FOREIGN KEY (StatusIndicator, Status) REFERENCES IndicatorValue (IndicatorName, ValueCode),
    ADD COLUMN TypeIndicator VARCHAR(64) GENERATED ALWAYS AS ('repair_type') STORED,
    ADD CONSTRAINT fk_Repair_TypeIndicator FOREIGN KEY (TypeIndicator, RepairType) REFERENCES IndicatorValue (IndicatorName, ValueCode);

ALTER TABLE `RepairEstimate`
    ADD COLUMN StatusIndicator VARCHAR(64) GENERATED ALWAYS AS ('estimate_status') STORED,
    ADD CONSTRAINT fk_RepairEstimate_StatusIndicator FOREIGN KEY (StatusIndicator, Status) REFERENCES IndicatorValue (IndicatorName, ValueCode);

ALTER TABLE `Invoice`
    ADD COLUMN StatusIndicator VARCHAR(64) GENERATED ALWAYS AS ('invoice_status') STORED,
    ADD CONSTRAINT fk_Invoice_StatusIndicator FOREIGN KEY (StatusIndicator, Status) REFERENCES IndicatorValue (IndicatorName, ValueCode);

ALTER TABLE `Technician`
    ADD COLUMN ActiveIndicator VARCHAR(64) GENERATED ALWAYS AS ('active_status') STORED,
    ADD COLUMN ActiveCode VARCHAR(100) GENERATED ALWAYS AS (CAST(ActiveStatus AS CHAR)) STORED,
    ADD CONSTRAINT fk_Technician_ActiveIndicator FOREIGN KEY (ActiveIndicator, ActiveCode) REFERENCES IndicatorValue (IndicatorName, ValueCode);

ALTER TABLE `Part`
    ADD COLUMN ActiveIndicator VARCHAR(64) GENERATED ALWAYS AS ('active_status') STORED,
    ADD COLUMN ActiveCode VARCHAR(100) GENERATED ALWAYS AS (CAST(ActiveStatus AS CHAR)) STORED,
    ADD CONSTRAINT fk_Part_ActiveIndicator FOREIGN KEY (ActiveIndicator, ActiveCode) REFERENCES IndicatorValue (IndicatorName, ValueCode);

ALTER TABLE `AuditLog`
    ADD COLUMN ActionIndicator VARCHAR(64) GENERATED ALWAYS AS ('audit_action') STORED,
    ADD CONSTRAINT fk_AuditLog_ActionIndicator FOREIGN KEY (ActionIndicator, Action) REFERENCES IndicatorValue (IndicatorName, ValueCode),
    ADD COLUMN EntityIndicator VARCHAR(64) GENERATED ALWAYS AS ('audit_entity') STORED,
    ADD CONSTRAINT fk_AuditLog_EntityIndicator FOREIGN KEY (EntityIndicator, AffectedEntity) REFERENCES IndicatorValue (IndicatorName, ValueCode);

DELIMITER //

CREATE TRIGGER trg_UserAccount_Indicator_bi
BEFORE INSERT ON `UserAccount` FOR EACH ROW
BEGIN
    CALL sp_ValidateIndicator('user_role', NEW.RoleType);
END //

CREATE TRIGGER trg_UserAccount_Indicator_bu
BEFORE UPDATE ON `UserAccount` FOR EACH ROW
BEGIN
    CALL sp_ValidateIndicator('user_role', NEW.RoleType);
END //

CREATE TRIGGER trg_ServiceAppointment_Indicator_bi
BEFORE INSERT ON `ServiceAppointment` FOR EACH ROW
BEGIN
    CALL sp_ValidateIndicator('appointment_status', NEW.Status);
END //

CREATE TRIGGER trg_ServiceAppointment_Indicator_bu
BEFORE UPDATE ON `ServiceAppointment` FOR EACH ROW
PRECEDES trg_ServiceAppointment_Status_Validate_bu
BEGIN
    CALL sp_ValidateIndicator('appointment_status', NEW.Status);
END //

CREATE TRIGGER trg_Repair_Indicator_bi
BEFORE INSERT ON `Repair` FOR EACH ROW
PRECEDES trg_Repair_Status_Validate_bi
BEGIN
    CALL sp_ValidateIndicator('repair_status', NEW.Status);
    CALL sp_ValidateIndicator('repair_type', NEW.RepairType);
END //

CREATE TRIGGER trg_Repair_Indicator_bu
BEFORE UPDATE ON `Repair` FOR EACH ROW
PRECEDES trg_Repair_Status_Validate_bu
BEGIN
    CALL sp_ValidateIndicator('repair_status', NEW.Status);
    CALL sp_ValidateIndicator('repair_type', NEW.RepairType);
END //

CREATE TRIGGER trg_RepairEstimate_Indicator_bi
BEFORE INSERT ON `RepairEstimate` FOR EACH ROW
PRECEDES trg_RepairEstimate_Validate_bi
BEGIN
    CALL sp_ValidateIndicator('estimate_status', NEW.Status);
END //

CREATE TRIGGER trg_RepairEstimate_Indicator_bu
BEFORE UPDATE ON `RepairEstimate` FOR EACH ROW
PRECEDES trg_RepairEstimate_Validate_bu
BEGIN
    CALL sp_ValidateIndicator('estimate_status', NEW.Status);
END //

CREATE TRIGGER trg_Invoice_Indicator_bi
BEFORE INSERT ON `Invoice` FOR EACH ROW
PRECEDES trg_Invoice_Validate_bi
BEGIN
    CALL sp_ValidateIndicator('invoice_status', NEW.Status);
END //

CREATE TRIGGER trg_Invoice_Indicator_bu
BEFORE UPDATE ON `Invoice` FOR EACH ROW
PRECEDES trg_Invoice_Validate_bu
BEGIN
    CALL sp_ValidateIndicator('invoice_status', NEW.Status);
END //

CREATE TRIGGER trg_Technician_Indicator_bi
BEFORE INSERT ON `Technician` FOR EACH ROW
BEGIN
    CALL sp_ValidateIndicator('active_status', CAST(NEW.ActiveStatus AS CHAR));
END //

CREATE TRIGGER trg_Technician_Indicator_bu
BEFORE UPDATE ON `Technician` FOR EACH ROW
BEGIN
    CALL sp_ValidateIndicator('active_status', CAST(NEW.ActiveStatus AS CHAR));
END //

CREATE TRIGGER trg_Part_Indicator_bi
BEFORE INSERT ON `Part` FOR EACH ROW
BEGIN
    CALL sp_ValidateIndicator('active_status', CAST(NEW.ActiveStatus AS CHAR));
END //

CREATE TRIGGER trg_Part_Indicator_bu
BEFORE UPDATE ON `Part` FOR EACH ROW
BEGIN
    CALL sp_ValidateIndicator('active_status', CAST(NEW.ActiveStatus AS CHAR));
END //

CREATE TRIGGER trg_AuditLog_Indicator_bi
BEFORE INSERT ON `AuditLog` FOR EACH ROW
BEGIN
    CALL sp_ValidateIndicator('audit_action', NEW.Action);
    CALL sp_ValidateIndicator('audit_entity', NEW.AffectedEntity);
END //

CREATE TRIGGER trg_AuditLog_Indicator_bu
BEFORE UPDATE ON `AuditLog` FOR EACH ROW
BEGIN
    CALL sp_ValidateIndicator('audit_action', NEW.Action);
    CALL sp_ValidateIndicator('audit_entity', NEW.AffectedEntity);
END //

-- The old invoice validator relied on its two-value CHECK for this rule.
-- Reference membership must not accidentally introduce new lifecycle edges.
CREATE TRIGGER trg_Invoice_TransitionGuard_bu
BEFORE UPDATE ON Invoice FOR EACH ROW PRECEDES trg_Invoice_Validate_bu
BEGIN
    IF NOT (OLD.Status <=> NEW.Status)
       AND NOT (OLD.Status = 'Draft' AND NEW.Status = 'Finalized') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid invoice status transition';
    END IF;
END //

CREATE PROCEDURE sp_GrantReferenceReaders()
BEGIN
    DECLARE v_Done BOOLEAN DEFAULT FALSE;
    DECLARE v_User VARCHAR(32);
    DECLARE v_Host VARCHAR(255);
    DECLARE principals CURSOR FOR
        SELECT DISTINCT User, Host FROM mysql.tables_priv
        WHERE Db = DATABASE() AND User IN ('role_service_advisor', 'role_technician', 'role_manager');
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_Done = TRUE;
    OPEN principals;
    grants_loop: LOOP
        FETCH principals INTO v_User, v_Host;
        IF v_Done THEN LEAVE grants_loop; END IF;
        SET @grant_sql = CONCAT('GRANT EXECUTE ON PROCEDURE `', DATABASE(),
            '`.sp_ListIndicatorValues TO ', QUOTE(v_User), '@', QUOTE(v_Host));
        PREPARE grant_stmt FROM @grant_sql; EXECUTE grant_stmt; DEALLOCATE PREPARE grant_stmt;
    END LOOP;
    CLOSE principals;
END //
DELIMITER ;
CALL sp_GrantReferenceReaders();
DROP PROCEDURE sp_GrantReferenceReaders;

-- Add descriptions without removing or renaming any existing report columns.
CREATE OR REPLACE VIEW vw_RepairReferenceLabels AS
SELECT RepairID, RepairType,
       fn_IndicatorDescription('repair_type', RepairType) AS RepairTypeDescription,
       Status, fn_IndicatorDescription('repair_status', Status) AS StatusDescription
FROM Repair;

-- Existing report contracts retain their original columns and gain metadata labels.
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
