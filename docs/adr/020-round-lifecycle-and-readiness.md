# ADR-020: Round readiness, withdrawal of unopened candidates and enrollment

Status: accepted. Date: 2026-10-02.

## Context

Requirement STU-02 asks that a study cannot be opened while mandatory elements
are missing, with a concrete list of findings. The state-machine specification
lets an approved, unopened round return to draft, and requires an active
protocol, a time window, enrollments and a matching consent before opening.
Three gaps existed: a manager approved a content hash without seeing the
instrument; a prepared candidate could neither be corrected nor removed, so a
mistaken candidate blocked both the next round and study completion; and a
panel member who joined after preparation was never enrolled.

## Decision

**Readiness.** `get_round_readiness()` returns a `delphyr_validation` with every
finding. Errors are: study not open for collection, protocol superseded or no
longer valid, study information outside the protocol languages, no items, an
unknown dimension or scale, a missing language version, a passed deadline and
no enrolled eligible member. `transition_round()` refuses approval while any
content error exists and refuses opening while any error exists
(`DEL_VALIDATION`, path `round.readiness:<codes>`). Warnings do not block: a
required group or the panel below the minimum valid n, eligible members not yet
enrolled, and no assigned feedback in a later round. They state a foreseeable
consequence and leave the decision to the study team.

**Withdrawal instead of reset.** A round in `draft`, `review` or `approved` can
move to the final state `cancelled` with a reason. Its instrument, enrollments
and approval events remain readable; nothing is deleted or edited in place. A
cancelled candidate no longer occupies its round number, does not block the
next round or study completion, does not bind item versions, is hidden from
panel members and suppresses its pending messages. A corrected candidate is
prepared as a new round. This replaces the specified reset to draft: the old
approval is invalid and historically retained, and the application role needs
no right to delete instrument rows. Database triggers make cancellation final
and impossible after opening.

**Enrollment.** Preparation no longer requires panel members; opening does.
`enroll_panel()` enrolls currently eligible members under the round's protocol
entry policy until the round closes, using each member's current stakeholder
group. Feedback already assigned to an unopened round is assigned to the new
enrollments as well. An open round with assigned feedback accepts no further
enrollment, so that everyone rating in a round has the same information. A
database trigger rejects enrollments once a round is closed.

**Exact review.** `get_round_instrument()` returns the round's items in every
language version, study information, protocol version, enrollment counts and
approval events. The interface approves only after this content was displayed
for the selected round and passes the displayed hash to the service.

## Consequences

Migration `013_round_lifecycle.sql` adds the state, a partial unique index on
active round numbers and two guard triggers. A round prepared before a protocol
amendment must be withdrawn and prepared again; opening it would collect data
under a superseded protocol. Round lists can show a withdrawn and an active
candidate with the same number.

## Validation

`tests/testthat/test-round-lifecycle.R` (PostgreSQL, 72 assertions) covers the
findings, blocked transitions, withdrawal and its database guards, completion
after withdrawal, enrollment before and during an open round, the entry policy,
shared feedback assignment, the instrument review and an enrollment queued
behind a committed close. `inst/qa/browser-management-postgres.R` passed in
Chromium under the restricted runtime role on 2026-10-02.
