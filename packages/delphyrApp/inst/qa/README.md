# Browser qualification evidence

These records describe specific synthetic checks performed on 25 September 2026.
They are not a claim that every current screen, language, browser, or production
component has been qualified. Current interface languages are English, German,
and French, with English as the default; historical EN/DE checks below retain
their actual scope. Scientific study text is not automatically translated.

## Deterministic panel fixture

Run `preview.R` in one terminal after installing delphyrApp, then
`browser-smoke.R` in another with the optional chromote package and Chromium.
Both use localhost port 3867. This is a deterministic injected-service fixture,
not a database integration test. The fixture never sends mail and uses no
real participant data.

Verified in Chromium on Linux:

- Questionnaire loads with no preselected rating.
- Selecting a value and changing EN to DE retains the pending value.
- The unsaved state is visible, then save confirmation follows the service return.
- Final submission produces a receipt.
- Desktop and 390-pixel viewport screenshots were inspected; the narrow viewport
  has document width 390 pixels and no horizontal page overflow.

The screenshots in `inst/figures` show this fixture. They do not certify other
browsers, assistive technologies, production login, or live database behavior.
Management queue and feedback release paths are exercised by `testServer()` with
injected services; a complete real-database management browser journey remains open.

The application uses a separate worker for jobs. There is no browser control
that assumes worker infrastructure privileges.

## PostgreSQL browser path

A separate real-database Chromium check passed on 2026-09-25 at 09:28 UTC.
A new synthetic study had two panel accounts and one bilingual item. The
manager reviewed, approved and opened the round. The browser then used the
`delphyr_runtime` database role and a trusted panel actor to record consent,
select rating 7, switch English to German without losing that pending rating,
save revision 1, and submit.

An independent repository read under the same runtime role verified consent
accepted, enrollment `submitted`, one response with value 7 and revision 1,
and one durable submission receipt:
`20f14a94-116e-4cb1-a316-8dcf94f0e986`.

This qualifies the local panel path on PostgreSQL and Chromium. The separate
management browser path and cross-browser/assistive-technology matrix remain
open. The committed illustrative screenshots continue to use the deterministic
service fixture. Queue, exact-feedback-review, and submission-guard tests use
`testServer()`; they do not stand in for the open management browser matrix.

## Reproduce the PostgreSQL browser check

From the repository root, first provision the disposable PostgreSQL instance
and the `delphyr_runtime` role using the project's development setup. These
scripts use the project's `.R-library`, then `pkgload::load_all()` for the two
source packages. `chromote` and Chromium are required for the browser step.

Terminal 1 creates a uniquely named two-account, one-item synthetic study,
opens its round, saves the fixture only in ignored `.checks/`, and starts the
panel app on localhost port 3868:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/preview-postgres.R
```

Terminal 2 performs browser consent, rating, language switching, saving and
submission, then independently verifies the persisted result through the
runtime repository:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-postgres.R
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/verify-postgres.R
```

Stop the preview with Ctrl+C. For a repeat run, set a new ignored fixture path
consistently in the preview and verification terminals, for example
`DELPHYR_QA_FIXTURE=.checks/browser-fixture-2.rds`. The preview refuses to
replace an existing fixture. The scripts intentionally retain the synthetic
study for inspection; they do not delete other database records.

Connection defaults are `127.0.0.1:55439`, database `delphyr`, administrator
`postgres` for fixture provisioning, and `delphyr_runtime` for the application
and verification. Override with `DELPHYR_DB_HOST`, `DELPHYR_DB_PORT`,
`DELPHYR_DB_NAME`, `DELPHYR_DB_ADMIN`, or `DELPHYR_DB_RUNTIME`. All three scripts
require the explicit `DELPHYR_TEST_DB=true` opt-in. The verification script was
rerun against the completed fixture and reproduced the receipt above.

## Manager display regression check

A fresh PostgreSQL manager session was checked in Chromium after the date
formatting fix. The table displayed `2026-10-02 11:32 +0200 Europe/Berlin`,
localized column headings and state names in German and English, and no
participation section for an actor without panel capability. The screenshot
`inst/figures/manager-desktop.png` captures the English view. This is a display
check; the full management browser mutation workflow remains open.

## Editorial and campaign module browser check

On 2026-09-25 the modules were exercised in Chromium with actual PostgreSQL
services under `delphyr_runtime`, in a focused module host rather than the full
application shell. One editor preserved a synthetic original and created a
separate summary. A different manager previewed and released that exact version.
The manager also previewed and approved one exact pseudonymous recipient and
synthetic message. Independent repository reads confirmed the unchanged
original, one separate edit, one release by a different principal, and one
campaign recipient with `sink_recorded` status. No external message was sent.

