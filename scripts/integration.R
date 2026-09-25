# Run from the repository root. Only the isolated local test PostgreSQL is used.
if (Sys.getenv("DELPHYR_TEST_DB") != "true") {
  stop("Opt in explicitly with DELPHYR_TEST_DB=true Rscript scripts/integration.R")
}
root <- normalizePath(".")
stopifnot(file.exists(file.path(root, "packages/delphyr/DESCRIPTION")))
.libPaths(c(file.path(root, ".R-library"), .libPaths()))
Sys.setenv(DELPHYR_SOURCE_ROOT = root)
pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
r <- connect_repository(
  host = "127.0.0.1", port = 55439, dbname = "delphyr",
  user = "postgres", environment = "test"
)
tryCatch(migrate_repository(r), finally = DBI::dbDisconnect(r$con))
for (file in c("test-services.R", "test-service-contracts.R", "test-jobs.R", "test-qualitative.R", "test-communications.R")) {
  path <- file.path(root, "packages/delphyr/tests/testthat", file)
  if (file.exists(path)) testthat::test_file(path, stop_on_failure = TRUE)
}
