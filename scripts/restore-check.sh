#!/usr/bin/env bash
set -euo pipefail
# Non-destructive recovery exercise for an explicitly synthetic development DB.
cd "$(dirname "$0")/.."
umask 077
exec python3 - <<'PYTHON'
from pathlib import Path
import datetime
import hashlib
import json
import os
import re
import shlex
import signal
import subprocess
import shutil
import sys
import tempfile
import time
import uuid

os.umask(0o077)
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(143))
backend = os.environ.get("DELPHYR_RESTORE_BACKEND", "docker")
if backend not in ("docker", "native"):
    raise SystemExit("DELPHYR_RESTORE_BACKEND must be docker or native")
if backend == "docker" and sys.platform != "linux":
    raise SystemExit("Docker socket recovery requires a native Linux Docker host. On macOS use DELPHYR_RESTORE_BACKEND=native; see docs/runbooks/backup-and-restore.md.")
# Explicit command hosts must not be redirected by inherited libpq services
# or numeric host addresses. Password/passfile authentication remains available.
for variable in ("PGHOSTADDR", "PGSERVICE", "PGSERVICEFILE"):
    os.environ.pop(variable, None)
if backend == "docker" and shutil.which("docker") is None:
    raise SystemExit("Docker executable is required for Docker recovery")
source = "delphyr-dev-postgres"
database = "delphyr"
root = Path.cwd()
pg_bin = None
source_port = None
source_database = None
source_user = os.environ.get("DELPHYR_RESTORE_SOURCE_USER", "postgres")
if backend == "native":
    binary_dir = os.environ.get("DELPHYR_PG_BIN", "")
    source_port = os.environ.get("DELPHYR_RESTORE_SOURCE_PORT", "")
    source_database = os.environ.get("DELPHYR_RESTORE_SOURCE_DB", "")
    if not binary_dir or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]{0,62}", source_database) or not source_user or not re.fullmatch(r"[0-9]+", source_port) or not 1 <= int(source_port) <= 65535:
        raise SystemExit("Native recovery requires DELPHYR_PG_BIN, DELPHYR_RESTORE_SOURCE_PORT and DELPHYR_RESTORE_SOURCE_DB for the synthetic source on 127.0.0.1; use a plain database name, not a URI or connection string")
    pg_bin = Path(binary_dir).resolve(strict=True)
    for program in ("postgres", "initdb", "pg_ctl", "createdb", "psql", "pg_dump", "pg_restore", "pg_isready"):
        if not (pg_bin / program).is_file() or not os.access(pg_bin / program, os.X_OK):
            raise SystemExit("Missing PostgreSQL executable: " + str(pg_bin / program))
(root / ".checks").mkdir(exist_ok=True)
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
out = Path(tempfile.mkdtemp(prefix="restore-" + stamp + "-", dir=root / ".checks"))
# A private, short local path is independent of the checkout's length.
socket = Path(tempfile.mkdtemp(prefix="delphyr-restore-", dir="/tmp"))
name = "delphyr-restore-" + uuid.uuid4().hex[:12]
restore_data = out / "pgdata"
holder = None
image = None
native_version = None
started = time.monotonic()
summary = None

def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def db_args(target):
    if backend == "native":
        if target == source:
            return ["-h", "127.0.0.1", "-p", source_port, "-U", source_user, "-d", source_database]
        return ["-h", str(socket), "-p", "5432", "-U", "postgres", "-d", database]
    return ["-U", "postgres", "-d", database]

def client(target, program, *options):
    prefix = [str(pg_bin / program)] if backend == "native" else ["docker", "exec", "-i", target, program]
    return prefix + list(options) + db_args(target)

def psql(target, sql):
    # to_jsonb(timestamptz) uses the session timezone. Compare the same
    # representation even when a fresh target has a different server default.
    return run(client(target, "psql", "-X", "-qAt", "-w", "-v", "ON_ERROR_STOP=1"), input="SET TIME ZONE 'UTC';\n" + sql, text=True, capture_output=True).stdout

def start_restore():
    if backend == "native":
        run([str(pg_bin / "initdb"), "-D", str(restore_data), "-U", "postgres", "-A", "trust", "--no-locale", "--encoding=UTF8"], stdout=subprocess.DEVNULL)
        options = "-c listen_addresses='' -c unix_socket_directories=" + shlex.quote(str(socket)) + " -p 5432"
        run([str(pg_bin / "pg_ctl"), "-D", str(restore_data), "-l", str(out / "postgres.log"), "-o", options, "-w", "-t", "60", "start"], stdout=subprocess.DEVNULL)
        run([str(pg_bin / "createdb"), "-h", str(socket), "-p", "5432", "-U", "postgres", database])
    else:
        run(["docker", "run", "--detach", "--name", name, "--network=none",
             "--label", "delphyr.purpose=synthetic-restore-check", "--env", "POSTGRES_DB=" + database,
             "--env", "POSTGRES_HOST_AUTH_METHOD=trust", "--volume", str(socket) + ":/var/run/postgresql", image], capture_output=True)
        for _ in range(120):
            ready = subprocess.run(["docker", "exec", name, "pg_isready", "-h", "127.0.0.1", "-U", "postgres", "-d", database], capture_output=True)
            if ready.returncode == 0:
                return
            time.sleep(0.25)
        raise RuntimeError("Fresh isolated restore database did not become ready")

