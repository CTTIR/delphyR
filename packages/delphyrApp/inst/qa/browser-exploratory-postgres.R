# From free-text proposals to rated items, with independently released
# feedback content and a later correction, in Chromium against PostgreSQL:
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-exploratory-postgres.R
#
# The free-text round itself is conducted through the services; the editorial
# work, the independent release, the feedback, the rating round and the
# correction happen in the browser with three separate accounts.
source("packages/delphyrApp/inst/qa/browser-helpers.R")
ports <- c(lead = 3885L, reviewer = 3886L, panel = 3887L)
admin <- qa_admin()
tag <- substr(uuid::UUIDgenerate(), 1, 8)
code <- paste0("QA-EXPLORE-", tag)
lead <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-lead-", code), TRUE))
p <- demo_protocol()
p$study$code <- code
p$study$title <- paste("Synthetic exploratory study", tag)
p$study$design <- "exploratory_round_based_delphi"
p$study$languages <- "en"
p$instrument$dimensions <- list(list(code = "proposal", scale = "open_text"), list(code = "relevance", scale = "relevance_9"))
p$instrument$scales$open_text <- list(type = "free_text", values = list(), missing_options = c("unable_to_judge"))
p$analysis$consensus$min_valid_n <- 2
p$analysis$consensus$group_policy <- "pooled"
study <- create_study(admin, lead, p, "create")$id
consent <- publish_consent(admin, lead, study, "Synthetic demonstration only.", "en", "consent")$id
panel <- lapply(1:4, function(i) {
  actor <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-", code, "-", i)))
  add_panelist(admin, lead, study, actor$principal_id, unlist(p$panel$groups)[1 + (i > 2)], paste0("panel-", i))
  actor
})
reviewer <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-reviewer-", code)))
invisible(set_capability(admin, lead, study, reviewer$principal_id, "manage", TRUE, "reviewer", reason = "Independent reviewer of editorial versions"))
deadline <- function() format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
first <- prepare_round(admin, lead, study, data.frame(item_code = "X001", item_version = 1L, locale = "en", text = "Which topics should the guidance cover?", dimension_code = "proposal", scale_code = "open_text", source_ref = "QA-EXPLORATORY", required = TRUE, display_order = 1L), consent, deadline(), "round-1")
for (state in c("review", "approved", "open")) transition_round(admin, lead, first$id, state, first$hash, "Synthetic qualification", state)
proposals <- paste0("ORIGINAL-PROPOSAL-", 1:4, c(" shared decisions (named colleague)", " shared decisions too", " training", " cost should not decide"))
for (i in 1:4) {
  e <- list_enrollments(admin, panel[[i]], study)$id
  record_consent(admin, panel[[i]], study, consent, TRUE, "consent")
  item <- get_questionnaire(admin, panel[[i]], e)$items$id
  saved <- save_response(admin, panel[[i]], e, item, list(value = proposals[i], status = "answered"), 0L, "save")
  submit_round(admin, panel[[i]], e, setNames(saved$revision, item), "submit")
}
invisible(transition_round(admin, lead, first$id, "closed", first$hash, "All proposals received", "close"))
snapshot <- freeze_round(admin, lead, first$id, "freeze")$id
analysis <- run_analysis(admin, lead, snapshot, "analyse")$id
files <- file.path(qa_root, ".checks", paste0("exploratory-", tag))
dir.create(files, mode = "0700")
utils::write.csv(data.frame(item_code = c("N001", "N002"), item_version = 1L, locale = "en", text = c("Guidance should cover shared decision making.", "Guidance should cover staff training."), dimension_code = "relevance", scale_code = "relevance_9", source_ref = "ROUND-1-PROPOSALS", required = TRUE, display_order = 1:2), file.path(files, "items.csv"), row.names = FALSE)

build <- function(repo, data) delphyrApp::run_app(repo, delphyr::demo_actor(repo, data$principal))
hosts <- list(
  qa_host("exploratory-lead", ports[["lead"]], build, list(principal = lead$principal_id)),
  qa_host("exploratory-reviewer", ports[["reviewer"]], build, list(principal = reviewer$principal_id)),
  qa_host("exploratory-panel", ports[["panel"]], build, list(principal = panel[[1]]$principal_id))
)
on.exit(for (h in hosts) if (h$is_alive()) h$kill(), add = TRUE)
open_study <- function(port) {
  s <- qa_session()
  qa_open(s, sprintf("http://127.0.0.1:%d", port))
  s$wait_for(sprintf("document.getElementById('study') !== null && document.getElementById('study').value === '%s'", study))
  s
}
settle <- function(seconds = .45) Sys.sleep(seconds)
value <- function(sql, ...) {
  params <- list(...)
  DBI::dbGetQuery(admin$con, sql, params = params)
}

