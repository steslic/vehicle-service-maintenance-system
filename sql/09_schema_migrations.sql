-- Infrastructure only; the runner creates this after verifying the baseline.
-- An empty history table means initialization was interrupted and is refused.
CREATE TABLE schema_migrations (
    version INT UNSIGNED NOT NULL PRIMARY KEY,
    filename VARCHAR(255) NOT NULL UNIQUE,
    checksum CHAR(64) NOT NULL,
    started_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    applied_at DATETIME(6) NULL,
    source_commit_sha VARCHAR(64) NOT NULL,
    source_dirty BOOLEAN NOT NULL,
    status ENUM('applying', 'applied', 'failed') NOT NULL,
    error_message TEXT NULL
) ENGINE=InnoDB;
