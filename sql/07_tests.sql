-- Vehicle Service and Maintenance Management System
-- 07_tests.sql
-- Automated test plan (TDD section 13).
--
-- Run after a fresh build: 01_schema -> ... -> 06_sample_data -> 07_tests.
--
-- T-11 (role privileges) must be run manually from the demo accounts; see the
-- instructions in section 4. T-12 was removed as redundant with T-15 and T-16.
USE vehicle_service_maintenance;

SET
    @app_user_id = NULL;

SET
    @adj_reason = NULL;

-- =====================================================================
-- 0. TEST HARNESS
-- =====================================================================
DROP TEMPORARY TABLE IF EXISTS TestResult;
CREATE TEMPORARY TABLE TestResult (
    RunOrder    INT AUTO_INCREMENT PRIMARY KEY,
    TestID      VARCHAR(20)   NOT NULL,
    Description VARCHAR(255)  NOT NULL,
    Result      VARCHAR(4)    NOT NULL,
    Detail      VARCHAR(1000) NULL
);

DELIMITER //
DROP PROCEDURE IF EXISTS tst_ExpectError //
CREATE PROCEDURE tst_ExpectError (
    IN p_TestID VARCHAR(20), -- test identifier 
    IN p_Description VARCHAR(255), -- what is being tested
    IN p_Sql TEXT, -- SQL statement that should be rejected
    IN p_ExpectedMessage VARCHAR(255) -- expected error message
) BEGIN DECLARE v_Error TINYINT DEFAULT 0;

DECLARE v_Message TEXT DEFAULT NULL;

DECLARE CONTINUE
HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_Message = MESSAGE_TEXT;

SET
    v_Error = 1;

END;

SET
    @tst_sql = p_Sql;

PREPARE tst_stmt
FROM
    @tst_sql;

IF v_Error = 0 THEN
EXECUTE tst_stmt;

DEALLOCATE PREPARE tst_stmt;

END IF;

INSERT INTO
    TestResult (TestID, Description, Result, Detail)
VALUES
    (
        p_TestID,
        p_Description,
        IF(
            v_Error = 1
            AND v_Message LIKE CONCAT('%', p_ExpectedMessage, '%'),
            'PASS',
            'FAIL'
        ),
        IF(
            v_Error = 1,
            CONCAT('Rejected: ', v_Message),
            'No error was raised'
        )
    );

END //
DROP PROCEDURE IF EXISTS tst_ExpectSuccess //
CREATE PROCEDURE tst_ExpectSuccess (
    IN p_TestID VARCHAR(20), -- test identifier
    IN p_Description VARCHAR(255), -- what is being tested
    IN p_Sql TEXT -- SQL statement that should succeed
) BEGIN DECLARE v_Error TINYINT DEFAULT 0;

DECLARE v_Message TEXT DEFAULT NULL;

DECLARE CONTINUE
HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_Message = MESSAGE_TEXT;

SET
    v_Error = 1;

END;

SET
    @tst_sql = p_Sql;

PREPARE tst_stmt
FROM
    @tst_sql;

IF v_Error = 0 THEN
EXECUTE tst_stmt;

DEALLOCATE PREPARE tst_stmt;

END IF;

-- Only failures are recorded here; the follow-up assertions record PASS
IF v_Error = 1 THEN
INSERT INTO
    TestResult (TestID, Description, Result, Detail)
VALUES
    (
        p_TestID,
        p_Description,
        'FAIL',
        CONCAT('Unexpected error: ', v_Message)
    );

END IF;

END //
DROP PROCEDURE IF EXISTS tst_Assert //
CREATE PROCEDURE tst_Assert (
    IN p_TestID VARCHAR(20),
    IN p_Description VARCHAR(255),
    IN p_Passed BOOLEAN,
    IN p_Detail VARCHAR(1000)
) BEGIN
INSERT INTO
    TestResult (TestID, Description, Result, Detail)
VALUES
    (
        p_TestID,
        p_Description,
        IF(p_Passed, 'PASS', 'FAIL'),
        p_Detail
    );

END // 

-- Runs a statement and saves its error message in @tst_captured without
-- writing to TestResult. Used inside T-09's transaction, so nothing it
-- records is lost when that transaction is rolled back.
DROP PROCEDURE IF EXISTS tst_CaptureError //
CREATE PROCEDURE tst_CaptureError(IN p_Sql TEXT)
BEGIN
    DECLARE v_Message TEXT DEFAULT NULL;

    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_Message = MESSAGE_TEXT;
    END;

    SET @tst_sql = p_Sql;
    PREPARE tst_stmt FROM @tst_sql;
    EXECUTE tst_stmt;
    DEALLOCATE PREPARE tst_stmt;

    SET @tst_captured = v_Message;
END //

DELIMITER ;

