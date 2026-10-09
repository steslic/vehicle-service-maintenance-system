# Technical Design Document

## 1. Project Identification

| Item           | Information                                       |
| -------------- | ------------------------------------------------- |
| Project title  | Vehicle Service and Maintenance Management System |
| Prepared by    | Sebastian Teslic                                  |
| Course/section | 01:198:437                                        |
| Date           | 10/9/2026                                         |
| Version        | 1.0                                               |

## 2. Design overview

This project implements a relational database for an independent auto repair shop. The database will manage customers, vehicles, technicians, service appointments, repairs, repair estimates, estimate line items, parts, parts usage, invoices, invoice line items, user accounts, and audit records. It will use MySQL and will support service appointment scheduling, technician assignment, repair and parts recording, estimate and invoice management, maintenance history retrieval, audit logging, and reports on shop workload, common repairs, low parts inventory, and parts revenue. The design consists of 13 related tables and enforces data integrity through primary keys, foreign keys, unique constraints, check constraints, and database transaction controls.

## 3. Technical environment

| Component                  | Selected technology/tool | Purpose                               |
| -------------------------- | ------------------------ | ------------------------------------- |
| Database management system | MySQL 8.x                | Store and manage relational data      |
| Database client/IDE        | MySQL Workbench          | Design, execute, and test SQL         |
| Modeling tool              | draw.io                  | Create ERD and schema diagram         |
| Source control             | GitHub                   | Version SQL scripts and documentation |
| Operating environment      | MacOS                    | Development and testing environment   |

## 4. Architecture and scope

The solution uses a relational database architecture. Users or a future application interface will submit data-entry, update, and reporting requests to the database. The database will store normalized records for customers, vehicles, technicians, service appointments, repairs, repair estimates, estimate line items, parts, parts usage, invoices, invoice line items, user accounts, and audit records. MySQL will enforce referential integrity and will return query results. A user interface is outside the scope unless specifically required.

The project uses a single MySQL database/schema. It will use fictional, non-sensitive sample data for development and testing. The project focuses on database implementation rather than the development of a website or mobile application. Real payment processing, external scheduling systems, AI diagnostics, and external vehicle history integrations are outside the scope. Production backup schedules and enterprise-scale performance tuning are outside the scope unless required.

## 5. Entity-relationship design

| Entity             | Purpose                                                           | Primary key             | Important relationships                                                                                                                                  |
| ------------------ | ----------------------------------------------------------------- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Customer           | Stores customer identity and contact information                  | CustomerID              | May own zero or more Vehicles                                                                                                                            |
| Vehicle            | Stores information about customer vehicles                        | VehicleID               | Belongs to one Customer, may have multiple ServiceAppointments                                                                                           |
| Technician         | Stores technician identity and contact information                | TechnicianID            | May be assigned to multiple ServiceAppointments, may be associated with one UserAccount                                                                  |
| ServiceAppointment | Stores schedule vehicle service information                       | AppointmentID           | Belongs to one Vehicle and one Technician. May have Repairs, a RepairEstimate, and an Invoice                                                            |
| Repair             | Stores information of work performed during a service appointment | RepairID                | Belongs to one ServiceAppointment, may be associated with multiple Parts through PartsUsage                                                              |
| RepairEstimate     | Stores the estimated cost and information for a proposed service  | EstimateID              | Belongs to one ServiceAppointment                                                                                                                        |
| Part               | Stores parts inventory and pricing information                    | PartID                  | May be used in multiple Repairs through PartsUsage                                                                                                       |
| PartsUsage         | Records a part used during a repair                               | PartsUsageID            | Links one Repair to one Part                                                                                                                             |
| Invoice            | Stores billing information for a service appointment              | InvoiceID               | Belongs to one ServiceAppointment                                                                                                                        |
| UserAccount        | Stores user identity and role                                     | UserID                  | May be associated with a Technician when applicable; may create, approve, finalize, or record operational records and may have multiple AuditLog records |
| AuditLog           | Records important database actions performed by users             | AuditLogID              | Belongs to one UserAccount                                                                                                                               |
| EstimateLineItem   | Stores an individual charge/item on a repair estimate             | EstimateID + LineNumber | Belongs to one RepairEstimate                                                                                                                            |
| InvoiceLineItem    | Stores an individual charge/item on an invoice                    | InvoiceLineItemID       | Belongs to one Invoice                                                                                                                                   |

