# ADR-017: CTTIR documentation and interface conventions

Status: accepted; language decision revised 2026-09-25.

## Context and superseding language decision

The user selected the repository name `CTTIR/delphyR` and requested consistency
with the CTTIR suite. Technical package names remain `delphyr` and `delphyrApp`.
This naming decision supersedes the earlier spelling in ADR-016.

The current explicit user decision is **English public documentation and an
English, French and German application interface**, with English as the default.
It supersedes this ADR's earlier German-documentation and bilingual-interface
requirements. The original German specification in `docs/spec/` is a verbatim
historical source archive, not the current public-documentation language policy.

The local `brainwritR` and `cellspecR` READMEs informed the structure: short purpose,
honest development status, runnable installation and entry point, then features,
reproducibility and license.

## Decision

The README uses delphyR branding, explains technical package names and accounts
for monorepository installation paths. Badges must describe evidenced states.
Brand assets must belong to this project.

The offline vignette runs without external services. It explains denominators,
group rules, missingness, round numbers, comparability and provenance. Synthetic
examples are not methodological recommendations. Public documentation points to
the central implementation status without inventing completed release gates.

The interface uses clear pages, readable typography, adequate contrast, explicit
field labels and a clear main action for each step. Navigation, actions,
validation and status must cover all three interface languages. Changing language
must preserve entered values. Keyboard operation, visible focus, mobile forms and
understandable feedback are required; color alone never conveys state or errors.

Interface language and approved study content are distinct. A round references
one approved consent version; changing language never translates or substitutes
that record. Instrument translations must be explicitly authored and validated
against declared protocol languages. Missing content translations must be visible
rather than implying that a fallback is an approved translation.

The interface confirms only completed service actions and visibly labels synthetic
demonstrations. Authentication, results, saved responses and feedback releases
must not be simulated by visual placeholders. Progress, draft and final submission
are separate states; sensitive responses are not stored in global UI objects.

## Evidence and limits

This ADR defines testable conventions; it does not certify accessibility,
browser, security or production acceptance. Actual evidence and remaining gates
belong in `docs/IMPLEMENTATION_STATUS.md`.
