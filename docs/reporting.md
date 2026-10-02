# Reports and numeric export supplements

`prepare_report_data(repo, actor, snapshot_id)` builds report data for an immutable
numeric snapshot. It checks current export authority in the owning study;
a separate analysis capability is not required. Panel members and users from
another study cannot obtain these data through this service.

## Included data and boundaries

Reports contain the protocol, consensus rules, scientific provenance, results,
denominators, missingness, distributions, and frozen multilingual instrument
texts. A dictionary explains key fields and hashes. Instrument text is authored
study content, not an individual response or an automatic translation.

Human item decisions are limited to item code, disposition, and the corresponding
analysis hash. Lineage includes codes, versions, and relationship types, filtered
to exact item/version combinations in the snapshot. These editorial records
reflect export time; they are not retroactively part of the frozen responses.

Unreviewed reasons, qualitative originals, individual free-text responses, contacts,
and principal/actor identifiers are excluded from this supplement. Snapshots
containing a free-text scale are rejected for this round profile; the
study-level research profile below exports such rounds with released redactions
only. The profile is for restricted research use, not public release or general
anonymization.

Authors, funding, conflicts of interest, institutional approval, methodological
interpretation, deviations, and ACCORD/CREDES review are taken from the study
documentation described below. A topic without an entry remains explicitly
"not documented". The report does not invent those statements.

## Write private supplements

```r
data <- delphyr::prepare_report_data(repo, actor, snapshot_id)
# staging is a new private directory controlled by the export worker.
files <- delphyr::write_report_data(data, staging)
```

The writer produces `report-data.json`, `data_dictionary.csv`, `round_items.csv`,
`item_decisions.csv`, `item_lineage.csv`, `missingness.csv`, `denominators.csv`,
`distributions.csv`, and `author_fields.csv`. CSV text uses the research export's
spreadsheet-formula masking. Existing files with these names are not overwritten.

The export worker creates the supplements and rendered report **before** generating
the final manifest. Every delivered file is listed with size and SHA-256. Report
data also have a canonical content hash, including the export timestamp; this
is distinct from the scientific result hash.

## Render the packaged Quarto template

```r
path <- delphyr::render_study_report(data, staging, timeout = 60L)
```

The installed `inst/reports/study.qmd` template is the only executable report
source. The API accepts neither arbitrary template paths nor custom render
arguments. It copies that template and JSON data into a fresh temporary directory.
Study content stays data, is escaped for HTML, and never becomes R code or YAML.

The renderer uses `system2()` with fixed or shell-quoted arguments, a timeout of
at most 300 seconds, and private temporary files. The resulting HTML embeds its
resources. Temporary inputs and logs are removed; failures return `DEL_RENDER`
without raw study text in the error. This is a bounded trusted worker process,
not a general sandbox for untrusted templates.

Quarto, `knitr`, and `rmarkdown` are optional runtime dependencies. Their absence
returns `DEL_DEPENDENCY`; only that condition selects the explicitly labelled
basic HTML fallback. The manifest identifies `quarto_html` or
`basic_html_missing_quarto_runtime` and records the report-data hash. An actual
render failure or missing package template fails the export job and does not
register a partial artifact. This path does not implement PDF or DOCX output.

Interface language and report-template language are separate contracts. Changing
the app language does not translate frozen scientific wording or turn an existing
report into another language.

## Study documentation

Authors, responsibilities, panel criteria, funding, conflicts of interest,
institutional approval, interpretation, deviations, guideline review and
data/software availability are recorded by study management with
`record_study_documentation()` or in the **Documentation** section. Each save
is a new immutable version that replaces the previous one completely and needs
a rationale. Reports show the latest version; a topic without an entry stays
"not documented". The software neither writes these statements nor verifies an
approval that is merely referenced.

## Study-level exports and report

`request_study_export(repo, actor, study_id, profile, command_id)` queues a
private export for the worker. The profiles and their separate rights are
described in [ADR-021](adr/021-export-profiles-and-study-documentation.md).