### Relationship narrative

- One Customer may be associated with zero, one, or many Vehicle records. Each Vehicle record must be associated with exactly one Customer.
- One Vehicle may be associated with zero, one, or many ServiceAppointment records. Each ServiceAppointment record must be associated with exactly one Vehicle.
- One Technician may be associated with zero, one, or many ServiceAppointment records. Each scheduled ServiceAppointment must be associated with exactly one primary Technician.
- One ServiceAppointment may be associated with zero, one, or many Repair records. Each Repair record must be associated with exactly one ServiceAppointment.
- One ServiceAppointment may be associated with zero or one RepairEstimate record. Each RepairEstimate record must be associated with exactly one ServiceAppointment.
- One ServiceAppointment may be associated with zero or one Invoice record. Each Invoice record must be associated with exactly one ServiceAppointment.
- One Repair may be associated with zero, one, or many PartsUsage records. Each PartsUsage record must be associated with exactly one Repair.
- One Part may be associated with zero, one, or many PartsUsage records. Each PartsUsage record must be associated with exactly one Part.
- PartsUsage resolves the many-to-many relationship between Repair and Part.
- One Technician may be associated with zero or one UserAccount. A UserAccount may be associated with zero or one Technician.
- One UserAccount may be associated with zero, one, or many AuditLog records. Each AuditLog record must be associated with exactly one UserAccount.
- One RepairEstimate may contain zero or many EstimateLineItem records. Each EstimateLineItem belongs to exactly one RepairEstimate.
- EstimateLineItem is a weak entity identified by its owning RepairEstimate through the composite primary key (EstimateID, LineNumber).
- One Invoice may contain zero or many InvoiceLineItem records. Each InvoiceLineItem belongs to exactly one Invoice.
- One UserAccount may create zero or many ServiceAppointment records. Each ServiceAppointment is created by exactly one UserAccount.
- One UserAccount may create zero or many RepairEstimate records. Each RepairEstimate is created by exactly one UserAccount.
- One UserAccount may approve zero or many RepairEstimate records. A RepairEstimate may have zero or one approving UserAccount until approval occurs.
- One UserAccount may create zero or many Invoice records. Each Invoice is created by exactly one UserAccount.
- One UserAccount may finalize zero or many Invoice records. An Invoice may have zero or one finalizing UserAccount until finalization occurs.
- One UserAccount may record zero or many PartsUsage records. Each PartsUsage record is recorded by exactly one UserAccount.
- One Technician may complete zero or many Repair records. A Repair may have zero or one completed-by Technician until completion.

## 6. Relational schema

