lifecycle_repo <- function(env = parent.frame(), user = "postgres") {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = user, environment = "test")
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

test_that("the database keeps an opened round's rules, instrument and lifecycle for every role", {
  r <- lifecycle_repo()
  runtime <- lifecycle_repo(user = "delphyr_runtime")
  f <- demo_study(r, n = 2L, item_count = 1L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic", state)
  versions <- list_protocol_versions(r, f$manager, f$study_id)
  p <- delphyr:::from_json(versions$config)
  p$analysis$consensus$min_valid_n <- 2L
  amended <- amend_protocol(r, f$manager, f$study_id, p, versions$hash, "Rules for later rounds", "amend")
  # The application role writes only the state, the deadline and the closing time.
  for (column in c("protocol_id", "consent_version_id", "instrument_hash", "number", "study_id")) {
    expect_error(execute(runtime, paste0("UPDATE research.rounds SET ", column, "=", column, " WHERE id=$1"), f$round$id), "permission denied")
  }
  # What was reviewed stays as it was, whoever writes.
  expect_error(execute(r, "UPDATE research.rounds SET protocol_id=$2 WHERE id=$1", f$round$id, amended$id), "reviewed round is immutable")
  expect_error(execute(r, "UPDATE research.rounds SET instrument_hash='altered' WHERE id=$1", f$round$id), "reviewed round is immutable")
  # An opened round never returns to a state that unlocks its instrument or
  # allows its cancellation.
  for (repo in list(r, runtime)) {
    for (state in c("draft", "review", "approved")) expect_error(execute(repo, "UPDATE research.rounds SET state=$2 WHERE id=$1", f$round$id, state), "round transition refused")
  }
  item <- query(r, "SELECT id FROM research.round_items WHERE round_id=$1", f$round$id)$id
  expect_error(execute(r, "INSERT INTO research.round_items SELECT $2,study_id,round_id,'I999',1,dimension_code,scale_code,texts,required,99,source_ref FROM research.round_items WHERE id=$1", item, uid()), "instrument locked")
  # The services still make their changes under the application role.
  later <- lifecycle_deadline(8)
  expect_identical(change_round_deadline(runtime, f$manager, f$round$id, later, f$round$hash, "More time", "extend")$deadline, later)
  member <- query(r, "SELECT panelist_id FROM research.enrollments WHERE round_id=$1 AND group_code='professionals'", f$round$id)$panelist_id
  expect_identical(set_panel_group(runtime, f$manager, f$study_id, member, "public_contributors", "Reclassified", "group")$group_code, "public_contributors")
  transition_round(runtime, f$manager, f$round$id, "closed", f$round$hash, "Close", "close")
  expect_error(execute(runtime, "UPDATE research.rounds SET state='open' WHERE id=$1", f$round$id), "round transition refused")
  expect_error(execute(runtime, "UPDATE research.rounds SET deadline=deadline+interval '1 day' WHERE id=$1", f$round$id), "round deadline locked")
  expect_error(execute(runtime, "UPDATE research.rounds SET closed_at=clock_timestamp() WHERE id=$1", f$round$id), "round closing time locked")
  stored <- query(r, "SELECT state,protocol_id,instrument_hash FROM research.rounds WHERE id=$1", f$round$id)
  expect_identical(c(stored$state, stored$instrument_hash), c("closed", f$round$hash))
  expect_false(identical(stored$protocol_id, amended$id))
  expect_equal(query(r, "SELECT count(*)::int AS n FROM research.round_items WHERE round_id=$1", f$round$id)$n, 1L)
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
  decided <- record_item_decision(r, f$manager, analysis$id, "I001", "finalize", "Synthetic decision", "decide")
  transition_round(r, f$manager, f$round$id, "finalized", f$round$hash, "Final round", "finalize")
  extra <- prepare_round(r, f$manager, f$study_id, f$items, f$consent_id, lifecycle_deadline(), "round-2")
  expect_error(complete_study(r, f$manager, f$study_id, "Stop after round 1", "complete"), class = "DEL_CONFLICT")
  transition_round(r, f$manager, extra$id, "cancelled", extra$hash, "No further round is needed", "cancel")
  done <- complete_study(r, f$manager, f$study_id, "Stop after round 1", "complete-2")
  expect_identical(done$state, "completed")
  expect_error(enroll_panel(r, f$manager, extra$id, "enroll"), class = "DEL_CONFLICT")
  # A completed study keeps the decisions, panel, groups, protocol and
  # information it was completed with; a retry of an earlier decision
  # returns its receipt.
  newcomer <- provision_demo_principal(r, paste0("demo-late-", uid()))
  member <- query(r, "SELECT panelist_id FROM research.enrollments WHERE round_id=$1 AND group_code='professionals'", f$round$id)$panelist_id
  versions <- list_protocol_versions(r, f$manager, f$study_id)
  amended <- delphyr:::from_json(versions$config)
  amended$stopping$max_rounds <- 4L
  for (attempt in list(
    function() record_item_decision(r, f$manager, analysis$id, "I001", "remove", "Changed after completion", "decide-late"),
    function() add_panelist(r, f$manager, f$study_id, newcomer, "professionals", "late-member"),
    function() publish_consent(r, f$manager, f$study_id, "Synthetic information, revised", "en", "consent-late"),
    function() prepare_round(r, f$manager, f$study_id, f$items, f$consent_id, lifecycle_deadline(), "round-late"),
    function() set_panel_group(r, f$manager, f$study_id, member, "public_contributors", "After completion", "group-late"),
    function() amend_protocol(r, f$manager, f$study_id, amended, versions$hash, "After completion", "amend-late")
  )) {
    refused <- tryCatch(attempt(), error = function(e) e)
    expect_s3_class(refused, "DEL_CONFLICT")
    expect_identical(refused$path, "study.state")
  }
  expect_identical(record_item_decision(r, f$manager, analysis$id, "I001", "finalize", "Synthetic decision", "decide"), decided)
  expect_identical(list_item_decisions(r, f$manager, f$study_id)$disposition, "finalize")
  expect_equal(nrow(list_panel(r, f$manager, f$study_id)), 2L)
  # Completion is final in the database as well.
  runtime <- lifecycle_repo(user = "delphyr_runtime")
  for (repo in list(r, runtime)) {
    for (state in c("active", "draft")) expect_error(execute(repo, "UPDATE research.studies SET state=$2 WHERE id=$1", f$study_id, state), "study transition refused")
  }
  expect_error(execute(runtime, "UPDATE research.studies SET title='Renamed' WHERE id=$1", f$study_id), "permission denied")
  expect_identical(query(r, "SELECT state FROM research.studies WHERE id=$1", f$study_id)$state, "completed")
})

test_that("opening after the deadline is refused with the readiness finding", {
  r <- lifecycle_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  transition_round(r, f$manager, f$round$id, "cancelled", f$round$hash, "Replaced", "cancel")
  # Preparation and approval accept a deadline that has passed; opening does not.
  late <- prepare_round(r, f$manager, f$study_id, f$items, f$consent_id, lifecycle_deadline(-1), "late")
  for (state in c("review", "approved")) transition_round(r, f$manager, late$id, state, late$hash, "Synthetic", state)
  expect_true("deadline_passed" %in% lifecycle_codes(get_round_readiness(r, f$manager, late$id), "error"))
  refused <- tryCatch(transition_round(r, f$manager, late$id, "open", late$hash, "Open", "open"), error = function(e) e)
  expect_s3_class(refused, "DEL_VALIDATION")
  expect_identical(refused$path, "round.readiness:deadline_passed")
  expect_identical(query(r, "SELECT state FROM research.rounds WHERE id=$1", late$id)$state, "approved")
  change_round_deadline(r, f$manager, late$id, lifecycle_deadline(), late$hash, "New deadline", "deadline")
  expect_identical(transition_round(r, f$manager, late$id, "open", late$hash, "Open", "open-2")$state, "open")
})

test_that("an opening that waits for a protocol amendment judges the amended protocol", {
  skip_if_not_installed("callr")
  root <- Sys.getenv("DELPHYR_SOURCE_ROOT")
  skip_if(!nzchar(root), "Source root required for independent connections")
  r <- lifecycle_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  for (state in c("review", "approved")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic", state)
  versions <- list_protocol_versions(r, f$manager, f$study_id)
  p <- delphyr:::from_json(versions$config)
  p$analysis$consensus$min_valid_n <- 2L
  child <- function(action, name) {
    callr::r_bg(function(root, libs, f, p, hash, action, name) {
      .libPaths(libs)
      pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
      r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "delphyr_runtime", environment = "test", application_name = name)
      on.exit(DBI::dbDisconnect(r$con))
      DBI::dbExecute(r$con, "SET statement_timeout='20s'")
      tryCatch(
        if (action == "amend") amend_protocol(r, f$manager, f$study_id, p, hash, "Rules changed", "amend")$version else transition_round(r, f$manager, f$round$id, "open", f$round$hash, "Open", "open")$state,
        delphyr_error = function(e) paste(e$code, e$path)
      )
    }, args = list(root, .libPaths(), f, p, versions$hash, action, name), supervise = TRUE)
  }
  wait_locked <- function(name, process) {
    until <- Sys.time() + 15
    repeat {
      query(r, "SELECT pg_stat_clear_snapshot()")
      st <- query(r, "SELECT wait_event_type FROM pg_stat_activity WHERE application_name=$1", name)
      if (nrow(st) == 1L && identical(st$wait_event_type, "Lock")) break
      if (!process$is_alive() || Sys.time() > until) stop("Child did not reach the lock barrier: ", paste(process$read_error(), collapse = "; "))
      Sys.sleep(.025)
    }
  }
  # The amendment holds the study and waits at its command lock while the
  # opening starts.
  DBI::dbBegin(r$con)
  withr::defer(try(DBI::dbRollback(r$con), silent = TRUE))
  query(r, "SELECT pg_advisory_xact_lock(hashtextextended($1,0))", paste(f$study_id, f$manager$principal_id, "amend_protocol", "amend", sep = ":"))
  labels <- paste0(c("amend-", "open-"), f$study_id)
  amend <- child("amend", labels[1])
  withr::defer(if (amend$is_alive()) amend$kill())
  wait_locked(labels[1], amend)
  opening <- child("open", labels[2])
  withr::defer(if (opening$is_alive()) opening$kill())
  wait_locked(labels[2], opening)
  DBI::dbCommit(r$con)
  amend$wait(timeout = 25000)
  opening$wait(timeout = 25000)
  expect_identical(amend$get_result(), 2L)
  expect_identical(opening$get_result(), "DEL_VALIDATION round.readiness:protocol_superseded")
  expect_identical(query(r, "SELECT state FROM research.rounds WHERE id=$1", f$round$id)$state, "approved")
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
  assigned <- assign_feedback(r, f$manager, second$id, feedback$id, "assign")
  expect_false("feedback_unassigned" %in% get_round_readiness(r, f$manager, second$id)$issues$code)
  # A round shows one feedback: a retry returns the receipt, a repeated
  # assignment under a new key is a conflict, not a storage failure.
  expect_identical(assign_feedback(r, f$manager, second$id, feedback$id, "assign"), assigned)
  repeated <- tryCatch(assign_feedback(r, f$manager, second$id, feedback$id, "assign-again"), error = function(e) e)
  expect_s3_class(repeated, "DEL_CONFLICT")
  expect_identical(repeated$path, "feedback.assigned")
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
  enrolled <- function(actor) query(r, "SELECT count(*)::int AS n FROM research.enrollments e JOIN identity.panelist_links l ON l.study_id=e.study_id AND l.panelist_id=e.panelist_id JOIN identity.memberships m ON m.study_id=l.study_id AND m.id=l.membership_id WHERE e.round_id=$1 AND m.principal_id=$2", third$id, actor$principal_id)$n
  expect_identical(enrolled(newcomer), 1L)
  assign_feedback(r, f$manager, third$id, feedback$id, "assign-2")
  another <- lifecycle_newcomer(r, f)
  expect_identical(enroll_panel(r, f$manager, third$id, "enroll-2")$added, 1L)
  # Members see the round, and the feedback assigned to it, once it opens.
  expect_equal(nrow(list_enrollments(r, another, f$study_id)), 0L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, third$id, state, third$hash, "Synthetic", paste0("third-", state))
  shown <- get_feedback(r, another, list_enrollments(r, another, f$study_id)$id)
  expect_identical(shown$id, feedback$id)
  expect_equal(nrow(shown$own), 0L)
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

test_that("panel members see neither a candidate under preparation nor a withdrawn one", {
  r <- lifecycle_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  member <- f$panel[[1]]
  own <- function(round) query(r, "SELECT e.id FROM research.enrollments e JOIN identity.panelist_links l ON l.study_id=e.study_id AND l.panelist_id=e.panelist_id JOIN identity.memberships m ON m.study_id=l.study_id AND m.id=l.membership_id WHERE e.round_id=$1 AND m.principal_id=$2", round, member$principal_id)$id
  item <- query(r, "SELECT id FROM research.round_items WHERE round_id=$1", f$round$id)$id
  outcome <- function(call) tryCatch(paste("accepted", class(call)[1]), error = function(e) paste(e$code, e$path))
  hidden <- function(enrollment) {
    expect_equal(nrow(list_enrollments(r, member, f$study_id)), 0L)
    expect_identical(outcome(get_questionnaire(r, member, enrollment)), "DEL_NOT_FOUND object")
    expect_identical(outcome(get_feedback(r, member, enrollment)), "DEL_NOT_FOUND object")
    expect_identical(outcome(save_response(r, member, enrollment, item, list(value = 7L, status = "answered"), 0L, uid())), "DEL_NOT_FOUND object")
  }
  record_consent(r, member, f$study_id, f$consent_id, TRUE, "consent")
  hidden(own(f$round$id))
  for (state in c("review", "approved")) {
    transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic", state)
    hidden(own(f$round$id))
  }
  transition_round(r, f$manager, f$round$id, "cancelled", f$round$hash, "Typo found before opening", "cancel")
  hidden(own(f$round$id))
  replacement <- prepare_round(r, f$manager, f$study_id, f$items, f$consent_id, lifecycle_deadline(), "replacement")
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, replacement$id, state, replacement$hash, "Synthetic", paste0("new-", state))
  listed <- list_enrollments(r, member, f$study_id)
  expect_identical(listed$id, own(replacement$id))
  expect_identical(get_questionnaire(r, member, listed$id)$round$state, "open")
  # The withdrawn candidate stays unreadable through its old identifier.
  expect_identical(outcome(get_questionnaire(r, member, own(f$round$id))), "DEL_NOT_FOUND object")
})

test_that("times PostgreSQL cannot convert are refused before any statement", {
  r <- lifecycle_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  for (bad in c("2027-01-10T12:00:00+16:00", "2027-01-10T12:00:00-23:59", "0000-01-10T12:00:00Z", "2027-02-29T12:00:00Z")) {
    for (call in list(
      function() change_round_deadline(r, f$manager, f$round$id, bad, f$round$hash, "Synthetic", uid()),
      function() prepare_round(r, f$manager, f$study_id, f$items, f$consent_id, bad, uid())
    )) {
      refused <- tryCatch(call(), error = function(e) e)
      expect_s3_class(refused, "DEL_VALIDATION")
      expect_identical(refused$path, "deadline.format")
    }
  }
  # The extremes PostgreSQL accepts are accepted.
  for (good in c("2099-01-10T12:00:00+15:59", "2099-01-10T12:00:00-15:59")) {
    expect_true(delphyr:::valid_time(good))
    expect_identical(DBI::dbGetQuery(r$con, "SELECT $1::timestamptz IS NOT NULL AS ok", params = list(good))$ok, TRUE)
  }
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