-- Fixed future time used by the appointment tests (T-03, T-04, T-05, FR-15)
SET
    @t03 = TIMESTAMP(DATE_ADD(CURDATE(), INTERVAL 60 DAY), '08:00:00');

-- =====================================================================
-- 1. REPORTS AND READ-ONLY CHECKS (run first, before any data changes)
-- =====================================================================
-- T-14 / RQ-01: Daily Service Appointments
SET
    @c = (
        SELECT
            COUNT(*)
        FROM
            ServiceAppointment
        WHERE
            AppointmentDateTime >= '2026-10-15'
            AND AppointmentDateTime < '2026-10-15' + INTERVAL 1 DAY
    );

CALL tst_Assert (
    'T-14',
    'RQ-01 returns the appointments for 2026-10-15',
    @c = 3,
    CONCAT('Appointments found: ', @c, ' (expected 3)')
);

-- T-15 / RQ-02: Vehicle Service History
SET
    @c = (
        SELECT
            COUNT(DISTINCT RepairID)
        FROM
            vw_VehicleServiceHistory
        WHERE
            VehicleID = 1
    );

CALL tst_Assert (
    'T-15',
    'RQ-02 returns completed repairs for vehicle 1',
    @c = 2,
    CONCAT('Completed repairs found: ', @c, ' (expected 2)')
);

-- T-16 / RQ-05: Shop Workload
SET
    @ben = (
        SELECT
            COUNT(*)
        FROM
            vw_TechnicianWorkload
        WHERE
            TechnicianID = 1
            AND AppointmentStatus IN ('Scheduled', 'Checked In', 'In Progress')
    );

SET
    @carla = (
        SELECT
            COUNT(*)
        FROM
            vw_TechnicianWorkload
        WHERE
            TechnicianID = 2
            AND AppointmentStatus IN ('Scheduled', 'Checked In', 'In Progress')
    );

SET
    @dan = (
        SELECT
            COUNT(*)
        FROM
            vw_TechnicianWorkload
        WHERE
            TechnicianID = 3
            AND AppointmentID IS NULL
    );

CALL tst_Assert (
    'T-16',
    'RQ-05 shows active appointments per technician, including idle ones',
    @ben = 2
    AND @carla = 3
    AND @dan = 1,
    CONCAT(
        'Ben: ',
        @ben,
        ' (2), Carla: ',
        @carla,
        ' (3), Dan listed with no appointments: ',
        @dan,
        ' (1)'
    )
);

-- T-17 / RQ-06: Parts Revenue
SET
    @rev = (
        SELECT
            SUM(pu.QuantityUsed * pu.UnitSellingPriceAtTimeOfUse)
        FROM
            PartsUsage pu
            JOIN Repair r ON pu.RepairID = r.RepairID
        WHERE
            r.Status = 'Completed'
    );

CALL tst_Assert (
    'T-17',
    'RQ-06 calculates parts revenue from prices at time of use',
    @rev = 272.91,
    CONCAT(
        'Total parts revenue: ',
        @rev,
        ' (expected 272.91)'
    )
);

-- RQ-04: Low Parts Inventory (supporting check)
SET
    @c = (
        SELECT
            COUNT(*)
        FROM
            Part
        WHERE
            QuantityOnHand < MinimumInventoryLevel
    );

CALL tst_Assert (
    'T-34',
    'Low inventory report lists Brake Rotor and Spark Plug',
    @c = 2,
    CONCAT('Parts below minimum: ', @c, ' (expected 2)')
);

-- =====================================================================
-- 2. OPERATIONS THAT MUST BE REJECTED (data must remain unchanged)
-- =====================================================================
SET
    @audit_before_rejections = (
        SELECT
            COUNT(*)
        FROM
            AuditLog
    );

SET
    @app_user_id = 1;

-- T-02 / FR-05, BR-02: vehicle for a nonexistent customer
CALL tst_ExpectError (
    'T-02',
    'Vehicle with a nonexistent CustomerID is rejected',
    'INSERT INTO Vehicle (CustomerID, VIN, Make, Model, `Year`) VALUES (999, ''TESTVIN0000000999'', ''Test'', ''Car'', 2020)',
    'foreign key constraint fails'
);

-- T-35 / BR-01: duplicate primary key
CALL tst_ExpectError('T-35', 'Duplicate primary key is rejected',
    'INSERT INTO Customer (CustomerID, Name, Phone, Email) VALUES (1, ''Duplicate Key'', ''555-0000'', NULL)',
    'Duplicate entry');

-- T-36 / FR-01: duplicate VIN (UNIQUE)
CALL tst_ExpectError('T-36', 'Duplicate VIN is rejected',
    'INSERT INTO Vehicle (CustomerID, VIN, Make, Model, `Year`) VALUES (1, ''1HGCV1F34LA012345'', ''Honda'', ''Civic'', 2022)',
    'Duplicate entry');

