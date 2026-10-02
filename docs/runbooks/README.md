# Runbooks

Each runbook has the same five parts: how the situation is recognised, what to
do first, how to resume safely, who is responsible and what to keep as
evidence. They describe the software as it is and were written against the
synthetic development environment. Commands run from the repository root.

They do not replace the operating organisation's own procedures. Before use
with real participants the organisation names the people behind the roles
below, confirms recovery objectives and adapts paths and service names. Fields
marked *to be named* are deliberately empty: the software does not invent them.

| Role | Responsibility | Person or team |
|---|---|---|
| Operator | Hosts, database, gateway, worker, backups | *to be named* |
| Study lead | Scientific decisions, rounds, feedback, amendments | *to be named* |
| Coordinator | Contacts, invitations, campaigns | *to be named* |
| Data protection contact | Assessment and notification of incidents involving personal data | *to be named* |

## Two tools used everywhere

`Rscript scripts/status.R` prints the operational state as JSON and exits with 0
(ready), 1 (not ready) or 2 (database unreachable). It lists counts and ages
only. `attention` names what a person should look at:

| Entry | Meaning |
|---|---|
| `database_unreachable` | No connection; see [database outage](database-outage.md) |
| `schema_behind`, `schema_ahead`, `schema_changed` | Database and software do not match; see [release and migration](release-and-migration.md) |
| `no_worker_registered`, `no_worker_alive` | No worker heartbeat in the last minute; see [queue stalled](queue-stalled.md) |
| `dead_letter_jobs`, `jobs_waiting_long` | Background work failed or waits; see [queue stalled](queue-stalled.md) |
| `uncertain_deliveries` | A coordinator has to resolve a delivery; see [invitation not received](invitation-not-received.md) |
| `expired_exports_not_removed` | Run the export cleanup; see [disk full](disk-full.md) |

The technical log is the standard error output of every application and worker
process, one JSON line per refused or failed operation
([security](../security.md)). A person who reports a failure quotes the
reference at the end of the message; `grep` finds its line. The log never
contains content, contacts, accounts or study identifiers, so it can be shared
with the people who operate the system.

## Runbooks

- [Database outage](database-outage.md)
- [Authentication provider outage](authentication-outage.md)
- [Invitation or message not received](invitation-not-received.md)
- [Queue stalled](queue-stalled.md)
- [Disk full](disk-full.md)
- [Certificate expired](certificate-expired.md)
- [Round closed by mistake](round-closed-by-mistake.md)
- [Feedback released by mistake](feedback-released-by-mistake.md)
- [Backup and restore](backup-and-restore.md)
- [Security incident](security-incident.md)
- [Release and migration](release-and-migration.md)
