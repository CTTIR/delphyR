# Synthetic invitation acceptance

Imported contacts and unbound drafts remain immutable. A coordinator explicitly
approves one **existing provisioned principal**, identified by its stable issuer
and subject, for a draft. `issue_panel_invitation()` records that exact approval
and its reason. An email address never creates an account or selects a principal.
Self-registration and institutional account recovery are not implemented.

`new_invitation_token()` uses OpenSSL's cryptographic generator for 256 random
bits. Its printed form is redacted. Keep the value privately: issuance stores only
SHA-256, and neither command outcomes nor audit records contain plaintext tokens.
The caller retains the original token for a retry; the service cannot recover it.
The default lifetime is 15 minutes, with an enforced maximum of 24 hours. No
message is sent and no token is inserted into a URL by these services.

`preview_panel_invitation()` returns only study title, expiry and invitation ID
for the currently authenticated, approved issuer/subject. It makes no changes.
A scanner or GET handler must use this read-only path, never the acceptance
service. `accept_panel_invitation()` requires an explicit confirmed action and
matching current verified actor. It creates one study-specific pseudonym and
panel membership, but no consent, round enrollment or rating. Those retain their
own explicit workflow gates. Existing disabled memberships and revoked panel
rights are not silently restored. A mismatch requires coordinator review,
revocation and a new explicitly approved invitation.

Study and invitation locks serialize acceptance and revocation. Database guards
also reject expired, revoked or mismatched consumption and make approval,
revocation and acceptance records immutable. Same-study composite foreign keys
and unique accepted-draft/account constraints protect links. The exact successful
acceptance command can be retried for its receipt, including after token expiry;
a different command cannot consume the token again. Identity remains checked
on retries. Revocation cannot undo an already accepted membership; normal rights
and participation services govern subsequent access.

The PostgreSQL test suite passed 26 assertions, including two independent R
processes held behind a database lock and then released: exactly one redemption
succeeded. Other cases cover invalid tokens, missing confirmation, expiry,
revocation, disabled accounts, issuer mismatch, cross-study identifiers,
read-only preview, no consent/enrollment side effects and secret-free receipts.
The restricted runtime role also passed issuance, acceptance and retry. Run with
`DELPHYR_TEST_DB=true`; only synthetic fixtures are created.

## Account onboarding and the browser workflow

No account is created by a login. A coordinator onboards an invited person with
`register_invited_account()`: the exact identity-provider issuer and stable
subject are recorded with a rationale. The registered principal has no study
rights and sees no study until its own invitation is accepted; a disabled
account is not reactivated. `list_panel_invitations()` shows each imported draft
with its state (`unbound`, `outstanding`, `expired`, `revoked`, `accepted`) and
never returns tokens, hashes, email addresses or pseudonyms.

In the coordinator's **Invitations** section the draft, issuer, subject,
validity, rationale and an explicit confirmation are required. The application
generates the token on the server, issues the invitation and shows one
hand-over code (`invitation_code()`: study, invitation and token) exactly once.
The code is not stored and disappears when hidden or when another study is
selected. The coordinator passes it on through an approved private channel; no
message is sent by the software. An outstanding invitation can be revoked with
a reason.

A session resolved by the verified gateway shows **Accept an invitation**. The
code can be typed or supplied in the URL fragment (`#invitation=...`); a fragment
is not part of the page request, so it does not reach proxy access logs, and it
is removed from the address bar after it is read. *Check invitation* calls only
the read-only preview. Joining requires a separate checkbox and button; one
idempotency key per previewed invitation makes a lost reply retryable. Every
refusal produces the same message, whether the code is malformed, expired,
revoked, consumed or issued for another account. An identity without a
registered account receives no session and a short notice to contact the
coordinators. Demo actors without a verified issuer are not offered acceptance.

`inst/qa/browser-invitation-postgres.R` exercised this journey in Chromium with
the restricted runtime role on 2 October 2026: the unregistered notice, required
rationale and confirmation, issuance through the interface, fragment prefill and
removal, refusal of a changed code, explicit confirmation, acceptance, the
study appearing for the new panel member, refusal of a replayed code, 390-pixel
and 1280-pixel layouts, and independent database reads (one acceptance, the
imported stakeholder group, no consent, no enrollment, no plaintext token in the
database or host logs). The invitee identity in that script is produced by the
gateway adapter from a synthetic trusted request.

The real local OIDC gateway is qualified separately in
[authentication.md](authentication.md). Production and the stock Shiny Server
OSS authentication target remain unqualified. Self-registration, institutional
account recovery and automated delivery of the hand-over code are not implemented.
