# Consolidated SQL installation and historical upgrades

The reference is commit `71696139e84a4e9b69f4baa6f89a6a8d20505561`, tagged `pre-consolidation-2026-11`. Consolidation changes installation sources and bookkeeping. It does not introduce a new business schema version or change transaction ownership/rejection durability.

## Authoritative files and execution phases

`sql/01_schema.sql` through `sql/08_demo_accounts.sql` are the current fresh-installation sources. `scripts/build.py` remains the entry point. `sql/build.sql` declares the ordered current files and a historical migration registry; registry entries are not fresh-build instructions.

1. Validate the manifest, all selected inputs and the pinned baseline contract before database creation/reset.
2. Check the server environment, optional demo-account collisions, and existing target-scoped role recipients. Authenticate the separate admin before any creation/reset when conditional grants are needed; acquire the same per-database advisory lock used by upgrades.
3. Run file 01's guarded database/metadata prefix. Commit six incomplete `applying` baseline records before application DDL.
4. Create the application tables from file 01. Create every secondary index from file 02 in the reference's key order, then apply file 01's foreign keys. This preserves constraint/index names, column order, and `SHOW CREATE TABLE` fingerprints without disabling integrity checks for the data load.
5. Create file 04's 11 procedures and four functions, then file 03's six views and original report queries. The reporting views require the indicator-description function.
6. Load file 06's fictional initial state and 17 observed history snapshots before installing triggers. This phase is limited to a new empty database, never an existing database upgrade.
7. Install all 187 triggers from file 05 in deployed action order. File 08 optionally creates native accounts and final grants through the separate admin connection.
8. Execute file 07's 41 current-schema/fixture assertions. For a build without demo provisioning, restore qualified existing roles' conditional reader grants through the admin connection. Verify all 246 tracked objects against the independent contract, then atomically register object versions and finalize coverage.
9. Execute pending migrations above version 006, if present. Original migrations 001–006 are never read or executed on the normal fresh path.

The tables are the original 13 business/audit tables, six reference/security/context tables, 19 temporal tables, and two bookkeeping tables. The 246 tracked objects exclude the two bookkeeping tables: 38 tables + 6 views + 11 procedures + 4 functions + 187 triggers.

## Honest baseline coverage

Fresh file 01 extends only `schema_migrations` bookkeeping: its status ENUM adds `covered`, and it gains nullable `baseline_version`, `baseline_checksum`, and `covered_at` columns. The published `sql/09_schema_migrations.sql` is unchanged. Existing historical databases retain their old metadata layout and rows.

| History record | status | applied_at | Baseline fields |
| --- | --- | --- | --- |
| Executed original migration | applied | Actual successful execution time | Absent on old layouts, otherwise NULL |
| Incomplete consolidated install | applying or failed | NULL | Baseline version/checksum present; no coverage time |
| Verified consolidated coverage, 001–006 | covered | NULL | Version 6, contract digest, actual coverage time |
| Future executed migration, 007 onward | applied | Actual successful execution time | NULL |

Historical filenames and checksums in covered rows identify the changes represented by the baseline, not files executed by the installer. Source SHA/dirty status refer to the actual installing checkout; they do not impersonate the reference commit. Logs explicitly say COVERED, not executed. `IndicatorValue.migration_status` retains the original execution-state vocabulary; baseline coverage is separate administrative bookkeeping, not an added application domain value.

`scripts/consolidated_baseline.py` pins the digest of `sql/consolidated/006_baseline.json`. That artifact contains independently captured checkpoint fingerprints and each object's last-change version, plus original migration digests. Fresh object records retain those individual versions; they are not all relabeled 006. Neither kind of metadata table is included in business-object fingerprints, so its intentional bookkeeping difference is documented and tested separately.

