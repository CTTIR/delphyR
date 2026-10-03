lifecycle_repo <- function(env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(r$con), envir = env)
  r
}
lifecycle_deadline <- function(days = 1) format(Sys.time() + days * 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
lifecycle_codes <- function(x, severity) x$issues$code[x$issues$severity == severity]
lifecycle_newcomer <- function(r, f, group = "professionals", key = uid()) {
  actor <- demo_actor(r, provision_demo_principal(r, paste0("demo-late-", uid())))
  add_panelist(r, f$manager, f$study_id, actor$principal_id, group, key)
  actor
}

test_that("readiness lists every blocking finding and opening is refused with them", {
  r <- lifecycle_repo()
  f <- demo_study(r, n = 2L, item_count = 2L)
  ready <- get_round_readiness(r, f$manager, f$round$id)
  expect_s3_class(ready, "delphyr_validation")
  expect_named(ready$issues, c("severity", "code", "path", "message_key", "details"))
  expect_true(ready$valid)
  # One member per required group is below the synthetic minimum of ten.
  expect_setequal(lifecycle_codes(ready, "warning"), "group_below_minimum")
  expect_equal(sum(ready$issues$code == "group_below_minimum"), 2L)
  expect_error(get_round_readiness(r, f$panel[[1]], f$round$id), class = "DEL_FORBIDDEN")
  other <- demo_study(r, n = 2L, item_count = 1L)
  expect_error(get_round_readiness(r, other$manager, f$round$id), class = "DEL_NOT_FOUND")

  # A round without any participant can be prepared and approved, not opened.
  empty <- create_study(r, f$manager, local({
    p <- demo_protocol()
    p$study$code <- paste0("EMPTY-", uid())
    p
  }), "create-empty")
  consent <- publish_consent(r, f$manager, empty$id, "Synthetic information", "fr", "consent")$id
  items <- f$items[f$items$locale %in% c("de", "en"), ]
  round <- prepare_round(r, f$manager, empty$id, items, consent, lifecycle_deadline(), "round")
  found <- get_round_readiness(r, f$manager, round$id)
  expect_false(found$valid)
  expect_setequal(lifecycle_codes(found, "error"), c("consent_language", "no_enrollments"))
  transition_round(r, f$manager, round$id, "review", round$hash, "Review", "review")
  blocked <- tryCatch(transition_round(r, f$manager, round$id, "approved", round$hash, "Approve", "approve"), error = function(e) e)
  expect_s3_class(blocked, "DEL_VALIDATION")
  expect_identical(blocked$path, "round.readiness:consent_language")
  expect_identical(DBI::dbGetQuery(r$con, "SELECT state FROM research.rounds WHERE id=$1", params = list(round$id))$state, "review")
})

test_that("a superseded protocol blocks approval until the candidate is replaced", {
  r <- lifecycle_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  versions <- list_protocol_versions(r, f$manager, f$study_id)
  p <- delphyr:::from_json(versions$config)
  p$stopping$max_rounds <- 4L
  amend_protocol(r, f$manager, f$study_id, p, versions$hash, "Prospective amendment", "amend")
  found <- get_round_readiness(r, f$manager, f$round$id)
  expect_true("protocol_superseded" %in% lifecycle_codes(found, "error"))
  transition_round(r, f$manager, f$round$id, "review", f$round$hash, "Review", "review")
  expect_error(transition_round(r, f$manager, f$round$id, "approved", f$round$hash, "Approve", "approve"), class = "DEL_VALIDATION")
  # The round number stays occupied until the candidate is withdrawn.
  expect_error(prepare_round(r, f$manager, f$study_id, f$items, f$consent_id, lifecycle_deadline(), "replacement"), class = "DEL_CONFLICT")
  cancelled <- transition_round(r, f$manager, f$round$id, "cancelled", f$round$hash, "Prepared under the earlier protocol", "cancel")
  expect_identical(cancelled$state, "cancelled")
  replacement <- prepare_round(r, f$manager, f$study_id, f$items, f$consent_id, lifecycle_deadline(), "replacement-2")
  rounds <- list_rounds(r, f$manager, f$study_id)
  expect_identical(rounds$number, c(1L, 1L))
  expect_identical(rounds$state, c("cancelled", "draft"))
  expect_false(identical(replacement$hash, f$round$hash))
  expect_true(get_round_readiness(r, f$manager, replacement$id)$valid)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, replacement$id, state, replacement$hash, "Synthetic", paste0("new-", state))
  # Panel members see only the round that is actually conducted.
  own <- list_enrollments(r, f$panel[[1]], f$study_id)
  expect_identical(own$round_state, "open")
  expect_equal(nrow(own), 1L)
})

