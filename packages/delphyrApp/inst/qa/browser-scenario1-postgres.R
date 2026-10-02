# Scenario 1 of the specification at its stated size: a complete modified
# Delphi with 30 synthetic members in two groups, 12 items and two rounds,
# in Chromium against PostgreSQL under the restricted runtime role:
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-scenario1-postgres.R
#
# Every staff step happens in the interface: protocol, study information,
# contacts, invitations, round preparation and approval, a message recorded in
# the local sink, closing, freezing, analysis, editorial review of comments,
# feedback, item decisions, the second round, completion and export. Every
# member accepts the invitation with the own account, consents, answers and
# submits in a browser session of their own. The operator steps are the first
# account and the worker. The database is read only to verify.
source("packages/delphyrApp/inst/qa/browser-helpers.R")
port <- 3898L
admin <- qa_admin()
issuer <- "https://qa-gateway.example.invalid/realms/scenario1"
secret <- paste(format(openssl::rand_bytes(32L)), collapse = "")
tag <- substr(uuid::UUIDgenerate(), 1, 8)
code <- paste0("SCENARIO1-", tag)
n <- 30L
groups <- rep(c("professionals", "public_contributors"), each = n / 2L)
subjects <- list(lead = paste0("lead-", tag), reviewer = paste0("reviewer-", tag), panel = sprintf("member-%02d-%s", seq_len(n), tag))
files <- file.path(qa_root, ".checks", paste0("scenario1-", tag))
dir.create(files, mode = "0700")
invisible(DBI::dbExecute(admin$con, "INSERT INTO identity.principals(id,issuer,subject,can_create) VALUES($1,$2,$3,true)", params = list(uuid::UUIDgenerate(), issuer, subjects$lead)))

# The example rule of the protocol: agreement is a rating of 7 to 9, at least
# 70 percent agreement and less than 15 percent disagreement, at least ten
# valid ratings, in every stakeholder group.
protocol <- demo_protocol()
protocol$study$code <- code
protocol$study$title <- paste("Synthetic scenario study", tag)
protocol$study$languages <- "en"
protocol$instrument$dimensions <- list(list(code = "relevance", scale = "relevance_9"), list(code = "comment", scale = "comment_text"))
protocol$instrument$scales$comment_text <- list(type = "free_text", values = list(), missing_options = c("unable_to_judge"))
writeLines(jsonlite::toJSON(protocol, auto_unbox = TRUE, null = "null", digits = NA), file.path(files, "protocol.json"))
writeLines(c("external_ref,email,display_name,locale,stakeholder_group", sprintf("S-%02d,scenario%02d-%s@example.invalid,Synthetic Member %02d,en,%s", seq_len(n), seq_len(n), tag, seq_len(n), groups)), file.path(files, "panel.csv"))
codes <- sprintf("I%03d", 1:12)
items <- rbind(
  data.frame(item_code = codes, item_version = 1L, locale = "en", text = paste("Synthetic scenario statement", codes), dimension_code = "relevance", scale_code = "relevance_9", source_ref = "SCENARIO-SRC", required = TRUE, display_order = 1:12),
  data.frame(item_code = codes, item_version = 1L, locale = "en", text = paste("Synthetic scenario statement", codes), dimension_code = "comment", scale_code = "comment_text", source_ref = "SCENARIO-SRC", required = FALSE, display_order = 1:12)
)
utils::write.csv(items, file.path(files, "items.csv"), row.names = FALSE)

