# A complete two-round study conducted through the interface, in Chromium
# against PostgreSQL under the restricted runtime role:
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-study-journey-postgres.R
#
# One application host resolves a separate identity and database connection
# for every browser session. The script stands in for the authentication
# gateway by sending the identity headers a qualified gateway would set; it
# qualifies the workflow and session isolation, not an OIDC deployment. The
# operator steps are provisioning the study lead's account and running the
# worker; everything else happens in the browser. The database is read only
# to verify results.
source("packages/delphyrApp/inst/qa/browser-helpers.R")
port <- 3884L
admin <- qa_admin()
issuer <- "https://qa-gateway.example.invalid/realms/journey"
secret <- paste(format(openssl::rand_bytes(32L)), collapse = "")
tag <- substr(uuid::UUIDgenerate(), 1, 8)
code <- paste0("JOURNEY-", tag)
subjects <- list(lead = paste0("lead-", tag), panel = paste0("panel-", 1:4, "-", tag), stranger = paste0("stranger-", tag))
files <- file.path(qa_root, ".checks", paste0("journey-", tag))
dir.create(files, mode = "0700")

# Operator: the study lead's account may create studies.
invisible(DBI::dbExecute(admin$con, "INSERT INTO identity.principals(id,issuer,subject,can_create) VALUES($1,$2,$3,true)", params = list(uuid::UUIDgenerate(), issuer, subjects$lead)))
protocol <- demo_protocol()
protocol$study$code <- code
protocol$study$title <- paste("Synthetic journey study", tag)
protocol$study$languages <- c("en", "de")
protocol$analysis$consensus$min_valid_n <- 2
protocol$feedback$minimum_display_cell_n <- 3
writeLines(jsonlite::toJSON(protocol, auto_unbox = TRUE, null = "null", digits = NA), file.path(files, "protocol.json"))
writeLines(c(
  "external_ref,email,display_name,locale,stakeholder_group",
  sprintf("J-%d,journey%d-%s@example.invalid,Synthetic Member %d,en,%s", 1:4, 1:4, tag, 1:4, rep(c("professionals", "public_contributors"), each = 2))
), file.path(files, "panel.csv"))
items <- expand.grid(item_code = c("I001", "I002"), locale = c("en", "de"), stringsAsFactors = FALSE)
items$item_version <- 1L
items$text <- paste(c(en = "Synthetic journey item", de = "Synthetisches Reiseitem")[items$locale], items$item_code)
items$dimension_code <- "relevance"
items$scale_code <- "relevance_9"
items$source_ref <- "JOURNEY-SRC-1"
items$required <- TRUE
items$display_order <- match(items$item_code, c("I001", "I002"))
utils::write.csv(items, file.path(files, "items.csv"), row.names = FALSE)

host <- qa_host("journey", port, function(repo, data, connect) {
  DBI::dbDisconnect(repo$con)
  config <- delphyr::new_authentication_config(data$issuer, data$secret, "127.0.0.1")
  delphyrApp::run_app(repo_factory = connect, actor_factory = function(session, repo) delphyr::authenticated_actor(repo, session$request, config))
}, list(issuer = issuer, secret = secret))
on.exit(if (host$is_alive()) host$kill(), add = TRUE)
worker <- qa_connection(Sys.getenv("DELPHYR_DB_RUNTIME", "delphyr_runtime"))
work <- function(study) while (!identical(worker_step(worker, study_id = study), FALSE)) NULL
url <- sprintf("http://127.0.0.1:%d", port)
as_user <- function(subject, gateway = secret, fragment = "") {
  s <- qa_session()
  s$identity(list(`X-Forwarded-User` = subject, `X-Delphyr-Gateway` = gateway))
  qa_open(s, paste0(url, fragment))
  s
}
settle <- function(seconds = .45) Sys.sleep(seconds)
value <- function(sql, ...) {
  params <- list(...)
  DBI::dbGetQuery(admin$con, sql, params = params)
}