-- T-37 / FR-01: required value missing (NOT NULL)
CALL tst_ExpectError('T-37', 'Customer without a name is rejected',
    'INSERT INTO Customer (Name, Phone, Email) VALUES (NULL, ''555-0000'', NULL)',
    'cannot be null');

-- T-06 / BR-05: invalid status value
CALL tst_ExpectError('T-06', 'Appointment with an invalid status value is rejected',
    'INSERT INTO ServiceAppointment (VehicleID, TechnicianID, CreatedByUserID, AppointmentDateTime, Status, ServiceRequestDescription, EstimatedDuration, CreationTimestamp) VALUES (1, 1, 2, NOW(), ''Pending'', ''Invalid status test'', 60, NOW())',
    'Check constraint');

-- T-13 / FR-18, SEC-01: finalized invoice cannot be updated or deleted
CALL tst_ExpectError (
    'T-13a',
    'Finalized invoice cannot be updated',
    'UPDATE Invoice SET TotalAmount = 0 WHERE InvoiceID = 1',
    'Finalized invoices cannot be modified'
);

CALL tst_ExpectError (
    'T-13b',
    'Finalized invoice cannot be deleted',
    'DELETE FROM Invoice WHERE InvoiceID = 1',
    'Finalized invoices cannot be deleted'
);

-- T-19 / FR-19: completed repair cannot go back to In Progress
CALL tst_ExpectError (
    'T-19',
    'Completed repair cannot change back to In Progress',
    'UPDATE Repair SET Status = ''In Progress'' WHERE RepairID = 1',
    'Completed or cancelled repairs cannot be modified'
);

-- T-20 / FR-18: finalized invoice line items are locked
CALL tst_ExpectError (
    'T-20a',
    'Cannot add a line item to a finalized invoice',
    'INSERT INTO InvoiceLineItem (InvoiceID, Description, Quantity, UnitPrice, LineTotal) VALUES (1, ''Extra charge'', 1, 1.00, 1.00)',
    'Cannot add line items to a finalized invoice'
);

CALL tst_ExpectError (
    'T-20b',
    'Cannot delete a line item of a finalized invoice',
    'DELETE FROM InvoiceLineItem WHERE InvoiceID = 1 LIMIT 1',
    'Cannot delete line items of a finalized invoice'
);

-- T-21 / FR-18: finalized estimate and its line items are locked
CALL tst_ExpectError (
    'T-21a',
    'Finalized estimate cannot be updated',
    'UPDATE RepairEstimate SET TotalAmount = 0 WHERE EstimateID = 1',
    'Finalized estimates cannot be modified'
);

CALL tst_ExpectError (
    'T-21b',
    'Line item of a finalized estimate cannot be updated',
    'UPDATE EstimateLineItem SET Quantity = 2, LineTotal = 79.98 WHERE EstimateID = 1 AND LineNumber = 1',
    'Cannot modify line items of a finalized estimate'
);

-- T-22 / BR-07, SEC-03: audit rows are append-only
CALL tst_ExpectError (
    'T-22a',
    'Audit record cannot be updated',
    'UPDATE AuditLog SET Action = ''Tampered'' WHERE AuditLogID = 1',
    'Audit records cannot be modified'
);

CALL tst_ExpectError (
    'T-22b',
    'Audit record cannot be deleted',
    'DELETE FROM AuditLog WHERE AuditLogID = 1',
    'Audit records cannot be deleted'
);

-- T-24 / FR-14, FR-19: completed appointment cannot go back to Scheduled
CALL tst_ExpectError (
    'T-24',
    'Completed appointment cannot change back to Scheduled',
    'UPDATE ServiceAppointment SET Status = ''Scheduled'' WHERE AppointmentID = 1',
    'no-show appointments cannot be modified'
);

-- T-25 / FR-08: audited write without an acting user
SET
    @app_user_id = NULL;

CALL tst_ExpectError (
    'T-25',
    'Audited write without @app_user_id is rejected',
    'UPDATE ServiceAppointment SET EstimatedDuration = 75 WHERE AppointmentID = 8',
    'Acting user not set'
);

-- T-27 / SEC-01: non-manager cannot approve an estimate
SET
    @app_user_id = 2;

CALL tst_ExpectError (
    'T-27',
    'Service Advisor cannot approve an estimate',
    'UPDATE RepairEstimate SET Status = ''Approved'', ApprovedByUserID = 2 WHERE EstimateID = 3',
    'Estimates must be approved or rejected by a Manager'
);

-- T-29 / SEC-02: technician cannot change another technician's repair
SET
    @app_user_id = 3;

CALL tst_ExpectError (
    'T-29',
    'Technician cannot start a repair assigned to another technician',
    'UPDATE Repair SET Status = ''In Progress'' WHERE RepairID = 8',
    'Technicians may only update their own assigned repairs'
);

