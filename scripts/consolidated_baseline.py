"""Install a pinned current revision while preserving independent v006 ancestry evidence."""

import json
from pathlib import Path
import re

from database import checksum, Session
from migrate import literal, schema_fingerprints, verify_objects

VERSION = 6
REVISION = 7
REVISION_FILE = "consolidated/007_procedure_only.json"
REVISION_SHA256 = "c4bff6c9a2bd50333bb0f64303ea74a661e2d88ac21c106bbfb8509c8e632539"
CONTRACT_FILE = 'consolidated/006_baseline.json'
# The contract is independent evidence captured from the published checkpoint.
CONTRACT_SHA256 = '94d124596a808d04cf00bcf0814ff6f2fd2c127426bef1c71205c9d21cf1dee2'


def load_contract(sql_dir, version=REVISION):
    """Independent contracts: never relabel revision-007 changes as v006 equivalence."""
    data = (sql_dir / CONTRACT_FILE).read_bytes()
    if checksum(data) != CONTRACT_SHA256:
        raise ValueError('Consolidated baseline contract checksum mismatch')
    base = json.loads(data)
    if base['version'] != VERSION or len(base['objects']) != 246:
        raise ValueError('Invalid consolidated baseline contract')
    if version == VERSION:
        return base
    if version != REVISION:
        raise ValueError('Unsupported consolidated revision')
    data = (sql_dir / REVISION_FILE).read_bytes()
    if checksum(data) != REVISION_SHA256:
        raise ValueError('Consolidated revision contract checksum mismatch')
    current = json.loads(data)
    if current['version'] != REVISION or current['parent_contract_sha256'] != CONTRACT_SHA256:
        raise ValueError('Invalid consolidated revision ancestry')
    replacements = {'FUNCTION:fn_applicationerrorid', 'FUNCTION:fn_errorclass'}
    from operation_contract import OPERATIONS
    additions = {'PROCEDURE:' + name.lower() for name in OPERATIONS}
    # Internal helper: pinned like every API, with no application entitlement or native grant.
    additions.add('PROCEDURE:sp_tryrecordrejecteddiagnostic')
    if (set(current['replaced_objects']) != replacements or set(current['added_objects']) != additions
            or set(current['objects']) != set(base['objects']) | additions
            or current['covered_migrations'] != base['covered_migrations']):
        raise ValueError('Invalid revision-007 object inventory')
    for key, record in base['objects'].items():
        if key not in replacements and current['objects'][key] != record:
            raise ValueError('Unapproved change to v006 object: ' + key)
    for key in replacements | additions:
        record = current['objects'][key]
        if record.get('revision') != REVISION or record['version'] != (base['objects'][key]['version'] if key in replacements else None):
            raise ValueError('Invalid per-object revision provenance: ' + key)
    for name, digest in current['input_sha256'].items():
        if checksum((sql_dir / name).read_bytes()) != digest:
            raise ValueError('Revision-007 input checksum mismatch: ' + name)
    return current


def validate_revision(session, contract):
    rows = session.run("SELECT JSON_ARRAY(revision, contract_file, contract_checksum, status, "
        "installed_at IS NOT NULL) FROM schema_revisions ORDER BY revision;").splitlines()
    expected = [[REVISION, REVISION_FILE, REVISION_SHA256, 'installed', 1]]
    if [json.loads(row) for row in rows] != expected:
        raise ValueError('Incomplete/invalid consolidated revision history')
    later = session.run("SELECT COUNT(*) FROM schema_migrations WHERE version > 6 AND status = 'applied';")
    if later == '0':
        rows = session.run("SELECT JSON_ARRAY(CONCAT(object_type, ':', object_name), migration_version, "
            "revision_version, definition_checksum) FROM schema_object_versions ORDER BY object_type, object_name;")
        expected = [[key, value['version'], value.get('revision'), value['checksum']]
                    for key, value in sorted(contract['objects'].items())]
        if [json.loads(row) for row in rows.splitlines()] != expected:
            raise ValueError('Revision-007 object provenance mismatch')


