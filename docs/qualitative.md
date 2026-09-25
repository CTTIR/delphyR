# Qualitative provenance in the synthetic development profile

The package provides a restricted editorial service layer. It preserves original
contributions, separate redactions and summaries, independent review, versioned
theme definitions, coding decisions, item-source links, and complete split/merge
events. It is not a complete qualitative-analysis editor or a qualified production
workflow. All development examples must remain synthetic.

## Editorial sequence

1. `record_qualitative_source()` stores exact original text with an explicit
   provenance reference. An optional response revision must belong to the same
   study and contain that exact free-text answer. Originals cannot be updated or
   deleted through ordinary SQL operations.
2. `redact_qualitative_source()` creates a new object with an explicit explanation
   of omissions or reformulation. `kind = "summary"` distinguishes paraphrases
   from redactions; a summary must never be presented as a quotation. Every
   correction creates a further object and preserves the earlier versions.
3. `release_qualitative_edit()` requires the exact reviewed hash, a rationale, and
   a manager different from the editing principal. The immutable release records
   who approved precisely which version. Review should explicitly consider
   identifying details, third parties, and preservation of minority views.
4. `create_qualitative_theme()` records a versioned definition. Calling
   `code_qualitative_source()` records an include/exclude decision and rationale
   for an original source and exact theme version. Several themes can reference
   one source. Contradictory decisions remain visible and require human
   resolution; they are not silently replaced or averaged.

Coding rows count decisions. Source rows count contributions. Neither count is a
participant count. This layer does not impose a qualitative research method,
resolve coder disagreements, perform automatic summarization, or publish text to
participants. Segmentation, coding adjudication, and a full editorial interface
remain separate work.

## Item derivation

`link_item_source()` links an existing or proposed item code and version to an
original source with a reason. Several sources can support an item; one source can
support several items. Proposed references do not create questionnaire items or
approve their inclusion. The read model reports `imported` when a matching code
and version actually appears in the study's round-item records.

`record_item_lineage()` records a complete split (one parent, at least two new
children) or merge (at least two parents, one new child). Parent versions must
already occur in an imported instrument or an earlier lineage event. Children
must have new semantic codes. The service serializes lineage decisions within a
study and rejects identity reuse and cycles. The database enforces same-study
references, immutable events and edges, and the declared complete edge counts at
transaction commit. Historical parents remain intact. Item revision with an
explicit comparability decision is not implemented by this split/merge API.

## Access and export boundaries

All source, redaction, theme and coding operations require current `edit` rights.
Release and lineage decisions require current `manage` rights. Writes use the
shared transactional command receipts and recheck rights after waiting on command
locks. Reusing a command key with changed content is a conflict.

`get_qualitative_provenance()` requires `edit` rights and returns editorial tables,
including originals. `export = TRUE` additionally requires `export`, excludes
original text and unreleased redactions, and retains immutable review and lineage
references. These are restricted research tables, not a participant feedback
payload. Provenance references, coding rationales and editorial identities remain
potentially sensitive. This function does not certify that the entire export has
undergone disclosure review and does not bypass the separate free-text artifact
export restriction.

Read and export access is audited without copying contribution text into the
audit log. No function exposes originals to a panel-only account. SQL constraints
also reject cross-study source, theme, item and release references. Migration
owners remain privileged; a service-layer contract does not constrain a database
administrator who can disable triggers.

## Application hooks and verification

An editor can use the source/edit/theme/coding tables to build review queues.
A manager can review an edit and submit its displayed hash to the release service.
The lineage service accepts `parents` and `children` data frames with
`item_code` and `item_version`. A released redaction is not automatically included
in existing feedback releases: explicit integration must bind the release UUID
and exact reviewed hash before displaying it to participants.

Opt-in tests in `test-qualitative.R` exercise durable command replay, content
conflicts, separate original and edited records, independent review, unreleased
text exclusion, capability revocation, multiple theme assignments, source/item
links, split/merge integrity, and cross-study rejection. They require the isolated
PostgreSQL development fixture with `DELPHYR_TEST_DB=true`; they do not use real
participant data.
