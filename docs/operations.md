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

The worker reports that it is alive every ten seconds under the name in
`DELPHYR_WORKER_ID` (default `worker-1`); give every worker of an installation
its own name.

Stop each process with `Ctrl+C`. Stopping an app does not delete its database.
Libraries, fixtures, logs and private artifacts are ignored by Git.

## Status, housekeeping and runbooks

```sh
Rscript scripts/status.R                    # JSON; exit 0 ready, 1 not ready, 2 no database
Rscript scripts/artifact-cleanup.R          # dry run: exports past their download period
Rscript scripts/artifact-cleanup.R --apply  # remove their files and record the time
Rscript scripts/hold-messages.R             # after a restore: count messages that waited for delivery
Rscript scripts/hold-messages.R --apply     # hold them for the coordinator's decision
```

The status lists the schema state, workers with the seconds since they were
last seen, waiting and failed background work by state and age, uncertain
deliveries and exports. It holds counts and ages only. The
[runbooks](runbooks/README.md) say what to do for each entry under `attention`
and for the incidents an operator has to expect. What the software stores, for
how long, and what it never removes by itself is described under
[retention](governance/retention.md).

## Several application processes

A process serves the sessions it holds one request at a time. The
[load qualification](load.md) gives the planning value for this hardware:
one process for every eight people rating at the same time. What several
processes need from the gateway and from storage, and what was checked with
one, two and three processes, is described under
[authentication](authentication.md#several-application-processes).

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
with no Docker network or published ports. Access uses `docker exec` and the
local socket of that instance, whose directory lies inside the private result
directory. `pg_restore` runs in one transaction with error-stop enabled.
Checks cover:

- Row counts and fingerprints in `identity`, `research` and `ops`.
- Columns, constraints, custom triggers and functions.
- Migration versions/checksums against local SQL files.
- Frozen snapshot IDs, hashes and JSON.
- The restored database in use (`scripts/restore-verify.R`): no migration is
  pending, the restricted application role is set up anew, the status reports
  the schema as current, every message that waited for delivery is put on hold
  and a worker step sends nothing, a synthetic panel member reads the own
  round and its stored answers, staff read the rounds, and every frozen
  snapshot of one study is rebuilt, verified against its hash and analysed
  again with the recorded result.

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

Without `DELPHYR_RESTORE_STUDY`, the receipt proves synthetic database recovery
and its use by the services, not artifact-byte recovery; the function check
then takes the study whose round was closed last. With it, the selected
study's registered artifacts and offline reproduction are included. Read the
exact scope in `result.json`. The sign-in through the gateway on the restored
instance, SMTP, operating configuration, keys, production roles, point-in-time
recovery and guaranteed RPO/RTO are excluded. The steps of a real restore are
in the [runbook](runbooks/backup-and-restore.md).

## Load

The [load qualification](load.md) measures 50 browser sessions that rate a
round of specification size, with the capacity found per application process.

```sh
DELPHYR_TEST_DB=true Rscript scripts/load-check.R
```

This smaller check measures the service and database path alone: independent
processes use runtime connections and reload confirmed saves, without
browsers. Results apply to the measured environment; they are not a general
capacity promise.

## Technical log and references

Application and worker write one JSON line per refused or failed operation to
standard error; see [security](security.md) for the fields and levels. Keep
that output with ordinary operational access: it contains no content, contact,
account or study identifier. A person who reports a failure quotes the
reference at the end of the message:

```sh
grep '"correlation_id":"dc8e1fe1f892"' app.log
```

The entry names the operation, the time and the condition class. A failed
background operation shows its operation ID; search for it as `"reference"` in
the worker's output. `DELPHYR_LOG_LEVEL=info` also records every successful
operation with its duration.

The worker ends with status 1 after an unexpected failure, having logged its
class. Run it under a supervisor that restarts it.

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
