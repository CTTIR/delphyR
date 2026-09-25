contract_repo <- function(env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  skip_if_not_installed("RPostgres")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(r$con), envir = env)
  r
}
contract_fixture <- function(r) {
  f <- demo_study(r, n = 2L, item_count = 1L, code = paste0("CONTRACT-", uuid::UUIDgenerate()))
  for (state in c("review", "approved", "open")) {
    transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic contract test", state)
  }
  f$actor <- f$panel[[1]]
  f$enrollment <- list_enrollments(r, f$actor, f$study_id)$id[1]
  f$item <- get_questionnaire(r, f$actor, f$enrollment)$items$id[1]
  record_consent(r, f$actor, f$study_id, f$consent_id, TRUE, "consent")
  f
}
contract_finalize <- function(r, f) {
  saved <- save_response(r, f$actor, f$enrollment, f$item, list(value = 7L, status = "answered"), 0L, "save")
  submit_round(r, f$actor, f$enrollment, setNames(saved$revision, f$item), "submit")
  transition_round(r, f$manager, f$round$id, "closed", f$round$hash, "Synthetic close", "close")
  s <- freeze_round(r, f$manager, f$round$id, "freeze")
  run_analysis(r, f$manager, s$id, "analyse")
  transition_round(r, f$manager, f$round$id, "finalized", f$round$hash, "Synthetic finalization", "finalize")
}

test_that("later rounds enforce entry policies and stable item-version content", {
  r <- contract_repo()
  f <- contract_fixture(r)
  contract_finalize(r, f)
  newcomer <- demo_actor(r, provision_demo_principal(r, paste0("demo-new-", f$study_id)))
  add_panelist(r, f$manager, f$study_id, newcomer$principal_id, "professionals", "new-panel")
  deadline <- format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  changed <- f$items
  changed$text[1] <- "Changed scientific wording"
  expect_error(prepare_round(r, f$manager, f$study_id, changed, f$consent_id, deadline, "changed-version"), class = "DEL_CONFLICT")
  changed$item_version <- 2L
  next_round <- prepare_round(r, f$manager, f$study_id, changed, f$consent_id, deadline, "round-2")
  enrolled <- DBI::dbGetQuery(r$con, "SELECT panelist_id FROM research.enrollments WHERE round_id=$1", params = list(next_round$id))
  first_person <- DBI::dbGetQuery(r$con, "SELECT panelist_id FROM research.enrollments WHERE id=$1", params = list(f$enrollment))
  expect_identical(enrolled$panelist_id, first_person$panelist_id)
  expect_equal(nrow(list_enrollments(r, newcomer, f$study_id)), 0L)
  expect_equal(nrow(list_enrollments(r, f$panel[[2]], f$study_id)), 1L)
})

contract_waiting_save <- function(r, f, name, env = parent.frame()) {
  skip_if_not_installed("callr")
  root <- Sys.getenv("DELPHYR_SOURCE_ROOT")
  skip_if(!nzchar(root), "Source root required for independent connection")
  child <- callr::r_bg(function(root, libs, f, name) {
    .libPaths(libs)
    pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
    r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test", application_name = name)
    on.exit(DBI::dbDisconnect(r$con))
    DBI::dbExecute(r$con, "SET statement_timeout='15s'")
    tryCatch(
      {
        save_response(r, f$actor, f$enrollment, f$item, list(value = 8L, status = "answered"), 0L, "waiting-save")
        "success"
      },
      delphyr_error = function(e) e$code
    )
  }, args = list(root, .libPaths(), f, name), supervise = TRUE)
  withr::defer(if (child$is_alive()) child$kill(), envir = env)
  until <- Sys.time() + 10
  repeat {
    DBI::dbGetQuery(r$con, "SELECT pg_stat_clear_snapshot()")
    st <- DBI::dbGetQuery(r$con, "SELECT wait_event_type FROM pg_stat_activity WHERE application_name=$1", params = list(name))
    if (nrow(st) == 1L && identical(st$wait_event_type, "Lock")) break
    if (!child$is_alive() || Sys.time() > until) stop("Save did not reach lock barrier: ", paste(child$read_error(), collapse = "; "))
    Sys.sleep(.025)
  }
  child
}

test_that("a blocked save rechecks capability after the lock is admitted", {
  r <- contract_repo()
  f <- contract_fixture(r)
  DBI::dbBegin(r$con)
  withr::defer(try(DBI::dbRollback(r$con), silent = TRUE))
  DBI::dbGetQuery(r$con, "SELECT id FROM research.enrollments WHERE id=$1 FOR UPDATE", params = list(f$enrollment))
  child <- contract_waiting_save(r, f, paste0("contract-revoke-", f$study_id))
  DBI::dbExecute(r$con, paste(
    "UPDATE identity.capabilities SET revoked_at=clock_timestamp()",
    "WHERE study_id=$1 AND capability='panel' AND membership_id IN",
    "(SELECT id FROM identity.memberships WHERE principal_id=$2)"
  ), params = list(f$study_id, f$actor$principal_id))
  DBI::dbCommit(r$con)
  child$wait(timeout = 20000)
  expect_identical(child$get_result(), "DEL_FORBIDDEN")
})

test_that("a blocked save cannot use the deadline captured before waiting", {
  r <- contract_repo()
  f <- contract_fixture(r)
  DBI::dbExecute(r$con, "UPDATE research.rounds SET deadline=clock_timestamp()+interval '3 seconds' WHERE id=$1", params = list(f$round$id))
  DBI::dbBegin(r$con)
  withr::defer(try(DBI::dbRollback(r$con), silent = TRUE))
  DBI::dbGetQuery(r$con, "SELECT id FROM research.enrollments WHERE id=$1 FOR UPDATE", params = list(f$enrollment))
  child <- contract_waiting_save(r, f, paste0("contract-deadline-", f$study_id))
  Sys.sleep(3)
  DBI::dbCommit(r$con)
  child$wait(timeout = 20000)
  expect_identical(child$get_result(), "DEL_ROUND_CLOSED")
})
