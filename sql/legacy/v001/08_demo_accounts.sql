-- Vehicle Service and Maintenance Management System
-- Optional local demo provisioning; enabled by scripts/build.py --with-demo-accounts.
-- Existing principals are never dropped, reused, or altered.

-- =====================================================================
-- 4. ROLES AND PRIVILEGES (FR-07, BR-06, SEC-01, SEC-02)
-- Roles live at the server level; this optional script only creates new principals.
-- Stored procedures run with their definer's privileges, so roles need
-- only EXECUTE on them, not write access to the underlying tables.
-- sp_WriteAuditLog is intentionally not granted to any role.
-- =====================================================================

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

CREATE USER 'sa_amy'@'localhost'   IDENTIFIED BY 'Advisor#2026';
CREATE USER 'tech_ben'@'localhost' IDENTIFIED BY 'Tech#2026';
CREATE USER 'mgr_mike'@'localhost' IDENTIFIED BY 'Manager#2026';

GRANT 'role_service_advisor' TO 'sa_amy'@'localhost';
GRANT 'role_technician'      TO 'tech_ben'@'localhost';
GRANT 'role_manager'         TO 'mgr_mike'@'localhost';

SET DEFAULT ROLE 'role_service_advisor' TO 'sa_amy'@'localhost';
SET DEFAULT ROLE 'role_technician'      TO 'tech_ben'@'localhost';
SET DEFAULT ROLE 'role_manager'         TO 'mgr_mike'@'localhost';
