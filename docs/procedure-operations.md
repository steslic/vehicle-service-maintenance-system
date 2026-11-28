# Procedure-only business operations (revision 007)

Revision 007 extends the consolidated v006 foundation with 29 typed stored procedures. The existing `sp_CreateServiceAppointment` and `sp_CompleteRepair` remain unchanged. The 31 business interfaces use verified actors, procedure entitlements, protected operation context, existing lifecycle/validation triggers, and the existing audit/history machinery. No dynamic SQL or caller-selected table/column interface is exposed.

## Operation inventory and entitlement decisions

A = Service Advisor, T = Technician, M = Manager. The previous capabilities below come from the executable v006 grants and TDD section 10; they describe native application access, not the developer's maintenance privileges. Every mutation now requires an authorized procedure. Existing SELECT/report and filtered-view access is retained.

| Entity | Previous permitted mutations | Roles | Existing public procedure | Added interface and rules | Native change |
| --- | --- | --- | --- | --- | --- |
| Customer | INSERT, UPDATE | A, M | None | `sp_CreateCustomer`, `sp_UpdateCustomer`; existing required fields, identity, history, and keys | Remove table INSERT/UPDATE |
| Vehicle | INSERT, UPDATE | A, M | None | `sp_CreateVehicle`, `sp_UpdateVehicle`; customer FK, VIN uniqueness, existing validation | Remove table INSERT/UPDATE |
| Technician | INSERT, UPDATE | M | None | `sp_CreateTechnician`, `sp_UpdateTechnician`; existing activation/profile checks | Remove table INSERT/UPDATE |
| Part | INSERT, UPDATE | M | None | `sp_CreatePart`, `sp_UpdatePart`, `sp_AdjustPartInventory`; nonnegative quantities/prices, activation, required inventory reason | Remove table INSERT/UPDATE |
| ServiceAppointment | INSERT through existing procedure; UPDATE | A, M | `sp_CreateServiceAppointment` | Existing booking; `sp_UpdateServiceAppointment` for details/reassignment/rescheduling; `sp_SetServiceAppointmentStatus` for lifecycle/cancellation. Existing overlap, final-state, actor, and open-repair checks remain | Remove table UPDATE; retain booking EXECUTE |
| Repair | INSERT | A, M | None | `sp_CreateRepair` starts Open and serializes against appointment closing | Remove table INSERT |
| Repair | UPDATE details | M | None | `sp_UpdateRepair`; closed records and provenance remain protected | Remove table UPDATE |
| Repair | Status UPDATE, through filtered view for T | T, M | None | `sp_SetRepairStatus`; T limited to assigned repair even on a no-op; T must use existing completion API to complete; M retains audited supervisor completion override | Remove table UPDATE and view UPDATE(Status) |
| Repair/PartsUsage/Part | Atomic completion, parts recording/deduction | T, M | `sp_CompleteRepair` | Existing `sp_CompleteRepair` unchanged; registered actor/delegation, technician ownership, stock validation, atomic history/audit | Keep authorized EXECUTE; no independent PartsUsage DML granted |
| RepairEstimate | INSERT, UPDATE | A, M | None | Create/update Draft data, submit, expire, finalize; manager decision through `sp_DecideRepairEstimate`. Existing transition/approval/total/final-state checks remain | Remove table INSERT/UPDATE |
| EstimateLineItem | INSERT, UPDATE, DELETE | A, M | None | Create/update/delete specific `(EstimateID, LineNumber)`; line total derived from quantity × unit price; parent locked and finalization protection preserved | Remove table INSERT/UPDATE/DELETE |
| Invoice | INSERT, UPDATE | A, M | None | Create/update/finalize; completed-appointment requirement, total checks, verified finalizer, final-state protection | Remove table INSERT/UPDATE |
| InvoiceLineItem | INSERT, UPDATE, DELETE | A, M | None | Create/update/delete specific line; derived total and parent finalization lock/protection | Remove table INSERT/UPDATE/DELETE |
| UserAccount/security/reference metadata | No native application writes | None | None | Remain administrative maintenance; no new application mutation APIs | No new application grants |
| AuditLog/history/context/event tables | No native application writes | None | None | Existing internal writers/triggers only | No new application grants |