# Planned ratings. The classification each item must receive follows from
# them by hand: see `expected` below.
rating <- function(member, item, round) {
  a <- member <= 15L
  switch(item,
    I001 = 8L, I002 = 2L, I003 = if (a) 8L else 5L,
    I004 = if (a) (if (member <= 13L) 8L else 2L) else (if (member <= 26L) 7L else 5L),
    I005 = if (a) (if (member <= (if (round == 1L) 10L else 11L)) 8L else 5L) else 8L,
    I006 = 9L, 6L
  )
}
comments <- c(`1` = paste0("COMMENT-ONE-", tag, " the term needs a definition (named colleague)"), `2` = paste0("COMMENT-TWO-", tag, " define the term"), `16` = paste0("COMMENT-THREE-", tag, " unclear wording"))
expected <- list(
  `1` = c(I001 = "consensus_in", I002 = "consensus_out", I003 = "no_consensus", I004 = "consensus_in", I005 = "no_consensus", I006 = "consensus_in", I007 = "no_consensus", I008 = "no_consensus", I009 = "no_consensus", I010 = "no_consensus", I011 = "no_consensus", I012 = "no_consensus"),
  `2` = c(I001 = "consensus_in", I002 = "consensus_out", I003 = "no_consensus", I004 = "consensus_in", I005 = "consensus_in", I006 = "consensus_in", I007 = "no_consensus", I008 = "no_consensus", I009 = "no_consensus", I010 = "no_consensus", I011 = "no_consensus", I012 = "no_consensus")
)

host <- qa_host(paste0("scenario1-", tag), port, function(repo, data, connect) {
  DBI::dbDisconnect(repo$con)
  config <- delphyr::new_authentication_config(data$issuer, data$secret, "127.0.0.1")
  delphyrApp::run_app(repo_factory = connect, actor_factory = function(session, repo) delphyr::authenticated_actor(repo, session$request, config))
}, list(issuer = issuer, secret = secret))
on.exit(if (host$is_alive()) host$kill(), add = TRUE)
worker <- qa_connection(Sys.getenv("DELPHYR_DB_RUNTIME", "delphyr_runtime"))
work <- function(study) {
  repeat {
    job <- worker_step(worker, study_id = study)
    message <- process_campaign_sink(worker, study)
    if (identical(job, FALSE) && identical(message, FALSE)) break
  }
}
url <- sprintf("http://127.0.0.1:%d", port)
as_user <- function(subject, fragment = "", script = NULL) {
  s <- qa_session()
  s$identity(list(`X-Forwarded-User` = subject, `X-Delphyr-Gateway` = secret))
  if (!is.null(script)) {
    s$b$Page$enable()
    invisible(s$b$Page$addScriptToEvaluateOnNewDocument(source = script))
  }
  qa_open(s, paste0(url, fragment))
  s
}
settle <- function(seconds = .45) Sys.sleep(seconds)
# Arguments are evaluated before the statement is sent: one of them may run a
# query of its own.
value <- function(sql, ...) {
  params <- list(...)
  DBI::dbGetQuery(admin$con, sql, params = params)
}
confirm <- function(s, id) if (!isTRUE(s$js(sprintf("document.getElementById('%s').checked", id)))) s$click(id)
listed <- function(s, id, option) s$wait_for(sprintf("(function(){var x=document.getElementById('%s');return !!x && (x.selectize ? Object.keys(x.selectize.options) : Array.from(x.options).map(function(o){return o.value;})).includes('%s');})()", id, option))

# 1. The lead creates the study from the protocol; its rules are displayed.
lead <- as_user(subjects$lead)
lead$wait_text("status", "No accessible study")
lead$wait_for("document.getElementById('study_create-validate') !== null")
lead$expand("study_create-validate")
lead$upload("study_create-file", file.path(files, "protocol.json"))
lead$click("study_create-validate")
lead$wait_text("study_create-status", "Protocol is valid.")
summary <- lead$text("study_create-summary")
stopifnot(grepl(code, summary, fixed = TRUE))
lead$click("study_create-confirm")
settle()
lead$click("study_create-create")
lead$wait_text("study_create-status", "Study created:")
study <- value("SELECT id FROM research.studies WHERE code=$1", code)$id
lead$wait_for(sprintf("document.getElementById('study').value === '%s'", study))

