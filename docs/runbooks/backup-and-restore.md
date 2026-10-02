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

The check restores into a separate temporary database and never touches the
source:

```sh
scripts/restore-check.sh
DELPHYR_RESTORE_STUDY="<study id>" scripts/restore-check.sh   # with that study's exports
```

It dumps one consistent state, restores it without a network, and compares
row counts and fingerprints of every table, the schema, migrations with their
checksums and every frozen snapshot. It then uses the restored database as
steps 4 to 8 below describe: no migration is pending, the restricted
application role is set up, the status reports the schema as current, every
message that waited for delivery is put on hold and a worker step sends
nothing, a synthetic member reads the own round, staff read the rounds, and
every frozen snapshot of one study is verified and analysed again with the
recorded result. With a study it also copies that study's exports and
recomputes their analysis. The receipt is `result.json` in a new directory
under `.checks/`. Rehearse after every migration and on the schedule the
organisation sets.

The rehearsal signs in with a synthetic development account. It does not
exercise the sign-in through the gateway on the restored instance.

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
