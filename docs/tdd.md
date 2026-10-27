# Technical Design Document

## 1. Project Identification

| Item           | Information                                       |
| -------------- | ------------------------------------------------- |
| Project title  | Vehicle Service and Maintenance Management System |
| Prepared by    | Sebastian Teslic                                  |
| Course/section | 01:198:437                                        |
| Date           | 10/25/2026                                        |
| Version        | 1.5                                               |

## 2. Design overview

This project implements a relational database for an independent auto repair shop. The database will manage customers, vehicles, technicians, service appointments, repairs, repair estimates, estimate line items, parts, parts usage, invoices, invoice line items, user accounts, and audit records. It will use MySQL and will support service appointment scheduling, technician assignment, repair and parts recording, estimate and invoice management, maintenance history retrieval, audit logging, and reports on shop workload, common repairs, low parts inventory, and parts revenue. The design consists of 13 related tables and enforces data integrity through primary keys, foreign keys, unique constraints, check constraints, triggers, stored procedures, and database transaction controls.

## 3. Technical environment

| Component                  | Selected technology/tool                            | Purpose                                          |
| -------------------------- | --------------------------------------------------- | ------------------------------------------------ |
| Database management system | MySQL 8.0.16 or later (developed on 26.7.0), InnoDB | Store and manage relational data, transactions   |
| SQL client                 | MySQL command-line client; MySQL Workbench          | Build the schema, run scripts, and test SQL      |
| Editor                     | Visual Studio Code                                  | Write SQL scripts and Markdown documentation     |
| Modeling tool              | draw.io                                             | Create the ERD                                   |
| Source control             | Git and GitHub; release tag `v1.2`                  | Version scripts and documentation; tagged builds |
| Documentation              | Markdown                                            | FRD, TDD, README, and performance records        |
| Operating environment      | macOS                                               | Development and testing environment              |

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
Customer(CustomerID PK, Name, Phone, Email)

Vehicle(VehicleID PK, CustomerID FK -> Customer, VIN UNIQUE, Make, Model, Year)

Technician(TechnicianID PK, Name, Phone, Email UNIQUE, ActiveStatus)

UserAccount(UserID PK, TechnicianID FK -> Technician UNIQUE NULL, Username UNIQUE, Name, RoleType)

ServiceAppointment(AppointmentID PK, VehicleID FK -> Vehicle, TechnicianID FK -> Technician,
                   CreatedByUserID FK -> UserAccount, AppointmentDateTime, Status,
                   ServiceRequestDescription, EstimatedDuration, CreationTimestamp,
                   CancellationDate, CancellationReason)

Repair(RepairID PK, AppointmentID FK -> ServiceAppointment,
       CompletedByTechnicianID FK -> Technician NULL, RepairDateTime, RepairType,
       RepairDescription, LaborHours, Status, CompletionDateTime)

RepairEstimate(EstimateID PK, AppointmentID FK -> ServiceAppointment UNIQUE,
               CreatedByUserID FK -> UserAccount, ApprovedByUserID FK -> UserAccount NULL,
               EstimateDate, Status, TotalAmount, ApprovalDateTime)

EstimateLineItem((EstimateID FK -> RepairEstimate, LineNumber) PK,
                 Description, Quantity, UnitPrice, LineTotal)

Invoice(InvoiceID PK, AppointmentID FK -> ServiceAppointment UNIQUE,
        CreatedByUserID FK -> UserAccount, FinalizedByUserID FK -> UserAccount NULL,
        InvoiceDate, Status, TotalAmount, FinalizationDateTime)

InvoiceLineItem(InvoiceLineItemID PK, InvoiceID FK -> Invoice,
                Description, Quantity, UnitPrice, LineTotal)

Part(PartID PK, PartNumber UNIQUE, PartName, QuantityOnHand, UnitCost,
     UnitSellingPrice, MinimumInventoryLevel, ActiveStatus)

PartsUsage(PartsUsageID PK, RepairID FK -> Repair, PartID FK -> Part,
           RecordedByUserID FK -> UserAccount, QuantityUsed,
           UnitSellingPriceAtTimeOfUse, UnitCostAtTimeOfUse, RecordedDateTime)

AuditLog(AuditLogID PK, UserID FK -> UserAccount, Timestamp, Action,
         AffectedEntity, AffectedRecordID, PreviousValue, NewValue, ContextID NULL)
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
| EstimatedDuration         | INT          | No           | CHECK (EstimatedDuration \> 0)                                                                    | Estimated duration in minutes        |
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
- An appointment cannot be moved to another vehicle, because vehicle ownership is checked at booking (FR-15). Its ID cannot change.
- trg_ServiceAppointment_Schedule_Validate applies the booking overlap check to rescheduling, duration changes, and technician reassignment of active appointments (FR-14, FR-16, BR-04, BR-09).

### Table: Repair

**Purpose:** Stores one row for each repair associated with a service appointment.

| Column                  | Data type    | Null allowed? | Key/constraint                                                                                         | Description/example                            |
| ----------------------- | ------------ | ------------- | ------------------------------------------------------------------------------------------------------ | ---------------------------------------------- |
| RepairID                | INT          | No            | PK, AUTO_INCREMENT                                                                                     | Unique repair identifier                       |
| AppointmentID           | INT          | No            | FK → ServiceAppointment(AppointmentID)                                                                 | Appointment associated with the repair         |
| RepairType              | VARCHAR(100) | No            | None                                                                                                   | Type of repair                                 |
| RepairDescription       | VARCHAR(500) | No            | None                                                                                                   | Description of repair work                     |
| Status                  | VARCHAR(20)  | No            | CHECK (Status IN (‘Open’, ‘In Progress’, ‘Completed’, ‘Cancelled’)); chk_Repair_Completion (see below) | Repair status                                  |
| CompletedByTechnicianID | INT          | Yes           | FK → Technician(TechnicianID); required when Status = 'Completed' (chk_Repair_Completion)              | Technician who completed the repair            |
| RepairDateTime          | DATETIME     | No            | None                                                                                                   | Date/time the repair was recorded or performed |
| LaborHours              | DECIMAL(5,2) | Yes           | CHECK (LaborHours \>= 0)                                                                               | Labor hours spent on the repair                |
| CompletionDateTime      | DATETIME     | Yes           | Required when Status = 'Completed' (chk_Repair_Completion)                                             | Date/time the repair was completed             |

#### Rules implemented by this table:

- FR-03 supports storing completed repair work.
- FR-04 supports retrieving the vehicle maintenance history.
- FR-20 requires repair completion and related updates to occur as one database transaction.
- BR-05 restricts repair status to approved values.
- chk_Repair_Completion: CHECK (Status <> 'Completed' OR (CompletedByTechnicianID IS NOT NULL AND CompletionDateTime IS NOT NULL)). Only sp_CompleteRepair sets these fields, so technicians can complete repairs only through the procedure (FR-20, T-38).
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
- trg_RepairEstimate_Validate blocks updates and deletes after finalization (FR-18). trg_RepairEstimate_Audit records approvals and status changes (FR-08). The acting user must be a Manager and must be the user recorded in ApprovedByUserID (SEC-01). An estimate cannot be moved to another appointment, and its ID cannot change.

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
- A line item cannot be moved to another estimate/invoice.
- trg_EstimateLineItem_Audit records line-item creation, updates, and deletion (FR-08).

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
- trg_Invoice_Validate blocks updates and deletes after finalization (FR-18). trg_Invoice_Audit records changes and finalization (FR-08). The acting user must be a Service Advisor or Manager and must be the user recored in FinalizedByUserID. An invoice cannot be moved to another appointment, and its ID cannot change.

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
- A line item cannot be moved to another estimate/invoice.
- trg_InvoiceLineItem_Audit records line-item creation, updates, and deletion (FR-08).

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

