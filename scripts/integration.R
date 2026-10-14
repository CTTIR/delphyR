# Run from the repository root. Only the isolated local test PostgreSQL is used.
# DELPHYR_TEST_DB_NAME selects another database of that server (default
# delphyr), so that two working copies can be tested at the same time.
if (Sys.getenv("DELPHYR_TEST_DB") != "true") {
  stop("Opt in explicitly with DELPHYR_TEST_DB=true Rscript scripts/integration.R")
}
root <- normalizePath(".")
stopifnot(file.exists(file.path(root, "packages/delphyr/DESCRIPTION")))
.libPaths(c(file.path(root, ".R-library"), .libPaths()))
Sys.setenv(DELPHYR_SOURCE_ROOT = root)
pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
r <- connect_repository(
  host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"),
  user = "postgres", environment = "test"
)
tryCatch(migrate_repository(r), finally = DBI::dbDisconnect(r$con))
# The listed files run in this order and each must exist. A contract file
# that needs the database but is not listed runs after them: no contract is
# skipped without notice.
directory <- file.path(root, "packages/delphyr/tests/testthat")
listed <- c("test-services.R", "test-service-contracts.R", "test-jobs.R", "test-qualitative.R", "test-communications.R", "test-authentication.R", "test-reporting.R", "test-protocols.R", "test-panel-import.R", "test-participation.R", "test-invitations.R", "test-languages.R", "test-round-lifecycle.R", "test-audit-documentation.R", "test-study-export.R", "test-administration.R", "test-exploratory.R", "test-delivery.R", "test-security.R", "test-large-rounds.R", "test-operations.R")
missing <- listed[!file.exists(file.path(directory, listed))]
if (length(missing)) stop("Listed contract files are missing: ", paste(missing, collapse = ", "))
present <- list.files(directory, pattern = "^test-.*[.]R$")
gated <- present[vapply(file.path(directory, present), function(f) any(grepl("DELPHYR_TEST_DB", readLines(f, warn = FALSE), fixed = TRUE)), logical(1))]
files <- c(listed, sort(setdiff(gated, listed)))
for (file in files) testthat::test_file(file.path(directory, file), stop_on_failure = TRUE)
cat(sprintf("PostgreSQL contracts: %d files passed.\n", length(files)))
