# Reference values, identity, and provenance

Schema versions 3 and 4 extend the existing model. Versions 1 and 2 and the baseline fingerprint file remain unchanged. Both new builds and upgrades apply the same ordered SQL migrations through `scripts/build.py` and `sql/build.sql`.

## What changed

The existing database already enforced its four lifecycles, logged operational changes, checked named-user impersonation at audit time, and restricted technician access through filtered views. This phase addresses the remaining domain-membership and provenance gaps without replacing those workflows:

- Domain membership now comes from `IndicatorValue`, rather than status/role CHECK lists or unrestricted repair-type text.
- Unregistered session accounts no longer inherit the ability to assert any person.
- Human identity must match the registered session, or an explicit service/person/operation delegation.
- New audit events record both the raw database login and the verified responsible person.
- Creator, approval, finalization, completion, and recording fields cannot be prefilled or reassigned outside their operations. Event timestamps come from the database.
- Technician-account links, required text, and appointment duration limits are enforced. Changing role policy cannot invalidate existing user profiles.

## Coded-domain inventory

`IndicatorValue(IndicatorName, ValueCode, Description, DisplayOrder)` has a composite primary key. Domain names are fixed by each consuming column, not supplied by the caller. Stored generated discriminator columns and foreign keys prevent cross-domain references, renaming used codes, or deleting used values. BEFORE triggers also check membership, including when a caller disables its session's foreign-key checks.

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
| `migration_status` | Catalog mirror of the migration protocol | applying, applied, failed |

The migration runner's existing status ENUM and internal boolean policy flags are fixed implementation protocols. Their semantics are not extensible dropdown choices; the history ENUM is intentionally unchanged. Adding an Indicator Value cannot add a new migration-runner state, authentication mechanism, permission, or lifecycle transition.

VINs, usernames, part numbers, entity IDs, vehicle makes/models, descriptions, monetary amounts, and dates are identifiers or open data, not finite coded domains. Numeric integrity constraints remain in place. Legacy unconstrained repair types and audit codes are registered without rewriting historical records. Dirty required fields or premature decision metadata cause an upgrade to fail for review, rather than being silently repaired.

## Dropdowns and reports

All application roles that already have access to this database receive EXECUTE on the generic reader:

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

The new value is immediately returned, and a repair using it passes the existing domain validator. No procedure, trigger, or GUI options need editing. Dropdowns should render `Description` and submit `ValueCode`.

`fn_IndicatorDescription(indicator, code)` reads the same metadata and renders an unknown code visibly as `[INVALID: code]`. Existing service-history and workload views retain their old columns and gain description columns. `vw_RepairReferenceLabels` provides decoded repair types and statuses. Updating a description updates these reports without changing stored codes. The technician's updatable repair view keeps its original columns and CHECK OPTION.

## Session identity and acting on behalf of a person

`DatabasePrincipal` maps the exact `USER()` string, including host, to either a Person/UserAccount or a Service. Existing local UserAccount logins are registered as people; this does not create database accounts. Other hosts need explicit administrator registration. `root`, other unmapped accounts, and wildcard-looking strings receive no operational identity fallback.

For a person, the existing actor-ID procedure parameter is an optional assertion: NULL derives the person from the session; a different ID is rejected. Direct operational writes also resolve the person from the session. `@app_user_id` is retained as a compatibility hint, checked before use; setting it cannot change identity.

For a service, the person ID is a delegation request. `PrincipalDelegation` must authorize that exact service, person, and operation. `RoleProcedurePermission` separately checks the person's entitlement to the requested existing procedure. A delegation cannot grant the service more authority than that person. `UserRolePolicy` verifies technician links and active technicians. These tables are administratively controlled and have no application DML grants.

The public procedures authenticate before accessing business resources. During their transactions, they insert a protected `OperationContext` row containing the connection, session login, person, procedure, and correlation ID. Triggers use that row, not caller variables. It is removed before commit and rolls back with failed business work; callers cannot write it or execute internal identity/audit helpers.

Native EXECUTE grants remain the outer permission gate. Disabling the native application role prevents entry. The procedures run with definer privileges to access their tables, so `CURRENT_USER()`/`CURRENT_ROLE()` inside them must not be mistaken for the original login/active roles. See [MySQL stored-object access control](https://dev.mysql.com/doc/refman/8.0/en/stored-objects-security.html). Routine grants are captured and restored when routines are replaced. Existing filtered technician views now also require the full registered session identity.

## Service setup example

This is administrator setup for a chosen disposable database. It is not run automatically by migrations and never reuses or changes an existing MySQL account. Replace database and credentials for the chosen environment.

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

Existing public-procedure rejection recording remains available; direct SQL/privilege rejections outside those procedures are not a complete server audit. Master-data and metadata-administration auditing remain separate work. Existing per-person direct table/view grants are preserved for current workflows; converting every mutation to procedures is a later change. The migration/DDL failure and manual-recovery contract in README still applies.

## Upgrade and verification

```bash
python3 scripts/build.py --mysql /usr/local/mysql/bin/mysql -u vsm_developer -p --admin-password \
    --database vsm_dev_example --migrate

python3 -B -m unittest discover -s tests -v
```

All automated tests start private MySQL servers with networking disabled. Root is used only to provision `vsm_admin` during startup and is then locked. Builds, migrations, SQL assertions, and data fixtures use `vsm_developer`; account/privilege changes use `vsm_admin`. See [account responsibilities and required privileges](build-accounts.md). These physical setup accounts have no operational person-identity fallback.

The tests exercise old build regressions, domain membership, live INSERT-driven dropdowns, human/service identity, native role gates, forged variables, provenance fields, database clocks, transactional rollback, and preservation of all original business columns. Fresh and upgraded schemas are compared using deployed object fingerprints. The baseline SQL acceptance suite remains unchanged and runs before upgrades; the new regression suite exercises the latest schema after upgrades.

## Remaining workflow work

Allowed values are now metadata; allowed transitions still use the existing database guards. Registering `Paid` as an invoice status, for example, does not permit Draft → Paid. Principle 4 still requires transition and per-role permission tables, a controlled transition entry point, and metadata-driven action discovery for the eventual GUI. Appointment/repair closing rules, final-state protection, and existing authorization must remain intact during that change. This phase deliberately adds no new lifecycle edges and does not implement that engine.
