# Local operation and recovery

## Scope

This guide covers synthetic development. PostgreSQL runs at `127.0.0.1:55439`,
database `delphyr`, container `delphyr-dev-postgres`. Migrations and fixtures use
`postgres`; app and worker use `delphyr_runtime`, without ownership, DDL, deletion
or superuser rights. Loopback trust authentication is a development simplification,
not a production access architecture. Keep the database bound to loopback.

`demo_actor()` creates short-lived synthetic server identities. The separate
[authentication fixture](authentication.md) has actual local OIDC evidence for its
direct Shiny backend; stock Shiny Server OSS and production remain unqualified.
Institutional consent/retention rules and production database roles are separate.

## Start from the repository root

R with development dependencies and Docker are required. Preserve existing
containers and volumes; do not start a second database when one already runs.

```sh
Rscript scripts/bootstrap.R
# Set up or start the development database:
docker compose -f deploy/compose.dev.yaml up -d
Rscript scripts/configure-dev-role.R
Rscript scripts/start-demo.R manager 3849
```

The manager interface is at `http://127.0.0.1:3849`. In another terminal:

```sh
Rscript scripts/start-demo.R 1 3850
```

The number selects a synthetic participant; it is not authentication.
`.local/demo-fixture.rds` stores the study mapping. Restarts must use the same
database and fixture. Never reuse a fixture blindly against a different or empty
database; first check connectivity and object mappings.

The separate worker handles analysis/export jobs and approved synthetic messages
in the database sink only:

```sh
Rscript scripts/worker.R
```

Stop each process with `Ctrl+C`. Stopping an app does not delete its database.
Libraries, fixtures, logs and private artifacts are ignored by Git.

## Per-session connections and identities

The demo launcher uses a fixed actor: a `manager` or `1` instance is not independent
multi-user login. `run_app(repo_factory=..., actor_factory=...)` can resolve a
connection and trusted identity for each session. Factory-created connections
close at session end; hosts clean up directly supplied repositories.

Factories are trusted server code. Never accept browser roles or unverified
headers. The factory interface alone does not qualify an authentication deployment.
Interface languages are en/fr/de; approved study content and the round's single
consent version are not automatically translated by a language switch.

## Functional checks

```sh
Rscript scripts/check.R
DELPHYR_TEST_DB=true Rscript scripts/integration.R
Rscript scripts/demo-e2e.R
```

Database tests require explicit opt-in and create uniquely named synthetic studies.
They neither delete existing studies nor reset schemas. Concurrency tests use
independent R processes and connections with observed database locks as barriers;
random sleeps alone do not establish ordering.

## Database and artifact recovery

```sh
scripts/restore-check.sh
```

The script reads the existing synthetic source container, exports one consistent
PostgreSQL snapshot and uses it for both `pg_dump` and comparison data. Concurrent
new commits therefore do not change the expected backup contents.

It starts a uniquely named temporary PostgreSQL container using the source image,
with no Docker network or published ports. Access uses `docker exec`.
`pg_restore` runs in one transaction with error-stop enabled. Checks cover:

- Row counts and fingerprints in `identity`, `research` and `ops`.
- Columns, constraints, custom triggers and functions.
- Migration versions/checksums against local SQL files.
- Frozen snapshot IDs, hashes and JSON.

At least one frozen synthetic snapshot is required; the two-round demo creates
one. An empty schema is insufficient recovery evidence.

To include one selected study's private registered exports after the demo:

```sh
DELPHYR_RESTORE_STUDY="$(cat .checks/latest-e2e-study.txt)" scripts/restore-check.sh
```

This mode reads the artifact registry within the same snapshot, validates paths,
manifest and hashes, copies backed-up bytes into a fresh restore directory and
runs `reproduce_export()`. Other studies' artifacts are outside this evidence.

Each run creates a private `.checks/restore-*` directory containing `database.dump`,
`restore.log`, source/target comparisons and, on success, `result.json` with
`status: PASS`, image ID, dump SHA-256 and scope. Previous evidence is retained.
Only the script's own temporary restore container and volume are removed.

Without `DELPHYR_RESTORE_STUDY`, the receipt proves synthetic database recovery,
not artifact-byte recovery. With it, the selected study's registered artifacts
and offline reproduction are included. Read the exact scope in `result.json`.
OIDC, SMTP, operating configuration, keys, production roles, point-in-time recovery
and guaranteed RPO/RTO are excluded. Full operational acceptance requires separate
evidence under the [archived acceptance requirements](spec/26_ACCEPTANCE_AND_RELEASE.md).

## Limited load evidence

```sh
DELPHYR_TEST_DB=true Rscript scripts/load-check.R
```

Independent processes use runtime connections and reload confirmed saves. This
measures the local service/database path, excluding browsers, internet latency,
TLS, OIDC and assistive technology. Results apply to the measured environment;
they are not a general capacity promise.

## Failure handling

On database failure, never report an unconfirmed save as successful. Check
connection/container state, then reload responses and durable submission receipts.
Reuse idempotency keys only for identical retries; conflicts require a fresh
comparison with server state.

On export/worker failure, inspect job state and safe error code. Reclaim expired
work only through the queue; do not overwrite active leases or successful results.
Artifacts remain private and access is reauthorized on retrieval.

On restore failure, preserve the evidence directory and log. Never overwrite the
source database as a repair experiment. A real restoration requires an explicit
plan for data loss, approval and restart.