# 2. Study information, a second manager for independent review, contacts.
lead$wait_for("document.getElementById('study_setup-consent_publish') !== null")
lead$expand("study_setup-consent_publish")
lead$type("study_setup-consent_text", "Synthetic scenario study. Participation is voluntary; do not enter real data.")
settle()
lead$click("study_setup-consent_confirm")
settle()
lead$click("study_setup-consent_publish")
lead$wait_text("study_setup-status", "Study information published.")
grant <- function(right) {
  account <- value("SELECT id FROM identity.principals WHERE issuer=$1 AND subject=$2", issuer, subjects$reviewer)$id
  lead$expand("study_setup-staff_apply")
  if (length(account)) {
    listed(lead, "study_setup-staff_account", account)
    lead$select("study_setup-staff_account", account)
  } else {
    lead$select("study_setup-staff_account", "new")
    lead$type("study_setup-staff_issuer", issuer)
    lead$type("study_setup-staff_subject", subjects$reviewer)
  }
  lead$select("study_setup-staff_capability", right)
  lead$select("study_setup-staff_action", "grant")
  lead$type("study_setup-staff_reason", "Second manager for independent review")
  settle()
  confirm(lead, "study_setup-staff_confirm")
  settle(.3)
  lead$mark("study_setup-staff_account")
  lead$click("study_setup-staff_apply")
  lead$replaced("study_setup-staff_account")
  lead$wait_text("study_setup-status", "Change of rights confirmed.")
}
grant("manage")
lead$wait_for("document.getElementById('panel_import-preview') !== null")
lead$upload("panel_import-file", file.path(files, "panel.csv"))
lead$click("panel_import-preview")
lead$wait_text("panel_import-status", "Preview passed validation.")
lead$type("panel_import-reason", "Thirty synthetic contacts reviewed.")
settle()
lead$click("panel_import-confirm")
settle()
lead$click("panel_import-approve")
lead$wait_text("panel_import-receipt", "30 contacts imported")

# 3. An invitation for every contact, bound to that person's account.
lead$wait_for("document.getElementById('invitations-refresh') !== null")
lead$click("invitations-refresh")
lead$wait_text("invitations-drafts", "S-30")
drafts <- value("SELECT d.id,c.external_ref FROM identity.panel_invitation_drafts d JOIN identity.panel_contacts c ON c.id=d.contact_id WHERE d.study_id=$1 ORDER BY c.external_ref", study)
invitations <- character(n)
for (i in seq_len(n)) {
  listed(lead, "invitations-draft", drafts$id[i])
  lead$select("invitations-draft", drafts$id[i])
  lead$type("invitations-issuer", issuer)
  lead$type("invitations-subject", subjects$panel[i])
  lead$type("invitations-reason", paste("Stable account verified for", drafts$external_ref[i]))
  settle()
  confirm(lead, "invitations-confirm")
  settle(.3)
  lead$click("invitations-issue")
  lead$wait_for("document.getElementById('invitations-code') !== null")
  invitations[i] <- lead$value("invitations-code")
  lead$click("invitations-hide")
  lead$wait_for("document.getElementById('invitations-code') === null")
}
stopifnot(length(unique(invitations)) == n)