```text
Customer(

CustomerID PK,

Name,

Phone,

Email
)

Vehicle(

VehicleID PK,

CustomerID FK -\> Customer(CustomerID),

VIN UNIQUE,

Make,

Model,

Year

)

Technician(

TechnicianID PK,

Name,

Phone,

Email UNIQUE,

ActiveStatus

)

ServiceAppointment(

AppointmentID PK,

VehicleID FK -\> Vehicle(VehicleID),

TechnicianID FK -\> Technician(TechnicianID),

CreatedByUserID FK -\> UserAccount(UserID),

AppointmentDateTime,

Status,

ServiceRequestDescription,

EstimatedDuration,

CreationTimestamp,

CancellationDate,

CancellationReason

)

Repair(

RepairID PK,

AppointmentID FK -\> ServiceAppointment(AppointmentID),

CompletedByTechnicianID FK -\> Technician(TechnicianID),

RepairDateTime,

RepairType,

RepairDescription,

LaborHours,

Status,

CompletionDateTime

)

RepairEstimate(

EstimateID PK,

AppointmentID FK -\> ServiceAppointment(AppointmentID),

CreatedByUserID FK -\> UserAccount(UserID),

ApprovedByUserID FK -\> UserAccount(UserID),

EstimateDate,

Status,

TotalAmount,

ApprovalDateTime,

UNIQUE(AppointmentID)

)

EstimateLineItem(

EstimateID PK, FK -\> RepairEstimate(EstimateID),

LineNumber PK,

Description,

Quantity,

UnitPrice,

LineTotal

)

Part(

PartID PK,

PartNumber UNIQUE,

PartName,

QuantityOnHand,

UnitCost,

UnitSellingPrice,

MinimumInventoryLevel,

ActiveStatus

)

PartsUsage(

PartsUsageID PK,

RepairID FK -\> Repair(RepairID),

PartID FK -\> Part(PartID),

RecordedByUserID FK -\> UserAccount(UserID),

QuantityUsed,

UnitSellingPriceAtTimeOfUse,

UnitCostAtTimeOfUse,

RecordedDateTime

)

Invoice(

InvoiceID PK,

AppointmentID FK -\> ServiceAppointment(AppointmentID),

CreatedByUserID FK -\> UserAccount(UserID),

FinalizedByUserID FK -\> UserAccount(UserID),

InvoiceDate,

Status,

TotalAmount,

FinalizationDateTime,

UNIQUE(AppointmentID)

)

InvoiceLineItem(

InvoiceLineItemID PK,

InvoiceID FK -\> Invoice(InvoiceID),

Description,

Quantity,

UnitPrice,

LineTotal

)

UserAccount(

UserID PK,

TechnicianID FK -\> Technician(TechnicianID),

Username UNIQUE,

Name,

RoleType,

UNIQUE(TechnicianID)

)

AuditLog(

AuditLogID PK,

UserID FK -\> UserAccount(UserID),

Timestamp,

Action,

AffectedEntity,

AffectedRecordID,

PreviousValue,

NewValue

)
```

## 7. Table and attribute specifications

### Table: Customer

**Purpose:** Stores one row for each customer of the repair shop.

| Column     | Data type    | Null allowed? | Key/constraint     | Description/example        |
| ---------- | ------------ | ------------- | ------------------ | -------------------------- |
| CustomerID | INT          | No            | PK, AUTO_INCREMENT | Unique customer identifier |
| Name       | VARCHAR(100) | No            | None               | Customer name              |
| Phone      | VARCHAR(25)  | Yes           | None               | Customer phone number      |
| Email      | VARCHAR(100) | Yes           | None               | Customer email address     |

#### Rules implemented by this table:

- FR-01 stores customer information.
- BR-01 requires every customer to have a unique identifier.

### Table: Vehicle

**Purpose:** Stores one row for each vehicle belonging to a customer.

| Column     | Data type   | Null allowed? | Key/constraint            | Description/example           |
| ---------- | ----------- | ------------- | ------------------------- | ----------------------------- |
| VehicleID  | INT         | No            | PK, AUTO_INCREMENT        | Unique vehicle identifier     |
| CustomerID | INT         | No            | FK → Customer(CustomerID) | Customer who owns the vehicle |
| VIN        | VARCHAR(17) | No            | UNIQUE                    | Vehicle identification number |
| Make       | VARCHAR(50) | No            | None                      | Vehicle manufacturer          |
| Model      | VARCHAR(50) | No            | None                      | Vehicle model                 |
| Year       | SMALLINT    | No            | None                      | Vehicle model year            |

#### Rules implemented by this table:

- FR-01 links vehicles to customers.
- FR-05 and BR-02 require every vehicle to belong to an existing customer.

