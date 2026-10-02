# ADR-022: Study administration in the interface

Status: accepted. Date: 2026-10-02.

## Context

The end-to-end scenario of the specification expects every step of a study to
be possible in the interface without database intervention. Creating a study,
publishing study information, managing staff rights, reviewing the panel and
recording item decisions existed only as R services. The first complete browser
run also showed that sections of one session kept stale lists after another
section changed the study.

## Decision

- **Creation.** An account with the operator-granted creation right uploads a
  complete protocol. It is validated, summarized and shown in full; a separate
  confirmation creates the study with protocol version 1. An invalid protocol
  reports the field in question. Production protocols remain rejected by the
  validator.
- **Setup.** One section holds study information versions, staff rights and
  the pseudonymous panel, each change with a rationale and confirmation.
- **Rights.** See [roles and rights](../roles-and-rights.md): exact accounts,
  registration without rights, audit rationale, and a last-manager rule.
- **Decisions.** Item decisions are recorded against the displayed analysis of
  the selected round, with disposition, rationale and confirmation, and listed
  per round. The rule outcome is shown separately and is never a decision.
- **Change signal.** A confirmed change in one section signals the others in
  the same session to read their lists again (rounds, drafts, study
  information, rights and offered export profiles). Typed text is kept. The
  signal is a convenience; services still check every action.
- **Sessions.** `run_app(repo_factory, actor_factory)` resolves a separate
  identity and database connection for each browser session; the fixed-actor
  form remains for local demonstrations.

## Consequences

Round preparation validates against the current protocol and study information
instead of the state read when the section was opened. Empty lists render as
empty outputs rather than errors.

## Validation

Module tests cover each form's required rationale and confirmation, the bound
upload, hidden sections without the right and the change signal.
`inst/qa/browser-study-journey-postgres.R` conducted a complete two-round study
in Chromium on 2026-10-02 with five separate identities on one host under the
restricted runtime role.