| Column           | Data type    | Null allowed? | Key/constraint           | Description/example                                                                             |
| ---------------- | ------------ | ------------- | ------------------------ | ----------------------------------------------------------------------------------------------- |
| AuditLogID       | INT          | No            | PK, AUTO_INCREMENT       | Unique audit entry identifier                                                                   |
| UserID           | INT          | No            | FK → UserAccount(UserID) | User who performed the action                                                                   |
| Timestamp        | DATETIME     | No            | None                     | Date/time the action occurred                                                                   |
| Action           | VARCHAR(50)  | No            | None                     | Action performed, such as create, update, cancel, approve, or finalize                          |
| AffectedEntity   | VARCHAR(100) | No            | None                     | Type of record affected, such as Invoice or ServiceAppointment                                  |
| AffectedRecordID | INT          | Yes           | None                     | Identifier of the affected record; NULL for a rejected request that created no record           |
| PreviousValue    | JSON         | Yes           | None                     | Relevant values before the change                                                               |
| NewValue         | JSON         | Yes           | None                     | Relevant values after the change                                                                |
| ContextID        | CHAR(36)     | Yes           | idx_AuditLog_Context     | UUID shared by every audit row written by one stored-procedure call; NULL for direct statements |

#### Rules implemented by this table:

- FR-08 requires audit entries for important creates, updates, completions, cancellations, approvals, finalizations, status changes, technician reassignments, inventory adjustments, and parts-usage changes.
- Each audit entry records the responsible user, timestamp, action, affected entity, affected record identifier, and relevant old/new values.
- SEC-03 requires important changes to service appointments, repairs, repair estimates, and invoices to be auditable.
- Every audit row written during one stored-procedure call shares the same ContextID, so the full effect of one operation can be retrieved together (T-47).
- A failed procedure call writes one audit row with Action 'Rejected', recording the user, the attempted request, and the error message (T-48).
- trg_AuditLog_Protect rejects all UPDATE and DELETE operations, so audit rows are append-only (BR-07, SEC-03).

## 8. Normalization Analysis

The database is designed to satisfy First Normal Form, Second Normal Form, and Third Normal Form.

| Normal Form              | Design check                                                     | Evidence in this project                                                                                                                                                                                                                     |
| ------------------------ | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| First Normal Form (1NF)  | Columns contain atomic values and there are no repeating groups. | Each column stores a single value. Multiple parts used in a repair are stored as separate PartsUsage rows rather than repeating part fields in Repair.                                                                                       |
| Second Normal Form (2NF) | Every non-key attribute depends on the entire primary key.       | Most tables use a single-column primary key, so partial dependencies do not occur. EstimateLineItem uses the composite key (EstimateID, LineNumber) and its description, quantity, unit price, and total depend on that full key.            |
| Third Normal Form (3NF)  | Non-key attributes do not depend on other non-key attributes.    | Customer, technician, part, and user information are stored in their own tables. Related tables reference them using foreign keys instead of repeating descriptive information, which prevents transitive dependencies and update anomalies. |

## 9. Integrity, validation, and business-rule enforcement

| Business rule ID | Rule                                                                          | Technical implementation                                                                                                                                                                                                                                                                                                                                                               | Verification method                                                                                        |
| ---------------- | ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| BR-01            | Each major record must have a unique identifier.                              | PRIMARY KEY constraints on each table.                                                                                                                                                                                                                                                                                                                                                 | Attempt to insert a duplicate primary-key value and verify that MySQL rejects it (T-35).                   |
| BR-02            | Each vehicle must belong to exactly one customer.                             | Vehicle.CustomerID is NOT NULL and a foreign key to customer(CustomerID)                                                                                                                                                                                                                                                                                                               | Attempt to insert a vehicle with a nonexistent CustomerID and verify rejection.                            |
| BR-03            | Repairs and parts have a many-to-many relationship.                           | PartsUsage junction table with foreign keys to Repair and Part.                                                                                                                                                                                                                                                                                                                        | Insert multiple parts for one repair and the same part for multiple repairs, then query the relationships. |
| BR-04            | Duplicate active appointments for the same vehicle/date/time are not allowed. | sp_CreateServiceAppointment checks for an existing active appointment for the same vehicle before inserting; trg_ServiceAppointment_Schedule_Validate applies the same check when an appointment is rescheduled or its duration changes.                                                                                                                                               | Attempt to create a duplicate active appointment and verify rejection.                                     |
| BR-05            | Status values must use allowed values.                                        | CHECK constraints on the Status columns of ServiceAppointment, Repair, RepairEstimate, and Invoice. Status-validate triggers reject invalid transitions.                                                                                                                                                                                                                               | Attempt to insert an invalid status value and verify rejection.                                            |
| BR-06            | Only authorized roles may create or modify protected records.                 | MySQL roles role_service_advisor, role_technician, and role_manager, each granted table- and column-level privileges matching its entitlements (section 10). Technicians read and update only through the filtered views vw_MyAppointments and vw_MyRepairs (Status column only) and complete repairs through sp_CompleteRepair. No role has UPDATE or DELETE on AuditLog.             | Attempt an allowed action with an authorized role and the same action with an unauthorized role.           |
| BR-07            | Important changes must be auditable.                                          | AuditLog table, audit triggers `trg_ServiceAppointment_Audit`, `trg_Repair_Audit`, `trg_RepairEstimate_Audit`, `trg_Invoice_Audit`, `trg_PartInventory_Audit`, `trg_PartsUsage_Audit`, which insert AuditLog rows on create, update, and delete; and `trg_AuditLog_Protect`, `trg_EstimateLineItem_Audit`, `trg_InvoiceLineItem_Audit`, which rejects updates and deletes on AuditLog. | Perform an audited update and verify the corresponding AuditLog row is created.                            |
| BR-08            | Multi-step repair completion must either fully succeed or fully roll back.    | Stored procedure using START TRANSACTION, COMMIT, and ROLLBACK.                                                                                                                                                                                                                                                                                                                        | Force one step to fail and verify that none of the earlier changes remain.                                 |
| BR-09            | A technician cannot be assigned to conflicting active appointments.           | sp_CreateServiceAppointment checks technician/date/time conflicts before insert; trg_ServiceAppointment_Schedule_Validate applies the same check on rescheduling and technician reassignment.                                                                                                                                                                                          | Attempt to assign one technician to two active appointments at the same time and verify rejection.         |
| BR-10            | Parts usage cannot reduce inventory below zero.                               | CHECK (QuantityOnHand >= 0) on Part rejects any update that would make inventory negative. sp_CompleteRepair also locks each requested part with SELECT ... FOR UPDATE and verifies that QuantityOnHand >= QuantityUsed for every part before recording any usage, so an insufficient part rolls back the whole operation.                                                             | Attempt to use more parts than are available and verify rejection with inventory unchanged.                |

## 10. Database objects and SQL design