Reproduce with the disposable development database and runtime role described
above. All commands run from the repository root and require the explicit opt-in.
The module preview scripts load `.R-library` and both source packages with
`pkgload`; the fixture remains in ignored `.checks/`.

Terminal 1 starts the editor's trusted session:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/preview-editorial-postgres.R editor
```

Terminal 2 records the original and summary, then starts the manager's distinct
trusted session:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-editorial-postgres.R
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/preview-editorial-postgres.R manager
```

Terminal 3 reviews and releases the summary, previews and approves the synthetic
campaign, and verifies the persisted result. The verifier also processes the
scoped local sink if the separate worker has not already done so:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-review-campaign-postgres.R
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/verify-editorial-postgres.R
```

These scripts use the local disposable database at `127.0.0.1:55439`, database
`delphyr`. Choose a fresh ignored `DELPHYR_EDITORIAL_FIXTURE` path for a repeat
run; pass the same value to both preview hosts and the verifier. Stop the two
hosts with Ctrl+C after checking. The full browser matrix, theme/lineage browser
mutations, and production authentication deployment remain separate gates.

## Network loss, keyboard input and reload

The full panel application was checked in Chromium against PostgreSQL on
2026-09-25 using a fresh synthetic fixture and `delphyr_runtime`:

- Actual browser keyboard events selected the response type and rating 7,
  activated consent and saved revision 1. DOM focus was set to each starting
  control; this was not a complete screen-reader or uninterrupted Tab-order test.
- Rating 8 was then entered without saving. The status said unsaved and did not
  repeat the preceding save confirmation.
- Chromium network emulation was set offline and the WebSocket was closed.
  A connection-loss alert stated that changes were not being saved; per-field
  save indicators were hidden. A keyboard save attempt produced no confirmation.
- After network restoration and page reload, the form restored committed rating
  7. A fresh repository read confirmed that the disconnected edit had not become
  another response revision.
- Checkbox Space, Tab to the submission button, and Enter submitted successfully.
  All visible fields had an explicit, implicit, or ARIA label. At a 390-pixel
  viewport the document width was 390; editor and campaign controls were absent
  for the panel actor.

Independent verification found consent accepted, enrollment submitted, rating
7 at revision 1, and receipt `95a56605-8d87-4aa8-bb96-bc890f0df689`.
This is a narrow tested disconnection/reload scenario, not an offline editor or
an automatic retry guarantee. Pending text is not persisted in browser storage.

Reproduce with a fresh fixture path in both terminals:

```sh
DELPHYR_TEST_DB=true DELPHYR_QA_FIXTURE=.checks/network-new.rds Rscript packages/delphyrApp/inst/qa/preview-postgres.R
```

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-network-keyboard.R
DELPHYR_TEST_DB=true DELPHYR_QA_FIXTURE=.checks/network-new.rds Rscript packages/delphyrApp/inst/qa/verify-postgres.R
```

## Protocol amendment browser check

A focused protocol-module host was exercised in Chromium with PostgreSQL and
the runtime database role on 2026-09-25. A manager uploaded a complete valid
JSON protocol, reviewed the exact `stopping.max_rounds` change from 3 to 4,
confirmed the future-round-only scope, supplied a rationale, and approved
version 2. Independent repository reads verified two immutable versions, the
unchanged original hash, the new maximum of 4, and the existing questionnaire's
original maximum of 3. This is technical versioning evidence, not ethical or
institutional approval.

From the repository root, use a fresh ignored fixture path for each repeat:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/preview-protocol-postgres.R
```

In another terminal:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-protocol-postgres.R
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/verify-protocol-postgres.R
```

The host uses localhost port 3873 and the same disposable database/runtime role
as the other PostgreSQL fixtures. Override `DELPHYR_PROTOCOL_FIXTURE` for a fresh
fixture, and optionally `DELPHYR_PROTOCOL_JSON` for its generated upload file;
use the same values across the relevant commands. Defaults are ignored files
under `.checks/`. Stop the host with Ctrl+C. Tests also reject invalid/oversized
JSON, lack of explicit approval, and uploaded content changed after preview.

## Panel import and workspace navigation

A PostgreSQL/Chromium module-host check first uploaded a CSV with duplicate
references and addresses. The interface showed every blocking row/column issue.
A corrected UTF-8 CSV ending in a normal newline then passed preview and was
explicitly approved. Runtime receipt retrieval and independent database counts
verified two contacts, two unbound invitation drafts, one import receipt, and
unchanged counts of two panelists and two enrollments. Receipt:
`de3bfaae-66a3-4bf5-9f12-a5d7d6436ebc`. No accounts, response links, or mail were
created. The actual browser check exposed a terminal-newline parsing defect;
the core parser was repaired and the real upload was rerun successfully.