Customer, vehicle, appointment, repair, part, technician, estimate, and invoice deletion were not granted in the executable v006 role policy and are not invented here. Parts-usage correction/reversal is also not exposed: despite broad FRD audit descriptions, v006 native roles could write parts usage only through completion. FR-11's actor list includes advisors, but the actual grant/TDD matrix gives them read-only parts access. Revision 007 preserves that narrower entitlement. Further business permissions require an explicit requirements decision.

## Procedure interfaces

Every new interface has a final `p_ActorUserID INT` parameter. Pass NULL for a registered human login; it is an optional assertion, never an identity source. A registered service must provide the person and have a matching `PrincipalDelegation` for that exact procedure, as well as native EXECUTE. `sp_ResolveActor` also checks that person's current `RoleProcedurePermission`. Native EXECUTE alone cannot bypass that metadata check.

Updates replace the listed editable fields; NULL is a real SQL NULL, not an implicit keep-existing marker. Keys and provenance fields are not editable. New APIs return their affected record ID (invoice-line creation also returns its parent ID; estimate-line creation returns its composite key). Existing booking/completion signatures and result columns are retained.

| Procedure | Parameters before final ActorUserID | Roles |
| --- | --- | --- |
| `sp_CreateCustomer` | `Name VARCHAR(100)`, `Phone VARCHAR(25)`, `Email VARCHAR(100)` | A, M |
| `sp_UpdateCustomer` | `CustomerID INT`, `Name VARCHAR(100)`, `Phone VARCHAR(25)`, `Email VARCHAR(100)` | A, M |
| `sp_CreateVehicle` | `CustomerID INT`, `VIN VARCHAR(17)`, `Make VARCHAR(50)`, `Model VARCHAR(50)`, `Year SMALLINT` | A, M |
| `sp_UpdateVehicle` | `VehicleID INT`, `CustomerID INT`, `VIN VARCHAR(17)`, `Make VARCHAR(50)`, `Model VARCHAR(50)`, `Year SMALLINT` | A, M |
| `sp_CreateTechnician` | `Name VARCHAR(100)`, `Phone VARCHAR(25)`, `Email VARCHAR(100)`, `ActiveStatus TINYINT` | M |
| `sp_UpdateTechnician` | `TechnicianID INT`, `Name VARCHAR(100)`, `Phone VARCHAR(25)`, `Email VARCHAR(100)`, `ActiveStatus TINYINT` | M |
| `sp_CreatePart` | `PartNumber VARCHAR(50)`, `PartName VARCHAR(100)`, `UnitCost DECIMAL(10,2)`, `UnitSellingPrice DECIMAL(10,2)`, `MinimumInventoryLevel INT`, `ActiveStatus TINYINT`, `QuantityOnHand INT` | M |
| `sp_UpdatePart` | `PartID INT`, `PartNumber VARCHAR(50)`, `PartName VARCHAR(100)`, `UnitCost DECIMAL(10,2)`, `UnitSellingPrice DECIMAL(10,2)`, `MinimumInventoryLevel INT`, `ActiveStatus TINYINT` | M |
| `sp_AdjustPartInventory` | `PartID INT`, `QuantityOnHand INT`, `Reason VARCHAR(500)` | M |
| `sp_UpdateServiceAppointment` | `AppointmentID INT`, `TechnicianID INT`, `AppointmentDateTime DATETIME`, `ServiceRequestDescription VARCHAR(500)`, `EstimatedDuration INT` | A, M |
| `sp_SetServiceAppointmentStatus` | `AppointmentID INT`, `Status VARCHAR(20)`, `CancellationReason VARCHAR(500)` | A, M |
| `sp_CreateRepair` | `AppointmentID INT`, `RepairDateTime DATETIME`, `RepairType VARCHAR(100)`, `RepairDescription VARCHAR(500)`, `LaborHours DECIMAL(5,2)` | A, M |
| `sp_UpdateRepair` | `RepairID INT`, `RepairDateTime DATETIME`, `RepairType VARCHAR(100)`, `RepairDescription VARCHAR(500)`, `LaborHours DECIMAL(5,2)` | M |
| `sp_SetRepairStatus` | `RepairID INT`, `Status VARCHAR(20)` | T, M |
| `sp_CreateRepairEstimate` | `AppointmentID INT`, `EstimateDate DATE`, `TotalAmount DECIMAL(10,2)` | A, M |
| `sp_UpdateRepairEstimate` | `EstimateID INT`, `EstimateDate DATE`, `TotalAmount DECIMAL(10,2)` | A, M |
| `sp_FinalizeRepairEstimate` | `EstimateID INT` | A, M |
| `sp_CreateInvoice` | `AppointmentID INT`, `InvoiceDate DATE`, `TotalAmount DECIMAL(10,2)` | A, M |
| `sp_UpdateInvoice` | `InvoiceID INT`, `InvoiceDate DATE`, `TotalAmount DECIMAL(10,2)` | A, M |
| `sp_FinalizeInvoice` | `InvoiceID INT` | A, M |
| `sp_SubmitRepairEstimate` | `EstimateID INT` | A, M |
| `sp_ExpireRepairEstimate` | `EstimateID INT` | A, M |
| `sp_DecideRepairEstimate` | `EstimateID INT`, `Decision VARCHAR(20)` | M |
| `sp_CreateEstimateLineItem` | `EstimateID INT`, `LineNumber INT`, `Description VARCHAR(500)`, `Quantity INT`, `UnitPrice DECIMAL(10,2)` | A, M |
| `sp_UpdateEstimateLineItem` | `EstimateID INT`, `LineNumber INT`, `Description VARCHAR(500)`, `Quantity INT`, `UnitPrice DECIMAL(10,2)` | A, M |
| `sp_DeleteEstimateLineItem` | `EstimateID INT`, `LineNumber INT` | A, M |
| `sp_CreateInvoiceLineItem` | `InvoiceID INT`, `Description VARCHAR(500)`, `Quantity INT`, `UnitPrice DECIMAL(10,2)` | A, M |
| `sp_UpdateInvoiceLineItem` | `InvoiceLineItemID INT`, `Description VARCHAR(500)`, `Quantity INT`, `UnitPrice DECIMAL(10,2)` | A, M |
| `sp_DeleteInvoiceLineItem` | `InvoiceLineItemID INT` | A, M |

