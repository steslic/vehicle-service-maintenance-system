# FRD

## 1. Project Identification

| **Item**            | **Information**                                                         |
| ------------------- | ----------------------------------------------------------------------- |
| Project title       | Vehicle Service and Maintenance Management System                       |
| Prepared by         | Sebastian Teslic                                                        |
| Course/section      | 01:198:437                                                              |
| Date                | 9/12/2026                                                               |
| Version             | 1.0                                                                     |
| Repository location | https://github.com/steslic/database-implementation-2026-SebastianTeslic |

## 2. Business Problem and Purpose

An independent auto repair shop needs a database system to manage
customers, vehicles, service appointments, technician assignments,
repair estimates, parts usage, invoices, and maintenance history. For
this project, we assume that this information is currently managed
across disconnected records and processes. This makes it difficult to
maintain complete vehicle service histories, coordinate technician
assignments and workload, track parts used during repairs, manage
estimates and invoices consistently, and produce reports on shop
workload, common repairs, and parts revenue.

The purpose of this project is to create a relational database that
allows customers, service advisors, technicians, and managers to manage
vehicle service operations efficiently. The database will provide a
reliable source of information for customer and vehicle records, service
appointments and technician assignments, repair estimates and completed
work, parts usage, invoices, maintenance history, and operational
reporting.

## 3. Scope

| **In Scope**                                                           | **Out of Scope**                                       |
| ---------------------------------------------------------------------- | ------------------------------------------------------ |
| Manage customer and vehicle records                                    | Real credit-card or payment processing                 |
| Manage service appointments and technician assignments                 | Integration with external scheduling systems           |
| Create and manage repair estimates and invoices                        | Ordering parts directly from external suppliers        |
| Record completed repairs, parts usage, and vehicle maintenance history | External vehicle history and manufacturer integrations |
| Generate reports on shop workload, parts revenue, and common repairs   | AI-based vehicle diagnostics                           |

## 4. Stakeholders and User Roles

| **Stakeholder / Role** | **Responsibilities**                                                                                                   | **Database Needs**                                                                                                | **Typical Access**                                            |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Customer               | Provides vehicle information and requests/receives vehicle service                                                     | Vehicle information, appointments, estimates, invoices, maintenance history (records of previous service/repairs) | View own service-related records                              |
| Service Advisor        | Coordinate customers and service appointments, manage technician assignments, and create repair estimates and invoices | Customer and vehicle records, appointments, repair estimates, technician assignments, invoices                    | Create, view, and update operational records                  |
| Technician             | Performs vehicle service and records completed work                                                                    | Assigned service work, vehicle information, repair details, parts usage                                           | View assigned work, update repair and parts-usage information |
| Manager                | Oversees repair shop operations and performance                                                                        | Shop workload information, common-repair information, parts-revenue information, invoices and reports             | Broad operational and reporting access                        |

### Entitlement Prompt

| Role            | Can view                                                                                                                                       | Can create/update                                                                                                                               | Must not modify                                                                                      | Requires manager approval              | Audit log                                                                                               |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Customer        | Own vehicles, appointments, estimates, invoices, maintenance history                                                                           | Update own contact information                                                                                                                  | Other customers’ records, service records, technician assignments, estimates, invoices               | None                                   | No audit needed                                                                                         |
| Service Advisor | Customers, vehicles, appointments, estimates, invoices, service status                                                                         | Customers/vehicles, appointments, technician assignments, non-finalized estimates, non-finalized invoices                                       | Completed service records, audit records                                                             | Finalizing repair estimate             | Appointment changes, estimate changes, invoice changes                                                  |
| Technician      | Assigned appointments, vehicle/service information needed for assigned repair, parts available                                                 | Completed repairs, parts used during assigned work                                                                                              | Customer information, estimates, invoices, appointments assigned to other technicians                | None                                   | Repair completion and status, parts usage                                                               |
| Manager         | Customers, vehicles, appointments, repairs, estimates, invoices, parts, workload reports, common repairs, parts revenue reports, audit records | Update appointment status, reassign technicians, approve estimates, correct non-finalized invoice/estimate amounts, adjust inventory quantities | Existing audit-log entries, completed repair records, finalized invoices, finalized repair estimates | N/A – Manager performs these approvals | Estimate approvals, technician reassignments, inventory quantity corrections, appointment cancellations |

