-- Vehicle Service and Maintenance Management System
-- 02_indexes.sql
-- Creates indexes for improved query performance

USE vehicle_service_maintenance;

-- Appointment lookup by date/time
CREATE INDEX idx_ServiceAppointment_DateTime
ON ServiceAppointment (AppointmentDateTime);

-- Technician scheduling and workload
CREATE INDEX idx_ServiceAppointment_Technician_DateTime
ON ServiceAppointment (TechnicianID, AppointmentDateTime);

-- Vehicle appointment conflict checks
CREATE INDEX idx_ServiceAppointment_Vehicle_DateTime
ON ServiceAppointment (VehicleID, AppointmentDateTime);

-- Audit history lookup
CREATE INDEX idx_AuditLog_Entity_Record
ON AuditLog (AffectedEntity, AffectedRecordID, `Timestamp`);

-- Helps find completed repairs grouped by repair type 
CREATE INDEX idx_Repair_Status_Type
ON Repair (`Status`, RepairType);