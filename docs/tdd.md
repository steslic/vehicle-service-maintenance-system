# Technical Design Document

## 1. Project Identification

| Item           | Information                                       |
| -------------- | ------------------------------------------------- |
| Project title  | Vehicle Service and Maintenance Management System |
| Prepared by    | Sebastian Teslic                                  |
| Course/section | 01:198:437                                        |
| Date           | 10/15/2026                                        |
| Version        | 1.1                                               |

## 2. Design overview

This project implements a relational database for an independent auto repair shop. The database will manage customers, vehicles, technicians, service appointments, repairs, repair estimates, estimate line items, parts, parts usage, invoices, invoice line items, user accounts, and audit records. It will use MySQL and will support service appointment scheduling, technician assignment, repair and parts recording, estimate and invoice management, maintenance history retrieval, audit logging, and reports on shop workload, common repairs, low parts inventory, and parts revenue. The design consists of 13 related tables and enforces data integrity through primary keys, foreign keys, unique constraints, check constraints, triggers, stored procedures, and database transaction controls.

## 3. Technical environment

| Component                  | Selected technology/tool | Purpose                               |
| -------------------------- | ------------------------ | ------------------------------------- |
| Database management system | MySQL 8.0.16 or later    | Store and manage relational data      |
| Database client/IDE        | MySQL Workbench          | Design, execute, and test SQL         |
| Modeling tool              | draw.io                  | Create ERD and schema diagram         |
| Source control             | GitHub                   | Version SQL scripts and documentation |
| Operating environment      | MacOS                    | Development and testing environment   |

## 4. Architecture and scope

The solution uses a relational database architecture. Users or a future application interface will submit data-entry, update, and reporting requests to the database. The database will store normalized records for customers, vehicles, technicians, service appointments, repairs, repair estimates, estimate line items, parts, parts usage, invoices, invoice line items, user accounts, and audit records. MySQL will enforce referential integrity and will return query results. A user interface is outside the scope unless specifically required.

The project uses a single MySQL database/schema. It will use fictional, non-sensitive sample data for development and testing. The project focuses on database implementation rather than the development of a website or mobile application. Real payment processing, external scheduling systems, AI diagnostics, and external vehicle history integrations are outside the scope. Production backup schedules and enterprise-scale performance tuning are outside the scope unless required.

## 5. Entity-relationship design

The complete ER diagram is maintained in the project repository under the `docs/` directory as an editable draw.io file and exported SVG.

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

### ER-to-Relational Mapping Documentation