# 4. The first round is prepared from the item file.
deadline <- format(Sys.time() + 2 * 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
prepare_round_ui <- function() {
  lead$wait_for("document.getElementById('management-operations-prepare') !== null")
  lead$expand("management-operations-prepare")
  lead$upload("management-operations-csv", file.path(files, "items.csv"))
  lead$click("management-operations-validate")
  lead$wait_text("management-operations-status", "Import validated.")
  lead$wait_text("management-operations-items", "I012")
  lead$wait_for("document.getElementById('management-operations-consent') !== null && document.getElementById('management-operations-consent').value !== ''")
  lead$type("management-operations-deadline", deadline)
  settle()
  lead$click("management-operations-prepare")
  lead$wait_text("management-operations-status", "Round draft created.")
}
prepare_round_ui()
round <- function(number) value("SELECT id,state,instrument_hash FROM research.rounds WHERE study_id=$1 AND number=$2 AND state<>'cancelled'", study, number)

# 5. Every invited person signs in and accepts with a confirmed action.
panel <- vector("list", n)
for (i in seq_len(n)) {
  s <- as_user(subjects$panel[i], fragment = paste0("/#invitation=", invitations[i]))
  s$wait_for("document.getElementById('invitation_accept-code') !== null && document.getElementById('invitation_accept-code').value.length > 0")
  s$click("invitation_accept-check")
  s$wait_for("document.getElementById('invitation_accept-accept') !== null")
  s$click("invitation_accept-confirm")
  settle(.3)
  s$click("invitation_accept-accept")
  s$wait_text("invitation_accept-preview", "Invitation accepted.")
  s$close()
}
stopifnot(value("SELECT count(*)::int AS n FROM research.panelists WHERE study_id=$1", study)$n == n)

# 6. Review, approval, enrollment and opening.
select_round <- function(id) {
  listed(lead, "management-round", id)
  lead$select("management-round", id)
  settle()
}
transition <- function(target, reason) {
  lead$select("management-target", target)
  lead$type("management-reason", reason)
  settle()
  confirm(lead, "management-confirm")
  settle(.3)
  lead$click("management-transition")
}
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
  lead$wait_text("management-review_items", "Synthetic scenario statement I012")
  advance(id, "review", "Instrument handed to review")
  lead$click("management-review")
  lead$wait_text("management-review_panel", paste("Instrument of round", number))
  advance(id, "approved", "Exact instrument approved")
  if (number == 1L) {
    lead$click("management-enroll")
    lead$wait_text("management-status", "Panel members enrolled: 30")
  }
  advance(id, "open", "Round opened for rating")
}
open_round(1L)

# 7. A round-start message for every enrolled member, recorded in the local sink.
enrollments <- function(number) value("SELECT e.id,p.subject FROM research.enrollments e JOIN research.rounds r ON r.id=e.round_id JOIN identity.panelist_links l ON l.study_id=e.study_id AND l.panelist_id=e.panelist_id JOIN identity.memberships m ON m.study_id=l.study_id AND m.id=l.membership_id JOIN identity.principals p ON p.id=m.principal_id WHERE e.study_id=$1 AND r.number=$2 ORDER BY p.subject", study, number)
first <- enrollments(1L)
stopifnot(nrow(first) == n)
listed(lead, "communications-round", round(1)$id)
lead$select("communications-round", round(1)$id)
listed(lead, "communications-enrollments", first$id[1])
invisible(lead$js(sprintf("(function(){document.getElementById('communications-enrollments').selectize.setValue(%s);return true;})()", jsonlite::toJSON(first$id))))
lead$select("communications-kind", "round_start")
lead$type("communications-subject", "The first round is open")
lead$type("communications-message", "The first round of the synthetic scenario study is open. No external delivery.")
settle()
lead$click("communications-prepare")
lead$wait_text("communications-preview", "30 exactly selected recipients")
lead$type("communications-reason", "Exact text and all thirty recipients reviewed")
settle()
confirm(lead, "communications-confirm")
settle(.3)
lead$click("communications-release")
lead$wait_text("communications-status", "Approved. No email will be sent.")
work(study)
stopifnot(value("SELECT count(*)::int AS n FROM ops.message_sink s JOIN ops.message_outbox o ON o.id=s.message_id WHERE o.study_id=$1", study)$n == n)

