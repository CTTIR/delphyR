# Synthetic campaigns and local outbox

Communication services write only to a PostgreSQL mail sink. They ship no SMTP
client and no production provider adapter. `sink_recorded` means a local test
receipt, not dispatch, delivery or a read receipt. Campaign text is final plain
text for all recipients; per-recipient placeholders are not supported.

## Exact preview and explicit approval

`prepare_campaign()` accepts a round, an explicit list of its enrollment IDs,
kind, locale, template version and final plain-text subject/body. Supported kinds
are `invitation`, `round_start`, `reminder`, `deadline_change` and `completion`.
Unresolved `{{...}}` placeholders are rejected. There are no address fields or
automatic additions to the approved audience. Locales are `en`, `fr` and `de`;
English is the default. Content is supplied by the authorized author, not translated
automatically when the interface language changes.

`preview_campaign()` returns the exact text, hash and recipient study pseudonyms,
without contacts, principal IDs or individual answers. Current `coordinate`
capability is required; the synthetic manager has it by default.

```r
campaign <- delphyr::prepare_campaign(
  repo, manager, round_id, enrollment_ids,
  kind = "reminder", subject = "Synthetic reminder",
  body = "Local functional test. No external message is sent.",
  locale = "en", template_version = 1L, command_id = "campaign-01"
)
delphyr::preview_campaign(repo, manager, campaign$id)

# Execute only after reviewing this exact preview.
delphyr::release_campaign(
  repo, manager, campaign$id, expected_hash = campaign$hash,
  reason = "Synthetic content and exact audience reviewed",
  command_id = "campaign-01-release"
)
```

The hash binds text, kind, locale, version, round and sorted recipient list.
Approval and deduplicated outbox entries commit together. Identical retries return
the earlier receipt; changed content under the same command key is rejected.
Campaigns, approvals, recipients and outbox envelopes are immutable. Changes need
a new reviewed campaign.

`cancel_campaign(repo, manager, campaign$id, reason, command_id)` stops outstanding
messages. Existing sink receipts remain.

## Separate sink worker

Trusted worker code calls `process_campaign_sink(repo, study_id)`. It does not
require a browser actor and must never be exposed as an unauthorized UI handler.
It claims at most one message with a durable lease and processes it in a second,
short transaction. Immediately before recording the sink receipt it rechecks:

- Campaign not cancelled; approving actor still has coordination rights.
- Active principal, membership and panel participation; panel right not revoked.
- No withdrawal or latest negative consent event.
- Required consent present; invitations and round-start notices may request it
  if no withdrawal exists.
- Reminders do not target an already submitted enrollment.
- Round-start, reminder and deadline-change notices require an open, unexpired round.

These checks can only reduce the approved audience. Ineligible messages become
`suppressed` with a code. Round → enrollment locking matches save/submit/close;
a completed submission prevents a subsequently admitted reminder.

A successful transaction writes one immutable `ops.message_sink` receipt and
`sink_recorded` together. Processing outcomes also appear in audit; message text
and response content are not audit object references.

## Send time, quiet hours and reminder limits

`release_campaign(..., not_before = "2026-12-01T09:00:00+01:00")` approves the
earliest send time together with the exact text and recipients. The time needs
an explicit offset, must not lie in the past and may be at most 90 days ahead;
without it the campaign is eligible at once. The approved window is immutable.

A protocol can state three optional rules under `communications`:

```json
"communications": {
  "mode": "sink", "campaign_approval_required": true, "automated_reminders_enabled": false,
  "quiet_hours": {"start": "20:00", "end": "08:00"},
  "max_reminders": 2,
  "min_reminder_interval_hours": 48
}
```

Quiet hours are clock times in the study's timezone and may pass midnight. They
are fixed with the approval; the worker does not claim a message inside them or
before its send time, and the message stays queued. `max_reminders` counts
approved, non-cancelled reminders per person and round that were not
suppressed, failed or abandoned. `min_reminder_interval_hours` is measured
from the previous reminder's send time. A reminder that would exceed either
limit for any recipient is refused as a whole with `campaign.reminder_limit`
or `campaign.reminder_interval`: the limits never shrink an approved audience
silently, the coordinator selects the recipients again. The recipient list
shows each person's reminder count. There is no automatic reminder schedule;
every reminder is an approved campaign.

## Provider adapter contract

`process_campaign_message(repo, adapter, study_id)` is the generic worker step;
`process_campaign_sink()` uses the built-in database sink. An external adapter
is created with `new_message_adapter(name, send)`. `send` receives one message
(`message_id`, `idempotency_key`, `kind`, `locale`, `subject`, `body`, `to`,
`display_name`) and returns one of:

| Return | Delivery state |
|---|---|
| `list(status = "accepted", provider_ref = "...")` | `accepted`, with the provider reference |
| `list(status = "rejected", reason = "code")` | `failed`; never retried |
| `list(status = "retry", reason = "code")` | `queued` again after a growing delay with jitter; `failed` with `retries_exhausted` after three attempts |
| an error, a timeout or anything else | `delivery_unknown` |

Claim, eligibility check and result are three short transactions; no database
transaction is open while the provider is called. Immediately before sending
the same eligibility checks as for the sink run again. The recipient address
comes from the contact of the accepted invitation; a member without a contact
is suppressed with `no_contact`. The idempotency key is the message's
deduplication key and is identical on every attempt. A provider's free text is
never stored: reasons are restricted to short codes.

No production adapter is shipped or approved. Contact addresses are restricted
by a database constraint to the reserved `.invalid` domain, repositories accept
only the development and test environments, and the adapter contract is
exercised with test doubles. Provider acknowledgments after acceptance,
bounces and complaints are not processed.

## Crashes and uncertain delivery

An expired `running` claim conservatively becomes `delivery_unknown`, and so
does an adapter call whose outcome is unknown. It is not automatically resent
or reclaimed. A lease holder whose claim expired cannot record a result. The
sink is unique per message ID; that does not establish exactly-once delivery
for an external provider.

`list_uncertain_deliveries()` shows these messages by study pseudonym, without
contacts. A coordinator resolves each one with `resolve_delivery()` and a
rationale: `confirmed_delivered` records that delivery was verified and never
sends again; `requeue` sends again and accepts a possible duplicate, after the
eligibility checks; `abandon` stops the message. Resolutions are append-only
and appear in the audit trail with their rationale.

`get_operations_status()` gives study management and coordination the counts
of jobs and messages by state, the age of the oldest waiting entry, error
codes and the number of uncertain deliveries, without any content.

`test-communications.R` and `test-delivery.R` require `DELPHYR_TEST_DB=true`
and the synthetic database. They cover approval hashes, deduplication, study
boundaries, revocation, subsequent submission, withdrawal, cancellation,
immutability, expired leases, the send time, quiet hours including windows
that pass midnight, reminder limits, the adapter contract with accepting,
rejecting, retrying, failing and malformed doubles, a lease that expires
during sending, and every resolution. No test sends an external message.
