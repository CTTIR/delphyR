# Run after browser-postgres.R has completed against preview-postgres.R.
if (!identical(Sys.getenv("DELPHYR_TEST_DB"), "true")) {
  stop("Set DELPHYR_TEST_DB=true to opt into the synthetic PostgreSQL check.")
}
if (dir.exists(".R-library")) {
  .libPaths(c(normalizePath(".R-library"), .libPaths()))
}
pkgload::load_all("packages/delphyr", quiet = TRUE)
fixture <- readRDS(Sys.getenv("DELPHYR_QA_FIXTURE", ".checks/browser-fixture.rds"))
runtime <- delphyr::connect_repository(
  host = Sys.getenv("DELPHYR_DB_HOST", "127.0.0.1"),
  port = as.integer(Sys.getenv("DELPHYR_DB_PORT", "55439")),
  dbname = Sys.getenv("DELPHYR_DB_NAME", "delphyr"),
  user = Sys.getenv("DELPHYR_DB_RUNTIME", "delphyr_runtime"),
  environment = "development", artifact_root = file.path(getwd(), ".artifacts")
)
tryCatch({
  actor <- delphyr::demo_actor(runtime, fixture$panel[[1]]$principal_id)
  enrollment <- delphyr::list_enrollments(runtime, actor, fixture$study_id)
  stopifnot(nrow(enrollment) == 1L)
  questionnaire <- delphyr::get_questionnaire(runtime, actor, enrollment$id)
  stopifnot(
    identical(questionnaire$enrollment$state, "submitted"),
    nrow(questionnaire$receipt) == 1L,
    nrow(questionnaire$responses) == 1L,
    questionnaire$responses$value_int == 7L,
    questionnaire$responses$revision == 1L,
    isTRUE(questionnaire$consent$accepted)
  )
  print(list(
    database_role = DBI::dbGetQuery(runtime$con, "SELECT current_user")[[1]],
    state = questionnaire$enrollment$state,
    consent = questionnaire$consent$accepted,
    value = questionnaire$responses$value_int,
    revision = questionnaire$responses$revision,
    receipt = questionnaire$receipt$id
  ))
}, finally = DBI::dbDisconnect(runtime$con))
