# Current state

Live verification: **2026-09-25 12:05 UTC**. Repository `CTTIR/delphyR`, branch `main`.
Workspace: `/data/GitHub/CTTIR/public/delphyR`.
Code baseline: `eb42fb6293f12cf052b990b46163623d80bd1a90`, matched `origin/main`
at inspection with a clean working tree. The subsequent handover commit changes
documentation only; use `git log -1` for its actual hash.
`admin/` remains ignored; the original specifications are archived in `docs/spec/`.
Current English guides document the implementation and its limitations.

## Verified synthetic implementation

The core package, PostgreSQL services, worker, and Shiny interface support round
release, consent, confirmed saves, submission, snapshots, analysis, feedback,
and exports. Additional services cover versioned protocol amendments,
qualitative editorial review with independent approval, campaigns using a local
sink, panel CSV preview and atomic import, account-bound single-use tokens,
participation withdrawal, and stakeholder group history. Quarto reports and
private export supplements support offline reproduction.

The interface supports English, French, and German, with English as the default.
The French interface contains 274 translation keys. The synthetic demonstration
covers all three locales; stored study and instrument wording remains explicitly
authored rather than automatically translated. Package guides and vignettes are
English, and both vignettes have been rendered and visually inspected.

The current combined PostgreSQL suite and two-round service scenario passed;
the latter confirms 720 responses from 30 synthetic participants. Twelve
migrations are checksummed and frozen; do not edit applied SQL files. Both package
checks report `Status: OK`. The direct app suite passed 145 assertions, the
offline suite passed 81 (48 explicit database skips), and the PostgreSQL suite
passed 350 without failures, warnings or skips. Real EN/FR/DE panel switching,
French save/submission, independent receipt verification and manager language
checks passed. See the current implementation-status record for exact scope.

Historical baseline: 338 PostgreSQL assertions without failures, warnings, or
skips; 77 offline assertions with 47 explicit database skips; and 115 Shiny
assertions. Real Chromium paths checked panel submission, connection loss,
editorial review, campaigns, protocol amendments, panel import, and
permission-filtered navigation. Both package checks passed locally and in hosted
CI for `0f03ae6`:
https://github.com/CTTIR/delphyR/actions/runs/36123381681.
Current code CI **passed** for `eb42fb6293f12cf052b990b46163623d80bd1a90`:
https://github.com/CTTIR/delphyR/actions/runs/36128911932.
This is hosted technical validation, not deployment or P1 acceptance.

## Authentication and limitations

A real Keycloak/OAuth2 Proxy login with a direct Shiny backend passed twelve
checks. Stock Shiny Server OSS discards the required identity headers and is
explicitly not qualified for that deployment path. Both outcomes are documented
separately in `docs/authentication.md`. Invitation acceptance is tested as a core
service but is not yet integrated as a complete browser workflow.

The complete P1 platform has not been accepted. Institutional governance,
production hosting, invitation screens, additional export profiles, reminder
scheduling, full management/browser/assistive-technology acceptance, and
scientific author metadata remain tracked in `docs/IMPLEMENTATION_STATUS.md`
and `docs/requirements-matrix.md`.

## Local environment and continuation

PostgreSQL runs in `delphyr-dev-postgres`, exclusively on 127.0.0.1:55439,
database `delphyr`. The app and worker use `delphyr_runtime`; migrations use a
separate owner connection. Private files remain in `.local/`, `.checks/`,
`.artifacts/`, and `.R-library/`. The local authentication path uses
127.0.0.1:4189 and an isolated Docker backend network.

`HANDOVER.md` lists reproducible commands. Inspect current processes and Git
status before continuing; do not rely on old process IDs. No external email or
production use has been authorized.

## Live runtime snapshot

Recheck process identity and ports before changing anything; these PIDs are
observations, not durable service identifiers.

| Component | Observed state |
|---|---|
| Manager demo | PID 1686791, `Rscript scripts/start-demo.R manager`, listening on `127.0.0.1:3849` |
| Local job/sink worker | PID 1751858, `Rscript scripts/worker.R` |
| PostgreSQL | `delphyr-dev-postgres`, up, `127.0.0.1:55439` |
| Authentication sandbox | `delphyr-auth-app`, `-gateway`, `-proxy`, `-keycloak` up; proxy `127.0.0.1:4189`, Keycloak `127.0.0.1:4190` |
| Panel/QA previews | No listener on 3850 or 3868; trilingual QA server stopped after independent receipt verification |

The authentication containers were not rebuilt for the language/branding commit;
their running state does not establish that they contain current sources.
The manager script uses source loading and reuses `.local/demo-fixture.rds`.
That older fixture may display German titles or lack French instrument wording;
its approved content is intentionally unchanged. Fresh `demo_study()` fixtures
include EN/FR/DE. Do not delete fixtures or rewrite approved data to change the UI.
The local installed package library was built before the final logo replacement;
reinstall before checking installed-asset identity. Hosted CI checked the final commit.

## Latest user decisions and completed work

- Exact repository/brand spelling: `delphyR`; technical packages: `delphyr` and
  `delphyrApp`. Documentation is English; UI is EN/FR/DE with English default.
- Match brainwritR petrol `#0e6e78` and red `#b3372b`. Dolphin badge uses the CTTIR
  dark hex, restrained illustration and external monospaced wordmark.
  Canonical shipped asset: `packages/delphyrApp/inst/www/delphyR-hex.png`.
- Repository description and topics have been updated and verified on GitHub.
- The language, documentation, metadata and logo requests are implemented and
  pushed. No code operation remains in progress. Local demo services remain up.
- The current request is a durable takeover checkpoint. Future product work
  should start from the open gates, not repeat the completed re-audit.
