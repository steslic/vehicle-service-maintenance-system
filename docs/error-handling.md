# Standardized database errors

The current error-handling definitions are in the consolidated SQL files [04_procedures.sql](../sql/04_procedures.sql) and [05_triggers_roles.sql](../sql/05_triggers_roles.sql). Clients use MySQL error numbers and SQLSTATE, not human-readable message matching. All previously valid workflows and public procedure parameters remain supported. Meaningful native MySQL errors are propagated unchanged.

## Current definitions and installation paths

| Current source | Error-handling responsibility |
| --- | --- |
| [sql/04_procedures.sql](../sql/04_procedures.sql) | `fn_ApplicationErrorID`, `fn_ErrorClass`, `fn_ErrorCallerAction`, public-procedure exception handlers, `sp_RecordRejectedDiagnostic`, the compatibility writer `sp_RecordRejectedAttempt`, and audit-reader cleanup |
| [sql/05_triggers_roles.sql](../sql/05_triggers_roles.sql) | Validation, authorization, provenance, and temporal-history protections that raise stable `MYSQL_ERRNO` values using `SIGNAL` |
| [sql/01_schema.sql](../sql/01_schema.sql) | The final `AuditLog` definition, including nullable diagnostic columns |

Fresh installations use consolidated files 01–08 through `scripts/build.py` and `sql/build.sql`. They install and verify the version-006 baseline directly; migrations 001–006 are historical upgrade/compatibility resources and are not read or executed on the normal fresh path. Covered versions have status `covered`, NULL `applied_at`, and explicit baseline provenance. Per-object last-change versions are preserved. Any later pending migrations run after this baseline. See [SQL consolidation](sql-consolidation.md) for the phased build order and verification contract.

Existing databases use `--migrate` to verify recorded history and apply only pending historical/later migrations. Migration [006_standardized_error_handling.sql](../sql/migrations/006_standardized_error_handling.sql) remains the immutable upgrade from version 005 to this error contract. Frozen files under `sql/legacy/v001/` support historical build reproduction; `--build-profile legacy` selects that path explicitly.

## Classification and caller actions

| Class | Meaning | Expected caller action |
| --- | --- | --- |
| `validation` | Invalid input, domain membership, or business data | Correct the input; do not retry unchanged input. |
| `forbidden` | Identity, entitlement, native privilege, or protected-write failure | Stop; authenticate/authorize correctly. Do not retry unchanged credentials or forge attribution. |
| `not_found` | Required business record absent | Refresh the record selection and tell the user what is missing. |
| `conflict` | Scheduling, lifecycle, financial, or related-state conflict | Refresh current business state and resolve the conflict before resubmitting. |
| `retryable` | Native deadlock or lock timeout | Retry the entire transaction only after confirmed full rollback and within the retry budget. |
| `warning` | Completed operation with a nonfatal condition | Accept the completed result and retain/display the warning; do not replay successful writes. |
| `critical` | Unexpected failure or inconsistent internal state | Stop and report the original diagnostics for investigation. Unknown transaction outcomes require reconciliation. |

The three deterministic `NO SQL` functions in [sql/04_procedures.sql](../sql/04_procedures.sql) are:

```sql
SELECT fn_ApplicationErrorID(51001);                 -- VSM_INVALID_APPOINTMENT
SELECT fn_ErrorClass(51001, '45000', FALSE);          -- validation
SELECT fn_ErrorCallerAction(1213, '40001', FALSE,
                           'rolled_back', 1);      -- retry_transaction
```

`fn_ApplicationErrorID(number)` returns NULL for native/unrecognized numbers. `fn_ErrorClass(number, sqlstate, is_warning)` classifies by explicit number/state/severity. Both missing inputs, or normal success 0/00000 without a warning, produce NULL rather than an invented failure. Unknown failures default to `critical`. `fn_ErrorCallerAction(number, sqlstate, is_warning, outcome, attempt)` is a conservative decision helper; it does not execute or retry a business operation.

These are developer/authorized diagnostic interfaces. Existing application roles receive no new function EXECUTE privileges. A future application adapter can implement the same published numeric contract locally; it should not need another database request after connection loss. Diagnostic functions and internal writers remain protected by the existing native privilege model.

## Stable identifiers

Fatal application errors use SQLSTATE `45000` with an explicit `MYSQL_ERRNO`. Numeric allocations are permanent. Multiple sites enforcing the same invariant share an identifier. Explanatory text may change or be localized without changing the wire contract.