-- T-38 / FR-03, FR-20: a repair cannot be marked Completed without sp_CompleteRepair
SET @app_user_id = 4;   -- Carla, assigned to repair 7
CALL tst_ExpectError('T-38', 'Repair cannot be completed by a direct status update',
    'UPDATE Repair SET Status = ''Completed'' WHERE RepairID = 7',
    'chk_Repair_Completion');

-- T-28a / FR-13: inventory adjustment without a reason
SET
    @app_user_id = 1;

SET
    @adj_reason = NULL;

CALL tst_ExpectError (
    'T-28a',
    'Inventory adjustment without @adj_reason is rejected',
    'UPDATE Part SET QuantityOnHand = QuantityOnHand + 5 WHERE PartID = 1',
    'Inventory adjustments require @adj_reason'
);

-- T-07 / FR-12, BR-10: more parts than inventory allows
SET
    @p3_before = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 3
    );

CALL tst_ExpectError (
    'T-07',
    'Parts usage exceeding inventory is rejected',
    'CALL sp_CompleteRepair(6, 1, 3, ''[{"partId": 3, "qty": 5}]'')',
    'Insufficient parts inventory'
);

SET
    @p3_after = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 3
    );

CALL tst_Assert (
    'T-07',
    'Inventory unchanged after rejected parts usage',
    @p3_after = @p3_before,
    CONCAT(
        'Brake Rotor quantity: ',
        @p3_after,
        ' (expected ',
        @p3_before,
        ')'
    )
);

-- T-30 / FR-12, BR-10: invalid quantity hidden by a duplicate entry
CALL tst_ExpectError (
    'T-30',
    'Negative quantity offset by a duplicate entry is rejected',
    'CALL sp_CompleteRepair(6, 1, 3, ''[{"partId": 2, "qty": -2}, {"partId": 2, "qty": 5}]'')',
    'positive integer qty'
);

-- T-31 / SEC-02, FR-03: service advisor cannot be the recording user
CALL tst_ExpectError (
    'T-31',
    'Service Advisor cannot be recorded as completing a repair',
    'CALL sp_CompleteRepair(7, 2, 2, ''[{"partId": 4, "qty": 1}]'')',
    'Recording user is not authorized'
);

-- T-26 / FR-20, BR-08: second part short -> entire procedure rolls back
SET
    @p4_before = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 4
    );

SET
    @p5_before = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 5
    );

CALL tst_ExpectError (
    'T-26',
    'Repair with one part short is rejected',
    'CALL sp_CompleteRepair(7, 2, 4, ''[{"partId": 4, "qty": 1}, {"partId": 5, "qty": 4}]'')',
    'Insufficient parts inventory'
);

SET
    @p4_after = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 4
    );

SET
    @p5_after = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 5
    );

SET
    @usage = (
        SELECT
            COUNT(*)
        FROM
            PartsUsage
        WHERE
            RepairID = 7
    );

SET
    @status = (
        SELECT
            Status
        FROM
            Repair
        WHERE
            RepairID = 7
    );

CALL tst_Assert (
    'T-26',
    'No parts recorded, inventory unchanged, repair not completed',
    @p4_after = @p4_before
    AND @p5_after = @p5_before
    AND @usage = 0
    AND @status = 'In Progress',
    CONCAT(
        'Air filter: ',
        @p4_after,
        '/',
        @p4_before,
        ', Spark plug: ',
        @p5_after,
        '/',
        @p5_before,
        ', PartsUsage rows: ',
        @usage,
        ', Repair status: ',
        @status
    )
);

-- FR-15: vehicle must belong to the selected customer
CALL tst_ExpectError (
    'T-32',
    'Appointment for a vehicle owned by another customer is rejected',
    'CALL sp_CreateServiceAppointment(2, 1, 1, 2, @t03 + INTERVAL 1 DAY, ''Ownership mismatch test'', 60)',
    'Vehicle does not belong to the customer'
);

-- ---------------------------------------------------------------------
-- Boundary tests: values just outside the allowed range are rejected
-- ---------------------------------------------------------------------
-- T-39 / FR-02: duration one minute over the maximum (1440 = 24 hours)
CALL tst_ExpectError('T-39', 'Appointment duration of 1441 minutes is rejected',
    'CALL sp_CreateServiceAppointment(1, 1, 2, 2, @t03 + INTERVAL 5 DAY, ''Boundary test'', 1441)',
    'Invalid appointment information');

-- T-40 / FR-02: duration of zero (minimum is 1)
CALL tst_ExpectError('T-40', 'Appointment duration of 0 minutes is rejected',
    'CALL sp_CreateServiceAppointment(1, 1, 2, 2, @t03 + INTERVAL 5 DAY, ''Boundary test'', 0)',
    'Invalid appointment information');

