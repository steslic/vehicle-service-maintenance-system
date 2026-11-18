# Temporal history and audit trail

Migration `005_temporal_history.sql` adds row-version history without changing migrations 001–004 or replacing the existing generic `AuditLog`. Fresh builds and upgrades use the same manifest and SQL. Stop application writes and take a backup before upgrading; migration locks serialize migration runners, not application traffic. The existing implicit-DDL-commit/manual-recovery contract still applies.

## Coverage and objects

Every source column is copied with its SQL type and collation. Each source table below has a corresponding `<Table>History` table:

| Category | Source tables |
| --- | --- |
| Master data | Customer, Vehicle, Technician, Part, UserAccount |
| Transactions | ServiceAppointment, Repair, RepairEstimate, EstimateLineItem, Invoice, InvoiceLineItem, PartsUsage |
| Reference and security policy | IndicatorValue, UserRolePolicy, DatabasePrincipal, RoleProcedurePermission, PrincipalDelegation |

These are 12 business tables and five durable metadata tables. `AuditLog` remains the append-only legacy/security-event log; versioning an audit log inside itself would duplicate evidence recursively. `OperationContext`, new `TemporalWriteContext`, and migration/object-version bookkeeping are transient or administrative infrastructure, not business history sources. MySQL's native account/grant tables are outside this schema.

The migration introduces:

- 17 mirrored history tables, plus `TemporalEvent` and `TemporalWriteContext`: 19 tables, bringing the schema to 40 base tables.
- Three AFTER business triggers per source for insert/update/delete, three history-protection triggers per history table, and three event-directory protection triggers: 105 triggers.
- `sp_BeginTemporalEvent`, an internal writer/actor helper, and `sp_ListAuditTrail`, the read interface.
- `vw_AuditTrail`, a denormalized UNION ALL view over the event directory and all 17 history tables.