### Table: Technician

**Purpose:** Stores one row for each technician who may be assigned to service appointments.

| Column       | Data type    | Null allowed? | Key/constraint     | Description/example          |
| ------------ | ------------ | ------------- | ------------------ | ---------------------------- |
| TechnicianID | INT          | No            | PK, AUTO_INCREMENT | Unique technician identifier |
| Name         | VARCHAR(100) | No            | None               | Technician name              |
| Phone        | VARCHAR(25)  | Yes           | None               | Technician phone number      |
| Email        | VARCHAR(100) | Yes           | UNIQUE             | Technician email address     |
| ActiveStatus | BOOLEAN      | No            | None               | Technician active status     |

#### Rules implemented by this table:

- FR-02 supports assigning a technician to an appointment.
- BR-01 requires each technician to have a unique identifier.

### Table: ServiceAppointment

**Purpose:** Stores one row for each scheduled vehicle service appointment.

| Column                    | Data type    | Null allowed | Key/constraint                                                                                    | Description/example                  |
| ------------------------- | ------------ | ------------ | ------------------------------------------------------------------------------------------------- | ------------------------------------ |
| AppointmentID             | INT          | No           | PK, AUTO_INCREMENT                                                                                | Unique appointment identifier        |
| VehicleID                 | INT          | No           | FK → Vehicle(VehicleID)                                                                           | Vehicle being serviced               |
| TechnicianID              | INT          | No           | FK → Technician(TechnicianID)                                                                     | Assigned primary technician          |
| CreatedByUserID           | INT          | No           | FK → UserAccount(UserID)                                                                          | User who created the appointment     |
| AppointmentDateTime       | DATETIME     | No           | None                                                                                              | Scheduled appointment date/time      |
| Status                    | VARCHAR(20)  | No           | CHECK (Status IN (‘Scheduled’, ‘Checked In’, ‘In Progress’, ‘Completed’, ‘Cancelled’, ‘No Show’)) | Current appointment status           |
| ServiceRequestDescription | VARCHAR(500) | No           | None                                                                                              | Description of the requested service |
| EstimatedDuration         | INT          | Yes          | CHECK (EstimatedDuration \> 0)                                                                    | Estimated duration in minutes        |
| CreationTimestamp         | DATETIME     | No           | None                                                                                              | Date/time appointment was created    |
| CancellationDate          | DATE         | Yes          | None                                                                                              | Date appointment was cancelled       |
| CancellationReason        | VARCHAR(500) | Yes          | None                                                                                              | Reason for cancellation              |

#### Rules implemented by this table:

- FR-02 supports creating, viewing, updating, rescheduling, and cancelling service appointments.
- FR-05 prevents appointments from referencing invalid vehicles.
- FR-14 allows non-completed appointments to be updated, rescheduled, or cancelled.
- FR-16 and BR-09 prevent technician scheduling conflicts.
- BR-04 prevents duplicate active appointments for the same vehicle/date/time.
- BR-05 restricts appointment status to approved values.

### Table: Repair

**Purpose:** Stores one row for each repair associated with a service appointment.

| Column                  | Data type    | Null allowed? | Key/constraint                                                      | Description/example                            |
| ----------------------- | ------------ | ------------- | ------------------------------------------------------------------- | ---------------------------------------------- |
| RepairID                | INT          | No            | PK, AUTO_INCREMENT                                                  | Unique repair identifier                       |
| AppointmentID           | INT          | No            | FK → ServiceAppointment(AppointmentID)                              | Appointment associated with the repair         |
| RepairType              | VARCHAR(100) | No            | None                                                                | Type of repair                                 |
| RepairDescription       | VARCHAR(500) | No            | None                                                                | Description of repair work                     |
| Status                  | VARCHAR(20)  | No            | CHECK (Status IN (‘Open’, ‘In Progress’, ‘Completed’, ‘Cancelled’)) | Repair status                                  |
| CompletedByTechnicianID | INT          | Yes           | FK → Technician(TechnicianID)                                       | Technician who completed the repair            |
| RepairDateTime          | DATETIME     | No            | None                                                                | Date/time the repair was recorded or performed |
| LaborHours              | DECIMAL(5,2) | Yes           | CHECK (LaborHours \>= 0)                                            | Labor hours spent on the repair                |
| CompletionDateTime      | DATETIME     | Yes           | None                                                                | Date/time the repair was completed             |