`sp_DecideRepairEstimate` accepts only Approved or Rejected. `sp_FinalizeRepairEstimate` requires a previously approved estimate whose stored total matches its lines. `sp_FinalizeInvoice` likewise verifies its stored total; update that total through its typed API before finalizing. Parent locks serialize line mutation against finalization. Repair creation locks its appointment before the source trigger reads its status.

Manager `sp_SetRepairStatus(..., 'Completed', ...)` retains the previous direct supervisor override, including the assigned technician and verified manager audit identity. It does not invent parts usage or deduct stock; use `sp_CompleteRepair` when the operation includes inventory. Technician completion through the status API remains rejected by the unchanged trigger.

## Native privileges and provisioning

[sql/08_demo_accounts.sql](../sql/08_demo_accounts.sql) now provisions SELECT plus explicitly authorized EXECUTE. No business table or writable view receives INSERT, UPDATE, or DELETE; no application role receives administrative, audit/history/context-write, internal-writer EXECUTE, or grant-option authority. The exact native grant inventory is pinned and tested against expanded real-user `SHOW GRANTS`. The technician's two filtered views remain readable, with no writable-view escape.

Full native roles/demo-account creation remains optional (`--with-demo-accounts`). Named demo users and passwords are unchanged. New fresh builds require the separate admin for an existing `mysql.user(User,Host)` collision inspection before creation/reset, even without demos. The installer refuses existing fixture role/user names (including the fourth seeded person, `tech_carla`) rather than reusing principals whose global/schema/table/column grants it cannot safely convert. Same-named principals in other schemas are left untouched; refusal happens before DDL/reset. No new setup-account privileges were added. All schema, routine, view, trigger, fixture, assertion, and bookkeeping operations remain developer-owned.

