# These tests only use the explicitly opted-in, isolated loopback test database.
service_repo <- function(env = parent.frame()) {
  testthat::skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "PostgreSQL tests require DELPHYR_TEST_DB=true")
  testthat::skip_if_not_installed("RPostgres")
  r <- connect_repository(
    host = "127.0.0.1", port = 55439, dbname = "delphyr",
    user = "postgres", environment = "test"
  )
  withr::defer(DBI::dbDisconnect(r$con), envir = env)
  r
}
service_fixture <- function(r, open = TRUE) {
  f <- demo_study(r,
    n = 2L, item_count = 1L,
    code = paste0("TEST-", uuid::UUIDgenerate())
  )
  if (open) {
    for (state in c("review", "approved", "open")) {
      transition_round(
        r, f$manager, f$round$id, state, f$round$hash,
        "Synthetic integration test", state
      )
    }
  }
  f$actor <- f$panel[[1L]]
  f$enrollment <- list_enrollments(r, f$actor, f$study_id)$id[1L]
  f$item <- get_questionnaire(r, f$actor, f$enrollment)$items$id[1L]
  record_consent(r, f$actor, f$study_id, f$consent_id, TRUE, "consent")
  f
}
service_save <- function(r, f, value = 7L, revision = 0L, key = "save") {
  save_response(
    r, f$actor, f$enrollment, f$item,
    list(value = value, status = "answered"), revision, key
  )
}
service_count <- function(r, table, study) {
  stopifnot(table %in% c("research.response_revisions", "ops.commands", "ops.audit"))
  as.integer(DBI::dbGetQuery(r$con, paste0(
    "SELECT count(*) AS n FROM ", table,
    " WHERE study_id=$1"
  ), params = list(study))$n)
}

# Clear parameterized statements even when PostgreSQL rejects dbBind().
service_statement <- function(con, sql, params) {
  result <- DBI::dbSendStatement(con, sql)
  on.exit(DBI::dbClearResult(result))
  DBI::dbBind(result, params)
  invisible(DBI::dbGetRowsAffected(result))
}

test_that("current authority and person boundaries protect every request", {
  r <- service_repo()
  f <- service_fixture(r)
  other <- service_fixture(r)
  stranger <- f$panel[[2L]]
  expect_error(get_questionnaire(r, stranger, f$enrollment), class = "DEL_NOT_FOUND")
  expect_error(
    save_response(
      r, stranger, f$enrollment, f$item,
      list(value = 9L, status = "answered"), 0L, "foreign"
    ),
    class = "DEL_NOT_FOUND"
  )
  expect_error(get_questionnaire(r, other$actor, f$enrollment), class = "DEL_NOT_FOUND")
  expect_error(
    save_response(
      r, f$actor, f$enrollment, other$item,
      list(value = 9L, status = "answered"), 0L, "foreign-item"
    ),
    class = "DEL_NOT_FOUND"
  )
  expect_equal(service_count(r, "research.response_revisions", f$study_id), 0L)
  receipt <- service_save(r, f)
  set_capability(
    r, f$manager, f$study_id, f$actor$principal_id,
    "panel", FALSE, "revoke-panel"
  )
  expect_error(get_questionnaire(r, f$actor, f$enrollment), class = "DEL_FORBIDDEN")
  # A retry must still recheck authority before returning an old receipt.
  expect_error(service_save(r, f), class = "DEL_FORBIDDEN")
  expired <- f$manager
  expired$expires_at <- Sys.time() - 1
  expect_error(list_studies(r, expired), class = "DEL_UNAUTHORIZED")
  expect_true(nzchar(receipt$id))
})

test_that("revision conflicts and command replay preserve durable receipts", {
  r <- service_repo()
  f <- service_fixture(r)
  first <- service_save(r, f)
  expect_identical(service_save(r, f), first)
  expect_error(service_save(r, f, value = 8L), class = "DEL_CONFLICT")
  expect_error(service_save(r, f, value = 8L, key = "stale"), class = "DEL_CONFLICT")
  expect_equal(service_count(r, "research.response_revisions", f$study_id), 1L)
  second <- service_save(r, f, value = 8L, revision = 1L, key = "next")
  expect_equal(second$revision, 2L)
  expect_error(submit_round(r, f$actor, f$enrollment, setNames(1L, f$item), "stale-submit"),
    class = "DEL_CONFLICT"
  )
  versions <- setNames(2L, f$item)
  submitted <- submit_round(r, f$actor, f$enrollment, versions, "submit")
  expect_identical(submit_round(r, f$actor, f$enrollment, versions, "submit"), submitted)
  expect_identical(submit_round(r, f$actor, f$enrollment, versions, "new-submit-key"), submitted)
  expect_error(service_save(r, f, revision = 2L, key = "after-submit"), class = "DEL_CONFLICT")
  q <- get_questionnaire(r, f$actor, f$enrollment)
  expect_equal(nrow(q$receipt), 1L)
  expect_identical(q$receipt$id, submitted$id)
  expect_equal(q$responses$value_int, 8L)
})

