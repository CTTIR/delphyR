# Authentication provider outage

## Recognise

- Nobody can sign in: the gateway redirects to the identity provider and the
  provider does not answer, or the gateway reports an error after sign-in.
- People who were already signed in keep working for at most the configured
  session lifetime (15 minutes by default). After that every action fails with
  a reference, and the technical log shows `"error_class":"DEL_UNAUTHORIZED"`
  with `"error_path":"session"`.
- New sessions that reach the application without a verified identity are
  closed; the log shows `"operation":"session_identity"` with the path
  `authentication.peer`, `authentication.gateway`, `authentication.subject` or
  `authentication.principal`. The last one means the provider works and the
  account is not registered or is disabled, which is not an outage.

## First

1. Confirm with the provider's own status that it is the provider and not the
   gateway. The application never talks to the provider itself.
2. Do not weaken the gateway: no shared account, no bypass of the header
   check, no direct access to the application port.
3. Tell the study lead. Saved responses are unaffected.

## Resume

1. When sign-in works again, sign in with a synthetic account and check that
   the study selection shows the expected study.
2. Participants sign in again and see their last saved responses.
3. If the outage ran into the deadline of an open round, see step 5 of
   [database outage](database-outage.md).
4. If accounts were disabled or changed at the provider during the outage, the
   coordinator reviews outstanding invitations: an invitation is bound to one
   account and expires after at most 24 hours.

## Responsible

Operator together with the identity provider's contact; study lead for
deadlines.

## Evidence

Start and end, the provider's incident reference, the `session_identity`
entries of the technical log by path, and the decision about deadlines.
