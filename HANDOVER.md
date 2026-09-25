# Handover

Verified **2026-09-25 12:05 UTC** against code commit
`eb42fb6293f12cf052b990b46163623d80bd1a90` on `main`.
This handover update is documentation-only. Use `git log -1` for its commit hash.

## First five minutes

Work from `/data/GitHub/CTTIR/public/delphyR`. Read in order:

1. `CURRENT_STATE.md`: current evidence, live services and recent user decisions.
2. `AGENTS.md`: working agreement; preserve configured Git authorship and ignored data.
3. `docs/IMPLEMENTATION_STATUS.md` and `docs/requirements-matrix.md`: implemented
   scope versus unaccepted P1 work.
4. `docs/adr/017-suite-conventions.md`: current English-documentation and EN/FR/DE
   decisions supersede the archived German/bilingual specification.
5. `docs/spec/00_START_HERE.md` and `docs/spec/27_ORCHESTRATOR_PROMPT.md` for the
   original product requirements. Archived specifications are not current status.

Inspect before editing:

```sh
pwd
git status --short
git log -3 --oneline
git remote -v
gh run list --limit 3 --json headSha,status,conclusion,url
ps -eo pid,args | rg 'scripts/(start-demo|worker)[.]R|inst/qa/preview'
docker ps --filter name=delphyr
ss -ltnp | rg ':(3849|3850|3868|4189|4190|55439)\b'
```

The inspected tree was clean and `HEAD` matched `origin/main`. Code CI passed:
https://github.com/CTTIR/delphyR/actions/runs/36128911932.
Do not confuse older failed attempts or historical baseline counts with this run.
Do not reset, clean, delete fixtures or stop unrelated containers.

## What is complete

English READMEs, public guides, report templates and both vignettes; EN/FR/DE UI
with English default and 274 explicit French keys; backend French content support
through migration 012; updated repository description/topics; and a dolphin badge
aligned with the CTTIR hex family. These changes are committed and pushed.

Study text, anchors and consent are approved content, not automatic translations.
Each round references one approved consent version. Missing item translations use
the protocol default with a visible fallback notice. Fresh synthetic studies have
trilingual items; existing fixtures retain their original wording.

## Source map

| Concern | Entry points |
|---|---|
| Core protocol and demonstration | `packages/delphyr/R/domain.R`, `demo.R` |
| Transactional workflow and permissions | `packages/delphyr/R/workflow.R`, service modules and `inst/sql/` |
| French backend constraints | `packages/delphyr/inst/sql/012_content_languages.sql`, `tests/testthat/test-languages.R` |
| App shell and style | `packages/delphyrApp/R/app.R`, `theme.R` |
| Translation behavior | `packages/delphyrApp/R/i18n.R`, `inst/i18n/fr.tsv`, `inst/i18n/ui-keys.txt` |
| Translation completeness tests | `packages/delphyrApp/tests/testthat/test-i18n.R` |
| Participant save/submission | `packages/delphyrApp/R/panel.R` |
| English reports | `packages/delphyr/inst/reports/study.qmd`, `R/reporting.R`, fallback in `R/jobs.R` |
| Vignettes | `packages/delphyr/vignettes/offline.Rmd`, `packages/delphyrApp/vignettes/synthetic-workflow.Rmd` |
| Logo used by app/READMEs | `packages/delphyrApp/inst/www/delphyR-hex.png` |

Use `tr(lang, de, en)` for UI text; vectors preserve names. Add explicit French
entries and update the exact key manifest whenever adding labels. Missing French
keys fail loudly. Stored status messages use `localize_status()` to translate only
registered prefixes while retaining opaque receipts/timestamps. Do not translate
technical identifiers or stored participant content.

## Reproduce validation

Commands run from the repository root. Bootstrap only when dependencies are missing:

```sh
Rscript scripts/bootstrap.R
Rscript scripts/check.R
Rscript -e '.libPaths(c(normalizePath(".R-library"), .libPaths())); pkgload::load_all("packages/delphyr", quiet=TRUE); testthat::test_local("packages/delphyrApp")'
```

Before database contract tests, identify and gracefully stop this repository's
background worker; it otherwise consumes test outbox jobs and causes false
failures. Verify PID and command immediately before stopping. Do not run these
queue-consuming checks concurrently with each other. Restart the worker afterward.

```sh
DELPHYR_TEST_DB=true Rscript scripts/integration.R
Rscript scripts/migration-empty.R
Rscript scripts/demo-e2e.R
Rscript scripts/check-packages.R
```