The migration reader validates a complete six-row coverage prefix, its contract checksum, coverage timestamps, and NULL execution timestamps before accepting it. Relabeling some or all covered rows as applied is rejected. Incomplete installs, missing rows, changed historical checksums, deployed object drift, and downgrades fail closed. There is no automatic adoption of an unversioned version-006 schema.

## Seed and historical evidence

The old sample and acceptance scripts switched human actors on a developer connection. Current identity validation correctly forbids that behavior. The consolidated fixture therefore imports the tagged build's final fictional state before trigger installation, preserving original acceptance-check effects, IDs, amounts, inventory, statuses, audit payloads, and unknown historical attribution. It does not add an identity bypass or weaken a trigger.

Historical dates stay historical; runtime-relative fixture dates remain relative to `CURDATE()`, and observed runtime timestamps use the current database clock. Original random fixture correlation IDs remain fictional fixture values. Audit JSON retains numeric decimal types/scales and native DATE/DATETIME types via explicit casts. DATE_ADD on a user variable is explicitly cast as DATETIME before JSON construction, since its otherwise identical text can be stored as a JSON string. Fresh initial snapshots have one version per source row, unknown opening actor/valid-from/context, and no invented temporal events. Empty histories begin with the same ID allocation behavior as migration 005.

File 07 now asserts the final state without changing business rows. The original 66 SQL workflow checks remain byte-for-byte in `sql/legacy/v001/07_tests.sql` and execute during legacy regression builds. Current business workflows, permissions, identity, errors, and temporal behavior continue to be tested using real registered users/services in the Python suite. Fixture import is not a substitute for those workflow tests.

## Reproduction and upgrades

Commands assume a separately provisioned disposable server, selected explicitly by its Unix socket:

```bash
# Default: consolidated 006. Admin is needed only for demo provisioning or qualified existing roles.
python3 scripts/build.py --socket "$DEV_SOCKET" --database vsm_dev_current -p

# Original ordered implementation, through the same schema version.
python3 scripts/build.py --socket "$DEV_SOCKET" --database vsm_dev_legacy -p \
    --build-profile legacy --target-version 6 --admin-password

# Older targets automatically use the frozen legacy files.
python3 scripts/build.py --socket "$DEV_SOCKET" --database vsm_dev_upgrade -p --target-version 2

# Existing databases: validate history, then execute only pending original migrations.
python3 scripts/build.py --socket "$DEV_SOCKET" --database vsm_dev_upgrade -p --migrate --admin-password
```

The archived files under `sql/legacy/v001/` are exact checkpoint copies, not generated versions of the new SQL. `sql/migrations/001`–`006`, `sql/migrations/baseline.json`, and `sql/09_schema_migrations.sql` retain their published bytes. Legacy builds and upgrades still use them, including scoped native-grant restoration. `--migrate --baseline` retains the original version-001 adoption checks. Existing upgrades never load consolidated fixtures or recreate history snapshots.

File 08 directly contains the final reference-reader grants for all application roles and manager audit-reader grants. Without demo provisioning, the installer separately reproduces migration 003's target-table-grant qualification and the migration-005 runner's target-AuditLog qualification for roles that already exist. Role/host identity and the exact target schema are retained; unrelated same-named roles receive no new rights. Grants are issued by the admin after object creation, before baseline coverage is finalized. Normal builds still create no native application roles or demo users, and need no admin if no roles qualify. Existing upgrades retain the original conditional manager qualification and temporary routine grant mechanisms. There are no new global/schema grant options or application history/context write privileges. All schema objects retain the developer definer and existing security type.

The offline error generator now reads frozen legacy procedure/trigger inputs; both historical generators still reproduce their migrations exactly. Normal builds never invoke generators.

## Verification and review

Run `python3 -B -m unittest discover -s tests -v` on an environment that allows private MySQL startup. The suite retains all original 104 Python tests and adds 21 consolidation tests. Build/account tests preserve their original assertions through explicit legacy profiles; current identity, temporal and error modules exercise consolidated installs.

