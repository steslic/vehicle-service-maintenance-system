-- Revision 007 builds on the immutable v006 checkpoint 71696139e84a4e9b69f4baa6f89a6a8d20505561.
-- Only the runner creates fresh databases; never source this into an existing schema.
CREATE DATABASE vehicle_service_maintenance CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE vehicle_service_maintenance;

CREATE TABLE `schema_migrations` (
  `version` int unsigned NOT NULL,
  `filename` varchar(255) NOT NULL,
  `checksum` char(64) NOT NULL,
  `started_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `applied_at` datetime(6) DEFAULT NULL,
  `source_commit_sha` varchar(64) NOT NULL,
  `source_dirty` tinyint(1) NOT NULL,
  `status` enum('applying','applied','failed','covered') NOT NULL,
  `error_message` text,
  `baseline_version` int unsigned DEFAULT NULL,
  `baseline_checksum` char(64) DEFAULT NULL,
  `covered_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`version`),
  UNIQUE KEY `filename` (`filename`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Fresh-installation revision history is separate from historical migration execution.
CREATE TABLE `schema_revisions` (
  `revision` int unsigned NOT NULL,
  `contract_file` varchar(255) NOT NULL,
  `contract_checksum` char(64) NOT NULL,
  `source_commit_sha` varchar(64) NOT NULL,
  `source_dirty` tinyint(1) NOT NULL,
  `status` enum('applying','installed','failed') NOT NULL,
  `started_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `installed_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`revision`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `schema_object_versions` (
  `object_type` varchar(20) NOT NULL,
  `object_name` varchar(100) NOT NULL,
  `migration_version` int unsigned DEFAULT NULL,
  `revision_version` int unsigned DEFAULT NULL,
  `definition_checksum` char(64) NOT NULL,
  `source_commit_sha` varchar(64) NOT NULL,
  `source_dirty` tinyint(1) NOT NULL,
  PRIMARY KEY (`object_type`,`object_name`),
  KEY `migration_version` (`migration_version`),
  CONSTRAINT `schema_object_versions_revision_fk` FOREIGN KEY (`revision_version`) REFERENCES `schema_revisions` (`revision`),
  CONSTRAINT `schema_object_versions_ibfk_1` FOREIGN KEY (`migration_version`) REFERENCES `schema_migrations` (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- BEGIN APPLICATION TABLES
CREATE TABLE `AuditLog` (
  `AuditLogID` int NOT NULL AUTO_INCREMENT,
  `UserID` int DEFAULT NULL,
  `Timestamp` datetime NOT NULL,
  `Action` varchar(50) NOT NULL,
  `AffectedEntity` varchar(100) NOT NULL,
  `AffectedRecordID` int DEFAULT NULL,
  `PreviousValue` json DEFAULT NULL,
  `NewValue` json DEFAULT NULL,
  `ContextID` char(36) DEFAULT NULL,
  `ActionIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'audit_action') STORED,
  `EntityIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'audit_entity') STORED,
  `SessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `ApplicationErrorID` varchar(64) DEFAULT NULL,
  `ErrorClass` varchar(16) DEFAULT NULL,
  `ErrorSQLSTATE` char(5) DEFAULT NULL,
  `ErrorNumber` int DEFAULT NULL,
  `ErrorMessage` text,
  `TransactionOutcome` varchar(16) DEFAULT NULL,
  PRIMARY KEY (`AuditLogID`),
  CONSTRAINT `chk_AuditLog_ResponsiblePerson` CHECK (((`Action` = _utf8mb4'Rejected') or (`UserID` is not null)))
) ENGINE=InnoDB AUTO_INCREMENT=123 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `Customer` (
  `CustomerID` int NOT NULL AUTO_INCREMENT,
  `Name` varchar(100) NOT NULL,
  `Phone` varchar(25) DEFAULT NULL,
  `Email` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`CustomerID`)
) ENGINE=InnoDB AUTO_INCREMENT=101 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `CustomerHistory` (
  `CustomerID` int NOT NULL DEFAULT '0',
  `Name` varchar(100) NOT NULL,
  `Phone` varchar(25) DEFAULT NULL,
  `Email` varchar(100) DEFAULT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `customerhistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `customerhistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `customerhistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `DatabasePrincipal` (
  `SessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `PrincipalType` varchar(20) NOT NULL,
  `UserID` int DEFAULT NULL,
  `TypeIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'principal_type') STORED,
  PRIMARY KEY (`SessionAccount`),
  CONSTRAINT `databaseprincipal_chk_1` CHECK ((((`PrincipalType` = _utf8mb4'Person') and (`UserID` is not null)) or ((`PrincipalType` = _utf8mb4'Service') and (`UserID` is null)))),
  CONSTRAINT `databaseprincipal_chk_2` CHECK ((trim(`SessionAccount`) <> _utf8mb4''))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `DatabasePrincipalHistory` (
  `SessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `PrincipalType` varchar(20) NOT NULL,
  `UserID` int DEFAULT NULL,
  `TypeIndicator` varchar(64) DEFAULT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `databaseprincipalhistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `databaseprincipalhistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `databaseprincipalhistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `EstimateLineItem` (
  `EstimateID` int NOT NULL,
  `LineNumber` int NOT NULL,
  `Description` varchar(500) NOT NULL,
  `Quantity` int NOT NULL,
  `UnitPrice` decimal(10,2) NOT NULL,
  `LineTotal` decimal(10,2) NOT NULL,
  PRIMARY KEY (`EstimateID`,`LineNumber`),
  CONSTRAINT `chk_EstimateLineItem_LineTotal` CHECK ((`LineTotal` = (`Quantity` * `UnitPrice`))),
  CONSTRAINT `estimatelineitem_chk_1` CHECK ((`Quantity` > 0)),
  CONSTRAINT `estimatelineitem_chk_2` CHECK ((`UnitPrice` >= 0)),
  CONSTRAINT `estimatelineitem_chk_3` CHECK ((`LineTotal` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `EstimateLineItemHistory` (
  `EstimateID` int NOT NULL,
  `LineNumber` int NOT NULL,
  `Description` varchar(500) NOT NULL,
  `Quantity` int NOT NULL,
  `UnitPrice` decimal(10,2) NOT NULL,
  `LineTotal` decimal(10,2) NOT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `estimatelineitemhistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `estimatelineitemhistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `estimatelineitemhistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `IndicatorValue` (
  `IndicatorName` varchar(64) NOT NULL,
  `ValueCode` varchar(100) NOT NULL,
  `Description` varchar(255) NOT NULL,
  `DisplayOrder` int NOT NULL,
  PRIMARY KEY (`IndicatorName`,`ValueCode`),
  CONSTRAINT `indicatorvalue_chk_1` CHECK (((trim(`IndicatorName`) <> _utf8mb4'') and (trim(`ValueCode`) <> _utf8mb4'') and (trim(`Description`) <> _utf8mb4''))),
  CONSTRAINT `indicatorvalue_chk_2` CHECK ((`DisplayOrder` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `IndicatorValueHistory` (
  `IndicatorName` varchar(64) NOT NULL,
  `ValueCode` varchar(100) NOT NULL,
  `Description` varchar(255) NOT NULL,
  `DisplayOrder` int NOT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `indicatorvaluehistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `indicatorvaluehistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `indicatorvaluehistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `Invoice` (
  `InvoiceID` int NOT NULL AUTO_INCREMENT,
  `AppointmentID` int NOT NULL,
  `CreatedByUserID` int NOT NULL,
  `FinalizedByUserID` int DEFAULT NULL,
  `InvoiceDate` date NOT NULL,
  `Status` varchar(20) NOT NULL,
  `TotalAmount` decimal(10,2) NOT NULL,
  `FinalizationDateTime` datetime DEFAULT NULL,
  `StatusIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'invoice_status') STORED,
  PRIMARY KEY (`InvoiceID`),
  CONSTRAINT `invoice_chk_2` CHECK ((`TotalAmount` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `InvoiceHistory` (
  `InvoiceID` int NOT NULL DEFAULT '0',
  `AppointmentID` int NOT NULL,
  `CreatedByUserID` int NOT NULL,
  `FinalizedByUserID` int DEFAULT NULL,
  `InvoiceDate` date NOT NULL,
  `Status` varchar(20) NOT NULL,
  `TotalAmount` decimal(10,2) NOT NULL,
  `FinalizationDateTime` datetime DEFAULT NULL,
  `StatusIndicator` varchar(64) DEFAULT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `invoicehistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `invoicehistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `invoicehistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `InvoiceLineItem` (
  `InvoiceLineItemID` int NOT NULL AUTO_INCREMENT,
  `InvoiceID` int NOT NULL,
  `Description` varchar(500) NOT NULL,
  `Quantity` int NOT NULL,
  `UnitPrice` decimal(10,2) NOT NULL,
  `LineTotal` decimal(10,2) NOT NULL,
  PRIMARY KEY (`InvoiceLineItemID`),
  CONSTRAINT `chk_InvoiceLineItem_LineTotal` CHECK ((`LineTotal` = (`Quantity` * `UnitPrice`))),
  CONSTRAINT `invoicelineitem_chk_1` CHECK ((`Quantity` > 0)),
  CONSTRAINT `invoicelineitem_chk_2` CHECK ((`UnitPrice` >= 0)),
  CONSTRAINT `invoicelineitem_chk_3` CHECK ((`LineTotal` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `InvoiceLineItemHistory` (
  `InvoiceLineItemID` int NOT NULL DEFAULT '0',
  `InvoiceID` int NOT NULL,
  `Description` varchar(500) NOT NULL,
  `Quantity` int NOT NULL,
  `UnitPrice` decimal(10,2) NOT NULL,
  `LineTotal` decimal(10,2) NOT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `invoicelineitemhistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `invoicelineitemhistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `invoicelineitemhistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `OperationContext` (
  `ConnectionID` bigint unsigned NOT NULL,
  `SessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `UserID` int NOT NULL,
  `ProcedureName` varchar(64) NOT NULL,
  `ContextID` char(36) NOT NULL,
  PRIMARY KEY (`ConnectionID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `Part` (
  `PartID` int NOT NULL AUTO_INCREMENT,
  `PartNumber` varchar(50) NOT NULL,
  `PartName` varchar(100) NOT NULL,
  `QuantityOnHand` int NOT NULL,
  `UnitCost` decimal(10,2) NOT NULL,
  `UnitSellingPrice` decimal(10,2) NOT NULL,
  `MinimumInventoryLevel` int NOT NULL,
  `ActiveStatus` tinyint(1) NOT NULL,
  `ActiveIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'active_status') STORED,
  `ActiveCode` varchar(100) GENERATED ALWAYS AS (cast(`ActiveStatus` as char charset utf8mb4)) STORED,
  PRIMARY KEY (`PartID`),
  CONSTRAINT `part_chk_1` CHECK ((`QuantityOnHand` >= 0)),
  CONSTRAINT `part_chk_2` CHECK ((`UnitCost` >= 0)),
  CONSTRAINT `part_chk_3` CHECK ((`UnitSellingPrice` >= 0)),
  CONSTRAINT `part_chk_4` CHECK ((`MinimumInventoryLevel` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `PartHistory` (
  `PartID` int NOT NULL DEFAULT '0',
  `PartNumber` varchar(50) NOT NULL,
  `PartName` varchar(100) NOT NULL,
  `QuantityOnHand` int NOT NULL,
  `UnitCost` decimal(10,2) NOT NULL,
  `UnitSellingPrice` decimal(10,2) NOT NULL,
  `MinimumInventoryLevel` int NOT NULL,
  `ActiveStatus` tinyint(1) NOT NULL,
  `ActiveIndicator` varchar(64) DEFAULT NULL,
  `ActiveCode` varchar(100) DEFAULT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `parthistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `parthistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `parthistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `PartsUsage` (
  `PartsUsageID` int NOT NULL AUTO_INCREMENT,
  `RepairID` int NOT NULL,
  `PartID` int NOT NULL,
  `RecordedByUserID` int NOT NULL,
  `QuantityUsed` int NOT NULL,
  `UnitSellingPriceAtTimeOfUse` decimal(10,2) NOT NULL,
  `UnitCostAtTimeOfUse` decimal(10,2) NOT NULL,
  `RecordedDateTime` datetime NOT NULL,
  PRIMARY KEY (`PartsUsageID`),
  CONSTRAINT `partsusage_chk_1` CHECK ((`QuantityUsed` > 0)),
  CONSTRAINT `partsusage_chk_2` CHECK ((`UnitSellingPriceAtTimeOfUse` >= 0)),
  CONSTRAINT `partsusage_chk_3` CHECK ((`UnitCostAtTimeOfUse` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `PartsUsageHistory` (
  `PartsUsageID` int NOT NULL DEFAULT '0',
  `RepairID` int NOT NULL,
  `PartID` int NOT NULL,
  `RecordedByUserID` int NOT NULL,
  `QuantityUsed` int NOT NULL,
  `UnitSellingPriceAtTimeOfUse` decimal(10,2) NOT NULL,
  `UnitCostAtTimeOfUse` decimal(10,2) NOT NULL,
  `RecordedDateTime` datetime NOT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `partsusagehistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `partsusagehistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `partsusagehistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `PrincipalDelegation` (
  `SessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `UserID` int NOT NULL,
  `ProcedureName` varchar(64) NOT NULL,
  `ProcedureIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'procedure_name') STORED,
  PRIMARY KEY (`SessionAccount`,`UserID`,`ProcedureName`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `PrincipalDelegationHistory` (
  `SessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `UserID` int NOT NULL,
  `ProcedureName` varchar(64) NOT NULL,
  `ProcedureIndicator` varchar(64) DEFAULT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `principaldelegationhistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `principaldelegationhistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `principaldelegationhistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `Repair` (
  `RepairID` int NOT NULL AUTO_INCREMENT,
  `AppointmentID` int NOT NULL,
  `CompletedByTechnicianID` int DEFAULT NULL,
  `RepairDateTime` datetime NOT NULL,
  `RepairType` varchar(100) NOT NULL,
  `RepairDescription` varchar(500) NOT NULL,
  `LaborHours` decimal(5,2) DEFAULT NULL,
  `Status` varchar(20) NOT NULL,
  `CompletionDateTime` datetime DEFAULT NULL,
  `StatusIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'repair_status') STORED,
  `TypeIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'repair_type') STORED,
  PRIMARY KEY (`RepairID`),
  CONSTRAINT `chk_Repair_Completion` CHECK (((`Status` <> _utf8mb4'Completed') or ((`CompletedByTechnicianID` is not null) and (`CompletionDateTime` is not null)))),
  CONSTRAINT `repair_chk_2` CHECK ((`LaborHours` >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `RepairEstimate` (
  `EstimateID` int NOT NULL AUTO_INCREMENT,
  `AppointmentID` int NOT NULL,
  `CreatedByUserID` int NOT NULL,
  `ApprovedByUserID` int DEFAULT NULL,
  `EstimateDate` date NOT NULL,
  `Status` varchar(20) NOT NULL,
  `TotalAmount` decimal(10,2) NOT NULL,
  `ApprovalDateTime` datetime DEFAULT NULL,
  `StatusIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'estimate_status') STORED,
  PRIMARY KEY (`EstimateID`),
  CONSTRAINT `repairestimate_chk_2` CHECK ((`TotalAmount` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `RepairEstimateHistory` (
  `EstimateID` int NOT NULL DEFAULT '0',
  `AppointmentID` int NOT NULL,
  `CreatedByUserID` int NOT NULL,
  `ApprovedByUserID` int DEFAULT NULL,
  `EstimateDate` date NOT NULL,
  `Status` varchar(20) NOT NULL,
  `TotalAmount` decimal(10,2) NOT NULL,
  `ApprovalDateTime` datetime DEFAULT NULL,
  `StatusIndicator` varchar(64) DEFAULT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `repairestimatehistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `repairestimatehistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `repairestimatehistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `RepairHistory` (
  `RepairID` int NOT NULL DEFAULT '0',
  `AppointmentID` int NOT NULL,
  `CompletedByTechnicianID` int DEFAULT NULL,
  `RepairDateTime` datetime NOT NULL,
  `RepairType` varchar(100) NOT NULL,
  `RepairDescription` varchar(500) NOT NULL,
  `LaborHours` decimal(5,2) DEFAULT NULL,
  `Status` varchar(20) NOT NULL,
  `CompletionDateTime` datetime DEFAULT NULL,
  `StatusIndicator` varchar(64) DEFAULT NULL,
  `TypeIndicator` varchar(64) DEFAULT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `repairhistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `repairhistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `repairhistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `RoleProcedurePermission` (
  `RoleType` varchar(30) NOT NULL,
  `ProcedureName` varchar(64) NOT NULL,
  `RoleIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'user_role') STORED,
  `ProcedureIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'procedure_name') STORED,
  PRIMARY KEY (`RoleType`,`ProcedureName`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `RoleProcedurePermissionHistory` (
  `RoleType` varchar(30) NOT NULL,
  `ProcedureName` varchar(64) NOT NULL,
  `RoleIndicator` varchar(64) DEFAULT NULL,
  `ProcedureIndicator` varchar(64) DEFAULT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `roleprocedurepermissionhistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `roleprocedurepermissionhistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `roleprocedurepermissionhistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `ServiceAppointment` (
  `AppointmentID` int NOT NULL AUTO_INCREMENT,
  `VehicleID` int NOT NULL,
  `TechnicianID` int NOT NULL,
  `CreatedByUserID` int NOT NULL,
  `AppointmentDateTime` datetime NOT NULL,
  `Status` varchar(20) NOT NULL,
  `ServiceRequestDescription` varchar(500) NOT NULL,
  `EstimatedDuration` int NOT NULL,
  `CreationTimestamp` datetime NOT NULL,
  `CancellationDate` date DEFAULT NULL,
  `CancellationReason` varchar(500) DEFAULT NULL,
  `StatusIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'appointment_status') STORED,
  PRIMARY KEY (`AppointmentID`),
  CONSTRAINT `serviceappointment_chk_2` CHECK ((`EstimatedDuration` > 0))
) ENGINE=InnoDB AUTO_INCREMENT=17 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `ServiceAppointmentHistory` (
  `AppointmentID` int NOT NULL DEFAULT '0',
  `VehicleID` int NOT NULL,
  `TechnicianID` int NOT NULL,
  `CreatedByUserID` int NOT NULL,
  `AppointmentDateTime` datetime NOT NULL,
  `Status` varchar(20) NOT NULL,
  `ServiceRequestDescription` varchar(500) NOT NULL,
  `EstimatedDuration` int NOT NULL,
  `CreationTimestamp` datetime NOT NULL,
  `CancellationDate` date DEFAULT NULL,
  `CancellationReason` varchar(500) DEFAULT NULL,
  `StatusIndicator` varchar(64) DEFAULT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `serviceappointmenthistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `serviceappointmenthistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `serviceappointmenthistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `Technician` (
  `TechnicianID` int NOT NULL AUTO_INCREMENT,
  `Name` varchar(100) NOT NULL,
  `Phone` varchar(25) DEFAULT NULL,
  `Email` varchar(100) DEFAULT NULL,
  `ActiveStatus` tinyint(1) NOT NULL,
  `ActiveIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'active_status') STORED,
  `ActiveCode` varchar(100) GENERATED ALWAYS AS (cast(`ActiveStatus` as char charset utf8mb4)) STORED,
  PRIMARY KEY (`TechnicianID`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `TechnicianHistory` (
  `TechnicianID` int NOT NULL DEFAULT '0',
  `Name` varchar(100) NOT NULL,
  `Phone` varchar(25) DEFAULT NULL,
  `Email` varchar(100) DEFAULT NULL,
  `ActiveStatus` tinyint(1) NOT NULL,
  `ActiveIndicator` varchar(64) DEFAULT NULL,
  `ActiveCode` varchar(100) DEFAULT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `technicianhistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `technicianhistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `technicianhistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `TemporalEvent` (
  `EventID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `EntityType` varchar(64) NOT NULL,
  `RecordIdentifier` varchar(1024) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `RecordHash` binary(32) GENERATED ALWAYS AS (unhex(sha2(`RecordIdentifier`,256))) STORED,
  `OperationType` varchar(10) NOT NULL,
  `ChangedAttributes` json NOT NULL,
  `ResponsibleUserID` int DEFAULT NULL,
  `SessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `EventTimestamp` datetime(6) NOT NULL,
  `ContextID` char(36) DEFAULT NULL,
  `Reason` varchar(500) DEFAULT NULL,
  PRIMARY KEY (`EventID`),
  CONSTRAINT `temporalevent_chk_1` CHECK ((`OperationType` in (_utf8mb4'Insert',_utf8mb4'Update',_utf8mb4'Delete')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `TemporalWriteContext` (
  `ConnectionID` bigint unsigned NOT NULL,
  `SessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `EntityType` varchar(64) NOT NULL,
  PRIMARY KEY (`ConnectionID`,`EntityType`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `UserAccount` (
  `UserID` int NOT NULL AUTO_INCREMENT,
  `Username` varchar(100) NOT NULL,
  `Name` varchar(100) NOT NULL,
  `RoleType` varchar(30) NOT NULL,
  `TechnicianID` int DEFAULT NULL,
  `RoleIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'user_role') STORED,
  PRIMARY KEY (`UserID`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `UserAccountHistory` (
  `UserID` int NOT NULL DEFAULT '0',
  `Username` varchar(100) NOT NULL,
  `Name` varchar(100) NOT NULL,
  `RoleType` varchar(30) NOT NULL,
  `TechnicianID` int DEFAULT NULL,
  `RoleIndicator` varchar(64) DEFAULT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `useraccounthistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `useraccounthistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `useraccounthistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `UserRolePolicy` (
  `RoleType` varchar(30) NOT NULL,
  `RequiresTechnician` tinyint(1) NOT NULL,
  `RoleIndicator` varchar(64) GENERATED ALWAYS AS (_utf8mb4'user_role') STORED,
  PRIMARY KEY (`RoleType`),
  CONSTRAINT `userrolepolicy_chk_1` CHECK ((`RequiresTechnician` in (0,1)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `UserRolePolicyHistory` (
  `RoleType` varchar(30) NOT NULL,
  `RequiresTechnician` tinyint(1) NOT NULL,
  `RoleIndicator` varchar(64) DEFAULT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `userrolepolicyhistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `userrolepolicyhistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `userrolepolicyhistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `Vehicle` (
  `VehicleID` int NOT NULL AUTO_INCREMENT,
  `CustomerID` int NOT NULL,
  `VIN` varchar(17) NOT NULL,
  `Make` varchar(50) NOT NULL,
  `Model` varchar(50) NOT NULL,
  `Year` smallint NOT NULL,
  PRIMARY KEY (`VehicleID`)
) ENGINE=InnoDB AUTO_INCREMENT=101 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `VehicleHistory` (
  `VehicleID` int NOT NULL DEFAULT '0',
  `CustomerID` int NOT NULL,
  `VIN` varchar(17) NOT NULL,
  `Make` varchar(50) NOT NULL,
  `Model` varchar(50) NOT NULL,
  `Year` smallint NOT NULL,
  `HistoryID` bigint unsigned NOT NULL AUTO_INCREMENT,
  `HistoryVersion` bigint unsigned NOT NULL,
  `HistoryValidFrom` datetime(6) DEFAULT NULL,
  `HistoryValidTo` datetime(6) DEFAULT NULL,
  `HistoryRecordedAt` datetime(6) NOT NULL,
  `HistoryOrigin` varchar(10) NOT NULL,
  `HistoryUserID` int DEFAULT NULL,
  `HistorySessionAccount` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryContextID` char(36) DEFAULT NULL,
  `HistoryReason` varchar(500) DEFAULT NULL,
  `HistoryStartEventID` bigint unsigned DEFAULT NULL,
  `HistoryEndEventID` bigint unsigned DEFAULT NULL,
  `HistoryClosedByUserID` int DEFAULT NULL,
  `HistoryClosedBySession` varchar(288) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `HistoryClosedContextID` char(36) DEFAULT NULL,
  `HistoryCloseReason` varchar(500) DEFAULT NULL,
  `HistoryCloseOperation` varchar(10) DEFAULT NULL,
  `HistoryIsCurrent` tinyint GENERATED ALWAYS AS (if((`HistoryValidTo` is null),1,NULL)) STORED,
  PRIMARY KEY (`HistoryID`),
  CONSTRAINT `vehiclehistory_chk_1` CHECK ((`HistoryVersion` > 0)),
  CONSTRAINT `vehiclehistory_chk_2` CHECK ((`HistoryOrigin` in (_utf8mb4'Snapshot',_utf8mb4'Insert',_utf8mb4'Update'))),
  CONSTRAINT `vehiclehistory_chk_3` CHECK (((`HistoryValidTo` is null) or (`HistoryValidFrom` is null) or (`HistoryValidTo` > `HistoryValidFrom`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- BEGIN FOREIGN KEYS
ALTER TABLE `AuditLog` ADD CONSTRAINT `auditlog_ibfk_1` FOREIGN KEY (`UserID`) REFERENCES `UserAccount` (`UserID`);
ALTER TABLE `AuditLog` ADD CONSTRAINT `fk_AuditLog_ActionIndicator` FOREIGN KEY (`ActionIndicator`, `Action`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `AuditLog` ADD CONSTRAINT `fk_AuditLog_EntityIndicator` FOREIGN KEY (`EntityIndicator`, `AffectedEntity`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `DatabasePrincipal` ADD CONSTRAINT `databaseprincipal_ibfk_1` FOREIGN KEY (`TypeIndicator`, `PrincipalType`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `DatabasePrincipal` ADD CONSTRAINT `databaseprincipal_ibfk_2` FOREIGN KEY (`UserID`) REFERENCES `UserAccount` (`UserID`);
ALTER TABLE `EstimateLineItem` ADD CONSTRAINT `estimatelineitem_ibfk_1` FOREIGN KEY (`EstimateID`) REFERENCES `RepairEstimate` (`EstimateID`);
ALTER TABLE `Invoice` ADD CONSTRAINT `fk_Invoice_StatusIndicator` FOREIGN KEY (`StatusIndicator`, `Status`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `Invoice` ADD CONSTRAINT `invoice_ibfk_1` FOREIGN KEY (`AppointmentID`) REFERENCES `ServiceAppointment` (`AppointmentID`);
ALTER TABLE `Invoice` ADD CONSTRAINT `invoice_ibfk_2` FOREIGN KEY (`CreatedByUserID`) REFERENCES `UserAccount` (`UserID`);
ALTER TABLE `Invoice` ADD CONSTRAINT `invoice_ibfk_3` FOREIGN KEY (`FinalizedByUserID`) REFERENCES `UserAccount` (`UserID`);
ALTER TABLE `InvoiceLineItem` ADD CONSTRAINT `invoicelineitem_ibfk_1` FOREIGN KEY (`InvoiceID`) REFERENCES `Invoice` (`InvoiceID`);
ALTER TABLE `OperationContext` ADD CONSTRAINT `operationcontext_ibfk_1` FOREIGN KEY (`SessionAccount`) REFERENCES `DatabasePrincipal` (`SessionAccount`);
ALTER TABLE `OperationContext` ADD CONSTRAINT `operationcontext_ibfk_2` FOREIGN KEY (`UserID`) REFERENCES `UserAccount` (`UserID`);
ALTER TABLE `Part` ADD CONSTRAINT `fk_Part_ActiveIndicator` FOREIGN KEY (`ActiveIndicator`, `ActiveCode`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `PartsUsage` ADD CONSTRAINT `partsusage_ibfk_1` FOREIGN KEY (`RepairID`) REFERENCES `Repair` (`RepairID`);
ALTER TABLE `PartsUsage` ADD CONSTRAINT `partsusage_ibfk_2` FOREIGN KEY (`PartID`) REFERENCES `Part` (`PartID`);
ALTER TABLE `PartsUsage` ADD CONSTRAINT `partsusage_ibfk_3` FOREIGN KEY (`RecordedByUserID`) REFERENCES `UserAccount` (`UserID`);
ALTER TABLE `PrincipalDelegation` ADD CONSTRAINT `principaldelegation_ibfk_1` FOREIGN KEY (`SessionAccount`) REFERENCES `DatabasePrincipal` (`SessionAccount`);
ALTER TABLE `PrincipalDelegation` ADD CONSTRAINT `principaldelegation_ibfk_2` FOREIGN KEY (`UserID`) REFERENCES `UserAccount` (`UserID`);
ALTER TABLE `PrincipalDelegation` ADD CONSTRAINT `principaldelegation_ibfk_3` FOREIGN KEY (`ProcedureIndicator`, `ProcedureName`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `Repair` ADD CONSTRAINT `fk_Repair_StatusIndicator` FOREIGN KEY (`StatusIndicator`, `Status`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `Repair` ADD CONSTRAINT `fk_Repair_TypeIndicator` FOREIGN KEY (`TypeIndicator`, `RepairType`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `Repair` ADD CONSTRAINT `repair_ibfk_1` FOREIGN KEY (`AppointmentID`) REFERENCES `ServiceAppointment` (`AppointmentID`);
ALTER TABLE `Repair` ADD CONSTRAINT `repair_ibfk_2` FOREIGN KEY (`CompletedByTechnicianID`) REFERENCES `Technician` (`TechnicianID`);
ALTER TABLE `RepairEstimate` ADD CONSTRAINT `fk_RepairEstimate_StatusIndicator` FOREIGN KEY (`StatusIndicator`, `Status`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `RepairEstimate` ADD CONSTRAINT `repairestimate_ibfk_1` FOREIGN KEY (`AppointmentID`) REFERENCES `ServiceAppointment` (`AppointmentID`);
ALTER TABLE `RepairEstimate` ADD CONSTRAINT `repairestimate_ibfk_2` FOREIGN KEY (`CreatedByUserID`) REFERENCES `UserAccount` (`UserID`);
ALTER TABLE `RepairEstimate` ADD CONSTRAINT `repairestimate_ibfk_3` FOREIGN KEY (`ApprovedByUserID`) REFERENCES `UserAccount` (`UserID`);
ALTER TABLE `RoleProcedurePermission` ADD CONSTRAINT `roleprocedurepermission_ibfk_1` FOREIGN KEY (`RoleIndicator`, `RoleType`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `RoleProcedurePermission` ADD CONSTRAINT `roleprocedurepermission_ibfk_2` FOREIGN KEY (`ProcedureIndicator`, `ProcedureName`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `ServiceAppointment` ADD CONSTRAINT `fk_ServiceAppointment_StatusIndicator` FOREIGN KEY (`StatusIndicator`, `Status`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `ServiceAppointment` ADD CONSTRAINT `serviceappointment_ibfk_1` FOREIGN KEY (`VehicleID`) REFERENCES `Vehicle` (`VehicleID`);
ALTER TABLE `ServiceAppointment` ADD CONSTRAINT `serviceappointment_ibfk_2` FOREIGN KEY (`TechnicianID`) REFERENCES `Technician` (`TechnicianID`);
ALTER TABLE `ServiceAppointment` ADD CONSTRAINT `serviceappointment_ibfk_3` FOREIGN KEY (`CreatedByUserID`) REFERENCES `UserAccount` (`UserID`);
ALTER TABLE `Technician` ADD CONSTRAINT `fk_Technician_ActiveIndicator` FOREIGN KEY (`ActiveIndicator`, `ActiveCode`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `UserAccount` ADD CONSTRAINT `fk_UserAccount_RoleIndicator` FOREIGN KEY (`RoleIndicator`, `RoleType`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `UserAccount` ADD CONSTRAINT `fk_UserAccount_RolePolicy` FOREIGN KEY (`RoleType`) REFERENCES `UserRolePolicy` (`RoleType`);
ALTER TABLE `UserAccount` ADD CONSTRAINT `useraccount_ibfk_1` FOREIGN KEY (`TechnicianID`) REFERENCES `Technician` (`TechnicianID`);
ALTER TABLE `UserRolePolicy` ADD CONSTRAINT `userrolepolicy_ibfk_1` FOREIGN KEY (`RoleIndicator`, `RoleType`) REFERENCES `IndicatorValue` (`IndicatorName`, `ValueCode`);
ALTER TABLE `Vehicle` ADD CONSTRAINT `vehicle_ibfk_1` FOREIGN KEY (`CustomerID`) REFERENCES `Customer` (`CustomerID`);
