# ADR-024: Send windows, reminder limits and uncertain delivery

Status: accepted. Date: 2026-10-02.

## Context

Requirement COM-01 and the communications specification ask for an approved
time, reminder limits with quiet hours, a provider contract with idempotency
keys, and a `delivery_unknown` state that is never resent blindly but can be
resolved by a person who sees the uncertainty. The first implementation
released campaigns immediately into a database sink and left an expired claim
uncertain without any way to resolve it.

## Decisions

- **Approved window.** The earliest send time is part of the approval command
  and stored immutably with the quiet hours and timezone valid at approval.
  The worker claims a message only inside the window. Nothing is sent early
  because a rule changed later.
- **Protocol rules are optional and conservative.** `quiet_hours`,
  `max_reminders` and `min_reminder_interval_hours` are optional protocol
  fields. Absent fields impose no limit beyond explicit approval. Development
  values are examples and are never applied as hidden defaults.
- **Limits refuse, they do not filter.** A reminder that would exceed a limit
  for any recipient is refused as a whole; the approved audience is exactly
  what was previewed. Suppressed, failed and abandoned reminders do not count.
- **No automatic reminders.** `automated_reminders_enabled` must stay false;
  every reminder is a previewed and approved campaign.
- **Adapter contract.** Three short transactions surround the provider call.
  The idempotency key is constant per message. Transient failures retry at
  most three times with a growing delay; permanent refusals stop; anything
  unclear is `delivery_unknown`.
- **Human resolution.** An uncertain delivery is resolved only by a
  coordinator with a rationale: confirmed, queued again with an accepted
  duplicate risk, or abandoned. Resolutions are append-only.
- **No production provider.** The contract is tested with doubles. Real
  dispatch needs an approved sender, a reviewed adapter and a contact policy;
  until then addresses are constrained to `.invalid`.

## Consequences

Migration `016_communication_schedules.sql` adds the schedule and resolution
tables, the delivery states `accepted`, `failed`, `resolved_delivered` and
`abandoned`, and a retry time. Campaigns approved before the migration have no
window and stay immediately eligible.

## Validation

`test-delivery.R` (PostgreSQL, 94 assertions) and the existing
`test-communications.R` (38 assertions).
`inst/qa/browser-communications-postgres.R` passed in Chromium on 2026-10-02.