test_that("cancellation is final, keeps history and is impossible after opening", {
  r <- lifecycle_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  expect_error(transition_round(r, f$panel[[1]], f$round$id, "cancelled", f$round$hash, "No right", "x"), class = "DEL_FORBIDDEN")
  transition_round(r, f$manager, f$round$id, "review", f$round$hash, "Review", "review")
  transition_round(r, f$manager, f$round$id, "approved", f$round$hash, "Approve", "approve")
  transition_round(r, f$manager, f$round$id, "cancelled", f$round$hash, "Typo found before opening", "cancel")
  for (target in c("review", "approved", "open", "closed", "finalized", "cancelled")) {
    expect_error(transition_round(r, f$manager, f$round$id, target, f$round$hash, "After cancellation", paste0("after-", target)), class = "DEL_CONFLICT")
  }
  expect_error(execute(r, "UPDATE research.rounds SET state='draft' WHERE id=$1", f$round$id), "cancelled round is final")
  events <- DBI::dbGetQuery(r$con, "SELECT target_state,reason FROM research.round_events WHERE round_id=$1 ORDER BY occurred_at", params = list(f$round$id))
  expect_identical(events$target_state, c("review", "approved", "cancelled"))
  expect_identical(events$reason[3], "Typo found before opening")
  expect_equal(DBI::dbGetQuery(r$con, "SELECT count(*)::int AS n FROM research.round_items WHERE round_id=$1", params = list(f$round$id))$n, 1L)
  # A corrected wording may reuse the version that was never presented.
  corrected <- f$items
  corrected$text <- paste(corrected$text, "(corrected)")
  second <- prepare_round(r, f$manager, f$study_id, corrected, f$consent_id, lifecycle_deadline(), "corrected")
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, second$id, state, second$hash, "Synthetic", paste0("second-", state))
  expect_error(transition_round(r, f$manager, second$id, "cancelled", second$hash, "Too late", "late"), class = "DEL_CONFLICT")
  expect_error(execute(r, "UPDATE research.rounds SET state='cancelled' WHERE id=$1", second$id), "opened round cannot be cancelled")
  expect_equal(nrow(list_campaign_rounds(r, f$manager, f$study_id)), 1L)
})

test_that("a withdrawn candidate does not block the completion of a study", {
  r <- lifecycle_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic", state)
  for (actor in f$panel) {
    e <- list_enrollments(r, actor, f$study_id)$id
    record_consent(r, actor, f$study_id, f$consent_id, TRUE, "consent")
    q <- get_questionnaire(r, actor, e)
    saved <- save_response(r, actor, e, q$items$id, list(value = 8L, status = "answered"), 0L, "save")
    submit_round(r, actor, e, setNames(saved$revision, q$items$id), "submit")
  }
  transition_round(r, f$manager, f$round$id, "closed", f$round$hash, "Close", "close")
  snapshot <- freeze_round(r, f$manager, f$round$id, "freeze")
  analysis <- run_analysis(r, f$manager, snapshot$id, "analyse")
  record_item_decision(r, f$manager, analysis$id, "I001", "finalize", "Synthetic decision", "decide")
  transition_round(r, f$manager, f$round$id, "finalized", f$round$hash, "Final round", "finalize")
  extra <- prepare_round(r, f$manager, f$study_id, f$items, f$consent_id, lifecycle_deadline(), "round-2")
  expect_error(complete_study(r, f$manager, f$study_id, "Stop after round 1", "complete"), class = "DEL_CONFLICT")
  transition_round(r, f$manager, extra$id, "cancelled", extra$hash, "No further round is needed", "cancel")
  done <- complete_study(r, f$manager, f$study_id, "Stop after round 1", "complete-2")
  expect_identical(done$state, "completed")
  expect_error(enroll_panel(r, f$manager, extra$id, "enroll"), class = "DEL_CONFLICT")
})

