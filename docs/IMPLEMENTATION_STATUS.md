# Implementation status

As of 3 October 2026: version 0.0.1, synthetic development only. The
software is at commit `2838509`; later commits add checks, fixture scripts
and documentation. The release report with every number and the commit each
check ran against is [validation of 3 October 2026](validation/2026-10-03.md).

The specification keeps three statements apart
([acceptance](spec/26_ACCEPTANCE_AND_RELEASE.md)); so does this page.

| Statement | State |
|---|---|
| Documentation package complete | Yes: the archived specification under `docs/spec/`. |
| Software technically ready (P1) | Evidence is recorded for each of the twelve technical gates below, on synthetic data and for one hosting path. The limits are listed. The acceptance decision belongs to the responsible persons and has **not** been taken. |
| Study released for productive use | **No.** The decisions under "External gates" are outstanding. No real participant data, no external message and no production deployment are authorized. |

The current user decision is English public documentation and an en/fr/de
interface with English as default ([ADR-017](adr/017-suite-conventions.md)).
The original German specification remains a verbatim archive.

## Technical gates of P1

| Gate | Required evidence | Evidence | Result |
|---|---|---|---|
| Method | Reference cases, denominators, groups and comparison of versions | `test-domain-analytics.R`, `test-core-contracts.R` (hand-computed cases, metamorphic tests); scenario 1 with hand-computed classifications | passed |
| Storage | Save, submit and close under concurrency; retry | `test-services.R`, `test-service-contracts.R`, `test-participation.R` (independent processes, database locks as barriers); load runs: 60 000 confirmed saves, none lost | passed |
| Isolation | Two studies, two persons, export rights | `test-security.R` (every service with the identifiers of another study and of another person), `test-study-export.R`, `browser-revocation-postgres.R` | passed |
| Identity | Real gateway path, binding to the subject, session limits | [Gateway qualification](authentication.md) with one, two and three application processes: 27, 30 and 30 checks, and four checks of session lifetimes | passed for the directly served application; stock Shiny Server OSS drops the identity headers and stays unqualified |
| Feedback | Frozen release, own previous answer, suppression | `test-services.R`, `test-domain-analytics.R`, `test-exploratory.R` (correction by a new version), scenario 1 in the browser | passed |
| Qualitative | Origin to final item exportable | `test-qualitative.R`, `test-exploratory.R`, `browser-exploratory-postgres.R` | passed |
| Communication | Approval, sink, retry and uncertain delivery documented | `test-communications.R`, `test-delivery.R`, `browser-communications-postgres.R`, [communications](communications.md) | passed in the local sink and against test doubles; no provider adapter is shipped |
| Reporting | Independent offline reproduction from an export | `test-study-export.R`, `test-reporting.R`, `scripts/demo-e2e.R`, scenario 1 | passed |
| Operation | Migration, restart, worker resumption, backup and restore | `scripts/migration-empty.R` (empty database; previous release with data), `test-jobs.R`, `test-operations.R`, `scripts/restore-check.sh` with the function check | passed; no production recovery objectives |
| Usability | Core path on a narrow screen and by keyboard | `browser-accessibility-postgres.R`, `browser-firefox-postgres.R`, 390 and 320 pixel checks | passed in Chromium and Firefox; no test with a screen reader |
| Performance | Defined load test; target met or approved limits | [Load qualification](load.md): 50 sessions, 150 items in two dimensions | target met with six application processes; one process serves about eight people rating at once |
| Documentation | Installation, use and incidents | [README](../README.md), [user guide](user-guide.md), [operations](operations.md), eleven [runbooks](runbooks/README.md), [governance material](governance/README.md) | present |

## End-to-end scenarios

The ten scenarios of the specification
([chapter 32](spec/32_END_TO_END_SCENARIOS.md)). "Browser" is Chromium against
PostgreSQL under the restricted application role.

| Scenario | Evidence | Size and boundary |
|---|---|---|
| 1 Complete modified Delphi | `browser-scenario1-postgres.R` | As specified: 30 members in two groups, 12 items, two rounds; every staff step in the interface; identity from headers as behind a gateway, not OIDC |
| 2 Exploratory free-text round | `test-exploratory.R`; `browser-exploratory-postgres.R` | Services as specified: eight members, five derived items, a minority position in the feedback; the browser run uses four members |
| 3 Interruption and two tabs | `browser-autosave-postgres.R` | Two tabs of one person, conflict without overwriting, connection loss, reload |
| 4 Deadline and closing | `test-services.R`, `test-service-contracts.R`; `browser-security-postgres.R` | Controlled concurrency of save, submit and close with independent processes; a late entry in the browser is refused |
| 5 Changed item | `test-audit-documentation.R`, `test-study-export.R`; `browser-governance-postgres.R` | Explicit decision "not comparable" with rationale; both versions exported |
| 6 Groups and missing data | `test-domain-analytics.R`, `test-study-export.R` | Insufficient data in a required group; small cells suppressed, also against subtraction from the total |
| 7 Right revoked during a session | `browser-revocation-postgres.R`; gateway qualification | Revocation in the interface; a foreign identifier; a forged identity header through the real gateway |
| 8 Reminder and late submission | `test-delivery.R` | As specified: ten members due, two submit, one withdraws, seven recorded, three suppressed with a reason; uncertain provider outcome separately |
| 9 Wrong release and correction | `test-exploratory.R`; `browser-exploratory-postgres.R` | New version with its own hash; earlier displays keep the earlier version |
| 10 Restore and reproduction | `scripts/restore-check.sh` | Dump, isolated restore, every table compared, function check through the services, messages held, exports recomputed; sign-in through the gateway on the restored instance not exercised |

