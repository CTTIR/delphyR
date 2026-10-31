# Backup and restore

## What a backup contains

- The PostgreSQL database: research data, identities and contacts, audit
  trail, queue.
- The private export directory, if exports are to survive; they can also be
  produced again from the database.
- The configuration and the exact software version: commit, `renv.lock`,
  container image digests.
- Kept separately: the credentials needed for a restore. They never lie beside
  the backup.

Recovery objectives are the organisation's decision. The specification names
planning values for a small pilot, to be confirmed before use: at most 24
hours of lost data and one working day until service is restored. A restore
loses every response confirmed after the backup.

## Rehearse

The check reads an explicitly synthetic source and restores into a new private
instance. It never restores over the source. Python 3, R with the repository's
installed dependencies, and at least one frozen synthetic snapshot with a
recorded analysis are required.

On **macOS**, use native PostgreSQL 17 utilities, including `initdb`, `pg_ctl`,
`psql`, `pg_dump`, `pg_restore` and `createdb`, from one installation. The source
may be the Docker demonstration or a native development database; it must be
reachable at `127.0.0.1`. Supply its port and database explicitly:

```sh
DELPHYR_RESTORE_BACKEND=native \
DELPHYR_PG_BIN="/absolute/path/to/postgresql-17/bin" \
DELPHYR_RESTORE_SOURCE_PORT=55439 \
DELPHYR_RESTORE_SOURCE_DB=delphyr \
scripts/restore-check.sh
```

Use the actual binary directory and a plain database name (letters, digits,
underscores or hyphens, starting with a letter or underscore), not a connection
URI. `DELPHYR_RESTORE_SOURCE_USER` defaults to
`postgres`. Configure source authentication through the normal PostgreSQL
client environment or a private password file; the script does not prompt or
record passwords. Inherited host-address/service routing overrides are ignored.
The restore instance has TCP disabled and accepts connections
only through its own short Unix socket directory, created with mode `0700`
under `/tmp`. Its database is named `delphyr`, independently of the source name.
Neither a long checkout path nor a shared Docker filesystem is used for this
socket.

On a **native Linux Docker host**, the default mode uses the existing
`delphyr-dev-postgres` container and the same image for its separate restore:

```sh
scripts/restore-check.sh
```

The restore container retains `--network=none`. This mode requires a local
Linux Docker engine whose Unix socket mount is accessible to native R. It is
not a Docker Desktop/Colima socket-forwarding implementation; on macOS it exits
before creating a backup and directs the operator to native mode.

To include a study's registered export files, add these variables to either
invocation, using the private artifact directory of that source database:

```sh
DELPHYR_RESTORE_STUDY="<study UUID>" \
DELPHYR_ARTIFACT_ROOT="/absolute/private/artifact-directory" \
DELPHYR_RESTORE_BACKEND=native \
DELPHYR_PG_BIN="/absolute/path/to/postgresql-17/bin" \
DELPHYR_RESTORE_SOURCE_PORT=55439 \
DELPHYR_RESTORE_SOURCE_DB=delphyr \
scripts/restore-check.sh
```

Both modes dump one exported read-only source snapshot, restore it without
external network access, and compare row counts and fingerprints of every
table, the schema, migration checksums and every frozen snapshot. Comparison
sessions use UTC so different server time zones do not change timestamp
fingerprints. The restored services then check schema readiness, configure the restricted application
role, hold waiting messages before any worker starts, confirm that a worker
sends nothing, read a synthetic member's own round and the staff round list,
and reanalyse every frozen snapshot of one study against its recorded result.

Every copied artifact must match its registered manifest hash, profile and
member checksums, with no extra files. `research_round` artifacts are reproduced
with `reproduce_export`; `research_pseudonymized` artifacts use
`reproduce_study_export`. Summary, audit and contact profiles receive checksum
verification and explicitly report `analysis_reproduced: false`. Missing files
of a registered, unremoved export fail the check; files of exports recorded as
removed after expiry are not required.

A `result.json` receipt is written in a new private `.checks/restore-*`
directory only after verification and cleanup succeed. Dumps and evidence are
retained; the owned restore server, transient data directory and socket are
removed. If a server cannot be stopped, its data are retained and the check
fails rather than deleting a running cluster. Rehearse after migrations and
on the schedule the organisation sets.

The rehearsal uses synthetic development identities. It does not verify OIDC
sign-in, external delivery, production permissions, PITR, or production
recovery-time and data-loss objectives. A native result does not qualify the
Linux Docker transport.

## Restore after a loss

1. Stop application processes and the worker. Nobody may write to a database
   that is about to be replaced.
2. Keep the damaged database as it is. Restore into a new database or
   instance; never overwrite the source as an experiment.
3. Restore the dump with the owner role, in one transaction.
4. Install the software version that matches the backup, or a later one, and
   check: `Rscript scripts/status.R`. `schema_behind` is resolved by the
   [migration](release-and-migration.md) of the later version; `schema_ahead`
   means the software is older than the database and must not be started.
5. Apply the restricted role settings: `Rscript scripts/configure-dev-role.R`
   in development; the equivalent for the installation.
6. **Before the worker starts**, put the queue on hold:
   `Rscript scripts/hold-messages.R` counts the messages that waited for
   delivery when the backup was taken, `--apply` turns each of them into an
   uncertain delivery with the cause "was waiting when a backup was
   restored". The worker sends none of them. Under Communications the
   coordinator decides for each one with a rationale: delivery confirmed, send
   again, or abandon. A message may have been delivered between the backup and
   the loss; only the records of the lost system or of the provider can tell.
7. **Apply what happened after the backup.** Withdrawals of participation,
   revoked rights, disabled accounts, revoked invitations and any deletion
   carried out since the backup are not in it. They are applied again from the
   organisation's own records before anybody signs in.
8. Start the application, sign in with a synthetic account, read a round,
   and recompute one export.
9. Tell participants which period is affected. Responses confirmed after the
   backup are lost and have to be entered again if the round is still open.

## Responsible

Operator; study lead for step 9 and for the decision to restore at all; the
data protection contact for step 7.

## Evidence

`result.json` of the last rehearsal, the backup used with its checksum, the
number of messages put on hold and the decisions on them in the audit trail,
the list of events applied again in step 7, and the message to participants.