| ER Component                                          | Database Implementation                                    | Constraints Applied                                                    |
| ----------------------------------------------------- | ---------------------------------------------------------- | ---------------------------------------------------------------------- |
| Customer strong entity                                | Customer table                                             | CustomerID primary key                                                 |
| Vehicle strong entity                                 | Vehicle table                                              | VehicleID primary key, CustomerID foreign key, VIN UNIQUE              |
| Customer-Vehicle 1:N relationship                     | CustomerID stored in Vehicle                               | Foreign key, NOT NULL, referential integrity                           |
| Technician strong entity                              | Technician table                                           | TechnicianID primary key, Email UNIQUE                                 |
| Technician-ServiceAppointment 1:N relationship        | TechnicianID stored in ServiceAppointment                  | Foreign key, NOT NULL                                                  |
| Vehicle-ServiceAppointment 1:N relationship           | VehicleID stored in ServiceAppointment                     | Foreign key, NOT NULL                                                  |
| ServiceAppointment-Repair 1:N relationship            | AppointmentID stored in Repair                             | Foreign key, NOT NULL                                                  |
| Repair-Part M:N relationship                          | PartsUsage junction table                                  | PartsUsageID primary key; foreign keys RepairID and PartID             |
| RepairEstimate weak-entity relationship               | EstimateLineItem table                                     | Composite primary key (EstimateID, LineNumber); EstimateID foreign key |
| ServiceAppointment-RepairEstimate 1:0..1 relationship | AppointmentID stored in RepairEstimate                     | Foreign key, UNIQUE                                                    |
| ServiceAppointment-Invoice 1:0..1 relationship        | AppointmentID stored in Invoice                            | Foreign key, UNIQUE                                                    |
| Invoice-InvoiceLineItem 1:N relationship              | InvoiceID stored in InvoiceLineItem                        | Foreign key, NOT NULL                                                  |
| Technician-UserAccount 1:0..1 relationship            | TechnicianID stored in UserAccount                         | Foreign key, UNIQUE, nullable                                          |
| UserAccount-AuditLog 1:N relationship                 | UserID stored in AuditLog                                  | Foreign key, NOT NULL                                                  |
| UserAccount-ServiceAppointment 1:N relationship       | CreatedByUserID stored in ServiceAppointment               | Foreign key, NOT NULL                                                  |
| UserAccount-RepairEstimate relationships              | CreatedByUserID, ApprovedByUserID stored in RepairEstimate | Foreign keys; approval FK nullable                                     |
| UserAccount-Invoice relationships                     | CreatedByUserID, FinalizedByUserID stored in Invoice       | Foreign keys; finalization FK nullable                                 |
| UserAccount-PartsUsage 1:N relationship               | RecordedByUserID stored in PartsUsage                      | Foreign key, NOT NULL                                                  |
| Technician-Repair relationship                        | CompletedByTechnicianID stored in Repair                   | Foreign key, nullable until completion                                 |

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
- trg_ServiceAppointment_Status_Validate enforces valid status transitions (FR-14, FR-19). trg_ServiceAppointment_Audit records important changes (FR-08).

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
- trg_Repair_Status_Validate enforces valid status transitions (FR-19). trg_Repair_Audit records creation, completion, and status changes (FR-08).

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
- trg_RepairEstimate_Validate blocks updates and deletes after finalization (FR-18). trg_RepairEstimate_Audit records approvals and status changes (FR-08). Requires a Manager as the approving user (SEC-01).

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
- trg_EstimateLineItem_Validate blocks inserts, updates, and deletes once the parent estimate is finalized (FR-18).

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
- trg_PartInventory_Audit records quantity changes (FR-08, FR-13).

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
- FR-12 validates sufficient inventory before parts usage is recorded.
- FR-13 reduces inventory when parts usage is recorded.
- BR-03 resolves the Repair-to-Part many-to-many relationship through PartsUsage.
- BR-10 prevents parts usage from reducing quantity on hand below zero.
- trg_PartsUsage_Audit records additions, updates, and reversals (FR-08).

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
- trg_Invoice_Validate blocks updates and deletes after finalization (FR-18). trg_Invoice_Audit records changes and finalization (FR-08).

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
- trg_InvoiceLineItem_Validate blocks inserts, updates, and deletes once the parent invoice is finalized (FR-18).

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
- trg_AuditLog_Protect rejects all UPDATE and DELETE operations, so audit rows are append-only (BR-07, SEC-03).

## 8. Normalization Analysis

The database is designed to satisfy First Normal Form, Second Normal Form, and Third Normal Form.

| Normal Form              | Design check                                                     | Evidence in this project                                                                                                                                                                                                                     |
| ------------------------ | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| First Normal Form (1NF)  | Columns contain atomic values and there are no repeating groups. | Each column stores a single value. Multiple parts used in a repair are stored as separate PartsUsage rows rather than repeating part fields in Repair.                                                                                       |
| Second Normal Form (2NF) | Every non-key attribute depends on the entire primary key.       | Most tables use a single-column primary key, so partial dependencies do not occur. EstimateLineItem uses the composite key (EstimateID, LineNumber) and its description, quantity, unit price, and total depend on that full key.            |
| Third Normal Form (3NF)  | Non-key attributes do not depend on other non-key attributes.    | Customer, technician, part, and user information are stored in their own tables. Related tables reference them using foreign keys instead of repeating descriptive information, which prevents transitive dependencies and update anomalies. |

## 9. Integrity, validation, and business-rule enforcement