## 5. Functional Requirements

| ID    | Functional Requirement                                                                                                                                                                                                       | Priority | Related Data/Entities                                         | Related Role(s)                                |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------------------- | ---------------------------------------------- |
| FR-01 | The system shall store customer information and the vehicles that belong to each customer.                                                                                                                                   | High     | Customer, Vehicle                                             | Service Advisor                                |
| FR-02 | The system shall allow service advisors to create service appointments and assign a technician to an appointment.                                                                                                            | High     | Technician, ServiceAppointment                                | Service Advisor, Technician                    |
| FR-03 | The system shall allow technicians to record completed vehicle repairs and the parts used for the repair.                                                                                                                    | High     | Repair, Part, PartsUsage                                      | Technician                                     |
| FR-04 | The system shall allow authorized users to view a vehicle’s previous repairs and maintenance history.                                                                                                                        | Medium   | Vehicle, Repair, PartsUsage                                   | Customer, Service Advisor, Technician          |
| FR-05 | The system shall prevent a service appointment from being created for a customer or vehicle that does not exist in the system, and every vehicle must belong to an existing customer.                                        | High     | Customer, Vehicle, ServiceAppointment                         | Service Advisor                                |
| FR-06 | The system shall provide a workload report showing scheduled appointments and technician assignments.                                                                                                                        | Medium   | ServiceAppointment, Technician                                | Manager                                        |
| FR-07 | The system shall restrict what users can view or change based on their role.                                                                                                                                                 | High     | UserAccount, protected service records                        | Customer, Service Advisor, Technician, Manager |
| FR-08 | The system shall create an audit entry when key service records, including service appointments, repairs, repair estimates, and invoices, are created, updated, cancelled, approved/finalized, or have their status changed. | Medium   | AuditLog, RepairEstimate, Invoice, ServiceAppointment, Repair | Service Advisor, Manager, Technician           |
| FR-09 | The system shall provide reports showing common repairs and revenue from parts.                                                                                                                                              | Medium   | Repair, Part, PartsUsage, Invoice                             | Manager                                        |
| FR-10 | The system shall allow service advisors to create repair estimates and invoices for vehicle service appointments.                                                                                                            | High     | RepairEstimate, Invoice, Vehicle, ServiceAppointment          | Service Advisor                                |

## 6. Transaction Flows / Use Cases

### Use Case UC-01: Create a Service Appointment

| Item                     | Description                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Goal                     | Create a service appointment for a customer’s vehicle and assign a technician to the appointment.                                                                                                                                                                                                                                                                                                                                          |
| Primary actor            | Service Advisor                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Trigger                  | A customer requests a service appointment for their vehicle.                                                                                                                                                                                                                                                                                                                                                                               |
| Preconditions            | The customer and vehicle must exist in the system.                                                                                                                                                                                                                                                                                                                                                                                         |
| Related requirements     | FR-02, FR-05                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Main success flow        | 1. The service advisor selects the customer and vehicle.<br>2. The service advisor enters the service information and appointment date.<br>3. The service advisor selects a technician for the appointment.<br>4. The system verifies that the vehicle and customer exist.<br>5. The system creates a service appointment with the assigned technician.<br>6. The system records the creation of the service appointment in the audit log. |
| Alternate/exception flow | If the vehicle or customer does not exist, the appointment will not be created.                                                                                                                                                                                                                                                                                                                                                            |
| Postconditions           | A new service appointment associated with the customer’s vehicle and assigned technician exists.                                                                                                                                                                                                                                                                                                                                           |

### Use Case UC-02: Complete a Vehicle Repair

