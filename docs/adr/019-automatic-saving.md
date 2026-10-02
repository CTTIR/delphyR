# ADR-019: Automatic saving with per-field commit confirmation

Status: accepted. Date: 2026-10-02. Supersedes the explicit-save limitation in
[ADR-018](018-p0-integrity-and-qualification.md).

## Context

Requirement RSP-04 and the interface specification ask for saving after a short
debounce, with the states unsaved, saved, failed and conflict, and without a
success indication that precedes the database commit. The first interface saved
only on an explicit button.

## Decision

Each response field saves itself once its entry has been unchanged for
`autosave_ms` (default 1500 ms) and is complete. The confirmation text is produced
only from the returned revision and server timestamp. The explicit **Save now**
button remains for immediate saving and keyboard use; `autosave_ms = 0` keeps
explicit saving only.

- An entry that equals the stored response creates no revision.
- Choosing a rating selects *Give a response*; choosing a special response clears
  the rating. The stored pair is therefore always the pair on screen.
- An identical retry reuses its idempotency key, so a save whose reply was lost
  returns the original receipt instead of a false conflict.
- A failed save is not retried in the background. It is retried when the entry
  changes or when the person saves explicitly.
- A revision conflict or a closed round stops automatic attempts for that field.
  The stored response replaces the entry only after an explicit action, and
  nothing is saved automatically until the form shows the loaded state.
- Submission and loading another round first save complete pending entries and
  are refused while any field remains unconfirmed.

The save runs synchronously in the session, so a separate "saving" state is not
displayed: the field reads *Unsaved change* until the commit is confirmed.
Pending entries are not written to browser storage. A lost connection ends the
session; a reload shows the last committed responses.

## Consequences

Service contracts are unchanged: optimistic revisions, the shared lock order and
content-bound command retries still decide every write. Legacy browser checks
that verify pending and explicitly saved states run their host with
`autosave_ms = 0`.

## Validation

Module tests cover the debounce, incomplete entries, special responses, key
reuse, conflict, closed round, locked enrollment and submission with a pending
entry. `inst/qa/browser-autosave-postgres.R` passed in Chromium against PostgreSQL
under the restricted runtime role on 2026-10-02, including a two-tab conflict,
connection loss with reload, and submission of a pending entry.