#### Rules implemented by this table:

- FR-03 supports storing completed repair work.
- FR-04 supports retrieving the vehicle maintenance history.
- FR-20 requires repair completion and related updates to occur as one database transaction.
- BR-05 restricts repair status to approved values.

### Table: RepairEstimate

**Purpose:** Stores an estimate that is prepared for a service appointment.

| Column           | Data type     | Null allowed? | Key/constraint                                                                                  | Description/example                        |
| ---------------- | ------------- | ------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------ |
| EstimateID       | INT           | No            | PK, AUTO_INCREMENT                                                                              | Unique estimate identifier                 |
| AppointmentID    | INT           | No            | FK, UNIQUE → ServiceAppointment(AppointmentID)                                                  | Appointment that is receiving the estimate |
| CreatedByUserID  | INT           | No            | FK → UserAccount(UserID)                                                                        | User who created the estimate              |
| ApprovedByUserID | INT           | Yes           | FK → UserAccount(UserID)                                                                        | Manager/user who approved the estimate     |
| EstimateDate     | DATE          | No            | None                                                                                            | Date estimate was created                  |
| Status           | VARCHAR(20)   | No            | CHECK (Status IN (‘Draft’, ‘Pending Approval’, ‘Approved’, ‘Rejected’, ‘Expired’, ‘Finalized’)) | Current estimate status                    |
| TotalAmount      | DECIMAL(10,2) | No            | CHECK (TotalAmount \>= 0)                                                                       | Total estimate amount                      |
| ApprovalDateTime | DATETIME      | Yes           | None                                                                                            | Date/time estimate was approved            |

#### Rules implemented by this table:

- FR-10 supports service advisors creating estimates.
- UNIQUE(AppointmentID) enforces at most one repair estimate per appointment.
- FR-17 requires estimate line-item details.
- FR-18 prevents finalized estimates from being directly updated or deleted.
- FR-19 enforces valid estimate statuses and transitions.
- SEC-01 requires manager approval before finalization and protects finalized estimates from modification.

### Table: EstimateLineItem

**Purpose:** Stores one row for each line item included in a repair estimate

| Column      | Data type     | Null allowed | Key/constraint                      | Description/example                       |
| ----------- | ------------- | ------------ | ----------------------------------- | ----------------------------------------- |
| LineNumber  | INT           | No           | PK                                  | Line number within the repair estimate    |
| EstimateID  | INT           | No           | PK, FK → RepairEstimate(EstimateID) | Repair estimate this line item belongs to |
| Description | VARCHAR(500)  | No           | None                                | Description of the labor, part, or charge |
| Quantity    | INT           | No           | CHECK (Quantity \> 0)               | Number of units                           |
| UnitPrice   | DECIMAL(10,2) | No           | CHECK (UnitPrice \>= 0)             | Price per unit                            |
| LineTotal   | DECIMAL(10,2) | No           | CHECK (LineTotal \>= 0)             | Total amount for this line item           |

#### Rules implemented by this table:

- FR-17 requires repair estimates to store line-item details including description, quantity, unit price, and line total.
- Each EstimateLineItem must belong to exactly one RepairEstimate.

### Table: Part

**Purpose:** Stores one row for each part maintained in the shop inventory.