## Verification

| Check | Result |
|---|---|
| Offline core tests (`scripts/check.R`) | 407 passed |
| PostgreSQL contracts (`scripts/integration.R`) | 21 files, 1 346 assertions, no failure, warning or skip |
| Application tests | 657 passed |
| Migrations (`scripts/migration-empty.R`) | 17 on an empty database, repeat idempotent, changed checksum refused, upgrade of a database holding a conducted round |
| Two-round service scenario (`scripts/demo-e2e.R`) | 720 committed responses, offline reproduction |
| Package checks | `Status: OK` for both packages |
| Hosted CI | passed for every commit of this step, the last `27a2aeb` ([run](https://github.com/CTTIR/delphyR/actions/runs/37075501075)) |
| Browser checks | all passed on 3 October 2026 against commit `27a2aeb` ([browser evidence](../packages/delphyrApp/inst/qa/README.md)) |
| Gateway | as above; stock Shiny Server OSS negative result reproduced |
| Load | target met with six application processes in two runs (95th percentile 1.28 s after the pause), missed with four (2.38 and 2.11 s); no confirmed write lost in 60 000 |
| Restore | passed with the exports of one study: 59 tables, 836 snapshots and 17 migrations identical; the services used the restored database (227 waiting messages held, a member's and a staff read, two snapshots verified and analysed again); the export reproduced offline |

## Known limits of the software

- **Hosting.** Identity is qualified for the application served directly by
  `shiny::runApp()` behind an OIDC gateway. Stock Shiny Server OSS, which the
  specification names as reference, does not pass the identity headers to the
  session. All gateway evidence is local, over HTTP, with a development
  identity provider.
- **Capacity.** One application process serves about eight people rating at
  the same time within the two-second target on the measured hardware. Fifty
  need six to seven processes behind a gateway that routes by account. Some
  management operations on a round of specification size occupy their process
  for seconds.
- **Messages.** Only the local sink is delivered to. The provider contract is
  exercised with test doubles; no adapter for a real provider exists, and
  bounces or complaints are not processed.
- **Removal of data.** Withdrawal stops collection and messages and keeps
  earlier data. No function removes or anonymises responses, consent records
  or contacts; the software ships no retention period
  ([retention](governance/retention.md)).
- **Accessibility.** Keyboard operation, names, headings, contrast and reflow
  are checked by script in Chromium, the core path also in Firefox. There is
  no test with a screen reader, with Safari or on a mobile device, and no
  statement of conformance.
- **Languages.** The interface exists in English, French and German. Study
  content is shown as authored; nothing is translated automatically.
- **Recovery.** The restore rehearsal covers the synthetic database and one
  study's exports. Point-in-time recovery, recovery objectives and the
  sign-in on a restored instance are not covered.
- **Scope.** Real-time Delphi and rankings are P2 and absent. No CRAN
  submission and no scientific or clinical validation is claimed.

## External gates before any real study

These are decisions and qualifications of the responsible organisation. The
software does not invent them.

- Legal basis, study information and consent texts, retention and removal
  policy, the processing record ([template](governance/processing-record-template.md)).
- A hosting decision and its qualification with TLS, secret management,
  separated operational roles, monitoring and recovery objectives.
- The institution's identity provider: account lifecycle, MFA, central logout.
- A message provider with an approved sender and contact policy, and its
  adapter.
- Translations of study content, panel criteria, consensus and stopping rules
  of the actual study.
- A pilot with real users, including people who use assistive technology, and
  the acceptance decision with the names and date of those who take it.

## How the current state was reached

Each step has a decision record: invitation screens and
[automatic saving](adr/019-automatic-saving.md),
[round readiness](adr/020-round-lifecycle-and-readiness.md),
[export profiles and documentation](adr/021-export-profiles-and-study-documentation.md),
[study administration](adr/022-study-administration-in-the-interface.md),
[exploratory rounds](adr/023-exploratory-rounds-and-feedback-content.md),
[communication rules](adr/024-communication-schedule-and-delivery.md),
[technical log](adr/025-technical-log-and-references.md),
[large rounds and blocks](adr/026-large-rounds-and-blocks.md),
[operations and deadlines](adr/027-operations-status-and-deadlines.md) and
[sessions, processes and restore](adr/028-sessions-processes-and-restore.md).
The checkpoint of 25 September 2026 is recorded in
[validation of 25 September](validation/2026-09-25.md).

Hosted CI failed once, for commit `5bf26c7`, at the package check (non-ASCII
characters in a source file); the following commit repaired it and both
packages carry a source-level ASCII test.

`admin/`, data, backups and local libraries remain ignored. Entry points:
[README](../README.md), [operations](operations.md), [HANDOVER](../HANDOVER.md).
