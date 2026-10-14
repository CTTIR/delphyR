test_that("withdrawal stops new activity and retains committed synthetic data", {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  on.exit(DBI::dbDisconnect(r$con))
  f <- demo_study(r, n = 2L, item_count = 1L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic test", state)
  a <- f$panel[[1]]
  enrollment <- list_enrollments(r, a, f$study_id)$id[1]
  q <- get_questionnaire(r, a, enrollment)
  record_consent(r, a, f$study_id, f$consent_id, TRUE, "consent")
  saved <- save_response(r, a, enrollment, q$items$id, list(status = "answered", value = 7L), 0L, "save")
  campaign <- prepare_campaign(r, f$manager, f$round$id, enrollment, "reminder", "Synthetic reminder", "Synthetic reminder body", command_id = "campaign")
  preview <- preview_campaign(r, f$manager, campaign$id)
  expect_error(withdraw_participation(r, a, f$study_id, "delete_all", "bad-policy"), class = "DEL_VALIDATION")
  receipt <- withdraw_participation(r, a, f$study_id, "synthetic_retain_prior_data", "withdraw")
  expect_identical(withdraw_participation(r, a, f$study_id, "synthetic_retain_prior_data", "withdraw")$id, receipt$id)
  expect_error(save_response(r, a, enrollment, q$items$id, list(status = "answered", value = 8L), 1L, "later"), class = "DEL_CONFLICT")
  expect_error(submit_round(r, a, enrollment, stats::setNames(1L, q$items$id), "submit"), class = "DEL_CONFLICT")
  preserved <- get_questionnaire(r, a, enrollment)
  expect_identical(preserved$responses$id, saved$id)
  expect_equal(preserved$responses$value_int, 7L)
  expect_equal(preserved$enrollment$state, "withdrawn")
  release_campaign(r, f$manager, campaign$id, preview$hash, "Synthetic approval", "release")
  process_campaign_sink(r, study_id = f$study_id)
  delivery <- DBI::dbGetQuery(r$con, "SELECT d.state FROM ops.message_delivery d JOIN ops.message_outbox o ON o.id=d.message_id WHERE o.campaign_id=$1", params = list(campaign$id))
  expect_equal(delivery$state, "suppressed")
  expect_error(withdraw_participation(r, f$manager, f$study_id, "synthetic_retain_prior_data", "wrong-role"), class = "DEL_FORBIDDEN")
  # The withdrawal is final in the database as well.
  expect_error(delphyr:::execute(r, "UPDATE research.panelists SET active=true WHERE id=$1", preserved$enrollment$panelist_id), "panel membership change refused")
  expect_error(delphyr:::execute(r, "UPDATE research.enrollments SET state='in_progress' WHERE id=$1", enrollment), "enrollment transition refused")
  expect_false(DBI::dbGetQuery(r$con, "SELECT active FROM research.panelists WHERE id=$1", params = list(preserved$enrollment$panelist_id))$active)
})

test_that("stakeholder changes leave existing round assignments untouched and apply to new rounds", {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  on.exit(DBI::dbDisconnect(r$con))
  f <- demo_study(r, n = 2L, item_count = 1L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic test", state)
  enrollment <- list_enrollments(r, f$panel[[1]], f$study_id)$id[1]
  old <- get_questionnaire(r, f$panel[[1]], enrollment)$enrollment
  expect_identical(old$group_code, "professionals")
  receipt <- set_panel_group(r, f$manager, f$study_id, old$panelist_id, "public_contributors", "Updated synthetic stakeholder profile", "group")
  expect_equal(receipt$group_code, "public_contributors")
  expect_identical(get_questionnaire(r, f$panel[[1]], enrollment)$enrollment$group_code, old$group_code)
  expect_equal(DBI::dbGetQuery(r$con, "SELECT group_code FROM research.panelists WHERE id=$1", params = list(old$panelist_id))$group_code, "public_contributors")
  expect_error(set_panel_group(r, f$panel[[1]], f$study_id, old$panelist_id, "professionals", "Cannot self-classify", "forbidden"), class = "DEL_FORBIDDEN")
  expect_error(set_panel_group(r, f$manager, f$study_id, old$panelist_id, "unknown", "Bad group", "bad"), class = "DEL_VALIDATION")
  # The round is conducted to its end; the next round enrolls the member in
  # the recorded group, and the first round keeps the earlier one.
  for (actor in f$panel) {
    e <- list_enrollments(r, actor, f$study_id)$id
    record_consent(r, actor, f$study_id, f$consent_id, TRUE, "consent")
    item <- get_questionnaire(r, actor, e)$items$id
    saved <- save_response(r, actor, e, item, list(value = 7L, status = "answered"), 0L, "save")
    submit_round(r, actor, e, setNames(saved$revision, item), "submit")
  }
  transition_round(r, f$manager, f$round$id, "closed", f$round$hash, "Close", "close")
  snapshot <- freeze_round(r, f$manager, f$round$id, "freeze")
  run_analysis(r, f$manager, snapshot$id, "analyse")
  transition_round(r, f$manager, f$round$id, "finalized", f$round$hash, "Next round follows", "finalize")
  second <- prepare_round(r, f$manager, f$study_id, f$items, f$consent_id, format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), "round-2")
  groups <- DBI::dbGetQuery(r$con, "SELECT r.number,e.group_code FROM research.enrollments e JOIN research.rounds r ON r.id=e.round_id WHERE e.panelist_id=$1 ORDER BY r.number", params = list(old$panelist_id))
  expect_identical(groups$number, 1:2)
  expect_identical(groups$group_code, c("professionals", "public_contributors"))
  expect_identical(get_round_instrument(r, f$manager, second$id)$enrollments$group_code, "public_contributors")
})

test_that("a save queued behind committed withdrawal is rejected without losing prior save", {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  root <- Sys.getenv("DELPHYR_SOURCE_ROOT")
  skip_if(!nzchar(root), "Source root required for independent connections")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  on.exit(DBI::dbDisconnect(r$con))
  f <- demo_study(r, n = 2L, item_count = 1L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic race", state)
  actor <- f$panel[[1]]
  enrollment <- list_enrollments(r, actor, f$study_id)$id[1]
  item <- get_questionnaire(r, actor, enrollment)$items$id[1]
  record_consent(r, actor, f$study_id, f$consent_id, TRUE, "consent")
  saved <- save_response(r, actor, enrollment, item, list(status = "answered", value = 7L), 0L, "first")
  DBI::dbBegin(r$con)
  delphyr:::query(r, "SELECT id FROM research.enrollments WHERE id=$1 FOR UPDATE", enrollment)
  child <- function(action, name) {
    callr::r_bg(function(root, libs, f, actor, enrollment, item, action, name) {
      .libPaths(libs)
      pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
      repo <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "delphyr_runtime", environment = "test", application_name = name)
      on.exit(DBI::dbDisconnect(repo$con))
      tryCatch(if (action == "withdraw") withdraw_participation(repo, actor, f$study_id, "synthetic_retain_prior_data", "withdraw") else save_response(repo, actor, enrollment, item, list(status = "answered", value = 8L), 1L, "waiting-save"), delphyr_error = function(e) list(code = e$code))
    }, list(root, .libPaths(), f, actor, enrollment, item, action, name))
  }
  wait_locked <- function(name) {
    limit <- Sys.time() + 15
    repeat {
      DBI::dbGetQuery(r$con, "SELECT pg_stat_clear_snapshot()")
      row <- DBI::dbGetQuery(r$con, "SELECT wait_event_type FROM pg_stat_activity WHERE application_name=$1", params = list(name))
      if (nrow(row) && identical(row$wait_event_type, "Lock")) break
      if (Sys.time() > limit) stop("Child did not reach controlled lock")
      Sys.sleep(0.03)
    }
  }
  wname <- paste0("withdraw-", uuid::UUIDgenerate())
  w <- child("withdraw", wname)
  on.exit(if (w$is_alive()) w$kill(), add = TRUE)
  wait_locked(wname)
  sname <- paste0("save-", uuid::UUIDgenerate())
  s <- child("save", sname)
  on.exit(if (s$is_alive()) s$kill(), add = TRUE)
  wait_locked(sname)
  DBI::dbCommit(r$con)
  w$wait(timeout = 15000)
  s$wait(timeout = 15000)
  expect_true(nzchar(w$get_result()$id))
  expect_equal(s$get_result()$code, "DEL_CONFLICT")
  q <- get_questionnaire(r, actor, enrollment)
  expect_identical(q$responses$id, saved$id)
  expect_equal(q$responses$value_int, 7L)
})

test_that("an admitted save can commit study foreign keys before waiting withdrawal", {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  root <- Sys.getenv("DELPHYR_SOURCE_ROOT")
  skip_if(!nzchar(root), "Source root required for independent connections")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(r$con))
  f <- demo_study(r, n = 2L, item_count = 1L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic FK race", state)
  actor <- f$panel[[1]]
  enrollment <- list_enrollments(r, actor, f$study_id)$id[1]
  item <- get_questionnaire(r, actor, enrollment)$items$id[1]
  record_consent(r, actor, f$study_id, f$consent_id, TRUE, "consent")
  DBI::dbBegin(r$con)
  withr::defer(suppressWarnings(try(DBI::dbRollback(r$con), silent = TRUE)))
  query(r, "SELECT id FROM research.enrollments WHERE id=$1 FOR UPDATE", enrollment)
  child <- function(action, name) {
    callr::r_bg(function(root, libs, actor, study, enrollment, item, action, name) {
      .libPaths(libs)
      pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
      repo <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "delphyr_runtime", environment = "test", application_name = name)
      on.exit(DBI::dbDisconnect(repo$con))
      DBI::dbExecute(repo$con, "SET statement_timeout='20s'")
      tryCatch(
        if (action == "save") {
          save_response(repo, actor, enrollment, item, list(value = 7L, status = "answered"), 0L, "first-save")
        } else {
          withdraw_participation(repo, actor, study, "synthetic_retain_prior_data", "withdraw")
        },
        delphyr_error = function(e) list(code = e$code)
      )
    }, args = list(root, .libPaths(), actor, f$study_id, enrollment, item, action, name), supervise = TRUE)
  }
  wait_locked <- function(name, process) {
    limit <- Sys.time() + 15
    repeat {
      query(r, "SELECT pg_stat_clear_snapshot()")
      row <- query(r, "SELECT wait_event_type,query FROM pg_stat_activity WHERE application_name=$1", name)
      if (nrow(row) && identical(row$wait_event_type, "Lock")) {
        return(row$query)
      }
      if (!process$is_alive() || Sys.time() > limit) stop("Child failed before enrollment lock barrier")
      Sys.sleep(0.025)
    }
  }
  sname <- paste0("save-fk-first-", uuid::UUIDgenerate())
  save <- child("save", sname)
  withr::defer(if (save$is_alive()) save$kill())
  expect_match(wait_locked(sname, save), "research.enrollments")
  wname <- paste0("withdraw-fk-second-", uuid::UUIDgenerate())
  withdrawal <- child("withdraw", wname)
  withr::defer(if (withdrawal$is_alive()) withdrawal$kill())
  expect_match(wait_locked(wname, withdrawal), "research.enrollments")
  # Save owns the first enrollment wait position; withdrawal already owns its
  # study lock. Save must still acquire study FK KEY SHARE when recording its
  # command and audit, otherwise the old FOR UPDATE study lock deadlocks here.
  DBI::dbCommit(r$con)
  save$wait(timeout = 25000)
  withdrawal$wait(timeout = 25000)
  saved <- save$get_result()
  withdrawn <- withdrawal$get_result()
  expect_true(is.null(saved$code))
  expect_true(is.null(withdrawn$code))
  expect_true(nzchar(saved$id))
  expect_true(nzchar(withdrawn$id))
  q <- get_questionnaire(r, actor, enrollment)
  expect_equal(q$responses$value_int, 7L)
  expect_identical(q$responses$id, saved$id)
  expect_identical(q$enrollment$state, "withdrawn")
})