| Item                     | Description                                                                                                                                                                                                                                                                                                                                                                                 |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Goal                     | Record a completed vehicle repair and the parts used during the repair.                                                                                                                                                                                                                                                                                                                     |
| Primary actor            | Technician                                                                                                                                                                                                                                                                                                                                                                                  |
| Trigger                  | The technician completes the repair for a service appointment.                                                                                                                                                                                                                                                                                                                              |
| Preconditions            | The service appointment exists and the technician is assigned to it.                                                                                                                                                                                                                                                                                                                        |
| Related requirements     | FR-03, FR-04                                                                                                                                                                                                                                                                                                                                                                                |
| Main success flow        | 1. The technician selects the assigned service appointment.<br>2. The technician enters the completed repair work.<br>3. The technician records parts used during the repair.<br>4. The system saves the completed repair and the parts used.<br>5. The completed repair becomes part of the vehicle’s maintenance history.<br>6. The system records the completed repair in the audit log. |
| Alternate/exception flow | If the service appointment does not exist or is not assigned to the technician, the system will not allow the repair information to be recorded.                                                                                                                                                                                                                                            |
| Postconditions           | The completed repair and parts usage information is stored and can be viewed as part of the vehicle’s maintenance history.                                                                                                                                                                                                                                                                  |

## 7. Data Requirements

| Data subject        | Information to store                                                            | Example identifier | Likely relationship(s)                                                                                            |
| ------------------- | ------------------------------------------------------------------------------- | ------------------ | ----------------------------------------------------------------------------------------------------------------- |
| Customer            | Name, phone number, email address                                               | CustomerID         | Can own one or more vehicles                                                                                      |
| Vehicle             | VIN, make, model, year                                                          | VehicleID          | Belongs to a customer. Can have multiple service appointments.                                                    |
| Technician          | Name, phone number, email address                                               | TechnicianID       | Can be assigned to multiple service appointments.                                                                 |
| Service Appointment | Appointment date/time, status, service information                              | AppointmentID      | Is associated with a vehicle. Is assigned to a technician.                                                        |
| Repair              | Repair description, repair type, status, completion date                        | RepairID           | Is associated with a service appointment. Can use multiple parts.                                                 |
| Repair Estimate     | Estimated cost, description, estimate date, status                              | EstimateID         | Is associated with a service appointment.                                                                         |
| Part                | Part name, price, quantity available, minimum inventory level                   | PartID             | Can be used in multiple repairs.                                                                                  |
| Parts Usage         | Part, quantity used, unit price at time of use                                  | PartsUsageID       | Associates a repair with a part.                                                                                  |
| Invoice             | Total amount, date, status                                                      | InvoiceID          | Associated with a service appointment.                                                                            |
| User Account        | User name, name, role type, associated customer or technician when applicable   | UserID             | Identifies the user and associates the account with a role and, when applicable, a customer or technician record. |
| Audit Log           | User account, action performed, affected record, date/time, previous/new values | AuditLogID         | Records important changes made by users to system records.                                                        |

## 8. Business Rules and Validation Rules

| ID    | Business rule                                                                                                                                                                      | Why it matters                                                        | Possible enforcement approach                         |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ----------------------------------------------------- |
| BR-01 | Each customer, vehicle, technician, user account, service appointment, repair, part, parts usage record, repair estimate, invoice, and audit record must have a unique identifier. | Ensures that each record can be uniquely identified.                  | Primary key                                           |
| BR-02 | Each vehicle must belong to exactly one customer.                                                                                                                                  | Ensures that every vehicle is connected to a valid customer.          | Foreign key + NOT NULL                                |
| BR-03 | A repair may use many parts, and a part may be used in many repairs.                                                                                                               | Defines the many-to-many relationship between repairs and parts.      | PartsUsage junction table                             |
| BR-04 | A duplicate service appointment for the same vehicle, date, and time should not be created.                                                                                        | Prevents duplicate appointments.                                      | UNIQUE constraint or controlled procedure             |
| BR-05 | Appointment, repair estimate, repair, and invoice statuses must use allowed status values.                                                                                         | Prevents invalid status values.                                       | CHECK constraint or lookup table                      |
| BR-06 | Only authorized roles may create or modify service records.                                                                                                                        | Prevents unauthorized changes to service records.                     | Role/entitlement design or application access control |
| BR-07 | Changes to service appointments, repairs, repair estimates, and invoices must be auditable.                                                                                        | Provides a record of important changes.                               | Audit table + trigger/application logic               |
| BR-08 | A multi-step repair transaction must either complete successfully or be rolled back.                                                                                               | Prevents incomplete updates and keeps the related records consistent. | Database transaction with COMMIT/ROLLBACK             |