| Business rule ID | Rule                                                                          | Technical implementation                                                                                                                                                                                                                                                                                                    | Verification method                                                                                        |
| ---------------- | ----------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| BR-01            | Each major record must have a unique identifier.                              | PRIMARY KEY constraints on each table.                                                                                                                                                                                                                                                                                      | Attempt to insert a duplicate primary-key value and verify that MySQL rejects it.                          |
| BR-02            | Each vehicle must belong to exactly one customer.                             | Vehicle.CustomerID is NOT NULL and a foreign key to customer(CustomerID)                                                                                                                                                                                                                                                    | Attempt to insert a vehicle with a nonexistent CustomerID and verify rejection.                            |
| BR-03            | Repairs and parts have a many-to-many relationship.                           | PartsUsage junction table with foreign keys to Repair and Part.                                                                                                                                                                                                                                                             | Insert multiple parts for one repair and the same part for multiple repairs, then query the relationships. |
| BR-04            | Duplicate active appointments for the same vehicle/date/time are not allowed. | sp_CreateServiceAppointment checks for an existing active appointment for the same vehicle before inserting.                                                                                                                                                                                                                | Attempt to create a duplicate active appointment and verify rejection.                                     |
| BR-05            | Status values must use allowed values.                                        | CHECK constraints on the Status columns of ServiceAppointment, Repair, RepairEstimate, and Invoice. Status-validate triggers reject invalid transitions.                                                                                                                                                                    | Attempt to insert an invalid status value and verify rejection.                                            |
| BR-06            | Only authorized roles may create or modify protected records.                 | MySQL roles role_service_advisor, role_technician, and role_manager, each granted table- and column-level privileges matching its entitlements (section 10). Technicians write only through sp_CompleteRepair and the Status column of Repair. No role has UPDATE or DELETE on AuditLog.                                    | Attempt an allowed action with an authorized role and the same action with an unauthorized role.           |
| BR-07            | Important changes must be auditable.                                          | AuditLog table, audit triggers `trg_ServiceAppointment_Audit`, `trg_Repair_Audit`, `trg_RepairEstimate_Audit`, `trg_Invoice_Audit`, `trg_PartInventory_Audit`, `trg_PartsUsage_Audit`, which insert AuditLog rows on create, update, and delete; and `trg_AuditLog_Protect`, which rejects updates and deletes on AuditLog. | Perform an audited update and verify the corresponding AuditLog row is created.                            |
| BR-08            | Multi-step repair completion must either fully succeed or fully roll back.    | Stored procedure using START TRANSACTION, COMMIT, and ROLLBACK.                                                                                                                                                                                                                                                             | Force one step to fail and verify that none of the earlier changes remain.                                 |
| BR-09            | A technician cannot be assigned to conflicting active appointments.           | sp_CreateServiceAppointment checks technician/date/time conflicts before insert.                                                                                                                                                                                                                                            | Attempt to assign one technician to two active appointments at the same time and verify rejection.         |
| BR-10            | Parts usage cannot reduce inventory below zero.                               | CHECK (QuantityOnHand >= 0) on Part rejects any update that would make inventory negative. sp_CompleteRepair also locks each requested part with SELECT ... FOR UPDATE and verifies that QuantityOnHand >= QuantityUsed for every part before recording any usage, so an insufficient part rolls back the whole operation.  | Attempt to use more parts than are available and verify rejection with inventory unchanged.                |

## 10. Database objects and SQL design