# 8. Every member consents, answers and submits in a session of their own.
answers_of <- function(member, number, q) {
  out <- list()
  for (row in seq_len(nrow(q))) {
    if (q$dimension_code[row] == "relevance") {
      out[[as.character(row)]] <- if (number == 1L && member == 1L && q$item_code[row] == "I006") "unable_to_judge" else as.character(rating(member, q$item_code[row], number))
    } else if (number == 1L && q$item_code[row] == "I003" && as.character(member) %in% names(comments)) {
      out[[as.character(row)]] <- comments[[as.character(member)]]
    }
  }
  out
}
answer_round <- function(number, members, submit = function(member) TRUE) {
  order <- value("SELECT item_code,dimension_code FROM research.round_items WHERE study_id=$1 AND round_id=$2 ORDER BY display_order,item_code,dimension_code", study, round(number)$id)
  pages <- lapply(members, function(member) as_user(subjects$panel[member], script = qa_participant_script(number, answers_of(member, number, order), think = c(0.2, 0.5), consent = number == 1L, submit = submit(member))))
  for (attempt in 1:1800) {
    done <- vapply(pages, function(s) isTRUE(tryCatch(s$js("!!(window.__participant && window.__participant.done)"), error = function(e) FALSE)), logical(1))
    if (all(done)) break
    Sys.sleep(1)
  }
  results <- lapply(pages, function(s) jsonlite::fromJSON(s$js("JSON.stringify(window.__participant)"), simplifyVector = FALSE))
  problems <- unlist(lapply(results, function(r) unlist(r$errors)))
  if (!all(done) || length(problems)) stop("Round ", number, " was not answered completely: ", paste(utils::head(problems, 5), collapse = "; "))
  stopifnot(all(vapply(pages, function(s) identical(s$output_errors(), 0L), logical(1))))
  list(pages = pages, results = results)
}
one <- answer_round(1L, seq_len(n))
# The second block shows nothing of other members; the first page stays open.
for (s in one$pages[-1]) s$close()
stopifnot(
  value("SELECT count(*)::int AS n FROM research.submissions WHERE study_id=$1", study)$n == n,
  value("SELECT count(*)::int AS n FROM identity.consents WHERE study_id=$1 AND decision", study)$n == n
)

# 9. Close, freeze, analyse.
conclude_round <- function(number) {
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
  lead$wait_text("management-operations-analysis", "I012")
}
decide <- function(disposition, reason) {
  lead$expand("management-operations-decide")
  for (item in codes) {
    listed(lead, "management-operations-decision_code", item)
    lead$select("management-operations-decision_code", item)
    lead$select("management-operations-disposition", disposition)
    lead$type("management-operations-decision_reason", paste(reason, item))
    settle()
    confirm(lead, "management-operations-decision_confirm")
    settle(.3)
    lead$click("management-operations-decide")
    lead$wait_text("management-operations-status", paste("Item decision saved:", item))
  }
}
conclude_round(1L)

