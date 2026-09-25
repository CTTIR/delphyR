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

These are service contracts, not a complete invitation user interface or email
campaign integration. The real local OIDC gateway is qualified separately in
[authentication.md](authentication.md). Invitation acceptance through that browser
path remains an end-to-end gate until the confirmation UI is wired and tested.
Production and the stock Shiny Server OSS authentication target remain unqualified.
