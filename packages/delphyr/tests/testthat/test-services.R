# These tests only use the explicitly opted-in, isolated loopback test database.
service_repo <- function(env = parent.frame()) {
  testthat::skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "PostgreSQL tests require DELPHYR_TEST_DB=true")
  testthat::skip_if_not_installed("RPostgres")
  r <- connect_repository(
    host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"),
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
  if (open) {
    f$enrollment <- list_enrollments(r, f$actor, f$study_id)$id[1L]
    f$item <- get_questionnaire(r, f$actor, f$enrollment)$items$id[1L]
  } else {
    # A round that is not open yet is not shown to its members.
    f$enrollment <- DBI::dbGetQuery(r$con, "SELECT e.id FROM research.enrollments e JOIN identity.panelist_links l ON l.study_id=e.study_id AND l.panelist_id=e.panelist_id JOIN identity.memberships m ON m.study_id=l.study_id AND m.id=l.membership_id WHERE e.round_id=$1 AND m.principal_id=$2", params = list(f$round$id, f$actor$principal_id))$id
    f$item <- DBI::dbGetQuery(r$con, "SELECT id FROM research.round_items WHERE round_id=$1", params = list(f$round$id))$id
  }
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
  # The enrollment of a round that has not opened does not exist for the member.
  expect_error(service_save(r, f), class = "DEL_NOT_FOUND")
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

test_that("a confirmed submission is never reopened, extended or attributed to anyone else", {
  r <- service_repo()
  runtime <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "delphyr_runtime", environment = "test")
  withr::defer(DBI::dbDisconnect(runtime$con))
  f <- service_fixture(r)
  first <- service_save(r, f)
  second <- service_save(r, f, value = 8L, revision = 1L, key = "second")
  # A submission holds one answer per field.
  expect_error(DBI::dbWithTransaction(r$con, {
    submission <- uuid::UUIDgenerate()
    service_statement(r$con, "INSERT INTO research.submissions(id,study_id,round_id,enrollment_id) VALUES($1,$2,$3,$4)", list(submission, f$study_id, f$round$id, f$enrollment))
    for (v in c(first$id, second$id)) service_statement(r$con, "INSERT INTO research.submission_entries VALUES($1,$2,$3,$4,$5)", list(f$study_id, f$round$id, f$enrollment, submission, v))
  }), "submission holds the field already")
  # The service submits under the application role.
  submitted <- submit_round(runtime, f$actor, f$enrollment, setNames(2L, f$item), "submit")
  other <- DBI::dbGetQuery(r$con, "SELECT panelist_id FROM research.enrollments WHERE round_id=$1 AND id<>$2", params = list(f$round$id, f$enrollment))$panelist_id
  for (repo in list(r, runtime)) {
    expect_error(delphyr:::execute(repo, "UPDATE research.enrollments SET state='in_progress' WHERE id=$1", f$enrollment), "enrollment transition refused")
    expect_error(delphyr:::execute(repo, "UPDATE research.enrollments SET state='eligible' WHERE id=$1", f$enrollment), "enrollment transition refused")
  }
  expect_error(delphyr:::execute(r, "UPDATE research.enrollments SET group_code='public_contributors' WHERE id=$1", f$enrollment), "enrollment assignment is immutable")
  expect_error(delphyr:::execute(r, "UPDATE research.enrollments SET panelist_id=$2 WHERE id=$1", f$enrollment, other), "enrollment assignment is immutable")
  expect_error(delphyr:::execute(runtime, "UPDATE research.enrollments SET group_code='public_contributors' WHERE id=$1", f$enrollment), "permission denied")
  expect_error(delphyr:::execute(runtime, "UPDATE research.enrollments SET panelist_id=$2 WHERE id=$1", f$enrollment, other), "permission denied")
  expect_error(delphyr:::execute(runtime, "INSERT INTO research.submission_entries VALUES($1,$2,$3,$4,$5)", f$study_id, f$round$id, f$enrollment, submitted$id, first$id), "submission locked")
  entries <- DBI::dbGetQuery(r$con, "SELECT response_revision_id FROM research.submission_entries WHERE submission_id=$1", params = list(submitted$id))
  expect_identical(entries$response_revision_id, second$id)
  expect_identical(DBI::dbGetQuery(r$con, "SELECT state FROM research.enrollments WHERE id=$1", params = list(f$enrollment))$state, "submitted")
  # Nobody submits in a member's place with fewer answers or none: a
  # submission commits only with the change to submitted and holds every
  # current answer, and the change to submitted needs the submission.
  peer <- f$panel[[2L]]
  peer_enrollment <- list_enrollments(r, peer, f$study_id)$id
  record_consent(r, peer, f$study_id, f$consent_id, TRUE, "consent")
  save_response(r, peer, peer_enrollment, f$item, list(value = 6L, status = "answered"), 0L, "save")
  insert_submission <- function() service_statement(runtime$con, "INSERT INTO research.submissions(id,study_id,round_id,enrollment_id) VALUES($1,$2,$3,$4)", list(uuid::UUIDgenerate(), f$study_id, f$round$id, peer_enrollment))
  mark_submitted <- function() service_statement(runtime$con, "UPDATE research.enrollments SET state='submitted' WHERE id=$1", list(peer_enrollment))
  # These checks run at commit, when the whole submission is written; a
  # refused commit ends the transaction.
  committed <- function(...) {
    DBI::dbExecute(runtime$con, "BEGIN")
    tryCatch(for (step in list(...)) step(), error = function(e) {
      DBI::dbExecute(runtime$con, "ROLLBACK")
      stop(e)
    })
    DBI::dbExecute(runtime$con, "COMMIT")
  }
  expect_error(committed(insert_submission), "submission incomplete")
  expect_error(committed(insert_submission, mark_submitted), "submission incomplete")
  expect_error(committed(mark_submitted), "submission missing")
  expect_identical(DBI::dbGetQuery(r$con, "SELECT state FROM research.enrollments WHERE id=$1", params = list(peer_enrollment))$state, "in_progress")
  # A closed round takes no submission at all.
  transition_round(r, f$manager, f$round$id, "closed", f$round$hash, "Synthetic close", "close")
  expect_error(insert_submission(), "submission locked")
  expect_identical(DBI::dbGetQuery(r$con, "SELECT enrollment_id FROM research.submissions WHERE round_id=$1", params = list(f$round$id))$enrollment_id, f$enrollment)
})

