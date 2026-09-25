# delphyR specification archive, version 1.0

This directory preserves the original implementation specification for the
Delphi study platform. The archived documents are mostly German; API, code,
and database identifiers are English. This English index is maintained for
current readers. It does not rewrite the historical requirements.

## Start here

- [Reading order and document map](00_START_HERE.md).
- [Complete implementation brief](27_ORCHESTRATOR_PROMPT.md).
- [Study protocol template](24_STUDY_PROTOCOL_TEMPLATE.md).
- [Roadmap](22_IMPLEMENTATION_ROADMAP.md), [work packages](28_WORK_PACKETS.md),
  and [acceptance criteria](26_ACCEPTANCE_AND_RELEASE.md).
- [Original structural validation report](VALIDATION_REPORT.md) and
  [sources and comparators](30_SOURCES_AND_COMPARATORS.md).

There are 33 numbered requirements and working documents, plus the archive's
validation report and checksum records. All text is UTF-8. Mermaid diagrams
remain readable as source when a viewer does not render them.

## Distinguish requirements from implementation

The specification was drafted on 24 September 2026. Its proposed APIs,
configurations, and directory structures are requirements or examples, not
proof that a feature exists or passed qualification. Read the current
[repository guide](../../README.md) and
[implementation status](../IMPLEMENTATION_STATUS.md) for actual behavior and
remaining gates.

The current repository is `CTTIR/delphyR`; the packages are `delphyr` and
`delphyrApp`, licensed under MIT. Older passages may retain an earlier repository
spelling or describe licensing as undecided. Those historical passages have
not been silently rewritten. Example data and thresholds are synthetic, not
methodological recommendations.

## Scope and authorization

Providing this specification does not authorize real participant messages,
public deployment, or changes to a production server. Development fixtures use
synthetic data, test identities, and local message sinks. Institutional and
scientific approvals must come from the responsible people.

## Archive checksums

`MANIFEST.json` and `CHECKSUMS.sha256` describe the original supplied archive.
This README is now a maintained English index, so its original checksum no
longer describes this file. The other archived specification files remain
unchanged by this documentation update. Keep the original checksum records as
historical provenance; do not treat an archive check as a software test or a
production acceptance result.
