# Reference values, identity, and provenance

**Current revision 007:** [Procedure-only operations](procedure-operations.md) adds 29 typed mutation interfaces and removes application table/writable-view DML. Its separately pinned child contract preserves exact v006 ancestry and all existing trigger/history definitions. The v006 installation/entitlement details below remain historical context where superseded by that guide. Current fresh builds require an admin principal-collision inspection and do not silently convert existing native grants; full role/demo provisioning remains optional. Revision 007 has 41 base tables (one additional administrative table), 276 tracked objects, 45 SQL assertions, and 170 Python tests. Applications must use clean connections without caller transactions; A2 detection remains deferred.

Versions 003 (indicator values), 004 (session identity and provenance), and 005 (temporal history) are historical development milestones. Their behavior, together with version 006's standardized errors, is now represented by the consolidated version-006 definitions in SQL files 01–08. Normal fresh installations use those current definitions through [scripts/build.py](../scripts/build.py) and [sql/build.sql](../sql/build.sql), without reading or executing migrations 001–006. See [SQL consolidation](sql-consolidation.md) for the phased build and baseline coverage records.

Historical migration scripts remain upgrade and compatibility resources for existing databases and legacy reproduction. Versions 001–002, all published migration checksums, and the original baseline fingerprint file remain unchanged. Existing upgrades execute only pending migrations; they do not reinstall the consolidated fixture or rebuild existing history.

The current schema includes the [temporal audit history](temporal-audit.md) introduced at version 005 for 12 business source tables and five durable reference/security policy tables. It reuses verified actors and protected procedure contexts; physical developer/admin metadata maintenance is attributed to its actual session with no invented person. `AuditLog` remains a separate generic/security log rather than a recursively versioned history source.

## Authoritative consolidated SQL sources

| Current source | Responsibility |
| --- | --- |
| [sql/01_schema.sql](../sql/01_schema.sql) | Indicator, identity, policy, context, audit, and mirrored-history table definitions; generated domain discriminators and foreign keys |
| [sql/02_indexes.sql](../sql/02_indexes.sql) | Secondary indexes, including temporal lookup and uniqueness indexes |
| [sql/03_views_reports.sql](../sql/03_views_reports.sql) | Reference labels, filtered technician views, reports, and `vw_AuditTrail` |
| [sql/04_procedures.sql](../sql/04_procedures.sql) | Indicator readers/validation, actor resolution, protected business procedures, audit writers/readers, and error classifiers |
| [sql/05_triggers_roles.sql](../sql/05_triggers_roles.sql) | Domain, provenance, lifecycle, role/ownership, audit, and temporal-history enforcement |
| [sql/06_sample_data.sql](../sql/06_sample_data.sql) | Required catalog/policy rows, fictional identity/business fixtures, and observed initial history snapshots |
| [sql/07_tests.sql](../sql/07_tests.sql) | Current-schema fixture/assertion checks |
| [sql/08_demo_accounts.sql](../sql/08_demo_accounts.sql) | Optional native demo roles/users, grants, role assignments, and default roles |

Use the runner rather than sourcing these files in numeric order: functions precede dependent views, and initial fixtures/snapshots are loaded before triggers. A normal fresh build records migrations 001–006 as `covered`, with NULL execution timestamps and explicit baseline provenance, while preserving each object's last-change version. Later pending migrations execute after that baseline.

## What changed

Before the historical reference/identity work, the database already enforced its four lifecycles, logged operational changes, checked named-user impersonation at audit time, and restricted technician access through filtered views. The following behavior introduced at versions 003–004 remains part of the current consolidated schema without replacing those workflows:

- Domain membership now comes from `IndicatorValue`, rather than status/role CHECK lists or unrestricted repair-type text.
- Unregistered session accounts no longer inherit the ability to assert any person.
- Human identity must match the registered session, or an explicit service/person/operation delegation.
- New audit events record both the raw database login and the verified responsible person.
- Creator, approval, finalization, completion, and recording fields cannot be prefilled or reassigned outside their operations. Event timestamps come from the database.
- Technician-account links, required text, and appointment duration limits are enforced. Changing role policy cannot invalidate existing user profiles.

## Coded-domain inventory

`IndicatorValue(IndicatorName, ValueCode, Description, DisplayOrder)` has a composite primary key in [sql/01_schema.sql](../sql/01_schema.sql); [sql/06_sample_data.sql](../sql/06_sample_data.sql) seeds the current catalog. Domain names are fixed by each consuming column, not supplied by the caller. Stored generated discriminator columns and foreign keys prevent cross-domain references, renaming used codes, or deleting used values. BEFORE triggers in [sql/05_triggers_roles.sql](../sql/05_triggers_roles.sql) also check membership, including when a caller disables its session's foreign-key checks.