-- T-41 / FR-12, BR-10: part quantity of zero (minimum is 1)
CALL tst_ExpectError('T-41', 'Part quantity of 0 is rejected',
    'CALL sp_CompleteRepair(6, 1, 3, ''[{"partId": 2, "qty": 0}]'')',
    'positive integer qty');

-- T-09 / FR-20, BR-08: a multi-step repair transaction fails at its last step.
-- Mirrors sp_CompleteRepair's steps: record usage, reduce inventory, then
-- update the repair. The final step fails, and ROLLBACK undoes the earlier
-- steps, including the audit rows the triggers wrote.
SET
    @app_user_id = 3;

SET
    @adj_reason = 'T-09 rollback test';

SET
    @p2_before = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 2
    );

START TRANSACTION;

INSERT INTO
    PartsUsage (
        RepairID,
        PartID,
        RecordedByUserID,
        QuantityUsed,
        UnitSellingPriceAtTimeOfUse,
        UnitCostAtTimeOfUse,
        RecordedDateTime
    )
VALUES
    (6, 2, 3, 1, 49.99, 22.00, NOW());

UPDATE Part
SET
    QuantityOnHand = QuantityOnHand - 1
WHERE
    PartID = 2;

CALL tst_CaptureError('UPDATE Repair SET Status = ''Open'' WHERE RepairID = 6');
ROLLBACK;

CALL tst_Assert('T-09', 'Final step of a repair transaction fails',
    @tst_captured LIKE '%Invalid repair status transition%',
    CONCAT('Rejected: ', COALESCE(@tst_captured, 'No error was raised')));

SET
    @adj_reason = NULL;

SET
    @p2_after = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 2
    );

SET
    @usage = (
        SELECT
            COUNT(*)
        FROM
            PartsUsage
        WHERE
            RepairID = 6
    );

SET
    @status = (
        SELECT
            Status
        FROM
            Repair
        WHERE
            RepairID = 6
    );

CALL tst_Assert (
    'T-09',
    'Rollback removed the earlier steps of the transaction',
    @p2_after = @p2_before
    AND @usage = 0
    AND @status = 'In Progress',
    CONCAT(
        'Brake pads: ',
        @p2_after,
        '/',
        @p2_before,
        ', PartsUsage rows: ',
        @usage,
        ', Repair status: ',
        @status
    )
);

-- No rejected operation may leave audit rows behind
SET
    @audit_after_rejections = (
        SELECT
            COUNT(*)
        FROM
            AuditLog
    );

CALL tst_Assert (
    'T-33',
    'Rejected and rolled-back operations wrote no audit rows',
    @audit_after_rejections = @audit_before_rejections,
    CONCAT(
        'Audit rows before: ',
        @audit_before_rejections,
        ', after: ',
        @audit_after_rejections
    )
);

-- =====================================================================
-- 3. OPERATIONS THAT MUST SUCCEED (these change data permanently)
-- =====================================================================
-- T-01 / FR-01: insert a customer and vehicle
CALL tst_ExpectSuccess (
    'T-01',
    'Insert customer',
    'INSERT INTO Customer (CustomerID, Name, Phone, Email) VALUES (100, ''Test Customer'', ''555-0999'', ''test.customer@example.com'')'
);

CALL tst_ExpectSuccess (
    'T-01',
    'Insert vehicle',
    'INSERT INTO Vehicle (VehicleID, CustomerID, VIN, Make, Model, `Year`) VALUES (100, 100, ''TESTVIN0000000100'', ''Subaru'', ''Outback'', 2022)'
);

SET
    @c = (
        SELECT
            COUNT(*)
        FROM
            Vehicle
        WHERE
            VehicleID = 100
            AND CustomerID = 100
    );

CALL tst_Assert (
    'T-01',
    'Customer and vehicle inserted; vehicle references the customer',
    @c = 1,
    CONCAT('Matching vehicle rows: ', @c, ' (expected 1)')
);

-- T-03 / FR-02: create a valid appointment through the procedure
CALL tst_ExpectSuccess (
    'T-03',
    'Create appointment through sp_CreateServiceAppointment',
    'CALL sp_CreateServiceAppointment(1, 5, 1, 2, @t03, ''Test: 30,000-mile service'', 90)'
);

SET
    @c = (
        SELECT
            COUNT(*)
        FROM
            ServiceAppointment
        WHERE
            VehicleID = 5
            AND TechnicianID = 1
            AND CreatedByUserID = 2
            AND AppointmentDateTime = @t03
            AND Status = 'Scheduled'
    );

CALL tst_Assert (
    'T-03',
    'Appointment created as Scheduled with correct vehicle, technician, and user',
    @c = 1,
    CONCAT('Matching appointments: ', @c, ' (expected 1)')
);

-- T-04 / BR-04: overlapping appointment for the same vehicle
CALL tst_ExpectError (
    'T-04',
    'Overlapping appointment for the same vehicle is rejected',
    'CALL sp_CreateServiceAppointment(1, 5, 2, 2, @t03 + INTERVAL 30 MINUTE, ''Duplicate test'', 60)',
    'Vehicle already has a conflicting appointment'
);

