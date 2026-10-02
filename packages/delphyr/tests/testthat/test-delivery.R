delivery_repo <- function(env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "PostgreSQL opt-in required")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(r$con), envir = env)
  r
}
delivery_stamp <- function(seconds) format(Sys.time() + seconds, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
# A local clock time of the study's timezone, shifted by whole hours.
delivery_clock <- function(hours, timezone = "Europe/Berlin") format(as.POSIXct(Sys.time(), tz = timezone) + hours * 3600, "%H:%M", tz = timezone)
# An open round with two consenting synthetic members; `rules` extends the
# protocol's communication settings.
delivery_fixture <- function(r, rules = list()) {
  code <- paste0("DELIVERY-", substr(uid(), 1, 8))
  manager <- demo_actor(r, provision_demo_principal(r, paste0("demo-manager-", code), TRUE))
  p <- demo_protocol()
  p$study$code <- code
  p$study$languages <- "en"
  p$communications <- c(p$communications, rules)
  study <- create_study(r, manager, p, "create")$id
  consent <- publish_consent(r, manager, study, "Synthetic information.", "en", "consent")$id
  panel <- lapply(1:2, function(i) {
    actor <- demo_actor(r, provision_demo_principal(r, paste0("demo-", code, "-", i)))
    add_panelist(r, manager, study, actor$principal_id, unlist(p$panel$groups)[i], paste0("panel-", i))
    actor
  })
  items <- data.frame(item_code = "I001", item_version = 1L, locale = "en", text = "Synthetic item", dimension_code = "relevance", scale_code = "relevance_9", source_ref = "SRC", required = TRUE, display_order = 1L)
  round <- prepare_round(r, manager, study, items, consent, delivery_stamp(86400), "round")
  for (state in c("review", "approved", "open")) transition_round(r, manager, round$id, state, round$hash, "Synthetic", state)
  enrollments <- vapply(panel, function(a) {
    record_consent(r, a, study, consent, TRUE, "consent")
    list_enrollments(r, a, study)$id
  }, character(1))
  list(code = code, manager = manager, panel = panel, study_id = study, consent = consent, round = round, enrollments = enrollments)
}
delivery_campaign <- function(r, f, key, recipients = f$enrollments, kind = "reminder", not_before = NULL, release = TRUE) {
  c <- prepare_campaign(r, f$manager, f$round$id, recipients, kind, "Synthetic subject", "Synthetic body. No external delivery.", command_id = paste("prepare", key))
  if (release) c$release <- release_campaign(r, f$manager, c$id, c$hash, "Exact text and recipients reviewed", paste("release", key), not_before = not_before)
  c
}
delivery_states <- function(r, campaign) query(r, "SELECT d.state,d.reason,d.attempts,d.adapter,d.provider_ref,o.id FROM ops.message_delivery d JOIN ops.message_outbox o ON o.id=d.message_id WHERE o.campaign_id=$1 ORDER BY o.enrollment_id", campaign)
# A member who joined through an accepted invitation has a contact record.
delivery_invited_member <- function(r, f) {
  csv <- paste("external_ref,email,display_name,locale,stakeholder_group", "D-1,delivery-canary@example.invalid,Synthetic Recipient,en,professionals", sep = "\n")
  preview <- preview_panel_import(r, f$manager, f$study_id, csv)
  draft <- import_panel(r, f$manager, f$study_id, preview, preview$hash, "Synthetic contact", "import")$invitation_ids[[1]]
  issuer <- "https://delivery-idp.example.invalid"
  subject <- paste0("member-", uid())
  account <- register_invited_account(r, f$manager, f$study_id, issuer, subject, "Stable account", "register")$id
  token <- new_invitation_token()
  invitation <- issue_panel_invitation(r, f$manager, f$study_id, draft, account, token, 900L, "Approved account", "issue")$id
  config <- new_authentication_config(issuer, paste(rep("a", 64), collapse = ""), "127.0.0.1")
  actor <- authenticated_actor(r, list(REMOTE_ADDR = "127.0.0.1", HTTP_X_DELPHYR_GATEWAY = config$gateway_secret, HTTP_X_FORWARDED_USER = subject), config)
  accept_panel_invitation(r, actor, f$study_id, invitation, token, TRUE, "accept")
  enroll_panel(r, f$manager, f$round$id, paste("enroll", subject))
  record_consent(r, actor, f$study_id, f$consent, TRUE, "consent")
  list(actor = actor, enrollment = list_enrollments(r, actor, f$study_id)$id)
}

test_that("protocol communication rules are optional and validated", {
  p <- demo_protocol()
  expect_true(validate_protocol(p)$valid)
  p$communications$quiet_hours <- list(start = "20:00", end = "08:00")
  p$communications$max_reminders <- 2
  p$communications$min_reminder_interval_hours <- 48
  expect_true(validate_protocol(p)$valid)
  for (bad in list(list(start = "20:00", end = "20:00"), list(start = "24:00", end = "08:00"), list(start = "8pm", end = "08:00"), list(start = "20:00"))) {
    q <- p
    q$communications$quiet_hours <- bad
    expect_identical(validate_protocol(q)$issues$path, "communications.quiet_hours")
  }
  q <- p
  q$communications$max_reminders <- -1
  expect_identical(validate_protocol(q)$issues$path, "communications.max_reminders")
  q <- p
  q$communications$min_reminder_interval_hours <- 0
  expect_identical(validate_protocol(q)$issues$path, "communications.min_reminder_interval_hours")
  q <- p
  q$communications$send_real_mail <- TRUE
  expect_false(validate_protocol(q)$valid)
})

test_that("an approved send time holds a message until it is reached", {
  r <- delivery_repo()
  f <- delivery_fixture(r)
  draft <- delivery_campaign(r, f, "draft", release = FALSE)
  for (bad in list("2026-12-01 09:00", delivery_stamp(-3600), delivery_stamp(100 * 86400))) {
    expect_error(release_campaign(r, f$manager, draft$id, draft$hash, "Reviewed", paste("bad", bad), not_before = bad), class = "DEL_VALIDATION")
  }
  at <- delivery_stamp(3)
  released <- release_campaign(r, f$manager, draft$id, draft$hash, "Reviewed", "timed", not_before = at)
  expect_identical(released$not_before, at)
  expect_identical(release_campaign(r, f$manager, draft$id, draft$hash, "Reviewed", "timed", not_before = at), released)
  preview <- preview_campaign(r, f$manager, draft$id)
  expect_identical(preview$schedule$not_before, at)
  expect_null(preview$rules$max_reminders)
  expect_identical(process_campaign_sink(r, f$study_id), FALSE)
  expect_setequal(delivery_states(r, draft$id)$state, "queued")
  Sys.sleep(3.5)
  expect_identical(process_campaign_sink(r, f$study_id)$state, "sink_recorded")
  expect_error(execute(r, "UPDATE ops.campaign_schedules SET not_before=clock_timestamp() WHERE campaign_id=$1", draft$id), "immutable")
})

test_that("quiet hours of the study timezone hold approved messages", {
  r <- delivery_repo()
  quiet <- delivery_fixture(r, list(quiet_hours = list(start = delivery_clock(-1), end = delivery_clock(1))))
  held <- delivery_campaign(r, quiet, "held")
  expect_identical(preview_campaign(r, quiet$manager, held$id)$schedule$quiet_start, delivery_clock(-1))
  expect_identical(process_campaign_sink(r, quiet$study_id), FALSE)
  expect_setequal(delivery_states(r, held$id)$state, "queued")
  # A window that passes midnight and still contains the current time.
  wrapped <- delivery_fixture(r, list(quiet_hours = list(start = delivery_clock(2), end = delivery_clock(1))))
  delivery_campaign(r, wrapped, "wrapped")
  expect_identical(process_campaign_sink(r, wrapped$study_id), FALSE)
  # A window that passes midnight and does not contain the current time.
  free <- delivery_fixture(r, list(quiet_hours = list(start = delivery_clock(1), end = delivery_clock(-1))))
  sent <- delivery_campaign(r, free, "free")
  expect_identical(process_campaign_sink(r, free$study_id)$state, "sink_recorded")
  expect_identical(preview_campaign(r, free$manager, sent$id)$schedule$timezone, "Europe/Berlin")
})

test_that("reminder limits refuse a campaign instead of shrinking its audience", {
  r <- delivery_repo()
  f <- delivery_fixture(r, list(max_reminders = 1))
  # The first member submits before the worker runs: that reminder is
  # suppressed and does not count against the limit.
  q <- get_questionnaire(r, f$panel[[1]], f$enrollments[1])
  save_response(r, f$panel[[1]], f$enrollments[1], q$items$id, list(value = 7L, status = "answered"), 0L, "save")
  first <- delivery_campaign(r, f, "first")
  submit_round(r, f$panel[[1]], f$enrollments[1], setNames(1L, q$items$id), "submit")
  while (!identical(process_campaign_sink(r, f$study_id), FALSE)) NULL
  expect_setequal(delivery_states(r, first$id)$state, c("suppressed", "sink_recorded"))
  counts <- list_campaign_enrollments(r, f$manager, f$round$id)
  expect_identical(counts$reminders[match(f$enrollments, counts$enrollment_id)], c(0L, 1L))
  both <- delivery_campaign(r, f, "both", release = FALSE)
  blocked <- tryCatch(release_campaign(r, f$manager, both$id, both$hash, "Reviewed", "release both"), error = function(e) e)
  expect_s3_class(blocked, "DEL_CONFLICT")
  expect_identical(blocked$path, "campaign.reminder_limit")
  expect_equal(nrow(delivery_states(r, both$id)), 0L)
  expect_identical(delivery_campaign(r, f, "first-member", recipients = f$enrollments[1])$release$n_recipients, 1L)
  # Other message kinds are not reminders.
  expect_identical(delivery_campaign(r, f, "deadline", kind = "deadline_change")$release$n_recipients, 2L)
  none <- delivery_fixture(r, list(max_reminders = 0))
  zero <- delivery_campaign(r, none, "zero", release = FALSE)
  expect_error(release_campaign(r, none$manager, zero$id, zero$hash, "Reviewed", "release zero"), class = "DEL_CONFLICT")
  spaced <- delivery_fixture(r, list(max_reminders = 3, min_reminder_interval_hours = 24))
  delivery_campaign(r, spaced, "one")
  soon <- delivery_campaign(r, spaced, "soon", release = FALSE)
  early <- tryCatch(release_campaign(r, spaced$manager, soon$id, soon$hash, "Reviewed", "release soon", not_before = delivery_stamp(3600)), error = function(e) e)
  expect_identical(early$path, "campaign.reminder_interval")
  expect_identical(release_campaign(r, spaced$manager, soon$id, soon$hash, "Reviewed", "release later", not_before = delivery_stamp(25 * 3600))$n_recipients, 2L)
})

test_that("a provider adapter receives one eligible message with a stable idempotency key", {
  r <- delivery_repo()
  f <- delivery_fixture(r)
  member <- delivery_invited_member(r, f)
  seen <- list()
  accepting <- new_message_adapter("test_accept", function(message) {
    seen[[length(seen) + 1L]] <<- message
    list(status = "accepted", provider_ref = paste0("provider-", length(seen)))
  })
  expect_error(new_message_adapter("database_sink", function(m) NULL), class = "DEL_VALIDATION")
  expect_error(new_message_adapter("Bad Name", function(m) NULL), class = "DEL_VALIDATION")
  expect_error(process_campaign_message(r, list(send = identity), f$study_id), class = "DEL_VALIDATION")
  campaign <- delivery_campaign(r, f, "adapter", recipients = c(f$enrollments[1], member$enrollment))
  results <- list(process_campaign_message(r, accepting, f$study_id), process_campaign_message(r, accepting, f$study_id))
  expect_identical(process_campaign_message(r, accepting, f$study_id), FALSE)
  # A member without a contact record is suppressed; the provider is not called.
  expect_setequal(vapply(results, `[[`, character(1), "state"), c("accepted", "suppressed"))
  expect_length(seen, 1L)
  expect_named(seen[[1]], c("message_id", "idempotency_key", "kind", "locale", "subject", "body", "to", "display_name"))
  expect_identical(seen[[1]]$to, "delivery-canary@example.invalid")
  states <- delivery_states(r, campaign$id)
  accepted <- states[states$state == "accepted", ]
  expect_identical(c(accepted$adapter, accepted$provider_ref), c("test_accept", "provider-1"))
  expect_identical(states$reason[states$state == "suppressed"], "no_contact")
  expect_identical(seen[[1]]$idempotency_key, query(r, "SELECT dedupe_key FROM ops.message_outbox WHERE id=$1", accepted$id)$dedupe_key)
  expect_equal(query(r, "SELECT count(*)::int AS n FROM ops.message_sink s JOIN ops.message_outbox o ON o.id=s.message_id WHERE o.campaign_id=$1", campaign$id)$n, 0L)
  events <- list_audit_events(r, f$manager, f$study_id, actions = c("message_accepted", "message_suppressed"))
  expect_setequal(events$action, c("message_accepted", "message_suppressed"))
  expect_false(any(grepl("delivery-canary", unlist(lapply(events, as.character)), fixed = TRUE)))
  # Eligibility is checked again immediately before the provider is called.
  q <- get_questionnaire(r, member$actor, member$enrollment)
  save_response(r, member$actor, member$enrollment, q$items$id, list(value = 8L, status = "answered"), 0L, "save")
  late <- delivery_campaign(r, f, "late", recipients = member$enrollment)
  submit_round(r, member$actor, member$enrollment, setNames(1L, q$items$id), "submit")
  expect_identical(process_campaign_message(r, accepting, f$study_id)$reason, "already_submitted")
  expect_length(seen, 1L)
})

test_that("transient failures retry with the same key and permanent ones stop", {
  r <- delivery_repo()
  f <- delivery_fixture(r)
  member <- delivery_invited_member(r, f)
  keys <- character()
  retrying <- new_message_adapter("test_retry", function(message) {
    keys <<- c(keys, message$idempotency_key)
    list(status = "retry", reason = "rate_limited")
  })
  campaign <- delivery_campaign(r, f, "retry", recipients = member$enrollment)
  expect_identical(process_campaign_message(r, retrying, f$study_id)$state, "queued")
  # The message waits for its retry time.
  expect_identical(process_campaign_message(r, retrying, f$study_id), FALSE)
  state <- delivery_states(r, campaign$id)
  expect_identical(c(state$state, state$reason), c("queued", "rate_limited"))
  expect_true(query(r, "SELECT available_at>clock_timestamp()+interval '100 seconds' AS later FROM ops.message_delivery WHERE message_id=$1", state$id)$later)
  for (attempt in 2:3) {
    execute(r, "UPDATE ops.message_delivery SET available_at=clock_timestamp() WHERE message_id=$1", state$id)
    result <- process_campaign_message(r, retrying, f$study_id)
  }
  expect_identical(c(result$state, result$reason), c("failed", "retries_exhausted"))
  expect_length(unique(keys), 1L)
  expect_length(keys, 3L)
  expect_identical(process_campaign_message(r, retrying, f$study_id), FALSE)
  rejecting <- new_message_adapter("test_reject", function(message) list(status = "rejected", reason = "Invalid Address! <script>"))
  rejected <- delivery_campaign(r, f, "reject", recipients = member$enrollment, kind = "deadline_change")
  result <- process_campaign_message(r, rejecting, f$study_id)
  # A provider's free text is never stored as a reason code.
  expect_identical(c(result$state, result$reason), c("failed", "provider_rejected"))
  expect_identical(process_campaign_message(r, rejecting, f$study_id), FALSE)
})

test_that("an uncertain delivery is never repeated without a documented decision", {
  r <- delivery_repo()
  f <- delivery_fixture(r)
  member <- delivery_invited_member(r, f)
  calls <- 0L
  failing <- new_message_adapter("test_unknown", function(message) {
    calls <<- calls + 1L
    stop("connection reset after the request was sent")
  })
  accepting <- new_message_adapter("test_accept", function(message) {
    calls <<- calls + 1L
    list(status = "accepted", provider_ref = "provider-ok")
  })
  malformed <- new_message_adapter("test_malformed", function(message) "ok")
  campaign <- delivery_campaign(r, f, "unknown", recipients = member$enrollment)
  expect_identical(process_campaign_message(r, failing, f$study_id)$state, "delivery_unknown")
  expect_identical(process_campaign_message(r, accepting, f$study_id), FALSE)
  expect_identical(calls, 1L)
  uncertain <- list_uncertain_deliveries(r, f$manager, f$study_id)
  expect_named(uncertain, c("message_id", "kind", "round_number", "pseudonym", "reason", "adapter", "attempts", "updated_at"))
  expect_identical(c(uncertain$reason, uncertain$adapter), c("adapter_outcome_unknown", "test_unknown"))
  expect_false(any(grepl("example.invalid", unlist(lapply(uncertain, as.character)), fixed = TRUE)))
  message <- uncertain$message_id
  expect_error(list_uncertain_deliveries(r, f$panel[[1]], f$study_id), class = "DEL_FORBIDDEN")
  expect_error(resolve_delivery(r, f$panel[[1]], f$study_id, message, "requeue", "No right", "a"), class = "DEL_FORBIDDEN")
  expect_error(resolve_delivery(r, f$manager, f$study_id, message, "resend_all", "Reason", "b"), class = "DEL_VALIDATION")
  expect_error(resolve_delivery(r, f$manager, f$study_id, message, "requeue", " ", "c"), class = "DEL_VALIDATION")
  other <- delivery_fixture(r)
  expect_error(resolve_delivery(r, other$manager, other$study_id, message, "requeue", "Foreign", "d"), class = "DEL_NOT_FOUND")
  done <- resolve_delivery(r, f$manager, f$study_id, message, "requeue", "Provider log shows no acceptance; a duplicate is acceptable", "requeue")
  expect_identical(done$state, "queued")
  expect_identical(resolve_delivery(r, f$manager, f$study_id, message, "requeue", "Provider log shows no acceptance; a duplicate is acceptable", "requeue"), done)
  expect_error(resolve_delivery(r, f$manager, f$study_id, message, "abandon", "Too late", "e"), class = "DEL_CONFLICT")
  expect_identical(process_campaign_message(r, accepting, f$study_id)$state, "accepted")
  expect_identical(calls, 2L)
  expect_equal(nrow(list_uncertain_deliveries(r, f$manager, f$study_id)), 0L)
  events <- list_audit_events(r, f$manager, f$study_id, actions = "delivery_resolution")
  expect_identical(c(events$detail, events$reason), c("requeue", "Provider log shows no acceptance; a duplicate is acceptable"))
  expect_error(execute(r, "DELETE FROM ops.delivery_resolutions WHERE study_id=$1", f$study_id), "immutable")
  # A malformed provider reply is uncertain too; it can be confirmed or abandoned.
  for (resolution in c("confirmed_delivered", "abandon")) {
    extra <- delivery_campaign(r, f, resolution, recipients = member$enrollment, kind = "deadline_change")
    expect_identical(process_campaign_message(r, malformed, f$study_id)$state, "delivery_unknown")
    id <- delivery_states(r, extra$id)$id
    state <- resolve_delivery(r, f$manager, f$study_id, id, resolution, "Checked with the provider", resolution)$state
    expect_identical(state, c(confirmed_delivered = "resolved_delivered", abandon = "abandoned")[[resolution]])
    expect_identical(process_campaign_message(r, accepting, f$study_id), FALSE)
  }
  status <- get_operations_status(r, f$manager, f$study_id)
  expect_named(status, c("jobs", "messages", "uncertain_deliveries"))
  expect_identical(status$uncertain_deliveries, 0L)
  expect_true(all(c("accepted", "resolved_delivered", "abandoned") %in% status$messages$state))
  expect_error(get_operations_status(r, f$panel[[1]], f$study_id), class = "DEL_FORBIDDEN")
})

test_that("a lease that expires during sending leaves the delivery uncertain", {
  r <- delivery_repo()
  f <- delivery_fixture(r)
  member <- delivery_invited_member(r, f)
  campaign <- delivery_campaign(r, f, "lease", recipients = member$enrollment)
  second <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(second$con))
  slow <- new_message_adapter("test_slow", function(message) {
    # Another worker sweeps the expired claim while the provider call runs.
    execute(second, "UPDATE ops.message_delivery SET lease_until=clock_timestamp()-interval '1 second' WHERE message_id=$1", message$message_id)
    claim_campaign_message(second, f$study_id)
    list(status = "accepted", provider_ref = "provider-late")
  })
  result <- process_campaign_message(r, slow, f$study_id)
  expect_identical(c(result$state, result$reason), c("delivery_unknown", "expired_in_flight_lease"))
  state <- delivery_states(r, campaign$id)
  expect_identical(state$state, "delivery_unknown")
  expect_true(is.na(state$provider_ref))
})