## 9. Security, Entitlements, and Auditing

### Role and Entitlement Requirements

| ID     | Security/entitlement requirement                                                                                                                                                                                                                                                    | Role(s) affected                     | Protected action or data                                                         |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | -------------------------------------------------------------------------------- |
| SEC-01 | The system shall allow customers to view their own vehicle, service appointment, repair, maintenance history, estimate, and invoice records.                                                                                                                                        | Customer                             | The customer’s own service-related data                                          |
| SEC-02 | The system shall allow service advisors to create and modify service appointments, non-finalized repair estimates, and non-finalized invoices. Repair estimates require manager approval before finalization. Finalized repair estimates and invoices cannot be modified or voided. | Service Advisor, Manager             | Service appointments, repair estimates, invoices                                 |
| SEC-03 | The system shall prevent technicians from modifying customer information, repair estimates, and invoices.                                                                                                                                                                           | Technician                           | Customer information, repair estimates, invoices                                 |
| SEC-04 | The system shall record the user, timestamp, operation, and affected record when a service appointment, repair, repair estimate, or invoice is created, updated, cancelled, or has its status changed.                                                                              | Service Advisor, Manager, Technician | Audited changes to service appointments, repairs, repair estimates, and invoices |

### Audit Requirements

| Business record     | Action(s) logged                                     | User Account/Role recorded | Date/time recorded      | Old/New values or transaction reference retained                       |
| ------------------- | ---------------------------------------------------- | -------------------------- | ----------------------- | ---------------------------------------------------------------------- |
| Service Appointment | Create, update, cancellation, status change          | Service Advisor, Manager   | Date and time of action | Appointment ID, previous/new appointment date/time, status, technician |
| Repair Estimate     | Create, update, approval/finalization, status change | Service Advisor, Manager   | Date and time of action | Estimate ID, previous/new cost, estimate date, status                  |
| Repair              | Create, update, status change                        | Technician                 | Date and time of action | Repair ID, previous/new description, status, completion date           |
| Invoice             | Create, update, status change                        | Service Advisor, Manager   | Date and time of action | Invoice ID, previous/new total amount, invoice date, status            |

## 10. Reports and Queries

| ID    | Report/query name          | Business question                                                 | Required result                                                                                              | Likely SQL features         |
| ----- | -------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | --------------------------- |
| RQ-01 | Daily Service Appointments | Which service appointments are scheduled for a selected day?      | Appointment ID, appointment date/time, vehicle, assigned technician, and status, ordered by appointment time | SELECT, WHERE, ORDER BY     |
| RQ-02 | Vehicle Service History    | What repairs and parts have been recorded for a selected vehicle? | Vehicle information, repair description, parts used, quantity used, completion date                          | JOIN                        |
| RQ-03 | Common Repairs Report      | Which types of repairs are most often performed?                  | Repair type and number of completed repairs, ordered from most common to least common                        | GROUP BY, COUNT(), ORDER BY |
| RQ-04 | Low Parts Inventory Report | Which parts have a quantity below the minimum inventory level?    | Part ID, part name, quantity available, minimum inventory level for parts below the minimum                  | WHERE                       |
| RQ-05 | Shop Workload Report       | How many service appointments are assigned to each technician?    | Technician name, number of assigned appointments                                                             | JOIN, GROUP BY, COUNT()     |
| RQ-06 | Parts Revenue Report       | How much revenue was generated from parts used in repairs?        | Part name, quantity used, unit price, total parts revenue                                                    | JOIN, GROUP BY, SUM()       |

