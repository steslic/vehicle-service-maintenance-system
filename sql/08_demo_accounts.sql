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

-- Service Advisor: business procedures plus existing report/table reads.
GRANT SELECT ON vehicle_service_maintenance.Customer TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.Vehicle TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.ServiceAppointment TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.Repair TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.RepairEstimate TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.EstimateLineItem TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.Invoice TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.InvoiceLineItem TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.Technician TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.Part TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.PartsUsage TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.vw_VehicleServiceHistory TO 'role_service_advisor';
GRANT SELECT ON vehicle_service_maintenance.vw_TechnicianWorkload TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateServiceAppointment TO 'role_service_advisor';

-- Technician: filtered reads, own-repair status procedure, and completion procedure.
GRANT SELECT ON vehicle_service_maintenance.vw_MyAppointments TO 'role_technician';
GRANT SELECT ON vehicle_service_maintenance.vw_MyRepairs TO 'role_technician';
GRANT SELECT ON vehicle_service_maintenance.Vehicle TO 'role_technician';
GRANT SELECT ON vehicle_service_maintenance.Part TO 'role_technician';
GRANT SELECT ON vehicle_service_maintenance.PartsUsage TO 'role_technician';
GRANT SELECT ON vehicle_service_maintenance.vw_VehicleServiceHistory TO 'role_technician';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CompleteRepair TO 'role_technician';

-- Manager: authorized procedures, including audited completion override, and audit reads.
GRANT SELECT ON vehicle_service_maintenance.Customer TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.Vehicle TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.Technician TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.ServiceAppointment TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.Repair TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.RepairEstimate TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.EstimateLineItem TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.Invoice TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.InvoiceLineItem TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.Part TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.PartsUsage TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.UserAccount TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.AuditLog TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.vw_VehicleServiceHistory TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.vw_TechnicianWorkload TO 'role_manager';
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

GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_ListIndicatorValues TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_ListIndicatorValues TO 'role_technician';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_ListIndicatorValues TO 'role_manager';
GRANT SELECT ON vehicle_service_maintenance.vw_AuditTrail TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_ListAuditTrail TO 'role_manager';

-- Revision 007: business mutations are available only through authorized procedures.
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateCustomer TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateCustomer TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateCustomer TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateCustomer TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateVehicle TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateVehicle TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateVehicle TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateVehicle TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateTechnician TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateTechnician TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreatePart TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdatePart TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_AdjustPartInventory TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateServiceAppointment TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateServiceAppointment TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_SetServiceAppointmentStatus TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_SetServiceAppointmentStatus TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateRepair TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateRepair TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateRepair TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_SetRepairStatus TO 'role_technician';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_SetRepairStatus TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateRepairEstimate TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateRepairEstimate TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateRepairEstimate TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateRepairEstimate TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_FinalizeRepairEstimate TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_FinalizeRepairEstimate TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateInvoice TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateInvoice TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateInvoice TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateInvoice TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_FinalizeInvoice TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_FinalizeInvoice TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_SubmitRepairEstimate TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_SubmitRepairEstimate TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_ExpireRepairEstimate TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_ExpireRepairEstimate TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_DecideRepairEstimate TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateEstimateLineItem TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateEstimateLineItem TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateEstimateLineItem TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateEstimateLineItem TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_DeleteEstimateLineItem TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_DeleteEstimateLineItem TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateInvoiceLineItem TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_CreateInvoiceLineItem TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateInvoiceLineItem TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_UpdateInvoiceLineItem TO 'role_manager';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_DeleteInvoiceLineItem TO 'role_service_advisor';
GRANT EXECUTE ON PROCEDURE vehicle_service_maintenance.sp_DeleteInvoiceLineItem TO 'role_manager';
