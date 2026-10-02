# Current state

As of **3 October 2026**. Repository `CTTIR/delphyR`, branch `main`, workspace
`/data/GitHub/CTTIR/public/delphyR`. Use `git log -1` for the current commit;
the evidence below names the commits it was recorded against.

## Where the project stands

The roadmap of the specification is implemented up to and including phase 6
("report and operation"): every P1 requirement has its technical component
and evidence on synthetic data, and each of the twelve technical gates of
P1 has its evidence ([implementation status](docs/IMPLEMENTATION_STATUS.md),
[requirements matrix](docs/requirements-matrix.md),
[release report](docs/validation/2026-10-03.md)). The acceptance decision has
not been taken. Phase 7, a pilot and the release for a real study, depends on
decisions of the responsible organisation that the software does not make:
hosting, identity provider, message provider, retention and removal policy,
consent texts, recovery objectives.

## Evidence of the latest step

- Offline 407, PostgreSQL 1 346, application 657 assertions; both packages
  `Status: OK`; 17 migrations on an empty database and as an upgrade of a
  database holding data; the two-round service scenario. Hosted CI passed for `27a2aeb` ([run](https://github.com/CTTIR/delphyR/actions/runs/37075501075)).
- Browser checks in Chromium against PostgreSQL, the core path also in
  Firefox, among them scenario 1 at its specified size through the interface,
  keyboard-only rating and submission, and rights revoked in an open page.
- The local OIDC gateway with one, two and three application processes,
  session lifetimes and sign-out; stock Shiny Server OSS stays unqualified.
- Load: 50 browser sessions on a round of 150 items in two dimensions; the
  two-second target is met with six application processes.
- Restore rehearsal including the use of the restored database through the
  services.

## Local environment

| Component | State |
|---|---|
| PostgreSQL | container `delphyr-dev-postgres`, `127.0.0.1:55439`, database `delphyr`; app and worker use `delphyr_runtime` |
| Authentication fixture | `delphyr-auth-keycloak` (`127.0.0.1:4190`), `-proxy` (`127.0.0.1:4189`), `-gateway`, `-app` with the direct backend and one application process, image built from the current packages |
| Demo applications and worker | not running; start them as described in [operations](docs/operations.md) |
| Load fixture | study `QA-LOAD-a05e07d2` with 300 members (`.local/load-fixture.rds`); five load runs and earlier experiments used most of its members, so a further run needs a new fixture from `load-fixture-postgres.R` |

Private files stay in the ignored `.local/`, `.checks/`, `.artifacts/` and
`.R-library/`; credentials of the fixture are in `.local/auth/` and are never
printed or copied. `admin/` stays local and ignored. No external message has
been sent and no production system has been touched.