## 11. Assumptions and Constraints

### Assumptions

- Assumption: Each scheduled service appointment has one primary
  technician assigned.

- Assumption: A customer may own multiple vehicles.

- Assumption: A vehicle may have multiple service appointments over
  time.

- Assumption: Each repair estimate and invoice applies to one service
  appointment.

- Assumption: Vehicle maintenance history is based on completed repair
  records.

- Assumption: Status values for service appointments, repair estimates,
  repairs, and invoices are maintained through controlled allowed
  values.

- Assumption: Each service appointment may have at most one repair estimate and at most one invoice.

- Assumption: A customer and a technician may each have at most one user account.

### Constraints

- Constraint: The database will be implemented in MySQL.

- Constraint: The project will use fictional/sample data only.

- Constraint: Real payment processing is outside the scope of this
  project.

- Constraint: External scheduling systems, supplier ordering systems, AI
  diagnostics, and external vehicle history/manufacturer integrations
  are outside the scope of this project.

- Constraint: The project documentation will be maintained in Markdown
  and ERD source/export artifacts will be stored in the repository under
  docs/.

- Constraint: Project diagram submissions will include the editable
  .drawio file, an exported .svg, and a Markdown page explaining the
  diagram’s purpose and assumptions.

## 12. Acceptance Criteria and Traceability

| Requirement | Acceptance criterion                                                                                                                                         | Evidence to show                                                                                                                                                       |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FR-01       | Insert, retrieve, and update at least 3 customer records and 3 vehicle records, with each vehicle linked to an existing customer.                            | INSERT, SELECT, and UPDATE statements and resulting rows                                                                                                               |
| FR-02       | Create a valid service appointment for an existing vehicle and assign an existing technician.                                                                | INSERT statement for the service appointment, technician assignment data, and a SELECT query showing the new appointment linked to the correct vehicle and technician. |
| FR-03       | Complete a valid repair transaction and record at least one part used for that repair.                                                                       | Transaction script and resulting Repair and PartsUsage records                                                                                                         |
| FR-04       | Retrieve the maintenance history for a selected vehicle, including completed repairs and parts used.                                                         | SQL query                                                                                                                                                              |
| FR-05       | Attempt to create a service appointment for a nonexistent vehicle and show that the database rejects it.                                                     | Foreign key/constraint error and the attempted SQL query                                                                                                               |
| FR-06       | Run the shop workload report showing scheduled appointments and the technician assigned to each appointment.                                                 | SQL query and report output                                                                                                                                            |
| FR-07       | Demonstrate that each role can perform allowed actions and is prevented from performing restricted actions.                                                  | Role/privilege or controlled access demonstration                                                                                                                      |
| FR-08       | Create or update an estimate or invoice and show that an audit record is created with the user, timestamp, action, and affected record.                      | Audit table contents and triggering SQL operation                                                                                                                      |
| FR-09       | Run reports showing common repairs and parts revenue using sample data.                                                                                      | SQL queries and report output                                                                                                                                          |
| FR-10       | Create a repair estimate and invoice for an existing service appointment and retrieve the resulting records.                                                 | SQL statements and resulting estimate/invoice records                                                                                                                  |
| SEC-02      | Show that a Service Advisor can modify appointments, non-finalized estimates, and non-finalized invoices while a Technician cannot perform the same actions. | Successful Service Advisor update and denied Technician update                                                                                                         |
| SEC-04      | Perform a create, update, or status change on an estimate or invoice and verify that an audit entry is stored.                                               | Audit table query and the triggering operation                                                                                                                         |
| BR-08       | Begin a multi-step repair transaction, force one step to fail, and verify that none of the incomplete changes remain in the database.                        | Rollback test with before/after results                                                                                                                                |