| Indicator | Consumers | Initial values |
| --- | --- | --- |
| `appointment_status` | ServiceAppointment.Status | Scheduled, Checked In, In Progress, Completed, Cancelled, No Show |
| `repair_status` | Repair.Status | Open, In Progress, Completed, Cancelled |
| `estimate_status` | RepairEstimate.Status | Draft, Pending Approval, Approved, Rejected, Expired, Finalized |
| `invoice_status` | Invoice.Status | Draft, Finalized |
| `repair_type` | Repair.RepairType | Existing sample/demo/performance repair categories and distinct legacy categories |
| `user_role` | UserAccount, UserRolePolicy, RoleProcedurePermission | Service Advisor, Technician, Manager |
| `active_status` | Technician.ActiveStatus, Part.ActiveStatus | 0 (Inactive), 1 (Active) |
| `audit_action` | AuditLog.Action | Existing create/update/delete, lifecycle, inventory, reversal, and rejection actions; distinct legacy actions |
| `audit_entity` | AuditLog.AffectedEntity | Existing business entity names and distinct legacy entity names |
| `principal_type` | DatabasePrincipal.PrincipalType | Person, Service |
| `procedure_name` | Delegations, operation permissions, protected call context | sp_CreateServiceAppointment, sp_CompleteRepair |
| `migration_status` | Historical execution-state protocol; baseline coverage is separate bookkeeping | applying, applied, failed |

Migration statuses and internal boolean policy flags are fixed implementation protocols, not extensible dropdown choices. Historical metadata retains its `applying`/`applied`/`failed` status ENUM. Consolidated fresh-install metadata additionally supports `covered` with explicit baseline provenance; the `migration_status` indicator retains the historical execution-state vocabulary shown above. Adding an Indicator Value cannot add a new migration-runner state, authentication mechanism, permission, or lifecycle transition.

VINs, usernames, part numbers, entity IDs, vehicle makes/models, descriptions, monetary amounts, and dates are identifiers or open data, not finite coded domains. Numeric integrity constraints remain in place. The historical upgrade path registers legacy unconstrained repair types and audit codes without rewriting historical records. Dirty required fields or premature decision metadata cause that upgrade to fail for review, rather than being silently repaired; a fresh installation instead seeds the consolidated fixture/catalog.

## Dropdowns and reports

The generic reader is `sp_ListIndicatorValues` in [sql/04_procedures.sql](../sql/04_procedures.sql). On a fresh build without demo provisioning, each existing `role_service_advisor`, `role_technician`, or `role_manager` principal with any table grant on the exact target database receives EXECUTE on this reader. The qualification is not applied to arbitrary custom roles or same-named roles authorized only in another database.

Separately, an existing `role_manager` with a table grant on the target database's `AuditLog` receives SELECT on `vw_AuditTrail` and EXECUTE on `sp_ListAuditTrail`. A grant on another target table qualifies the manager only for the indicator reader; an AuditLog grant in another database does not qualify it for the target's audit readers. [scripts/consolidated_baseline.py](../scripts/consolidated_baseline.py) selects the recipients using the developer's existing metadata-column reads. The separate admin authenticates before creation/reset and applies the conditional grants after the objects exist, before baseline coverage is finalized. These rules reproduce the historical migration/runner behavior without executing their SQL.

