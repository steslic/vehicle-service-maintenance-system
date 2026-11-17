"""Small shared helpers for the build and migration runner (standard library only)."""

from datetime import datetime, timezone
import hashlib
import json
import os
import re
import subprocess
import threading
import uuid


BUILD_SQL_MODE = ("ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,"
                  "ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION")


def checksum(data):
    return hashlib.sha256(data).hexdigest()


class RunLog:
    def __init__(self, directory):
        directory.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        self.path = directory / f"{stamp}-{os.getpid()}-build.log"
        self.file = self.path.open("x", encoding="utf-8", buffering=1)
        self.write(f"LOG {self.path}")

    def write(self, message):
        for line in str(message).splitlines():
            print(line, flush=True)
            stamp = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
            self.file.write(f"{stamp} {line}\n")

    def close(self, status):
        self.write(f"FINAL STATUS: {status}")
        self.file.close()


def source_revision(root):
    def git(*args):
        return subprocess.check_output(["git", "-C", str(root), *args], text=True,
                                       stderr=subprocess.PIPE).strip()
    return git("rev-parse", "HEAD"), bool(git("status", "--porcelain", "--untracked-files=normal"))


class Session:
    """Keep one fail-fast mysql connection, including its advisory lock, alive."""

    def __init__(self, command, env, log):
        self.log = log
        self.process = subprocess.Popen(command, env=env, text=True, bufsize=1,
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT)

    def run(self, sql, echo=False):
        marker = "__build_end_" + uuid.uuid4().hex
        errors = []

        def send():
            try:
                self.process.stdin.write(sql + f"\nSELECT '{marker}';\n")
                self.process.stdin.flush()
            except (BrokenPipeError, OSError) as error:
                errors.append(error)

        # Read while writing, so a large SQL batch cannot fill both pipe buffers.
        writer = threading.Thread(target=send, daemon=True)
        writer.start()
        rows = []
        for line in self.process.stdout:
            line = line.rstrip("\n")
            if line == marker:
                writer.join()
                if errors:
                    raise RuntimeError("MySQL connection closed while sending SQL")
                return "\n".join(rows)
            rows.append(line)
            if echo:
                self.log.write(line)
        writer.join(timeout=2)
        self.process.wait()
        raise RuntimeError("MySQL stopped: " + ("\n".join(rows[-8:]) or "connection interrupted"))

    def close(self):
        try:
            self.process.stdin.close()
        except (BrokenPipeError, OSError):
            pass
        try:
            self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        self.process.stdout.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


def mysql_version(value, component):
    match = re.search(r"\b(\d+)\.(\d+)\.(\d+)", value)
    if "mariadb" in value.lower() or not match or tuple(map(int, match.groups())) < (8, 0, 18):
        raise ValueError(f"{component} requires MySQL 8.0.18 or newer: {value}")


def verify_environment(session, client_version, log):
    mysql_version(client_version, "Client")
    settings = json.loads(session.run("""
        SELECT JSON_OBJECT('version', VERSION(), 'distribution', @@version_comment,
          'engine', @@session.default_storage_engine, 'sql_mode', @@session.sql_mode,
          'foreign_key_checks', @@session.foreign_key_checks,
          'unique_checks', @@session.unique_checks, 'autocommit', @@session.autocommit,
          'isolation', @@session.transaction_isolation, 'read_only', @@global.read_only,
          'super_read_only', @@global.super_read_only,
          'flush_at_commit', @@global.innodb_flush_log_at_trx_commit,
          'charset', @@character_set_connection, 'collation', @@collation_connection);
    """))
    log.write("MYSQL CLIENT: " + client_version)
    log.write("MYSQL SERVER AND SETTINGS: " + json.dumps(settings, sort_keys=True))
    mysql_version(settings["version"] + " " + settings["distribution"], "Server")
    modes = set(settings["sql_mode"].split(","))
    required = {"STRICT_TRANS_TABLES", "NO_ENGINE_SUBSTITUTION"}
    if not required <= modes or {"ANSI_QUOTES", "NO_BACKSLASH_ESCAPES"} & modes:
        raise ValueError("Required SQL modes: STRICT_TRANS_TABLES, NO_ENGINE_SUBSTITUTION; "
                         "ANSI_QUOTES and NO_BACKSLASH_ESCAPES must be disabled")
    if settings["engine"].lower() != "innodb" or settings["isolation"] != "REPEATABLE-READ":
        raise ValueError("Required settings: InnoDB and REPEATABLE-READ")
    if any(settings[name] != 1 for name in ("foreign_key_checks", "unique_checks", "autocommit")):
        raise ValueError("foreign_key_checks, unique_checks, and autocommit must be enabled")
    if settings["read_only"] or settings["super_read_only"]:
        raise ValueError("Builds and migrations require a writable server")
    if settings["flush_at_commit"] != 1:
        raise ValueError("Durable migration checkpoints require innodb_flush_log_at_trx_commit = 1")
    if settings["charset"] != "utf8mb4":
        raise ValueError("The connection must use utf8mb4")
    # MySQL stores the creation-time SQL mode on routines and triggers. Pin it
    # after validating defaults so compatible servers produce the same objects.
    session.run(f"SET SESSION sql_mode = '{BUILD_SQL_MODE}'; SET SESSION time_zone = '+00:00';")
    log.write(f"SESSION SETTINGS: sql_mode={BUILD_SQL_MODE}; time_zone=+00:00")
    log.write("PREFLIGHT: PASS")
