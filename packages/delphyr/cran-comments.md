## Submission

This is a new submission. The companion package 'delphyrApp', which imports
'delphyr', will be submitted after 'delphyr' has been accepted.

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  Maintainer: 'Raban Heller <raban.heller@uni-ulm.de>'
  New submission

  This is the expected note for a first submission.

## Test environments

* local: macOS 27.0.1 (aarch64-apple-darwin), R 4.6.1,
  `R CMD check --as-cran` on the built tarball, including the PDF manual
  (TinyTeX, TeX Live 2026) and the HTML manual validation (HTML Tidy 5.8.0).
* GitHub Actions (r-lib/actions v2, `--as-cran`): ubuntu-latest (R devel,
  release, oldrel-1), macos-latest (R release), windows-latest (R release).
* GitHub Actions, ubuntu-latest (R release) with a PostgreSQL 17 service:
  the database, recovery and report-rendering tests that are opt-in.

## Notes

* Offline analysis, the runnable examples and the vignette use synthetic data
  and need neither a database nor network access; they write only to
  `tempdir()`.
* The study services work on a PostgreSQL database. Their examples are
  wrapped in `\dontrun{}` because they need a running PostgreSQL server
  prepared with `migrate_repository()`; each example says so in a comment.
* Tests that need a PostgreSQL server run only when explicitly enabled with an
  environment variable; tests that render reports with the external 'Quarto'
  program are skipped on CRAN and when 'Quarto' is not installed.
* 'RPostgres' (Suggests) is needed only to connect to a study database.