| Profile | Files |
|---|---|
| `research_pseudonymized` | `snapshot-round-<n>.json` (authoritative), `responses.csv`, `submissions.csv`, `enrollments_pseudonymized.csv`, `round_items.csv`, `analysis_results.csv`, `denominators.csv`, `missingness.csv`, `distributions.csv`, `comparisons.csv`, `item_comparability.csv/.json`, `item_decisions.csv`, `item_lineage.csv`, `qualitative_*.csv`, `protocol.json`, `protocol_versions.json`, `amendments.csv`, `feedback_manifest.json`, `study_documentation.json`, `documentation.csv`, `data_dictionary.csv`, `provenance.json`, `reproduce.R`, `report-data.json`, `report.html` |
| `study_summary` | `participation.csv`, `recruitment.csv`, `round_items.csv`, `analysis_results.csv`, `distributions.csv`, `comparisons.csv`, `item_decisions.csv`, `item_lineage.csv`, `qualitative_work.csv`, `amendments.csv`, `documentation.csv`, `protocol.json`, `provenance.json`, `feedback_manifest.json`, `study_documentation.json`, `data_dictionary.csv`, `report-data.json`, `report.html` |
| `audit_restricted` | `audit_events.csv`, `round_events.csv`, `protocol_versions.csv`, `campaign_approvals.csv`, `staff_rights.csv`, `qualitative_releases.csv`, `documentation_versions.csv` |
| `contacts_restricted` | `contacts.csv` |

Every profile has a `README.md` and a `manifest.json` listing each file with
size and SHA-256. `responses.csv` follows the research response export
contract: one row per person, item and dimension of a submitted response set,
with pseudonym, group, item version, status, value, revision and submission.
A free-text value is the released redaction or the marker
`[withheld: no released redaction]`; unreviewed originals are never exported.

`provenance.json` records the export time separately from the data date, the
protocol hash, timezone, quantile definition, software versions and, per round,
the frozen snapshot hash, the exported snapshot hash, the result hash and
whether it matches the stored analysis. Git commit and lockfile hash are
"not recorded" unless the operator supplies them.

`prepare_study_report_data()` and the packaged `study-final.qmd` template
produce one report across all frozen rounds: design and scope, protocol and
amendments, recruitment and participation, instruments, results, change between
rounds with comparability decisions, released feedback, qualitative work and
decisions, final items, author-supplied documentation, dictionary, provenance
and limitations. The summary profile omits denominators and decision
rationales and applies small-cell suppression.

```sh
Rscript reproduce.R /path/to/extracted-research-export
```

`reproduce_study_export(path)` verifies every checksum, reads each snapshot,
recomputes the analyses and the comparisons between rounds and compares them
with the recorded hashes. It needs neither the application nor a database.

A panel member obtains the participant-feedback profile with *Download my
feedback*: the released aggregate of the previous round and only that person's
own previous answers (`write_participant_feedback()`).

## Verification

`test-reporting.R` checks study boundaries, revocation, export access without
analysis access, exclusion of editorial reasons, allowed files, and content
hashes. With Quarto installed, it performs actual rendering. Injected HTML,
inline R, and include text remain inert data; a requested execution marker is
not created.

The integrated worker test checks the final manifest, download-time checksums,
the dependency fallback, and failure without an artifact on `DEL_RENDER`. A
regression also excludes a later item-version split from an older snapshot's
lineage. The local run on 25 September 2026 passed 45 reporting assertions and
17 existing job assertions, including actual Quarto rendering. Those numbers
identify that run; the central implementation status tracks subsequent checks.

`test-study-export.R` covers the study-level profiles on PostgreSQL: file sets,
canary strings for unreviewed text, contacts and account references, separate
rights for each profile, small-cell suppression, tamper detection at download,
repeatable requests, offline reproduction and the participant download. On
2 October 2026 it passed 110 assertions including actual Quarto rendering of
the study report.

Database tests require `DELPHYR_TEST_DB=true` and the local synthetic PostgreSQL
instance. The standard run without opt-in does not access that database.