| Object type      | Object name                                  | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | Related requirements                            |
| ---------------- | -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| View             | `vw_VehicleServiceHistory`                   | Displays completed repairs and parts used for a selected vehicle.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | FR-04, RQ-02                                    |
| View             | `vw_TechnicianWorkload`                      | Displays service appointments assigned to each technician for workload reporting.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | FR-06, RQ-05                                    |
| View             | `vw_MyAppointments`                          | Shows only the appointments assigned to the logged-in technician, with vehicle details. Filters on `USER()` matched to UserAccount.Username, so the filter cannot be bypassed by setting a session variable. Runs with its definer's privileges, so technicians need no access to the base tables.                                                                                                                                                                                                                                                                                                                                       | FR-07, SEC-02                                   |
| View             | `vw_MyRepairs`                               | Shows only repairs on appointments assigned to the logged-in technician. Updatable single-table view; technicians change Repair.Status through it, and another technician's repair is not visible (an update affects 0 rows). WITH CHECK OPTION keeps updated rows inside the view.                                                                                                                                                                                                                                                                                                                                                      | FR-07, SEC-02, FR-19                            |
| Stored procedure | `sp_CreateServiceAppointment`                | Validates required appointment data (future date/time, positive duration, non-empty description), confirms the vehicle belongs to the customer, the technician is active, and the creating user exists; rejects the appointment if it overlaps an active appointment for the same vehicle or technician, using each appointment's estimated duration; then inserts it with status Scheduled and returns the new AppointmentID, all in one transaction. All audit rows from one call share a ContextID. On failure, the procedure rolls back and then writes one ‘Rejected’ audit row with the error message before re-raising the error. | FR-02, FR-05, FR-15, FR-16, BR-04, BR-09        |
| Stored procedure | `sp_CompleteRepair`                          | Validates that the repair is In Progress, and validates the appointment, technician, and recording user; records usage for zero or more parts passed as a JSON array; reduces inventory; and marks the repair completed. All changes commit or roll back as one transaction. Audit records are written by the table triggers. All audit rows from one call share a ContextID. On failure, the procedure rolls back and then writes one ‘Rejected’ audit row with the error message before re-raising the error.                                                                                                                          | FR-03, FR-12, FR-13, FR-20, BR-03, BR-08, BR-10 |
| Stored procedure | `sp_WriteAuditLog`                           | Internal helper called by all audit triggers. Rejects the write if `@app_user_id` is not set, then inserts the AuditLog row with the acting user, timestamp, action, affected entity, record ID, and before/after values, and the context ID from the session variable `@context_id`. Not granted to any role, so users cannot write audit rows directly.                                                                                                                                                                                                                                                                                | FR-08, BR-07, SEC-03                            |
| Trigger          | `trg_ServiceAppointment_Audit`               | Automatically creates an AuditLog record when important service-appointment data is changed.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | FR-08, SEC-03                                   |
| Trigger          | `trg_Invoice_Audit`                          | Automatically records important invoice changes and finalization activity.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | FR-08, FR-18, SEC-03                            |
| Trigger          | `trg_RepairEstimate_Audit`                   | Automatically records important repair-estimate changes, approvals, finalization, and status changes in AuditLog.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | FR-08, FR-18, SEC-03                            |
| Trigger          | `trg_PartInventory_Audit`                    | Records inventory quantity changes in AuditLog, including the previous and new quantity and the adjustment reason from the session variable `@adj_reason`; rejects a quantity change when no reason is set.                                                                                                                                                                                                                                                                                                                                                                                                                              | FR-08, FR-13, SEC-03                            |
| Trigger          | `trg_Repair_Audit`                           | Automatically records repair creation, updates, completion, and status changes in AuditLog.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | FR-03, FR-08, SEC-03                            |
| Trigger          | `trg_PartsUsage_Audit`                       | Automatically records parts usage additions, updates, and reversals in AuditLog.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | FR-08, FR-12, FR-13, SEC-03                     |
| Trigger          | `trg_Invoice_Validate`                       | Allows only the Draft to Finalized status transition. When an invoice is finalized, requires the acting user to be a Service Advisor or Manager and to be the recorded finalizer, and records the finalization date/time. Prevents finalized invoices from being modified or deleted, and blocks changing an invoice's ID or moving it to another appointment.                                                                                                                                                                                                                                                                           | FR-18, FR-19, SEC-01                            |
| Trigger          | `trg_RepairEstimate_Validate`                | Allows only the status transitions Draft → Pending Approval, Pending Approval → Approved/Rejected/Expired, and Approved → Finalized. When an estimate is approved or rejected, requires the acting user to be a Manager and to be the recorded approver and records the approval date/time. Prevents finalized estimates from being modified or deleted, and blocks changing an estimate's ID or moving it to another appointment.                                                                                                                                                                                                       | FR-18, FR-19, SEC-01                            |
| Trigger          | `trg_Repair_Status_Validate`                 | Allows only the status transitions Open → In Progress, In Progress → Completed, and Open/In Progress → Cancelled; rejects all others, such as changing a completed repair back to In Progress. Locks completed and cancelled repairs against any further change. Blocks changing the repair ID or moving the repair to another appointment.                                                                                                                                                                                                                                                                                              | FR-19, BR-05                                    |
| Trigger          | `trg_ServiceAppointment_Status_Validate`     | Allows only the status transitions Scheduled → Checked In → In Progress → Completed and Scheduled → Cancelled/No Show; rejects all others, such as changing a completed appointment back to Scheduled. Locks completed, cancelled and no-show appointments. Fills in CancellationDate when applicable. Blocks changing the appointment ID or its vehicle.                                                                                                                                                                                                                                                                                | FR-14, FR-19, BR-05                             |
| Trigger          | `trg_ServiceAppointment_Schedule_Validate`   | When an active appointment's date/time, duration, or technician changes, applies the same checks as `sp_CreateServiceAppointment`: duration of at most 1440 minutes, active technician, and no overlap with another active appointment for the same vehicle or technician (its own row excluded). Locks the technician and vehicle rows like the booking procedure, so a reschedule and a booking cannot take the same slot. Runs after the status trigger (FOLLOWS).                                                                                                                                                                    | FR-14, FR-16, BR-04, BR-09                      |
| Trigger          | `trg_InvoiceLineItem_Validate`               | Prevents invoice line items from being inserted, updated, or deleted after the associated invoice has been finalized. Blocks changing a line item's ID or moving it to another invoice.                                                                                                                                                                                                                                                                                                                                                                                                                                                  | FR-17, FR-18, SEC-01                            |
| Trigger          | `trg_EstimateLineItem_Validate`              | Prevents estimate line items from being inserted, updated, or deleted after the associated repair estimate has been finalized.Blocks changing a line item's ID or moving it to another estimate.                                                                                                                                                                                                                                                                                                                                                                                                                                         | FR-17, FR-18, SEC-01                            |
| Trigger          | `trg_AuditLog_Protect`                       | Prevents existing audit records from being updated or deleted, preserving audit history.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | FR-08, SEC-03, BR-07                            |
| Index            | `idx_ServiceAppointment_DateTime`            | Supports appointment queries filtered by date and time.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | RQ-01                                           |
| Index            | `idx_ServiceAppointment_Technician_DateTime` | Supports technician workload queries and scheduling-conflict checks using technician and appointment time.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | FR-06, FR-16, RQ-05                             |
| Index            | `idx_ServiceAppointment_Vehicle_DateTime`    | Supports duplicate/conflicting appointment checks for the same vehicle at the same date and time.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | FR-02, BR-04                                    |
| Index            | `idx_AuditLog_Entity_Record`                 | Supports audit-history lookups for a specific business record in chronological order.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | FR-08, SEC-03                                   |
| Index            | `idx_Repair_Status_Type`                     | Supports the common repairs report by filtering completed repairs and grouping them by repair type.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | FR-09, RQ-03                                    |
| Index            | `idx_AuditLog_Context`                       | Supports retrieving all audit log entries generated by a single stored procedure call using ContextID.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | FR-08, SEC-03                                   |
| Role             | `role_service_advisor`                       | Creates and updates customers and vehicles; creates appointments only through `sp_CreateServiceAppointment` (no direct INSERT on ServiceAppointment); updates appointments and technician assignments, non-finalized estimates, and non-finalized invoices; creates repair records; finalizes approved estimates and invoices; cannot approve or reject estimates or access AuditLog.                                                                                                                                                                                                                                                    | FR-07, BR-06, SEC-01                            |
| Role             | `role_technician`                            | Row-level access: reads only their own appointments and repairs through `vw_MyAppointments` and `vw_MyRepairs`, with no direct access to the ServiceAppointment or Repair tables; may update only the Status column through `vw_MyRepairs` (transitions still enforced by `trg_Repair_Status_Validate`); reads Vehicle, Part, PartsUsage, and `vw_VehicleServiceHistory`; completes repairs through `sp_CompleteRepair`; has no other write access.                                                                                                                                                                                      | FR-07, BR-06, SEC-02                            |
| Role             | `role_manager`                               | Has broad operational and reporting access; creates appointments through `sp_CreateServiceAppointment` (no direct INSERT on ServiceAppointment); updates repair details on open or in-progress repairs; estimate approval or rejection, update appointments and technician reassignment, estimate and invoice finalization and adjustment (for non-finalized invoices), and inventory adjustments; completes repairs on behalf of the assigned technician through `sp_CompleteRepair` or directly as an audited supervisor override; has SELECT-only access to AuditLog.                                                                 | FR-07, BR-06, SEC-01, SEC-02                    |

