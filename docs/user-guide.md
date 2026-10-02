# Using delphyR

`delphyr` provides independent analysis and transactional study services;
`delphyrApp` provides the study interface. Start with the
[repository installation and demo instructions](../README.md). The
[implementation status](IMPLEMENTATION_STATUS.md) distinguishes implemented
features, executed checks, and remaining acceptance gates.

The interface supports English, German, and French, initially English. Protocols,
study information, and instrument wording retain their authored language. No
interface language change automatically translates scientific content.

## Analyse a frozen round offline

1. Check the complete configuration with `validate_protocol(config)` and construct
   it with `new_protocol(config)`. Invalid input reports `DEL_VALIDATION` and a field path.
2. Combine submitted responses, panel assignments, and the instrument with
   `new_snapshot()`. Set the round number explicitly; `demo_snapshot()` creates round 1.
3. Run `analyse_round(snapshot)`. Read `results` with `denominators` and `missingness`;
   `decisions` applies the configured group policy.
4. Use `compare_rounds(previous, current)` for descriptive paired comparisons.
   Changed item versions require a justified comparability mapping.
5. Prepare a draft with `prepare_feedback(analysis)` and check it with
   `validate_feedback()`. Editorial review and release remain separate steps.

The [offline vignette](../packages/delphyr/vignettes/offline.Rmd) runs this workflow
with synthetic examples. After installing built vignettes, open it with
`vignette("offline", package = "delphyr")`. No database is required.

## Interpret the counts

`n_valid` is the denominator for agreement and disagreement. Abstention, missing
responses, and inability to judge are not zero ratings. `insufficient_data`
means the prespecified minimum was not reached; `no_consensus` is a legitimate
study result.

The default protocol requires adequate results in every designated group. The
small snapshot helper explicitly uses a pooled rule, so its overall consensus
can coexist with an empty group. Consensus does not automatically establish
individual stability, retain an item, or end a study. Example thresholds are
not methodological recommendations.

## Participate in a round

Use the [local setup guide](operations.md) to start separate synthetic manager
and panel sessions. In the panel view, choose a study and assigned round, read
the stored information, and record consent explicitly. Ratings start without
a preselected value. Choose allowed special responses separately.

A settled, complete entry is saved automatically about 1.5 seconds after the
last change; **Save now** saves it immediately. Choosing a rating selects the
response type *Give a response*; choosing a special response clears the rating.
An answer without a rating or text is incomplete and is not saved. Only a
returned revision and server timestamp establish a confirmed save; until then
the field reads *Unsaved change*. Errors retain the pending value and are not
retried in the background. A revision conflict, for example from a second tab,
stops automatic saving for that field. *Load the saved response and discard my
entry* replaces the entry with the stored response; nothing is overwritten
automatically. Final submission first saves complete pending entries and is
refused while any field is unconfirmed. Successful submission returns a durable
receipt and ends editing for that round.

A disconnected browser must not imply successful saving. The tested reload
path restores the last committed value; unsaved text is not an offline backup.
The core withdrawal service stops future collection and message eligibility
while retaining prior synthetic research data under its explicit test policy.
This is not an institutional deletion policy.

## Create and set up a study

An account that the operator allowed to create studies sees **Create a new
study**. Upload the complete protocol as JSON, read the summary and the full
text, confirm, and the study is created with protocol version 1. In **Setup**,
publish the study information that participants must consent to, manage the
[rights of the study team](roles-and-rights.md) with a rationale for each
change, and review the panel by pseudonym. A changed stakeholder group applies
to rounds prepared afterwards.

## Manage rounds and protocols

Select a round and use **Review instrument and readiness**. The review shows the
study information, every item in each approved language version, enrolled
members by group, the approval history and the readiness findings. Approval is
possible only after this exact instrument was displayed and binds its content
checksum. Blocking findings prevent approval or opening; notes describe a
foreseeable consequence, for example a required group below the minimum valid n.
**Enroll eligible panel members** adds members who joined after the round was
prepared, until the round closes. A candidate that was never opened can be
withdrawn with a reason; it stays readable, frees its round number, and a
corrected candidate is prepared as a new round. A round prepared before a
protocol amendment must be withdrawn and prepared again.

Confirm every lifecycle change with a reason. Freeze a closed
round before queuing analysis or export for the separate worker. Refresh the
operation state to obtain completed results. Under **Item decisions**, record
the study team's decision for each item of the displayed analysis with its
rationale; the rule outcome alone is never a decision, and no consensus is a
legitimate result. Preview the exact feedback candidate before release, then
assign released feedback to an unopened next round. A study is completed after
its last round is finalized and every item of that round has a decision.