def validate_initial_policy(session, contract):
    rows = session.run('SELECT JSON_ARRAY(RoleType, ProcedureName) FROM RoleProcedurePermission ORDER BY RoleType, ProcedureName;')
    if [json.loads(row) for row in rows.splitlines()] != contract['application_entitlements']:
        raise ValueError('Revision-007 application entitlement mismatch')


def load_current_migrations(sql_dir, inputs, contract):
    """Historical filenames/digests are evidence; their SQL is never read here."""
    manifest = (sql_dir / 'build.sql').read_text()
    names = re.findall(r'^SOURCE\s+(migrations/\d{3}_[a-z0-9_]+\.sql)\s*$', manifest, re.MULTILINE)
    covered = contract['covered_migrations']
    if names[:VERSION] != [row['filename'] for row in covered]:
        raise ValueError('Out-of-order consolidated migration registry')
    migrations = [(row['version'], row['filename'], row['checksum'], None) for row in covered]
    for name in names[VERSION:]:
        version = int(Path(name).name[:3])
        if version != len(migrations) + 1:
            raise ValueError('Out-of-order migrations: versions must be contiguous')
        data = inputs[name]
        migrations.append((version, name, checksum(data), data.decode('utf-8')))
    listed = set(names)
    discovered = {'migrations/' + p.name for p in (sql_dir / 'migrations').glob('[0-9][0-9][0-9]_*.sql')}
    if discovered - listed or listed - discovered - {row['filename'] for row in covered}:
        raise ValueError('Out-of-order/unlisted migration files; update sql/build.sql')
    return migrations


def validate_coverage(session, contract):
    """A covered prefix is not an execution record and cannot mask partial installs."""
    rows = [json.loads(row) for row in session.run(
        "SELECT JSON_ARRAY(version, filename, checksum, status, applied_at, baseline_version, "
        "baseline_checksum, covered_at IS NOT NULL) FROM schema_migrations WHERE version <= 6 ORDER BY version;"
    ).splitlines()]
    expected = [[r['version'], r['filename'], r['checksum'], 'covered', None, VERSION, CONTRACT_SHA256, 1]
                for r in contract['covered_migrations']]
    if rows != expected:
        raise ValueError('Invalid/incomplete consolidated baseline coverage')


def existing_reader_grants(session, database):
    """Match migration 003 and the migration-005 runner's target-scoped recipients.

    Inspect through the developer's existing metadata-column reads. Do not create
    principals or infer authority from a same-named role in another database.
    """
    rows = session.run("SELECT DISTINCT User, Host, LOWER(Table_name) FROM mysql.tables_priv "
        f"WHERE Db = {literal(database)} AND User IN "
        "('role_service_advisor', 'role_technician', 'role_manager') ORDER BY User, Host, LOWER(Table_name);")
    recipients = {}
    for row in rows.splitlines():
        user, host, table = row.split('\t')
        recipients.setdefault((user, host), set()).add(table)
    grants = []
    for (user, host), tables in recipients.items():
        principal = f'{literal(user)}@{literal(host)}'
        statements = [f'GRANT EXECUTE ON PROCEDURE `{database}`.sp_ListIndicatorValues TO {principal};']
        if user == 'role_manager' and 'auditlog' in tables:
            statements += [f'GRANT SELECT ON `{database}`.vw_AuditTrail TO {principal};',
                           f'GRANT EXECUTE ON PROCEDURE `{database}`.sp_ListAuditTrail TO {principal};']
        grants.append((principal, '\n'.join(statements)))
    return grants