test_that("late enrollment and withdrawal of the same member take effect one after the other", {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  skip_if_not_installed("callr")
  root <- Sys.getenv("DELPHYR_SOURCE_ROOT")
  skip_if(!nzchar(root), "Source root required for independent connections")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(r$con))
  child <- function(f, late, action, name) {
    callr::r_bg(function(root, libs, f, late, action, name) {
      .libPaths(libs)
      pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
      repo <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "delphyr_runtime", environment = "test", application_name = name)
      on.exit(DBI::dbDisconnect(repo$con))
      DBI::dbExecute(repo$con, "SET statement_timeout='20s'")
      tryCatch(
        if (action == "enroll") enroll_panel(repo, f$manager, f$round$id, "enroll") else withdraw_participation(repo, late, f$study_id, "synthetic_retain_prior_data", "withdraw"),
        delphyr_error = function(e) list(code = e$code)
      )
    }, args = list(root, .libPaths(), f, late, action, name), supervise = TRUE)
  }
  wait_locked <- function(name, process) {
    limit <- Sys.time() + 15
    repeat {
      query(r, "SELECT pg_stat_clear_snapshot()")
      row <- query(r, "SELECT wait_event_type FROM pg_stat_activity WHERE application_name=$1", name)
      if (nrow(row) && identical(row$wait_event_type, "Lock")) break
      if (!process$is_alive() || Sys.time() > limit) stop("Child did not reach the lock barrier: ", paste(process$read_error(), collapse = "; "))
      Sys.sleep(0.025)
    }
  }
  for (first in c("withdraw", "enroll")) {
    f <- demo_study(r, n = 2L, item_count = 1L)
    late <- demo_actor(r, provision_demo_principal(r, paste0("demo-late-", uuid::UUIDgenerate())))
    add_panelist(r, f$manager, f$study_id, late$principal_id, "professionals", "late")
    panelist <- query(r, "SELECT l.panelist_id FROM identity.panelist_links l JOIN identity.memberships m ON m.study_id=l.study_id AND m.id=l.membership_id WHERE m.study_id=$1 AND m.principal_id=$2", f$study_id, late$principal_id)$panelist_id
    # The member's row is held, so the first action stops inside its
    # transaction and the second one starts while the first is unfinished.
    DBI::dbBegin(r$con)
    query(r, "SELECT id FROM research.panelists WHERE id=$1 FOR UPDATE", panelist)
    labels <- paste0(c(first, setdiff(c("withdraw", "enroll"), first)), "-", uuid::UUIDgenerate())
    a <- child(f, late, first, labels[1])
    withr::defer(if (a$is_alive()) a$kill())
    wait_locked(labels[1], a)
    b <- child(f, late, setdiff(c("withdraw", "enroll"), first), labels[2])
    withr::defer(if (b$is_alive()) b$kill())
    wait_locked(labels[2], b)
    DBI::dbCommit(r$con)
    a$wait(timeout = 25000)
    b$wait(timeout = 25000)
    results <- stats::setNames(list(a$get_result(), b$get_result()), c(first, setdiff(c("withdraw", "enroll"), first)))
    expect_true(nzchar(results$withdraw$id))
    state <- query(r, "SELECT state FROM research.enrollments WHERE round_id=$1 AND panelist_id=$2", f$round$id, panelist)$state
    if (first == "withdraw") {
      # Withdrawn first: never enrolled.
      expect_identical(results$enroll$added, 0L)
      expect_identical(state, character())
    } else {
      # Enrolled first: the withdrawal reaches the new enrollment.
      expect_identical(results$enroll$added, 1L)
      expect_identical(state, "withdrawn")
    }
  }
})
