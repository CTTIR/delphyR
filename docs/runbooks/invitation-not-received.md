# Invitation or message not received

The software sends no e-mail by itself. In this version a campaign is recorded
in a local sink, and an invitation is a one-time code that the coordinator
hands over through a channel of the organisation's choice. A production
message provider is not part of the software.

## Recognise

- A person reports that no invitation code or message arrived.
- `scripts/status.R` reports `uncertain_deliveries`, or messages in state
  `failed` or long in state `queued`.
- Under *Communications → Resolve uncertain deliveries* a number other than 0.

## First

1. **Invitation code.** Under *Invitations* find the contact by its external
   reference. The states are: not issued, outstanding, expired, revoked,
   accepted. A code is shown once, when it is issued, and is valid for at most
   24 hours. It cannot be shown again.
2. **Campaign message.** Under *Communications* open the campaign and read the
   recipient's state: queued (waits for its send time or for the end of quiet
   hours), recorded or accepted, suppressed with a reason (already submitted,
   consent withdrawn, round not open, no contact), failed, or uncertain.
3. Never read a code or a message text to somebody whose identity is not
   established, and never put a code into a ticket or a log.

## Resume

- **Expired or lost code:** revoke the outstanding invitation with a rationale
  and issue a new one for the same account. The old code is void.
- **Wrong account:** the invitation is bound to exactly one registered
  account. Register the right account and issue a new invitation; do not ask
  the person to use somebody else's account.
- **Uncertain delivery:** it is never repeated automatically. The coordinator
  decides with a rationale: confirmed as delivered, send again and accept a
  possible duplicate, or abandon.
- **Suppressed message:** the reason is the answer. A suppressed message is not
  sent later; prepare a new campaign if the reason no longer applies.
- **Queued for long:** check the worker ([queue stalled](queue-stalled.md)) and
  the approved send time and quiet hours of the campaign.

## Responsible

Coordinator; operator for the worker.

## Evidence

The audit trail records issue, revocation, acceptance, campaign approval and
every delivery decision with its rationale and time. Note the external
reference of the contact, never the address, in an incident record.