test_that("late panel members are enrolled explicitly until the round closes", {
  r <- lifecycle_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  late <- lifecycle_newcomer(r, f, "public_contributors")
  expect_equal(nrow(list_enrollments(r, late, f$study_id)), 0L)
  found <- get_round_readiness(r, f$manager, f$round$id)
  expect_identical(found$issues$details[found$issues$code == "panelists_not_enrolled"], "1")
  expect_error(enroll_panel(r, f$panel[[1]], f$round$id, "enroll"), class = "DEL_FORBIDDEN")
  added <- enroll_panel(r, f$manager, f$round$id, "enroll")
  expect_identical(added$added, 1L)
  expect_identical(enroll_panel(r, f$manager, f$round$id, "enroll"), added)
  expect_identical(enroll_panel(r, f$manager, f$round$id, "enroll-again")$added, 0L)
  expect_false("panelists_not_enrolled" %in% get_round_readiness(r, f$manager, f$round$id)$issues$code)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic", state)
  expect_identical(list_enrollments(r, late, f$study_id)$round_state, "open")
  # Recruitment may overlap with an open first round.
  later <- lifecycle_newcomer(r, f)
  expect_identical(enroll_panel(r, f$manager, f$round$id, "enroll-open")$added, 1L)
  group <- DBI::dbGetQuery(r$con, "SELECT e.group_code FROM research.enrollments e JOIN identity.panelist_links l ON l.study_id=e.study_id AND l.panelist_id=e.panelist_id JOIN identity.memberships m ON m.id=l.membership_id WHERE e.round_id=$1 AND m.principal_id=$2", params = list(f$round$id, later$principal_id))$group_code
  expect_identical(group, "professionals")
  withdrawn <- lifecycle_newcomer(r, f)
  withdraw_participation(r, withdrawn, f$study_id, "synthetic_retain_prior_data", "withdraw")
  expect_identical(enroll_panel(r, f$manager, f$round$id, "enroll-withdrawn")$added, 0L)
  transition_round(r, f$manager, f$round$id, "closed", f$round$hash, "Close", "close")
  lifecycle_newcomer(r, f)
  expect_error(enroll_panel(r, f$manager, f$round$id, "enroll-closed"), class = "DEL_CONFLICT")
  expect_error(execute(r, "INSERT INTO research.enrollments(id,study_id,round_id,panelist_id,group_code) SELECT $1,study_id,round_id,panelist_id,group_code FROM research.enrollments WHERE round_id=$2 LIMIT 1", uid(), f$round$id), "enrollment closed")
})

test_that("later rounds apply the entry policy and share assigned feedback", {
  r <- lifecycle_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic", state)
  for (actor in f$panel) {
    e <- list_enrollments(r, actor, f$study_id)$id
    record_consent(r, actor, f$study_id, f$consent_id, TRUE, "consent")
    q <- get_questionnaire(r, actor, e)
    saved <- save_response(r, actor, e, q$items$id, list(value = 8L, status = "answered"), 0L, "save")
    submit_round(r, actor, e, setNames(saved$revision, q$items$id), "submit")
  }
  transition_round(r, f$manager, f$round$id, "closed", f$round$hash, "Close", "close")
  snapshot <- freeze_round(r, f$manager, f$round$id, "freeze")
  analysis <- run_analysis(r, f$manager, snapshot$id, "analyse")
  feedback <- create_feedback(r, f$manager, analysis$id, command_id = "feedback")
  release_feedback(r, f$manager, feedback$id, feedback$hash, "release")
  second <- prepare_round(r, f$manager, f$study_id, f$items, f$consent_id, lifecycle_deadline(), "round-2")
  expect_true("feedback_unassigned" %in% lifecycle_codes(get_round_readiness(r, f$manager, second$id), "warning"))
  assign_feedback(r, f$manager, second$id, feedback$id, "assign")
  expect_false("feedback_unassigned" %in% get_round_readiness(r, f$manager, second$id)$issues$code)
  # The synthetic protocol admits nobody who missed round one.
  newcomer <- lifecycle_newcomer(r, f)
  expect_identical(enroll_panel(r, f$manager, second$id, "enroll")$added, 0L)
  # With late entry approved by amendment, a replacement candidate enrolls
  # the newcomer and gives that person the same assigned feedback.
  versions <- list_protocol_versions(r, f$manager, f$study_id)
  p <- delphyr:::from_json(versions$config)
  p$panel$late_entry <- TRUE
  amend_protocol(r, f$manager, f$study_id, p, versions$hash, "Admit late entry", "amend")
  transition_round(r, f$manager, second$id, "cancelled", second$hash, "Replace under amended protocol", "cancel")
  third <- prepare_round(r, f$manager, f$study_id, f$items, f$consent_id, lifecycle_deadline(), "round-2b")
  expect_equal(nrow(list_enrollments(r, newcomer, f$study_id)), 1L)
  assign_feedback(r, f$manager, third$id, feedback$id, "assign-2")
  another <- lifecycle_newcomer(r, f)
  expect_identical(enroll_panel(r, f$manager, third$id, "enroll-2")$added, 1L)
  shown <- get_feedback(r, another, list_enrollments(r, another, f$study_id)$id)
  expect_identical(shown$id, feedback$id)
  expect_equal(nrow(shown$own), 0L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, third$id, state, third$hash, "Synthetic", paste0("third-", state))
  lifecycle_newcomer(r, f)
  expect_error(enroll_panel(r, f$manager, third$id, "enroll-3"), class = "DEL_CONFLICT")
  n <- DBI::dbGetQuery(r$con, "SELECT count(*)::int AS n FROM research.enrollments WHERE round_id=$1", params = list(third$id))$n
  expect_equal(n, 4L)
})