Reproduce against the disposable development database, from the repository root:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/preview-import-postgres.R
```

In a second terminal:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-import-postgres.R
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/verify-import-postgres.R
```

The fixture host uses port 3874. Set a fresh ignored `DELPHYR_IMPORT_FIXTURE`
path for repeat runs, consistently for the host and verifier. Generated CSVs
remain under ignored `.checks/`.

The full manager application was also inspected in Chromium at desktop and
390-pixel viewport widths. Its five navigation links were permission-filtered;
no participation link appeared for the manager. Moving to Panel import and back
to Rounds preserved unsubmitted reason text. Introductory guidance matched the
manager role. The mobile document width remained 390 pixels. Screenshots are
in `inst/figures/manager-navigation-{desktop,mobile}.png`.

Reproduce the navigation check with a populated development fixture:

```sh
Rscript scripts/start-demo.R manager 3875
```

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-navigation-postgres.R
```

This checks section navigation and preservation of a draft field. It is not a
formal accessibility audit or a substitute for the full browser matrix.

## Trilingual re-audit

`browser-languages.R` runs against a fresh `preview-postgres.R` fixture. It passed
against PostgreSQL on 25 September 2026: English default; EN/FR/DE switching with
rating 7 retained; approved consent unchanged; French save and final submission
receipts; status translation after switching back to English; and no horizontal
overflow at 1280px or 390px. This uses the restricted runtime database role.

The manager workspace was separately checked in all three languages: navigation,
section headings, file control labels, retained rationale text, no Shiny output
errors, and French desktop/mobile rendering. These checks do not constitute a
complete translated management transaction journey or human linguistic review.

## Invitation issuance and acceptance

`browser-invitation-postgres.R` starts a coordinator host and an invitee host
itself, drives both in Chromium and stops them. It passed on 2 October 2026
against PostgreSQL with the restricted runtime role:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-invitation-postgres.R
```

It checks the unregistered-account notice, mandatory rationale and confirmation,
issuance and one-time display of the hand-over code, fragment prefill and
removal, refusal of a changed and of a replayed code, explicit acceptance, the
resulting study access, both viewport widths, and independent database reads.
The invitee identity comes from the gateway adapter with a synthetic trusted
request; this is not an OIDC gateway qualification. Host logs are written to
ignored `.checks/invitation-*.log` and are scanned for the token and secret.

## Automatic saving, two tabs and connection loss

`browser-autosave-postgres.R` starts its own panel host with the default
automatic saving and passed on 2 October 2026 in Chromium against PostgreSQL
with the restricted runtime role:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-autosave-postgres.R
```

- A rating chosen without touching the response type became an answer and was
  committed as revision 1 without any button; the status read *Unsaved change*
  until the commit, then *Saved* with the server time.
- A changed rating stayed unsaved until its own commit (revision 2). A special
  response cleared the rating shown beside it and was stored without a value.
- A second tab of the same person committed a newer revision. The first tab's
  stale entry produced a conflict, created no revision, and stopped further
  automatic attempts. Only the explicit *Load the saved response* action replaced
  the entry, and no revision was created by it.
- After an entry made while Chromium went offline and the WebSocket closed, the
  alert stated that changes are not being saved, the field confirmation was
  hidden, the database was unchanged, and a reload showed the committed value.
- Submitting immediately after a new entry saved it first (revision 4) and the
  submission referenced exactly that revision. Audit save events equalled the
  committed revisions.

`preview-postgres.R` and `preview.R` run with explicit saving
(`autosave_ms = 0`) because the earlier scripts check pending and explicitly
saved states; set `DELPHYR_QA_AUTOSAVE_MS` to change that host. This remains a
narrow tested scenario on one browser, not an offline editor.

## Study management: review, readiness, enrollment and withdrawal

`browser-management-postgres.R` starts its own manager host and passed on
2 October 2026 in Chromium against PostgreSQL with the restricted runtime role:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-management-postgres.R
```

- Approval was refused until the instrument of the selected round had been
  displayed. The review showed the study information, both items in English,
  French and German, the content checksum and the readiness notes.
- A panel member added after preparation was enrolled explicitly; the round was
  then approved and opened. Round events recorded each transition with its
  reason and the reviewed checksum. Withdrawing the opened round was refused.
