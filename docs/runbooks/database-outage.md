# Database outage

## Recognise

- `Rscript scripts/status.R` exits with 2 and reports `database_unreachable`.
- Participants see "Action failed … No success was confirmed" with a
  reference; no field shows "Saved". The technical log has `"outcome":"failed"`
  with `"error_class":"DEL_STORAGE"` for many operations at once.
- The worker has exited with status 1 after logging `worker.loop`.

## First

1. Do not restart the database blindly. Check the container or service state,
   free disk space ([disk full](disk-full.md)) and the database log.
2. Tell the study lead and the coordinator that saving is interrupted. No
   message can be sent by the software while the database is down.
3. Leave application processes running. A response that was not saved stays
   visible on the participant's screen until the page is reloaded; text should
   be kept elsewhere before a reload.

Nothing is lost that was shown as saved: a save is confirmed only after its
transaction committed.

## Resume

1. Bring the database back. `Rscript scripts/status.R` must exit with 0 and
   report `"state":"current"` for the schema.
2. Restart application processes: each session holds its own connection, and a
   connection lost during the outage does not recover within a session.
   Participants reload the page and sign in again; they see their last saved
   responses.
3. Start the worker. Jobs that were running are taken up again after their
   lease of ten minutes, at most three times. A message that was being
   delivered becomes an uncertain delivery and waits for a coordinator
   ([invitation not received](invitation-not-received.md)).
4. Check one synthetic account: open a round, save a response, reload.
5. If the outage ran into the deadline of an open round, the study lead can
   move the deadline to a later time under *Rounds and analysis → Change the deadline*,
   with a rationale. A round that was closed is not reopened
   ([round closed by mistake](round-closed-by-mistake.md)).

If the database cannot be brought back with its data, continue with
[backup and restore](backup-and-restore.md). A restore loses every response
confirmed after the backup; that is a decision for the study lead and the
operator together.

## Responsible

Operator; study lead for deadlines and for a restore.

## Evidence

Start and end of the outage, the output of `scripts/status.R` before and after,
the relevant lines of the database log, the number of failed operations in the
technical log, and the decision about deadlines.
