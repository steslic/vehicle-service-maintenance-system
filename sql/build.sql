-- Vehicle Service and Maintenance Management System
-- Ordered input list for scripts/build.py. The runner validates and inlines
-- these files so SOURCE cannot hide an error or a missing file.
-- Demo provisioning is optional and runs before the existing test suite.

SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'Use python3 scripts/build.py; direct SOURCE builds are disabled';

SOURCE 01_schema.sql
SOURCE 02_indexes.sql
SOURCE 03_views_reports.sql
SOURCE 04_procedures.sql
SOURCE 05_triggers_roles.sql
SOURCE 06_sample_data.sql
SOURCE 08_demo_accounts.sql
SOURCE 07_tests.sql

-- Migration infrastructure and ordered upgrades (interpreted by the runner).
SOURCE 09_schema_migrations.sql
SOURCE migrations/001_baseline.sql
SOURCE migrations/002_customer_name_index.sql
SOURCE migrations/003_indicator_values.sql
SOURCE migrations/004_session_identity_and_provenance.sql
SOURCE migrations/005_temporal_history.sql
SOURCE migrations/006_standardized_error_handling.sql
