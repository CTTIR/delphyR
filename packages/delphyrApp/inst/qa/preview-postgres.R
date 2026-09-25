# Run from the repository root against the disposable development database.
if (!identical(Sys.getenv("DELPHYR_TEST_DB"), "true")) {
  stop("Set DELPHYR_TEST_DB=true to opt into the synthetic PostgreSQL check.")
}
if (dir.exists(".R-library")) {
  .libPaths(c(normalizePath(".R-library"), .libPaths()))
}
pkgload::load_all("packages/delphyr", quiet = TRUE)
pkgload::load_all("packages/delphyrApp", quiet = TRUE)
fixture_path <- Sys.getenv("DELPHYR_QA_FIXTURE", ".checks/browser-fixture.rds")
dir.create(dirname(fixture_path), recursive = TRUE, showWarnings = FALSE)
if (file.exists(fixture_path)) {
  stop("Fixture already exists; choose a new DELPHYR_QA_FIXTURE path.")
}
connection <- list(
  host = Sys.getenv("DELPHYR_DB_HOST", "127.0.0.1"),
  port = as.integer(Sys.getenv("DELPHYR_DB_PORT", "55439")),
  dbname = Sys.getenv("DELPHYR_DB_NAME", "delphyr"),
  environment = "development",
  artifact_root = file.path(getwd(), ".artifacts")
)
# Provisioning requires the development administrator. The browser uses the
# restricted runtime role after provisioning has finished.
admin <- do.call(delphyr::connect_repository, c(connection, list(
  user = Sys.getenv("DELPHYR_DB_ADMIN", "postgres")
)))
fixture <- tryCatch({
  f <- delphyr::demo_study(admin, n = 2L, item_count = 1L)
  for (target in c("review", "approved", "open")) {
    delphyr::transition_round(
      admin, f$manager, f$round$id, target, f$round$hash,
      "Synthetic browser qualification", uuid::UUIDgenerate()
    )
  }
  f
}, finally = DBI::dbDisconnect(admin$con))
saveRDS(fixture, fixture_path)
runtime <- do.call(delphyr::connect_repository, c(connection, list(
  user = Sys.getenv("DELPHYR_DB_RUNTIME", "delphyr_runtime")
)))
actor <- delphyr::demo_actor(runtime, fixture$panel[[1]]$principal_id)
tryCatch(
  shiny::runApp(
    delphyrApp::run_app(runtime, actor, language = "en"),
    host = "127.0.0.1", port = 3868L, launch.browser = FALSE
  ),
  finally = DBI::dbDisconnect(runtime$con)
)
