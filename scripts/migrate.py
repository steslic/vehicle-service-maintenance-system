"""Ordered migrations used by build.py; this is not a second command-line entry point."""

import json
import re
from contextlib import contextmanager

from database import checksum, Session


HISTORY_FILE = "09_schema_migrations.sql"
BASELINE_FILE = "migrations/001_baseline.sql"
SNAPSHOT_FILE = "migrations/baseline.json"
METADATA_TABLES = {"schema_migrations", "schema_object_versions"}

# These immutable migrations perform their own routine GRANTs. Give their
# developer-definer helpers authority only on the exact routines, only while
# the helper CALL runs. All account administration stays on a separate session.
ROUTINE_GRANT_STEPS = {
    "migrations/003_indicator_values.sql": (
        "CALL sp_GrantReferenceReaders();", {"sp_ListIndicatorValues": {"EXECUTE"}}),
    "migrations/004_session_identity_and_provenance.sql": (
        "CALL sp_RestorePublicRoutineGrants();",
        {"sp_CreateServiceAppointment": {"EXECUTE", "ALTER ROUTINE"},
         "sp_CompleteRepair": {"EXECUTE", "ALTER ROUTINE"}}),
    "migrations/006_standardized_error_handling.sql": (
        "CALL sp_RestoreErrorRoutineGrants();",
        {name: {"EXECUTE", "ALTER ROUTINE"} for name in (
            "sp_ListIndicatorValues", "sp_ValidateIndicator", "sp_ResolveActor",
            "sp_CreateServiceAppointment", "sp_CompleteRepair", "sp_ListAuditTrail")}),
}
AUDIT_READER_MIGRATION = "migrations/005_temporal_history.sql"


def grant_audit_readers(admin, log, database):
    # Only the existing manager role already scoped to this database. Never
    # grant new rights to an unrelated server-wide role with the same name.
    rows = admin.run("SELECT DISTINCT User, Host FROM mysql.tables_priv "
                     f"WHERE Db = {literal(database)} AND User = 'role_manager' "
                     "AND LOWER(Table_name) = 'auditlog';")
    for row in rows.splitlines():
        user, host = row.split('\t')
        principal = f"{literal(user)}@{literal(host)}"
        admin.run(f"GRANT SELECT ON `{database}`.vw_AuditTrail TO {principal}; "
                  f"GRANT EXECUTE ON PROCEDURE `{database}`.sp_ListAuditTrail TO {principal};")
        log.write(f"ADMIN audit reader grants: {database} {user}@{host}")


@contextmanager
def routine_grant_authority(session, admin, log, database, routines):
    account = session.run("SELECT CURRENT_USER();")
    user, host = account.rsplit("@", 1)
    principal = f"{literal(user)}@{literal(host)}"
    previous = {}
    try:
        for name, required in routines.items():
            old = admin.run("SELECT Proc_priv FROM mysql.procs_priv "
                            f"WHERE Db = {literal(database)} AND User = {literal(user)} "
                            f"AND Host = {literal(host)} AND Routine_name = {literal(name)};")
            existing = {value.upper() for value in old.split(",") if value}
            admin.run(f"GRANT {', '.join(sorted(required))} ON PROCEDURE `{database}`.`{name}` "
                      f"TO {principal} WITH GRANT OPTION;")
            previous[name] = existing
            log.write(f"ADMIN temporary routine authority: {account} {database}.{name}")
        yield
    finally:
        for name, existing in previous.items():
            added = routines[name] - existing
            if added:
                admin.run(f"REVOKE {', '.join(sorted(added))} ON PROCEDURE `{database}`.`{name}` FROM {principal};")
            if "GRANT" not in existing:
                admin.run(f"REVOKE GRANT OPTION ON PROCEDURE `{database}`.`{name}` FROM {principal};")
            log.write(f"ADMIN restored prior routine authority: {account} {database}.{name}")


