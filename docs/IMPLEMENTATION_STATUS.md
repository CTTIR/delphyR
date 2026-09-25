# Implementation status

As of 2026-09-25: version 0.0.1, synthetic development only.
The complete P1 platform is **not yet accepted**.

The current user decision is English public documentation and an en/fr/de interface
with English as default. This supersedes the earlier German/bilingual convention
([ADR-017](adr/017-suite-conventions.md)). The original German specification remains
a verbatim archive. Earlier measurements below describe their recorded source
checkpoint; they do not automatically qualify the subsequent language changes.

## Implemented and locally exercised

- brainwritR colors: teal `#0e6e78`, warning red `#b3372b`, slate text and gray
  background; dolphin hex logo in app and READMEs. Confirmed saves are green;
  unsaved/failed saves are red, always with text. Historical Chromium checks at
  1280px and 390px found no overflow, missing logo or Shiny output errors.
- Deterministic offline analytics: scales, missingness, denominators, group rules,
  versions, stability and controlled feedback suppression.
- Checksummed PostgreSQL migrations, immutable records, current rights,
  study/participant isolation and content-bound retry receipts.
- Consent, confirmed revisions and atomic submission/closing; real concurrency
  checks including withdrawal against in-flight saves.
- Protocol amendments with predecessor, reason, hash, occupied-group validation
  and stable scale semantics; existing rounds remain unchanged.
- Round states, frozen snapshots, analysis, exact feedback approval, personal
  previous responses and human decisions.
- Qualitative originals, separate edits/summaries, independent approval, themes,
  coding, source links and split/merge history.
- Synthetic campaigns with exact recipient preview, approval, outbox, leases,
  suppression and an exclusively local database sink.
- Panel import with row errors, conservative normalization, blocking duplicate
  review, exact file approval, atomic receipts and separated contacts.
- Single-use invitation services: cryptographic randomness, hash-only storage,
  expiry, revocation, explicitly preapproved issuer/subject binding, confirmed
  acceptance and actual concurrency tests. No email-based account binding.
- Synthetic withdrawal with explained retention; stakeholder changes apply to
  future rounds without rewriting earlier assignments.
- Durable analysis/export jobs, private numeric exports, Quarto reports, dictionary,
  instrument/denominator/missingness/decision/lineage tables, manifests and
  independent offline reproduction.
- Shiny with confirmed saves, conflict/error states, connection warnings, explicit
  submission/withdrawal, rights-based navigation, protocol review, management,
  editorial workflows, panel import and campaign approval.
- CTTIR-style README and executable vignettes, mobile layouts, live status and
  reproducible browser checks.
- French core content validation and migration `012_content_languages.sql`:
  consent, instrument translations, imported contacts and campaign locale.
  The focused PostgreSQL language suite passed 12 assertions; broader current
  evidence is recorded below.

Interface language does not rewrite approved content. Each round still references
one explicitly approved consent version; multilingual content must be authored,
not inferred from a language selector.

## Current language re-audit

- English maintained READMEs, vignettes, public guides and report templates;
  original source specifications remain explicitly archived.
- 274 registered UI strings have explicit French translations. English is the
  default; English, French and German navigation, forms and status messages work.
- 81 offline assertions passed (48 database cases excluded from that run),
  145 app assertions passed, and 350 PostgreSQL assertions passed with no
  errors, warnings or skips in the database run.
- Both packages passed `R CMD check --as-cran --no-manual` with `Status: OK`
  (incoming remote checks disabled). Both vignettes built during checks and
  were separately rendered and visually inspected in Chromium.
- Twelve migrations applied to an empty database and reran idempotently.
- The two-round scenario confirmed 720 responses from 30 synthetic people over
  12 trilingual items, feedback, export and independent reproduction.
- Real PostgreSQL browser checks covered EN/FR/DE switching with an unsaved
  rating, unchanged approved consent, a confirmed French save and submission,
  and 390px/1280px layouts. Manager headings, upload labels and retained text
  drafts passed all three languages without Shiny output errors.
- Repository description and eight search topics now describe the Delphi,
  R/Shiny, PostgreSQL and reproducible-research scope.

## Historical verified checkpoint before the language expansion

| Check | Recorded result | Boundary |
|---|---|---|
| Offline tests | 77 assertions | 47 database cases intentionally skipped there |
| PostgreSQL integration | 338 assertions, no errors/warnings/skips | Breakdown in validation report |
| Shiny modules | 117 assertions | Service/session/navigation tests |
| Actual Chromium paths | Passed | Panel, network loss, keyboard, editorial, campaign, protocol, import, navigation |
| Actual OIDC integration | 12 checks passed | Local synthetic direct Shiny backend |
| Stock Shiny Server OSS | Not qualified | Websocket drops identity headers; session correctly rejected |
| Two-round service path | Passed | 30 people, 12 bilingual items, 720 responses, feedback, export reproduction |
| Empty migration | Passed | Eleven migrations, identical retry, service fixture |
| Package checks | Both Status OK | Built vignettes; incoming checks disabled |
| Database/artifact restore | Passed | Consistent database snapshot and selected study export; no production RPO/RTO |
| Local service load | 360 saves confirmed and reloaded | 30 processes, p95 0.083 s; no browser/internet latency |

Details: [validation](validation/2026-09-25.md), [browser QA](../packages/delphyrApp/inst/qa/README.md),
[authentication](authentication.md), [reporting](reporting.md),
[panel import](panel-import.md), [invitations](invitations.md),
[participation](participation.md), [protocol amendments](protocol-amendments.md).
No CRAN submission or scientific/clinical validation is claimed. Hosted CI is
verified separately for each actual commit.

## Remaining P1 work and external gates

- Institutional governance, consent/retention/deletion policies, operator
  responsibility and approved research-data handling.
- Stock-OSS hosting decision or separate direct-backend production qualification
  with TLS, secret management and separated operational roles.
- Browser invitation issuance/acceptance and full account onboarding; tested
  services require existing provisioned accounts.
- Full qualitative provenance in participant feedback, approved free-text/audit/
  publication profiles and scientific author information.
- Production provider adapter, reminder schedules, quiet hours and controlled
  resolution of uncertain delivery. No external dispatch is approved.
- Autosave, complete management browser workflow, systematic tab-order/assistive-
  technology/cross-browser acceptance and end-to-end load tests.
- Approved retention/cleanup, full production recovery, pilot and release acceptance.

Synthetic examples and green local tests do not close these gates. `admin/`, data,
backups and local libraries remain ignored. Entry points: [README](../README.md),
[operations](operations.md), [HANDOVER](../HANDOVER.md).

Hosted CI confirmation (2026-09-25 12:05 UTC): code commit
`eb42fb6293f12cf052b990b46163623d80bd1a90` passed
[run 36128911932](https://github.com/CTTIR/delphyR/actions/runs/36128911932).
See `CURRENT_STATE.md` and `HANDOVER.md` for the verified takeover checkpoint.
