communication_repo <- function(env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "PostgreSQL opt-in required")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(r$con), envir = env)
  r
}
communication_fixture <- function(r) {
  f <- demo_study(r, n = 2L, item_count = 1L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic communications test", state)
  f$enrollments <- vapply(f$panel, function(a) {
    record_consent(r, a, f$study_id, f$consent_id, TRUE, "consent")
    list_enrollments(r, a, f$study_id)$id[1]
  }, character(1))
  f
}
communication_campaign <- function(r, f, key = "prepare", kind = "reminder", recipients = f$enrollments) {
  prepare_campaign(r, f$manager, f$round$id, recipients, kind, "Synthetic reminder",
    "Synthetic demonstration only. No external delivery.",
    command_id = key
  )
}
communication_release <- function(r, f, c, key = "release") {
  release_campaign(r, f$manager, c$id, c$hash, "Reviewed exact synthetic recipients and text", key)
}
communication_statement <- function(con, sql, params) {
  x <- DBI::dbSendStatement(con, sql)
  on.exit(DBI::dbClearResult(x))
  DBI::dbBind(x, params)
  invisible(DBI::dbGetRowsAffected(x))
}

test_that("campaign approval binds exact content and recipients with idempotent outbox", {
  r <- communication_repo()
  f <- communication_fixture(r)
  c <- communication_campaign(r, f)
  expect_identical(communication_campaign(r, f), c)
  expect_identical(process_campaign_sink(r, f$study_id), FALSE)
  preview <- preview_campaign(r, f$manager, c$id)
  expect_equal(nrow(preview$recipients), 2L)
  expect_false(any(c("subject", "email", "principal_id", "value_int") %in% names(preview$recipients)))
  expect_false(preview$released)
  expect_error(release_campaign(r, f$manager, c$id, "unreviewed", "Synthetic reason", "wrong-hash"), class = "DEL_CONFLICT")
  expect_error(prepare_campaign(r, f$manager, f$round$id, f$enrollments, "reminder", "Altered",
    "Synthetic body",
    command_id = "prepare"
  ), class = "DEL_CONFLICT")
  released <- communication_release(r, f, c)
  expect_identical(communication_release(r, f, c), released)
  expect_equal(query(r, "SELECT count(*) AS n FROM ops.message_outbox WHERE campaign_id=$1", c$id)$n, 2)
  first <- process_campaign_sink(r, f$study_id)
  second <- process_campaign_sink(r, f$study_id)
  expect_identical(first$state, "sink_recorded")
  expect_identical(second$state, "sink_recorded")
  expect_false(identical(first$id, second$id))
  expect_identical(process_campaign_sink(r, f$study_id), FALSE)
  expect_equal(query(r, "SELECT count(*) AS n FROM ops.message_sink s JOIN ops.message_outbox o ON o.id=s.message_id WHERE o.campaign_id=$1", c$id)$n, 2)
  expect_true(preview_campaign(r, f$manager, c$id)$released)
})

test_that("cross study recipients and non-coordinator access are rejected", {
  r <- communication_repo()
  f <- communication_fixture(r)
  other <- communication_fixture(r)
  expect_error(communication_campaign(r, f, recipients = c(f$enrollments[1], other$enrollments[1])), class = "DEL_NOT_FOUND")
  c <- communication_campaign(r, f)
  expect_error(preview_campaign(r, other$manager, c$id), class = "DEL_NOT_FOUND")
  expect_error(preview_campaign(r, f$panel[[1]], c$id), class = "DEL_FORBIDDEN")
  expect_error(prepare_campaign(r, f$manager, f$round$id, f$enrollments, "reminder",
    "Hello {{name}}", "Synthetic body",
    command_id = "placeholder"
  ), class = "DEL_VALIDATION")
  set_capability(r, f$manager, f$study_id, f$manager$principal_id, "coordinate", FALSE, "revoke")
  expect_error(communication_release(r, f, c), class = "DEL_FORBIDDEN")
})

test_that("submission withdrawal and cancellation suppress already approved reminders", {
  r <- communication_repo()
  f <- communication_fixture(r)
  c <- communication_campaign(r, f)
  communication_release(r, f, c)
  q <- get_questionnaire(r, f$panel[[1]], f$enrollments[1])
  save_response(r, f$panel[[1]], f$enrollments[1], q$items$id, list(value = 7L, status = "answered"), 0L, "save")
  submit_round(r, f$panel[[1]], f$enrollments[1], setNames(1L, q$items$id), "submit")
  record_consent(r, f$panel[[2]], f$study_id, f$consent_id, FALSE, "withdraw")
  states <- list(process_campaign_sink(r, f$study_id), process_campaign_sink(r, f$study_id))
  expect_true(all(vapply(states, function(x) x$state == "suppressed", logical(1))))
  expect_setequal(vapply(states, `[[`, character(1), "reason"), c("already_submitted", "consent_withdrawn"))
  expect_equal(query(r, "SELECT count(*) AS n FROM ops.message_sink s JOIN ops.message_outbox o ON o.id=s.message_id WHERE o.campaign_id=$1", c$id)$n, 0)
  cancel <- communication_campaign(r, f, key = "cancel-campaign")
  communication_release(r, f, cancel, key = "release-cancel")
  receipt <- cancel_campaign(r, f$manager, cancel$id, "Synthetic cancellation", "cancel")
  expect_identical(cancel_campaign(r, f$manager, cancel$id, "Synthetic cancellation", "cancel"), receipt)
  expect_identical(process_campaign_sink(r, f$study_id)$reason, "campaign_cancelled")
  expect_identical(process_campaign_sink(r, f$study_id)$reason, "campaign_cancelled")
})

test_that("expired in-flight claims are never blindly resent", {
  r <- communication_repo()
  f <- communication_fixture(r)
  c <- communication_campaign(r, f, recipients = f$enrollments[1])
  communication_release(r, f, c)
  claim <- claim_campaign_message(r, f$study_id)
  expect_equal(nrow(claim), 1L)
  expect_equal(nrow(claim_campaign_message(r, f$study_id)), 0L)
  execute(r, "UPDATE ops.message_delivery SET lease_until=clock_timestamp()-interval '1 second' WHERE message_id=$1", claim$id)
  expect_identical(process_campaign_sink(r, f$study_id), FALSE)
  delivery <- one(query(r, "SELECT state,reason,attempts FROM ops.message_delivery WHERE message_id=$1", claim$id))
  expect_identical(delivery$state, "delivery_unknown")
  expect_identical(delivery$reason, "expired_in_flight_lease")
  expect_equal(delivery$attempts, 1L)
  expect_error(complete_campaign_sink(r, claim), class = "DEL_NOT_FOUND")
  expect_identical(process_campaign_sink(r, f$study_id), FALSE)
})

test_that("released envelopes remain immutable and changed authority stops delivery", {
  r <- communication_repo()
  f <- communication_fixture(r)
  c <- communication_campaign(r, f, recipients = f$enrollments[1])
  communication_release(r, f, c)
  expect_error(communication_statement(r$con, "UPDATE ops.campaigns SET body='altered' WHERE id=$1", list(c$id)), "immutable record")
  expect_error(communication_statement(r$con, "INSERT INTO ops.campaign_recipients VALUES($1,$2,$3,$4)", list(f$study_id, f$round$id, c$id, f$enrollments[2])), "campaign recipients released")
  set_capability(r, f$manager, f$study_id, f$manager$principal_id, "coordinate", FALSE, "revoke")
  expect_identical(process_campaign_sink(r, f$study_id)$reason, "approval_authority_revoked")
  expect_equal(query(r, "SELECT count(*) AS n FROM ops.message_sink s JOIN ops.message_outbox o ON o.id=s.message_id WHERE o.campaign_id=$1", c$id)$n, 0)
})