def apply_migration_sql(session, get_admin, log, database, filename, sql):
    if filename not in ROUTINE_GRANT_STEPS:
        session.run(sql)
        if filename == AUDIT_READER_MIGRATION:
            grant_audit_readers(get_admin(), log, database)
        return
    call, routines = ROUTINE_GRANT_STEPS[filename]
    if sql.count(call) != 1:
        raise ValueError(f"Expected routine grant helper call missing/duplicated in {filename}")
    before, after = sql.split(call)
    # Retain the developer connection and its temporary grant snapshot table.
    # No migration text is edited, and its full original checksum is recorded.
    session.run(before)
    with routine_grant_authority(session, get_admin(), log, database, routines):
        session.run(call)
    session.run(after)


def literal(value):
    # Environment preflight rejects NO_BACKSLASH_ESCAPES.
    return "'" + str(value).replace("\\", "\\\\").replace("'", "''") + "'"


def normalize_sql(sql, database):
    # Normalize identifiers/formatting, preserving quoted business values and messages.
    parts = re.split(r"('(?:''|\\.|[^'\\])*')", sql)
    for index in range(0, len(parts), 2):
        text = re.sub(r"\bAUTO_INCREMENT=\d+\b", "", parts[index], flags=re.IGNORECASE)
        text = text.replace("`", "").lower()
        text = re.sub(r"\b" + re.escape(database) + r"\b", "vehicle_service_maintenance", text)
        text = re.sub(r"\b(tinyint|smallint|mediumint|int|bigint)\(\d+\)", r"\1", text)
        parts[index] = re.sub(r"\s+", " ", text)
    return "".join(parts).strip()


def schema_fingerprints(session, database, get_admin=None, log=None):
    """Definitions only: row contents, AUTO_INCREMENT counters, and definers are excluded."""
    objects = {}
    schema = literal(database)
    tables = session.run(f"SELECT TABLE_NAME FROM information_schema.TABLES "
                         f"WHERE TABLE_SCHEMA = {schema} AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;")
    for table in tables.splitlines():
        if table.lower() in METADATA_TABLES:
            continue
        ddl = session.run(f"SHOW CREATE TABLE `{table.replace('`', '``')}`;").split("\t", 1)[1]
        objects["TABLE:" + table.lower()] = checksum(normalize_sql(ddl, database).encode())

    queries = {
        "VIEW": f"""SELECT JSON_ARRAY(TABLE_NAME, VIEW_DEFINITION, CHECK_OPTION, SECURITY_TYPE, IS_UPDATABLE)
                   FROM information_schema.VIEWS WHERE TABLE_SCHEMA = {schema};""",
        "PROCEDURE": f"""SELECT JSON_ARRAY(ROUTINE_NAME, ROUTINE_TYPE, ROUTINE_DEFINITION,
                    IS_DETERMINISTIC, SQL_DATA_ACCESS, SECURITY_TYPE, SQL_MODE,
                    (SELECT GROUP_CONCAT(CONCAT_WS(':', ORDINAL_POSITION, COALESCE(PARAMETER_MODE, ''),
                        COALESCE(PARAMETER_NAME, ''), DTD_IDENTIFIER) ORDER BY ORDINAL_POSITION SEPARATOR '|')
                     FROM information_schema.PARAMETERS p
                     WHERE p.SPECIFIC_SCHEMA = r.ROUTINE_SCHEMA AND p.SPECIFIC_NAME = r.ROUTINE_NAME))
                   FROM information_schema.ROUTINES r WHERE ROUTINE_SCHEMA = {schema};""",
        "TRIGGER": f"""SELECT JSON_ARRAY(TRIGGER_NAME, EVENT_MANIPULATION, EVENT_OBJECT_TABLE,
                       ACTION_ORDER, ACTION_STATEMENT, ACTION_TIMING, SQL_MODE)
                   FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = {schema};""",
    }
    for kind, query in queries.items():
        rows = [json.loads(line) for line in session.run(query).splitlines()]
        if kind == "PROCEDURE" and any(row[2] is None for row in rows) and get_admin is not None:
            if log:
                log.write(f"ADMIN metadata inspection: routine bodies in {database} have another definer")
            # This query remains restricted to the target schema. SHOW_ROUTINE,
            # when explicitly approved, belongs only to the administrative account.
            rows = [json.loads(line) for line in get_admin().run(query).splitlines()]
        for row in rows:
            definition = row[2] if kind == "PROCEDURE" else row[1]
            if definition is None:
                raise ValueError(f"Cannot inspect definition of {kind} {row[0]}")
            actual_kind = row[1] if kind == "PROCEDURE" else kind
            objects[actual_kind + ":" + row[0].lower()] = checksum(
                normalize_sql(json.dumps(row[1:], ensure_ascii=False), database).encode())
    return dict(sorted(objects.items()))