| Object type      | Object name                                  | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                | Related requirements                            |
| ---------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------- |
| View             | `vw_VehicleServiceHistory`                   | Displays completed repairs and parts used for a selected vehicle.                                                                                                                                                                                                                                                                                                                                                                                      | FR-04, RQ-02                                    |
| View             | `vw_TechnicianWorkload`                      | Displays service appointments assigned to each technician for workload reporting.                                                                                                                                                                                                                                                                                                                                                                      | FR-06, RQ-05                                    |
| Stored procedure | `sp_CreateServiceAppointment`                | Validates required appointment data (future date/time, positive duration, non-empty description), confirms the vehicle belongs to the customer, the technician is active, and the creating user exists; rejects the appointment if it overlaps an active appointment for the same vehicle or technician, using each appointment's estimated duration; then inserts it with status Scheduled and returns the new AppointmentID, all in one transaction. | FR-02, FR-05, FR-15, FR-16, BR-04, BR-09        |
| Stored procedure | `sp_CompleteRepair`                          | Validates that the repair is In Progress, and validates the appointment, technician, and recording user; records usage for zero or more parts passed as a JSON array; reduces inventory; and marks the repair completed. All changes commit or roll back as one transaction. Audit records are written by the table triggers.                                                                                                                          | FR-03, FR-12, FR-13, FR-20, BR-03, BR-08, BR-10 |
| Trigger          | `trg_ServiceAppointment_Audit`               | Automatically creates an AuditLog record when important service-appointment data is changed.                                                                                                                                                                                                                                                                                                                                                           | FR-08, SEC-03                                   |
| Trigger          | `trg_Invoice_Audit`                          | Automatically records important invoice changes and finalization activity.                                                                                                                                                                                                                                                                                                                                                                             | FR-08, FR-18, SEC-03                            |
| Trigger          | `trg_RepairEstimate_Audit`                   | Automatically records important repair-estimate changes, approvals, finalization, and status changes in AuditLog.                                                                                                                                                                                                                                                                                                                                      | FR-08, FR-18, SEC-03                            |
| Trigger          | `trg_PartInventory_Audit`                    | Records inventory quantity changes in AuditLog, including the previous and new quantity and the adjustment reason from the session variable `@adj_reason`; rejects a quantity change when no reason is set.                                                                                                                                                                                                                                            | FR-08, FR-13, SEC-03                            |
| Trigger          | `trg_Repair_Audit`                           | Automatically records repair creation, updates, completion, and status changes in AuditLog.                                                                                                                                                                                                                                                                                                                                                            | FR-03, FR-08, SEC-03                            |
| Trigger          | `trg_PartsUsage_Audit`                       | Automatically records parts usage additions, updates, and reversals in AuditLog.                                                                                                                                                                                                                                                                                                                                                                       | FR-08, FR-12, FR-13, SEC-03                     |
| Trigger          | `trg_Invoice_Validate`                       | Allows only the Draft to Finalized status transition, requires a finalizing user and finalization date/time when an invoice is finalized, and prevents finalized invoices from being modified or deleted.                                                                                                                                                                                                                                              | FR-18, FR-19, SEC-01                            |
| Trigger          | `trg_RepairEstimate_Validate`                | Allows only the status transitions Draft → Pending Approval, Pending Approval → Approved/Rejected/Expired, and Approved → Finalized; requires the approving user to have the Manager role when an estimate is approved; and prevents finalized estimates from being modified or deleted.                                                                                                                                                               | FR-18, FR-19, SEC-01                            |
| Trigger          | `trg_Repair_Status_Validate`                 | Allows only the status transitions Open → In Progress, In Progress → Completed, and Open/In Progress → Cancelled; rejects all others, such as changing a completed repair back to In Progress.                                                                                                                                                                                                                                                         | FR-19, BR-05                                    |
| Trigger          | `trg_ServiceAppointment_Status_Validate`     | Allows only the status transitions Scheduled → Checked In → In Progress → Completed and Scheduled → Cancelled/No Show; rejects all others, such as changing a completed appointment back to Scheduled.                                                                                                                                                                                                                                                 | FR-14, FR-19, BR-05                             |
| Trigger          | `trg_InvoiceLineItem_Validate`               | Prevents invoice line items from being inserted, updated, or deleted after the associated invoice has been finalized.                                                                                                                                                                                                                                                                                                                                  | FR-17, FR-18, SEC-01                            |
| Trigger          | `trg_EstimateLineItem_Validate`              | Prevents estimate line items from being inserted, updated, or deleted after the associated repair estimate has been finalized.                                                                                                                                                                                                                                                                                                                         | FR-17, FR-18, SEC-01                            |
| Trigger          | `trg_AuditLog_Protect`                       | Prevents existing audit records from being updated or deleted, preserving audit history.                                                                                                                                                                                                                                                                                                                                                               | FR-08, SEC-03, BR-07                            |
| Index            | `idx_ServiceAppointment_DateTime`            | Supports appointment queries filtered by date and time.                                                                                                                                                                                                                                                                                                                                                                                                | RQ-01                                           |
| Index            | `idx_ServiceAppointment_Technician_DateTime` | Supports technician workload queries and scheduling-conflict checks using technician and appointment time.                                                                                                                                                                                                                                                                                                                                             | FR-06, FR-16, RQ-05                             |
| Index            | `idx_ServiceAppointment_Vehicle_DateTime`    | Supports duplicate/conflicting appointment checks for the same vehicle at the same date and time.                                                                                                                                                                                                                                                                                                                                                      | FR-02, BR-04                                    |
| Index            | `idx_AuditLog_Entity_Record`                 | Supports audit-history lookups for a specific business record in chronological order.                                                                                                                                                                                                                                                                                                                                                                  | FR-08, SEC-03                                   |
| Index            | `idx_Repair_Status_Type`                     | Supports the common repairs report by filtering completed repairs and grouping them by repair type.                                                                                                                                                                                                                                                                                                                                                    | FR-09, RQ-03                                    |
| Role             | `role_service_advisor`                       | Creates and updates customers, vehicles, appointments, technician assignments, non-finalized estimates, and non-finalized invoices; finalizes invoices; cannot approve estimates or modify AuditLog.                                                                                                                                                                                                                                                   | FR-07, BR-06, SEC-02                            |
| Role             | `role_technician`                            | Views assigned appointments; may update only the Status column of Repair (limited to the transitions allowed by `trg_Repair_Status_Validate`); completes repairs through `sp_CompleteRepair`; has no other direct write access to protected tables.                                                                                                                                                                                                    | FR-07, BR-06, SEC-02                            |
| Role             | `role_manager`                               | Has broad operational and reporting access, including estimate approval, technician reassignment, invoice finalization, and inventory adjustments; has SELECT-only access to AuditLog.                                                                                                                                                                                                                                                                 | FR-07, BR-06, SEC-01, SEC-02                    |

