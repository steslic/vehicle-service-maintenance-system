# Temporal history and audit trail

**Current revision 007:** [Procedure-only operations](procedure-operations.md) adds 29 typed mutation interfaces and removes application table/writable-view DML. Its separately pinned child contract preserves exact v006 ancestry and all existing trigger/history definitions. The v006 installation/entitlement details below remain historical context where superseded by that guide. Current fresh builds require an admin principal-collision inspection and do not silently convert existing native grants; full role/demo provisioning remains optional. Revision 007 has 41 base tables (one additional administrative table), 276 tracked objects, 45 SQL assertions, and 170 Python tests. Applications must use clean connections without caller transactions; A2 detection remains deferred.

Migration [005_temporal_history.sql](../sql/migrations/005_temporal_history.sql) historically introduced row-version history without changing migrations 001–004 or replacing the existing generic `AuditLog`. The current version-006 implementation is defined by consolidated SQL files 01–08, including standardized errors and protected diagnostic propagation. Normal fresh installations use those definitions through [scripts/build.py](../scripts/build.py) and [sql/build.sql](../sql/build.sql); they do not read or execute migrations 001–006. See [SQL consolidation](sql-consolidation.md) for the phased build and baseline coverage records.

Existing databases use `--migrate` to execute only pending historical/later migrations. Migration 005 remains the upgrade that initializes temporal history for a version-004 database; migration 006 subsequently standardizes errors without rebuilding its snapshots. Frozen original files under `sql/legacy/v001/` and the unchanged migrations support historical build reproduction. Stop application writes and retain a verified backup before upgrading; migration locks serialize migration runners, not application traffic. The existing implicit-DDL-commit/manual-recovery contract still applies.

## Coverage and objects

Every source column is copied with its SQL type and collation. Each source table below has a corresponding `<Table>History` table:

| Category | Source tables |
| --- | --- |
| Master data | Customer, Vehicle, Technician, Part, UserAccount |
| Transactions | ServiceAppointment, Repair, RepairEstimate, EstimateLineItem, Invoice, InvoiceLineItem, PartsUsage |
| Reference and security policy | IndicatorValue, UserRolePolicy, DatabasePrincipal, RoleProcedurePermission, PrincipalDelegation |

These are 12 business tables and five durable metadata tables. `AuditLog` remains the append-only legacy/security-event log; versioning an audit log inside itself would duplicate evidence recursively. `OperationContext`, `TemporalWriteContext`, and migration/object-version bookkeeping are transient or administrative infrastructure, not business history sources. MySQL's native account/grant tables are outside this schema.

The temporal subsystem introduced by migration 005 and retained in version 006 consists of:

- 17 mirrored history tables, plus `TemporalEvent` and `TemporalWriteContext`: 19 tables, bringing the schema to 40 base tables.
- Three AFTER source-table triggers per source for insert/update/delete (51), three history-protection triggers per history table (51), and three event-directory protection triggers: **105 temporal triggers**.
- `sp_BeginTemporalEvent`, an internal writer/actor helper, and `sp_ListAuditTrail`, the read interface.
- `vw_AuditTrail`, a denormalized UNION ALL view over the event directory and all 17 history tables.

The complete current version-006 schema has **187 triggers: 105 temporal triggers plus 82 other business, generic-audit, domain, and provenance triggers**. This count is verified against the CREATE TRIGGER definitions in file 05 and the independent version-006 baseline inventory. Migration 006 replaces 133 existing triggers across the schema; those replacements do not add 133 to the total or introduce the temporal subsystem a second time.

Current definitions are organized as follows:

| Authoritative source | Temporal responsibility |
| --- | --- |
| [sql/01_schema.sql](../sql/01_schema.sql) | Final mirrored-history, `TemporalEvent`, and `TemporalWriteContext` tables, columns, primary keys, checks, and foreign-key definitions |
| [sql/02_indexes.sql](../sql/02_indexes.sql) | Temporal secondary indexes, including unique event links/current versions and event lookup keys |
| [sql/03_views_reports.sql](../sql/03_views_reports.sql) | `vw_AuditTrail` and its before/after payload projections |
| [sql/04_procedures.sql](../sql/04_procedures.sql) | `sp_BeginTemporalEvent`, identity helpers, paginated `sp_ListAuditTrail`, and standardized error/diagnostic handling |
| [sql/05_triggers_roles.sql](../sql/05_triggers_roles.sql) | All 187 current triggers, including the 105 temporal writers/guards in their deployed action order |
| [sql/06_sample_data.sql](../sql/06_sample_data.sql) | Fresh-install fixture loading and initial observed snapshots |
| [sql/07_tests.sql](../sql/07_tests.sql) | Current-schema fixture and snapshot assertions |
| [sql/08_demo_accounts.sql](../sql/08_demo_accounts.sql) | Optional native demo accounts/roles, including manager audit-reader grants |