# 0. Identity boundary: no headers, a wrong gateway secret and an unknown
#    account receive no session.
for (s in list(local({
  x <- qa_session()
  qa_open(x, url)
  x
}), as_user(subjects$lead, gateway = paste(rep("0", 64), collapse = "")), as_user(subjects$stranger))) {
  s$wait_for("document.getElementById('unregistered').hidden === false")
  s$close()
}

# 1. The lead creates the study from an uploaded protocol.
lead <- as_user(subjects$lead)
lead$wait_text("status", "No accessible study")
lead$wait_for("document.getElementById('study_create-validate') !== null")
lead$expand("study_create-validate")
lead$upload("study_create-file", file.path(files, "protocol.json"))
lead$click("study_create-validate")
lead$wait_text("study_create-status", "Protocol is valid.")
lead$wait_text("study_create-summary", code)
stopifnot(nrow(value("SELECT id FROM research.studies WHERE code=$1", code)) == 0L)
lead$wait_for("document.getElementById('study_create-create') !== null")
lead$click("study_create-confirm")
settle()
lead$click("study_create-create")
lead$wait_text("study_create-status", "Study created:")
study <- value("SELECT id FROM research.studies WHERE code=$1", code)$id
stopifnot(length(study) == 1L)
lead$wait_for(sprintf("document.getElementById('study').value === '%s'", study))
lead$wait_for("document.querySelector('nav.del-nav') !== null && document.querySelector('nav.del-nav').innerText.includes('Setup')")

# 2. Study information.
lead$wait_for("document.getElementById('study_setup-consent_publish') !== null")
lead$expand("study_setup-consent_publish")
lead$type("study_setup-consent_text", "Synthetic journey study. Participation is voluntary; do not enter real data.")
settle()
lead$click("study_setup-consent_confirm")
settle()
lead$click("study_setup-consent_publish")
lead$wait_text("study_setup-status", "Study information published.")
lead$wait_text("study_setup-consents", "Participation is voluntary")

# 3. Panel contacts and invitations bound to stable accounts.
lead$wait_for("document.getElementById('panel_import-preview') !== null")
lead$upload("panel_import-file", file.path(files, "panel.csv"))
lead$click("panel_import-preview")
lead$wait_text("panel_import-status", "Preview passed validation.")
lead$type("panel_import-reason", "Four synthetic contacts reviewed.")
settle()
lead$click("panel_import-confirm")
settle()
lead$click("panel_import-approve")
lead$wait_text("panel_import-receipt", "4 contacts imported")
lead$wait_for("document.getElementById('invitations-refresh') !== null")
lead$click("invitations-refresh")
lead$wait_text("invitations-drafts", "J-4")
drafts <- value("SELECT d.id,c.external_ref FROM identity.panel_invitation_drafts d JOIN identity.panel_contacts c ON c.id=d.contact_id WHERE d.study_id=$1 ORDER BY c.external_ref", study)
codes <- character()
for (i in 1:4) {
  lead$wait_for(sprintf("document.getElementById('invitations-draft').selectize !== undefined && Object.keys(document.getElementById('invitations-draft').selectize.options).includes('%s')", drafts$id[i]))
  lead$select("invitations-draft", drafts$id[i])
  lead$type("invitations-issuer", issuer)
  lead$type("invitations-subject", subjects$panel[i])
  lead$type("invitations-reason", paste("Stable account verified for", drafts$external_ref[i]))
  settle()
  if (!isTRUE(lead$js("document.getElementById('invitations-confirm').checked"))) lead$click("invitations-confirm")
  settle()
  lead$click("invitations-issue")
  lead$wait_for("document.getElementById('invitations-code') !== null")
  codes[i] <- lead$value("invitations-code")
  lead$click("invitations-hide")
  lead$wait_for("document.getElementById('invitations-code') === null")
}
stopifnot(length(unique(codes)) == 4L, all(grepl("^dlp1[.]", codes)))