# 1. The editor takes over the frozen proposals as sources.
l <- open_study(ports[["lead"]])
l$wait_for("document.getElementById('editorial-contribution_import') !== null")
l$expand("editorial-contribution_import")
l$wait_text("editorial-contributions", "4")
stopifnot(value("SELECT count(*)::int AS n FROM research.qualitative_sources WHERE study_id=$1", study)$n == 0L)
l$mark("editorial-source")
l$click("editorial-contribution_import")
l$replaced("editorial-source")
l$wait_text("editorial-status", "Contributions taken over: 4")
sources <- value("SELECT id,source_ref,original_text FROM research.qualitative_sources WHERE study_id=$1", study)
stopifnot(nrow(sources) == 4L, setequal(sources$original_text, proposals), all(grepl("^R1-X001-proposal-[0-9a-f]{8}$", sources$source_ref)))
source_of <- function(i) sources$id[sources$original_text == proposals[i]]

# 2. Separate versions: a summary across similar proposals and a redaction.
create_version <- function(i, kind, text, reason) {
  l$wait_for(sprintf("document.getElementById('editorial-source').selectize !== undefined && Object.keys(document.getElementById('editorial-source').selectize.options).includes('%s')", source_of(i)))
  l$select("editorial-source", source_of(i))
  l$expand("editorial-redact")
  l$select("editorial-kind", kind)
  l$type("editorial-redacted", text)
  l$type("editorial-edit_reason", reason)
  settle()
  before <- value("SELECT count(*)::int AS n FROM research.qualitative_edits WHERE study_id=$1", study)$n
  l$mark("editorial-source")
  l$click("editorial-redact")
  l$replaced("editorial-source")
  l$wait_text("editorial-status", "Saved. Original history is preserved.")
  stopifnot(value("SELECT count(*)::int AS n FROM research.qualitative_edits WHERE study_id=$1", study)$n == before + 1L)
  value("SELECT id FROM research.qualitative_edits WHERE study_id=$1 ORDER BY created_at DESC LIMIT 1", study)$id
}
wrong_summary <- create_version(1, "summary", "Most members reject covering shared decision making.", "Summary of two similar proposals")
redaction <- create_version(4, "redaction", "Cost should not decide.", "Wording shortened; dissenting view kept")
# The original stays readable for the editor and is unchanged.
l$select("editorial-source", source_of(1))
l$expand("editorial-original_preview")
l$wait_text("editorial-original_preview", "named colleague")
# 3. Derived items are linked to the proposals they come from.
link_item <- function(i, item) {
  l$select("editorial-source", source_of(i))
  l$expand("editorial-link")
  l$type("editorial-item_code", item)
  l$type("editorial-link_reason", paste("Derived from proposal", i))
  settle()
  before <- value("SELECT count(*)::int AS n FROM research.qualitative_item_sources WHERE study_id=$1", study)$n
  l$mark("editorial-source")
  l$click("editorial-link")
  l$replaced("editorial-source")
  stopifnot(value("SELECT count(*)::int AS n FROM research.qualitative_item_sources WHERE study_id=$1", study)$n == before + 1L)
}
link_item(1, "N001")
link_item(2, "N001")
link_item(3, "N002")
stopifnot(value("SELECT count(*)::int AS n FROM research.qualitative_item_sources WHERE study_id=$1", study)$n == 3L)
# The author of a version cannot release it.
stopifnot(identical(l$js("Object.keys(document.getElementById('editorial-review_edit').selectize.options).length"), 0L))

# 4. A second manager reviews and releases the exact versions.
r <- open_study(ports[["reviewer"]])
release_version <- function(edit, expected) {
  r$wait_for("document.getElementById('editorial-refresh') !== null")
  r$click("editorial-refresh")
  r$wait_for(sprintf("document.getElementById('editorial-review_edit') !== null && document.getElementById('editorial-review_edit').selectize !== undefined && Object.keys(document.getElementById('editorial-review_edit').selectize.options).includes('%s')", edit))
  r$expand("editorial-release")
  r$select("editorial-review_edit", edit)
  settle()
  r$click("editorial-preview_review")
  r$wait_text("editorial-review_preview", expected)
  r$type("editorial-review_reason", "Faithful to the proposals; dissent preserved")
  settle()
  r$click("editorial-review_confirm")
  settle(.3)
  r$mark("editorial-review_edit")
  r$click("editorial-release")
  r$replaced("editorial-review_edit")
  if (value("SELECT count(*)::int AS n FROM research.qualitative_releases WHERE edit_id=$1", edit)$n != 1L) stop("Version was not released: ", r$text("editorial-status"))
}
stopifnot(!grepl("named colleague", r$js("document.documentElement.outerHTML"), fixed = TRUE))
release_version(wrong_summary, "Most members reject covering shared decision making.")
release_version(redaction, "Cost should not decide.")