| Column                | Data type     | Null allowed | Key/constraint     | Description/example                           |
| --------------------- | ------------- | ------------ | ------------------ | --------------------------------------------- |
| PartID                | INT           | No           | PK, AUTO_INCREMENT | Unique part identifier                        |
| PartNumber            | VARCHAR(50)   | No           | UNIQUE             | Unique part number/SKU                        |
| PartName              | VARCHAR(100)  | No           | None               | Name of the part                              |
| QuantityOnHand        | INT           | No           | CHECK \>= 0        | Quantity currently available in the inventory |
| UnitCost              | DECIMAL(10,2) | No           | CHECK \>= 0        | Cost paid by the shop per unit                |
| UnitSellingPrice      | DECIMAL(10,2) | No           | CHECK \>= 0        | Selling price charged per unit                |
| MinimumInventoryLevel | INT           | No           | CHECK \>= 0        | Minimum desired inventory amount              |
| ActiveStatus          | BOOLEAN       | No           | None               | Whether the part is active in inventory       |

#### Rules implemented by this table:

- FR-03 supports recording parts used in repairs.
- FR-11 supports creating, viewing, and updating inventory records.
- FR-12 prevents parts usage from reducing inventory below zero.
- FR-13 requires inventory quantity to be reduced when parts usage is recorded.
- BR-10 prevents negative quantity on hand.
- RQ-04 compares quantity on hand with the minimum inventory level.

### Table: PartsUsage

**Purpose:** Resolves the many-to-many relationship between Repair and Part. One row represents a quantity of one part used for one repair.

| Column                      | Data type      | Null allowed? | Key/constraint           | Description/example               |
| --------------------------- | -------------- | ------------- | ------------------------ | --------------------------------- |
| PartsUsageID                | INT            | No            | PK, AUTO_INCREMENT       | Unique parts-usage identifier     |
| RepairID                    | INT            | No            | FK → Repair(RepairID)    | Repair that used the part         |
| PartID                      | INT            | No            | FK → Part(PartID)        | Part that was used                |
| RecordedByUserID            | INT            | No            | FK → UserAccount(UserID) | User who recorded the parts usage |
| QuantityUsed                | INT            | No            | CHECK \> 0               | Number of units used              |
| UnitSellingPriceAtTimeOfUse | DECIMAL(10, 2) | No            | CHECK \>= 0              | Selling price per unit when used  |
| UnitCostAtTimeOfUse         | DECIMAL(10,2)  | No            | CHECK \>= 0              | Shop cost per unit when used      |
| RecordedDateTime            | DATETIME       | No            | None                     | Date/time the usage was recorded  |

#### Rules implemented by this table:

- FR-03 supports recording parts used during repairs.

<!-- -->

- FR-12 validates sufficient inventory before parts usage is recorded.
- FR-13 reduces inventory when parts usage is recorded.
- BR-03 resolves the Repair-to-Part many-to-many relationship through PartsUsage.
- BR-10 prevents parts usage from reducing quantity on hand below zero.

### Table: Invoice

**Purpose:** Stores one invoice associated with a service appointment.

| Column               | Data type     | Null allowed? | Key/constraint                                 | Description/example                 |
| -------------------- | ------------- | ------------- | ---------------------------------------------- | ----------------------------------- |
| InvoiceID            | INT           | No            | PK, AUTO_INCREMENT                             | Unique invoice identifier           |
| AppointmentID        | INT           | No            | FK, UNIQUE → ServiceAppointment(AppointmentID) | Appointment being invoiced          |
| CreatedByUserID      | INT           | No            | FK → UserAccount(UserID)                       | User who created the invoice        |
| FinalizedByUserID    | INT           | Yes           | FK → UserAccount(UserID)                       | User who finalized the invoice      |
| InvoiceDate          | DATE          | No            | None                                           | Date the invoice was created        |
| Status               | VARCHAR(20)   | No            | CHECK (Status IN (‘Draft’, ‘Finalized’))       | Current invoice status              |
| TotalAmount          | DECIMAL(10,2) | No            | CHECK \>= 0                                    | Invoice total                       |
| FinalizationDateTime | DATETIME      | Yes           | None                                           | Date/time the invoice was finalized |

