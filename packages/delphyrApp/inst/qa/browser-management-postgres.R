# Study management in Chromium against PostgreSQL under the restricted runtime
# role. Run from the repository root:
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-management-postgres.R
source("packages/delphyrApp/inst/qa/browser-helpers.R")
port <- 3880L
admin <- qa_admin()
f <- demo_study(admin, n = 2L, item_count = 2L)
late <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-qa-late-", uuid::UUIDgenerate())))
invisible(add_panelist(admin, f$manager, f$study_id, late$principal_id, "public_contributors", "late-panelist"))
host <- qa_host("management", port, function(repo, data) delphyrApp::run_app(repo, delphyr::demo_actor(repo, data$principal)), list(principal = f$manager$principal_id))
on.exit(if (host$is_alive()) host$kill(), add = TRUE)
round_state <- function(id) DBI::dbGetQuery(admin$con, "SELECT state FROM research.rounds WHERE id=$1", params = list(id))$state
enrolled <- function(id) qa_count(admin, "SELECT count(*) FROM research.enrollments WHERE round_id=$1", id)
m <- qa_session()
qa_open(m, sprintf("http://127.0.0.1:%d", port))
m$wait_for(sprintf("document.getElementById('study') !== null && document.getElementById('study').selectize !== undefined && Object.keys(document.getElementById('study').selectize.options).includes('%s')", f$study_id))
m$select("study", f$study_id)
m$wait_for(sprintf("document.getElementById('management-round') !== null && document.getElementById('management-round').value === '%s'", f$round$id))
transition <- function(target, reason, confirm = TRUE) {
  m$select("management-target", target)
  m$type("management-reason", reason)
  Sys.sleep(.5)
  if (confirm && !isTRUE(m$js("document.getElementById('management-confirm').checked"))) m$click("management-confirm")
  Sys.sleep(.2)
  m$click("management-transition")
}

# 1. Review of the candidate; approval needs the displayed instrument.
transition("review", "Instrument handed to review")
m$wait_text("management-status", "State change confirmed.")
stopifnot(identical(round_state(f$round$id), "review"))
transition("approved", "Exact instrument approved")
m$wait_text("management-status", "Display and review this round")
stopifnot(identical(round_state(f$round$id), "review"))
m$click("management-review")
m$wait_text("management-review_panel", "Instrument of round 1")
m$wait_text("management-review_items", "Synthetic example item I001")
m$wait_text("management-review_readiness", "not yet enrolled")
shown <- m$text("management-review_panel")
stopifnot(
  grepl("Synthetic example item I001", shown, fixed = TRUE), grepl("Synthetisches Beispielitem I002", shown, fixed = TRUE),
  grepl("Exemple synth", shown, fixed = TRUE), grepl("Synthetic demonstration only.", shown, fixed = TRUE),
  grepl("Eligible panel members are not yet enrolled in this round.", shown, fixed = TRUE),
  grepl("A required group has fewer enrolled members than the minimum valid n", shown, fixed = TRUE),
  # The checksum sits in the collapsed technical details.
  isTRUE(m$js(sprintf("document.getElementById('management-review_panel').textContent.includes('%s')", f$round$hash))),
  !grepl("Blocking", shown, fixed = TRUE), enrolled(f$round$id) == 2L
)
# 2. The late panel member is enrolled explicitly.
m$click("management-enroll")
m$wait_text("management-status", "Panel members enrolled: 1")
m$wait_for("!document.getElementById('management-review_panel').innerText.includes('not yet enrolled')")
stopifnot(enrolled(f$round$id) == 3L)
transition("approved", "Exact instrument approved")
m$wait_for(sprintf("document.getElementById('management-rounds').innerText.includes('Approved')"))
stopifnot(identical(round_state(f$round$id), "approved"))
transition("open", "Recruitment complete; open for rating")
m$wait_for("document.getElementById('management-rounds').innerText.includes('Open')")
stopifnot(identical(round_state(f$round$id), "open"))
events <- DBI::dbGetQuery(admin$con, "SELECT target_state,content_hash,reason FROM research.round_events WHERE round_id=$1 ORDER BY occurred_at", params = list(f$round$id))
stopifnot(identical(events$target_state, c("review", "approved", "open")), all(events$content_hash == f$round$hash), identical(events$reason[2], "Exact instrument approved"))
# An opened round cannot be withdrawn.
transition("cancelled", "Too late to withdraw")
m$wait_text("management-status", "This transition is not possible")
stopifnot(identical(round_state(f$round$id), "open"))

# 3. A second study without participants: opening is blocked with findings.
empty <- create_study(admin, f$manager, local({
  p <- demo_protocol()
  p$study$code <- paste0("QA-EMPTY-", substr(uuid::UUIDgenerate(), 1, 8))
  p$study$title <- "Synthetic study without panel"
  p$study$languages <- c("en", "fr", "de")
  p
}), "create")
consent <- publish_consent(admin, f$manager, empty$id, "Synthetic demonstration only.", "en", "consent")$id
candidate <- prepare_round(admin, f$manager, empty$id, f$items, consent, format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), "round")
invisible(m$b$Page$reload())
m$wait_for(sprintf("document.getElementById('study') !== null && document.getElementById('study').selectize !== undefined && Object.keys(document.getElementById('study').selectize.options).includes('%s')", empty$id))
m$select("study", empty$id)
m$wait_for(sprintf("document.getElementById('management-round') !== null && document.getElementById('management-round').value === '%s'", candidate$id))
transition("review", "Instrument handed to review")
m$wait_text("management-status", "State change confirmed.")
m$click("management-review")
m$wait_text("management-review_panel", "No eligible panel member is enrolled.")
stopifnot(grepl("Blocking", m$text("management-review_panel"), fixed = TRUE))
transition("approved", "Content approved before recruitment")
m$wait_for("document.getElementById('management-rounds').innerText.includes('Approved')")
transition("open", "Attempt to open without participants")
m$wait_text("management-status", "The round is not ready yet.")
m$wait_text("management-review_panel", "No eligible panel member is enrolled.")
stopifnot(identical(round_state(candidate$id), "approved"))
# 4. The candidate is withdrawn; its number becomes free and history stays.
transition("cancelled", "Recruitment postponed; candidate withdrawn")
m$wait_for("document.getElementById('management-rounds').innerText.includes('Withdrawn (never opened)')")
stopifnot(identical(round_state(candidate$id), "cancelled"))
replacement <- prepare_round(admin, f$manager, empty$id, f$items, consent, format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), "round-again")
stopifnot(
  identical(DBI::dbGetQuery(admin$con, "SELECT number FROM research.rounds WHERE id=$1", params = list(replacement$id))$number, 1L),
  qa_count(admin, "SELECT count(*) FROM research.round_events WHERE round_id=$1", candidate$id) == 3L
)
stopifnot(identical(m$output_errors(), 0L))
for (mobile in c(TRUE, FALSE)) {
  m$viewport(mobile)
  Sys.sleep(.3)
  stopifnot(m$no_overflow())
}
m$close()
DBI::dbDisconnect(admin$con)
print(list(
  approval_requires_displayed_instrument = TRUE, trilingual_instrument_and_consent_shown = TRUE, late_member_enrolled_explicitly = TRUE,
  transitions_recorded_with_reason_and_hash = TRUE, opened_round_cannot_be_withdrawn = TRUE,
  opening_blocked_with_findings = TRUE, withdrawn_candidate_keeps_history_and_frees_number = TRUE, mobile_overflow = FALSE
))