Each trigger object listed above is implemented as one MySQL trigger per event and timing, because MySQL triggers handle a single event. For example, `trg_Invoice_Audit` consists of AFTER INSERT, AFTER UPDATE, and AFTER DELETE triggers, and `trg_Invoice_Validate` consists of BEFORE UPDATE and BEFORE DELETE triggers.

Because MySQL stored procedures do not support array parameters, `sp_CompleteRepair` accepts parts as a JSON array, which is parsed with `JSON_TABLE` and stored as normalized PartsUsage rows.

## 11. Query and report design

| Query ID | Query/report               | Main tables                                           | Key SQL features                   | Expected result                                                                                                                               |
| -------- | -------------------------- | ----------------------------------------------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| RQ-01    | Daily Service Appointments | ServiceAppointment, Vehicle, Technician               | JOIN, WHERE, ORDER BY              | Service appointments for a selected day showing appointment date/time, vehicle, assigned technician, and status, ordered by appointment time. |
| RQ-02    | Vehicle Service History    | Vehicle, ServiceAppointment, Repair, PartsUsage, Part | Multiple JOINs, WHERE, ORDER BY    | Completed repairs for a selected vehicle, including repair description, completion date, parts used, and quantity used                        |
| RQ-03    | Common Repairs Report      | Repair                                                | WHERE, GROUP BY, COUNT(), ORDER BY | Repair types with the number of completed repairs, ordered from most common to least common.                                                  |
| RQ-04    | Low Parts Inventory Report | Part                                                  | WHERE, comparison                  | Parts whose QuantityOnHand is below MinimumInventoryLevel, showing part ID, part name, quantity available, and minimum level.                 |
| RQ-05    | Shop Workload Report       | Technician, ServiceAppointment                        | LEFT JOIN, COUNT(), GROUP BY       | Each technician with the number of active or scheduled appointments assigned to them.                                                         |
| RQ-06    | Parts Revenue Report       | Part, PartsUsage, Repair                              | JOIN, SUM(), GROUP BY              | Part name, total quantity used, and total revenue generated from parts used in repairs.                                                       |

## 12. Security, privacy, and backup assumptions

- Access to the database will be limited to authorized project users through MySQL database credentials.
- Role-based permissions will be used to restrict actions for Service Advisor, Technician, and Manager users according to the project’s entitlement requirements.
- Customers do not have direct database or system access.
- The project will use fictional sample data only and will not include real credit-card numbers, passwords, Social Security numbers, or other highly sensitive information.
- Audit logging will be used to record important changes to protected operational records.
- Audit triggers identify the acting user through the session variable @app_user_id. Stored procedures set it from their user ID parameter and clear it after commit or rollback; direct writes (such as status updates or inventory adjustments) must set it at the start of the session. An audited write without it is rejected so every AuditLog row has a valid UserID. In this course implementation the variable is trusted as supplied; a production system would set it in middleware after authentication.
- AuditLog is append-only: audit rows are inserted only by triggers, which run with their definer’s privileges; managers receive SELECT only, other roles have no direct access, and trg_AuditLog_Protect rejects any UPDATE or DELETE.
- Foreign keys on audited tables use the default RESTRICT behavior instead of ON DELETE CASCADE, because MySQL cascades do not fire triggers and cascaded deletes would leave no audit record.
- In a production environment, the database would use encrypted connections, stronger credential management, scheduled backups, access monitoring, and a documented backup and recovery process.
- Production-grade security hardening, automated backup scheduling, disaster recovery, and enterprise-scale security monitoring are outside the scope of this course implementation unless specifically required.
- Inventory quantity changes require an adjustment reason in the session variable `@adj_reason`, which `trg_PartInventory_Audit` stores in the audit record's NewValue. Managers set it before manual adjustments; `sp_CompleteRepair` sets it automatically (for example, "Parts usage for repair 12") and clears it afterward.

