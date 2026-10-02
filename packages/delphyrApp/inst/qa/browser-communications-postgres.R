# Campaign approval with reminder limits and a send time, and the resolution
# of an uncertain delivery, in Chromium against PostgreSQL:
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-communications-postgres.R
#
# Messages only ever reach the local database sink. The uncertain delivery is
# produced by letting a worker's claim expire, as after a crash.
source("packages/delphyrApp/inst/qa/browser-helpers.R")
port <- 3888L
admin <- qa_admin()
tag <- substr(uuid::UUIDgenerate(), 1, 8)
code <- paste0("QA-COMM-", tag)
manager <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-manager-", code), TRUE))
clock <- function(hours) format(as.POSIXct(Sys.time(), tz = "Europe/Berlin") + hours * 3600, "%H:%M", tz = "Europe/Berlin")
p <- demo_protocol()
p$study$code <- code
p$study$title <- paste("Synthetic communication study", tag)
p$study$languages <- "en"
# Quiet hours that do not contain the current time, and one reminder per round.
p$communications$quiet_hours <- list(start = clock(3), end = clock(5))
p$communications$max_reminders <- 1
study <- create_study(admin, manager, p, "create")$id
consent <- publish_consent(admin, manager, study, "Synthetic demonstration only.", "en", "consent")$id
panel <- lapply(1:2, function(i) {
  actor <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-", code, "-", i)))
  add_panelist(admin, manager, study, actor$principal_id, unlist(p$panel$groups)[i], paste0("panel-", i))
  actor
})
round <- prepare_round(admin, manager, study, data.frame(item_code = "I001", item_version = 1L, locale = "en", text = "Synthetic item", dimension_code = "relevance", scale_code = "relevance_9", source_ref = "SRC", required = TRUE, display_order = 1L), consent, format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), "round")
for (state in c("review", "approved", "open")) invisible(transition_round(admin, manager, round$id, state, round$hash, "Synthetic qualification", state))
enrollments <- vapply(panel, function(a) {
  record_consent(admin, a, study, consent, TRUE, "consent")
  list_enrollments(admin, a, study)$id
}, character(1))
host <- qa_host("communications", port, function(repo, data) delphyrApp::run_app(repo, delphyr::demo_actor(repo, data$principal)), list(principal = manager$principal_id))
on.exit(if (host$is_alive()) host$kill(), add = TRUE)
worker <- qa_connection(Sys.getenv("DELPHYR_DB_RUNTIME", "delphyr_runtime"))
work <- function() while (!identical(process_campaign_sink(worker, study), FALSE)) NULL
settle <- function(seconds = .45) Sys.sleep(seconds)
value <- function(sql, ...) DBI::dbGetQuery(admin$con, sql, params = list(...))
states <- function(campaign) value("SELECT d.state FROM ops.message_delivery d JOIN ops.message_outbox o ON o.id=d.message_id WHERE o.campaign_id=$1 ORDER BY o.enrollment_id", campaign)$state
m <- qa_session()
qa_open(m, sprintf("http://127.0.0.1:%d", port))
m$wait_for(sprintf("document.getElementById('study') !== null && document.getElementById('study').value === '%s'", study))
m$wait_for("document.getElementById('communications-prepare') !== null")
compose <- function(kind, subject, recipients) {
  m$wait_for(sprintf("document.getElementById('communications-enrollments') !== null && document.getElementById('communications-enrollments').selectize !== undefined && Object.keys(document.getElementById('communications-enrollments').selectize.options).includes('%s')", recipients[1]))
  m$js(sprintf("(function(){document.getElementById('communications-enrollments').selectize.setValue(%s);return true;})()", jsonlite::toJSON(recipients)))
  m$select("communications-kind", kind)
  m$type("communications-subject", subject)
  m$type("communications-message", "Synthetic message of the qualification run. No external delivery.")
  settle()
  m$click("communications-prepare")
  m$wait_text("communications-preview", subject)
  value("SELECT id FROM ops.campaigns WHERE study_id=$1 AND subject=$2", study, subject)$id
}
approve <- function(reason, at = "") {
  m$type("communications-reason", reason)
  m$type("communications-not_before", at)
  settle()
  if (!isTRUE(m$js("document.getElementById('communications-confirm').checked"))) m$click("communications-confirm")
  settle(.3)
  m$click("communications-release")
}

# 1. A reminder is previewed with the study's rules, approved and recorded.
# Option labels of the recipient control state each person's reminder count.
recipient_labels <- function(text) m$wait_for(sprintf("(function(){var x=document.getElementById('communications-enrollments');return !!x && !!x.selectize && Object.values(x.selectize.options).every(function(o){return o.label.includes('%s');});})()", text))
recipient_labels("reminders: 0")
first <- compose("reminder", paste("First reminder", tag), enrollments)
preview <- m$text("communications-preview")
stopifnot(grepl("Quiet hours:", preview, fixed = TRUE), grepl("Maximum reminders per person and round: 1", preview, fixed = TRUE), grepl("2 exactly selected recipients", preview, fixed = TRUE))
approve("Exact text and both recipients reviewed")
m$wait_text("communications-status", "Approved. No email will be sent.")
m$wait_text("communications-preview", "Approved from (UTC):")
stopifnot(identical(states(first), c("queued", "queued")))
work()
m$click("communications-refresh")
m$wait_text("communications-recipient_preview", "Local receipt recorded")
stopifnot(identical(states(first), c("sink_recorded", "sink_recorded")))

