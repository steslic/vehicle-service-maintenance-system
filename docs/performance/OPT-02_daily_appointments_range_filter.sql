-- OPT-02: Daily Service Appointments (RQ-01), function on an indexed column
-- Run after perf_data.sql.

USE vehicle_service_maintenance;
ANALYZE TABLE ServiceAppointment;

-- ===== BEFORE: DATE() wrapped around the indexed column =====
EXPLAIN
SELECT AppointmentID, AppointmentDateTime, Status
FROM ServiceAppointment
WHERE DATE(AppointmentDateTime) = '2024-03-15'
ORDER BY AppointmentDateTime;

EXPLAIN ANALYZE
SELECT AppointmentID, AppointmentDateTime, Status
FROM ServiceAppointment
WHERE DATE(AppointmentDateTime) = '2024-03-15'
ORDER BY AppointmentDateTime;

SELECT COUNT(*) AS RowsReturnedBefore
FROM ServiceAppointment
WHERE DATE(AppointmentDateTime) = '2024-03-15';

-- ===== CHANGE + AFTER: same filter written as a range (one change) =====
EXPLAIN
SELECT AppointmentID, AppointmentDateTime, Status
FROM ServiceAppointment
WHERE AppointmentDateTime >= '2024-03-15'
  AND AppointmentDateTime <  '2024-03-16'
ORDER BY AppointmentDateTime;

EXPLAIN ANALYZE
SELECT AppointmentID, AppointmentDateTime, Status
FROM ServiceAppointment
WHERE AppointmentDateTime >= '2024-03-15'
  AND AppointmentDateTime <  '2024-03-16'
ORDER BY AppointmentDateTime;

SELECT COUNT(*) AS RowsReturnedAfter
FROM ServiceAppointment
WHERE AppointmentDateTime >= '2024-03-15'
  AND AppointmentDateTime <  '2024-03-16';
