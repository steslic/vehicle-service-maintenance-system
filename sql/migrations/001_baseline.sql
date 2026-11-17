-- Baseline: the existing 13 business tables, 4 views, 3 procedures, 40 triggers.
-- Snapshot and history DDL digests below bind baseline verification to this version.
-- baseline-snapshot-sha256: 3cdfabd5974eae58352c2618d57013fff186a8ae8dcead889543a85f053e65b7
-- history-schema-sha256: 66cb38326dc30b46d32f8ca3582e69f65e10aafa3d94639bd72e4904dceff40f
CREATE TABLE schema_object_versions (
    object_type VARCHAR(20) NOT NULL,
    object_name VARCHAR(100) NOT NULL,
    migration_version INT UNSIGNED NOT NULL,
    definition_checksum CHAR(64) NOT NULL,
    source_commit_sha VARCHAR(64) NOT NULL,
    source_dirty BOOLEAN NOT NULL,
    PRIMARY KEY (object_type, object_name),
    FOREIGN KEY (migration_version) REFERENCES schema_migrations(version)
) ENGINE=InnoDB;
