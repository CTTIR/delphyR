# Current state

As of 2026-09-25. Repository CTTIR/delphyR, branch main.
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
Hosted CI for the current changes is pending; the historical run does not
validate the current working tree.

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