Existing v006 role/database conversion is not automated. Reproduce v006 with the historical profile if needed; provision revision 007 on a new, explicitly scoped disposable instance/database with unused fixture principal names. Do not manually carry v006 direct-write grants into a revision-007 application deployment. Explicit service provisioning uses only the required EXECUTEs and per-person/per-operation delegation, as in [reference and identity](reference-and-identity.md).

## Transaction and error contract

Applications must call transaction-owning procedures on **clean connections**, with autocommit enabled, `completion_type=0`, and no active caller transaction. The application service must not wrap these calls in its own transaction. The existing A2 detection limitation is deliberately deferred: this revision adds no Performance Schema dependency, detection heuristic, or promise that a caller transaction will be refused. `START TRANSACTION` can commit caller-owned work if the integration contract is violated.

New interfaces resolve the actor, start their owned business transaction, install protected per-call context, execute their typed mutation, remove that context, and commit. On failure they capture original stacked diagnostics, roll back owned business changes, call the private `sp_TryRecordRejectedDiagnostic` helper to attempt the existing structured rejection logger in a separate explicitly owned transaction, and bare-RESIGNAL the original error. The helper has no application EXECUTE grant or role/delegation entitlement; its definition is pinned and checked for drift like every business API. Secondary logger/rollback failures cannot replace it. New transaction endings explicitly request no chaining/release. The two original business procedures retain their v006 transaction/diagnostic implementation.

The existing 37 identifiers retain their meaning. Current classifiers additionally recognize `VSM_RECORD_NOT_FOUND` (53007/45000, not_found; caller action `refresh_record`) for a missing target in a new interface. Native constraint, authorization, deadlock, and lock-timeout diagnostics remain native and use the existing classifier. Rejection logging remains best effort, and unknown commit outcomes still require reconciliation; this is not an autonomous-audit/idempotency redesign. See [error handling](error-handling.md).

## Versioning and verification

[006_baseline.json](../sql/consolidated/006_baseline.json) and its pin remain unchanged. [007_procedure_only.json](../sql/consolidated/007_procedure_only.json) is a separately pinned, explicit child: exactly two existing classifier functions change and 30 procedures are added (29 business interfaces and one private rejection-audit transaction helper). All other 244 v006 object fingerprints must match exactly, including all 187 triggers, six views, 38 application/history tables, all 11 original procedures (including the two reused business procedures), and two other functions. The current contract verifies **276 tracked objects**: 38 tables, six views, 41 procedures, four functions, and 187 triggers. These are revision-specific totals.

Fresh metadata gains `schema_revisions`, bringing base tables to 41 including three administrative tables. Migration rows 001–006 still say `covered`, reference the immutable v006 contract, and have NULL execution timestamps. Revision 007 is recorded independently as installed with its own contract, source SHA/dirty flag, and installation time; it does not pretend migration 007 executed. `schema_object_versions.revision_version` marks changed/new objects as 7. Existing historical `migration_version` values are retained; new procedures have NULL historical migration version instead of a fabricated migration origin.

