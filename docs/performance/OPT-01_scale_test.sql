-- OPT-01 scale test: at what row count does the un-indexed query fall over?
-- Runs the RQ-03 Common Repairs query with and without idx_Repair_Status_Type
-- at 20k, 100k, 500k, 1M and 5M rows.
--
-- Uses its own database (optscale) with a copy of the Repair table and the same
-- data distribution as perf_data.sql (8 repair types, half Completed).
-- The project database is not touched. Takes a few minutes at 5M rows.
--
-- Run:  mysql -u root -p -t < OPT-01_scale_test.sql > OPT-01_scale_output.txt
-- Read: the "actual time=...." on the first line of each EXPLAIN ANALYZE
--       (the second number is the total time in ms).

DROP DATABASE IF EXISTS optscale;
CREATE DATABASE optscale;
USE optscale;

-- Same columns as Repair in 01_schema.sql (no foreign keys: standalone copy)
CREATE TABLE Repair (
    RepairID INT NOT NULL AUTO_INCREMENT,
    AppointmentID INT NOT NULL,
    CompletedByTechnicianID INT NULL,
    RepairDateTime DATETIME NOT NULL,
    RepairType VARCHAR(100) NOT NULL,
    RepairDescription VARCHAR(500) NOT NULL,
    LaborHours DECIMAL(5,2) NULL,
    Status VARCHAR(20) NOT NULL,
    CompletionDateTime DATETIME NULL,
    PRIMARY KEY (RepairID)
);

-- Number table 1..100000, used to insert rows in batches
CREATE TABLE seq (n INT PRIMARY KEY);
SET SESSION cte_max_recursion_depth = 100000;
INSERT INTO seq
WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM s WHERE n < 100000)
SELECT n FROM s;

DELIMITER //

-- Grow Repair to p_Target rows, 100k at a time
CREATE PROCEDURE grow_to(IN p_Target INT)
BEGIN
    DECLARE v_Have INT;
    DECLARE v_Batch INT;
    SELECT COUNT(*) INTO v_Have FROM Repair;
    WHILE v_Have < p_Target DO
        SET v_Batch = LEAST(100000, p_Target - v_Have);
        INSERT INTO Repair (AppointmentID, RepairDateTime, RepairType, RepairDescription,
                            LaborHours, Status, CompletedByTechnicianID, CompletionDateTime)
        SELECT v_Have + n,
               '2024-01-01' + INTERVAL (v_Have + n) * 20 MINUTE,
               ELT(1 + MOD(v_Have + n, 8),
                   'Oil Change', 'Brake Service', 'Tire Rotation', 'Battery Replacement',
                   'Diagnostic', 'Tune-Up', 'Filter Replacement', 'Ignition Service'),
               'Perf test repair', 1.00,
               IF(MOD(v_Have + n, 2) = 0, 'Completed', 'In Progress'),
               IF(MOD(v_Have + n, 2) = 0, 1, NULL),
               IF(MOD(v_Have + n, 2) = 0, '2024-01-01', NULL)
        FROM seq WHERE n <= v_Batch;
        SET v_Have = v_Have + v_Batch;
    END WHILE;
END //

-- Measure the query at the current size, without and then with the index
CREATE PROCEDURE measure()
BEGIN
    SELECT COUNT(*) AS RepairRows, SUM(Status = 'Completed') AS CompletedRows FROM Repair;

    -- BEFORE: no index (warm-up run first, then the measured run)
    ANALYZE TABLE Repair;
    SELECT RepairType, COUNT(*) AS TotalRepairs FROM Repair
    WHERE Status = 'Completed' GROUP BY RepairType ORDER BY TotalRepairs DESC;
    SELECT 'BEFORE (no index)' AS Run;
    EXPLAIN ANALYZE
    SELECT RepairType, COUNT(*) AS TotalRepairs FROM Repair
    WHERE Status = 'Completed' GROUP BY RepairType ORDER BY TotalRepairs DESC;

    -- AFTER: covering index
    CREATE INDEX idx_Repair_Status_Type ON Repair (Status, RepairType);
    ANALYZE TABLE Repair;
    SELECT RepairType, COUNT(*) AS TotalRepairs FROM Repair
    WHERE Status = 'Completed' GROUP BY RepairType ORDER BY TotalRepairs DESC;
    SELECT 'AFTER (covering index)' AS Run;
    EXPLAIN ANALYZE
    SELECT RepairType, COUNT(*) AS TotalRepairs FROM Repair
    WHERE Status = 'Completed' GROUP BY RepairType ORDER BY TotalRepairs DESC;

    DROP INDEX idx_Repair_Status_Type ON Repair;
END //

DELIMITER ;

CALL grow_to(20000);    CALL measure();
CALL grow_to(100000);   CALL measure();
CALL grow_to(500000);   CALL measure();
CALL grow_to(1000000);  CALL measure();
CALL grow_to(5000000);  CALL measure();

-- Clean up
DROP DATABASE optscale;