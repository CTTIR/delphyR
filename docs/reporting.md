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
containing a free-text scale are rejected for this profile. The profile is for
restricted research use, not public release or general anonymization.

Authors, funding, conflicts of interest, institutional approval, methodological
interpretation, deviations, and ACCORD/CREDES review remain explicitly
undocumented where the report service has no approved structured entry. This
means the report lacks a supported value, not that a real study necessarily
lacks the information. The report does not invent those statements.

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

Database tests require `DELPHYR_TEST_DB=true` and the local synthetic PostgreSQL
instance. The standard run without opt-in does not access that database.