# 4. Round one is prepared for review while recruitment is still under way.
deadline <- format(Sys.time() + 2 * 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
prepare_round_ui <- function() {
  lead$wait_for("document.getElementById('management-operations-prepare') !== null")
  lead$expand("management-operations-prepare")
  lead$upload("management-operations-csv", file.path(files, "items.csv"))
  lead$click("management-operations-validate")
  lead$wait_text("management-operations-status", "Import validated.")
  lead$wait_for("document.getElementById('management-operations-consent') !== null && document.getElementById('management-operations-consent').value !== ''")
  lead$type("management-operations-deadline", deadline)
  settle()
  lead$click("management-operations-prepare")
  lead$wait_text("management-operations-status", "Round draft created.")
}
prepare_round_ui()
round <- function(number) value("SELECT id,state,instrument_hash FROM research.rounds WHERE study_id=$1 AND number=$2 AND state<>'cancelled'", study, number)
stopifnot(identical(round(1)$state, "draft"))

# 5. Every invited person accepts with the own verified account.
panel <- lapply(1:4, function(i) {
  s <- as_user(subjects$panel[i], fragment = paste0("/#invitation=", codes[i]))
  s$wait_for("document.getElementById('invitation_accept-code') !== null && document.getElementById('invitation_accept-code').value.length > 0")
  s$wait_for("location.hash === ''")
  s$click("invitation_accept-check")
  s$wait_for("document.getElementById('invitation_accept-accept') !== null")
  stopifnot(grepl(protocol$study$title, s$text("invitation_accept-preview"), fixed = TRUE))
  s$click("invitation_accept-confirm")
  settle()
  s$click("invitation_accept-accept")
  s$wait_text("invitation_accept-preview", "Invitation accepted.")
  s$wait_for(sprintf("document.getElementById('study').value === '%s'", study))
  s
})
# A code is bound to its account: the second member cannot use the first code.
panel[[2]]$type("invitation_accept-code", codes[1])
settle()
panel[[2]]$click("invitation_accept-check")
panel[[2]]$wait_text("invitation_accept-status", "not available for your account")
stopifnot(value("SELECT count(*)::int AS n FROM research.panelists WHERE study_id=$1", study)$n == 4L)

# 6. Readiness, explicit enrollment, exact review, approval and opening.
select_round <- function(id) {
  lead$wait_for(sprintf("document.getElementById('management-round').selectize !== undefined && Object.keys(document.getElementById('management-round').selectize.options).includes('%s')", id))
  lead$select("management-round", id)
  settle()
}
transition <- function(target, reason) {
  lead$select("management-target", target)
  lead$type("management-reason", reason)
  settle()
  if (!isTRUE(lead$js("document.getElementById('management-confirm').checked"))) lead$click("management-confirm")
  settle(.3)
  lead$click("management-transition")
}
# A person acts on what the page shows: the next step waits until the round
# list displays the new state, then the database is checked independently.
advance <- function(id, target, reason) {
  transition(target, reason)
  label <- c(review = "In review", approved = "Approved", open = "Open", closed = "Closed", finalized = "Finalized")[[target]]
  shown <- tryCatch(lead$wait_for(sprintf("(function(){var x=document.getElementById('management-round');return !!x && !!x.selectize && !!x.selectize.options['%s'] && x.selectize.options['%s'].label.endsWith('%s');})()", id, id, label)), error = function(e) FALSE)
  if (identical(shown, FALSE)) stop("Round did not reach state ", target, ": ", lead$text("management-status"))
  stopifnot(identical(value("SELECT state FROM research.rounds WHERE id=$1", id)$state, target))
  settle()
}
open_round <- function(number) {
  id <- round(number)$id
  select_round(id)
  lead$click("management-review")
  lead$wait_text("management-review_panel", paste("Instrument of round", number))
  lead$wait_text("management-review_items", "Synthetisches Reiseitem I002")
  if (number == 1L) {
    lead$wait_text("management-review_readiness", "No eligible panel member is enrolled.")
    advance(id, "review", "Instrument handed to review")
    lead$click("management-review")
    lead$wait_text("management-review_panel", "Instrument of round 1")
    advance(id, "approved", "Exact instrument approved")
    transition("open", "Attempt before enrollment")
    lead$wait_text("management-status", "The round is not ready yet.")
    stopifnot(identical(round(1)$state, "approved"))
    lead$click("management-enroll")
    lead$wait_text("management-status", "Panel members enrolled: 4")
    advance(id, "open", "Recruitment complete; round opened")
  } else {
    lead$wait_for("!document.getElementById('management-review_panel').innerText.includes('Blocking')")
    advance(id, "review", "Instrument handed to review")
    lead$click("management-review")
    lead$wait_text("management-review_panel", paste("Instrument of round", number))
    advance(id, "approved", "Exact instrument approved")
    advance(id, "open", "Feedback assigned; round opened")
  }
}
open_round(1L)

# 7. The panel consents, rates with automatic saving and submits.
enrollment <- function(subject, number) value("SELECT e.id FROM research.enrollments e JOIN research.rounds r ON r.id=e.round_id JOIN identity.panelist_links l ON l.study_id=e.study_id AND l.panelist_id=e.panelist_id JOIN identity.memberships m ON m.id=l.membership_id JOIN identity.principals p ON p.id=m.principal_id WHERE e.study_id=$1 AND r.number=$2 AND r.state<>'cancelled' AND p.subject=$3", study, number, subject)$id
saved <- function(s, item) s$wait_for(sprintf("document.querySelector('#panel-slot_%d-save_status .del-status--saved') !== null && document.getElementById('panel-slot_%d-status').innerText.startsWith('Saved:')", item, item))
answer_round <- function(i, number, answers, submit = TRUE, prior = NULL) {
  s <- panel[[i]]
  invisible(s$b$Page$reload())
  id <- enrollment(subjects$panel[i], number)
  s$wait_for(sprintf("document.getElementById('panel-enrollment') !== null && document.getElementById('panel-enrollment').selectize !== undefined && Object.keys(document.getElementById('panel-enrollment').selectize.options).includes('%s')", id))
  s$select("panel-enrollment", id)
  settle()
  s$click("panel-load")
  s$wait_for("document.getElementById('panel-item_1_2-value') !== null")
  if (number == 1L) {
    s$click("panel-consent_check")
    settle(.3)
    s$click("panel-consent")
    s$wait_text("panel-status", "Consent saved.")
  }
  if (!is.null(prior)) for (item in seq_along(prior)) s$wait_text(sprintf("panel-slot_%d-prior", item), paste("Your previous response:", prior[item]))
  for (item in seq_along(answers)) {
    if (identical(answers[[item]], "unable")) s$select(sprintf("panel-item_1_%d-kind", item), "unable_to_judge") else s$select(sprintf("panel-item_1_%d-value", item), as.character(answers[[item]]))
    saved(s, item)
  }
  if (submit) {
    s$click("panel-confirm")
    settle(.3)
    s$click("panel-submit")
    s$wait_text("panel-receipt", "Submission confirmed:")
  }
}
answer_round(1, 1L, list(8, 7))
answer_round(2, 1L, list(7, 3))
answer_round(3, 1L, list(9, 8))
answer_round(4, 1L, list("unable", 9))
stopifnot(value("SELECT count(*)::int AS n FROM research.submissions WHERE study_id=$1", study)$n == 4L)

# 8. Close, freeze, analyse, decide, review and release feedback.
conclude_round <- function(number, disposition, reason) {
  id <- round(number)$id
  select_round(id)
  advance(id, "closed", "All expected submissions received")
  lead$wait_for("document.getElementById('management-operations-freeze') !== null")
  lead$click("management-operations-freeze")
  lead$wait_text("management-operations-status", "Snapshot confirmed.")
  lead$click("management-operations-analyse")
  lead$wait_text("management-operations-status", "Analysis queued.")
  work(study)
  lead$click("management-operations-poll")
  lead$wait_text("management-operations-status", "Succeeded")
  lead$wait_text("management-operations-analysis", "I002")
  lead$expand("management-operations-decide")
  for (item in c("I001", "I002")) {
    lead$wait_for(sprintf("document.getElementById('management-operations-decision_code') !== null && document.getElementById('management-operations-decision_code').selectize !== undefined && Object.keys(document.getElementById('management-operations-decision_code').selectize.options).includes('%s')", item))
    lead$select("management-operations-decision_code", item)
    lead$select("management-operations-disposition", disposition)
    lead$type("management-operations-decision_reason", paste(reason, item))
    settle()
    if (!isTRUE(lead$js("document.getElementById('management-operations-decision_confirm').checked"))) lead$click("management-operations-decision_confirm")
    settle(.3)
    lead$click("management-operations-decide")
    lead$wait_text("management-operations-status", paste("Item decision saved:", item))
  }
  lead$wait_text("management-operations-decisions", paste(reason, "I002"))
}
conclude_round(1L, "rerate", "Rated again after feedback:")
lead$expand("management-operations-draft")
lead$click("management-operations-draft")
lead$wait_text("management-operations-status", "Feedback created for review.")
lead$wait_text("management-operations-preview", "hash")
lead$click("management-operations-release")
settle()
stopifnot(identical(round(1)$state, "analysed"))
lead$click("management-operations-reviewed")
settle(.3)
lead$click("management-operations-release")
lead$wait_text("management-operations-status", "Feedback released.")
stopifnot(identical(round(1)$state, "released"))

# 9. Round two: same instrument, assigned feedback, own previous answers.
prepare_round_ui()
select_round(round(2)$id)
lead$click("management-operations-assign")
lead$wait_text("management-operations-status", "Feedback assigned.")
open_round(2L)
answer_round(1, 2L, list(8, 8), prior = c("answered 8", "answered 7"))
answer_round(2, 2L, list(8, 7), prior = c("answered 7", "answered 3"))
answer_round(3, 2L, list(9, 8), prior = c("answered 9", "answered 8"))
# The fourth member rates but does not submit; such answers are not research data.
answer_round(4, 2L, list(5, 5), submit = FALSE, prior = c("unable_to_judge", "answered 9"))
feedback_text <- panel[[1]]$text("panel-slot_1-feedback")
stopifnot(grepl("I001", feedback_text, fixed = TRUE), !grepl("public_contributors", feedback_text, fixed = TRUE))

# 10. Final round, decisions, finalization and completion.
conclude_round(2L, "finalize", "Final decision documented:")
advance(round(2)$id, "finalized", "Second round is the final round")
lead$type("management-reason", "Two rounds completed; remaining dissent is documented.")
settle()
if (!isTRUE(lead$js("document.getElementById('management-confirm').checked"))) lead$click("management-confirm")
settle(.3)
lead$click("management-complete")
lead$wait_text("management-status", "Study completed.")
stopifnot(identical(value("SELECT state FROM research.studies WHERE id=$1", study)$state, "completed"))

# 11. Documentation, research export with offline reproduction, and history.
lead$type("documentation-authors_responsibilities", "Synthetic lead (journey qualification).")
lead$type("documentation-reason", "Statements for the final report")
settle()
lead$click("documentation-confirm")
settle(.3)
lead$click("documentation-save")
lead$wait_text("documentation-status", "Documentation version saved: 1")
lead$wait_for("document.getElementById('exports-profile') !== null && document.getElementById('exports-profile').selectize !== undefined")
lead$select("exports-profile", "research_pseudonymized")
settle()
lead$click("exports-confirm")
settle(.3)
lead$click("exports-request")
lead$wait_text("exports-status", "Export queued.")
work(study)
lead$click("exports-poll")
lead$wait_text("exports-status", "Succeeded")
export <- qa_unzip(lead$download("exports-download"))
reproduced <- reproduce_study_export(export)
responses <- utils::read.csv(file.path(export, "responses.csv"), stringsAsFactors = FALSE)
text <- paste(unlist(lapply(list.files(export, full.names = TRUE), function(p) readLines(p, warn = FALSE))), collapse = "\n")
first <- reproduced$analyses[["1"]]$decisions
stopifnot(
  identical(names(reproduced$analyses), c("1", "2")),
  # One group has a single valid rating for I001: the group rule reports
  # insufficient data although the overall proportion is high.
  identical(first$classification[first$item_code == "I001"], "insufficient_data"),
  identical(first$classification[first$item_code == "I002"], "no_consensus"),
  identical(reproduced$comparisons$n_paired, c(3L, 3L)), all(reproduced$comparisons$status == "descriptive"),
  nrow(responses[responses$round_number == 1, ]) == 8L, nrow(responses[responses$round_number == 2, ]) == 6L,
  sum(responses$answer_status == "unable_to_judge") == 1L,
  !grepl("example.invalid", text, fixed = TRUE), !any(vapply(unlist(subjects), function(x) grepl(x, text, fixed = TRUE), logical(1))),
  grepl("Synthetic lead (journey qualification).", text, fixed = TRUE)
)
lead$click("audit-load")
lead$wait_text("audit-events", "Study completed")

# 12. Independent verification of what the interface confirmed.
actions <- value("SELECT action,count(*)::int AS n FROM ops.audit WHERE study_id=$1 GROUP BY action", study)
count <- function(action) {
  n <- actions$n[actions$action == action]
  if (length(n)) n else 0L
}
revisions <- value("SELECT r.number,count(*)::int AS n FROM research.response_revisions v JOIN research.rounds r ON r.id=v.round_id WHERE v.study_id=$1 GROUP BY r.number ORDER BY r.number", study)
stopifnot(
  count("create_study") == 1L, count("publish_consent") == 1L, count("panel_import") == 1L, count("invitation_account") == 4L, count("invitation_issue") == 4L,
  count("invitation_accept") == 4L, count("prepare_round") == 2L, count("enroll_panel") == 1L, count("consent") == 4L, count("submit") == 7L,
  count("save") == sum(revisions$n), identical(revisions$n, c(8L, 8L)), count("freeze") == 2L, count("request_analysis") == 2L, count("decision") == 4L,
  count("feedback_draft") == 1L, count("release_feedback") == 1L, count("assign_feedback") == 1L, count("complete_study") == 1L,
  count("study_documentation") == 1L, count("artifact_download") == 1L,
  identical(value("SELECT state FROM research.rounds WHERE study_id=$1 ORDER BY number", study)$state, c("released", "finalized")),
  value("SELECT count(*)::int AS n FROM identity.consents WHERE study_id=$1 AND decision", study)$n == 4L,
  # Sessions never shared an identity: every enrollment's revisions belong to one account.
  value("SELECT count(DISTINCT a.actor_id)::int AS n FROM ops.audit a WHERE a.study_id=$1 AND a.action='save'", study)$n == 4L
)
logs <- readLines(file.path(qa_root, ".checks", "journey.log"), warn = FALSE)
stopifnot(!any(grepl(secret, logs, fixed = TRUE)), !any(vapply(codes, function(x) any(grepl(sub("^.*[.]", "", x), logs, fixed = TRUE)), logical(1))))
for (s in c(list(lead), panel)) {
  if (!identical(s$output_errors(), 0L)) stop("Output errors: ", s$output_error_ids())
  for (mobile in c(TRUE, FALSE)) {
    s$viewport(mobile)
    Sys.sleep(.3)
    stopifnot(s$no_overflow())
  }
  s$close()
}
DBI::dbDisconnect(worker$con)
DBI::dbDisconnect(admin$con)
print(list(
  study = code, identity_boundary_rejections = 3L, created_from_reviewed_protocol = TRUE, invitations_accepted = 4L,
  opening_blocked_until_enrollment = TRUE, round_1_submissions = 4L, round_2_submissions = 3L,
  own_previous_answers_per_person = TRUE, decisions_recorded = 4L, study_completed = TRUE,
  research_export_reproduced_offline = TRUE, audit_events = sum(actions$n), mobile_overflow = FALSE
))