Latest results: 81 offline assertions (48 intentional database skips), 350 real
PostgreSQL assertions with no failures/warnings/skips, 145 app assertions, twelve
migrations with idempotent rerun, and 720 committed responses in the two-round
30-person/12-trilingual-item scenario. Both package checks: `Status: OK` with
`--as-cran --no-manual`, remote incoming checks disabled. Hosted CI also passed.

Both English vignettes were built/rebuilt in package checks and independently
rendered and visually inspected in Chromium against CTTIR conventions. The app
launch examples deliberately do not start services during vignette builds.

Evidence is local/ignored unless linked as a public CI artifact:

- `.local/reaudit-core-tests.log`, `reaudit-integration.log`, `reaudit-app-tests.log`.
- `.local/reaudit-package-checks.log`, `reaudit-migration.log`, `reaudit-e2e.log`.
- `.local/reaudit-browser-languages.log`, `reaudit-manager-languages.log`, `reaudit-logo.log`.
- `.checks/{delphyr,delphyrApp}.Rcheck/00check.log` and `.checks/english-vignettes/`.
- `.local/manager-fr-{desktop,mobile}.png` and `.local/branding-{desktop,mobile}.png`.
- `docs/validation/2026-09-25.md` and `packages/delphyrApp/inst/qa/README.md`.

For a new browser language test, use a fresh fixture path; the existing
`.local/trilingual-browser-fixture.rds` has already been submitted:

```sh
DELPHYR_TEST_DB=true DELPHYR_QA_FIXTURE=.local/new-language-fixture.rds Rscript packages/delphyrApp/inst/qa/preview-postgres.R
# Separate terminal, with chromote installed and /usr/bin/chromium available:
Rscript -e '.libPaths(c(normalizePath(".R-library"), .libPaths())); source("packages/delphyrApp/inst/qa/browser-languages.R")'
DELPHYR_TEST_DB=true DELPHYR_QA_FIXTURE=.local/new-language-fixture.rds Rscript packages/delphyrApp/inst/qa/verify-postgres.R
```

The successful browser run preserved pending rating 7 through EN/FR/DE, retained
approved consent, then saved/submitted in French. An independent runtime-role
read confirmed consent, revision 1, value 7, submitted state and durable receipt.
Manager checks covered translated headings/upload labels, retained rationale and
390px/1280px layouts; this is not exhaustive management or accessibility acceptance.

## Runtime and safe restart

See `CURRENT_STATE.md` for observed PIDs and containers. The manager is already
running on 3849 and worker is active. Do not launch duplicate workers or listeners.
If stopped, start in separately managed terminals/processes:

```sh
Rscript scripts/start-demo.R manager
Rscript scripts/start-demo.R 1 3850
Rscript scripts/worker.R
```

These scripts load source packages and reuse `.local/demo-fixture.rds`. PostgreSQL
uses loopback port 55439/database `delphyr`; app/worker use `delphyr_runtime`, while
migration/provisioning uses a separate owner connection. The isolated auth sandbox
is still running on 4189/4190 and has not been rebuilt for this commit. Its controlled
start/stop/profile instructions are in `docs/authentication.md`.

Do not assume the installed `.R-library` asset matches the latest logo: reinstall
before installed-package asset checks. Preserve existing user libraries when
setting `.libPaths()`. Local files in `admin/`, `.local/`, `.checks/`, `.artifacts/`
and `.R-library/` remain ignored; do not publish credentials, fixtures or databases.

Twelve SQL migrations are applied and frozen. Draft the next migration outside the
`*.sql` glob; integration discovers every visible migration. Never alter applied
SQL or registered checksums. For optional recovery qualification, consult
`docs/operations.md` before running `scripts/restore-check.sh`; prior recovery
hashes are historical evidence, not a new production recovery guarantee.

## Next work and boundaries

The latest documentation/language/design requests are complete. No pending code
edit or test needs resuming. For further product work, choose a bounded open gate
from the requirements matrix and define its acceptance evidence first. Current
priorities include invitation issuance/acceptance screens, a complete management
browser journey, broader accessibility/cross-browser coverage, and approved
feedback/export profiles. Avoid reopening completed audits without a new reason.

Stock Shiny Server OSS loses required identity headers and is not qualified.
The separate direct-backend local OIDC path passed twelve historical checks;
production hosting/governance, retention, real messaging and pilot/release
acceptance remain open. No real recruitment, external email or production
operation is authorized. Technical test success does not establish scientific or
clinical validity or complete P1 acceptance.

Before committing/publishing, verify `git var GIT_AUTHOR_IDENT`,
`git var GIT_COMMITTER_IDENT` and `gh api user --jq .login`; use the configured user
identity without overrides or added attribution. Commit and push significant
verified work to `main`, then refresh these two checkpoints with actual results.
