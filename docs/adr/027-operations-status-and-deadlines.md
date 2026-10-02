# ADR-027: Operational status, export removal, retention inventory and deadline changes

Status: accepted. Date: 2026-10-02.

## Context

The specification asks for monitoring of the worker, the queue and exports, for
runbooks with real commands, for a dry-run report before any removal of data,
and names a change of deadline as an occasion for a message to participants.
None of these had a counterpart in the software: an operator could not see
whether a worker was alive, expired exports stayed on disk for ever, there was
no inventory of stored data by age, and a deadline could not be changed, so an
outage shortly before a deadline had no remedy.

## Decisions

- **Status without content.** `get_system_status()` reports schema state,
  worker heartbeats, background work by state and age, uncertain deliveries
  and exports as counts and ages. `ready` means the database answers and its
  schema is exactly the one of the software; everything else is `attention`.
  It names no study, account or content, so it can feed ordinary monitoring.
- **A heartbeat per worker slot.** The worker records that it is alive under a
  configured name. A restart reuses the name; no row accumulates per process.
- **Exports end.** After its download period an export's files are removed by
  an explicit operator command; the registration stays and records the time.
  A guard in the database allows exactly that one change, only after expiry.
  A missing export directory is treated as a wrong configuration, not as
  removed files.
- **Inventory, not deletion.** `get_retention_report()` counts every class of
  stored data of a study with its age and, for proposed periods, what would be
  older. The software ships no period and deletes no research or identity
  data. Removing such data stays a decision and a procedure of the
  organisation ([retention](../governance/retention.md)).
- **Deadlines can move, closes cannot.** The deadline is not part of the
  reviewed instrument. Before opening it may be any future time; an open round
  can only be extended, so that nobody loses time they were told they had.
  Extending after the deadline has passed lets an open round accept answers
  again. A closed round is not reopened: its close is the point up to which
  every confirmed answer is included. The change is recorded with its
  rationale in the round's history and the audit trail.
- **A deadline is validated before the database sees it.** A complete time
  with an explicit offset is required; a malformed text is refused as a
  validation error and never reaches a statement.

## Consequences

Migration `017_operations.sql` adds the heartbeat table, the creation and
removal times of exports and their guard. The application role needs update
rights on both tables; `scripts/configure-dev-role.R` grants them. Eleven
runbooks under `docs/runbooks/` use these commands.

## Validation

`test-operations.R` (PostgreSQL, 108 assertions) and `test-deadline.R` of the
application.
