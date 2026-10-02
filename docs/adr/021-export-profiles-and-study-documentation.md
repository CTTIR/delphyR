# ADR-021: Export profiles, study documentation and comparability decisions

Status: accepted. Date: 2026-10-02. Extends the numeric export decision in
[ADR-018](018-p0-integrity-and-qualification.md).

## Context

The first export covered one frozen numeric round and rejected any snapshot
with a free-text scale. Reports marked every author topic "not documented"
because no structured entry existed. A changed item version always interrupted
paired comparison, and the specification asks for an exportable comparability
decision (ITM-04), separated export profiles (EXP-01), a reproducible report
with its limits (EXP-02) and an audit trail with rationale (AUD-01).

## Decisions

**Profiles.** `request_study_export()` queues one of four study-level profiles;
each has its own capability and content.

| Profile | Capability | Content |
|---|---|---|
| `research_pseudonymized` | `export` | every frozen round, pseudonyms, decisions with rationale, lineage, comparability, reviewed qualitative records, report |
| `study_summary` | `analyse` or `manage` | aggregates only, small cells suppressed, report |
| `audit_restricted` | `audit` or `manage` | events, approvals and rationales |
| `contacts_restricted` | `contacts_export` | contact fields and invitation state, no pseudonyms |

`contacts_export` is a separate right that no role implies. A public release is
not produced: the request is refused, because publication needs a separate
review outside the software. The participant-feedback profile is a direct
download of the released aggregate and the person's own previous answers. The
round export of one numeric snapshot stays available unchanged.

**Free text.** A study-level research export replaces each free-text answer by
its independently released redaction, or by a withheld marker when none exists.
Statuses and ratings are unchanged, so the analysis result hash is identical;
the export records both the frozen and the exported snapshot hash and states
that the frozen hash of such a round cannot be recomputed from the export.
Unreviewed originals never leave through any profile.

**Small cells in the summary.** An item whose total is below the protocol's
display minimum loses its statistics. Where only a group is below it, the
groups of that item are omitted and the total stays, since a total alone
discloses nothing about a subgroup.

**Repeatable requests.** A finished export no longer blocks a later request for
the same input; a duplicate pending request is merged. One analysis per
requester and snapshot remains the rule, and a dead-lettered analysis can be
requested again.

**Study documentation.** `record_study_documentation()` stores author-supplied
statements for nine reporting topics as immutable versions with optimistic
version checking. Reports use the latest version; a topic without an entry
stays "not documented". A recorded reference to an approval grants nothing.

**Comparability.** `record_item_comparability()` records, with a rationale,
whether two versions of an item may be compared. The latest decision per
version pair is effective and the history is exported. Without a decision a
changed version remains not comparable. Panel members see whether the study
team assessed a revised item as comparable, not the internal rationale.

**Audit.** Events carry the recorded rationale and a short detail; see
[audit](../audit.md).

## Consequences

Migration `014_audit_documentation_exports.sql` adds the audit columns, the two
append-only tables, the job and artifact profile columns and partial unique
indexes. Download rights follow the artifact's profile and are checked again
at retrieval. Exports record git commit and lockfile hash only when the
operator provides them (`DELPHYR_GIT_COMMIT`, `DELPHYR_LOCKFILE_SHA256`; the
development worker derives both from the checkout); otherwise "not recorded".

## Validation

`test-audit-documentation.R` (60 assertions) and `test-study-export.R`
(110 assertions) on PostgreSQL, including canary strings for unreviewed text,
contacts and account references in every profile, tamper detection and
offline reproduction. `browser-governance-postgres.R` passed in Chromium under
the restricted runtime role on 2026-10-02.