The installer checks the complete current object inventory, exact initial procedure-entitlement rows, pinned fixture/metadata/assertion/role SQL inputs, and complete revision provenance. Missing/extra/changed objects, damaged contracts, failed SQL/assertions, or incomplete metadata fail closed. No runtime fingerprint is accepted as its own expected checksum. Administratively managed role/delegation data can still change after installation under the existing protected metadata rules; initial-seed checks are not a new ban on authorized metadata maintenance.

`--migrate` keeps historical 001–006 upgrades at v006; it does not install revision-007 business interfaces or convert native grants. On revision 007 it validates the separate revision/provenance and preserves existing non-destructive migration behavior. Revision numbers and historical migration numbers are separate namespaces. The synthetic additive-migration regression confirms a future SQL migration 007 can still execute once after a revision-007 fresh installation, with honest execution records.

## Regression coverage

Run from the repository root:

```bash
python3 -B -m unittest discover -s tests -v
python3 -B -m unittest discover -s tests -p test_procedure_operations.py -v
```

The suite contains 170 tests: the original 125 v006 regressions plus 45 current-revision tests. Original assertions are unchanged and run against the immutable merged v006 fixture (`839ff8efb1c72703589a86a2920b4d9db6f60646`); no old permission, workflow, error, temporal, upgrade, or consolidation assertion was deleted. Current equivalents exercise the typed API with real restricted accounts, every procedure/role gate, direct table and writable-view denial, effective SELECT/EXECUTE grants, actor spoofing, delegation, all retained business workflows, manager overrides, concurrent histories, native lock timeout, injected history/logger failure, and rollback/context cleanup.

[Database CI](../.github/workflows/database-ci.yml) runs the full suite for pull requests targeting `main`, pushes to `main`, and manual dispatches. It uses Python 3.14 and checksum-pinned MySQL Community Server 26.7.0 Linux binaries on Ubuntu 22.04. The checkout retains full history for the immutable v006 fixtures. Syntax and pinned-contract checks run before the suite; fresh builds, all 45 SQL assertions, object fingerprints, restricted-account behavior, and no-op migration checks run through the existing tests. Each test server uses a private temporary data directory and Unix socket with generated credentials; CI needs no repository database secrets or running system database service.

Build tests cover pinned v006 ancestry, the explicit v007 delta, no historical SQL on fresh builds, 45 SQL assertions, damaged contracts, altered old/new definitions, tampered policy/assertion inputs before reset, honest revision/object provenance, principal collisions/schema-level DML bypass refusal, current no-op verification, and retained historical/additive migration behavior. All servers/accounts/data are disposable; root is used only for initial private bootstrap and then locked. Existing user/production databases are not used.

## Initial procedure-only validation (before the readability refactor)

On 2026-11-23, the complete suite passed **163 tests, 0 failures, 0 skips**, in **236.102 seconds** on disposable MySQL Community Server 26.7.0 instances (macOS ARM64). The prior combined run also passed all 163 tests in 234.115 seconds; the focused current-revision run passed all 38 tests in 45.140 seconds.

An additional focused rerun of the current-installation test passed in 3.524 seconds, including explicit assertions for developer-owned routines/triggers and absence of developer grant authority. This is a rerun of an existing test, not a 164th unique test. Current fresh installations passed all **45 SQL assertions** and the independently pinned **275-object** contract. Restricted-user workflows, schema-level grant bypass refusal, collision/reset safety, rollback/history, and historical compatibility checks all passed. No product SQL/tooling changed during the final full-suite run.

The independent candidate comparison also verified exactly 244 unchanged v006 objects, 29 additions, and only the two declared classifier replacements. Every original SELECT grant was independently compared against the merged v006 policy and retained. Original classifier source differs only by the explicit 53007 extension. Historical migrations, legacy SQL, v006 contract, triggers, views, and indexes remain byte-for-byte unchanged.

## Procedure readability refactor

