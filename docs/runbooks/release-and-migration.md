# Release and migration

A release is a deliberate act of the operator. This runbook is the order of
steps; it does not deploy anything by itself.

## Before

1. The commit is fixed and its checks passed: `scripts/check.R`,
   `scripts/integration.R`, `scripts/migration-empty.R` (which also applies the
   newest migration to a database of the previous release that holds data),
   `scripts/demo-e2e.R`, `scripts/check-packages.R`.
2. Record commit, `renv.lock` checksum and image digests.
3. Apply the migrations to a copy of the current database, not only to an
   empty one, and run the restore rehearsal on the result
   ([backup and restore](backup-and-restore.md)).
4. Take a backup and confirm that it can be restored.
5. Choose a time without an open deadline, or tell participants. Saving is
   interrupted while processes restart.

## Migrate

1. Stop the worker after its current job. A job that is interrupted is taken
   up again after its reservation ends; a message in delivery becomes an
   uncertain delivery, so let the worker finish.
2. Stop the application processes.
3. Apply the migrations with the owner role:

   ```r
   delphyr::migrate_repository(repo)
   ```

   Migrations are numbered, forward only and recorded with their checksum.
   The call takes a lock, so two runs cannot overlap, and one run is one
   transaction: it applies completely or not at all. A migration file that was
   already applied must never be edited; a changed file is refused.
4. Apply the role settings of the application role, including the terse log
   setting ([security](../security.md)).
5. Install the new software for every application process and the worker.
   They must all be the same version. If the number of application processes
   changes, change it now and the routing of the gateway with it: a change
   while people work routes some of them to another process, where uploads
   and downloads of their open pages fail until a reload
   ([authentication](../authentication.md#several-application-processes)).

## After

1. `Rscript scripts/status.R` exits with 0 and reports the schema as current.
2. Start the application; sign in with a synthetic account; read a round and
   save a response.
3. Start the worker; request and download one export.
4. Watch the technical log and `status.R` for the first hour.

## If it fails

- A failed migration changed nothing. Start the previous software version.
- After a successful migration the previous software version may not match the
  schema: `status.R` then reports `schema_ahead` and the application must not
  be started. Going back means restoring the backup, which loses responses
  confirmed since. Prefer correcting forward with a further release.
- Checking out an older commit does not restore a database.

## Responsible

Operator; study lead for the timing.

## Evidence

Commit and digests, the rehearsal receipt, backup checksum, `status.R` output
before and after, and the times of each step.