Each trigger object listed above is implemented as one MySQL trigger per event and timing, because MySQL triggers handle a single event. For example, `trg_Invoice_Audit` consists of AFTER INSERT, AFTER UPDATE, and AFTER DELETE triggers, and `trg_Invoice_Validate` consists of BEFORE INSERT, BEFORE UPDATE and BEFORE DELETE triggers.

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
- Audit triggers identify the acting user through the session variable `@app_user_id`. Stored procedures set it from their user ID parameter and clear it after commit or rollback; direct writes (such as status updates or inventory adjustments) must set it at the start of the session. An audited write without it is rejected so every AuditLog row has a valid UserID. In this course implementation the variable is trusted as supplied; a production system would set it in middleware after authentication. Procedures also set `@context_id` to a new UUID at the start and clear it after commit or rollback. Row-level read access does not rely on `@app_user_id`: the technician views filter on USER(), the authenticated MySQL login, which cannot be changed from SQL.
- AuditLog is append-only: audit rows are inserted only by triggers, which run with their definer’s privileges; managers receive SELECT only, other roles have no direct access, and trg_AuditLog_Protect rejects any UPDATE or DELETE.
- Foreign keys on audited tables use the default RESTRICT behavior instead of ON DELETE CASCADE, because MySQL cascades do not fire triggers and cascaded deletes would leave no audit record.
- In a production environment, the database would use encrypted connections, stronger credential management, scheduled backups, access monitoring, and a documented backup and recovery process.
- Production-grade security hardening, automated backup scheduling, disaster recovery, and enterprise-scale security monitoring are outside the scope of this course implementation unless specifically required.
- Inventory quantity changes require an adjustment reason in the session variable `@adj_reason`, which `trg_PartInventory_Audit` stores in the audit record's NewValue. Managers set it before manual adjustments; `sp_CompleteRepair` sets it automatically (for example, "Parts usage for repair 12") and clears it afterward.

### Performance and index design

Indexes were chosen from the common access paths: appointments by date (RQ-01), by technician and date (workload report and scheduling-conflict checks), and by vehicle and date (vehicle conflict checks); completed repairs grouped by type (RQ-03); and audit history for one record (`idx_AuditLog_Entity_Record`). InnoDB indexes foreign-key columns automatically, which supports the joins in every report.

Each index adds a small cost to inserts and updates on its table. ServiceAppointment and Repair rows change status only a few times, while reports and conflict checks read them constantly, so the read benefit outweighs the write cost. AuditLog is the most write-heavy table (one row per audited change), so it has only two secondary indexes: one for record-history lookups and one (idx_AuditLog_Context) for retrieving all rows written by one procedure call.

Indexes were verified with `EXPLAIN` and `EXPLAIN ANALYZE` on a 20,000-row data set. Three optimization records are in `docs/performance/`:

| Record                           | Change                                           | Result                                                                       |
| -------------------------------- | ------------------------------------------------ | ---------------------------------------------------------------------------- |
| OPT-01 (RQ-03, aggregate report) | Covering index on Repair (Status, RepairType)    | Full scan of 20,008 rows → index lookup of 10,004 entries; 7.84 ms → 2.21 ms |
| OPT-02 (RQ-01)                   | `DATE(AppointmentDateTime)` rewritten as a range | Full scan of 20,010 rows → index range scan of 25 rows; 7.23 ms → 0.06 ms    |
| OPT-03 (audit extract)           | OFFSET paging replaced with keyset paging        | 50,020 rows read → 20; 24.2 ms → 0.16 ms                                     |

The bulk load in `perf_data.sql` applied 70,000 inserts and updates through the validation and audit triggers in about 2.5 seconds. Very large loads and extracts should be split into smaller committed batches to keep transactions and lock times short.

### Resiliency, recovery, and data integrity

**Atomic operations.** `sp_CreateServiceAppointment` and `sp_CompleteRepair` run inside `START TRANSACTION ... COMMIT`. An EXIT handler rolls back and re-raises any error, so either every related insert, update, and audit row is saved or none is. Audit rows are written by triggers inside the same transaction, so they roll back with it (T-26, T-33). After the rollback, the handler writes one 'Rejected' audit row recording the failed attempt (T-48).

**Duplicate submissions and conflicting updates.** The booking procedure locks the technician and vehicle rows with `SELECT ... FOR UPDATE` before checking for overlapping appointments, so two simultaneous bookings for the same slot cannot both succeed. Rescheduling and reassignment take the same locks in `trg_ServiceAppointment_Schedule_Validate`, so a reschedule and a booking cannot both claim one slot either. `sp_CompleteRepair` locks the repair and every requested part before checking inventory, so two completions cannot spend the same stock. `UNIQUE(AppointmentID)` on RepairEstimate and Invoice prevents a second estimate or invoice for one appointment.

**Invalid state transitions.** Validation triggers allow only the FRD status transitions for appointments, repairs, estimates, and invoices; anything else is rejected before the row changes (T-06, T-19, T-24).

**History preservation.** Business records are closed by status changes (Cancelled, No Show, Rejected, Expired, Finalized) rather than deleted. Foreign keys use RESTRICT, so parent rows with history cannot be removed. Finalized estimates, finalized invoices, their line items, and audit rows cannot be updated or deleted.

**Cancellation and expiration.** Appointments move Scheduled → Cancelled with CancellationDate and CancellationReason, or to No Show. Repairs can be cancelled from Open or In Progress. Estimates move from Pending Approval to Rejected or Expired. Expiration is a status update made by staff; an automatic expiry job is outside the scope.

**Failure and retry.** If a step fails, including a deadlock (MySQL error 1213) or lock wait timeout, the whole transaction is rolled back and the database is unchanged, so the client can safely retry. Retrying an operation that already succeeded is rejected by the state checks (for example, a repair that is already Completed) instead of creating duplicate data.

**Correction.** Draft records can be edited. Inventory corrections are made by a Manager with a required reason (`@adj_reason`) and are audited. Finalized invoices cannot be changed; correcting one would require a separate credit or adjustment record, which is outside the scope of this implementation.

**Recovery.** InnoDB's redo log keeps committed transactions after a crash and rolls back uncommitted ones on restart. Production backups and point-in-time recovery are outside the scope; the development database can be recreated at any time from the repository with `build.sql`.

### Audit and traceability design