-- T-05 / FR-16, BR-09: overlapping appointment for the same technician
CALL tst_ExpectError (
    'T-05',
    'Overlapping appointment for the same technician is rejected',
    'CALL sp_CreateServiceAppointment(2, 2, 1, 2, @t03 + INTERVAL 30 MINUTE, ''Technician conflict test'', 60)',
    'Technician already has a conflicting appointment'
);

-- ---------------------------------------------------------------------
-- Boundary tests: values exactly at the edge of the allowed range succeed
-- ---------------------------------------------------------------------
-- T-42 / FR-02: minimum duration (1 minute) is accepted
CALL tst_ExpectSuccess('T-42', 'Create appointment with a 1-minute duration',
    'CALL sp_CreateServiceAppointment(1, 1, 2, 2, @t03 + INTERVAL 2 DAY, ''Boundary test: 1 minute'', 1)');

-- 1 if the procedure worked 
SET @c = (SELECT COUNT(*) FROM ServiceAppointment
          WHERE VehicleID = 1 AND AppointmentDateTime = @t03 + INTERVAL 2 DAY
            AND EstimatedDuration = 1);

CALL tst_Assert('T-42', 'Appointment with a 1-minute duration was created',
    @c = 1, CONCAT('Matching appointments: ', @c, ' (expected 1)'));

-- T-43 / FR-02: maximum duration (1440 minutes) is accepted
CALL tst_ExpectSuccess('T-43', 'Create appointment with a 1440-minute duration',
    'CALL sp_CreateServiceAppointment(1, 1, 2, 2, @t03 + INTERVAL 3 DAY, ''Boundary test: 24 hours'', 1440)');

SET @c = (SELECT COUNT(*) FROM ServiceAppointment
          WHERE VehicleID = 1 AND AppointmentDateTime = @t03 + INTERVAL 3 DAY
            AND EstimatedDuration = 1440);

CALL tst_Assert('T-43', 'Appointment with a 1440-minute duration was created',
    @c = 1, CONCAT('Matching appointments: ', @c, ' (expected 1)'));

-- T-44 / BR-04, BR-09: one minute of overlap is still a conflict.
-- T-03 booked vehicle 5 with Ben from @t03 for 90 minutes.
CALL tst_ExpectError('T-44', 'Appointment starting 1 minute before the previous one ends is rejected',
    'CALL sp_CreateServiceAppointment(1, 5, 1, 2, @t03 + INTERVAL 89 MINUTE, ''Boundary test: overlap'', 60)',
    'conflicting appointment');

-- T-45 / BR-04, BR-09: back-to-back booking (start = previous end) is allowed
CALL tst_ExpectSuccess('T-45', 'Create back-to-back appointment',
    'CALL sp_CreateServiceAppointment(1, 5, 1, 2, @t03 + INTERVAL 90 MINUTE, ''Boundary test: back to back'', 60)');

SET @c = (SELECT COUNT(*) FROM ServiceAppointment
          WHERE VehicleID = 5 AND TechnicianID = 1
            AND AppointmentDateTime = @t03 + INTERVAL 90 MINUTE);

CALL tst_Assert('T-45', 'Appointment starting exactly when the previous one ends was created',
    @c = 1, CONCAT('Matching appointments: ', @c, ' (expected 1)'));

-- T-10 / FR-08, SEC-03: an audited update creates the correct audit record
SET
    @app_user_id = 2;

SET
    @a = (
        SELECT
            MAX(AuditLogID)
        FROM
            AuditLog
    );

CALL tst_ExpectSuccess (
    'T-10',
    'Reschedule appointment 8',
    'UPDATE ServiceAppointment SET AppointmentDateTime = ''2026-11-03 15:00:00'' WHERE AppointmentID = 8'
);

SET
    @c = (
        SELECT
            COUNT(*)
        FROM
            AuditLog
        WHERE
            AuditLogID > @a
            AND UserID = 2
            AND Action = 'Reschedule'
            AND AffectedEntity = 'ServiceAppointment'
            AND AffectedRecordID = 8
    );

CALL tst_Assert (
    'T-10',
    'Audit row records user, action, entity, and record',
    @c = 1,
    CONCAT('Matching audit rows: ', @c, ' (expected 1)')
);

-- T-23 / FR-08: an update that changes nothing writes no audit row
SET
    @app_user_id = 2;

SET
    @a = (
        SELECT
            COUNT(*)
        FROM
            AuditLog
    );

CALL tst_ExpectSuccess (
    'T-23',
    'No-op update of invoice 3',
    'UPDATE Invoice SET TotalAmount = TotalAmount WHERE InvoiceID = 3'
);