# Each child starts a new R process and creates its own libpq connection.
service_child <- function(f, operation, application_name, key, revision = 0L, env = parent.frame()) {
  testthat::skip_if_not_installed("callr")
  root <- Sys.getenv("DELPHYR_SOURCE_ROOT")
  testthat::skip_if(!nzchar(root), "Concurrency tests need DELPHYR_SOURCE_ROOT")
  child <- callr::r_bg(function(root, libs, f, operation, application_name, key, revision) {
    .libPaths(libs)
    pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
    r <- connect_repository(
      host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"),
      user = "postgres", environment = "test", application_name = application_name
    )
    on.exit(DBI::dbDisconnect(r$con))
    DBI::dbExecute(r$con, "SET statement_timeout='20s'")
    tryCatch(
      {
        value <- if (operation == "save") {
          save_response(
            r, f$actor, f$enrollment, f$item,
            list(value = 8L, status = "answered"), revision, key
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
  }, args = list(root, .libPaths(), f, operation, application_name, key, revision), supervise = TRUE)
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

test_that("a submit queued behind a committed close creates no submission", {
  r <- service_repo()
  f <- service_fixture(r)
  service_save(r, f)
  DBI::dbBegin(r$con)
  withr::defer(suppressWarnings(try(DBI::dbRollback(r$con), silent = TRUE)))
  DBI::dbGetQuery(r$con, "SELECT id FROM research.rounds WHERE id=$1 FOR UPDATE", params = list(f$round$id))
  name <- paste0("delphyr-submit-close-", f$study_id)
  child <- service_child(f, "submit", name, "racing-submit")
  service_wait_lock(r, name, child)
  DBI::dbExecute(r$con, "UPDATE research.rounds SET state='closed',closed_at=clock_timestamp() WHERE id=$1", params = list(f$round$id))
  DBI::dbCommit(r$con)
  result <- service_result(child)
  expect_false(result$ok)
  expect_identical(result$code, "DEL_ROUND_CLOSED")
  expect_equal(nrow(DBI::dbGetQuery(r$con, "SELECT id FROM research.submissions WHERE study_id=$1", params = list(f$study_id))), 0L)
  # The frozen round holds the saved answer as not submitted.
  snapshot <- get_snapshot(r, f$manager, freeze_round(r, f$manager, f$round$id, "freeze")$id)
  expect_equal(sum(snapshot$data$submitted), 0L)
})

test_that("close waits for an in-flight submit and the snapshot holds exactly that submission", {
  r <- service_repo()
  f <- service_fixture(r)
  saved <- service_save(r, f)
  DBI::dbBegin(r$con)
  withr::defer(suppressWarnings(try(DBI::dbRollback(r$con), silent = TRUE)))
  DBI::dbGetQuery(r$con, "SELECT id FROM research.enrollments WHERE id=$1 FOR UPDATE", params = list(f$enrollment))
  submit_name <- paste0("delphyr-submit-first-", f$study_id)
  submit <- service_child(f, "submit", submit_name, "submit-first")
  service_wait_lock(r, submit_name, submit)
  close_name <- paste0("delphyr-close-after-submit-", f$study_id)
  close <- service_child(f, "close", close_name, "close-after-submit")
  service_wait_lock(r, close_name, close)
  DBI::dbCommit(r$con)
  expect_true(service_result(submit)$ok)
  expect_true(service_result(close)$ok)
  entries <- DBI::dbGetQuery(r$con, "SELECT e.response_revision_id FROM research.submission_entries e JOIN research.submissions s ON s.id=e.submission_id WHERE s.study_id=$1", params = list(f$study_id))
  expect_identical(entries$response_revision_id, saved$id)
  snapshot <- get_snapshot(r, f$manager, freeze_round(r, f$manager, f$round$id, "freeze")$id)
  expect_equal(sum(snapshot$data$submitted), 1L)
  expect_equal(snapshot$data$value_integer[snapshot$data$submitted], 7L)
})

test_that("a save and a submit of the same answers never both take effect", {
  r <- service_repo()
  f <- service_fixture(r)
  saved <- service_save(r, f)
  DBI::dbBegin(r$con)
  withr::defer(suppressWarnings(try(DBI::dbRollback(r$con), silent = TRUE)))
  DBI::dbGetQuery(r$con, "SELECT id FROM research.enrollments WHERE id=$1 FOR UPDATE", params = list(f$enrollment))
  submit_name <- paste0("delphyr-submit-vs-save-", f$study_id)
  submit <- service_child(f, "submit", submit_name, "submit-racing-save")
  service_wait_lock(r, submit_name, submit)
  save_name <- paste0("delphyr-save-vs-submit-", f$study_id)
  save <- service_child(f, "save", save_name, "save-racing-submit", revision = 1L)
  service_wait_lock(r, save_name, save)
  DBI::dbCommit(r$con)
  submitted <- service_result(submit)
  changed <- service_result(save)
  # Whichever is admitted first, the other is refused as a conflict.
  expect_true(xor(submitted$ok, changed$ok))
  expect_identical(c(submitted$code, changed$code), "DEL_CONFLICT")
  entries <- DBI::dbGetQuery(r$con, "SELECT e.response_revision_id FROM research.submission_entries e JOIN research.submissions s ON s.id=e.submission_id WHERE s.study_id=$1", params = list(f$study_id))
  revisions <- service_count(r, "research.response_revisions", f$study_id)
  if (submitted$ok) {
    # The submission holds the answer it was made for; the later entry was not stored.
    expect_identical(entries$response_revision_id, saved$id)
    expect_equal(revisions, 1L)
  } else {
    # The new answer was stored; the submission of the earlier one did not happen.
    expect_equal(nrow(entries), 0L)
    expect_equal(revisions, 2L)
  }
})

test_that("a submit queued behind an in-flight save names a replaced revision and submits nothing", {
  r <- service_repo()
  f <- service_fixture(r)
  service_save(r, f)
  DBI::dbBegin(r$con)
  withr::defer(suppressWarnings(try(DBI::dbRollback(r$con), silent = TRUE)))
  DBI::dbGetQuery(r$con, "SELECT id FROM research.enrollments WHERE id=$1 FOR UPDATE", params = list(f$enrollment))
  save_name <- paste0("delphyr-save-before-submit-", f$study_id)
  save <- service_child(f, "save", save_name, "save-before-submit", revision = 1L)
  service_wait_lock(r, save_name, save)
  submit_name <- paste0("delphyr-submit-after-save-", f$study_id)
  submit <- service_child(f, "submit", submit_name, "submit-after-save")
  service_wait_lock(r, submit_name, submit)
  DBI::dbCommit(r$con)
  changed <- service_result(save)
  submitted <- service_result(submit)
  # The save is admitted first; the submit still names revision 1.
  expect_true(changed$ok)
  expect_identical(changed$value$revision, 2L)
  expect_false(submitted$ok)
  expect_identical(submitted$code, "DEL_CONFLICT")
  expect_equal(nrow(DBI::dbGetQuery(r$con, "SELECT id FROM research.submissions WHERE study_id=$1", params = list(f$study_id))), 0L)
  expect_equal(service_count(r, "research.response_revisions", f$study_id), 2L)
})

test_that("a round accepts answers only with consent to exactly the information version it requires", {
  r <- service_repo()
  f <- demo_study(r, n = 2L, item_count = 1L, code = paste0("TEST-", uuid::UUIDgenerate()))
  # The study information is revised before the round opens, and the round
  # is prepared again with the new version.
  revised <- publish_consent(r, f$manager, f$study_id, "Synthetic demonstration only, revised.", "en", "consent-2")$id
  transition_round(r, f$manager, f$round$id, "cancelled", f$round$hash, "Information revised", "cancel")
  round <- prepare_round(r, f$manager, f$study_id, f$items, revised, format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), "round-2")
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, round$id, state, round$hash, "Synthetic test", state)
  actor <- f$panel[[1L]]
  enrollment <- list_enrollments(r, actor, f$study_id)$id
  q <- get_questionnaire(r, actor, enrollment)
  expect_identical(q$consent$id, revised)
  expect_false(q$consent$accepted)
  # Consent to the earlier version does not admit answers to this round.
  record_consent(r, actor, f$study_id, f$consent_id, TRUE, "consent-1")
  expect_false(get_questionnaire(r, actor, enrollment)$consent$accepted)
  refused <- tryCatch(save_response(r, actor, enrollment, q$items$id, list(value = 7L, status = "answered"), 0L, "save"), error = function(e) e)
  expect_s3_class(refused, "DEL_FORBIDDEN")
  expect_identical(refused$path, "consent")
  record_consent(r, actor, f$study_id, revised, TRUE, "consent-2")
  expect_true(get_questionnaire(r, actor, enrollment)$consent$accepted)
  expect_identical(save_response(r, actor, enrollment, q$items$id, list(value = 7L, status = "answered"), 0L, "save-2")$revision, 1L)
  expect_equal(service_count(r, "research.response_revisions", f$study_id), 1L)
})

test_that("two concurrent close commands close the round once", {
  r <- service_repo()
  f <- service_fixture(r)
  DBI::dbBegin(r$con)
  withr::defer(suppressWarnings(try(DBI::dbRollback(r$con), silent = TRUE)))
  DBI::dbGetQuery(r$con, "SELECT id FROM research.rounds WHERE id=$1 FOR UPDATE", params = list(f$round$id))
  name1 <- paste0("delphyr-close-a-", f$study_id)
  name2 <- paste0("delphyr-close-b-", f$study_id)
  a <- service_child(f, "close", name1, "close-a")
  service_wait_lock(r, name1, a)
  b <- service_child(f, "close", name2, "close-b")
  service_wait_lock(r, name2, b)
  DBI::dbCommit(r$con)
  results <- list(service_result(a), service_result(b))
  expect_equal(sum(vapply(results, `[[`, logical(1), "ok")), 1L)
  expect_identical(results[!vapply(results, `[[`, logical(1), "ok")][[1L]]$code, "DEL_CONFLICT")
  events <- DBI::dbGetQuery(r$con, "SELECT target_state FROM research.round_events WHERE round_id=$1 AND target_state='closed'", params = list(f$round$id))
  expect_equal(nrow(events), 1L)
  expect_identical(DBI::dbGetQuery(r$con, "SELECT state FROM research.rounds WHERE id=$1", params = list(f$round$id))$state, "closed")
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