#### Rules implemented by this table:

- FR-10 supports creating invoices.
- UNIQUE(AppointmentID) enforces at most one invoice per appointment.
- SEC-01 protects finalized invoices from modification.
- FR-17 requires invoices to contain line-item details.
- FR-18 prevents finalized invoices from being directly updated or deleted.
- FR-19 enforces valid invoice status values and transitions.

### Table: InvoiceLineItem

**Purpose:** Stores one row for each individual charge included on an invoice.

| Column            | Data type     | Null allowed | Key/constraint          | Description/example                       |
| ----------------- | ------------- | ------------ | ----------------------- | ----------------------------------------- |
| InvoiceLineItemID | INT           | No           | PK, AUTO_INCREMENT      | Unique invoice line item identifier       |
| InvoiceID         | INT           | No           | FK → Invoice(InvoiceID) | Invoice this line item belongs to         |
| Description       | VARCHAR(500)  | No           | None                    | Description of the labor, part, or charge |
| Quantity          | INT           | No           | CHECK (Quantity \> 0)   | Number of units                           |
| UnitPrice         | DECIMAL(10,2) | No           | CHECK (UnitPrice \>= 0) | Price per unit                            |
| LineTotal         | DECIMAL(10,2) | No           | CHECK (LineTotal \>= 0) | Total amount for this line item           |

#### Rules implemented by this table:

- FR-17 requires invoices to store line-item details including description, quantity, unit price, and line total.
- Each InvoiceLineItem must belong to exactly one invoice.

### Table: UserAccount

**Purpose:** Stores one system login identity and its associated role.

| Column       | Data type    | Null allowed? | Key/constraint                                                   | Description/example                                 |
| ------------ | ------------ | ------------- | ---------------------------------------------------------------- | --------------------------------------------------- |
| UserID       | INT          | No            | PK, AUTO_INCREMENT                                               | Unique user identifier                              |
| Username     | VARCHAR(100) | No            | UNIQUE                                                           | User login name                                     |
| Name         | VARCHAR(100) | No            | None                                                             | User’s name                                         |
| RoleType     | VARCHAR(30)  | No            | CHECK (RoleType IN (‘Service Advisor’, ‘Technician’, ‘Manager’)) | User’s system role                                  |
| TechnicianID | INT          | Yes           | FK, UNIQUE → Technician(TechnicianID)                            | Technician associated with account, when applicable |

#### Rules implemented by this table:

- FR-07 controls what users can view or modify based on their role.
- Username must be unique.
- RoleType is restricted to Service Advisor, Technician, or Manager.
- TechnicianID is optional and links a technician account to its Technician record.
- Customers do not have UserAccount records and do not directly access the system.

### Table: AuditLog

**Purpose:** Stores one row for each auditable database action performed by a user.

| Column           | Data type    | Null allowed? | Key/constraint           | Description/example                                                    |
| ---------------- | ------------ | ------------- | ------------------------ | ---------------------------------------------------------------------- |
| AuditLogID       | INT          | No            | PK, AUTO_INCREMENT       | Unique audit entry identifier                                          |
| UserID           | INT          | No            | FK → UserAccount(UserID) | User who performed the action                                          |
| Timestamp        | DATETIME     | No            | None                     | Date/time the action occurred                                          |
| Action           | VARCHAR(50)  | No            | None                     | Action performed, such as create, update, cancel, approve, or finalize |
| AffectedEntity   | VARCHAR(100) | No            | None                     | Type of record affected, such as Invoice or ServiceAppointment         |
| AffectedRecordID | INT          | No            | None                     | Identifier of the affected record                                      |
| PreviousValue    | JSON         | Yes           | None                     | Relevant values before the change                                      |
| NewValue         | JSON         | Yes           | None                     | Relevant values after the change                                       |

