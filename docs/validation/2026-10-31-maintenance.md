# Maintenance audit — 31 October 2026

Scope: public delphyR, isolated from the original working copy. Base
`02e81e5b3f4f9b53eaaf6d66d86750a74261aa26`. The original 52 modified tracked
files and 11 untracked files already match upstream byte-for-byte and remain
untouched. This is synthetic-development qualification, not study approval.

## Evidence and strategy before implementation

Confirmed offline probes:

* Adjacent doubles around 0.7 serialize identically and produce the same
  scientific content hash. A threshold can therefore change without provenance
  changing, and persistence can change a consensus boundary. Repair numeric
  serialization and version the hash contract; preserve verification of earlier
  records explicitly, without silently rewriting recorded hashes or migrations.
* `new_scale()` accepts 2147483648, then coerces it to missing with a warning.
  Reject categories outside the supported R/PostgreSQL integer range before
  conversion; protect the input contract with boundary tests.
* `compare_rounds()` pairs identical participant codes from different study
  codes. Require the same study identity before making paired claims.
* Summary exports suppress a small cell in the statistics but repeat its
  classification in the final-item table and report. Suppression must cover
  both routes; the authorized research export retains its full results.
* Signed zero can make the hash of a table depend on row order. Normalize
  numeric zero in version 2 while keeping legacy verification unchanged.
* An item version above R's integer limit is accepted when constructing a
  snapshot but becomes missing on JSON reconstruction. Validate before storage.

The baseline core suite passed 443 assertions, with 124 database-gated test
blocks skipped; the application suite passed 1,626 assertions without skips.
Neither had failures or warnings. Logs and serialized results are retained
under the workspace audit's `evidence/delphyR/`. Existing October 3 reports
are historical and will not be relabelled as current evidence.

| Finding | Severity / impact | Main location | Repair |
|---|---|---|---|
| Numeric JSON and hash collision | High: a threshold and classification can change during storage without provenance changing | `conditions.R`, `snapshots.R`, app `setup.R` and `protocols.R` | Exact JSON and explicitly versioned hashes; legacy fixtures and threshold boundary tests |
| Summary classification disclosure | High: a suppressed small-cell result remains visible | `study_export.R` | Filter final-item classifications with the same disclosure policy; verify JSON, CSV and report data |
| Foreign-study pairing | High: unrelated pseudonyms are described as repeated participants | `analytics.R` | Require matching study code before pairing |
| Integer overflow | Medium: accepted ratings or versions become missing, or valid paired differences overflow | `domain.R`, `analytics.R` | Bound coercible values and calculate differences as doubles |
| Signed-zero table identity | Medium: row reordering changes scientific identity | `conditions.R` | Normalize zero in the new contract only |

The fixed legacy fixtures come from the unmodified base commit, not the new
implementation's compatibility branch. Their snapshot, result, rules and
feedback hashes are fixed test oracles. Service tests also exercise existing
approvals and retry receipts. A receipt retains the exact preview hash that
was approved, even when that preview predates the new contract.

## Milestones and acceptance

1. Repair scientific identity and invalid inputs, with meaningful failing
   baseline examples, compatibility fixtures and exact numeric round trips.
2. Exercise real transactional services in an isolated PostgreSQL instance:
   permissions, concurrent saves/submission/close, exports, offline reproduction,
   migrations, worker recovery and a complete synthetic study journey.
3. Audit application and packaging boundaries; fix confirmed material defects,
   run both package checks and realistic browser journeys, document first use.
4. Review the final changes independently. Record exact results and limitations.
   Production authentication, institutional study approval, real recruitment,
   external messages and publishing remain separate gates. Longer-term features
   and cosmetic restructuring are outside this maintenance increment.

## Additional confirmed findings and repairs

* Both trusted HTML templates used jsonlite's default display precision. A
  stored threshold of `0.70000000000000007` appeared as `0.7`; parsing the
  displayed protocol changed the fixture's decision from `no_consensus` to
  `consensus_in`. Both templates now serialize displayed JSON with 17 digits.
  Two actual Quarto renders verify the displayed protocol, classification,
  result hash, output creation and working-directory restoration (22 passing
  assertions). Original and corrected HTML are retained in the audit evidence.
