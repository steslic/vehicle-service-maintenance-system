"""Ordered migrations used by build.py; this is not a second command-line entry point."""

import json
import re

from database import checksum, Session


HISTORY_FILE = "09_schema_migrations.sql"
BASELINE_FILE = "migrations/001_baseline.sql"
SNAPSHOT_FILE = "migrations/baseline.json"
METADATA_TABLES = {"schema_migrations", "schema_object_versions"}


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


def schema_fingerprints(session, database):
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
        for line in session.run(query).splitlines():
            row = json.loads(line)
            if any(value is None for value in row[1:2]):
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
                   sha, dirty, baseline=False, target=None):
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
        verify_objects(schema_fingerprints(session, database), snapshot, "Baseline")
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
        verify_objects(schema_fingerprints(session, database),
                       dict(line.split("\t") for line in registered.splitlines()), "Deployed object")
    for version, filename, digest, sql in migrations[len(history):target]:
        log.write(f"OPERATION migration {version:03d} {filename} sha256={digest} source={sha}")
        session.run("INSERT INTO schema_migrations "
                    "(version, filename, checksum, source_commit_sha, source_dirty, status) VALUES "
                    f"({version}, {literal(filename)}, {literal(digest)}, {literal(sha)}, {int(dirty)}, 'applying'); COMMIT;")
        try:
            session.run(sql)
            stamp_objects(session, schema_fingerprints(session, database), version, sha, dirty)
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
