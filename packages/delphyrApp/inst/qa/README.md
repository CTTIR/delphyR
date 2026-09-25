# Browser qualification evidence, 2026-09-25

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
Management queue and feedback release paths are exercised by testServer with
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