* On macOS, an R temporary path through `/var` and its canonical working
  directory through `/private/var` made Quarto/Pandoc construct an invalid
  relative output path. The render job failed with `DEL_RENDER` and no report.
  The renderer now resolves the staging directory and renders its local input
  basename. The real failing wrapper and corrected wrapper were both exercised;
  no timeout was enlarged. The fixed command follows the
  [Quarto render interface](https://quarto.org/docs/cli/render.html).
* The bootstrap checked only package presence, so an installed package below
  its declared minimum was silently retained. It now checks DESCRIPTION
  constraints and the exact recorded documentation generator before loading
  namespaces. Selection regressions cover outdated dependencies, version pins
  and archived-generator dependencies.
* Recovery used a Unix socket under the checkout, exceeding its path limit in
  the observed long checkout. Its Docker mode also depended on host access to
  a Linux-container socket; that transport was unverified on macOS. The
  rehearsal now supports native PostgreSQL with a short private socket and TCP
  disabled; Docker recovery explicitly requires native Linux.
* Recovery treated all export profiles as round-analysis exports. Verification
  now follows the registered profile: both research profiles reproduce their
  analyses; summary, audit and contact profiles receive exact manifest and
  checksum checks, without a false analysis-reproduction claim.

The report regression is included in ordinary package tests. CI now installs
an explicitly pinned Quarto release so this behavior is exercised rather than
skipped for a missing optional runtime. Hosted CI of these changes has not run.

## Current verification

* Both final 0.0.2 source archives passed `R CMD check --as-cran
  --no-manual`: `Status: OK`. The installed core suite passed 557 assertions
  with 130 explicit database/source-context skips; the application suite passed
  1,649 assertions without skips. Neither had failures or warnings. As in the project check script, CRAN
  incoming checks were disabled; these are not CRAN acceptance results. Database
  contracts run separately against the source tree with explicit opt-in.
* Fresh-database application of all 18 migrations, an idempotent second run,
  refusal of an edited migration checksum, and upgrade of a populated previous
  schema all passed. Stored responses, snapshot hashes and analysis results
  were unchanged across the upgrade.
* Deterministic browser qualification passed 20 checks. The separate actual
  PostgreSQL browser path passed 25 checks, including persisted consent,
  rating, explicit submission, receipt and reload through the restricted role.
  The initial runs used Playwright and their screenshots were visually
  inspected. With the optional chromote runtime available, both actual
  shipped R drivers (`browser-smoke.R`, `browser-postgres.R`) also passed.
  `verify-postgres.R` independently confirmed consent, a submitted response of
  7 at revision 1, and the same receipt through the restricted database role.
  These follow-up checks used a separate fresh database, installed no packages,
  preserved the global role settings and stopped their owned browser/servers.
* The corrected round HTML report was opened at 1280 and 390 pixel widths:
  no page errors or page overflow were observed; long JSON blocks scroll
  within the report. Both templates' precision is checked in actual HTML.

* Both archives installed into an initially empty project-package library,
  excluding the development package library. Existing dependency libraries were
  reused. The README analysis produced ten valid ratings, seven agreement
  ratings and one disagreement, `consensus_in`, and an empty group labelled
  `insufficient_data`; feedback validation and the installed vignette passed.
  Full clean dependency provisioning was not performed.
* All 71 non-base runtime/build dependencies recorded in `renv.lock` match the
  libraries actually used, including 277 checked dependency constraints.
  Bootstrap selection regressions, eight Python recovery tests, 25 R recovery
  assertions, shell syntax and actionlint passed.
* The shipped two-round demonstration passed in a separate fresh synthetic
  database: 30 participants, 12 trilingual items, 720 committed responses,
  participant-specific feedback, queued analysis, completion and round-export
  offline reproduction.

* All five export profiles passed manifest, file-set, byte-size and checksum
  verification. Both research profiles reproduced their analyses offline;
  the two-round export reproduced 12 comparisons with 30 paired respondents.
  The contacts export was valid but empty; no imported contacts were present.
* A complete native PostgreSQL recovery rehearsal passed: 59 tables, schema,
  18 migration checksums, two frozen snapshots, all five artifact profiles and
  nine restored application checks. The original database signatures and
  artifact bytes were unchanged. The owned target process, cluster directory
  and private socket were removed. The first rehearsal used an empty message queue; the additional case below
  qualifies the populated-queue path.
* The first recovery attempt exposed a timezone-dependent fingerprint:
  identical timestamps were serialized in UTC by the source and CET by the
  restored server. A read-only comparison in the same zone demonstrated the
  cause. Both comparison sessions now explicitly use UTC. The initial failed
  evidence is retained; the complete corrected rehearsal took 37.672 seconds.
  That measurement is not a production recovery-time objective.
* Independent app review found no material regression in the changed
  protocol, localization, summary or amendment paths. The original checkout
  still has its original HEAD, branch and status; all 63 changed/untracked
  files remain byte-identical to the upstream base already observed at start.

* An additional independent recovery fixture contained an imported synthetic
  contact and two eligible waiting reminders. Its restored copy held both
  messages before the worker ran and produced no sink receipt. The contacts
  CSV recovered its one row and recorded checksum; all five profiles and the
  restored services passed again. The source retained two queued messages,
  no held messages or receipts, its contact and all original artifact bytes.
  The additional target and socket were removed. This second qualified
  rehearsal took 34.691 seconds; it still makes no SMTP or production claim.

The orchestrated database run completed its first 22 files successfully.
The final file then failed in fixture setup: its newly added synthetic account
name lacked the required `demo-` prefix. The production identity guard correctly
refused it. Only the fixture name was corrected. The complete final file then
passed all 31 assertions, including its three PostgreSQL precision checks, with
no failures, warnings or skips against the same audit database. All 23 database
contract files are therefore covered across the full run and focused rerun; the
entire orchestration command was not repeated after that test-only correction.
Both the initial failure and successful focused result are retained.

All owned browser hosts and the native PostgreSQL server were stopped after
their checks; synthetic data, dumps and verification evidence are retained.

## First use and readiness boundary

The qualified local toolchain is macOS ARM64, R 4.6.1, PostgreSQL 17.11 and
Quarto 1.10.19. Offline analysis requires neither PostgreSQL nor Quarto. The
local application path additionally requires Docker Compose and the synthetic
PostgreSQL service described in the root README. Source dependency installation
may require a C/C++ compiler and the platform development libraries.

From this checkout, the offline first-use path is:

```sh
Rscript scripts/bootstrap.R
export R_LIBS_USER="$PWD/.R-library${R_LIBS_USER:+:$R_LIBS_USER}"
R CMD build packages/delphyr
R CMD INSTALL --library=.R-library delphyr_0.0.2.tar.gz
Rscript -e 'library(delphyr); x <- analyse_round(demo_snapshot()); print(x$decisions); stopifnot(validate_feedback(prepare_feedback(x)))'
```

For the Shiny manager and panel journey, follow the root README's separate
worker and application terminals. Only deliberately submitted ratings enter
analysis. For a restore rehearsal with export files, select the study UUID and
artifact directory as documented in the recovery runbook.

This increment qualifies synthetic development use on the observed local
runtime. Current browser checks cover the panel journey; a complete current
management journey in the browser and assistive-technology testing were not
performed. The service-level two-round journey and application unit tests are
separate evidence. This increment does not repeat the historical OIDC-gateway
or load qualification,
qualify a new production host, demonstrate SMTP delivery, obtain institutional
approval, or establish production recovery objectives. Linux Docker recovery
and hosted CI of these commits remain unobserved. Legacy hashes retain their
original precision limitation; no historical data or migration is rewritten.
The remaining production gates in the implementation-status document still
apply. No package has been submitted, published, pushed or deployed by this
audit. The next external release step is review of the local maintenance
commits, authorized publication and successful hosted CI, followed by the
separate production acceptance process if production use is intended.