test_that("the instrument review shows exact content without identities or answers", {
  r <- lifecycle_repo()
  f <- demo_study(r, n = 2L, item_count = 2L)
  x <- get_round_instrument(r, f$manager, f$round$id)
  expect_named(x, c("round", "protocol", "consent", "items", "enrollments", "events"))
  expect_identical(x$round$instrument_hash, f$round$hash)
  expect_equal(nrow(x$items), 6L)
  expect_setequal(x$items$locale, c("en", "fr", "de"))
  expect_identical(x$protocol$version, 1L)
  expect_identical(sum(x$enrollments$n), 2L)
  expect_false(any(c("panelist_id", "principal_id", "membership_id") %in% unlist(lapply(x, names))))
  expect_error(get_round_instrument(r, f$panel[[1]], f$round$id), class = "DEL_FORBIDDEN")
  transition_round(r, f$manager, f$round$id, "review", f$round$hash, "Exact instrument reviewed", "review")
  expect_identical(get_round_instrument(r, f$manager, f$round$id)$events$reason, "Exact instrument reviewed")
})

test_that("an enrollment queued behind a committed close adds nobody", {
  skip_if_not_installed("callr")
  root <- Sys.getenv("DELPHYR_SOURCE_ROOT")
  skip_if(!nzchar(root), "Source root required for independent connection")
  r <- lifecycle_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic", state)
  lifecycle_newcomer(r, f)
  name <- paste0("lifecycle-enroll-", f$study_id)
  DBI::dbBegin(r$con)
  withr::defer(try(DBI::dbRollback(r$con), silent = TRUE))
  DBI::dbGetQuery(r$con, "SELECT id FROM research.rounds WHERE id=$1 FOR UPDATE", params = list(f$round$id))
  child <- callr::r_bg(function(root, libs, f, name) {
    .libPaths(libs)
    pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
    r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test", application_name = name)
    on.exit(DBI::dbDisconnect(r$con))
    DBI::dbExecute(r$con, "SET statement_timeout='15s'")
    tryCatch(paste("added", enroll_panel(r, f$manager, f$round$id, "waiting-enroll")$added), delphyr_error = function(e) e$code)
  }, args = list(root, .libPaths(), f, name), supervise = TRUE)
  withr::defer(if (child$is_alive()) child$kill())
  until <- Sys.time() + 10
  repeat {
    DBI::dbGetQuery(r$con, "SELECT pg_stat_clear_snapshot()")
    st <- DBI::dbGetQuery(r$con, "SELECT wait_event_type FROM pg_stat_activity WHERE application_name=$1", params = list(name))
    if (nrow(st) == 1L && identical(st$wait_event_type, "Lock")) break
    if (!child$is_alive() || Sys.time() > until) stop("Enrollment did not reach the lock barrier: ", paste(child$read_error(), collapse = "; "))
    Sys.sleep(.025)
  }
  DBI::dbExecute(r$con, "UPDATE research.rounds SET state='closed',closed_at=clock_timestamp() WHERE id=$1", params = list(f$round$id))
  DBI::dbCommit(r$con)
  child$wait(timeout = 20000)
  expect_identical(child$get_result(), "DEL_CONFLICT")
  expect_equal(DBI::dbGetQuery(r$con, "SELECT count(*)::int AS n FROM research.enrollments WHERE round_id=$1", params = list(f$round$id))$n, 2L)
})