`sql/04_procedures.sql` remains the single 04 input in the existing 01–08 build. Its line count decreases from **3,530 to 3,263**. All 29 revision-007 business procedures use clearer local names and formatting. Their repeated audit-transaction block moves into one private, explicitly DEFINER helper that calls the unchanged `sp_RecordRejectedDiagnostic`. Each business procedure retains its own stacked diagnostic selection, rollback flags, commit-outcome tracking, session cleanup, and bare `RESIGNAL`. A local handler also preserves the original exception if the helper itself is unavailable.

The refactor removes 21 unused lock declarations, four assignment-only parent-key variables, and 29 audit-start flags from business procedures. `sp_UpdateServiceAppointment` reads its appointment ID and vehicle ID together while retaining the appointment/vehicle/technician lock sequence. Invoice-line update/delete retain their first child lock and parent lock/checks, then reuse the supplied line ID instead of selecting and locking the same child again. The audit record ID is still assigned only after parent checks, preserving missing-parent/finalized-parent diagnostic precedence and rejection payloads. Parent-status reads retain `FOR UPDATE` even when their unused primary-key output is removed.

The original 11 procedures, all original function definitions apart from the existing 53007 classifier extension, triggers, constraints, views, native role grants, initial entitlements, historical files, and immutable v006 contract remain unchanged. No file split, migration, generic dispatcher, new public interface, or A2 enforcement is introduced. New focused regressions cover partial logger writes and same-session reuse, an unavailable helper, pre-transaction actor rejection, invoice-line diagnostic/audit precedence, parent locking, a real deadlock through a current wrapper, and helper-definition drift. Existing restricted-account tests also deny direct calls to the new helper for every application role.

The revised verification fingerprints are derived offline from reviewed SQL bodies and captured original signatures/security/SQL-mode metadata. Normal builds still compare against the independently pinned contract; they never generate or accept a new expected fingerprint from the running database. The v006 parent contract and its pin remain unchanged, as do all 244 protected v006 object records, the two existing classifier fingerprints, input digests, grants, and entitlements. Only the 29 revision-007 business procedure fingerprints change, and the one explicitly allowed private helper is added.

Disposable test servers now explicitly default to UTC. The historical consolidation comparison normalizes runtime clocks using the current date; the original host-dependent default made its local date disagree with UTC audit clocks around the UTC/local date boundary. No historical test assertion, data comparison, or SQL definition is weakened or changed. The previously failing tagged-schema/data/security comparison passes with the UTC test setup.

On 2026-11-23, the final command `python3 -B -m unittest discover -s tests -v` passed **170 tests, 0 failures, 0 errors, 0 skips**, in **243.972 seconds** on disposable MySQL Community Server 26.7.0 instances. This includes all **125 preserved v006 regressions** and **45 revision-007 regressions**, including restricted-account security tests and seven added refactor regressions. Current fresh builds passed all **45 SQL assertions** and the independently pinned **276-object** contract. The v006 parent still verifies its original 246 objects. `git diff --check` also passed.

The initial complete run took 250.320 seconds and reported 41 failing subchecks in the one historical tagged-consolidation comparison because of the UTC/local-date mismatch described above. After setting the disposable servers to UTC, that unchanged comparison passed independently in 7.547 seconds, followed by the clean 170-test run. The refactored application SQL did not change between those complete runs.

## Branch review validation (2026-11-26)

The review run of `python3 -B -m unittest discover -s tests -v` passed **170 tests in 256.919 seconds**, with **0 failures, 0 errors, and 0 skips**: 125 preserved v006 regressions and 45 revision-007 tests. This includes real restricted-account permission checks, actor/delegation enforcement, transaction rollback, concurrent updates, native lock timeouts/deadlocks, temporal/audit preservation, best-effort rejection logging, and drift/provenance checks. No test was weakened or removed for this review.

An additional fresh build on a private disposable MySQL Community Server 26.7.0 instance passed all **45 SQL assertions** and independently matched the pinned **276-object** current contract. Existing-database `--migrate` verification passed without applying a migration or changing temporal-event/audit row counts. The immutable 246-object v006 parent contract, all 187 trigger definitions, historical migrations, and legacy SQL are unchanged. Python syntax checks and `git diff --check` passed. Build/test logs and generated credentials remain outside the committed change set.