# 10. Editorial review of the comments: taken over, summarised by the lead,
#     released by the second manager.
lead$wait_for("document.getElementById('editorial-contribution_import') !== null")
lead$expand("editorial-contribution_import")
lead$wait_text("editorial-contributions", "3")
lead$mark("editorial-source")
lead$click("editorial-contribution_import")
lead$replaced("editorial-source")
lead$wait_text("editorial-status", "Contributions taken over: 3")
sources <- value("SELECT id,original_text FROM research.qualitative_sources WHERE study_id=$1", study)
stopifnot(nrow(sources) == 3L, setequal(sources$original_text, unname(comments)))
source_one <- sources$id[sources$original_text == comments[["1"]]]
listed(lead, "editorial-source", source_one)
lead$select("editorial-source", source_one)
lead$expand("editorial-redact")
lead$select("editorial-kind", "summary")
summary_text <- "Several members ask for a definition of the central term."
lead$type("editorial-redacted", summary_text)
lead$type("editorial-edit_reason", "Summary of three similar comments; no person named")
settle()
lead$mark("editorial-source")
lead$click("editorial-redact")
lead$replaced("editorial-source")
lead$wait_text("editorial-status", "Saved. Original history is preserved.")
edit <- value("SELECT id FROM research.qualitative_edits WHERE study_id=$1", study)$id
lead$select("editorial-source", source_one)
lead$expand("editorial-link")
lead$type("editorial-item_code", "I003")
lead$type("editorial-link_reason", "The comments concern this statement")
settle()
lead$mark("editorial-source")
lead$click("editorial-link")
lead$replaced("editorial-source")
stopifnot(value("SELECT count(*)::int AS n FROM research.qualitative_item_sources WHERE study_id=$1", study)$n == 1L)
reviewer <- as_user(subjects$reviewer)
reviewer$wait_for(sprintf("document.getElementById('study') !== null && document.getElementById('study').value === '%s'", study))
reviewer$wait_for("document.getElementById('editorial-refresh') !== null")
reviewer$click("editorial-refresh")
listed(reviewer, "editorial-review_edit", edit)
reviewer$expand("editorial-release")
reviewer$select("editorial-review_edit", edit)
settle()
reviewer$click("editorial-preview_review")
reviewer$wait_text("editorial-review_preview", summary_text)
reviewer$type("editorial-review_reason", "Faithful to the comments; no person identifiable")
settle()
reviewer$click("editorial-review_confirm")
settle(.3)
reviewer$mark("editorial-review_edit")
reviewer$click("editorial-release")
reviewer$replaced("editorial-review_edit")
stopifnot(value("SELECT count(*)::int AS n FROM research.qualitative_releases WHERE study_id=$1", study)$n == 1L)
reviewer$close()

# 11. Item decisions, feedback with the released summary, second round.
select_round(round(1)$id)
lead$click("management-operations-read")
lead$wait_text("management-operations-analysis", "I012")
decide("rerate", "Rated again after feedback:")
lead$expand("management-operations-draft")
lead$click("management-operations-released_refresh")
listed(lead, "management-operations-released_edits", edit)
invisible(lead$js(sprintf("(function(){document.getElementById('management-operations-released_edits').selectize.setValue(['%s']);return true;})()", edit)))
settle()
lead$click("management-operations-draft")
lead$wait_text("management-operations-status", "Feedback created for review.")
lead$wait_text("management-operations-preview", summary_text)
preview <- lead$text("management-operations-preview")
stopifnot(!grepl("COMMENT-", preview, fixed = TRUE), !grepl("named colleague", preview, fixed = TRUE))
lead$click("management-operations-reviewed")
settle(.3)
lead$click("management-operations-release")
lead$wait_text("management-operations-status", "Feedback released.")
prepare_round_ui()
select_round(round(2)$id)
lead$click("management-operations-assign")
lead$wait_text("management-operations-status", "Feedback assigned.")
open_round(2L)

# 12. Round two: the own previous rating and the panel result beside each
#     item; two members rate and do not submit.
two <- answer_round(2L, seq_len(n), submit = function(member) !member %in% c(15L, 30L))
first_page <- two$pages[[1]]
order <- value("SELECT item_code,dimension_code FROM research.round_items WHERE study_id=$1 AND round_id=$2 ORDER BY display_order,item_code,dimension_code", study, round(2)$id)
first_page$select("panel-block_choice", "1")
settle(.3)
first_page$click("panel-block_go")
first_page$wait_text("panel-block_heading", "Block 1 of")
position <- which(order$item_code == "I003" & order$dimension_code == "relevance")
slot <- position - 0L
first_page$wait_text(sprintf("panel-slot_%d-prior", slot), "Your previous response: answered 8")
shown <- first_page$text(sprintf("panel-slot_%d-title", slot))
stopifnot(
  grepl("Moderated summary (not a quotation):", shown, fixed = TRUE), grepl(summary_text, shown, fixed = TRUE),
  grepl("I003", first_page$text(sprintf("panel-slot_%d-feedback", slot)), fixed = TRUE),
  # Nothing of another member's comment or pseudonym reaches a participant.
  !grepl("COMMENT-TWO", first_page$js("document.documentElement.outerHTML"), fixed = TRUE),
  !grepl("COMMENT-THREE", first_page$js("document.documentElement.outerHTML"), fixed = TRUE)
)
for (s in two$pages) s$close()
one$pages[[1]]$close()
stopifnot(value("SELECT count(*)::int AS n FROM research.submissions s JOIN research.rounds r ON r.id=s.round_id WHERE s.study_id=$1 AND r.number=2", study)$n == n - 2L)