**Audited events.** Creates, updates, deletes, and status changes on ServiceAppointment, Repair, RepairEstimate, Invoice, and PartsUsage, and estimate and invoice line items; estimate approval and rejection; invoice and estimate finalization; appointment cancellation and rescheduling; technician reassignment; and every inventory quantity change.

**Audit content.** Each AuditLog row records the acting user (UserID, from `@app_user_id`), timestamp, action, affected entity, affected record ID, and the previous and new values as JSON, and a ContextID linking all rows written by one procedure call. Inventory changes also store the reason. Updates that change nothing are not logged (T-23). Create and Delete rows store the full row; Update rows store every non-key column before and after, so any change is recorded. Record IDs and parent links cannot be changed, so no change escapes the audit trail.

**Context.** Each stored procedure generates a UUID at the start of its transaction and stores it in `@context_id`; `sp_WriteAuditLog` copies it into the ContextID column of every audit row written during the call, and the procedure clears it on commit or rollback. One completed repair therefore produces a group of rows (parts usage, inventory changes, repair completion) that can be retrieved with a single lookup (T-47). Direct statements outside a procedure have no ContextID.

**Failures.** When a stored procedure fails, its EXIT handler saves the error message, rolls back the work, then writes one audit row with Action 'Rejected' that records the user, the attempted request, and the error (T-48). The row is written after the rollback so it is not undone. Rejections of direct statements (trigger, constraint, or privilege errors outside a procedure) are not recorded, because a failed statement rolls back anything its trigger writes and privilege errors occur before any trigger runs; the server's audit log feature or an application layer would be needed for those.

**Protection.** Audit rows are inserted only by triggers through `sp_WriteAuditLog`. No role has INSERT, UPDATE, or DELETE on AuditLog; Managers have SELECT only, and `trg_AuditLog_Protect` rejects any update or delete (T-22).

**Reconstructing history.** The full lifecycle of a record is read in time order using `idx_AuditLog_Entity_Record`:

```sql
SELECT a.`Timestamp`, u.Name, u.RoleType, a.Action, a.PreviousValue, a.NewValue
FROM AuditLog a
JOIN UserAccount u ON u.UserID = a.UserID
WHERE a.AffectedEntity = 'Repair' AND a.AffectedRecordID = 6
ORDER BY a.`Timestamp`, a.AuditLogID;
```

All rows written by one procedure call:

```sql
SELECT AuditLogID, UserID, Action, AffectedEntity, AffectedRecordID, `Timestamp`
FROM AuditLog
WHERE ContextID = '<context id>'
ORDER BY AuditLogID;
```

### Known limitations

- **The acting user (`@app_user_id`) is verified only for business-user logins.** For a user logged in with their own MySQL account (e.g. `sa_amy`), every audited write checks that `@app_user_id` belongs to that login (`USER()`); a mismatch is rejected ("Acting user must be the logged-in user") and the whole change rolls back. Connections with no UserAccount (root, or an application service account) are trusted to set it, as a production application would after authenticating the user. Row-level reads do not depend on it: the technician views filter on `USER()`.
- **Managers can complete a repair directly** by setting the status and completion fields in one UPDATE, without recording parts. This is treated as an audited supervisor override; technicians cannot do this (`chk_Repair_Completion`, T-38).
- **Only stored-procedure failures are audited.** Failed procedure calls write a 'Rejected' audit row (T-48), but rejections of direct statements (trigger, constraint, or privilege errors outside a procedure) are not recorded, because a failed statement rolls back anything its trigger writes and privilege errors occur before any trigger runs. A failed call with a nonexistent user ID is also not recorded, because AuditLog.UserID must reference a real account.
- **Technicians can read all vehicles, parts, and parts usage.** Row-level filtering covers appointments and repairs (`vw_MyAppointments`, `vw_MyRepairs`); the other tables contain no customer information.
- **Master-data changes are not audited.** Changes to Customer, Vehicle, Technician (including deactivation), and Part details other than quantity (such as price) are not recorded in AuditLog. Auditing covers operational and financial records; the same trigger pattern could be applied to these tables.
- **Approved estimates can still be edited until they are finalized.** After approval, an advisor can change the estimate's total, its line items, and its approval fields (`ApprovedByUserID`, `ApprovalDateTime`) without a new approval; records are locked only once Finalized. Every change is audited under the real user. Fix: lock an estimate once it is decided (Approved, Rejected, Expired), allowing only the move to Finalized, or require re-approval after an edit.
- **Finalized invoices cannot be voided or corrected.** Invoices have only Draft and Finalized statuses, and each appointment can have one invoice, so a finalized error cannot be reversed.

## 13. Test plan and acceptance criteria

Automated tests are in `07_tests.sql` and run as part of `build.sql`. Expected rejections are caught and checked against the expected error message, so a test passes only if it fails for the right reason. Tests run in three groups (read-only reports, rejected operations, then operations that change data) so that no test alters data another test depends on. T-11 is run manually because MySQL privileges apply to the logged-in account. Latest run: 66 of 66 automated checks passed.

### Test harness

The automated tests in `07_tests.sql` use four helper procedures. They are created at the start of the script and dropped at the end, so they are not part of the delivered schema.

