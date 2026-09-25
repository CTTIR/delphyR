# Synthetic campaigns and local outbox

Communication services write only to a PostgreSQL mail sink. They have no SMTP
client, external provider adapter or recipient addresses. `sink_recorded` means a
local test receipt, not dispatch, delivery or a read receipt.

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

## Crashes and uncertain delivery

An expired `running` claim conservatively becomes `delivery_unknown`. It is not
automatically resent or reclaimed. An expired lease holder cannot record success.
The sink is unique per message ID; that does not establish exactly-once delivery
for a future external provider.

Manual resolution of unknown delivery, provider acknowledgments, bounces, contact
management, quiet hours and automatic reminder schedules remain unimplemented.
They require separate adapter contracts, approvals and tests.

`test-communications.R` requires `DELPHYR_TEST_DB=true` and the synthetic database.
It covers approval hashes, deduplication, study boundaries, revocation, subsequent
submission, withdrawal, cancellation, immutability and expired leases. No test
sends an external message.
