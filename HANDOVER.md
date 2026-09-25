# Handover

Start with `CURRENT_STATE.md`, `docs/IMPLEMENTATION_STATUS.md`, `AGENTS.md`, and
`docs/spec/27_ORCHESTRATOR_PROMPT.md`. The full platform task remains active;
a passing P0 workflow is not acceptance of P1.

## Continue work

1. Inspect Git status and running tests/development processes; preserve existing work.
2. Use `.checks/` for current logs. Distinguish historical failed attempts from later successful runs.
3. Run `Rscript scripts/bootstrap.R` if R dependencies are missing.
4. The database runs separately on loopback port 55439. Do not modify unrelated containers.
5. Run `DELPHYR_TEST_DB=true Rscript scripts/integration.R` and `Rscript scripts/demo-e2e.R` to verify real database contracts.
6. Run `Rscript scripts/check-packages.R` to build and check both packages, including their vignettes.
7. Run `bash scripts/restore-check.sh` for an isolated backup and recovery experiment.
8. Start a local demonstration with `Rscript scripts/start-demo.R manager`; start a separate synthetic panel session with `Rscript scripts/start-demo.R 1 3850`. Run `Rscript scripts/worker.R` to process durable queued jobs.

Do not conduct real recruitment, send external messages, or deploy to production.
`admin/` and local data remain ignored. Never edit an applied SQL migration;
implement corrections in a new numbered migration.

## Current integrated state

The interface now supports English, French, and German, initially English, with
274 French translation keys and a demonstration covering all three locales.
Study and instrument texts retain their authored languages. The English offline
and application vignettes render successfully; inspected HTML and screenshots
are in `.checks/english-vignettes/`.

The current combined database suite and the two-round, 720-response synthetic
scenario passed. Both package checks report `Status: OK`; 145 app, 81 offline
and 350 PostgreSQL assertions passed. The offline run explicitly excludes 48
database cases. Real EN/FR/DE browser checks and an independent database read
confirmed the French save/submission receipt. Hosted CI for the current changes
remains pending.

Historical baseline: 338 real PostgreSQL assertions, 77 offline assertions,
and 115 app assertions, with both local package checks reporting OK. Detailed
historical counts, builds, and recovery hashes are in
`docs/validation/2026-09-25.md`. Institutional gates, stock OSS identity-header
transport, and invitation screens remain explicitly open.

Twelve migrations are applied and frozen. Prepare future migration drafts
outside the `*.sql` glob, then add a fully reviewed file: a concurrent integration
run applies every visible SQL file. Never rewrite registered checksums to match
an applied migration that was subsequently edited.

To verify selected study artifacts together with the database:

```sh
DELPHYR_RESTORE_STUDY=$(cat .checks/latest-e2e-study.txt) scripts/restore-check.sh
```

The authentication qualification path and controlled start/stop commands are
in `docs/authentication.md`. Never publish private authentication fixtures.
