# ADR-023: Exploratory rounds, reviewed feedback content and corrections

Status: accepted. Date: 2026-10-02.

## Context

The specification allows a first exploratory free-text round whose proposals
are turned into rating items by editorial work with documented provenance
(QUA-01, QUA-02, ITM-01). It requires that participants see qualitative content
only after review, that a summary is never presented as a quotation, and that a
released feedback is corrected by a new version rather than in place. The
editorial services existed, but free-text answers could not reach them, the
feedback service accepted caller-supplied text marked as reviewed, and there
was no correction path.

## Decisions

**Free text is not rated.** A free-text scale needs no anchors. Its analysis
rows report how many answers were given and carry the classification
`not_rated`; the group rule never turns it into a consensus statement, and a
comparison between rounds reports `not_rated` as well. No numeric result is
derived from text.

**Answers become sources once.** `import_round_contributions()` preserves every
submitted free-text answer of a frozen round as an immutable original source,
referenced by round, item and an opaque suffix, without a pseudonym. The
import can be repeated; a database index admits one source per answer.
Segments of one contribution are represented as separate editorial versions of
its source; items are linked to sources, several to one and one to several.

**Only released versions reach participants.** `create_feedback()` takes the
identifiers of released editorial versions and reads their text itself. Text
supplied by the caller, an unreleased version or a version of another study is
refused. A version whose source is linked to item codes is shown beside those
items; other versions appear once above the items. Summaries are labelled
"moderated summary (not a quotation)". The person's own original answer is
shown only to that person.

**Corrections are new versions.** `release_feedback_correction()` releases a
second candidate of the same analysis and records that it replaces the first,
with an internal rationale, an internal assessment of the effect on ratings
already given, and a note for participants. Later views resolve the chain of
corrections and show the note; earlier display events keep referring to the
version that was shown. The earlier feedback row is unchanged. A database
trigger requires both versions to be released, to belong to the same analysis
and the replacement not to be replaced already; corrections are immutable.

## Consequences

Migration `015_exploratory_feedback.sql` adds the index and the corrections
table. Analyses of free-text items created before this change report
`insufficient_data` in their stored form; the study export recomputes them and
flags the difference from the stored analysis. Collapsible sections of the
interface now stay open when a section is rendered again after a change.

## Validation

`test-exploratory.R` (PostgreSQL, 71 assertions) covers the protocol rule, the
`not_rated` outcome, single import without pseudonyms, refusal of injected,
unreleased and foreign text, item links, export with released text only,
correction with unchanged history, a second correction and the database guard.
`inst/qa/browser-exploratory-postgres.R` passed in Chromium on 2026-10-02 with
an editor, an independent reviewer and a panel member.