| Procedure           | Purpose                                                                                                                                                                                                                                                              |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tst_ExpectError`   | Runs a statement that should be rejected. A CONTINUE handler catches the error and `GET DIAGNOSTICS` reads its message; the test passes only if an error occurred and its message contains the expected text, so a failure for the wrong reason is recorded as FAIL. |
| `tst_ExpectSuccess` | Runs a statement that should succeed and records FAIL, with the error message, if it raises an error.                                                                                                                                                                |
| `tst_Assert`        | Records PASS or FAIL for a condition checked after a test, such as inventory being unchanged after a rejected transaction.                                                                                                                                           |
| `tst_CaptureError`  | Runs a statement and stores its error message in a session variable without recording a result. Used by T-09, whose result is recorded after its transaction is rolled back.                                                                                         |

Statements are passed as text and run with `PREPARE`/`EXECUTE`. Results are stored in a temporary `TestResult` table and printed at the end of the script as a full list and a PASS/FAIL summary. Tests run in three groups: report checks first (on the unchanged sample data), then operations that must be rejected, then operations that must succeed, which change data permanently. The database should be rebuilt before the tests are re-run.

| Test ID | Requirement/rule | Test action                                                                                                                                       | Expected result                                                                                                                                              | Actual result/pass-fail                                                                                                                                                                                         |
| ------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| T-01    | FR-01            | Insert a valid customer and vehicle with all required fields.                                                                                     | Customer and vehicle records are inserted with unique IDs, and the vehicle references the correct customer.                                                  | PASS: Customer 100 and vehicle 100 inserted; vehicle references customer 100.                                                                                                                                   |
| T-02    | FR-05 / BR-02    | Attempt to insert a vehicle with a CustomerID that does not exist.                                                                                | Insert is rejected by the foreign key constraint.                                                                                                            | PASS: Rejected with "Cannot add or update a child row: a foreign key constraint fails."                                                                                                                         |
| T-03    | FR-02            | Create a valid service appointment for an existing vehicle and active technician.                                                                 | Appointment is created with status Scheduled and correct vehicle, technician, creating user, and timestamp.                                                  | PASS: Appointment created through `sp_CreateServiceAppointment` as Scheduled with the correct vehicle, technician, and creating user.                                                                           |
| T-04    | BR-04            | Attempt to create a duplicate active appointment for the same vehicle at the same date/time.                                                      | Appointment creation is rejected by `sp_CreateServiceAppointment`.                                                                                           | PASS: Overlapping appointment rejected with "Vehicle already has a conflicting appointment."                                                                                                                    |
| T-05    | FR-16 / BR-09    | Attempt to assign the same technician to two conflicting active appointments.                                                                     | Second assignment is rejected.                                                                                                                               | PASS: Rejected with "Technician already has a conflicting appointment."                                                                                                                                         |
| T-06    | BR-05 / FR-19    | Insert a service appointment with an invalid status value ('Pending').                                                                            | Insert is rejected by the Status CHECK constraint.                                                                                                           | PASS: Rejected with "Check constraint 'serviceappointment_chk_1' is violated."                                                                                                                                  |
| T-07    | FR-12 / BR-10    | Record more parts usage than inventory allows.                                                                                                    | Operation is rejected and inventory stays unchanged.                                                                                                         | PASS: Rejected with "Insufficient parts inventory"; Brake Rotor quantity unchanged at 2.                                                                                                                        |
| T-08    | FR-13            | Record valid parts usage.                                                                                                                         | PartsUsage is created and inventory decreases.                                                                                                               | PASS: Repair 7 completed; 1 PartsUsage row recorded; Air Filter 25 → 24; 3 audit rows written.                                                                                                                  |
| T-09    | FR-20 / BR-08    | Force repair completion to fail midway.                                                                                                           | Entire transaction rolls back.                                                                                                                               | PASS: Final step rejected with "Invalid repair status transition"; after ROLLBACK, Brake Pads unchanged (8), no PartsUsage rows, repair still In Progress.                                                      |
| T-10    | FR-08 / SEC-03   | Perform an audited update.                                                                                                                        | Correct AuditLog record is created.                                                                                                                          | PASS: Rescheduling appointment 8 created one AuditLog row with user 2, action "Reschedule," entity ServiceAppointment, and record 8.                                                                            |
| T-11    | SEC-02 / FR-07   | Log in as tech_ben and attempt to update a customer and view invoices; log in as sa_amy and attempt to call sp_CompleteRepair and view AuditLog.  | Each restricted operation is denied by MySQL privileges; permitted reads (tech_ben on Part, sa_amy on Customer) succeed.                                     | PASS (manual): tech_ben denied UPDATE on Customer and SELECT on Invoice (ERROR 1142); sa_amy denied EXECUTE on sp_CompleteRepair (ERROR 1370) and SELECT on AuditLog (ERROR 1142). Permitted SELECTs succeeded. |
| T-12    | RQ-02 / RQ-05    | Run service-history and workload queries.                                                                                                         | Queries return the expected records and counts.                                                                                                              | Removed: duplicate of T-15 (RQ-02) and T-16 (RQ-05).                                                                                                                                                            |
| T-13    | FR-18 / SEC-01   | Finalize an invoice, then attempt to update or delete it.                                                                                         | Modification or deletion is rejected and the finalized record remains unchanged.                                                                             | PASS: Update rejected with "Finalized invoices cannot be modified"; delete rejected with "Finalized invoices cannot be deleted."                                                                                |
| T-14    | RQ-01            | Run the Daily Service Appointments query for a selected date.                                                                                     | Query returns appointments for that date with vehicle, technician, status, and appointment time.                                                             | PASS: 3 appointments returned for 2026-10-15.                                                                                                                                                                   |
| T-15    | RQ-02            | Run the Vehicle Service History query for a selected vehicle.                                                                                     | Query returns completed repairs and parts used for that vehicle.                                                                                             | PASS: 2 completed repairs returned for vehicle 1.                                                                                                                                                               |
| T-16    | RQ-05            | Run the Shop Workload report.                                                                                                                     | Results show technicians with their assigned appointment counts.                                                                                             | PASS: Ben 2, Carla 3 active appointments; Dan listed with none.                                                                                                                                                 |
| T-17    | RQ-06            | Run the Parts Revenue Report.                                                                                                                     | Results show part names, total quantity used, and calculated parts revenue.                                                                                  | PASS: Total parts revenue $272.91, calculated from prices at time of use.                                                                                                                                       |
| T-18    | FR-03 / FR-20    | Complete a valid repair with valid parts usage.                                                                                                   | Repair is completed, two PartsUsage rows are recorded, inventory decreases for both parts, audit triggers create AuditLog rows, and the transaction commits. | PASS: Repair 6 Completed; 2 PartsUsage rows; Brake Pads 8 → 7, Brake Rotors 2 → 0; 5 audit rows written.                                                                                                        |
| T-19    | FR-19            | Attempt an invalid status transition, such as changing a Completed repair back to In Progress.                                                    | Operation is rejected and the record remains unchanged.                                                                                                      | PASS: Rejected with "Completed or cancelled repairs cannot be modified."                                                                                                                                        |
| T-20    | FR-18 / SEC-01   | Finalize an invoice, then attempt to insert, update, or delete one of its line items.                                                             | Operation is rejected and the invoice line items remain unchanged.                                                                                           | PASS: Insert rejected with "Cannot add line items to a finalized invoice"; delete rejected with "Cannot delete line items of a finalized invoice."                                                              |
| T-21    | FR-18 / SEC-01   | Finalize a repair estimate, then attempt to update or delete it or one of its line items.                                                         | Operation is rejected and the estimate and its line items remain unchanged.                                                                                  | PASS: Estimate update rejected with "Finalized estimates cannot be modified"; line item update rejected with "Cannot modify line items of a finalized estimate."                                                |
| T-22    | BR-07 / SEC-03   | Attempt to update or delete an existing AuditLog record.                                                                                          | Operation is rejected and the audit record remains unchanged.                                                                                                | PASS: Update rejected with "Audit records cannot be modified"; delete rejected with "Audit records cannot be deleted."                                                                                          |
| T-23    | FR-08            | Update an audited record without changing any of its values.                                                                                      | No new AuditLog record is created.                                                                                                                           | PASS: Audit row count unchanged (64 before and after).                                                                                                                                                          |
| T-24    | FR-14 / FR-19    | Attempt to change a Completed appointment back to Scheduled.                                                                                      | Operation is rejected and the appointment remains unchanged.                                                                                                 | PASS: Rejected with "Completed, cancelled, or no-show appointments cannot be modified."                                                                                                                         |
| T-25    | FR-08            | Perform an audited write without setting @app_user_id.                                                                                            | Operation is rejected because the acting user is unknown.                                                                                                    | PASS: Rejected with "Acting user not set: SET @app_user_id before writing audited data."                                                                                                                        |
| T-26    | FR-20 / BR-08    | Complete a repair with two parts where the second part has insufficient inventory.                                                                | Operation is rejected; no PartsUsage rows are added, inventory is unchanged, the repair is not completed, and no AuditLog rows are created.                  | PASS: Rejected with "Insufficient parts inventory"; Air Filter (25) and Spark Plug (3) unchanged; no PartsUsage rows; repair still In Progress.                                                                 |
| T-27    | SEC-01           | Attempt to approve a repair estimate as a user who does not have the Manager role.                                                                | Operation is rejected and the estimate status remains unchanged.                                                                                             | PASS: Rejected with "Estimates must be approved or rejected by a Manager."                                                                                                                                      |
| T-28    | FR-13 / SEC-03   | As a Manager, adjust a part's QuantityOnHand without setting @adj_reason, then again with a reason.                                               | The first update is rejected; the second succeeds and its AuditLog record contains the previous quantity, new quantity, and reason.                          | PASS: First update rejected with "Inventory adjustments require @adj_reason"; second succeeded and its audit row contains the reason "Cycle count correction."                                                  |
| T-29    | SEC-02           | As a Technician, change the status of a repair on an appointment assigned to a different technician.                                              | Operation is rejected and the repair status remains unchanged.                                                                                               | PASS: Rejected with "Technicians may only update their own assigned repairs."                                                                                                                                   |
| T-30    | FR-12 / BR-10    | Call sp_CompleteRepair with a parts list where a negative quantity is offset by a duplicate entry for the same part.                              | Operation is rejected; no PartsUsage rows are added and inventory is unchanged.                                                                              | PASS: Rejected with "Each part needs an integer partId and a positive integer qty."                                                                                                                             |
| T-31    | SEC-02 / FR-03   | Call sp_CompleteRepair with a Service Advisor as the recording user.                                                                              | Operation is rejected and the repair status remains unchanged.                                                                                               | PASS: Rejected with "Recording user is not authorized to complete this repair."                                                                                                                                 |
| T-32    | FR-15            | Create an appointment for a vehicle that belongs to a different customer.                                                                         | Operation is rejected because the vehicle does not belong to the customer.                                                                                   | PASS: Rejected with "Vehicle does not belong to the customer."                                                                                                                                                  |
| T-33    | BR-07 / FR-08    | Count AuditLog rows before and after all rejected and rolled-back operations.                                                                     | The count is unchanged; failed operations leave no audit rows.                                                                                               | PASS: 62 audit rows before and after.                                                                                                                                                                           |
| T-34    | RQ-04            | Run the Low Parts Inventory report.                                                                                                               | Brake Rotor and Spark Plug are listed as below their minimum inventory level.                                                                                | PASS: 2 parts below minimum (Brake Rotor, Spark Plug).                                                                                                                                                          |
| T-35    | BR-01            | Insert a customer with an existing CustomerID.                                                                                                    | Insert is rejected by the primary key constraint.                                                                                                            | PASS: Rejected with "Duplicate entry '1' for key 'customer.PRIMARY'."                                                                                                                                           |
| T-36    | FR-01            | Insert a vehicle with a VIN that already exists.                                                                                                  | Insert is rejected by the UNIQUE constraint on VIN.                                                                                                          | PASS: Rejected with "Duplicate entry '1HGCV1F34LA012345' for key 'vehicle.VIN'."                                                                                                                                |
| T-37    | FR-01            | Insert a customer with no name.                                                                                                                   | Insert is rejected by the NOT NULL constraint.                                                                                                               | PASS: Rejected with "Column 'Name' cannot be null."                                                                                                                                                             |
| T-38    | FR-03 / FR-20    | As the assigned technician, set a repair's status to Completed with a direct UPDATE.                                                              | Update is rejected; repairs must be completed through sp_CompleteRepair.                                                                                     | PASS: Rejected with "Check constraint 'chk_Repair_Completion' is violated."                                                                                                                                     |
| T-39    | FR-02            | Create an appointment with a duration of 1441 minutes (one over the maximum).                                                                     | Procedure rejects the appointment.                                                                                                                           | PASS: Rejected with "Invalid appointment information."                                                                                                                                                          |
| T-40    | FR-02            | Create an appointment with a duration of 0 minutes (one under the minimum).                                                                       | Procedure rejects the appointment.                                                                                                                           | PASS: Rejected with "Invalid appointment information."                                                                                                                                                          |
| T-41    | FR-12 / BR-10    | Complete a repair with a part quantity of 0.                                                                                                      | Procedure rejects the parts list; nothing is recorded.                                                                                                       | PASS: Rejected with "Each part needs an integer partId and a positive integer qty."                                                                                                                             |
| T-42    | FR-02            | Create an appointment with a duration of 1 minute (the minimum).                                                                                  | Appointment is created as Scheduled.                                                                                                                         | PASS: 1 matching appointment created.                                                                                                                                                                           |
| T-43    | FR-02            | Create an appointment with a duration of 1440 minutes (the maximum).                                                                              | Appointment is created as Scheduled.                                                                                                                         | PASS: 1 matching appointment created.                                                                                                                                                                           |
| T-44    | BR-04 / BR-09    | Book the same vehicle and technician starting 1 minute before an existing 90-minute appointment ends.                                             | Procedure rejects the overlapping appointment.                                                                                                               | PASS: Rejected with "Vehicle already has a conflicting appointment."                                                                                                                                            |
| T-45    | BR-04 / BR-09    | Book the same vehicle and technician starting exactly when the existing appointment ends.                                                         | Back-to-back appointment is accepted (end time equal to start time is not an overlap).                                                                       | PASS: 1 matching appointment created.                                                                                                                                                                           |
| T-46    | FR-12 / BR-10    | Complete a repair using exactly the quantity of spark plugs on hand.                                                                              | Repair is completed, usage is recorded, and inventory goes to 0.                                                                                             | PASS: Spark plug 3 -> 0, quantity used 3, repair status Completed.                                                                                                                                              |
| T-47    | FR-08 / SEC-03   | Complete a repair through sp_CompleteRepair, then compare the context IDs on the audit rows it wrote; check a direct UPDATE's audit row too.      | All audit rows from the one procedure call share a single context ID; a direct update outside a procedure has no context ID.                                 | PASS: 5 audit rows, 1 distinct context ID, 0 rows without one; reschedule row has no context ID.                                                                                                                |
| T-48    | FR-08 / SEC-03   | Complete a repair with more brake rotors than are in stock, then check the audit log.                                                             | Call is rejected and rolled back; exactly one Rejected audit row records the user, repair, error message, and a context ID.                                  | PASS: Rejected with "Insufficient parts inventory"; 1 new audit row, 1 matching Rejected row.                                                                                                                   |
| T-49    | SEC-02           | Check the technician role's grants: no direct access to ServiceAppointment or Repair, only the filtered views vw_MyAppointments and vw_MyRepairs. | Technician role has 0 grants on the base tables and SELECT on both views; logged in as tech_ben, only his own appointments and repairs are visible.          | PASS: Base-table grants: 0, view grants: 2. Demo 4.3 (tech_ben): SELECT on Repair denied; vw_MyRepairs shows only his repairs; update of repair 8 affects 0 rows.                                               |
| T-50    | FR-14 / FR-19    | Complete an appointment whose repair is still In Progress.                                                                                        | Update is rejected; an appointment cannot close while a repair is open.                                                                                      | PASS: Rejected with "Appointment has open repairs: complete or cancel them first."                                                                                                                              |
| T-51    | FR-03 / FR-20    | Complete an In Progress repair whose appointment is only Checked In.                                                                              | Procedure rejects the call; a repair can be completed only while its appointment is In Progress.                                                             | PASS: Rejected with "Appointment must be In Progress to complete a repair."                                                                                                                                     |
| T-52    | FR-16 / BR-09    | Reschedule an appointment into a time when its technician already has an active appointment.                                                      | Update is rejected with the same conflict check as a new booking.                                                                                            | PASS: Rejected with "Technician already has a conflicting appointment."                                                                                                                                         |
| T-53    | FR-17            | Insert a line item on a draft invoice whose LineTotal does not equal Quantity × UnitPrice.                                                        | Insert is rejected by the line-total CHECK constraint.                                                                                                       | PASS: Rejected with "Check constraint 'chk_InvoiceLineItem_LineTotal' is violated."                                                                                                                             |
| T-54    | FR-08 / SEC-03   | Change the unit price of a line item on a draft invoice.                                                                                          | Update succeeds and one AuditLog row records the line-item change.                                                                                           | PASS: 1 Update audit row for the InvoiceLineItem.                                                                                                                                                               |
| T-55    | SEC-01           | As a Service Advisor, approve an estimate while naming a Manager as the approver.                                                                 | Update is rejected; the acting user must be a Manager and must be the recorded approver.                                                                     | PASS: Rejected with "Estimates must be approved or rejected by a Manager."                                                                                                                                      |
| T-56    | FR-15            | Move an appointment to a different vehicle.                                                                                                       | Update is rejected; an appointment's vehicle is fixed when it is booked.                                                                                     | PASS: Rejected with "An appointment cannot be moved to another vehicle."                                                                                                                                        |
| T-57    | FR-08 / BR-01    | Change an appointment's ID, and change an invoice's creating user.                                                                                | Both updates are rejected; record IDs and the creating user cannot change.                                                                                   | PASS: Rejected with "Record IDs cannot be changed" and "The creating user cannot be changed."                                                                                                                   |

## 14. Requirement traceability

| Functional Requirement                         | Tables/relationships                                                        | Constraints or objects                                                                                                                                                                                                                         | Query/report/test evidence                                               |
| ---------------------------------------------- | --------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| FR-01: Store customer and vehicle records      | Customer → Vehicle                                                          | CustomerID PK; VehicleID PK; Vehicle.CustomerID FK; VIN UNIQUE                                                                                                                                                                                 | T-01; T-35; T-36; T-37; customer/vehicle insert and update demonstration |
| FR-02: Create service appointments             | Vehicle → ServiceAppointment ← Technician; UserAccount → ServiceAppointment | Appointment PK; vehicle/technician/user FKs; `sp_CreateServiceAppointment`; required-field/status checks                                                                                                                                       | T-03; T-04; T-14; RQ-01 Daily Service Appointments                       |
| FR-03: Record completed repairs                | ServiceAppointment → Repair ← Technician                                    | RepairID PK; AppointmentID FK; technician FK; repair-status checks; `sp_CompleteRepair`; `trg_Repair_Status_Validate`                                                                                                                          | T-08; T-18; T-19; T-31; T-51; RQ-02 Vehicle Service History              |
| FR-04: Display vehicle service history         | Vehicle → ServiceAppointment → Repair → PartsUsage → Part                   | FKs connecting vehicle, appointment, repair, and parts usage; `vw_VehicleServiceHistory`                                                                                                                                                       | T-15; RQ-02 Vehicle Service History                                      |
| FR-05: Validate appointment data               | Vehicle, Technician, ServiceAppointment                                     | FKs; validation in `sp_CreateServiceAppointment`                                                                                                                                                                                               | T-02; T-03; T-32                                                         |
| FR-06: Track technician workload               | Technician → ServiceAppointment                                             | TechnicianID FK; `vw_TechnicianWorkload`; technician/date index                                                                                                                                                                                | T-16; RQ-05 Shop Workload Report                                         |
| FR-07: Restrict access based on role           | UserAccount, protected operational tables                                   | RoleType CHECK; `role_service_advisor`, `role_technician`, `role_manager`; EXECUTE granted on procedures; manager-role check in `trg_RepairEstimate_Validate`                                                                                  | T-11; T-27; T-29; T-31; T-55                                             |
| FR-08: Maintain audit history                  | UserAccount → AuditLog; audited operational tables                          | AuditLog FKs; audit triggers on ServiceAppointment, Repair, RepairEstimate, Invoice, Part, PartsUsage; `trg_AuditLog_Protect`; `@app_user_id`; `idx_AuditLog_Entity_Record`                                                                    | T-10; T-22; T-23; T-25; T-28; T-33; T-54; T-57                           |
| FR-09: Report common repairs and parts revenue | Repair, Part, PartsUsage                                                    | RQ-03 and RQ-06 report queries; GROUP BY, COUNT(), SUM(); `idx_Repair_Status_Type`                                                                                                                                                             | T-17; RQ-03 Common Repairs Report; RQ-06 Parts Revenue Report            |
| FR-10: Create repair estimates and invoices    | ServiceAppointment, RepairEstimate, Invoice, UserAccount                    | Appointment FKs; CreatedByUserID FKs; status checks; UNIQUE AppointmentID                                                                                                                                                                      | Estimate/invoice creation demonstration                                  |
| FR-11: Manage part inventory                   | Part                                                                        | PartID PK; PartNumber UNIQUE; inventory/cost/price CHECK constraints                                                                                                                                                                           | T-28; T-34; RQ-04 Low Parts Inventory Report                             |
| FR-12: Record parts used during repairs        | Repair → PartsUsage ← Part                                                  | RepairID FK; PartID FK; quantity checks; `sp_CompleteRepair` (JSON parts list); `trg_PartsUsage_Audit`                                                                                                                                         | T-07; T-08; T-26; T-30                                                   |
| Trigger                                        | `trg_EstimateLineItem_Audit`                                                | Records estimate line-item creation, updates, and deletion in AuditLog with the description, quantity, unit price, and line total before and after; the estimate's EstimateID is the affected record and the LineNumber is stored in the JSON. | FR-08, FR-17, SEC-03                                                     |
| Trigger                                        | `trg_InvoiceLineItem_Audit`                                                 | Records invoice line-item creation, updates, and deletion in AuditLog with the description, quantity, unit price, and line total before and after.                                                                                             | FR-08, FR-17, SEC-03                                                     |
| FR-13: Update inventory after parts usage      | Part → PartsUsage                                                           | QuantityOnHand CHECK; `sp_CompleteRepair`; `trg_PartInventory_Audit`                                                                                                                                                                           | T-08; T-18; T-26; T-28                                                   |
| FR-14: Modify non-completed appointments       | ServiceAppointment, Technician, Vehicle                                     | Status CHECK; `trg_ServiceAppointment_Status_Validate`; `trg_ServiceAppointment_Schedule_Validate`                                                                                                                                             | T-10; T-24; T-50                                                         |
| FR-15: Validate vehicle ownership              | Customer, Vehicle, ServiceAppointment, RepairEstimate, Repair, Invoice      | Vehicle.CustomerID FK; ownership check in `sp_CreateServiceAppointment`; estimates, repairs, and invoices inherit the validated owner through AppointmentID                                                                                    | T-03; T-32; T-56                                                         |
| FR-16: Prevent technician scheduling conflicts | Technician → ServiceAppointment                                             | `sp_CreateServiceAppointment` duration-based overlap check; `idx_ServiceAppointment_Technician_DateTime`; `trg_ServiceAppointment_Schedule_Validate`                                                                                           | T-05; T-52                                                               |
| FR-17: Store estimate and invoice line items   | RepairEstimate, EstimateLineItem, Invoice, InvoiceLineItem                  | EstimateLineItem composite PK; line-item FKs; quantity/unit-price CHECK constraints; `trg_EstimateLineItem_Validate`; `trg_InvoiceLineItem_Validate`                                                                                           | T-20; T-21; T;53 line-item creation demonstration                        |
| FR-18: Protect finalized records               | RepairEstimate, EstimateLineItem, Invoice, InvoiceLineItem                  | `trg_Invoice_Validate`; `trg_RepairEstimate_Validate`; `trg_InvoiceLineItem_Validate`; `trg_EstimateLineItem_Validate`                                                                                                                         | T-13; T-20; T-21                                                         |
| FR-19: Enforce valid status transitions        | ServiceAppointment, Repair, RepairEstimate, Invoice                         | Status CHECK constraints; `trg_ServiceAppointment_Status_Validate`; `trg_Repair_Status_Validate`; `trg_RepairEstimate_Validate`; `trg_Invoice_Validate`                                                                                        | T-06; T-19; T-24; T-50                                                   |
| FR-20: Use transactions for repair completion  | Repair, PartsUsage, Part, AuditLog                                          | `sp_CompleteRepair`; START TRANSACTION, COMMIT, ROLLBACK; audit rows written by triggers roll back with the transaction                                                                                                                        | T-09; T-18; T-26; T-33. T-51                                             |