SET
    @b = (
        SELECT
            COUNT(*)
        FROM
            AuditLog
    );

CALL tst_Assert (
    'T-23',
    'No-op update created no audit row',
    @b = @a,
    CONCAT('Audit rows before: ', @a, ', after: ', @b)
);

-- T-28b / FR-13: inventory adjustment with a reason is audited with the reason
SET
    @app_user_id = 1;

SET
    @adj_reason = 'Cycle count correction';

SET
    @a = (
        SELECT
            MAX(AuditLogID)
        FROM
            AuditLog
    );

CALL tst_ExpectSuccess (
    'T-28b',
    'Adjust oil filter inventory with a reason',
    'UPDATE Part SET QuantityOnHand = QuantityOnHand + 5 WHERE PartID = 1'
);

SET
    @adj_reason = NULL;

SET
    @c = (
        SELECT
            COUNT(*)
        FROM
            AuditLog
        WHERE
            AuditLogID > @a
            AND Action = 'Inventory Adjustment'
            AND AffectedRecordID = 1
            AND JSON_UNQUOTE(JSON_EXTRACT(NewValue, '$.Reason')) = 'Cycle count correction'
    );

CALL tst_Assert (
    'T-28b',
    'Adjustment audited with previous quantity, new quantity, and reason',
    @c = 1,
    CONCAT('Matching audit rows: ', @c, ' (expected 1)')
);

-- T-08 / FR-13: valid parts usage reduces inventory (repair 7)
SET
    @p4_before = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 4
    );

SET
    @a = (
        SELECT
            MAX(AuditLogID)
        FROM
            AuditLog
    );

CALL tst_ExpectSuccess (
    'T-08',
    'Complete repair 7 with one air filter',
    'CALL sp_CompleteRepair(7, 2, 4, ''[{"partId": 4, "qty": 1}]'')'
);

SET
    @p4_after = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 4
    );

SET
    @usage = (
        SELECT
            COUNT(*)
        FROM
            PartsUsage
        WHERE
            RepairID = 7
    );

SET
    @status = (
        SELECT
            Status
        FROM
            Repair
        WHERE
            RepairID = 7
    );

SET
    @new_audit = (
        SELECT
            COUNT(*)
        FROM
            AuditLog
        WHERE
            AuditLogID > @a
    );

CALL tst_Assert (
    'T-08',
    'PartsUsage recorded and inventory reduced',
    @p4_after = @p4_before - 1
    AND @usage = 1
    AND @status = 'Completed'
    AND @new_audit = 3,
    CONCAT(
        'Air filter: ',
        @p4_before,
        ' -> ',
        @p4_after,
        ', PartsUsage rows: ',
        @usage,
        ', Repair status: ',
        @status,
        ', new audit rows: ',
        @new_audit,
        ' (expected 3)'
    )
);

-- T-18 / FR-03, FR-20: complete a repair with two different parts (repair 6)
SET
    @p2_before = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 2
    );

SET
    @p3_before = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 3
    );

SET
    @a = (
        SELECT
            MAX(AuditLogID)
        FROM
            AuditLog
    );

CALL tst_ExpectSuccess (
    'T-18',
    'Complete repair 6 with brake pads and rotors',
    'CALL sp_CompleteRepair(6, 1, 3, ''[{"partId": 2, "qty": 1}, {"partId": 3, "qty": 2}]'')'
);

SET
    @p2_after = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 2
    );

SET
    @p3_after = (
        SELECT
            QuantityOnHand
        FROM
            Part
        WHERE
            PartID = 3
    );

SET
    @usage = (
        SELECT
            COUNT(*)
        FROM
            PartsUsage
        WHERE
            RepairID = 6
    );

SET
    @status = (
        SELECT
            Status
        FROM
            Repair
        WHERE
            RepairID = 6
    );

SET
    @tech = (
        SELECT
            CompletedByTechnicianID
        FROM
            Repair
        WHERE
            RepairID = 6
    );

SET
    @new_audit = (
        SELECT
            COUNT(*)
        FROM
            AuditLog
        WHERE
            AuditLogID > @a
    );

CALL tst_Assert (
    'T-18',
    'Repair completed, both parts recorded, inventory reduced, audited',
    @status = 'Completed'
    AND @tech = 1
    AND @usage = 2
    AND @p2_after = @p2_before - 1
    AND @p3_after = @p3_before - 2
    AND @new_audit = 5,
    CONCAT(
        'Status: ',
        @status,
        ', PartsUsage rows: ',
        @usage,
        ', Pads: ',
        @p2_before,
        ' -> ',
        @p2_after,
        ', Rotors: ',
        @p3_before,
        ' -> ',
        @p3_after,
        ', new audit rows: ',
        @new_audit,
        ' (expected 5)'
    )
);