def cleanup_restore():
    if backend == "native":
        if restore_data.exists():
            active = subprocess.run([str(pg_bin / "pg_ctl"), "-D", str(restore_data), "status"], capture_output=True)
            if active.returncode == 0:
                # Never remove the data of a server that has not stopped.
                run([str(pg_bin / "pg_ctl"), "-D", str(restore_data), "-m", "fast", "-w", "-t", "60", "stop"], stdout=subprocess.DEVNULL)
            elif active.returncode != 3 and (restore_data / "postmaster.pid").exists():
                raise RuntimeError("Cannot establish restore server state; retained " + str(restore_data))
            shutil.rmtree(restore_data)
    else:
        inspected = subprocess.run(["docker", "container", "inspect", "--format", "{{.State.Running}}", name], text=True, capture_output=True)
        if inspected.returncode == 0:
            hand_back = "rm -f /var/run/postgresql/.s.PGSQL.5432 /var/run/postgresql/.s.PGSQL.5432.lock; chown " + str(os.getuid()) + ":" + str(os.getgid()) + " /var/run/postgresql; chmod 0700 /var/run/postgresql"
            if inspected.stdout.strip() == "true":
                run(["docker", "exec", "--user", "root", name, "sh", "-c", hand_back], capture_output=True)
            else:
                run(["docker", "run", "--rm", "--network=none", "--user", "root", "--entrypoint", "sh", "--volume", str(socket) + ":/var/run/postgresql", image, "-c", hand_back], capture_output=True)
            run(["docker", "rm", "--force", "--volumes", name], capture_output=True)
    shutil.rmtree(socket)

