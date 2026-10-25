-- Vehicle Service and Maintenance Management System
-- 01_schema.sql
-- Creates the database schema and all 13 core tables

DROP DATABASE IF EXISTS vehicle_service_maintenance;

CREATE DATABASE IF NOT EXISTS vehicle_service_maintenance;

USE vehicle_service_maintenance;


-- Customer

CREATE TABLE Customer (
    CustomerID INT NOT NULL AUTO_INCREMENT,
    Name VARCHAR(100) NOT NULL,
    Phone VARCHAR(25) NULL,
    Email VARCHAR(100) NULL,

    PRIMARY KEY (CustomerID)
);


-- Technician

CREATE TABLE Technician (
    TechnicianID INT NOT NULL AUTO_INCREMENT,
    Name VARCHAR(100) NOT NULL,
    Phone VARCHAR(25) NULL,
    Email VARCHAR(100) NULL,
    ActiveStatus BOOLEAN NOT NULL,

    PRIMARY KEY (TechnicianID),
    UNIQUE (Email)
);


-- Part

CREATE TABLE Part (
    PartID INT NOT NULL AUTO_INCREMENT,
    PartNumber VARCHAR(50) NOT NULL,
    PartName VARCHAR(100) NOT NULL,
    QuantityOnHand INT NOT NULL,
    UnitCost DECIMAL(10,2) NOT NULL,
    UnitSellingPrice DECIMAL(10,2) NOT NULL,
    MinimumInventoryLevel INT NOT NULL,
    ActiveStatus BOOLEAN NOT NULL,

    PRIMARY KEY (PartID),
    UNIQUE (PartNumber),

    CHECK (QuantityOnHand >= 0),
    CHECK (UnitCost >= 0),
    CHECK (UnitSellingPrice >= 0),
    CHECK (MinimumInventoryLevel >= 0)
);


-- UserAccount

CREATE TABLE UserAccount (
    UserID INT NOT NULL AUTO_INCREMENT,
    Username VARCHAR(100) NOT NULL,
    Name VARCHAR(100) NOT NULL,
    RoleType VARCHAR(30) NOT NULL,
    TechnicianID INT NULL,

    PRIMARY KEY (UserID),

    UNIQUE (Username),
    UNIQUE (TechnicianID),

    CHECK (
        RoleType IN (
            'Service Advisor',
            'Technician',
            'Manager'
        )
    ),

    FOREIGN KEY (TechnicianID)
        REFERENCES Technician(TechnicianID)
);


-- Vehicle

CREATE TABLE Vehicle (
    VehicleID INT NOT NULL AUTO_INCREMENT,
    CustomerID INT NOT NULL,
    VIN VARCHAR(17) NOT NULL,
    Make VARCHAR(50) NOT NULL,
    Model VARCHAR(50) NOT NULL,
    `Year` SMALLINT NOT NULL,

    PRIMARY KEY (VehicleID),

    UNIQUE (VIN),

    FOREIGN KEY (CustomerID)
        REFERENCES Customer(CustomerID)
);


-- ServiceAppointment

CREATE TABLE ServiceAppointment (
    AppointmentID INT NOT NULL AUTO_INCREMENT,
    VehicleID INT NOT NULL,
    TechnicianID INT NOT NULL,
    CreatedByUserID INT NOT NULL,
    AppointmentDateTime DATETIME NOT NULL,
    Status VARCHAR(20) NOT NULL,
    ServiceRequestDescription VARCHAR(500) NOT NULL,
    EstimatedDuration INT NOT NULL,
    CreationTimestamp DATETIME NOT NULL,
    CancellationDate DATE NULL,
    CancellationReason VARCHAR(500) NULL,

    PRIMARY KEY (AppointmentID),

    CHECK (
        Status IN (
            'Scheduled',
            'Checked In',
            'In Progress',
            'Completed',
            'Cancelled',
            'No Show'
        )
    ),

    CHECK (EstimatedDuration > 0),

    FOREIGN KEY (VehicleID)
        REFERENCES Vehicle(VehicleID),

    FOREIGN KEY (TechnicianID)
        REFERENCES Technician(TechnicianID),

    FOREIGN KEY (CreatedByUserID)
        REFERENCES UserAccount(UserID)
);


-- Repair

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

    PRIMARY KEY (RepairID),

    CHECK (
        Status IN (
            'Open',
            'In Progress',
            'Completed',
            'Cancelled'
        )
    ),

    CHECK (LaborHours >= 0),

    -- A Completed repair must record who completed it and when, which only
    -- sp_CompleteRepair sets, so technicians cannot bypass it (T-38)
    CONSTRAINT chk_Repair_Completion CHECK (
        Status <> 'Completed'
        OR (CompletedByTechnicianID IS NOT NULL AND CompletionDateTime IS NOT NULL)
    ),

    FOREIGN KEY (AppointmentID)
        REFERENCES ServiceAppointment(AppointmentID),

    FOREIGN KEY (CompletedByTechnicianID)
        REFERENCES Technician(TechnicianID)
);


-- RepairEstimate