def load_migrations(sql_dir, inputs):
    if HISTORY_FILE not in inputs:
        raise ValueError(f"Missing migration infrastructure entry: {HISTORY_FILE}")
    migrations = []
    for name, data in inputs.items():
        if not name.startswith("migrations/"):
            continue
        match = re.fullmatch(r"migrations/(\d{3})_[a-z0-9_]+\.sql", name)
        if not match:
            raise ValueError(f"Invalid migration filename: {name}")
        migrations.append((int(match[1]), name, checksum(data), data.decode("utf-8")))
    if [item[0] for item in migrations] != list(range(1, len(migrations) + 1)):
        raise ValueError("Out-of-order migrations: versions must be contiguous and start at 001")
    if not migrations or migrations[0][1] != BASELINE_FILE:
        raise ValueError("The first migration must be 001_baseline.sql")
    listed = {item[1] for item in migrations}
    discovered = {"migrations/" + path.name for path in (sql_dir / "migrations").glob("*.sql")}
    if listed != discovered:
        raise ValueError("Out-of-order/unlisted migration files; update sql/build.sql in version order")
    snapshot = (sql_dir / SNAPSHOT_FILE).read_bytes()
    for tag, data in (("baseline-snapshot", snapshot), ("history-schema", inputs[HISTORY_FILE])):
        if f"-- {tag}-sha256: {checksum(data)}" not in migrations[0][3]:
            raise ValueError(f"Baseline {tag} checksum mismatch")
    return migrations, json.loads(snapshot)


def verify_objects(actual, expected, context):
    differences = sorted(key for key in actual.keys() | expected.keys() if actual.get(key) != expected.get(key))
    if differences:
        raise ValueError(f"{context} schema mismatch: " + ", ".join(differences))


def stamp_objects(session, objects, version, sha, dirty):
    old = session.run("SELECT CONCAT(object_type, ':', object_name), definition_checksum "
                      "FROM schema_object_versions;")
    old = dict(line.split("\t") for line in old.splitlines())
    statements = ["START TRANSACTION;"]
    for key, digest in objects.items():
        if old.get(key) == digest:
            continue
        kind, name = key.split(":", 1)
        statements.append("REPLACE INTO schema_object_versions VALUES "
                          f"({literal(kind)}, {literal(name)}, {version}, {literal(digest)}, "
                          f"{literal(sha)}, {int(dirty)});")
    for key in old.keys() - objects.keys():
        kind, name = key.split(":", 1)
        statements.append(f"DELETE FROM schema_object_versions WHERE object_type = {literal(kind)} "
                          f"AND object_name = {literal(name)};")
    statements.append(f"UPDATE schema_migrations SET status = 'applied', applied_at = CURRENT_TIMESTAMP(6) "
                      f"WHERE version = {version} AND status = 'applying';")
    statements.append("COMMIT;")
    session.run("\n".join(statements))