Normal fresh builds create no native roles or logins. `--with-demo-accounts` optionally runs file 08 as admin to create the three roles, their complete grants, and the fictional demo users; existing demo names cause refusal rather than reuse. Seeded application policy/login mappings do not themselves create native privileges. Custom services require explicit provisioning, as in the example below. See [account and conditional-grant details](build-accounts.md#optional-demo-provisioning-and-existing-role-grants).

As a caller with the appropriate native EXECUTE grant:

```sql
CALL sp_ListIndicatorValues('repair_type');

-- Equivalent query for a service with appropriate read access:
SELECT IndicatorName, ValueCode, Description, DisplayOrder
FROM IndicatorValue
WHERE IndicatorName = 'repair_type'
ORDER BY DisplayOrder, ValueCode;
```

An administrator can add a classification value with one INSERT:

```sql
INSERT INTO IndicatorValue (IndicatorName, ValueCode, Description, DisplayOrder)
VALUES ('repair_type', 'Wheel Alignment', 'Wheel alignment and balancing', 25);

CALL sp_ListIndicatorValues('repair_type');
```

The new value is immediately returned, and a repair using it passes the existing domain validator. No procedure or trigger needs editing. Future application dropdowns should read this catalog, render `Description`, and submit `ValueCode`; a GUI is not implemented here.

`fn_IndicatorDescription(indicator, code)` in [sql/04_procedures.sql](../sql/04_procedures.sql) reads the same metadata and renders an unknown code visibly as `[INVALID: code]`. The service-history and workload views in [sql/03_views_reports.sql](../sql/03_views_reports.sql) retain their original columns and include description columns. `vw_RepairReferenceLabels` provides decoded repair types and statuses. Updating a description updates these reports without changing stored codes. The technician's updatable repair view keeps its original columns and CHECK OPTION.

## Session identity and acting on behalf of a person

`DatabasePrincipal` maps the exact `USER()` string, including host, to either a Person/UserAccount or a Service. The historical upgrade registered existing local UserAccount logins as people; the consolidated fixture seeds its fictional person mappings in [sql/06_sample_data.sql](../sql/06_sample_data.sql). Neither operation creates native database accounts. Other people/hosts and service identities need explicit administrator registration. `root`, other unmapped accounts, and wildcard-looking strings receive no operational identity fallback.

For a person, the existing actor-ID procedure parameter is an optional assertion: NULL derives the person from the session; a different ID is rejected. Direct operational writes also resolve the person from the session. `@app_user_id` is retained as a compatibility hint, checked before use; setting it cannot change identity.

For a service, the person ID is a delegation request. `PrincipalDelegation` must authorize that exact service, person, and operation. `RoleProcedurePermission` separately checks the person's entitlement to the requested existing procedure. A delegation cannot grant the service more authority than that person. `UserRolePolicy` verifies technician links and active technicians. These tables are administratively controlled and have no application DML grants.

Actor resolution (`sp_ResolveActor`, `sp_ActorForWrite`) and the public business procedures are defined in [sql/04_procedures.sql](../sql/04_procedures.sql). The public procedures authenticate before accessing business resources. During their transactions, they insert a protected `OperationContext` row containing the connection, session login, person, procedure, and correlation ID. Triggers use that row, not caller variables. It is removed before commit and rolls back with failed business work; callers cannot write it or execute internal identity/audit helpers.

Native EXECUTE grants remain the outer permission gate. Disabling the native application role prevents entry when that role is the caller's source of EXECUTE authority. The procedures run with definer privileges to access their tables, so `CURRENT_USER()`/`CURRENT_ROLE()` inside them must not be mistaken for the original login/active roles. See [MySQL stored-object access control](https://dev.mysql.com/doc/refman/8.0/en/stored-objects-security.html). Historical upgrades capture and restore native grants when replacing routines; consolidated fresh builds create the final routines once. The filtered technician views in [sql/03_views_reports.sql](../sql/03_views_reports.sql) require the full registered session identity.

## Service setup example

This is explicit administrator setup after installing a chosen disposable database. Neither fresh builds nor migrations run this example automatically, and it never reuses or changes an existing MySQL account. `vsm_admin` can perform the native account/grant operations and authorized schema writes; the service receives neither administrative privileges nor direct table writes. Replace database and credentials for the chosen environment.

```sql
CREATE USER 'shop_service'@'localhost' IDENTIFIED BY 'Replace-with-a-local-test-password';
CREATE ROLE 'shop_service_calls';
GRANT EXECUTE ON PROCEDURE vsm_dev_example.sp_CreateServiceAppointment TO 'shop_service_calls';
GRANT EXECUTE ON PROCEDURE vsm_dev_example.sp_CompleteRepair TO 'shop_service_calls';
GRANT EXECUTE ON PROCEDURE vsm_dev_example.sp_ListIndicatorValues TO 'shop_service_calls';
GRANT 'shop_service_calls' TO 'shop_service'@'localhost';
SET DEFAULT ROLE 'shop_service_calls' TO 'shop_service'@'localhost';

USE vsm_dev_example;
INSERT INTO DatabasePrincipal (SessionAccount, PrincipalType, UserID)
VALUES ('shop_service@localhost', 'Service', NULL);
INSERT INTO PrincipalDelegation (SessionAccount, UserID, ProcedureName) VALUES
    ('shop_service@localhost', 2, 'sp_CreateServiceAppointment'),
    ('shop_service@localhost', 3, 'sp_CompleteRepair');
```

The application service must authenticate its end user before selecting an authorized delegation. The database then bounds that request using its own mappings and the person's permissions. No web authentication, GUI, or unrestricted “set current user” endpoint is introduced. The service gets EXECUTE only, with no direct business-table, metadata, context-table, or audit-table writes.

## Provenance and historical records

- New creators must equal the responsible actor. The appointment creation timestamp comes from UTC_TIMESTAMP() and cannot be changed later.
- New Open repairs cannot carry completion metadata. Technicians complete through `sp_CompleteRepair`; the existing Manager override remains available, with assignment validation and a database-owned completion timestamp.
- Draft estimates/invoices cannot carry approval/finalization metadata. Approvers/finalizers must match the responsible actor; the event writes UTC_TIMESTAMP(), overriding supplied event times. Existing decision-field locks and final-total checks remain.
- Parts usage records the verified actor and database time; identity, parent, and recording fields cannot later be reassigned.
- New AuditLog rows carry `SessionAccount = USER()` plus the verified `UserID`. Trusted identity/audit code resets caller-writable `SET timestamp` overrides; new provenance event timestamps use the actual database clock in UTC, independent of the caller's time zone. Rejected requests can have a NULL person when no human identity was verified; the claimed ID stays in JSON. Existing append-only protections remain.
- Historical rows and their original business/provenance values are retained. Old audit `SessionAccount` values remain NULL because the original session cannot be reconstructed honestly.

The provenance and history guards are defined in [sql/05_triggers_roles.sql](../sql/05_triggers_roles.sql). Master-data and durable reference/security-policy changes already have temporal coverage through their mirrored histories and `TemporalEvent`; this is implemented behavior, not outstanding work. Fresh file 06 initializes observed snapshots without inventing prior actors, valid-from times, or temporal change events. Later writes record the actual session and verified person, or system-only attribution for the named physical maintenance accounts.

Public-procedure rejection recording remains available through file 04's diagnostic writer; see [error handling](error-handling.md). Direct SQL/privilege rejections outside those procedures, native account/grant administration, and trusted-owner DDL still do not constitute a complete server security audit. Existing per-person direct table/view grants are preserved for current workflows; converting every mutation to procedures is a later change. The migration/DDL failure and manual-recovery contract in [README](../README.md#adding-a-migration-and-recovering-failures) still applies.

## Upgrade and verification

Use an explicitly selected disposable server and authorize the exact database through the [account setup](build-accounts.md) first. These are separate fresh-install and existing-upgrade paths:

```bash
# Fresh empty schema: install consolidated version 006 from files 01–08.
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u vsm_developer -p --admin-password \
    --socket "$DEV_SOCKET" --database vsm_dev_example

# Existing historical schema: stop writes and retain backups/grants first.
# On an already-current consolidated schema this verifies history and is a no-op.
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u vsm_developer -p --admin-password \
    --socket "$DEV_SOCKET" --database vsm_dev_example --migrate

python3 -B -m unittest discover -s tests -v
```

`--build-profile legacy` reproduces older builds using frozen original files and the historical migration chain; fresh targets below 006 select it automatically. Keep migrations 001–006, [sql/migrations/baseline.json](../sql/migrations/baseline.json), and [sql/09_schema_migrations.sql](../sql/09_schema_migrations.sql) immutable. Migration 001 binds the latter two files' digests, and upgrades reject changed applied checksums, incomplete history, and deployed-object drift. Fresh consolidated coverage records do not fabricate historical execution timestamps or replace existing upgrade histories.

All automated tests start private MySQL servers with networking disabled. Root is used only to provision `vsm_admin` during startup and is then locked. Builds, migrations, SQL assertions, and data fixtures use `vsm_developer`; account/privilege changes use `vsm_admin`. See [account responsibilities and required privileges](build-accounts.md). These physical setup accounts have no operational person-identity fallback.

The tests exercise historical build regressions, domain membership, live INSERT-driven dropdowns, human/service identity, native role gates, forged variables, provenance fields, database clocks, transactional rollback, and preservation of all original business columns. Current operational regressions use consolidated builds; the archived baseline SQL acceptance suite remains unchanged and runs before upgrades in the legacy profile. [Consolidation regressions](../tests/test_consolidated_build.py) compare all 246 tracked objects against the tagged implementation, effective permissions with and without demo provisioning, qualified/unrelated existing roles, native fixture JSON types, workflow results, and upgrades from each historical version.

## Remaining workflow work

Allowed values are metadata, but allowed transition pairs and transition-specific role checks remain coded in the lifecycle guards in [sql/05_triggers_roles.sql](../sql/05_triggers_roles.sql). Registering `Paid` as an invoice status, for example, does not permit Draft → Paid. The current SQL contains no generic workflow-transition catalog, shared transition entry point, or available-action discovery interface for a GUI/service.

The genuinely outstanding workflow tasks are:

- Define metadata for allowed transitions and the roles permitted to perform each transition. `RoleProcedurePermission` already implements per-procedure entitlement; it is not a per-transition permission table.
- Add a shared, controlled transition entry point that enforces that metadata together with verified actors, ownership, and existing invariants. Booking and repair completion already have protected public procedures; the missing piece is a general transition interface, not the absence of controlled business operations.
- Expose available business actions from that metadata for a future GUI/service. The existing error caller-action function provides diagnostic/retry guidance, not workflow-action discovery.

Appointment/repair closing rules, final-state protection, current role authorization, provenance, and temporal history must remain intact during any such change. Consolidation adds no new lifecycle edges and does not implement a metadata-driven workflow engine. GUI/service implementation and complete server security auditing also remain separate work.