## Pre-merge validation (2026-11-28)

`python3 -B -m unittest discover -s tests -v` passed **170 tests in 246.738 seconds**, with **0 failures, 0 errors, and 0 skips**, on disposable MySQL Community Server 26.7.0 instances. A separate fresh build from the committed feature source passed all **45 SQL assertions**, matched all **276 pinned object fingerprints**, and verified v006 ancestry, revision provenance, and initial procedure entitlements. A subsequent `--migrate` run applied no migrations and preserved row counts in `AuditLog`, `TemporalEvent`, and all 17 history tables. Both protected context tables were empty afterward. Python syntax, contract/input checksums, and `git diff --check` passed. Triggers, historical SQL, and the v006 contract remain unchanged.

The local sandbox prevented MySQL initialization; the successful database runs used the same unmodified harness outside that sandbox, with private temporary servers and generated credentials. Test logs, server files, and credentials are outside the committed change set.

## Remaining scope

The professor's thin-trigger requirement is **not completed by revision 007**. This PR is limited to procedure-only application entry points, authorization, native permissions, transaction/error handling, and their regression tests. Existing business rules and validations remain in the unchanged triggers, including `sql/05_triggers_roles.sql`. Moving workflow decisions from triggers into business procedures is known follow-up work for a separate feature branch and PR after this PR is merged. That work must preserve locking, errors, manager overrides, provenance, and audit/history behavior; it is not part of this branch's acceptance criteria.

No generic workflow-transition engine, GUI/action-discovery API, caller-transaction detector, autonomous/durable rejection audit, administrative user/policy-management API, new business deletion/reversal permissions, or automatic v006-to-revision-007 data/role conversion is introduced. Triggers and constraints still own lifecycle invariants. These limitations are explicit and must not be bypassed with direct application-table grants.

## Files changed

- [README.md](../README.md)
- [docs/FRD.md](FRD.md)
- [docs/build-accounts.md](build-accounts.md)
- [docs/error-handling.md](error-handling.md)
- [docs/procedure-operations.md](procedure-operations.md)
- [docs/reference-and-identity.md](reference-and-identity.md)
- [docs/sql-consolidation.md](sql-consolidation.md)
- [docs/tdd.md](tdd.md)
- [docs/temporal-audit.md](temporal-audit.md)
- [scripts/build.py](../scripts/build.py)
- [scripts/consolidated_baseline.py](../scripts/consolidated_baseline.py)
- [scripts/migrate.py](../scripts/migrate.py)
- [scripts/operation_contract.py](../scripts/operation_contract.py)
- [sql/01_schema.sql](../sql/01_schema.sql)
- [sql/04_procedures.sql](../sql/04_procedures.sql)
- [sql/06_sample_data.sql](../sql/06_sample_data.sql)
- [sql/07_tests.sql](../sql/07_tests.sql)
- [sql/08_demo_accounts.sql](../sql/08_demo_accounts.sql)
- [sql/build.sql](../sql/build.sql)
- [sql/consolidated/007_procedure_only.json](../sql/consolidated/007_procedure_only.json)
- [tests/mysql_test_support.py](../tests/mysql_test_support.py)
- [tests/test_build.py](../tests/test_build.py)
- [tests/test_build_accounts.py](../tests/test_build_accounts.py)
- [tests/test_consolidated_build.py](../tests/test_consolidated_build.py)
- [tests/test_error_handling.py](../tests/test_error_handling.py)
- [tests/test_procedure_operations.py](../tests/test_procedure_operations.py)
- [tests/test_reference_identity.py](../tests/test_reference_identity.py)
- [tests/test_temporal_history.py](../tests/test_temporal_history.py)