Protocol amendments need a complete validated configuration, an exact comparison
with the previous version, and explicit approval. They apply to future rounds;
existing instruments and snapshots retain their frozen protocol. Interface
visibility never substitutes for service-level authority checks.

## Run an exploratory free-text round

Use a protocol with a free-text dimension and prepare the first round with
open questions. After freezing it, an editor takes over the answers as original
sources in **Editorial review**, creates redactions or summaries, and links the
derived item codes to their sources; a different person releases each version.
When the feedback is created, select the released versions it should contain.
Participants see a summary labelled as a moderated summary, never as a
quotation, beside the items it led to. If a released feedback turns out to be
wrong, create a corrected version under *Correct released feedback* with a
rationale, an assessment of the effect on ratings already given, and a note
for participants. The earlier version stays unchanged; later views show the
correction and its note.

## Review sources and item provenance

Editors preserve synthetic originals and create separate redactions or summaries
with a reason. Summaries are labelled, not represented as quotations. Another
authorized person reviews the exact version before release.

Versioned themes and inclusion/exclusion coding can document dissent. Source links
connect item versions with their origin; split/merge decisions record new item
identities. A source link does not itself import an instrument item or approve a study.

## Import contacts and approve campaigns

Coordinators preview synthetic UTF-8 contact files and resolve blocking row/column
issues before approval. The whole reviewed file is imported atomically, creating
contacts and unbound drafts only. It does not create an account or assign a round.
In the Invitations section, a coordinator registers the invited person's stable
issuer/subject account with a rationale and issues a single-use invitation. The
hand-over code is displayed once and passed on privately. After verified
sign-in, the invited person checks the code, confirms explicitly and joins the
panel; consent and responses remain separate steps. See [invitations](invitations.md).

Campaigns select a round, purpose, exact study pseudonyms, and final text. Approval
requires review of that frozen preview and a reason, and may state the earliest
send time with its timezone. The preview shows the protocol's quiet hours and
reminder limits and each person's reminder count; a reminder that would exceed
a limit for anyone is refused, and you select the recipients again. Changed text
or recipients need a new preview. The worker writes only local database sink
receipts and suppresses obsolete reminders, withdrawals, and cancelled campaigns.
`sink_recorded` is not an external delivery confirmation. A `delivery_unknown`
message is never repeated automatically: under *Resolve uncertain deliveries*
you record, with a rationale, that delivery was confirmed, that it is queued
again with a possible duplicate, or that it is abandoned. See
[communications](communications.md).

## Document the study and decide comparability

In **Documentation**, study management enters the team's own statements on
authors, funding, conflicts of interest, approvals, interpretation, deviations
and data availability. Each save is a new version with a rationale; empty
topics appear in reports as not documented. In **Editorial review**, a revised
item version is paired with its earlier version only after an explicit,
reasoned comparability decision.

## Download and reproduce research exports

**Exports** offers the profiles your rights permit: pseudonymized research data
of all frozen rounds, an aggregated study summary, the history and approvals,
and, with its own separate right, the contact data. Confirm your entitlement,
request the export, check the operation and download it. The authorized
requester can download a completed private export for one day. Downloads
recheck authority, expiry, and checksums. Qualitative originals, unreleased
redactions and account mappings are excluded from every profile; a free-text
answer appears only as its released redaction. Pseudonyms remain potentially
identifying. Revoking server access cannot recall an already downloaded copy.

```sh
Rscript reproduce.R /path/to/extracted-export
```

**History** lists the recorded events of the study with their rationale for
the audit role and study management ([audit trail](audit.md)). Panel members
can download their own released feedback from the round view.

The documented core package is needed to reproduce the analysis; Quarto is not.
The manifest identifies the existing report's renderer. Read the
[reporting guide](reporting.md) for profile and rendering limits.

## Keep identities and operations separate

`run_app(repo, actor)` uses one trusted synthetic identity for a local app instance.
`actor_factory(session, repo)` resolves session-specific identities;
`repo_factory()` can create connections that close at session end. The caller
owns directly supplied connections. Identity must never come from unverified
browser fields, URLs, or headers.

Use only synthetic data in the demonstration. Local gateway checks do not qualify
the stock Shiny Server OSS transport or production operations. Institutional
approvals and real messages are separate from software tests.

## Report a reproducible problem

Include package version, function or screen, error code, and a synthetic minimal
example. Do not include credentials, tokens, real answers, or participant
identifiers in issues or logs.
