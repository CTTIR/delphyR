#!/usr/bin/env bash
set -euo pipefail
# Non-destructive P0 recovery exercise for the existing synthetic development DB.
# All source reads share one exported PostgreSQL snapshot. No production endpoint.
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import datetime
import hashlib
import json
import os
import subprocess
import shutil
import tempfile
import time
import uuid

os.umask(0o077)
source = "delphyr-dev-postgres"
database = "delphyr"
root = Path.cwd()
(root / ".checks").mkdir(exist_ok=True)
out = Path(tempfile.mkdtemp(prefix="restore-" + datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-", dir=root / ".checks"))
name = "delphyr-restore-" + uuid.uuid4().hex[:12]
created = False
holder = None
started = time.monotonic()

def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def psql(container, sql):
    return run(["docker", "exec", "-i", container, "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", database], input=sql, text=True, capture_output=True).stdout

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
    image = run(["docker", "inspect", "--format", "{{.Image}}", source], text=True, capture_output=True).stdout.strip()
    holder = subprocess.Popen(["docker", "exec", "-i", source, "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", database], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    holder.stdin.write("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\nSELECT pg_export_snapshot();\n")
    holder.stdin.flush()
    snapshot = holder.stdout.readline().strip()
    if not snapshot or any(c not in "0123456789ABCDEFabcdef-" for c in snapshot):
        raise RuntimeError("Could not acquire a valid exported source snapshot")
    prefix = "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SET TRANSACTION SNAPSHOT '" + snapshot + "';\n"
    artifact_study = os.environ.get("DELPHYR_RESTORE_STUDY", "")
    if artifact_study:
        artifact_study = str(uuid.UUID(artifact_study))
    checks = {"tables": counts_sql, "migrations": migrations_sql, "snapshots": snapshots_sql, "schema": schema_sql}
    if artifact_study:
        checks["artifacts"] = "SELECT id,storage_key,checksum FROM ops.artifacts WHERE study_id='" + artifact_study + "' ORDER BY id;\n"
    expected = {}
    for key, sql in checks.items():
        value = psql(source, prefix + sql + "COMMIT;\n")
        expected[key] = value
        (out / ("source-" + key + ".txt")).write_text(value)
    if not expected["snapshots"].strip():
        raise RuntimeError("Recovery proof requires at least one frozen synthetic snapshot")
    with (out / "database.dump").open("wb") as stream:
        run(["docker", "exec", source, "pg_dump", "-U", "postgres", "-d", database,
             "--format=custom", "--no-owner", "--no-privileges", "--snapshot=" + snapshot], stdout=stream)
    artifact_records = []
    if artifact_study:
        if not expected["artifacts"].strip():
            raise RuntimeError("Selected synthetic study has no registered artifacts")
        artifact_root = (root / ".artifacts").resolve(strict=True)
        for row in expected["artifacts"].splitlines():
            artifact_id, key, checksum = row.split("|")
            key = str(uuid.UUID(key))
            source_dir = artifact_root / key
            if source_dir.is_symlink() or source_dir.resolve(strict=True).parent != artifact_root:
                raise RuntimeError("Unsafe artifact directory")
            manifest_path = source_dir / "manifest.json"
            if manifest_path.is_symlink() or hashlib.sha256(manifest_path.read_bytes()).hexdigest() != checksum:
                raise RuntimeError("Artifact manifest does not match registry")
            manifest = json.loads(manifest_path.read_text())
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
            artifact_records.append((key, checksum))
    holder.stdin.write("ROLLBACK;\n\\q\n")
    holder.stdin.flush()
    holder.communicate(timeout=15)
    if holder.returncode:
        raise RuntimeError("Source read-only snapshot session failed")
    holder = None
    # No host port and no network: restore access is only via docker exec/local socket.
    run(["docker", "run", "--detach", "--name", name, "--network=none",
         "--label", "delphyr.purpose=synthetic-restore-check", "--env", "POSTGRES_DB=" + database,
         "--env", "POSTGRES_HOST_AUTH_METHOD=trust", image], capture_output=True)
    created = True
    for _ in range(120):
        ready = subprocess.run(["docker", "exec", name, "pg_isready", "-h", "127.0.0.1", "-U", "postgres", "-d", database], capture_output=True)
        if ready.returncode == 0:
            break
        time.sleep(0.25)
    else:
        raise RuntimeError("Fresh isolated restore database did not become ready")
    with (out / "database.dump").open("rb") as stream, (out / "restore.log").open("wb") as log:
        run(["docker", "exec", "-i", name, "pg_restore", "-U", "postgres", "-d", database,
             "--no-owner", "--no-privileges", "--exit-on-error", "--single-transaction"], stdin=stream, stdout=log, stderr=log)
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
    for key, checksum in artifact_records:
        restored_dir = out / "artifact-restored" / key
        shutil.copytree(out / "artifact-backup" / key, restored_dir)
        if hashlib.sha256((restored_dir / "manifest.json").read_bytes()).hexdigest() != checksum:
            raise RuntimeError("Restored artifact registry mismatch")
        code = '.libPaths(c(normalizePath(".R-library"),.libPaths()));pkgload::load_all("packages/delphyr",quiet=TRUE);delphyr::reproduce_export(commandArgs(TRUE)[1]);cat("OFFLINE RESTORED ARTIFACT PASS\\n")'
        with (out / ("artifact-" + key + ".log")).open("wb") as log:
            run(["Rscript", "-e", code, str(restored_dir)], cwd=root, stdout=log, stderr=log)
    digest = hashlib.sha256((out / "database.dump").read_bytes()).hexdigest()
    summary = dict(status="PASS", scope=("synthetic PostgreSQL and selected-study artifact recovery" if artifact_study else "synthetic PostgreSQL database recovery only"), source_container=source,
        restore_container=name, image_id=image, exported_snapshot=snapshot, dump_sha256=digest,
        compared=list(checks), table_count=len(expected["tables"].splitlines()),
        frozen_snapshot_count=len(expected["snapshots"].splitlines()), migrations_verified=migration_checks,
        artifact_study=artifact_study or None, restored_artifacts=len(artifact_records),
        elapsed_seconds=round(time.monotonic()-started, 3),
        exclusions=(["private artifact bytes"] if not artifact_study else ["artifacts of other studies"]) + ["OIDC", "SMTP", "production permissions", "PITR", "production RPO/RTO"])
    (out / "result.json").write_text(json.dumps(summary, indent=2) + "\n")
    print("RESTORE PASS: " + str(out), flush=True)
finally:
    if holder is not None:
        try:
            holder.communicate("ROLLBACK;\n\\q\n", timeout=10)
        except (subprocess.TimeoutExpired, BrokenPipeError):
            holder.kill()
            holder.wait()
    if created:
        run(["docker", "rm", "--force", "--volumes", name], capture_output=True)
PY
