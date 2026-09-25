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

Save each field explicitly. Only a returned revision and server timestamp
establish a confirmed save. Errors retain the pending value; a revision conflict
requires reloading and reviewing the server state. Save pending changes before
final submission. Successful submission returns a durable receipt and ends
editing for that round.

A disconnected browser must not imply successful saving. The tested reload
path restores the last committed value; unsaved text is not an offline backup.
The core withdrawal service stops future collection and message eligibility
while retaining prior synthetic research data under its explicit test policy.
This is not an institutional deletion policy.

## Manage rounds and protocols

Review instruments and confirm lifecycle changes with a reason. Freeze a closed
round before queuing analysis or export for the separate worker. Refresh the
operation state to obtain completed results. Preview the exact feedback candidate
before release, then assign released feedback to an unopened next round.

Protocol amendments need a complete validated configuration, an exact comparison
with the previous version, and explicit approval. They apply to future rounds;
existing instruments and snapshots retain their frozen protocol. Interface
visibility never substitutes for service-level authority checks.

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
[Invitation services](invitations.md) use a separate, explicit approval of an
existing verified issuer/subject identity. The full invitation browser journey
remains an integration gate.

Campaigns select a round, purpose, exact study pseudonyms, and final text. Approval
requires review of that frozen preview and a reason. Changed text or recipients
need a new preview. The worker writes only local database sink receipts and
suppresses obsolete reminders, withdrawals, and cancelled campaigns.
`sink_recorded` is not an external delivery confirmation; `delivery_unknown` is
not automatically retried. See [communications](communications.md).

## Download and reproduce research exports

The authorized requester can download a completed private export. Downloads
recheck authority, expiry, and checksums. Numeric exports include frozen data,
provenance, instrument texts, and a report; qualitative originals and account
mappings are excluded. Pseudonyms remain potentially identifying. Revoking
server access cannot recall an already downloaded copy.

```sh
Rscript reproduce.R /path/to/extracted-export
```

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