def run_migrations(session, command, env, log, database, inputs, migrations, snapshot,
                   sha, dirty, baseline=False, target=None, get_admin=None):
    target = migrations[-1][0] if target is None else target
    if target not in [item[0] for item in migrations]:
        raise ValueError("Target version is not in sql/build.sql")
    lock = "vsm:migrate:" + checksum(database.encode())[:40]
    if session.run(f"SELECT GET_LOCK({literal(lock)}, 0);") != "1":
        raise ValueError("Another migration connection holds the database migration lock")
    log.write("MIGRATION LOCK: acquired")
    session.run(f"USE `{database}`;")
    has_history = session.run("SELECT COUNT(*) FROM information_schema.TABLES "
                              "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'schema_migrations';") == "1"
    if not has_history:
        if not baseline:
            raise ValueError("Unversioned database: use --migrate --baseline to verify and register it")
        if session.run("SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() "
                       "AND TABLE_NAME = 'schema_object_versions';") != "0":
            raise ValueError("Orphan migration metadata: baseline refused; inspect/restore the pre-run backup")
        verify_objects(schema_fingerprints(session, database, get_admin, log), snapshot, "Baseline")
        log.write("BASELINE SCHEMA VERIFICATION: PASS (no business rows changed)")
        log.write(f"OPERATION {HISTORY_FILE} sha256={checksum(inputs[HISTORY_FILE])}")
        session.run(inputs[HISTORY_FILE].decode("utf-8"))
    history = []
    for row in session.run("SELECT JSON_ARRAY(version, filename, checksum, status) "
                            "FROM schema_migrations ORDER BY version;").splitlines():
        history.append(json.loads(row))
    if has_history and not history:
        raise ValueError("Interrupted migration initialization: empty schema_migrations; restore the pre-run backup")
    for index, row in enumerate(history):
        if row[0] != index + 1 or index >= len(migrations):
            raise ValueError("Out-of-order migration history")
        expected = migrations[index]
        if row[1:3] != [expected[1], expected[2]]:
            raise ValueError(f"Migration checksum/filename mismatch: version {row[0]}")
        if row[3] != "applied":
            raise ValueError(f"Incomplete migration {row[0]} ({row[3]}): no retry; inspect logs and restore the pre-run backup")
    if history:
        if history[-1][0] > target:
            raise ValueError("Downgrades/out-of-order migration targets are not supported")
        registered = session.run("SELECT CONCAT(object_type, ':', object_name), definition_checksum "
                                 "FROM schema_object_versions;")
        verify_objects(schema_fingerprints(session, database, get_admin, log),
                       dict(line.split("\t") for line in registered.splitlines()), "Deployed object")
    if any(filename in ROUTINE_GRANT_STEPS or filename == AUDIT_READER_MIGRATION
           for _, filename, _, _ in migrations[len(history):target]):
        if get_admin is None:
            raise ValueError("These migrations require a separate administrative connection for routine grants")
        get_admin()  # Authenticate before starting an immutable DDL migration.
    for version, filename, digest, sql in migrations[len(history):target]:
        log.write(f"OPERATION migration {version:03d} {filename} sha256={digest} source={sha}")
        session.run("INSERT INTO schema_migrations "
                    "(version, filename, checksum, source_commit_sha, source_dirty, status) VALUES "
                    f"({version}, {literal(filename)}, {literal(digest)}, {literal(sha)}, {int(dirty)}, 'applying'); COMMIT;")
        try:
            apply_migration_sql(session, get_admin, log, database, filename, sql)
            stamp_objects(session, schema_fingerprints(session, database, get_admin, log), version, sha, dirty)
        except (RuntimeError, ValueError) as error:
            # A SQL error closes the fail-fast client. Use a new connection to
            # mark failure; the durable applying row already blocks other runners.
            try:
                with Session(command, env, log) as failure_session:
                    failure_session.run(f"USE `{database}`; UPDATE schema_migrations SET status = 'failed', "
                                        f"error_message = {literal(str(error))} WHERE version = {version} "
                                        "AND status = 'applying'; COMMIT;")
            except RuntimeError:
                log.write("Migration remains applying; treat it as interrupted")
            raise
        log.write(f"MIGRATION {version:03d}: APPLIED")
    log.write(f"SCHEMA VERSION: {target}; applied migrations are never executed again")
    session.run(f"SELECT RELEASE_LOCK({literal(lock)});")
