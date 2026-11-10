## Submission

This is a new submission. 'delphyrApp' imports 'delphyr', which is submitted
first; this package will be submitted only after 'delphyr' is on CRAN.

## R CMD check results

0 errors | 1 warning | 0 notes (local check while 'delphyr' is not yet on CRAN)

* checking CRAN incoming feasibility ... WARNING
  Maintainer: 'Raban Heller <raban.heller@uni-ulm.de>'
  New submission
  Strong dependencies not in the CRAN or BioC software repositories:
    delphyr

  This warning disappears once 'delphyr' has been accepted; otherwise the
  check is clean.

## Test environments

* local: macOS 27.0.1 (aarch64-apple-darwin), R 4.6.1,
  `R CMD check --as-cran` on the built tarball, including the PDF manual
  (TinyTeX, TeX Live 2026) and the HTML manual validation (HTML Tidy 5.8.0),
  with 'delphyr' 0.1.0 installed from its source tarball.
* GitHub Actions (r-lib/actions v2, `--as-cran`): ubuntu-latest (R devel,
  release, oldrel-1), macos-latest (R release), windows-latest (R release),
  with 'delphyr' installed from the same repository.

## Notes

* The application needs a migrated PostgreSQL database and an interactive
  session, so the example of `run_app()` is wrapped in `\dontrun{}` with a
  comment. The tests exercise the 'shiny' modules with `shiny::testServer()`
  and in-memory service doubles; they need no database or network access and
  write only to `tempdir()`.