# 5. Feedback from released versions only; rating round with the derived items.
round_id <- function(number) value("SELECT id FROM research.rounds WHERE study_id=$1 AND number=$2 AND state<>'cancelled'", study, number)$id
select_round <- function(id) {
  l$wait_for(sprintf("document.getElementById('management-round').selectize !== undefined && Object.keys(document.getElementById('management-round').selectize.options).includes('%s')", id))
  l$select("management-round", id)
  settle()
}
advance <- function(id, target, reason) {
  l$select("management-target", target)
  l$type("management-reason", reason)
  settle()
  if (!isTRUE(l$js("document.getElementById('management-confirm').checked"))) l$click("management-confirm")
  settle(.3)
  l$click("management-transition")
  label <- c(review = "In review", approved = "Approved", open = "Open")[[target]]
  l$wait_for(sprintf("(function(){var x=document.getElementById('management-round');return !!x && !!x.selectize && !!x.selectize.options['%s'] && x.selectize.options['%s'].label.endsWith('%s');})()", id, id, label))
  settle()
}
select_round(round_id(1))
l$expand("management-operations-draft")
l$click("management-operations-released_refresh")
l$wait_for(sprintf("document.getElementById('management-operations-released_edits') !== null && document.getElementById('management-operations-released_edits').selectize !== undefined && Object.keys(document.getElementById('management-operations-released_edits').selectize.options).includes('%s')", redaction))
l$js(sprintf("(function(){document.getElementById('management-operations-released_edits').selectize.setValue(['%s','%s']);return true;})()", wrong_summary, redaction))
settle()
l$click("management-operations-draft")
l$wait_text("management-operations-status", "Feedback created for review.")
l$wait_text("management-operations-preview", "Most members reject covering shared decision making.")
stopifnot(!grepl("ORIGINAL-PROPOSAL", l$text("management-operations-preview"), fixed = TRUE))
l$click("management-operations-reviewed")
settle(.3)
l$click("management-operations-release")
l$wait_text("management-operations-status", "Feedback released.")
old_feedback <- value("SELECT id,hash FROM research.feedback WHERE study_id=$1 AND state='released'", study)
stopifnot(nrow(old_feedback) == 1L)
l$expand("management-operations-prepare")
l$upload("management-operations-csv", file.path(files, "items.csv"))
l$click("management-operations-validate")
l$wait_text("management-operations-status", "Import validated.")
l$type("management-operations-deadline", deadline())
settle()
l$click("management-operations-prepare")
l$wait_text("management-operations-status", "Round draft created.")
second <- round_id(2)
select_round(second)
l$click("management-operations-assign")
l$wait_text("management-operations-status", "Feedback assigned.")
advance(second, "review", "Derived items handed to review")
l$click("management-review")
l$wait_text("management-review_items", "staff training")
advance(second, "approved", "Exact derived instrument approved")
advance(second, "open", "Rating round opened")

# 6. A panel member sees released content, labelled, beside the derived item.
m <- open_study(ports[["panel"]])
enrollment <- utils::tail(list_enrollments(admin, panel[[1]], study)$id, 1)
load_second <- function() {
  m$wait_for(sprintf("document.getElementById('panel-enrollment') !== null && document.getElementById('panel-enrollment').selectize !== undefined && Object.keys(document.getElementById('panel-enrollment').selectize.options).includes('%s')", enrollment))
  m$select("panel-enrollment", enrollment)
  settle()
  m$click("panel-load")
  m$wait_for("document.getElementById('panel-item_1_2-value') !== null")
}
load_second()
m$wait_text("panel-slot_1-prior", "Moderated summary (not a quotation): Most members reject covering shared decision making.")
m$wait_text("panel-round_feedback", "Redacted contribution: Cost should not decide.")
page <- m$js("document.documentElement.outerHTML")
stopifnot(!grepl("ORIGINAL-PROPOSAL-2", page, fixed = TRUE), !grepl("ORIGINAL-PROPOSAL-4", page, fixed = TRUE), !grepl("named colleague", m$text("panel-slot_1-prior"), fixed = TRUE), !grepl("This feedback was corrected", page, fixed = TRUE))
m$select("panel-item_1_1-value", "3")
m$wait_for("document.querySelector('#panel-slot_1-save_status .del-status--saved') !== null")

