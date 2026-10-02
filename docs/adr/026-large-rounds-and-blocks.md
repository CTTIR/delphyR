# ADR-026: Rounds of specification size and the questionnaire in blocks

Status: accepted. Date: 2026-10-02.

## Context

The load qualification uses the largest study the specification plans for:
300 invited members, 150 items in two rating dimensions, 50 people rating at
the same time. Building that study for the first time showed that the
software, correct on small studies, did not work at this size:

- Reading a frozen snapshot took 93 seconds, analysing it 100 seconds and
  preparing a study report 200 seconds. Almost all of it was the canonical
  hash of a table of 90 000 rows.
- Every participant who opened the second round waited 92 seconds, because
  their own previous answers were taken from the complete verified snapshot.
- A background job is reserved for its worker for a limited time. The analysis
  and the export of such a round took longer than that time and could never
  record their result.
- The study report could not be rendered within five minutes.
- One participant's questionnaire of 300 fields took 49 seconds to appear.

None of these is a matter of hardware.

## Decisions

**The canonical form of a table is written directly.** The hash is defined by
a tagged JSON text. For tables that text is now assembled column by column
instead of row by row. It is byte for byte the same text, so every stored
hash stays valid; other structures still take the generic path. A table the
direct form cannot write falls back to the generic one.

**Snapshot rows are validated by column**, with the first offending row
deciding the reported path, as the row-by-row rules did.

**A participant's previous answers are read directly** from the frozen
revisions of that person. They equal that person's rows of the snapshot; the
snapshot is no longer parsed and verified for each reader.

**Reports write final markup.** Tables are written as blocks that the renderer
passes through unchanged. This is also a security correction, see
[security](../security.md).

**Jobs are reserved for ten minutes**, a wide margin over the measured
durations below.

**The questionnaire is shown in blocks.** A round with more response fields
than `block_fields` (ten by default) is presented block by block, with the
fields of one item kept together, a list of blocks, previous and next, and an
overview of answered, specially answered and open fields before submission.
Leaving a block saves its pending entries first and is refused while an entry
is incomplete or was not saved. A submission with open required fields shows
the first block that has one. Work resumes at the first block with an open
field. A round that fits one block looks as before.

**Fields share their place, not their controls.** The outputs of a field
belong to its place on the page and are reused by the field that follows
there, because the web framework inspects every output it has ever defined on
each message. The controls of a field keep an identifier of their own, so an
entry can never reach the field that follows it in that place. When a field
leaves the page its observers end and the session releases it; without that,
each visited field kept about 250 KB. About 60 KB per visited field stay with
the session until it ends.

**Ratings use the browser's own list control.** It needs no script to
initialise, which halved the time to show a block, and it is the control
assistive technology knows.

## Measurements

On the development machine, one process, study of specification size:

| Operation | Before | After |
|---|---|---|
| Read and verify a frozen snapshot (90 000 rows) | 93 s | 4.9 s |
| Analyse the round | 100 s | 5.8 s |
| Previous answers and feedback of one participant | 92 s | 0.1 s |
| Study report data | 200 s | 11 s |
| Analysis job in the worker | exceeded its reservation | 11 s |
| Research export job with rendered report | failed after 300 s | 28 s |
| Questionnaire ready for one participant | 49 s for 300 fields | 1.2 s for the first block |
| Next block | not applicable | 1.0 s |
| Memory kept per visited field until the session ends | 257 KB | about 60 KB |

Concurrent sessions are measured in the [load qualification](../load.md).

## Consequences

- Hashes written by earlier versions were recomputed with the new form for
  every snapshot, protocol and analysis in the development database; all that
  the earlier form reproduces, the new form reproduces identically.
- Element identifiers of the questionnaire changed: status, title and
  feedback of a field are addressed by their place (`slot_1`, `slot_2`, ...),
  its controls by the field.
- Reading a snapshot, creating feedback and verifying an export at download
  still take several seconds for a round of this size and run in the
  application process. Study management should not share a process with
  participants during an open round; see the load qualification.

## Validation

`test-large-rounds.R` holds the direct table form to the generic one over
adversarial text and numbers, the column-wise validation to the row-wise
rules, and a participant's previous answers to their snapshot rows.
`test-blocks.R` covers block building, navigation with pending and incomplete
entries, late entries for a previous block, submission across blocks and
resumption. `test-reporting.R` renders hostile study text.