test_that("invalid lifecycle and consent cannot create revisions", {
  r <- service_repo()
  f <- service_fixture(r, open = FALSE)
  expect_error(service_save(r, f), class = "DEL_ROUND_CLOSED")
  expect_error(transition_round(
    r, f$manager, f$round$id, "open", f$round$hash,
    "Synthetic invalid transition", "skip-approval"
  ), class = "DEL_CONFLICT")
  expect_error(freeze_round(r, f$manager, f$round$id, "early-freeze"), class = "DEL_CONFLICT")
  for (state in c("review", "approved", "open")) {
    transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic test", state)
  }
  record_consent(r, f$actor, f$study_id, f$consent_id, FALSE, "withdraw-consent")
  expect_error(service_save(r, f), class = "DEL_FORBIDDEN")
  record_consent(r, f$actor, f$study_id, f$consent_id, TRUE, "restore-consent")
  transition_round(r, f$manager, f$round$id, "closed", f$round$hash, "Synthetic close", "close")
  expect_error(service_save(r, f), class = "DEL_ROUND_CLOSED")
  expect_equal(service_count(r, "research.response_revisions", f$study_id), 0L)
})

test_that("database constraints and immutable records roll back the whole transaction", {
  r <- service_repo()
  f <- service_fixture(r)
  other <- service_fixture(r)
  receipt <- service_save(r, f)
  before <- service_count(r, "research.response_revisions", f$study_id)
  expect_error(DBI::dbWithTransaction(r$con, {
    DBI::dbExecute(r$con, "UPDATE research.studies SET title='Should roll back' WHERE id=$1",
      params = list(f$study_id)
    )
    service_statement(r$con, "UPDATE research.response_revisions SET value_int=1 WHERE id=$1",
      params = list(receipt$id)
    )
  }), "immutable record")
  expect_equal(DBI::dbGetQuery(r$con, "SELECT title FROM research.studies WHERE id=$1",
    params = list(f$study_id)
  )$title, demo_protocol()$study$title)
  expect_error(
    service_statement(r$con, paste(
      "INSERT INTO research.response_revisions(id,study_id,round_id,enrollment_id,round_item_id,revision,status,value_int)",
      "VALUES($1,$2,$3,$4,$5,2,'answered',7)"
    ),
    params = list(uuid::UUIDgenerate(), f$study_id, f$round$id, f$enrollment, other$item)
    ),
    "foreign key"
  )
  expect_error(service_statement(r$con, "UPDATE research.round_items SET texts='{}'::jsonb WHERE id=$1",
    params = list(f$item)
  ), "instrument locked")
  expect_equal(service_count(r, "research.response_revisions", f$study_id), before)
  # A service validation failure leaves neither command receipt nor audit event.
  counts <- vapply(c("ops.commands", "ops.audit"), function(x) service_count(r, x, f$study_id), integer(1))
  expect_error(service_save(r, f, value = 20L, revision = 1L, key = "invalid-scale"), class = "DEL_VALIDATION")
  expect_identical(vapply(names(counts), function(x) service_count(r, x, f$study_id), integer(1)), counts)
})

