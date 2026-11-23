"""Install and verify the frozen version-006 baseline, without executing old migrations."""

import json
from pathlib import Path
import re

from database import checksum, Session
from migrate import literal, schema_fingerprints, verify_objects

VERSION = 6
CONTRACT_FILE = 'consolidated/006_baseline.json'
# The contract is independent evidence captured from the published checkpoint.
CONTRACT_SHA256 = '94d124596a808d04cf00bcf0814ff6f2fd2c127426bef1c71205c9d21cf1dee2'


def load_contract(sql_dir):
    data = (sql_dir / CONTRACT_FILE).read_bytes()
    if checksum(data) != CONTRACT_SHA256:
        raise ValueError('Consolidated baseline contract checksum mismatch')
    contract = json.loads(data)
    if contract['version'] != VERSION or len(contract['objects']) != 246:
        raise ValueError('Invalid consolidated baseline contract')
    return contract


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
        verify_objects(objects, {k: v['checksum'] for k, v in contract['objects'].items()}, 'Consolidated baseline')
        statements = ['START TRANSACTION;']
        for key, record in contract['objects'].items():
            kind, name = key.split(':', 1)
            statements.append('INSERT INTO schema_object_versions VALUES '
                f"({literal(kind)}, {literal(name)}, {record['version']}, {literal(objects[key])}, {literal(sha)}, {int(dirty)});")
        statements += ["UPDATE schema_migrations SET status = 'covered', covered_at = CURRENT_TIMESTAMP(6) "
                       "WHERE baseline_version = 6 AND status = 'applying';", 'COMMIT;']
        session.run('\n'.join(statements))
        validate_coverage(session, contract)
        log.write('CONSOLIDATED BASELINE 006: VERIFIED; migrations 001–006 COVERED, not executed')
        log.write('DATABASE TEST SUITE: PASS (current-schema assertions; workflow regressions use registered actors)')
    except (RuntimeError, ValueError, KeyboardInterrupt) as error:
        if initialized:
            try:
                with Session(command, env, log) as failure:
                    failure.run(f'USE `{database}`; UPDATE schema_migrations SET status = \'failed\', '
                                f'error_message = {literal(str(error))} WHERE status = \'applying\'; COMMIT;')
            except RuntimeError:
                log.write('Baseline remains applying; treat installation as interrupted')
        raise
    finally:
        if session.process.poll() is None:
            session.run(f'SELECT RELEASE_LOCK({literal(lock)});')
