# Audit trail

Every confirmed service command writes one append-only audit event in the same
transaction as its effect: actor, time, action, object and, where the action
requires one, the recorded rationale. A short non-sensitive detail names what
changed, for example the target state of a round, a granted or revoked right,
or an export profile. Events are never updated or deleted by the application;
the database rejects both.

## What an event contains

| Field | Content |
|---|---|
| `occurred_at` | Database time in UTC |
| `action` | Stable code, for example `transition_round` or `release_feedback` |
| `detail` | Short machine-readable detail such as `open` or `audit granted` |
| `object_ref` | Identifier of the affected object |
| `reason` | The rationale entered for that action; empty where none is required |
| `actor_kind` | `staff`, `panel` or `worker` |
| `actor_ref` | Account UUID of the staff member; the approver for worker events; empty for panel actions |

Tokens, contact data, response values and free text are not written to the
audit trail. A panel member's actions carry no account reference in the read
model or in the audit export, so the trail cannot be used to link an account
to research responses. Technical administrators with direct database access
remain a separate trust boundary; "append-only" here means protection against
ordinary application paths, not tamper-proof storage.

Events recorded before migration 014 have no `reason` or `detail`; their
rationales remain in the specific records, such as round events and protocol
amendments.

## Reading the trail

`list_audit_events(repo, actor, study_id, from, to, actions, limit)` requires
the `audit` or `manage` capability of that study and returns the newest events
first. Time limits need an explicit offset. The **History** section of the
application offers the same view with a filter by action. The `audit` capability
alone grants no access to responses, contacts, editorial originals or any other
export profile.

The `audit_restricted` export profile ([reporting](reporting.md)) delivers the
complete trail together with round events, protocol versions, campaign
approvals, staff rights, editorial releases and documentation versions.

## Verification

`test-audit-documentation.R` checks rationale and detail for transitions and
decisions, withheld panel account references, filters and their validation,
study isolation, the audit role, revocation and the immutability trigger.
`test-study-export.R` checks the audit export for the absence of response
content, contacts and panel account references. `browser-governance-postgres.R`
exercised the History section and the audit export for a manager and for an
audit-only account in Chromium.