# 13. Final round, decisions, finalization, completion.
conclude_round(2L)
decide("finalize", "Final decision documented:")
advance(round(2)$id, "finalized", "Second round is the final round")
lead$type("management-reason", "Two rounds completed; remaining dissent is documented.")
settle()
confirm(lead, "management-confirm")
settle(.3)
lead$click("management-complete")
lead$wait_text("management-status", "Study completed.")
stopifnot(identical(value("SELECT state FROM research.studies WHERE id=$1", study)$state, "completed"))

# 14. Research export, its report and the offline reproduction.
lead$type("documentation-authors_responsibilities", "Synthetic lead (scenario qualification).")
lead$type("documentation-reason", "Statements for the final report")
settle()
confirm(lead, "documentation-confirm")
settle(.3)
lead$click("documentation-save")
lead$wait_text("documentation-status", "Documentation version saved: 1")
listed(lead, "exports-profile", "research_pseudonymized")
lead$select("exports-profile", "research_pseudonymized")
settle()
confirm(lead, "exports-confirm")
settle(.3)
lead$click("exports-request")
lead$wait_text("exports-status", "Export queued.")
work(study)
lead$click("exports-poll")
lead$wait_text("exports-status", "Succeeded")
export <- qa_unzip(lead$download("exports-download"))
reproduced <- reproduce_study_export(export)
all_text <- paste(unlist(lapply(list.files(export, full.names = TRUE), function(path) readLines(path, warn = FALSE))), collapse = "\n")
classification <- function(number) {
  d <- reproduced$analyses[[as.character(number)]]$decisions
  d <- d[d$dimension_code == "relevance", ]
  stats::setNames(d$classification, d$item_code)[codes]
}
participation <- utils::read.csv(file.path(export, "participation.csv"), stringsAsFactors = FALSE)
decisions <- utils::read.csv(file.path(export, "item_decisions.csv"), stringsAsFactors = FALSE)
responses <- utils::read.csv(file.path(export, "responses.csv"), stringsAsFactors = FALSE)
results <- reproduced$analyses[["1"]]$results
group <- function(item, stratum) results[results$item_code == item & results$dimension_code == "relevance" & results$stratum == stratum, ]
comparisons <- reproduced$comparisons[reproduced$comparisons$dimension_code == "relevance", ]
report <- paste(readLines(file.path(export, "report.html"), warn = FALSE), collapse = "\n")
stopifnot(
  identical(classification(1L), expected[["1"]]), identical(classification(2L), expected[["2"]]),
  # Hand-computed cells of the first round.
  group("I004", "professionals")$n_valid == 15L, group("I004", "professionals")$n_agree == 13L, group("I004", "professionals")$n_disagree == 2L,
  group("I005", "professionals")$n_agree == 10L, group("I006", "professionals")$n_valid == 14L, group("I003", "public_contributors")$n_agree == 0L,
  group("I001", "overall")$n_valid == 30L,
  identical(participation$enrolled, c(30L, 30L)), identical(participation$submitted, c(30L, 28L)), identical(participation$consent_recorded, c(30L, 30L)),
  nrow(decisions) == 24L, setequal(decisions$disposition, c("rerate", "finalize")),
  # Paired members: 28 submitted both rounds; one of them could not judge I006 at first.
  comparisons$n_paired[comparisons$item_code == "I001"] == 28L, comparisons$n_paired[comparisons$item_code == "I006"] == 27L,
  # The export holds pseudonymous responses and no contact, account or unreviewed comment.
  !any(grepl("contact", list.files(export), fixed = TRUE)), !grepl("example.invalid", all_text, fixed = TRUE), !grepl("Synthetic Member", all_text, fixed = TRUE),
  !any(vapply(unlist(subjects), function(x) grepl(x, all_text, fixed = TRUE), logical(1))), !grepl("COMMENT-TWO", all_text, fixed = TRUE), !grepl("named colleague", all_text, fixed = TRUE),
  grepl(summary_text, all_text, fixed = TRUE), sum(responses$round_number == 1 & responses$dimension_code == "relevance") == 360L,
  sum(responses$round_number == 2 & responses$dimension_code == "relevance") == 336L,
  # The report names rounds, participation and decisions.
  grepl("Recruitment and participation", report, fixed = TRUE), grepl("Results by round", report, fixed = TRUE), grepl("finalize", report, fixed = TRUE),
  grepl("Synthetic lead (scenario qualification).", report, fixed = TRUE)
)

