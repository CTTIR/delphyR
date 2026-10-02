# Roles, rights and accounts

Rights are study-specific capabilities of one account. An account is the exact
pair of identity-provider issuer and subject; an email address never selects an
account. No capability implies another, and the interface only shows what the
services will also permit. Every protected service checks the current account,
membership, capability, object ownership and state again, so a revoked right
ends at the person's next protected action. Content already delivered to a
browser cannot be recalled.

## Capabilities

| Capability | Permits | Does not permit |
|---|---|---|
| `manage` | protocol amendments, study information, round lifecycle, enrollment, feedback release, item decisions, comparability, documentation, staff rights, study completion, history | individual responses, contacts, research export |
| `analyse` | frozen snapshots, analyses, feedback drafts, aggregated study summary | releasing feedback, research export |
| `export` | pseudonymized research exports and their reports | contacts, originals of free text |
| `coordinate` | panel import, invitations, campaign preparation and approval | responses, analyses |
| `edit` | qualitative originals, redactions, summaries, themes, coding, item sources | releasing an own edit, item lineage |
| `audit` | history and the audit export | responses, contacts, editorial originals, other exports |
| `contacts_export` | the contact export | everything else; never implied by another right |
| `panel` | own consent, responses, submission, feedback, withdrawal | anything of another person |

The account that creates a study receives `manage`, `analyse`, `export`,
`coordinate` and `edit`. Releasing an editorial version requires a different
person than its author. Creating studies is a right of the account itself,
granted by the operator; it cannot be chosen in the interface.

## Managing rights

In **Setup → Study team and rights**, a study manager selects a staff account or
specifies another one by issuer and subject, chooses the right, grants or
revokes it, and records a rationale. `register_staff_account()` registers an
account of a verified gateway issuer (an http or https URL) if it does not
exist; accounts of any other issuer, such as synthetic development accounts,
must already be provisioned by the operator. Registration grants nothing and a
disabled account is not reactivated. `set_capability()` records the change and
its rationale in the audit trail.

The last management right of a study cannot be revoked: the service refuses it
with a conflict, counting only active accounts. Changes of rights within one
study are serialized, so two managers cannot remove each other at the same time.

`list_study_staff()` shows staff accounts with granted and revoked rights. Panel
membership is not part of that list. `list_panel()` shows the panel only by
study pseudonym, stakeholder group and participation counts; it contains no
account reference, so staff cannot link a pseudonym to an account through the
application. Technical administrators with database access remain a separate
trust boundary.

## Verification

`test-administration.R` (PostgreSQL, 40 assertions) covers the account right to
create studies, staff listing without panel links, registration without rights,
unknown and disabled accounts, audit rationale for grants and revocations, the
last-manager rule including a disabled second manager, and the pseudonymous
panel and decision lists. Role revocation during an open session is covered by
the service suites and the local gateway check in
[authentication](authentication.md).