# Each child starts a new R process and creates its own libpq connection.
service_child <- function(f, operation, application_name, key, env = parent.frame()) {
  testthat::skip_if_not_installed("callr")
  root <- Sys.getenv("DELPHYR_SOURCE_ROOT")
  testthat::skip_if(!nzchar(root), "Concurrency tests need DELPHYR_SOURCE_ROOT")
  child <- callr::r_bg(function(root, libs, f, operation, application_name, key) {
    .libPaths(libs)
    pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
    r <- connect_repository(
      host = "127.0.0.1", port = 55439, dbname = "delphyr",
      user = "postgres", environment = "test", application_name = application_name
    )
    on.exit(DBI::dbDisconnect(r$con))
    DBI::dbExecute(r$con, "SET statement_timeout='20s'")
    tryCatch(
      {
        value <- if (operation == "save") {
          save_response(
            r, f$actor, f$enrollment, f$item,
            list(value = 8L, status = "answered"), 0L, key
          )
        } else if (operation == "submit") {
          submit_round(r, f$actor, f$enrollment, setNames(1L, f$item), key)
        } else {
          transition_round(
            r, f$manager, f$round$id, "closed", f$round$hash,
            "Synthetic concurrent close", key
          )
        }
        list(ok = TRUE, value = value)
      },
      delphyr_error = function(e) list(ok = FALSE, code = e$code)
    )
  }, args = list(root, .libPaths(), f, operation, application_name, key), supervise = TRUE)
  withr::defer(if (child$is_alive()) child$kill(), envir = env)
  child
}
service_wait_lock <- function(r, name, child) {
  deadline <- Sys.time() + 15
  repeat {
    DBI::dbGetQuery(r$con, "SELECT pg_stat_clear_snapshot()")
    state <- DBI::dbGetQuery(r$con, paste(
      "SELECT wait_event_type FROM pg_stat_activity WHERE application_name=$1"
    ), params = list(name))
    if (nrow(state) == 1L && identical(state$wait_event_type, "Lock")) {
      return(invisible(TRUE))
    }
    if (!child$is_alive()) stop("Child exited before lock barrier: ", child$read_error())
    if (Sys.time() > deadline) stop("Child did not reach the database lock barrier")
    Sys.sleep(0.025)
  }
}
service_result <- function(child) {
  child$wait(timeout = 25000)
  if (child$is_alive()) stop("Concurrent service exceeded test deadline")
  child$get_result()
}

test_that("two concurrent first saves serialize with one optimistic conflict", {
  r <- service_repo()
  f <- service_fixture(r)
  DBI::dbBegin(r$con)
  withr::defer(suppressWarnings(try(DBI::dbRollback(r$con), silent = TRUE)))
  DBI::dbGetQuery(r$con, "SELECT id FROM research.enrollments WHERE id=$1 FOR UPDATE",
    params = list(f$enrollment)
  )
  name1 <- paste0("delphyr-save-a-", f$study_id)
  name2 <- paste0("delphyr-save-b-", f$study_id)
  a <- service_child(f, "save", name1, "concurrent-a")
  service_wait_lock(r, name1, a)
  b <- service_child(f, "save", name2, "concurrent-b")
  service_wait_lock(r, name2, b)
  DBI::dbCommit(r$con)
  results <- list(service_result(a), service_result(b))
  expect_equal(sum(vapply(results, `[[`, logical(1), "ok")), 1L)
  failed <- results[!vapply(results, `[[`, logical(1), "ok")][[1L]]
  expect_identical(failed$code, "DEL_CONFLICT")
  expect_equal(service_count(r, "research.response_revisions", f$study_id), 1L)
  expect_equal(get_questionnaire(r, f$actor, f$enrollment)$responses$revision, 1L)
})

test_that("a save queued behind committed close cannot write to a closed round", {
  r <- service_repo()
  f <- service_fixture(r)
  DBI::dbBegin(r$con)
  withr::defer(suppressWarnings(try(DBI::dbRollback(r$con), silent = TRUE)))
  DBI::dbGetQuery(r$con, "SELECT id FROM research.rounds WHERE id=$1 FOR UPDATE",
    params = list(f$round$id)
  )
  name <- paste0("delphyr-save-close-", f$study_id)
  child <- service_child(f, "save", name, "racing-save")
  service_wait_lock(r, name, child)
  DBI::dbExecute(r$con, "UPDATE research.rounds SET state='closed',closed_at=clock_timestamp() WHERE id=$1",
    params = list(f$round$id)
  )
  DBI::dbCommit(r$con)
  result <- service_result(child)
  expect_false(result$ok)
  expect_identical(result$code, "DEL_ROUND_CLOSED")
  expect_equal(service_count(r, "research.response_revisions", f$study_id), 0L)
})