| Number | Identifier | Class |
| --- | --- | --- |
| 51001 | `VSM_INVALID_APPOINTMENT` | validation |
| 51002 | `VSM_INVALID_INDICATOR` | validation |
| 51003 | `VSM_UNKNOWN_INDICATOR` | validation |
| 51004 | `VSM_REQUIRED_FIELD` | validation |
| 51005 | `VSM_INVALID_PROFILE` | validation |
| 51006 | `VSM_INVALID_PARTS_DOCUMENT` | validation |
| 51007 | `VSM_INVALID_PART_ITEM` | validation |
| 51008 | `VSM_PREMATURE_PROVENANCE` | validation |
| 51009 | `VSM_INVALID_AUDIT_QUERY` | validation |
| 51010 | `VSM_INVENTORY_REASON_REQUIRED` | validation |
| 52001 | `VSM_UNREGISTERED_SESSION` | forbidden |
| 52002 | `VSM_ACTOR_MISMATCH` | forbidden |
| 52003 | `VSM_LOGIN_MAPPING_MISMATCH` | forbidden |
| 52004 | `VSM_DELEGATION_DENIED` | forbidden |
| 52005 | `VSM_ACTOR_INACTIVE` | forbidden |
| 52006 | `VSM_OPERATION_DENIED` | forbidden |
| 52007 | `VSM_PROVENANCE_IMMUTABLE` | forbidden |
| 52008 | `VSM_HISTORY_WRITE_DENIED` | forbidden |
| 52009 | `VSM_AUDIT_IMMUTABLE` | forbidden |
| 52010 | `VSM_COMPLETION_ENTRY_REQUIRED` | forbidden |
| 53001 | `VSM_REPAIR_NOT_FOUND` | not_found |
| 53002 | `VSM_VEHICLE_NOT_FOUND` | not_found |
| 53003 | `VSM_TECHNICIAN_NOT_FOUND` | not_found |
| 53004 | `VSM_PART_NOT_FOUND` | not_found |
| 53005 | `VSM_CUSTOMER_NOT_FOUND` | not_found |
| 53006 | `VSM_USER_NOT_FOUND` | not_found |
| 54001 | `VSM_SCHEDULE_CONFLICT` | conflict |
| 54002 | `VSM_INVALID_TRANSITION` | conflict |
| 54003 | `VSM_FINAL_STATE_IMMUTABLE` | conflict |
| 54004 | `VSM_INSUFFICIENT_STOCK` | conflict |
| 54005 | `VSM_RELATED_STATE_CONFLICT` | conflict |
| 54006 | `VSM_ROLE_POLICY_CONFLICT` | conflict |
| 54007 | `VSM_FINANCIAL_TOTAL_CONFLICT` | conflict |
| 55001 | `VSM_NOTICE` | warning |
| 59001 | `VSM_HISTORY_INCONSISTENT` | critical |
| 59002 | `VSM_PARENT_INCONSISTENT` | critical |
| 59003 | `VSM_PRINCIPAL_INCONSISTENT` | critical |

`VSM_NOTICE` reserves a consistent nonfatal protocol using SQLSTATE `01000`. Neither the original migration nor consolidation introduces a new business warning or changed success behavior; a test-only procedure demonstrates a continuing warning handler. Future nonfatal notices must use a warning SQLSTATE and be treated as warnings by the client.

Native classifications include:

| Native numbers/state | Class |
| --- | --- |
| 1213 / 40001; 1205 / HY000 | retryable |
| 1044, 1045, 1142, 1143, 1227, 1370, 1698, 3118 | forbidden |
| 1062, 1169, 1451 | conflict |
| 1048, 1264, 1265, 1292, 1364, 1452, 3140, 3141, 3143, 3146, 3819; SQLSTATE class 22 or 23 | validation |
| Explicit warning severity or SQLSTATE class 01 | warning |
| Other failures | critical |

Explicit warning severity takes precedence. Some native conditions, such as 1292/22007, can be a warning or a fatal strict-mode error. Supply the connector's condition severity, a `SQLWARNING` handler result, or `SHOW WARNINGS` Level; do not infer severity solely from a numeric code or assume every warning uses SQLSTATE 01. Inspect warnings immediately after the operation, before another statement replaces their diagnostics. Native number/state/message are never rewritten to fit the classification.

## Rejection diagnostics and propagation

The consolidated `AuditLog` definition in [sql/01_schema.sql](../sql/01_schema.sql) includes six nullable diagnostic columns. Historical migration 006 adds these columns when upgrading a version-005 database:

| Column | Type | Meaning |
| --- | --- | --- |
| `ApplicationErrorID` | VARCHAR(64) | Stable symbolic identifier; NULL for native/unknown errors. |
| `ErrorClass` | VARCHAR(16) | Classification of the captured failure. |
| `ErrorSQLSTATE` | CHAR(5) | Original returned SQLSTATE. |
| `ErrorNumber` | INT | Original MYSQL_ERRNO. |
| `ErrorMessage` | TEXT | Original MESSAGE_TEXT, without a generic replacement. |
| `TransactionOutcome` | VARCHAR(16) | `rolled_back`, `not_started`, or `unknown` as observed by the public handler. |

On that upgrade, existing rows retain NULL in every new column. Fresh installations preserve the fictional imported audit records' unknown diagnostics rather than inventing them. Historical diagnostic values are never inferred from old message strings. Existing AuditLog JSON, temporal histories, event records, and person/session attribution remain intact.

In [sql/04_procedures.sql](../sql/04_procedures.sql), `sp_CreateServiceAppointment` and `sp_CompleteRepair` capture stacked diagnostics before rollback or cleanup, then pass them to the internal `sp_RecordRejectedDiagnostic`. That writer retains the existing verified attribution checks and rejection payload, separately recording USER() and the verified person. The original seven-argument `sp_RecordRejectedAttempt` remains in the same file for compatibility; it does not invent diagnostic fields.