[scripts/generate_temporal_history.py](../scripts/generate_temporal_history.py) is a historical development utility that reproduces migration 005 from its explicitly frozen version-004 column/key inventory. Neither a normal fresh build nor an upgrade runs that generator. Existing databases execute the checked-in migration only when 005 is pending; fresh installations execute the consolidated definitions instead.

The historical migration uses `CREATE TABLE ... SELECT ... WHERE FALSE` to copy column types, then adds metadata and indexes before populating snapshots. Consolidated file 01 declares the equivalent final table definitions directly; it does not run that historical CTAS sequence. In both paths, original generated discriminator columns become ordinary stored snapshot values. Source AUTO_INCREMENT, uniqueness, foreign keys, and generated expressions are deliberately not inherited: historical versions must repeat source keys and survive changes/deletions of their original references. See [MySQL CREATE TABLE ... SELECT](https://dev.mysql.com/doc/refman/8.4/en/create-table-select.html).

Never regenerate or edit an applied 005 migration or change its checksum. Future source-column changes need a new numbered migration that updates the matching history table, writer trigger, and read projections together; fresh and upgraded paths must remain equivalent. The current tests compare every source column's type/collation with its history counterpart. The recorded consolidated baseline and published migration checksums remain verification evidence, not values to rewrite to bypass a mismatch.

## Versions, validity, and initialization

In addition to the mirrored columns, each history table contains:

| Fields | Meaning |
| --- | --- |
| HistoryID, HistoryVersion | Surrogate primary key and increasing version number for the source key |
| HistoryValidFrom, HistoryValidTo | Half-open validity interval `[from, to)`; NULL end means current |
| HistoryRecordedAt, HistoryOrigin | Database observation time; Snapshot, Insert, or Update |
| HistoryUserID, HistorySessionAccount, HistoryContextID, HistoryReason | Verified opening actor/system/context and inventory reason where applicable |
| HistoryStartEventID, HistoryEndEventID | Links to the event that opened/closed this version |
| HistoryClosedByUserID, HistoryClosedBySession, HistoryClosedContextID, HistoryCloseReason, HistoryCloseOperation | Who closed the version, including deletion attribution |
| HistoryIsCurrent | Generated current marker used by the unique current-version index |

All history/event times use `DATETIME(6)`. Initial snapshot creation differs by installation path:

- **Historical upgrade through migration 005:** the migration creates its history tables and copies every existing source row into one current `Snapshot`, using `@history_snapshot_at = UTC_TIMESTAMP(6)` as the common observation time. It preserves the live business/provenance values. Snapshot inserts happen before the corresponding history guards/writers are installed.
- **Consolidated fresh installation:** file 01 creates the final tables and file 02 creates their secondary indexes. File 06 imports the tagged implementation's fictional initial state, including its original acceptance-check effects, then initializes one current `Snapshot` per mirrored source row using the fresh database's UTC observation time. File 05's final triggers are installed afterward. This controlled initialization is restricted to a new empty database; it adds no operational identity bypass.

In both cases, the initial row has `HistoryVersion = 1`, while `HistoryValidFrom`, opening actor/system/context, and start event remain NULL: the old/imported row's actual change history cannot be reconstructed from its current values. Business creation/approval/completion fields are copied unchanged, not reinterpreted as evidence of the installation actor. Initialization creates no fictional `TemporalEvent` or change row in the audit view.

`HistoryVersion` is a per-source-key row version, independent of the schema version recorded in `schema_object_versions`. Fresh version-006 installations preserve each object's historical last-change version and register migrations 001–006 as `covered`, not executed. A later `--migrate` never reruns file 06 or repeats snapshots for an already-applied migration 005; migration 006 preserves all existing history and events.

For changes after deployment:

1. INSERT creates version 1, or the next version when a deleted key is reused.
2. UPDATE locks the current history row, closes it at the new event time, and inserts its successor with the same boundary. Byte-sensitive comparisons capture case-only string changes and NULL changes. A no-op creates neither a version nor an event.
3. DELETE closes the current version, records its closing person/system/context/time, and retains the mirrored values. There is no replacement current version for a deleted record.

Current locking reads, source InnoDB row locks, a unique `(source key, HistoryVersion)` index, and a unique `(source key, HistoryIsCurrent)` index serialize updates and prevent duplicate current versions. If history is missing, the business mutation fails instead of silently reconstructing it. The internal clock resets caller `SET timestamp` overrides and uses UTC independently of caller time zone. If database clock resolution or a backward clock adjustment would yield a non-increasing boundary, the boundary advances one microsecond beyond the previous known boundary, including across key reuse. These are database-derived logical event times, not caller timestamps or transaction commit timestamps.

For known state at a point in time, use observation time as the earliest known bound for Snapshot rows:

```sql
SELECT * FROM CustomerHistory
WHERE CustomerID = 1
  AND COALESCE(HistoryValidFrom, HistoryRecordedAt) <= '2026-12-01 12:00:00.000000'
  AND (HistoryValidTo IS NULL OR HistoryValidTo > '2026-12-01 12:00:00.000000');
```

This query makes no claim about state before the first observation.

## Identity, atomicity, and protection

Ordinary people and service calls use `sp_ActorForWrite` and protected `OperationContext`, introduced at version 004 and now defined in [sql/04_procedures.sql](../sql/04_procedures.sql) and [sql/01_schema.sql](../sql/01_schema.sql). History records `USER()` separately from the verified person. Service delegation remains bounded by person/operation permissions. Caller `@app_user_id`, `@context_id`, and timestamp overrides cannot manufacture attribution. See [reference values and session identity](reference-and-identity.md).

The exact local physical maintenance logins `vsm_developer@localhost` and `vsm_admin@localhost` may change master/reference/security metadata under their existing native privileges. Their history has NULL person and actual system login; a supplied person/context variable is ignored. This is explicit system-only maintenance attribution, not the old fallback allowing any unregistered login to impersonate a person. Other unregistered accounts fail identity validation even if accidentally granted source-table DML. No account privileges or operational person mappings are added by the history migration.

`TemporalWriteContext` is a short-lived, per-connection/entity authorization row written inside the business trigger. History INSERT and closing UPDATE require this protected row; history DELETE always fails. Event UPDATE/DELETE always fail, and event INSERT also requires the protected maintenance context. No application role receives DML on histories, the event directory, or write context, or EXECUTE on the internal writer. Tests also grant history DML accidentally and verify that the guards still reject direct writes. Never grant application access to the protected context or internal writer.

The context, event, business row, and history changes all use InnoDB and the same statement/transaction. Temporal writer helpers never commit or start a transaction. A trigger failure rolls back the business statement's writes, including its temporal writes; rollback of a public procedure's owned business transaction also rolls back its history. The protected context is removed before a successful statement completes and cannot remain committed after normal trigger execution. See [MySQL trigger transaction behavior](https://dev.mysql.com/doc/refman/26.10/en/trigger-syntax.html).

Version 006's public business handlers capture original diagnostics, attempt rollback and a structured `Rejected` AuditLog write, and use bare `RESIGNAL`. Rejection logging is an attempt, not a durability guarantee: logger/storage failures and connection loss can prevent a row, and unknown commit outcomes require reconciliation. The audit reader's protected cleanup also preserves the original exception. History protection uses `VSM_HISTORY_WRITE_DENIED` (52008), missing-current-history failures use `VSM_HISTORY_INCONSISTENT` (59001), and invalid audit filters use `VSM_INVALID_AUDIT_QUERY` (51009). Native errors such as deadlocks retain their original diagnostics. See [standardized error handling](error-handling.md) for all classes, caller actions, rollback-outcome meanings, and remaining transaction-ownership limitations.

Native application roles retain their existing business entitlements. On a consolidated fresh build without demo provisioning, the separate `vsm_admin` connection grants SELECT on `vw_AuditTrail` and EXECUTE on `sp_ListAuditTrail` only to an existing `role_manager` User/Host pair with a table grant on `AuditLog` in the exact target database. A grant on another target table or on another database's AuditLog is insufficient for these audit permissions. Recipient selection uses the developer's existing metadata-column reads in [scripts/consolidated_baseline.py](../scripts/consolidated_baseline.py); admin authentication happens before creation/reset, and grants happen after object creation, before coverage is finalized. No roles/users are created by this conditional path. With `--with-demo-accounts`, file 08 separately creates the demo principals and their full grants, including the manager audit readers; collisions are refused rather than reused.

Fresh schema/fixture/assertion work, including all triggers and routines, runs as `vsm_developer` and preserves its definer. The admin connection performs native account/privilege operations, not the trigger DDL, and grants no temporary developer authority for this fresh temporal installation. Existing upgrades retain [scripts/migrate.py](../scripts/migrate.py)'s conditional migration-005 audit-reader step; separate historical routine-grant restoration in other migrations is described in [build accounts](build-accounts.md#immutable-migration-exceptions). Admin operations are logged; unrelated principals receive no grants. History integrity does not protect against a trusted schema owner deliberately dropping triggers or truncating tables with DDL; application roles have no such privileges.

## Denormalized read interface and pagination

`TemporalEvent` is a compact global event directory: event ID, entity/key, operation, changed attribute names, verified actor/system/context/time, and reason. It stores no before/after row payloads. `vw_AuditTrail` in [sql/03_views_reports.sql](../sql/03_views_reports.sql) obtains those payloads from opening/closing history rows, producing one row per successful event even when several attributes changed. Inserts have NULL PreviousValue; deletes have NULL NewValue. The paginated read procedure is defined in [sql/04_procedures.sql](../sql/04_procedures.sql).

The view and reader expose EventID, EntityType, RecordIdentifier, OperationType, ChangedAttributes, PreviousValue, NewValue, ResponsibleUserID, SessionAccount, EventTimestamp, ContextID, and Reason. Identifiers are canonical JSON primary-key objects, including composite keys; updates use the resulting key, deletes the old key. A primary-key rename is visible in the before/after payloads and closes the old key's current history. Queries spanning a rename should consider both keys.

```sql
-- Run as a manager with native audit-reader permissions, or the schema owner.
CALL sp_ListAuditTrail(
    'Part', JSON_OBJECT('PartID', 1), NULL,
    NULL, NULL, NULL, 50
);

-- Next page: use the smallest EventID returned on the preceding page.
CALL sp_ListAuditTrail('Part', JSON_OBJECT('PartID', 1), NULL,
                      NULL, NULL, 123, 50);

-- Filter by responsible person and UTC date range [from, to).
CALL sp_ListAuditTrail(NULL, NULL, 2,
    '2026-11-01 00:00:00', '2026-12-01 00:00:00', NULL, 50);
```

The parameters are entity, JSON record key, responsible person ID, inclusive UTC from, exclusive UTC to, exclusive before-EventID cursor, and page size (1–200). NULL omits a filter. The reader rejects unknown entities, invalid sizes, and reversed/empty date ranges. NULL person means no person filter, including system-only events; direct view queries can explicitly filter `ResponsibleUserID IS NULL`.

Ordering is deterministic `EventID DESC`, using an exclusive cursor rather than OFFSET. The reader first selects at most 200 indexed event IDs into a private temporary page, then fetches the corresponding old/new payloads through indexed history links for each entity. It does not materialize or sort the entire UNION view to serve a page. The temporary tables are removed on success and error, and the reader does not commit a caller's transaction. For a consistent multi-page export under concurrent commits, the caller can keep an InnoDB consistent-read transaction around all page calls; moving independent reads are not a commit-ordered snapshot, and rolled-back event IDs may leave gaps.

Each history table has six indexes: HistoryID PK, unique start/end event links, unique current and record/version keys, and validity bounds. The event directory has its EventID PK plus `(EntityType, RecordHash, EventID)`, `(EntityType, EventID)`, `(ResponsibleUserID, EventID)`, and `(EventTimestamp, EventID)` indexes. The protected context has a connection/entity PK. This is **108 temporal persistent indexes** (17 × 6 + 5 + 1), a subset of the complete schema's indexes. Their current primary-key definitions are in file 01 and secondary-key definitions in file 02. The record hash indexes long composite JSON keys, while equality also compares the complete identifier to avoid treating a hash match as identity.

Storage grows with every real change: one closed old version, one new mirrored row, and one small event-directory row for an update. Extra indexes and trigger work add write overhead. The regression suite checks indexed pagination over 300 generated events and concurrent writers; this is functional/index evidence, not a production-scale benchmark or retention policy. Use the paginated procedure for application reads; broad ad hoc scans of the full UNION view can be expensive.

## Existing generic log and limits

All old `AuditLog` rows, procedures, successful operational audit triggers, rejection handling, and append-only guards remain. Their successful event counts are unchanged. Master/reference/security changes are added to temporal history rather than emitting redundant new generic success rows. Part quantity reasons remain in the original generic log and the linked temporal event/versions. A stale inventory reason is not attached to an unrelated price-only event.

On historical databases, temporal capture begins with migration 005. On fresh consolidated databases it begins after initial fixture/snapshot loading and installation of the final triggers. Neither path invents changes before its observed snapshots or replaces incomplete prior history. Older generic events and Rejected/security events remain independently queryable in `AuditLog`; they are not unioned into the success-only temporal view, which would duplicate successes or claim rejected requests changed data.

Version 006 already implements a stable error taxonomy, caller/retry decision helpers, structured rejection diagnostics, and preservation of native failures. Master-data and durable reference/security-policy changes already have mirrored temporal coverage. Existing procedure entitlements and protected booking/completion APIs are also implemented; they are not generic workflow-transition metadata or a shared transition engine.

Genuinely outstanding work includes complete server security auditing for direct SQL/constraint/privilege rejections outside the public handlers, native CREATE USER/GRANT/REVOKE operations, trusted-owner DDL, and attempted attacks on history itself. Full procedure-only business mutations, transaction-ownership/rejection-durability redesign, a metadata-driven workflow engine/action discovery, GUI/service implementation, warehouse/ETL, retention/archival, and tamper-evident external storage remain separate work. The diagnostic helpers do not provide request deduplication or reconciliation for uncertain writes. See [remaining error-handling limitations](error-handling.md#remaining-limitations-and-next-work) and [remaining workflow work](reference-and-identity.md#remaining-workflow-work).

## Requirement coverage and verification

| Requirement/gap | Implementation | Executed regression coverage |
| --- | --- | --- |
| Master data, all part attributes, account roles, activation | Corresponding five master history tables and change attributes | `test_master_data_prices_stock_roles_and_activation_are_recorded` |
| Reference, login mappings, role policy, entitlements/delegation | Five metadata history tables; system-only maintenance attribution | `test_reference_and_identity_policy_insert_update_delete_are_all_covered`, maintenance-attribution test |
| Existing/current records and honest initialization | Historical upgrade snapshots and consolidated file-06 snapshots; unknown actor/from fields NULL | mirrored-snapshot, version-4 upgrade, and cross-path fixture tests |
| Insert, successive update, deletion, no-op, key reuse | AFTER triggers; current/version indexes; closure attribution | insert, successive-update, delete, no-op, and reused-key tests |
| Both identities, real clock, context | Current file-04 actor resolution; actual USER; UTC microseconds | insert-clock, delegated-completion, and unregistered-actor tests |
| Atomicity, concurrency | InnoDB, locking reads, protected maintenance context | rollback, injected-history-failure, late-procedure-failure, concurrent-update tests |
| Unauthorized history writes | Native permissions and history/event guards | accidental-DML-grant and unauthorized-reader tests |
| GUI audit foundation | Denormalized view; indexed, bounded keyset reader | view/payload/filter/page tests and 300-event index test |
| Standardized errors and native diagnostics | File-04 handlers/classifiers and file-05 stable error numbers | error-handling tests for history protection/consistency, audit filters, logger failure, lock timeout, and deadlocks |
| Existing business/audit data and behavior | Consolidated fresh definitions equivalent to the tagged schema; immutable historical upgrades; generic log preserved | version-4 upgrade, version-005-to-006 preservation, and tagged cross-path regressions |

Run the complete current suite or the temporal module alone from the repository root:

```bash
python3 -B -m unittest discover -s tests -v
python3 -B -m unittest discover -s tests -p test_temporal_history.py -v
```

[tests/test_temporal_history.py](../tests/test_temporal_history.py) contains 20 tests. The complete repository suite currently contains 125: 28 build tests, 14 account/binary-logging tests, 22 reference/identity tests, 20 temporal tests, 20 [error-handling tests](../tests/test_error_handling.py), and 21 [consolidation tests](../tests/test_consolidated_build.py). Current operational tests build the consolidated schema; selected build/account tests retain explicit legacy profiles to preserve historical acceptance coverage. Cross-path tests compare all 246 tracked objects, trigger order/definers, effective native permissions, native fixture JSON types, workflow results, and upgrades from versions 001–006. They include qualified existing roles, unrelated same-named roles, manager-specific audit qualification, collisions, and least-privilege execution.

Every server/account/database is private and disposable; root is used only for initial admin bootstrap and is then locked, and automated credential handling remains non-interactive. [scripts/generate_temporal_history.py](../scripts/generate_temporal_history.py)'s frozen table inventory is also used by the temporal tests, but its SQL generation is not an installation step. Local output under `logs/temporal-audit-regression-results.txt`, when retained, records the historical 84-test temporal milestone, not current version-006/full-suite evidence; logs are ignored by Git and are not guaranteed in a clean checkout. Use the commands above for current verification and [SQL consolidation](sql-consolidation.md#validation-result) for the recorded consolidated validation results.