# 2. A second reminder to the same people exceeds the limit and is refused.
invisible(m$b$Page$reload())
m$wait_for("document.getElementById('communications-prepare') !== null")
recipient_labels("reminders: 1")
second <- compose("reminder", paste("Second reminder", tag), enrollments)
approve("Exact text and both recipients reviewed")
m$wait_text("communications-status", "Not approved: at least one person has reached the maximum number of reminders")
stopifnot(length(states(second)) == 0L, value("SELECT count(*)::int AS n FROM ops.campaign_releases WHERE campaign_id=$1", second)$n == 0L)

# 3. A send time needs a timezone; an approved future time holds the messages.
third <- compose("deadline_change", paste("Deadline notice", tag), enrollments[1])
approve("Exact text and recipient reviewed", "tomorrow at nine")
m$wait_text("communications-status", "Not approved: the time needs a timezone")
later <- format(Sys.time() + 3600, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
approve("Exact text and recipient reviewed", later)
m$wait_text("communications-status", "Approved. No email will be sent.")
m$wait_text("communications-preview", paste("Approved from (UTC):", later))
work()
stopifnot(identical(states(third), "queued"))

# 4. A worker's claim expires as after a crash: the delivery is uncertain.
fourth <- prepare_campaign(admin, manager, round$id, enrollments[2], "completion", paste("Completion notice", tag), "Synthetic message.", command_id = "fourth")
invisible(release_campaign(admin, manager, fourth$id, fourth$hash, "Exact text and recipient reviewed", "release-fourth"))
claim <- delphyr:::claim_campaign_message(admin, study)
invisible(DBI::dbExecute(admin$con, "UPDATE ops.message_delivery SET lease_until=clock_timestamp()-interval '1 second' WHERE message_id=$1", params = list(claim$id)))
work()
stopifnot(identical(states(fourth$id), "delivery_unknown"), value("SELECT count(*)::int AS n FROM ops.message_sink WHERE message_id=$1", claim$id)$n == 0L)
invisible(m$b$Page$reload())
m$wait_for("document.getElementById('communications-resolve') !== null")
m$expand("communications-resolve")
m$wait_text("communications-uncertain", "Study completion")
stopifnot(grepl("Resolve uncertain deliveries (1)", m$text("section-communications"), fixed = TRUE))
m$select("communications-resolution", "abandon")
settle()
m$click("communications-resolve")
m$wait_text("communications-status", "A reason and confirmation are required.")
stopifnot(identical(states(fourth$id), "delivery_unknown"))
m$type("communications-resolution_reason", "No local receipt exists; the study is complete and the notice is no longer needed.")
settle()
m$click("communications-resolution_confirm")
settle(.3)
m$click("communications-resolve")
m$wait_text("communications-status", "Delivery decision saved.")
m$wait_for("document.getElementById('section-communications').innerText.includes('Resolve uncertain deliveries (0)')")
resolution <- value("SELECT resolution,reason FROM ops.delivery_resolutions WHERE message_id=$1", claim$id)
work()
stopifnot(identical(states(fourth$id), "abandoned"), identical(resolution$resolution, "abandon"), grepl("No local receipt exists", resolution$reason, fixed = TRUE))

# 5. Study management reads the status of background work.
m$expand("management-background_load")
m$click("management-background_load")
m$wait_text("management-background_messages", "Local receipt recorded")
status <- m$text("management-background_messages")
stopifnot(grepl("Abandoned", status, fixed = TRUE), grepl("Queued", status, fixed = TRUE))
page <- m$js("document.documentElement.outerHTML")
stopifnot(!grepl("example.invalid", page, fixed = TRUE), !any(vapply(panel, function(a) grepl(a$principal_id, page, fixed = TRUE), logical(1))))
if (!identical(m$output_errors(), 0L)) stop("Output errors: ", m$output_error_ids())
for (mobile in c(TRUE, FALSE)) {
  m$viewport(mobile)
  Sys.sleep(.3)
  stopifnot(m$no_overflow())
}
m$close()
DBI::dbDisconnect(worker$con)
DBI::dbDisconnect(admin$con)
print(list(
  rules_shown_before_approval = TRUE, reminder_recorded_in_sink = 2L, second_reminder_refused_by_limit = TRUE,
  send_time_requires_timezone = TRUE, future_send_time_holds_messages = TRUE, uncertain_delivery_never_repeated = TRUE,
  resolution_needs_rationale_and_confirmation = TRUE, background_status_shown = TRUE, mobile_overflow = FALSE
))