MySQL can append warnings about temporary-table rollback after a native deadlock. The handlers scan the stacked conditions, ignoring success/no-data/warning SQLSTATE classes and native rollback-warning numbers 1196/1751/1752 when selecting the exception; they retain the last exception candidate, with condition 1 as a defensive fallback. This avoids recording temporary-table warning 1751 instead of the actual 1213 deadlock. The real concurrent public-procedure test compares all three saved diagnostic fields to the native client error. See [GET DIAGNOSTICS](https://dev.mysql.com/doc/refman/8.0/en/get-diagnostics.html) and the [native rollback warning definitions](https://dev.mysql.com/doc/mysql-errors/8.0/en/server-error-reference.html).

Rollback, temporary-table cleanup, and rejection logging are protected from secondary failures. Bare `RESIGNAL` rethrows the original exception; logger failures cannot replace it. If rollback raises an exception, no rejection commit is attempted, avoiding a commit of partial business work. The audit-reader cleanup is similarly protected. These protections do not guarantee that a rejection record can always be written.

```sql
SELECT AuditLogID, ApplicationErrorID, ErrorClass, ErrorSQLSTATE,
       ErrorNumber, ErrorMessage, TransactionOutcome, UserID, SessionAccount
FROM AuditLog
WHERE Action = 'Rejected'
ORDER BY AuditLogID DESC;
```

This query requires existing AuditLog read authority. Structured rejections are separate from `vw_AuditTrail`, which continues to report successful temporal changes.

## Retry, unknown outcomes, and warnings

`rolled_back` means the public handler successfully rolled back its owned business transaction before any commit attempt. `not_started` means its own transaction had not begun; it makes no claim about a caller's ambient transaction. A failed rollback or any exception after the main COMMIT was attempted leaves the outcome `unknown`, even if a later rollback succeeds. Native connection failures can prevent a response or audit record altogether.

The caller-action function applies these rules in order:

1. Missing/unrecognized/unknown outcome, SQLSTATE class 08, or connection errors 2006/2013/2055: `reconcile_outcome`. Do not automatically replay the operation.
2. Warning plus confirmed `completed`/`committed`: `accept_with_warning`.
3. Other diagnostics after confirmed `completed`/`committed`: `review_completed_result`; do not resubmit writes.
4. Retryable failure without `rolled_back`: `confirm_full_rollback`.
5. Retryable failure with confirmed rollback: valid attempts 1 and 2 yield `retry_transaction`; attempt 3 or later yields `stop_retry_budget`; missing/invalid attempts yield `review_retry_state`.
6. Permanent failures yield the class-specific action: `correct_input`, `stop_and_authorize`, `refresh_record`, `refresh_state`, or `stop_and_report`.

Future callers should count the original execution as attempt 1, use at most three total attempts, wait approximately 100 ms and 200 ms before attempts 2 and 3 with jitter and a 1-second delay cap, and re-execute the entire business transaction after reopening any broken connection. A lock timeout may roll back only the failing statement; the whole business transaction must be explicitly rolled back before retry. InnoDB deadlocks normally roll back the transaction. See [MySQL InnoDB error handling](https://dev.mysql.com/doc/refman/8.0/en/innodb-error-handling.html).

No production application retry loop, request deduplication architecture, or automatic outcome reconciliation is introduced here. The functions expose a contract for a future adapter and permit regression coverage now.

## Procedure examples

As an authorized registered advisor, an invalid duration produces error 51001/45000:

```sql
CALL sp_CreateServiceAppointment(1, 5, 1, NULL,
    TIMESTAMP(CURDATE() + INTERVAL 120 DAY, '08:00:00'), 'Oil change', 0);
```

The application should associate 51001 with `VSM_INVALID_APPOINTMENT`, show the explanation, and request corrected input. A missing customer is 53005/45000; a conflicting appointment is 54001/45000. A claimed actor different from the authenticated person is 52002/45000. A native missing EXECUTE grant remains 1370/42000 and may be rejected before any procedure handler executes.

An authorized technician completing a nonexistent repair receives 53001/45000:

```sql
CALL sp_CompleteRepair(999999, 1, NULL, NULL);
```

The caller refreshes the record selection rather than repeating the same request. A missing requested part has its own 53004 code; an existing inactive part remains a business-state conflict. Successful business responses and procedure parameters retain their existing format.

## Migration and account safety

Use the existing `scripts/build.py` entry point and `sql/build.sql` manifest. Follow [first-time setup](../README.md#build-from-the-repository) for the intended socket and schema authorization. Examples below assume those variables identify an isolated disposable server:

```bash
# Fresh database from consolidated 01–08; does not execute migrations 001–006.
# Existing schemas are refused without an explicit allowed development reset.
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql \
    --socket "$DEV_SOCKET" --database "$VSM_DATABASE" \
    -u vsm_developer -p --admin-user vsm_admin --admin-password

# Existing verified version-005 database: stop writes and retain backups first.
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql \
    --socket "$DEV_SOCKET" --database "$VSM_DATABASE" --migrate \
    -u vsm_developer -p --admin-user vsm_admin --admin-password
```

**Fresh consolidated installations.** All schema/fixture/assertion work, including the procedures in file 04 and triggers in file 05, runs as the schema-scoped `vsm_developer`. Objects are created once with their final definitions and developer definer; no historical DROP/recreation or routine-grant-restoration helper runs. `schema_object_versions` records the classifiers, writers, procedures, triggers, and AuditLog with their reference last-change versions, rather than marking every object as version 6.

Native role/account provisioning remains optional. With `--with-demo-accounts`, the separate `vsm_admin` connection executes file 08 to create the demo principals and their complete grants. Without that option, existing standard roles with a table grant on the exact target schema receive indicator-reader EXECUTE; a manager with a table grant on the target's AuditLog also receives SELECT on `vw_AuditTrail` and EXECUTE on `sp_ListAuditTrail`. These conditional grants create no principals, broaden no internal diagnostic-function access, and do not change trigger definers. Admin authentication occurs before creation/reset when needed; with no demo provisioning or qualifying roles, no admin connection is opened. See [account details](build-accounts.md#optional-demo-provisioning-and-existing-role-grants) for the exact qualification rules.

**Historical upgrades.** Migrations 001–006 and their checksums remain unchanged. Migration 006 alters only AuditLog's shape and object definitions; it does not update or delete preexisting data or rebuild temporal snapshots. It recreates six procedures and 133 triggers while preserving signatures, security type, native grants, and relative trigger ACTION_ORDER. The procedures are `sp_ListIndicatorValues`, `sp_ValidateIndicator`, `sp_ResolveActor`, `sp_CreateServiceAppointment`, `sp_CompleteRepair`, and `sp_ListAuditTrail`. The internal temporal writer remains unchanged; its protection triggers receive stable numbers. Changed objects advance to version 6; unchanged objects retain their prior versions.

That migration SQL runs as developer. During the six-procedure grant-restoration call only, the separate admin grants temporary routine-scoped EXECUTE/ALTER ROUTINE grant authority to the developer, then restores prior rights. This historical exception adds no permanent developer privileges or global/schema GRANT OPTION and does not connect as root. It does not apply to consolidated fresh installations. See [historical migration exceptions](build-accounts.md#immutable-migration-exceptions).

Keep `sql/migrations/baseline.json` and `sql/09_schema_migrations.sql` unchanged as well: migration 001 binds their digests. Existing-database verification continues to reject changed applied checksums, incomplete histories, and deployed-object drift. `--migrate` never reloads sample data or executes installation SQL assertions or workflow tests.

For historical upgrades, stop application writes and retain a verified pre-upgrade database backup **and native routine-grant inventory**. DDL implicitly commits. A killed connection can lose the temporary native-grant snapshot after DROP PROCEDURE removed those grants; restoring the database alone is insufficient unless original grants are restored too. A failed/interrupted migration is recorded as `failed`/`applying` and blocks replay. Inspect actual DDL and temporary authority, restore the verified database and native grants, then rerun. Never clear failure history, edit applied checksums, or force a partial migration to look successful. A failed consolidated fresh installation likewise retains incomplete baseline metadata; assertions, grants, and fingerprint verification must succeed before coverage is finalized.

## Extending the contract

`scripts/error_contract.py` explicitly allocates the 37 identifiers. Its legacy message map is used only by the offline generator to locate frozen version-005 SIGNAL sites. Neither database runtime classification nor caller decisions match message text. There is no mutable persistent classification catalog, so no new reference table or temporal history is needed for this protocol metadata. Migration checksums, source control, and database object versions track changes.

For future procedures/triggers:

- Reuse a stable identifier for an existing invariant; allocate a new unused number for a distinct invariant. Never renumber or recycle a published code.
- Use `SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = <stable number>, MESSAGE_TEXT = <explanation>` for a fatal business error. Use a warning SQLSTATE for an intentional nonfatal notice.
- Retain meaningful native numbers and states. Capture stacked diagnostics before cleanup and propagate with bare `RESIGNAL` rather than replacing a native error with a generic one.
- Add any new classifier cases, grant restoration, and regression coverage through a new numbered migration. Verify that fresh installations and upgraded databases reach the same schema and error behavior. Define transaction ownership and audit durability explicitly before adopting a new rejection handler.
- Do not regenerate an applied migration. `scripts/generate_standardized_errors.py` reads frozen legacy/migration inputs to reproduce migration 006 for review. Fresh builds use the checked-in consolidated definitions; historical upgrades use the checked-in migration. Neither path runs the generator.

## Regression coverage

Run `python3 -B -m unittest discover -s tests -v`. The original 104 tests and 21 consolidation regressions use private disposable MySQL instances and generated credentials without prompts. The existing 84 build/account/reference/identity/temporal tests are preserved, with current-version application assertions changed to numeric codes. Historical acceptance SQL is preserved byte-for-byte under `sql/legacy/v001/`; migrations remain untouched. Fresh installs use current-schema assertions and the consolidated definitions. See [SQL consolidation](sql-consolidation.md).

The 20 tests in `tests/test_error_handling.py` cover all seven classes and every allocated identifier; invalid input; forbidden actor/native access; missing records; scheduling and lifecycle conflicts; indicator/audit-query validation; temporal protections and missing-history consistency; independence from message text; native constraint preservation; secondary logger failure; failed-completion rollback; missing parts; real lock timeouts and two real deadlock scenarios; exact wire/audit diagnostics; bounded retry and unknown outcomes; successful warning continuation; upgrades preserving all 38 existing data/history/security tables (the two migration bookkeeping tables intentionally advance); and native grant/security/signature/trigger-order preservation. Existing migration tests verify checksum integrity, repeat execution, clean builds, failure states, and source/log provenance.

The upgrade fixture creates pre-upgrade insert/update/delete history, including closed versions and events, and an existing rejection row. It compares every preexisting column of every table apart from the two migration bookkeeping tables before/after upgrading; binary history hashes are compared as hex. New diagnostic columns on legacy rows must remain NULL. The native grant fixture includes EXECUTE, ALTER ROUTINE, and existing recipient grant options, and verifies developer grant authority is removed.

The consolidation tests independently compare all 246 tracked objects against `pre-consolidation-2026-11`, along with effective grants, developer-owned object definers, fixture/native JSON data, workflow results, and upgrade compatibility. They also cover conditional readers for existing qualified roles without demo provisioning and rejection of grants to unrelated same-named roles. The same error taxonomy and transaction limitations apply to both installation paths.

## Remaining limitations and next work

- Rejection durability is unchanged in scope. The two public business handlers attempt rejection logging, but native privilege failures, rejected direct SQL, disconnected clients, logger/storage failures, and other paths can lack a durable rejection row. Secondary failures preserve the original client error without inventing a successful audit write.
- Public procedures still own their transaction. `START TRANSACTION` can commit an ambient caller transaction; failures before it begins can leave rejection writes inside that caller's transaction. `not_started` does not certify that transaction's outcome. Callers should invoke these procedures with no pending ambient transaction. Savepoint/ownership redesign is deferred.
- Unknown outcomes require reconciliation; there is no general idempotency key or safe automatic retry of an uncertain non-idempotent operation. No live commit-network-loss experiment is used to claim certainty: regression tests verify the conservative decision contract, and real engine tests verify known rollback cases.
- Trusted schema owners retain their existing DDL powers. Server-level administrative/security auditing and full rejection coverage require later work.

The next implementation step should establish an explicit transaction-ownership contract, then durable rejection-audit boundaries for every supported entry point using the diagnostic fields introduced here. Keep the existing identities and temporal provenance rules throughout that work.