Cross-path tests independently extract the tagged Git commit into a temporary checkout and build it on a private server. They compare all 246 fingerprints, per-object versions, trigger order/definers/security types, and expanded native role grants (including column/routine privileges). Every column of every non-bookkeeping table is compared before and after the same appointment/repair/parts workflow, including the returned IDs. Across independent executions only runtime clock values and randomly chosen correlation UUIDs are canonicalized; UUID equality/grouping remains checked. Business dates, decimal scales, audit payload structure, actor fields and NULL provenance remain compared. JSON_TYPE is independently compared at every stored audit JSON path, both before and after the workflow, so native dates/decimals cannot be silently replaced by strings/doubles.

The upgrade matrix covers every tagged version 001–006 with before/after comparisons of every preexisting table column. A synthetic test-only migration 007 is applied once to both install paths and produces identical schemas. Other gates cover missing historical files on the fresh path, clean-checkout provenance, damaged contracts, invalid final routines, false coverage, manifest order, missing inputs before reset, SQL/assertion failure, no-op upgrades, deployed drift, and killed installations.

The intended schema difference is confined to fresh-installation migration bookkeeping. The 246 tracked object fingerprints, reference data, final native permissions and business behavior must have no unexplained differences. No historical tag or checksum is changed.

DDL implicitly commits, so partial installs require inspection and explicit reset of an authorized disposable database. The runner preserves incomplete metadata and does not silently replay or delete partial work. Optional demo principals can remain if a later fresh-build step fails; account creation is server-scoped and not transactional. Existing transaction-ownership, rejection-audit durability, trusted-owner DDL powers, and server-level auditing limitations remain unchanged.

## Validation result

On 2026-11-22, the initial consolidation run passed all 119 Python tests in 176.007 seconds on MySQL Community Server 26.7.0 (macOS ARM64), using disposable servers exclusively. This includes all original 104 tests and 15 consolidation regressions, with the strengthened native audit-JSON type comparison. Fresh SQL assertions report 41 PASS; the original 66 checks remain exercised in demo-enabled legacy builds.

Incremental validation found and resolved history AUTO_INCREMENT initialization, JSON decimal-scale preservation, and JSON DATE/DATETIME representation differences before the final run. No tracked-object, security, fixture, workflow, or upgrade equivalence failures remain. One whitespace-only blank line inherited from the fingerprinted migration-006 routine body remains in file 04; `git diff --check` reports it. The preserved text is intentional; it is not a SQL execution/test failure. Other MySQL versions/platforms were not exercised during this refactor.

## Conditional-permission correction

The initial consolidation compared empty-server default builds and demo-enabled security metadata, but missed default builds with target-scoped role grants surviving removal of an older schema. Such roles received the indicator reader from migration 003 and, for a manager qualified on AuditLog, the audit view/reader from the migration-005 runner. Skipping those migrations and optional file 08 omitted up to five GRANT statements.

The correction snapshots recipients through the developer's permitted metadata columns before creation/reset, authenticates the separate admin when needed, and applies only those conditional grants before marking the baseline covered. Files 05/08, all historical SQL, the baseline contract, object versions and migration semantics are unchanged. Six additional regressions compare qualified and unrelated existing roles against the tag, verify manager-specific scope, preserve role/user collision refusal, reject bad admin credentials before reset, and leave coverage incomplete on grant failure. They also check expanded effective permissions, successful reader calls, denied non-manager audit calls, all tracked fingerprints, developer-owned triggers/routines, and absence of developer grant authority.

After the conditional-permission correction, the complete suite passed all 125 tests in 190.067 seconds on the same disposable MySQL 26.7.0 environment, with no failures or skips. The six new permission tests also passed independently in 12.521 seconds. All 246 tracked objects, native permission comparisons, fixture/native JSON checks, and upgrade compatibility checks passed; historical SQL/checksums and version metadata definitions remain unchanged.