# 15. Every step is in the audit trail; nothing was repaired by hand.
lead$click("audit-load")
lead$wait_text("audit-events", "Study completed")
actions <- value("SELECT action,count(*)::int AS n FROM ops.audit WHERE study_id=$1 GROUP BY action", study)
count <- function(action) {
  x <- actions$n[actions$action == action]
  if (length(x)) x else 0L
}
revisions <- value("SELECT r.number,count(*)::int AS n FROM research.response_revisions v JOIN research.rounds r ON r.id=v.round_id WHERE v.study_id=$1 GROUP BY r.number ORDER BY r.number", study)
stopifnot(
  count("create_study") == 1L, count("publish_consent") == 1L, count("staff_account") == 1L, count("panel_import") == 1L, count("invitation_account") == n,
  count("invitation_issue") == n, count("invitation_accept") == n, count("prepare_round") == 2L, count("enroll_panel") == 1L, count("consent") == n,
  count("campaign_release") == 1L, count("message_sink_recorded") == n, count("submit") == 2L * n - 2L, identical(revisions$n, c(363L, 360L)),
  count("save") == sum(revisions$n), count("freeze") == 2L, count("request_analysis") == 2L, count("qualitative_import") == 1L,
  count("qualitative_edit") == 1L, count("qualitative_release") == 1L, count("decision") == 24L, count("feedback_draft") == 1L, count("release_feedback") == 1L,
  count("assign_feedback") == 1L, count("complete_study") == 1L, count("study_documentation") == 1L, count("artifact_download") == 1L,
  identical(value("SELECT state FROM research.rounds WHERE study_id=$1 ORDER BY number", study)$state, c("released", "finalized")),
  value("SELECT count(DISTINCT a.actor_id)::int AS n FROM ops.audit a WHERE a.study_id=$1 AND a.action='save'", study)$n == n
)
log <- readLines(file.path(qa_root, ".checks", paste0("scenario1-", tag, ".log")), warn = FALSE)
stopifnot(!any(grepl(secret, log, fixed = TRUE)), !any(grepl("COMMENT-", log, fixed = TRUE)), !any(grepl("example.invalid", log, fixed = TRUE)))
if (!identical(lead$output_errors(), 0L)) stop("Output errors: ", lead$output_error_ids())
lead$close()
unlink(files, recursive = TRUE)
DBI::dbDisconnect(worker$con)
DBI::dbDisconnect(admin$con)
print(list(
  members = n, groups = 2L, items = 12L, rounds = 2L, every_staff_step_in_the_interface = TRUE, invitations_accepted = n, sink_receipts = n,
  submissions = c(round_1 = n, round_2 = n - 2L), classification_round_1 = table(expected[["1"]]), classification_round_2 = table(expected[["2"]]),
  comments_reviewed_before_feedback = TRUE, export_without_contacts = TRUE, offline_reproduction_matches = TRUE, steps_in_audit_trail = TRUE
))
