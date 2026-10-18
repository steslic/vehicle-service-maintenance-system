# Instructor Feedback Response

**Project:** Vehicle Service and Maintenance Management System  
**Student:** Sebastian Teslic

---

## 1. Customer Access and Row-Level Permissions

**Instructor feedback:**  
Customer access would require row-level permissions if implemented at the database level. Consider having Service Advisors access customer-facing information on behalf of customers and keeping direct customer access outside the project scope.

**Response:** Accepted.

**Changes made:**
- Customers do not directly access the database or have `UserAccount` records.
- Service Advisors access and manage customer-facing information on behalf of customers.
- A customer portal is outside the scope of this implementation.
- The FRD scope, stakeholder/role section, assumptions, and TDD security/design sections were updated accordingly.

## 2. Enrich the ServiceAppointment Data Model

**Instructor feedback:**  
Appointments should include date/time, status, service request/concern, assigned technician, customer/vehicle validation, estimated duration, creation timestamp/creating user, cancellation information, and rescheduling rules.

**Response:** Accepted.

**Changes made:**
- `ServiceAppointment` now stores `AppointmentDateTime`, `Status`, `ServiceRequestDescription`, `TechnicianID`, `VehicleID`, `CreatedByUserID`, `EstimatedDuration`, `CreationTimestamp`, `CancellationDate`, and `CancellationReason`.
- FR-02 was expanded to cover creation, viewing, updating, rescheduling, and cancellation of appointments.
- The TDD includes these fields in the `ServiceAppointment` relational schema and table specification.

## 3. Technician Scheduling Conflicts

**Instructor feedback:**  
The original design prevented duplicate vehicle appointments but did not prevent one technician from being assigned to multiple appointments at the same time.

**Response:** Accepted.

**Changes made:**
- BR-09 and FR-16 were added to prevent conflicting active technician assignments.
- UC-01 checks technician existence, active status, and availability before an appointment is created.
- The TDD specifies enforcement through `sp_CreateServiceAppointment` and supporting technician/date-time lookup logic.
- The suggested service location field was not added because the project models a single repair-shop location.

## 4. Parts Inventory Management

**Instructor feedback:**  
Add requirements for creating and maintaining part inventory, validating available inventory, preventing negative inventory, reducing quantity when parts are used, and recording authorized inventory adjustments.

**Response:** Accepted.

**Changes made:**
- FR-11, FR-12, and FR-13 were added.
- The `Part` table includes part number, name, quantity on hand, unit cost, unit selling price, minimum inventory level, and active status.
- `PartsUsage` records quantities used and historical cost/selling-price information.
- BR-10 prevents parts usage from reducing inventory below zero.
- Repair completion validates stock and updates inventory within a transaction.

## 5. Inventory Adjustment Auditing

**Instructor feedback:**  
Manager inventory adjustments should record the reason, quantity change, user, and timestamp.

**Response:** Accepted.

**Changes made:**
- FR-13 requires authorized inventory adjustments to be audited.
- The `AuditLog` design records the responsible user, timestamp, affected entity/record, action, and old/new values.
- Inventory adjustments are included in the audit requirements.

## 6. Estimate and Invoice Line Items

**Instructor feedback:**  
Clarify whether estimates and invoices can contain multiple line items and whether invoices contain labor, parts, or both.

**Response:** Accepted.

**Changes made:**
- `EstimateLineItem` and `InvoiceLineItem` were added.
- FR-17 requires description, quantity, unit price, and line total for estimate and invoice line items.
- Estimates and invoices may contain both labor and parts line items.

## 7. Invoice Creation and Estimate Approval

**Instructor feedback:**  
Clarify whether invoices are associated with completed repairs, whether estimates require approval, whether approval is customer or manager approval, and what finalization means.

**Response:** Accepted.

**Changes made:**
- The design assumes an invoice is created for a service appointment after the related repair work has been completed.
- Repair-estimate approval represents internal manager approval; customer approval is not modeled.
- Finalized estimates and invoices are treated as complete and cannot be directly modified or deleted.

## 8. Corrections or Voiding Finalized Invoices

**Instructor feedback:**  
A real system may need a controlled correction or voiding mechanism for finalized invoices. An immutable finalized invoice is acceptable for the database-course project.

**Response:** Not adopted for this implementation.

**Reason:**
- The project uses a simpler model in which finalized invoices and estimates are immutable.
- Payment processing, accounting corrections, and invoice replacement/void workflows are outside the current scope.
- FR-18 and SEC-01 protect finalized records from direct modification.

## 9. Allowed Status Values and Transitions

**Instructor feedback:**  
BR-05 originally required valid statuses but did not define the actual values or valid transitions.

**Response:** Accepted.

**Changes made:**
- The FRD defines allowed statuses for `ServiceAppointment`, `Repair`, `RepairEstimate`, and `Invoice`, along with valid transition paths.
- FR-19 requires controlled status values and valid transitions.

## 10. Audit Requirements

**Instructor feedback:**  
Expand FR-08 so important creates, updates, cancellations, approvals, finalizations, status changes, technician reassignments, inventory adjustments, and parts-usage changes are audited.

**Response:** Accepted.

**Changes made:**
- FR-08 was expanded to include these operational events.
- Audit records include the responsible user, timestamp, action, affected entity, record identifier, and relevant old/new values.
- The audit section identifies actions recorded for appointments, estimates, repairs, invoices, inventory, and parts usage.

## 11. UC-01: Create Service Appointment

**Instructor feedback:**  
UC-01 needed customer/vehicle ownership validation, technician validation and availability, duplicate/conflict handling, required service information, initial Scheduled status, audit information, and exception flows.

**Response:** Accepted.

**Changes made:**
- UC-01 validates vehicle ownership, technician existence and active status, technician availability, duplicate vehicle appointments, and technician conflicts.
- It requires appointment date/time and service request information.
- It creates appointments with initial `Scheduled` status, records the creating user/timestamp, and creates an audit entry.
- Exception flows were added for each identified failure case.

## 12. UC-02: Complete Vehicle Repair

**Instructor feedback:**  
UC-02 needed repair details, appointment validation, part existence and availability checks, inventory reduction, status updates, transactional completion, and rollback behavior.

**Response:** Accepted.

**Changes made:**
- UC-02 records repair date/time, repair type, repair description, and labor hours.
- It validates the appointment and technician assignment, as well as parts and inventory.
- It reduces inventory, updates statuses, adds the completed repair to vehicle maintenance history, and writes audit information.
- Related operations commit as one transaction; failure of any step causes rollback.

## 13. Important Unique Constraints

**Instructor feedback:**  
Explicitly identify important uniqueness rules for VIN, Username, PartNumber, technician email, customer email, and appointment duplicates.

**Response:** Accepted.

**Changes made:**
- The FRD documents `Vehicle.VIN`, `UserAccount.Username`, `Part.PartNumber`, and `Technician.Email` as unique.
- `Customer.Email` is intentionally not assumed to be unique.
- Appointment duplicate prevention uses controlled validation because cancelled appointments should not prevent later rebooking.

## 14. Additional Requirements FR-11 Through FR-20

**Instructor feedback:**  
Add requirements covering inventory management, inventory validation, inventory auditing, appointment modification, customer/vehicle ownership, technician conflicts, estimate/invoice line items, finalized-record protection, status transitions, and transactional repair completion.

**Response:** Accepted.

**Changes made:**
- FR-11 through FR-20 were added to the FRD.
- These requirements were mapped into the TDD schema, business-rule enforcement, procedures, tests, and traceability.