-- T-47 / FR-08, SEC-03: every audit row written by one procedure call shares
-- one context ID. Uses the rows T-18's sp_CompleteRepair call just wrote.
SET @ctx_rows = (SELECT COUNT(*) FROM AuditLog WHERE AuditLogID > @a);
SET @ctx_ids  = (SELECT COUNT(DISTINCT ContextID) FROM AuditLog WHERE AuditLogID > @a);
SET @ctx_null = (SELECT COUNT(*) FROM AuditLog WHERE AuditLogID > @a AND ContextID IS NULL);

CALL tst_Assert('T-47', 'Audit rows from one procedure call share one context ID',
    @ctx_rows = 5 AND @ctx_ids = 1 AND @ctx_null = 0,
    CONCAT('Audit rows: ', @ctx_rows, ', distinct context IDs: ', @ctx_ids,
           ' (expected 1), rows without one: ', @ctx_null, ' (expected 0)'));

-- A direct update outside a procedure has no context ID
SET @c = (SELECT COUNT(*) FROM AuditLog
          WHERE Action = 'Reschedule' AND AffectedRecordID = 8 AND ContextID IS NULL);

CALL tst_Assert('T-47', 'Direct update outside a procedure has no context ID',
    @c = 1, CONCAT('Reschedule rows with no context ID: ', @c, ' (expected 1)'));

-- T-46 / FR-12, BR-10: using exactly the quantity on hand is allowed and
-- leaves 0 in stock. Builds its own repair (vehicle 1, Carla) because
-- repairs 6 and 7 are already completed above. Uses spark plugs.
SET @t46 = @t03 + INTERVAL 6 DAY;

CALL tst_ExpectSuccess('T-46', 'Book appointment for the stock boundary test',
    'CALL sp_CreateServiceAppointment(1, 1, 2, 2, @t46, ''Boundary test: all spark plugs'', 60)');

SET @appt46 = (SELECT AppointmentID FROM ServiceAppointment
               WHERE VehicleID = 1 AND AppointmentDateTime = @t46);

SET @app_user_id = 2;   -- Amy checks the vehicle in and opens the repair
CALL tst_ExpectSuccess('T-46', 'Check in appointment',
    'UPDATE ServiceAppointment SET Status = ''Checked In'' WHERE AppointmentID = @appt46');
CALL tst_ExpectSuccess('T-46', 'Start appointment',
    'UPDATE ServiceAppointment SET Status = ''In Progress'' WHERE AppointmentID = @appt46');
CALL tst_ExpectSuccess('T-46', 'Open repair',
    'INSERT INTO Repair (AppointmentID, RepairDateTime, RepairType, RepairDescription, LaborHours, Status) VALUES (@appt46, @t46, ''Ignition Service'', ''Replace all spark plugs'', 1.00, ''Open'')');

SET @repair46 = (SELECT RepairID FROM Repair WHERE AppointmentID = @appt46);

SET @app_user_id = 4;   -- Carla starts her repair
CALL tst_ExpectSuccess('T-46', 'Start repair',
    'UPDATE Repair SET Status = ''In Progress'' WHERE RepairID = @repair46');

SET @p5_before = (SELECT QuantityOnHand FROM Part WHERE PartID = 5);
SET @parts46 = JSON_ARRAY(JSON_OBJECT('partId', 5, 'qty', @p5_before));

CALL tst_ExpectSuccess('T-46', 'Complete repair using every spark plug in stock',
    'CALL sp_CompleteRepair(@repair46, 2, 4, @parts46)');

SET @p5_after = (SELECT QuantityOnHand FROM Part WHERE PartID = 5);
SET @used = (SELECT QuantityUsed FROM PartsUsage WHERE RepairID = @repair46 AND PartID = 5);
SET @status = (SELECT Status FROM Repair WHERE RepairID = @repair46);

CALL tst_Assert('T-46', 'Quantity equal to stock accepted; inventory is now 0',
    @p5_after = 0 AND @used = @p5_before AND @status = 'Completed',
    CONCAT('Spark plug: ', @p5_before, ' -> ', @p5_after,
           ', quantity used: ', @used, ', repair status: ', @status));

SET
    @app_user_id = NULL;

SET
    @adj_reason = NULL;

-- =====================================================================
-- 5. RESULTS
-- =====================================================================
-- Full results table 
SELECT
    TestID,
    Description,
    Result,
    Detail
FROM
    TestResult
ORDER BY
    RunOrder;

-- Summary 
SELECT
    Result,
    COUNT(*) AS Checks
FROM
    TestResult
GROUP BY
    Result;

-- =====================================================================
-- 6. CLEANUP (removes the test harness; test data changes remain)
-- =====================================================================
DROP PROCEDURE IF EXISTS tst_ExpectError;

DROP PROCEDURE IF EXISTS tst_ExpectSuccess;

DROP PROCEDURE IF EXISTS tst_Assert;

DROP PROCEDURE IF EXISTS tst_CaptureError;