def install(session, command, env, log, database, inputs, contract, sha, dirty, with_demo, get_admin,
            reader_grants=()):
    lock = 'vsm:migrate:' + checksum(database.encode())[:40]
    if session.run(f'SELECT GET_LOCK({literal(lock)}, 0);') != '1':
        raise ValueError('Another migration connection holds the database migration lock')
    log.write('MIGRATION LOCK: acquired')
    initialized = False
    try:
        schema = inputs['01_schema.sql'].decode('utf-8').replace('vehicle_service_maintenance', database)
        prefix, body = schema.split('-- BEGIN APPLICATION TABLES\n')
        tables, foreign_keys = body.split('-- BEGIN FOREIGN KEYS\n')
        log.write(f"OPERATION 01_schema.sql sha256={checksum(inputs['01_schema.sql'])}")
        session.run(prefix)
        statements = []
        for row in contract['covered_migrations']:
            statements.append('INSERT INTO schema_migrations '
                '(version, filename, checksum, source_commit_sha, source_dirty, status, baseline_version, baseline_checksum) VALUES '
                f"({row['version']}, {literal(row['filename'])}, {literal(row['checksum'])}, {literal(sha)}, "
                f"{int(dirty)}, 'applying', {VERSION}, {literal(CONTRACT_SHA256)});")
        statements.append('INSERT INTO schema_revisions (revision, contract_file, contract_checksum, source_commit_sha, source_dirty, status) VALUES '
                f"({REVISION}, {literal(REVISION_FILE)}, {literal(REVISION_SHA256)}, {literal(sha)}, {int(dirty)}, 'applying');")
        session.run('\n'.join(statements) + '\nCOMMIT;')
        initialized = True
        session.run(tables)
        for name in ('02_indexes.sql', '01_foreign_keys', '04_procedures.sql', '03_views_reports.sql',
                     '06_sample_data.sql', '05_triggers_roles.sql', '08_demo_accounts.sql', '07_tests.sql'):
            if name == '01_foreign_keys':
                session.run(foreign_keys)
                continue
            if name == '08_demo_accounts.sql' and not with_demo:
                log.write('SKIP optional 08_demo_accounts.sql')
                continue
            sql = inputs[name].decode('utf-8').replace('vehicle_service_maintenance', database)
            log.write(f'OPERATION {name} sha256={checksum(inputs[name])}')
            operation = get_admin() if name == '08_demo_accounts.sql' else session
            if operation is not session:
                log.write('ADMIN OPERATION: ' + name)
            operation.run(sql, echo=True)
        for principal, sql in reader_grants:
            get_admin().run(sql)
            log.write(f'ADMIN existing role reader grants: {database} {principal}')
        objects = schema_fingerprints(session, database)
        verify_objects(objects, {k: v['checksum'] for k, v in contract['objects'].items()}, 'Consolidated revision 007')
        validate_initial_policy(session, contract)
        statements = ['START TRANSACTION;']
        for key, record in contract['objects'].items():
            kind, name = key.split(':', 1)
            migration_version = 'NULL' if record['version'] is None else str(record['version'])
            revision_version = 'NULL' if record.get('revision') is None else str(record['revision'])
            statements.append('INSERT INTO schema_object_versions (object_type, object_name, migration_version, revision_version, definition_checksum, source_commit_sha, source_dirty) VALUES '
                f"({literal(kind)}, {literal(name)}, {migration_version}, {revision_version}, {literal(objects[key])}, {literal(sha)}, {int(dirty)});")
        statements += ["UPDATE schema_migrations SET status = 'covered', covered_at = CURRENT_TIMESTAMP(6) "
                       "WHERE baseline_version = 6 AND status = 'applying';",
                       "UPDATE schema_revisions SET status = 'installed', installed_at = CURRENT_TIMESTAMP(6) WHERE revision = 7 AND status = 'applying';", 'COMMIT;']
        session.run('\n'.join(statements))
        validate_coverage(session, load_contract(Path(__file__).resolve().parent.parent / 'sql', version=6))
        validate_revision(session, contract)
        log.write('CONSOLIDATED REVISION 007: VERIFIED; baseline 006 ancestry preserved; migrations 001–006 COVERED, not executed')
        log.write('DATABASE TEST SUITE: PASS (current-schema assertions; workflow regressions use registered actors)')
    except (RuntimeError, ValueError, KeyboardInterrupt) as error:
        if initialized:
            try:
                with Session(command, env, log) as failure:
                    failure.run(f'USE `{database}`; UPDATE schema_migrations SET status = \'failed\', '
                                f'error_message = {literal(str(error))} WHERE status = \'applying\'; '
                                "UPDATE schema_revisions SET status = 'failed' WHERE status = 'applying'; COMMIT;")
            except RuntimeError:
                log.write('Baseline remains applying; treat installation as interrupted')
        raise
    finally:
        if session.process.poll() is None:
            session.run(f'SELECT RELEASE_LOCK({literal(lock)});')