- In a study without participants, content approval succeeded, opening was
  refused, and the blocking finding was displayed. The candidate was withdrawn;
  its three events remained and a new candidate received round number 1.
- No Shiny output error and no horizontal overflow at 390 and 1280 pixels.

This script covers the round lifecycle controls. Analysis, feedback, export and
study completion in the browser are recorded separately.

## Documentation, comparability, export profiles, history and participant download

`browser-governance-postgres.R` builds a two-round synthetic study through the
services, starts a manager, an audit-only and a panel host, steps the export
worker under the restricted runtime role and passed on 2 October 2026:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-governance-postgres.R
```

- The manager saved documentation version 1 only with a rationale and
  confirmation, and recorded a "not comparable" decision for the revised item.
- The manager was offered the research, summary and audit profiles, not the
  contact profile. The downloaded summary contained no response file and no
  pseudonym; the downloaded research export was reproduced offline, with the
  revised item shown as not comparable for the recorded reason and three paired
  members for the unchanged item.
- The History section listed the documentation, the comparability decision and
  the downloads with their rationale and without any panel account reference.
- The audit-only account saw only Exports and History, was offered only the
  audit profile, and its download contained events without panel account
  references.
- The panel member saw the changed-wording notice and downloaded a file holding
  only that person's own previous answers. All downloads were recorded as audit
  events. No Shiny output error and no horizontal overflow at 390 and 1280 pixels.

Downloads are fetched inside the page from the Shiny download link and unpacked
for inspection; this checks the delivered bytes, not a browser's save dialog.

## A complete two-round study through the interface

`browser-study-journey-postgres.R` passed on 2 October 2026 in Chromium against
PostgreSQL. One application host resolved a separate identity and database
connection for each of five browser sessions under the restricted runtime role:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-study-journey-postgres.R
```

The script stands in for the authentication gateway by sending the identity
headers a qualified gateway would set; it qualifies the workflow and session
isolation, not an OIDC deployment. The operator steps were provisioning the
study lead's account and stepping the worker. The database was read only to
verify results.

- Sessions without identity headers, with a wrong gateway secret or with an
  unknown account received the unregistered notice and no session.
- The lead created the study from an uploaded protocol after validation and
  confirmation, published the study information, imported four contacts and
  issued four account-bound invitations.
- Round one was prepared before anyone had joined. Four people accepted with
  their own accounts; a code used by another account was refused. Opening was
  refused with the finding that nobody was enrolled, then succeeded after
  explicit enrollment and exact instrument review.
- The panel consented, rated with automatic saving and submitted; one answer
  was "unable to judge". The lead closed and froze the round, requested the
  analysis, recorded item decisions, reviewed and released the feedback,
  prepared round two and assigned the feedback.
- In round two each person saw only the own previous answers beside the
  released panel results; one member rated without submitting. The lead
  finalized the round, completed the study, recorded documentation and
  downloaded the research export.
- The export was reproduced offline: the item with a single valid rating in
  one group was `insufficient_data` under the group rule, three members were
  paired for each item, round two held three submitted response sets, and no
  account subject or contact address appeared in any file.
- Independent reads confirmed 76 audit events with the expected counts per
  action, four distinct accounts behind the saved responses, no secret or
  invitation token in the host log, no Shiny output error and no horizontal
  overflow at 390 and 1280 pixels in any session.

Two defects found by this run were repaired with regression tests: round
preparation used the study information read when the section was opened, and
empty recipient and version lists rendered an output error.

## Exploratory round, released feedback content and correction

`browser-exploratory-postgres.R` passed on 2 October 2026 in Chromium against
PostgreSQL with separate hosts for the editor, an independent reviewer and a
panel member under the restricted runtime role:

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-exploratory-postgres.R
```

The free-text round itself is conducted through the services. In the browser:

- The editor took over four frozen proposals as sources, created a summary and
  a redaction, read the unchanged original, and linked two derived items to
  three proposals. The author was offered no version for release.
- The reviewer, who never saw an original, previewed and released the exact
  versions. The feedback preview contained only released text. The rating
  round was prepared with the derived items, the feedback assigned, and the
  round reviewed, approved and opened.
- The panel member saw the summary labelled "Moderated summary (not a
  quotation)" beside the derived item and the redaction above the items, and no
  other member's original text anywhere in the page.
- The summary had reversed the proposals. A corrected version was released by
  the reviewer and published as a correction with rationale, effect and note.
  After reloading, the panel member saw the corrected summary with the note and
  kept the rating already saved. The earlier feedback row and its hash were
  unchanged, the first display event referred to the earlier version and the
  last to the correction, and all three releases were made by a different
  account than the edits.
