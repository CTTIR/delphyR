# Handover

Updated **3 October 2026**. Read [CURRENT_STATE.md](CURRENT_STATE.md) first; it
says where the project stands and what runs locally.

## First five minutes

Work from `/data/GitHub/CTTIR/public/delphyR`. Read in order:

1. `CURRENT_STATE.md`: state, evidence and local services.
2. `AGENTS.md`: working agreement; configured Git authorship, ignored data,
   no further agents without permission.
3. `docs/IMPLEMENTATION_STATUS.md` and `docs/requirements-matrix.md`: the
   gates, scenarios, known limits and external gates.
4. `docs/adr/017-suite-conventions.md`: English documentation and an en/fr/de
   interface supersede the archived German/bilingual specification.
5. `docs/spec/00_START_HERE.md` and `docs/spec/27_ORCHESTRATOR_PROMPT.md` for
   the original requirements. Archived specifications are not current status.

Inspect before editing:

```sh
git status --short
git log -5 --oneline
gh run list --limit 3 --json headSha,status,conclusion,url
ps -eo pid,args | rg 'scripts/(start-demo|worker)[.]R|inst/qa/'
docker ps --filter name=delphyr
```

Do not reset, clean, delete fixtures or stop unrelated containers.

## Source map

| Concern | Entry points |
|---|---|
| Protocol, analysis, canonical hashes | `packages/delphyr/R/domain.R`, `analytics.R`, `conditions.R` |
| Transactional services and rights | `R/workflow.R`, `repository.R` and the service files; `inst/sql/` (17 checksummed migrations) |
| Snapshots, feedback, exports, reports | `R/snapshots.R`, `study_export.R`, `jobs.R`, `inst/reports/` |
| Messages | `R/communications.R` |
| Operation | `R/operations.R`, `scripts/status.R`, `artifact-cleanup.R`, `hold-messages.R`, `worker.R` |
| Technical log | `R/logging.R` |
| Application shell, sign-out, sessions | `packages/delphyrApp/R/app.R`, `theme.R` |
| Participant view and blocks | `R/panel.R` |
| Study management | `R/management.R`, `operations.R`, `setup.R`, `governance.R`, `editorial.R`, `communications.R` |
| Translations | `R/i18n.R`, `inst/i18n/fr.tsv`, `inst/i18n/ui-keys.txt` |
| Browser and load checks | `packages/delphyrApp/inst/qa/` and its README |
| Gateway fixture | `deploy/auth/` and [authentication](docs/authentication.md) |
| Runbooks and governance | `docs/runbooks/`, `docs/governance/` |

Use `tr(lang, de, en)` for interface text and add the French entry to
`inst/i18n/fr.tsv` and the key to `inst/i18n/ui-keys.txt`; missing keys fail a
test. R sources and tests stay ASCII; write other characters as `\u` escapes.

## Reproduce validation

From the repository root. Stop this repository's background worker before
the database tests; it consumes test jobs.

```sh
Rscript scripts/check.R
Rscript scripts/configure-dev-role.R
DELPHYR_TEST_DB=true Rscript scripts/integration.R
Rscript scripts/migration-empty.R
Rscript scripts/demo-e2e.R
Rscript -e '.libPaths(c(normalizePath(".R-library"), .libPaths())); pkgload::load_all("packages/delphyr", quiet=TRUE); testthat::test_local("packages/delphyrApp")'
Rscript scripts/check-packages.R
scripts/restore-check.sh
```

Before every push run the whole list, including `check-packages.R`; hosted
CI runs the same steps. Browser checks, the load run and the gateway are
described in `packages/delphyrApp/inst/qa/README.md`, `docs/load.md` and
`docs/authentication.md`. Never edit a script while Rscript runs it; R reads
it as it goes.

## Rules that keep evidence honest

- Never alter an applied SQL migration; add a new numbered file.
- Synthetic data only; no real message, no production deployment.
- A planned feature is never reported as present; a check that did not run
  is reported as not executed.
- Credentials in `.local/auth/` are never printed or copied into documents.
- Before committing, verify `git var GIT_AUTHOR_IDENT` and add no attribution
  lines.

## Next work

The software side of the roadmap is complete up to the acceptance decision.
What remains belongs to the responsible organisation: the external gates in
`docs/IMPLEMENTATION_STATUS.md`. Software work that would follow from those
decisions, and is not started: an adapter for the chosen message provider,
removal or anonymisation according to the approved retention policy, the
qualification of the chosen hosting path, and fixes from a pilot.