counts_sql = r"""
SELECT format('SELECT %L, count(*), md5(coalesce(string_agg(row_data, E''\n'' ORDER BY row_data COLLATE "C"), '''')) FROM (SELECT to_jsonb(t)::text AS row_data FROM %I.%I t) rows', schemaname || '.' || tablename, schemaname, tablename)
FROM pg_tables WHERE schemaname IN ('identity','research','ops') ORDER BY schemaname, tablename
\gexec
"""
migrations_sql = "SELECT version,checksum FROM ops.schema_migrations ORDER BY version;\n"
snapshots_sql = "SELECT id,hash,md5(content::text) FROM research.snapshots ORDER BY id;\n"
schema_sql = """
SELECT n.nspname,c.relname,a.attnum,a.attname,pg_catalog.format_type(a.atttypid,a.atttypmod),a.attnotnull,coalesce(pg_get_expr(d.adbin,d.adrelid),'')
FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
WHERE n.nspname IN ('identity','research','ops') AND c.relkind='r' AND a.attnum>0 AND NOT a.attisdropped ORDER BY n.nspname,c.relname,a.attnum;
SELECT n.nspname,c.relname,k.conname,pg_get_constraintdef(k.oid) FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('identity','research','ops') ORDER BY n.nspname,c.relname,k.conname;
SELECT n.nspname,c.relname,t.tgname,pg_get_triggerdef(t.oid) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('identity','research','ops') AND NOT t.tgisinternal ORDER BY n.nspname,c.relname,t.tgname;
SELECT n.nspname,p.proname,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('identity','research','ops') ORDER BY n.nspname,p.proname;
"""
try:
    if len(os.fsencode(socket / ".s.PGSQL.5432")) > 100:
        raise RuntimeError("Temporary Unix socket path is too long")
    if backend == "docker":
        image = run(["docker", "inspect", "--format", "{{.Image}}", source], text=True, capture_output=True).stdout.strip()
    else:
        native_version = run([str(pg_bin / "postgres"), "--version"], text=True, capture_output=True).stdout.strip()
    holder = subprocess.Popen(client(source, "psql", "-X", "-qAt", "-w", "-v", "ON_ERROR_STOP=1"), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    holder.stdin.write("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\nSELECT pg_export_snapshot();\n")
    holder.stdin.flush()
    snapshot = holder.stdout.readline().strip()
    if not snapshot or any(c not in "0123456789ABCDEFabcdef-" for c in snapshot):
        raise RuntimeError("Could not acquire a valid exported source snapshot")
    prefix = "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SET TRANSACTION SNAPSHOT '" + snapshot + "';\n"
    synthetic = psql(source, prefix + "SELECT count(*) FROM research.protocol_versions WHERE config->'study'->>'environment' IS DISTINCT FROM 'demo';\nCOMMIT;\n").strip()
    if synthetic != "0":
        raise RuntimeError("Recovery exercise accepts only explicitly synthetic demo protocols")
    artifact_study = os.environ.get("DELPHYR_RESTORE_STUDY", "")
    if artifact_study:
        artifact_study = str(uuid.UUID(artifact_study))
    checks = {"tables": counts_sql, "migrations": migrations_sql, "snapshots": snapshots_sql, "schema": schema_sql}
    if artifact_study:
        # Exports whose files were removed after their download period keep
        # their registration; they are compared but have no files to copy.
        checks["artifacts"] = "SELECT id,storage_key,checksum,profile FROM ops.artifacts WHERE study_id='" + artifact_study + "' AND removed_at IS NULL ORDER BY id;\n"
        checks["removed_artifacts"] = "SELECT id FROM ops.artifacts WHERE study_id='" + artifact_study + "' AND removed_at IS NOT NULL ORDER BY id;\n"
    expected = {}
    for key, sql in checks.items():
        value = psql(source, prefix + sql + "COMMIT;\n")
        expected[key] = value
        (out / ("source-" + key + ".txt")).write_text(value)
    if not expected["snapshots"].strip():
        raise RuntimeError("Recovery proof requires at least one frozen synthetic snapshot")
    with (out / "database.dump").open("wb") as stream:
        run(client(source, "pg_dump", "-w", "--format=custom", "--no-owner", "--no-privileges", "--snapshot=" + snapshot), stdout=stream)
    artifact_records = []
    removed_artifacts = len(expected.get("removed_artifacts", "").splitlines())
    if artifact_study:
        if not expected["artifacts"].strip() and not removed_artifacts:
            raise RuntimeError("Selected synthetic study has no registered artifacts")
        artifact_dir = Path(os.environ.get("DELPHYR_ARTIFACT_ROOT") or root / ".artifacts")
        if expected["artifacts"].strip() and not artifact_dir.is_dir():
            raise RuntimeError("The private export directory " + str(artifact_dir) + " does not exist")
        for row in expected["artifacts"].splitlines():
            artifact_root = artifact_dir.resolve(strict=True)
            artifact_id, key, checksum, profile = row.split("|")
            key = str(uuid.UUID(key))
            source_dir = artifact_root / key
            # A registered export whose worker stopped before renaming it
            # keeps its temporary name.
            if not os.path.lexists(source_dir) and (artifact_root / (key + ".partial")).is_dir():
                source_dir = artifact_root / (key + ".partial")
            if source_dir.is_symlink():
                raise RuntimeError("Unsafe artifact directory")
            if not source_dir.is_dir():
                raise RuntimeError("Export " + artifact_id + " has no directory in " + str(artifact_root) + "; its files may lie in another export directory")
            if source_dir.resolve(strict=True).parent != artifact_root:
                raise RuntimeError("Unsafe artifact directory")
            manifest_path = source_dir / "manifest.json"
            if manifest_path.is_symlink() or hashlib.sha256(manifest_path.read_bytes()).hexdigest() != checksum:
                raise RuntimeError("Artifact manifest does not match registry")
            manifest = json.loads(manifest_path.read_text())
            if manifest.get("profile") != profile or profile not in ("research_round", "research_pseudonymized", "study_summary", "audit_restricted", "contacts_restricted"):
                raise RuntimeError("Artifact profile does not match registry")
            allowed = {"manifest.json"}
            for entry in manifest["files"]:
                filename = entry["name"]
                if Path(filename).name != filename or filename in (".", "..", "manifest.json"):
                    raise RuntimeError("Unsafe manifest filename")
                file = source_dir / filename
                if file.is_symlink() or hashlib.sha256(file.read_bytes()).hexdigest() != entry["sha256"]:
                    raise RuntimeError("Artifact member checksum mismatch")
                allowed.add(filename)
            if set(f.name for f in source_dir.iterdir()) != allowed:
                raise RuntimeError("Artifact contains unregistered files")
            destination = out / "artifact-backup" / key
            shutil.copytree(source_dir, destination)
            artifact_records.append((key, checksum, profile))
    holder.stdin.write("ROLLBACK;\n\\q\n")
    holder.stdin.flush()
    holder.communicate(timeout=15)
    if holder.returncode:
        raise RuntimeError("Source read-only snapshot session failed")
    holder = None
    start_restore()
    with (out / "database.dump").open("rb") as stream, (out / "restore.log").open("wb") as log:
        run(client(name, "pg_restore", "-w", "--no-owner", "--no-privileges", "--exit-on-error", "--single-transaction"), stdin=stream, stdout=log, stderr=log)
    for key, sql in checks.items():
        actual = psql(name, sql)
        (out / ("restored-" + key + ".txt")).write_text(actual)
        if expected[key] != actual:
            raise RuntimeError("Restored " + key + " differ from the exported source snapshot")
    # Confirm locally shipped migrations match the restored checksum registry.
    migration_checks = []
    for line in expected["migrations"].splitlines():
        version, checksum = line.split("|")
        path = root / "packages/delphyr/inst/sql" / version
        if path.name != version:
            raise RuntimeError("Invalid migration path")
        observed = hashlib.sha256(path.read_bytes()).hexdigest()
        if observed != checksum:
            raise RuntimeError("Migration checksum mismatch: " + version)
        migration_checks.append(version)
    artifact_checks = []
    for key, checksum, profile in artifact_records:
        restored_dir = out / "artifact-restored" / key
        shutil.copytree(out / "artifact-backup" / key, restored_dir)
        if hashlib.sha256((restored_dir / "manifest.json").read_bytes()).hexdigest() != checksum:
            raise RuntimeError("Restored artifact registry mismatch")
        verified = subprocess.run(["Rscript", "scripts/restore-verify.R", "--artifact", str(restored_dir), profile], cwd=root, capture_output=True, text=True)
        (out / ("artifact-" + key + ".log")).write_text(verified.stdout + verified.stderr)
        lines = [line for line in verified.stdout.splitlines() if line.startswith("{")]
        proof = json.loads(lines[-1]) if lines else {"passed": False}
        if verified.returncode != 0 or not proof.get("passed") or proof.get("profile") != profile:
            raise RuntimeError("Restored artifact verification failed")
        artifact_checks.append(dict(storage_key=key, **proof))
    # The restored database in use: schema state, application role, messages
    # held before any worker starts, a member's and a staff read, and every
    # frozen snapshot of one study verified and analysed again.
    verify = subprocess.run(["Rscript", "scripts/restore-verify.R", str(socket)] + ([artifact_study] if artifact_study else []), cwd=root, capture_output=True, text=True, env=dict(os.environ, DELPHYR_DB_NAME=database, DELPHYR_DB_ADMIN="postgres"))
    (out / "function-check.log").write_text(verify.stdout + verify.stderr)
    lines = [line for line in verify.stdout.splitlines() if line.startswith("{")]
    function_check = json.loads(lines[-1]) if lines else {"passed": False}
    if verify.returncode != 0 or not function_check.get("passed"):
        raise RuntimeError("Function check of the restored database failed: " + json.dumps(function_check.get("checks", {})))
    digest = hashlib.sha256((out / "database.dump").read_bytes()).hexdigest()
    if not artifact_study:
        scope = "synthetic PostgreSQL database recovery only"
    elif artifact_records:
        scope = "synthetic PostgreSQL and selected-study artifact recovery"
    else:
        scope = "synthetic PostgreSQL database recovery; the selected study's exports were removed after their download period"
    summary = dict(status="PASS", scope=scope, backend=backend, source_container=source if backend == "docker" else None, source_database=database if backend == "docker" else source_database, source_port=None if backend == "docker" else int(source_port), postgres_version=native_version,
        restore_container=name if backend == "docker" else None, image_id=image, exported_snapshot=snapshot, dump_sha256=digest,
        compared=list(checks), table_count=len(expected["tables"].splitlines()),
        frozen_snapshot_count=len(expected["snapshots"].splitlines()), migrations_verified=migration_checks,
        artifact_study=artifact_study or None, restored_artifacts=len(artifact_records), removed_artifacts_excluded=removed_artifacts,
        function_check=function_check, artifact_checks=artifact_checks, elapsed_seconds=round(time.monotonic()-started, 3),
        exclusions=(["private artifact bytes"] if not artifact_study else ["artifacts of other studies"] + (["files of exports removed after their download period"] if removed_artifacts else [])) + ["OIDC sign-in on the restored instance", "SMTP", "production permissions", "PITR", "production RPO/RTO"])
finally:
    try:
        if holder is not None:
            try:
                holder.communicate("ROLLBACK;\n\\q\n", timeout=10)
            except (subprocess.TimeoutExpired, BrokenPipeError):
                holder.kill()
                holder.wait()
    finally:
        cleanup_restore()
# A successful receipt is written only after the owned restore server and
# socket directory have been removed. Dumps and verification evidence remain.
(out / "result.json").write_text(json.dumps(summary, indent=2) + "\n")
print("RESTORE PASS: " + str(out), flush=True)
PYTHON
