# ADR-028: Sessions, several application processes, and the use of a restored database

Status: accepted. Date: 2026-10-03.

## Context

Three acceptance gates could not be closed with what existed.

- **Performance.** The load qualification showed that one application process
  serves about eight people rating at the same time within the target
  ([load](../load.md)). Fifty need several processes behind the gateway, which
  had only ever been run with one.
- **Identity.** The specification asks for evidence of invitation acceptance,
  session renewal, the maximum lifetime of a session, logout and revoked
  rights through a real gateway. The gateway run covered none of the first
  four, and the application had no way to sign out.
- **Operation.** A restore was shown to reproduce every table, but not that
  the restored database works, and nothing kept a restarted worker from
  sending messages that were waiting when the backup was taken.

## Decisions

- **One process per account.** The gateway routes by the verified subject, so
  that a session, its uploads and its downloads meet in one process. No
  session state is shared between processes; they share the database and one
  private export directory.
- **A process answers for its page from its start.** The web framework
  registers the scripts and styles of a page only when it first renders that
  page. A page delivered by one process whose files were asked of a process
  that had just started stayed blank; this happened in the first run with two
  processes. Each process now renders its page once at start.
- **An expired sign-in is named.** The identity of a session ends after a
  configured time. The message then says so and asks for a reload, instead of
  the general failure message. Nothing is retried; confirmed answers are kept.
- **Signing out ends the account's sessions in the process.** With routing by
  account these are all of its open pages. The link then follows a configured
  address of the gateway, which is responsible for its own session and that of
  the identity provider. The application keeps no list of sessions outside
  the process and does not claim a logout that the gateway did not perform.
- **A cancelled step is not a failure.** An input that is not ready cancels a
  step silently. Such a cancellation could reach the failure message of a
  section and the technical log; it is now passed on as what it is.
- **After a restore, waiting messages need a decision.** A message that was
  queued or in flight at the time of a backup may have been delivered before
  the loss. `hold_pending_messages()` turns each into an uncertain delivery
  with its own cause. This reuses the existing rule that an uncertain delivery
  is never repeated without a documented human decision.
- **The rehearsal uses what it restored.** After comparing every table, the
  restore check connects the services to the restored instance through its
  local socket, which keeps that instance without a network: schema state,
  application role, the hold of waiting messages, a member's and a staff
  read, and the verification and repeated analysis of every frozen snapshot
  of one study.

## Consequences

- `run_app()` has the argument `sign_out_url`; without it nothing changes.
- A change of the set of processes while people work routes some accounts to
  another process, where uploads and downloads of their open pages fail until
  a reload; it belongs in a maintenance window. What the identity provider
  withdraws reaches an open page when its identity ends, not before.
- The restore rehearsal needs a repository path short enough for a local
  socket and takes longer by the function check.
- The fixture of the gateway gained a shared export volume, further synthetic
  accounts for the routing check and a configuration with short lifetimes.

## Validation

`deploy/auth/verify-browser.py` with one, two and three processes and with
`--lifetime` ([authentication](../authentication.md)); `test-session-identity.R`
and `test-security.R` of the application; `test-delivery.R` (hold after a
restore); `scripts/restore-check.sh` with `scripts/restore-verify.R`.