### Performance and scalability considerations

Indexes will be used on frequently searched appointment dates, technician assignments, and foreign-key columns, which InnoDB indexes automatically, to support common reads and joins. Query performance will be evaluated using EXPLAIN. Multi-step repair completion will use transactions to maintain consistency during updates. Large batch inserts and data extracts should be processed in manageable batches to reduce long-running locks and excessive transaction size. As appointment, repair, and audit data grows, indexes on frequently filtered foreign keys, dates, and status columns can be reviewed and adjusted based on query plans. Enterprise-scale performance tuning is outside the scope of this class implementation.

## 13. Test plan and acceptance criteria

| Test ID | Requirement/rule | Test action                                                                                          | Expected result                                                                                                                                              | Actual result/pass-fail |
| ------- | ---------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------- |
| T-01    | FR-01            | Insert a valid customer and vehicle with all required fields.                                        | Customer and vehicle records are inserted with unique IDs, and the vehicle references the correct customer.                                                  |                         |
| T-02    | FR-05 / BR-02    | Attempt to insert a vehicle with a CustomerID that does not exist.                                   | Insert is rejected by the foreign key constraint.                                                                                                            |                         |
| T-03    | FR-02            | Create a valid service appointment for an existing vehicle and active technician.                    | Appointment is created with status Scheduled and correct vehicle, technician, creating user, and timestamp.                                                  |                         |
| T-04    | BR-04            | Attempt to create a duplicate active appointment for the same vehicle at the same date/time.         | Appointment creation is rejected by `sp_CreateServiceAppointment`.                                                                                           |                         |
| T-05    | FR-16 / BR-09    | Attempt to assign the same technician to two conflicting active appointments.                        | Second assignment is rejected.                                                                                                                               |                         |
| T-06    | BR-05 / FR-19    | Use an invalid status value.                                                                         | Operation is rejected.                                                                                                                                       |                         |
| T-07    | FR-12 / BR-10    | Record more parts usage than inventory allows.                                                       | Operation is rejected and inventory stays unchanged.                                                                                                         |                         |
| T-08    | FR-13            | Record valid parts usage.                                                                            | PartsUsage is created and inventory decreases.                                                                                                               |                         |
| T-09    | FR-20 / BR-08    | Force repair completion to fail midway.                                                              | Entire transaction rolls back.                                                                                                                               |                         |
| T-10    | FR-08 / SEC-03   | Perform an audited update.                                                                           | Correct AuditLog record is created.                                                                                                                          |                         |
| T-11    | SEC-02           | Technician attempts to modify protected data.                                                        | Operation is denied.                                                                                                                                         |                         |
| T-12    | RQ-02 / RQ-05    | Run service-history and workload queries.                                                            | Queries return the expected records and counts.                                                                                                              |                         |
| T-13    | FR-18 / SEC-01   | Finalize an invoice, then attempt to update or delete it.                                            | Modification or deletion is rejected and the finalized record remains unchanged.                                                                             |                         |
| T-14    | RQ-01            | Run the Daily Service Appointments query for a selected date.                                        | Query returns appointments for that date with vehicle, technician, status, and appointment time.                                                             |                         |
| T-15    | RQ-02            | Run the Vehicle Service History query for a selected vehicle.                                        | Query returns completed repairs and parts used for that vehicle.                                                                                             |                         |
| T-16    | RQ-05            | Run the Shop Workload report.                                                                        | Results show technicians with their assigned appointment counts.                                                                                             |                         |
| T-17    | RQ-06            | Run the Parts Revenue Report.                                                                        | Results show part names, total quantity used, and calculated parts revenue.                                                                                  |                         |
| T-18    | FR-03 / FR-20    | Complete a valid repair with valid parts usage.                                                      | Repair is completed, two PartsUsage rows are recorded, inventory decreases for both parts, audit triggers create AuditLog rows, and the transaction commits. |                         |
| T-19    | FR-19            | Attempt an invalid status transition, such as changing a Completed repair back to In Progress.       | Operation is rejected and the record remains unchanged.                                                                                                      |                         |
| T-20    | FR-18 / SEC-01   | Finalize an invoice, then attempt to insert, update, or delete one of its line items.                | Operation is rejected and the invoice line items remain unchanged.                                                                                           |                         |
| T-21    | FR-18 / SEC-01   | Finalize a repair estimate, then attempt to update or delete it or one of its line items.            | Operation is rejected and the estimate and its line items remain unchanged.                                                                                  |                         |
| T-22    | BR-07 / SEC-03   | Attempt to update or delete an existing AuditLog record.                                             | Operation is rejected and the audit record remains unchanged.                                                                                                |                         |
| T-23    | FR-08            | Update an audited record without changing any of its values.                                         | No new AuditLog record is created.                                                                                                                           |                         |
| T-24    | FR-14 / FR-19    | Attempt to change a Completed appointment back to Scheduled.                                         | Operation is rejected and the appointment remains unchanged.                                                                                                 |                         |
| T-25    | FR-08            | Perform an audited write without setting @app_user_id.                                               | Operation is rejected because the acting user is unknown.                                                                                                    |                         |
| T-26    | FR-20 / BR-08    | Complete a repair with two parts where the second part has insufficient inventory.                   | Operation is rejected; no PartsUsage rows are added, inventory is unchanged, the repair is not completed, and no AuditLog rows are created.                  |                         |
| T-27    | SEC-01           | Attempt to approve a repair estimate as a user who does not have the Manager role.                   | Operation is rejected and the estimate status remains unchanged.                                                                                             |                         |
| T-28    | FR-13 / SEC-03   | As a Manager, adjust a part's QuantityOnHand without setting @adj_reason, then again with a reason.  | The first update is rejected; the second succeeds and its AuditLog record contains the previous quantity, new quantity, and reason.                          |                         |
| T-29    | SEC-02           | As a Technician, change the status of a repair on an appointment assigned to a different technician. | Operation is rejected and the repair status remains unchanged.                                                                                               |                         |