# 7. The summary reversed the proposals. It is corrected by a new version.
right_summary <- create_version(1, "summary", "Most members propose covering shared decision making.", "The earlier summary reversed the direction of the proposals")
release_version(right_summary, "Most members propose covering shared decision making.")
select_round(round_id(1))
l$expand("management-operations-correction_release")
l$click("management-operations-released_refresh")
l$wait_for(sprintf("document.getElementById('management-operations-correction_edits') !== null && document.getElementById('management-operations-correction_edits').selectize !== undefined && Object.keys(document.getElementById('management-operations-correction_edits').selectize.options).includes('%s')", right_summary))
l$wait_for(sprintf("document.getElementById('management-operations-correction_target').value === '%s'", old_feedback$id))
l$js(sprintf("(function(){document.getElementById('management-operations-correction_edits').selectize.setValue(['%s','%s']);return true;})()", right_summary, redaction))
settle()
l$click("management-operations-correction_draft")
l$wait_text("management-operations-status", "Corrected version created for review.")
l$wait_text("management-operations-correction_preview", "Most members propose covering shared decision making.")
l$click("management-operations-correction_release")
l$wait_text("management-operations-status", "Rationale, effect, note and confirmation are required.")
stopifnot(value("SELECT count(*)::int AS n FROM research.feedback_corrections WHERE study_id=$1", study)$n == 0L)
l$type("management-operations-correction_reason", "The summary reversed the direction of the proposals.")
l$type("management-operations-correction_impact", "One member had already rated N001; the rating is reviewed with that member's later submission.")
l$type("management-operations-correction_note", "The summary of round one was wrong: most members propose covering shared decision making.")
settle()
l$click("management-operations-correction_confirm")
settle(.3)
l$click("management-operations-correction_release")
l$wait_text("management-operations-status", "Correction released.")
l$wait_text("management-operations-published", "replaced")

# 8. Later views show the corrected version with its note; history is intact.
invisible(m$b$Page$reload())
load_second()
m$wait_text("panel-round_feedback", "This feedback was corrected. The summary of round one was wrong")
m$wait_text("panel-slot_1-prior", "Moderated summary (not a quotation): Most members propose covering shared decision making.")
stopifnot(!grepl("Most members reject", m$js("document.documentElement.outerHTML"), fixed = TRUE), identical(m$value("panel-item_1_1-value"), "3"))
feedback <- value("SELECT f.id,f.hash,f.state,f.content::text AS content FROM research.feedback f WHERE f.study_id=$1 ORDER BY (f.id=$2) DESC", study, old_feedback$id)
correction <- value("SELECT feedback_id,replacement_id,reason FROM research.feedback_corrections WHERE study_id=$1", study)
shown <- value("SELECT object_ref FROM ops.audit WHERE study_id=$1 AND action='feedback_displayed' ORDER BY occurred_at", study)$object_ref
releases <- value("SELECT e.edited_by,rel.reviewer_id FROM research.qualitative_releases rel JOIN research.qualitative_edits e ON e.id=rel.edit_id WHERE rel.study_id=$1", study)
stopifnot(
  nrow(feedback) == 2L, all(feedback$state == "released"), identical(feedback$hash[1], old_feedback$hash), grepl("Most members reject", feedback$content[1], fixed = TRUE),
  nrow(correction) == 1L, identical(correction$feedback_id, old_feedback$id), identical(correction$replacement_id, feedback$id[2]),
  identical(shown[1], old_feedback$id), identical(utils::tail(shown, 1), feedback$id[2]),
  nrow(releases) == 3L, all(releases$edited_by == lead$principal_id), all(releases$reviewer_id == reviewer$principal_id),
  # The original proposals are untouched by all editorial work.
  setequal(value("SELECT original_text FROM research.qualitative_sources WHERE study_id=$1", study)$original_text, proposals)
)
for (s in list(l, r, m)) {
  if (!identical(s$output_errors(), 0L)) stop("Output errors: ", s$output_error_ids())
  for (mobile in c(TRUE, FALSE)) {
    s$viewport(mobile)
    Sys.sleep(.3)
    stopifnot(s$no_overflow())
  }
  s$close()
}
DBI::dbDisconnect(admin$con)
print(list(
  proposals_preserved_as_sources = 4L, author_cannot_release_own_version = TRUE, independent_releases = 3L,
  feedback_from_released_versions_only = TRUE, summary_labelled_not_quotation = TRUE, originals_never_shown_to_panel = TRUE,
  corrected_by_new_version = TRUE, earlier_version_and_displays_unchanged = TRUE, mobile_overflow = FALSE
))