test_that("close waits for an in-flight save before committing", {
  r <- service_repo()
  f <- service_fixture(r)
  DBI::dbBegin(r$con)
  withr::defer(suppressWarnings(try(DBI::dbRollback(r$con), silent = TRUE)))
  DBI::dbGetQuery(r$con, "SELECT id FROM research.enrollments WHERE id=$1 FOR UPDATE",
    params = list(f$enrollment)
  )
  save_name <- paste0("delphyr-save-first-", f$study_id)
  save <- service_child(f, "save", save_name, "save-first")
  service_wait_lock(r, save_name, save)
  close_name <- paste0("delphyr-close-second-", f$study_id)
  close <- service_child(f, "close", close_name, "close-second")
  service_wait_lock(r, close_name, close)
  DBI::dbCommit(r$con)
  expect_true(service_result(save)$ok)
  expect_true(service_result(close)$ok)
  expect_equal(service_count(r, "research.response_revisions", f$study_id), 1L)
  expect_identical(get_questionnaire(r, f$actor, f$enrollment)$round$state, "closed")
})


test_that("concurrent duplicate submit creates one exact durable submission", {
  r <- service_repo()
  f <- service_fixture(r)
  saved <- service_save(r, f)
  DBI::dbBegin(r$con)
  withr::defer(suppressWarnings(try(DBI::dbRollback(r$con), silent = TRUE)))
  DBI::dbGetQuery(r$con, "SELECT id FROM research.enrollments WHERE id=$1 FOR UPDATE",
    params = list(f$enrollment)
  )
  name1 <- paste0("delphyr-submit-a-", f$study_id)
  name2 <- paste0("delphyr-submit-b-", f$study_id)
  a <- service_child(f, "submit", name1, "same-submit")
  service_wait_lock(r, name1, a)
  b <- service_child(f, "submit", name2, "same-submit")
  service_wait_lock(r, name2, b)
  DBI::dbCommit(r$con)
  first <- service_result(a)
  second <- service_result(b)
  expect_true(first$ok)
  expect_identical(first, second)
  submitted <- DBI::dbGetQuery(r$con,
    "SELECT id FROM research.submissions WHERE study_id=$1 AND enrollment_id=$2",
    params = list(f$study_id, f$enrollment)
  )
  expect_equal(nrow(submitted), 1L)
  entries <- DBI::dbGetQuery(r$con,
    "SELECT response_revision_id FROM research.submission_entries WHERE submission_id=$1",
    params = list(submitted$id)
  )
  expect_identical(entries$response_revision_id, saved$id)
})

test_that("frozen snapshots retain submitted revisions and current study authority", {
  r <- service_repo()
  f <- service_fixture(r)
  other <- service_fixture(r)
  service_save(r, f, value = 7L)
  service_save(r, f, value = 9L, revision = 1L, key = "revision-two")
  submit_round(r, f$actor, f$enrollment, setNames(2L, f$item), "submit")
  transition_round(r, f$manager, f$round$id, "closed", f$round$hash, "Synthetic close", "close")
  frozen <- freeze_round(r, f$manager, f$round$id, "freeze")
  expect_identical(freeze_round(r, f$manager, f$round$id, "freeze"), frozen)
  snapshot <- get_snapshot(r, f$manager, frozen$id)
  expect_identical(snapshot$content_hash, frozen$hash)
  expect_equal(snapshot$data$value_integer[snapshot$data$submitted], 9L)
  expect_equal(sum(snapshot$data$submitted), 1L)
  expect_error(get_snapshot(r, other$manager, frozen$id), class = "DEL_NOT_FOUND")
  expect_error(get_snapshot(r, f$actor, frozen$id), class = "DEL_FORBIDDEN")
  analysis <- run_analysis(r, f$manager, frozen$id, "analyse")
  expect_identical(
    get_analysis(r, f$manager, analysis$id)$provenance$result_hash,
    analyse_round(snapshot)$provenance$result_hash
  )
  set_capability(
    r, f$manager, f$study_id, f$manager$principal_id,
    "analyse", FALSE, "revoke-analysis"
  )
  expect_error(get_snapshot(r, f$manager, frozen$id), class = "DEL_FORBIDDEN")
  expect_error(run_analysis(r, f$manager, frozen$id, "analyse"), class = "DEL_FORBIDDEN")
  expect_error(service_statement(r$con, "UPDATE research.snapshots SET hash='altered' WHERE id=$1",
    params = list(frozen$id)
  ), "immutable record")
})