## 14. Requirement traceability

| Functional Requirement                         | Tables/relationships                                                        | Constraints or objects                                                                                                                                                      | Query/report/test evidence                               |
| ---------------------------------------------- | --------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| FR-01: Store customer and vehicle records      | Customer → Vehicle                                                          | CustomerID PK; VehicleID PK; Vehicle.CustomerID FK; VIN UNIQUE                                                                                                              | T-01; customer/vehicle insert demonstration              |
| FR-02: Create service appointments             | Vehicle → ServiceAppointment ← Technician; UserAccount → ServiceAppointment | Appointment PK; vehicle/technician/user FKs; `sp_CreateServiceAppointment`; required-field/status checks                                                                    | T-03; RQ-01 Daily Service Appointments                   |
| FR-03: Record completed repairs                | ServiceAppointment → Repair ← Technician                                    | RepairID PK; AppointmentID FK; technician FK; repair-status checks; `sp_CompleteRepair`; `trg_Repair_Status_Validate`                                                       | T-18; T-19; RQ-02 Vehicle Service History                |
| FR-04: Display vehicle service history         | Vehicle → ServiceAppointment → Repair → PartsUsage → Part                   | FKs connecting vehicle, appointment, repair, and parts usage; `vw_VehicleServiceHistory`                                                                                    | RQ-02 Vehicle Service History                            |
| FR-05: Validate appointment data               | Vehicle, Technician, ServiceAppointment                                     | FKs; validation in `sp_CreateServiceAppointment`                                                                                                                            | T-02; T-03                                               |
| FR-06: Track technician workload               | Technician → ServiceAppointment                                             | TechnicianID FK; `vw_TechnicianWorkload`; technician/date index                                                                                                             | RQ-05 Shop Workload Report                               |
| FR-07: Restrict access based on role           | UserAccount, protected operational tables                                   | RoleType CHECK; `role_service_advisor`, `role_technician`, `role_manager`; EXECUTE granted on procedures; manager-role check in `trg_RepairEstimate_Validate`               | T-11; T-27                                               |
| FR-08: Maintain audit history                  | UserAccount → AuditLog; audited operational tables                          | AuditLog FKs; audit triggers on ServiceAppointment, Repair, RepairEstimate, Invoice, Part, PartsUsage; `trg_AuditLog_Protect`; `@app_user_id`; `idx_AuditLog_Entity_Record` | T-10; T-22; T-23; T-25                                   |
| FR-09: Report common repairs and parts revenue | Repair, Part, PartsUsage                                                    | RQ-03 and RQ-06 report queries; GROUP BY, COUNT(), SUM(); `idx_Repair_Status_Type`                                                                                          | RQ-03 Common Repairs Report; RQ-06 Parts Revenue Report  |
| FR-10: Create repair estimates and invoices    | ServiceAppointment, RepairEstimate, Invoice, UserAccount                    | Appointment FKs; CreatedByUserID FKs; status checks; UNIQUE AppointmentID                                                                                                   | Estimate/invoice creation demonstration                  |
| FR-11: Manage part inventory                   | Part                                                                        | PartID PK; PartNumber UNIQUE; inventory/cost/price CHECK constraints                                                                                                        | Part inventory INSERT/UPDATE/SELECT demonstration; RQ-04 |
| FR-12: Record parts used during repairs        | Repair → PartsUsage ← Part                                                  | RepairID FK; PartID FK; quantity checks; `sp_CompleteRepair` (JSON parts list); `trg_PartsUsage_Audit`                                                                      | T-07; T-08; T-26                                         |
| FR-13: Update inventory after parts usage      | Part → PartsUsage                                                           | QuantityOnHand CHECK; `sp_CompleteRepair`; `trg_PartInventory_Audit`                                                                                                        | T-08; T-26                                               |
| FR-14: Modify non-completed appointments       | ServiceAppointment, Technician, Vehicle                                     | Status CHECK; `trg_ServiceAppointment_Status_Validate`                                                                                                                      | T-24; appointment update/reschedule/cancel demonstration |
| FR-15: Validate vehicle ownership              | Customer, Vehicle, ServiceAppointment, RepairEstimate, Repair, Invoice      | Vehicle.CustomerID FK; ownership check in `sp_CreateServiceAppointment`; estimates, repairs, and invoices inherit the validated owner through AppointmentID                 | T-03; vehicle-ownership rejection demonstration          |
| FR-16: Prevent technician scheduling conflicts | Technician → ServiceAppointment                                             | `sp_CreateServiceAppointment` duration-based overlap check; `idx_ServiceAppointment_Technician_DateTime`                                                                    | T-05                                                     |
| FR-17: Store estimate and invoice line items   | RepairEstimate, EstimateLineItem, Invoice, InvoiceLineItem                  | EstimateLineItem composite PK; line-item FKs; quantity/unit-price CHECK constraints; `trg_EstimateLineItem_Validate`; `trg_InvoiceLineItem_Validate`                        | T-20; T-21; line-item creation demonstration             |
| FR-18: Protect finalized records               | RepairEstimate, EstimateLineItem, Invoice, InvoiceLineItem                  | `trg_Invoice_Validate`; `trg_RepairEstimate_Validate`; `trg_InvoiceLineItem_Validate`; `trg_EstimateLineItem_Validate`                                                      | T-13; T-20; T-21                                         |
| FR-19: Enforce valid status transitions        | ServiceAppointment, Repair, RepairEstimate, Invoice                         | Status CHECK constraints; `trg_ServiceAppointment_Status_Validate`; `trg_Repair_Status_Validate`; `trg_RepairEstimate_Validate`; `trg_Invoice_Validate`                     | T-06; T-19; T-24                                         |
| FR-20: Use transactions for repair completion  | Repair, PartsUsage, Part, AuditLog                                          | `sp_CompleteRepair`; START TRANSACTION, COMMIT, ROLLBACK; audit rows written by triggers roll back with the transaction                                                     | T-09; T-18; T-26                                         |