CREATE TABLE RepairEstimate (
    EstimateID INT NOT NULL AUTO_INCREMENT,
    AppointmentID INT NOT NULL,
    CreatedByUserID INT NOT NULL,
    ApprovedByUserID INT NULL,
    EstimateDate DATE NOT NULL,
    Status VARCHAR(20) NOT NULL,
    TotalAmount DECIMAL(10,2) NOT NULL,
    ApprovalDateTime DATETIME NULL,

    PRIMARY KEY (EstimateID),

    UNIQUE (AppointmentID),

    CHECK (
        Status IN (
            'Draft',
            'Pending Approval',
            'Approved',
            'Rejected',
            'Expired',
            'Finalized'
        )
    ),

    CHECK (TotalAmount >= 0),

    FOREIGN KEY (AppointmentID)
        REFERENCES ServiceAppointment(AppointmentID),

    FOREIGN KEY (CreatedByUserID)
        REFERENCES UserAccount(UserID),

    FOREIGN KEY (ApprovedByUserID)
        REFERENCES UserAccount(UserID)
);


-- EstimateLineItem

CREATE TABLE EstimateLineItem (
    EstimateID INT NOT NULL,
    LineNumber INT NOT NULL,
    Description VARCHAR(500) NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL,
    LineTotal DECIMAL(10,2) NOT NULL,

    PRIMARY KEY (EstimateID, LineNumber),

    CHECK (Quantity > 0),
    CHECK (UnitPrice >= 0),
    CHECK (LineTotal >= 0),
    CONSTRAINT chk_EstimateLineItem_LineTotal CHECK (LineTotal = Quantity * UnitPrice),

    FOREIGN KEY (EstimateID)
        REFERENCES RepairEstimate(EstimateID)
);


-- Invoice

CREATE TABLE Invoice (
    InvoiceID INT NOT NULL AUTO_INCREMENT,
    AppointmentID INT NOT NULL,
    CreatedByUserID INT NOT NULL,
    FinalizedByUserID INT NULL,
    InvoiceDate DATE NOT NULL,
    Status VARCHAR(20) NOT NULL,
    TotalAmount DECIMAL(10,2) NOT NULL,
    FinalizationDateTime DATETIME NULL,

    PRIMARY KEY (InvoiceID),

    UNIQUE (AppointmentID),

    CHECK (
        Status IN (
            'Draft',
            'Finalized'
        )
    ),

    CHECK (TotalAmount >= 0),

    FOREIGN KEY (AppointmentID)
        REFERENCES ServiceAppointment(AppointmentID),

    FOREIGN KEY (CreatedByUserID)
        REFERENCES UserAccount(UserID),

    FOREIGN KEY (FinalizedByUserID)
        REFERENCES UserAccount(UserID)
);


-- InvoiceLineItem

CREATE TABLE InvoiceLineItem (
    InvoiceLineItemID INT NOT NULL AUTO_INCREMENT,
    InvoiceID INT NOT NULL,
    Description VARCHAR(500) NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL,
    LineTotal DECIMAL(10,2) NOT NULL,

    PRIMARY KEY (InvoiceLineItemID),

    CHECK (Quantity > 0),
    CHECK (UnitPrice >= 0),
    CHECK (LineTotal >= 0),
    CONSTRAINT chk_InvoiceLineItem_LineTotal CHECK (LineTotal = Quantity * UnitPrice),

    FOREIGN KEY (InvoiceID)
        REFERENCES Invoice(InvoiceID)
);


-- PartsUsage

CREATE TABLE PartsUsage (
    PartsUsageID INT NOT NULL AUTO_INCREMENT,
    RepairID INT NOT NULL,
    PartID INT NOT NULL,
    RecordedByUserID INT NOT NULL,
    QuantityUsed INT NOT NULL,
    UnitSellingPriceAtTimeOfUse DECIMAL(10,2) NOT NULL,
    UnitCostAtTimeOfUse DECIMAL(10,2) NOT NULL,
    RecordedDateTime DATETIME NOT NULL,

    PRIMARY KEY (PartsUsageID),

    CHECK (QuantityUsed > 0),
    CHECK (UnitSellingPriceAtTimeOfUse >= 0),
    CHECK (UnitCostAtTimeOfUse >= 0),

    FOREIGN KEY (RepairID)
        REFERENCES Repair(RepairID),

    FOREIGN KEY (PartID)
        REFERENCES Part(PartID),

    FOREIGN KEY (RecordedByUserID)
        REFERENCES UserAccount(UserID)
);


-- AuditLog

CREATE TABLE AuditLog (
    AuditLogID INT NOT NULL AUTO_INCREMENT,
    UserID INT NOT NULL,
    `Timestamp` DATETIME NOT NULL,
    Action VARCHAR(50) NOT NULL,
    AffectedEntity VARCHAR(100) NOT NULL,
    AffectedRecordID INT NULL, -- NULL for a rejected request that created no record 
    PreviousValue JSON NULL,
    NewValue JSON NULL,
    ContextID CHAR(36) NULL, -- groups the audit rows written by one procedure call 

    PRIMARY KEY (AuditLogID),

    FOREIGN KEY (UserID)
        REFERENCES UserAccount(UserID)
);