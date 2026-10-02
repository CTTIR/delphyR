# Queue stalled

## Recognise

- `scripts/status.R` reports `no_worker_alive`, `no_worker_registered`,
  `jobs_waiting_long` or `dead_letter_jobs`.
- An analysis or export stays "Queued" in the interface, or shows "Permanently
  failed" with a reference, which is the operation's identifier.
- The worker's log has an `error` entry for `job.…` or `worker.loop`.

## First

1. Is a worker running? `status.R` lists each worker with the seconds since it
   was last seen. A worker that stopped after an unexpected failure exits with
   status 1; its supervisor should have restarted it.
2. Search the worker's log for the reference shown in the interface:
   `grep '"reference":"<operation id>"' worker.log`. The entry names the kind of
   job and the condition class.
3. Do not change job rows by hand. Do not start many workers to "catch up":
   one job is one transaction and its order does not matter.

## What the states mean

| State | Meaning | What happens next |
|---|---|---|
| queued | Waits for a worker | Taken at the next worker step |
| running | Reserved by a worker for ten minutes | If the worker stops, another takes it after the reservation ends |
| retry_wait | A step failed | Retried, at most three attempts in total |
| dead_letter | Failed three times, or was refused for a reason a retry cannot change | Nothing; a person requests the work again |
| succeeded | Result registered | Export available for one day |

Condition classes: `DEL_FORBIDDEN` (the requester no longer holds the right),
`DEL_NOT_FOUND`, `DEL_VALIDATION` and `DEL_RENDER` (the report could not be
rendered) end a job; `DEL_STORAGE` is retried.

## Resume

1. Start the worker: `Rscript scripts/worker.R`. Check `status.R` after one
   minute: a recent heartbeat and no job waiting long.
2. For a dead-letter job the person who asked for it requests the analysis or
   export again in the interface. A failed export leaves no file and no
   registration.
3. `DEL_RENDER`: the report tool is missing or failed. Check that Quarto is
   installed for the worker; without it an export is produced with a plain
   report and says so in its manifest.
4. After a database outage see [database outage](database-outage.md).

## Responsible

Operator; the requester for a new request.

## Evidence

`status.R` output before and after, the log entries of the affected jobs by
reference, and the time the worker was restarted.