`scripts/generate_temporal_history.py` generates the repeated DDL from the explicitly frozen version-4 column/key inventory. The checked-in SQL migration is the runtime input; no generator runs during a build or migration. `CREATE TABLE ... SELECT ... WHERE FALSE` copies column types; metadata and indexes are then added before the snapshot is populated. Original generated discriminator columns become ordinary stored snapshot values. Source AUTO_INCREMENT, uniqueness, foreign keys, and generated expressions are deliberately not inherited: historical versions must repeat keys and survive changes/deletions of their original references. See [MySQL CREATE TABLE ... SELECT](https://dev.mysql.com/doc/refman/8.4/en/create-table-select.html).

Never regenerate or edit an applied 005 migration. Future source-column changes need a new numbered migration that updates the matching history table, writer trigger, and read projections together. The current tests compare every source column's type/collation with its history counterpart.

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

All history/event times use `DATETIME(6)`. Existing records receive exactly one current Snapshot version. Its observation time is the migration's UTC database time, but `HistoryValidFrom`, opening actor/system/context, and start event remain NULL: the old record's actual creation/change history cannot be reconstructed from a current row. Existing business creation/approval/completion fields are copied unchanged, not reinterpreted as evidence of the migration's actor. Snapshot initialization creates no fictional change event in the GUI view.

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

Ordinary people and service calls reuse migration 004's `sp_ActorForWrite` and protected `OperationContext`. History records `USER()` separately from the verified person. Service delegation remains bounded by person/operation permissions. Caller `@app_user_id`, `@context_id`, and timestamp overrides cannot manufacture attribution.

The exact local physical maintenance logins `vsm_developer@localhost` and `vsm_admin@localhost` may change master/reference/security metadata under their existing native privileges. Their history has NULL person and actual system login; a supplied person/context variable is ignored. This is explicit system-only maintenance attribution, not the old fallback allowing any unregistered login to impersonate a person. Other unregistered accounts fail identity validation even if accidentally granted source-table DML. No account privileges or operational person mappings are added by the history migration.

`TemporalWriteContext` is a short-lived, per-connection/entity authorization row written inside the business trigger. History INSERT and closing UPDATE require this protected row; history DELETE always fails. Event UPDATE/DELETE always fail, and event INSERT also requires the protected maintenance context. No application role receives DML on histories, the event directory, or write context, or EXECUTE on the internal writer. Tests also grant history DML accidentally and verify that the guards still reject direct writes. Never grant application access to the protected context or internal writer.

The context, event, business row, and history changes all use InnoDB and the same statement/transaction. Writer helpers never commit or start a transaction. Failure at any stage rolls back the statement; a later procedure failure rolls back all its history as well. Existing public-procedure rejection handlers then retain their generic Rejected audit row. The protected context is removed before a successful statement completes and cannot remain committed after normal trigger execution. See [MySQL trigger transaction behavior](https://dev.mysql.com/doc/refman/26.10/en/trigger-syntax.html).

Native application roles retain their existing business entitlements. The separate `vsm_admin` connection grants SELECT on the audit view and EXECUTE on the reader only to an existing `role_manager` already granted access to `AuditLog` in the target database. Merely having a same-named role with a basic grant on another table does not make it an audit reader. The developer executes all migration SQL; no new developer grant authority or MySQL privileges are needed. This direct admin grant step is recorded in the build log. No accounts are created, passwords changed, or unrelated principals granted access. History integrity does not protect against a trusted schema owner deliberately dropping triggers or truncating tables with DDL; application roles have no such privileges.

## Denormalized read interface and pagination

`TemporalEvent` is a compact global event directory: event ID, entity/key, operation, changed attribute names, verified actor/system/context/time, and reason. It stores no before/after row payloads. `vw_AuditTrail` obtains those payloads from opening/closing history rows, producing one row per successful event even when several attributes changed. Inserts have NULL PreviousValue; deletes have NULL NewValue.

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

Each history table has six indexes: HistoryID PK, unique start/end event links, unique current and record/version keys, and validity bounds. The event directory has its EventID PK plus `(EntityType, RecordHash, EventID)`, `(EntityType, EventID)`, `(ResponsibleUserID, EventID)`, and `(EventTimestamp, EventID)` indexes. The protected context has a connection/entity PK. That is 108 new persistent indexes. The record hash indexes long composite JSON keys, while equality also compares the complete identifier to avoid treating a hash match as identity.

Storage grows with every real change: one closed old version, one new mirrored row, and one small event-directory row for an update. Extra indexes and trigger work add write overhead. The regression suite checks indexed pagination over 300 generated events and concurrent writers; this is functional/index evidence, not a production-scale benchmark or retention policy. Use the paginated procedure for application reads; broad ad hoc scans of the full UNION view can be expensive.

## Existing generic log and limits

All old `AuditLog` rows, procedures, successful operational audit triggers, rejection handling, and append-only guards remain. Their successful event counts are unchanged. Master/reference/security changes are added to temporal history rather than emitting redundant new generic success rows. Part quantity reasons remain in the original generic log and the linked temporal event/versions. A stale inventory reason is not attached to an unrelated price-only event.

Temporal events begin at migration 005 and do not pretend to replace incomplete pre-migration history. Older generic events and Rejected/security events remain independently queryable in `AuditLog`; they are not unioned into the success-only temporal view, which would duplicate successes or claim rejected requests changed data.

Direct SQL, constraint/privilege rejections outside the existing public procedures, native MySQL CREATE USER/GRANT/REVOKE operations, trusted-owner DDL, and attempted attacks on history itself are not a complete server security audit. Those require later server-level auditing or controlled administrative/mutation interfaces. Full procedure-only business mutations, transaction-contract redesign, error taxonomy, workflow metadata, GUI/service, warehouse/ETL, retention/archival, and tamper-evident external storage are not implemented here.

## Requirement coverage and verification

| Requirement/gap | Implementation | Executed regression coverage |
| --- | --- | --- |
| Master data, all part attributes, account roles, activation | Corresponding five master history tables and change attributes | `test_master_data_prices_stock_roles_and_activation_are_recorded` |
| Reference, login mappings, role policy, entitlements/delegation | Five metadata history tables; system-only maintenance attribution | `test_reference_and_identity_policy_insert_update_delete_are_all_covered`, maintenance-attribution test |
| Existing/current records and honest initialization | Mirrored Snapshot rows; unknown actor/from fields NULL | mirrored-snapshot and version-4 upgrade tests |
| Insert, successive update, deletion, no-op, key reuse | AFTER triggers; current/version indexes; closure attribution | insert, successive-update, delete, no-op, and reused-key tests |
| Both identities, real clock, context | Migration-004 actor resolution; actual USER; UTC microseconds | insert-clock, delegated-completion, and unregistered-actor tests |
| Atomicity, concurrency | InnoDB, locking reads, protected maintenance context | rollback, injected-history-failure, late-procedure-failure, concurrent-update tests |
| Unauthorized history writes | Native permissions and history/event guards | accidental-DML-grant and unauthorized-reader tests |
| GUI audit foundation | Denormalized view; indexed, bounded keyset reader | view/payload/filter/page tests and 300-event index test |
| Existing business/audit data and behavior | New migration only; generic log unchanged | version-4 upgrade test and all pre-existing regressions |

Run `python3 -B -m unittest discover -s tests -v`. The new test module has 20 tests, alongside the existing 64. Every server/account/database is private and disposable; root is used only for initial admin bootstrap, and all automated credential handling remains non-interactive. See retained output in `logs/temporal-audit-regression-results.txt` after the implementation verification run.