#### Rules implemented by this table:

- FR-08 requires audit entries for important creates, updates, completions, cancellations, approvals, finalizations, status changes, technician reassignments, inventory adjustments, and parts-usage changes.
- Each audit entry records the responsible user, timestamp, action, affected entity, affected record identifier, and relevant old/new values.
- SEC-03 requires important changes to service appointments, repairs, repair estimates, and invoices to be auditable.
- AuditLog records should not be directly modified by ordinary users.

## 8. Normalization Analysis

The database is designed to satisfy First Normal Form, Second Normal Form, and Third Normal Form.

| Normal Form              | Design check                                                     | Evidence in this project                                                                                                                                                                                                                     |
| ------------------------ | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| First Normal Form (1NF)  | Columns contain atomic values and there are no repeating groups. | Each column stores a single value. Multiple parts used in a repair are stored as separate PartsUsage rows rather than repeating part fields in Repair.                                                                                       |
| Second Normal Form (2NF) | Every non-key attribute depends on the entire primary key.       | Most tables use a single-column primary key, so partial dependencies do not occur. EstimateLineItem uses the composite key (EstimateID, LineNumber) and its description, quantity, unit price, and total depend on that full key.            |
| Third Normal Form (3NF)  | Non-key attributes do not depend on other non-key attributes.    | Customer, technician, part, and user information are stored in their own tables. Related tables reference them using foreign keys instead of repeating descriptive information, which prevents transitive dependencies and update anomalies. |

## 9. Integrity, validation, and business-rule enforcement

| Business rule ID | Rule                                                                          | Technical implementation                                                                                | Verification method                                                                                        |
| ---------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| BR-01            | Each major record must have a unique identifier.                              | PRIMARY KEY constraints on each table.                                                                  | Attempt to insert a duplicate primary-key value and verify that MySQL rejects it.                          |
| BR-02            | Each vehicle must belong to exactly one customer.                             | Vehicle.CustomerID is NOT NULL and a foreign key to customer(CustomerID)                                | Attempt to insert a vehicle with a nonexistent CustomerID and verify rejection.                            |
| BR-03            | Repairs and parts have a many-to-many relationship.                           | PartsUsage junction table with foreign keys to Repair and Part.                                         | Insert multiple parts for one repair and the same part for multiple repairs, then query the relationships. |
| BR-04            | Duplicate active appointments for the same vehicle/date/time are not allowed. | Controlled procedure or validation logic checks for an existing active appointment before insertion.    | Attempt to create a duplicate active appointment and verify rejection.                                     |
| BR-05            | Status values must use allowed values.                                        | CHECK constraints on the Status columns of ServiceAppointment, Repair, RepairEstimate, and Invoice.     | Attempt to insert an invalid status value and verify rejection.                                            |
| BR-06            | Only authorized roles may create or modify protected records.                 | MySQL roles/privileges, protected views, and/or stored procedures.                                      | Attempt an allowed action with an authorized role and the same action with an unauthorized role.           |
| BR-07            | Important changes must be auditable.                                          | AuditLog table plus triggers or controlled procedures that insert audit records.                        | Perform an audited update and verify the corresponding AuditLog row is created.                            |
| BR-08            | Multi-step repair completion must either fully succeed or fully roll back.    | Stored procedure using START TRANSACTION, COMMIT, and ROLLBACK.                                         | Force one step to fail and verify that none of the earlier changes remain.                                 |
| BR-09            | A technician cannot be assigned to conflicting active appointments.           | Procedure or validation query checks technician/date/time conflicts before insert/update.               | Attempt to assign one technician to two active appointments at the same time and verify rejection.         |
| BR-10            | Parts usage cannot reduce inventory below zero.                               | Procedure/trigger checks QuantityOnHand \>= QuantityUsed before recording usage and updating inventory. | Attempt to use more parts than are available and verify rejection with inventory unchanged.                |
