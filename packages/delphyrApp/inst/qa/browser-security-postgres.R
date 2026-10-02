# Hostile text, failure references, the process logs and oversized uploads in
# Chromium against PostgreSQL under the restricted runtime role:
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-security-postgres.R
#
# Every free-text field of a synthetic study carries markup that would run a
# script if it were inserted as HTML. The check passes only if the text is
# shown literally everywhere, nothing of it becomes an element, a refused
# save quotes a reference found in the host's log, and the logs of both hosts
# hold none of the marked values.
source("packages/delphyrApp/inst/qa/browser-helpers.R")
ports <- c(manager = 3889L, panel = 3890L)
admin <- qa_admin()
tag <- substr(uuid::UUIDgenerate(), 1, 8)
code <- paste0("QA-SECURITY-", tag)
hostile <- function(label) sprintf('<img src=x onerror="window.__xss=1" data-xss="1"><script>window.__xss=1</script><b class="xss">XSS-%s</b>', label)
shown <- function(label) paste0("XSS-", label, "</b>")
manager <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-manager-", code), TRUE))
reviewer <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-reviewer-", code)))
p <- demo_protocol()
p$study$code <- code
p$study$title <- hostile("title")
p$study$rationale <- hostile("rationale")
p$study$languages <- "en"
p$panel$groups <- c("professionals", hostile("group"))
p$instrument$dimensions <- list(list(code = "relevance", scale = "relevance_9"), list(code = "comment", scale = "comment_text"))
p$instrument$scales$comment_text <- list(type = "free_text", values = list(), missing_options = c("unable_to_judge"))
p$analysis$consensus$min_valid_n <- 2
p$analysis$consensus$group_policy <- "pooled"
study <- create_study(admin, manager, p, "create")$id
consent <- publish_consent(admin, manager, study, hostile("consent"), "en", "consent")$id
for (capability in c("manage", "edit")) invisible(set_capability(admin, manager, study, reviewer$principal_id, capability, TRUE, paste("reviewer", capability), reason = hostile("reason")))
panel <- lapply(1:3, function(i) {
  actor <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-", code, "-", i)))
  add_panelist(admin, manager, study, actor$principal_id, p$panel$groups[1 + (i == 2)], paste0("panel-", i))
  actor
})
row <- function(dimension, scale, required) data.frame(item_code = "I001", item_version = 1L, locale = "en", text = hostile("item"), dimension_code = dimension, scale_code = scale, source_ref = "SRC-1", required = required, display_order = 1L)
items <- rbind(row("relevance", "relevance_9", TRUE), row("comment", "comment_text", FALSE))
deadline <- function() format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
first <- prepare_round(admin, manager, study, items, consent, deadline(), "round-1")
for (state in c("review", "approved", "open")) invisible(transition_round(admin, manager, first$id, state, first$hash, hostile("reason"), paste("1", state)))
for (i in seq_along(panel)) {
  e <- list_enrollments(admin, panel[[i]], study)$id
  record_consent(admin, panel[[i]], study, consent, TRUE, "consent")
  q <- get_questionnaire(admin, panel[[i]], e)
  save_response(admin, panel[[i]], e, q$items$id[q$items$dimension_code == "relevance"], list(value = 6L + i, status = "answered"), 0L, "rating")
  save_response(admin, panel[[i]], e, q$items$id[q$items$dimension_code == "comment"], list(value = hostile(paste0("answer", i)), status = "answered"), 0L, "comment")
  q <- get_questionnaire(admin, panel[[i]], e)
  submit_round(admin, panel[[i]], e, setNames(q$responses$revision, q$responses$round_item_id), "submit")
}
invisible(transition_round(admin, manager, first$id, "closed", first$hash, hostile("reason"), "close"))
snapshot <- freeze_round(admin, manager, first$id, "freeze")$id
analysis <- run_analysis(admin, manager, snapshot, "analyse")$id
invisible(record_item_decision(admin, manager, analysis, "I001", "retain", hostile("decision"), "decide"))
revision <- DBI::dbGetQuery(admin$con, "SELECT id FROM research.response_revisions WHERE study_id=$1 AND value_text=$2", params = list(study, hostile("answer1")))$id
source_id <- record_qualitative_source(admin, manager, study, hostile("answer1"), "R1-C1", "source", revision)$id
edit <- redact_qualitative_source(admin, manager, study, source_id, hostile("redaction"), hostile("reason"), "edit")
invisible(release_qualitative_edit(admin, reviewer, study, edit$id, edit$hash, hostile("reason"), "release-edit"))
# A version by the second manager that the first one can review.
pending <- redact_qualitative_source(admin, reviewer, study, source_id, hostile("pending"), hostile("reason"), "edit-pending")
feedback <- create_feedback(admin, manager, analysis, command_id = "feedback", released_edits = edit$id)
invisible(release_feedback(admin, manager, feedback$id, feedback$hash, "release-feedback"))
second <- prepare_round(admin, manager, study, items, consent, deadline(), "round-2")
invisible(assign_feedback(admin, manager, second$id, feedback$id, "assign"))
for (state in c("review", "approved", "open")) invisible(transition_round(admin, manager, second$id, state, second$hash, hostile("reason"), paste("2", state)))
invisible(record_study_documentation(admin, manager, study, list(funding = hostile("documentation")), 0L, hostile("reason"), "documentation"))
files <- file.path(qa_root, ".checks", paste0("security-", tag))
dir.create(files, mode = "0700")
contacts <- function(ref, label) data.frame(external_ref = ref, email = paste0(tolower(ref), "@example.invalid"), display_name = hostile(label), locale = "en", stakeholder_group = p$panel$groups[2])
preview <- preview_panel_import(admin, manager, study, paste(utils::capture.output(utils::write.csv(contacts("X-1", "contact"), row.names = FALSE)), collapse = "\n"))
invisible(import_panel(admin, manager, study, preview, preview$hash, hostile("reason"), "import"))
utils::write.csv(contacts("X-2", "upload"), file.path(files, "panel.csv"), row.names = FALSE)
writeBin(c(charToRaw("external_ref,email,display_name,locale,stakeholder_group\n"), rep(charToRaw("A"), 1024L * 1024L + 512L)), file.path(files, "oversized.csv"))
writeBin(rep(charToRaw("A"), 6L * 1024L * 1024L), file.path(files, "huge.csv"))

build <- function(repo, data) delphyrApp::run_app(repo, delphyr::demo_actor(repo, data$principal))
hosts <- list(
  qa_host(paste0("security-manager-", tag), ports[["manager"]], build, list(principal = manager$principal_id)),
  qa_host(paste0("security-panel-", tag), ports[["panel"]], build, list(principal = panel[[1]]$principal_id))
)
on.exit(for (h in hosts) if (h$is_alive()) h$kill(), add = TRUE)
logs <- file.path(qa_root, ".checks", paste0("security-", c("manager", "panel"), "-", tag, ".log"))
open_study <- function(port) {
  s <- qa_session()
  qa_open(s, sprintf("http://127.0.0.1:%d", port))
  s$wait_for(sprintf("document.getElementById('study') !== null && document.getElementById('study').value === '%s'", study))
  s
}
settle <- function(seconds = .45) Sys.sleep(seconds)
current_text <- "SELECT v.value_text FROM research.response_current c JOIN research.response_revisions v ON v.study_id=c.study_id AND v.enrollment_id=c.enrollment_id AND v.round_item_id=c.round_item_id AND v.revision=c.revision WHERE c.enrollment_id=$1 AND v.value_text IS NOT NULL"
# Nothing of a marked text became an element and none of its scripts ran. A
# script would leave its mark for the rest of the session, an element only
# while its view is on screen; each view is therefore awaited with the
# literal text before the next one replaces it.
inert <- function(s) {
  stopifnot(
    identical(s$js("typeof window.__xss"), "undefined"),
    identical(s$js("document.querySelectorAll('[data-xss], b.xss, img[src=\"x\"]').length"), 0L)
  )
}
option_labels <- function(s, id) s$js(sprintf("(function(){var x=document.getElementById('%s');return x&&x.selectize?Object.values(x.selectize.options).map(function(o){return o.label;}).join(' | '):'';})()", id))

# 1. Study management: every view that shows text entered by someone else.
m <- open_study(ports[["manager"]])
stopifnot(grepl(shown("title"), option_labels(m, "study"), fixed = TRUE))
m$wait_for(sprintf("document.getElementById('management-round') !== null && document.getElementById('management-round').selectize !== undefined && Object.keys(document.getElementById('management-round').selectize.options).includes('%s')", second$id))
m$select("management-round", second$id)
settle()
m$click("management-review")
m$wait_text("management-review_items", shown("item"))
m$wait_text("management-review_panel", shown("consent"))
m$expand("management-review_events")
m$wait_text("management-review_events", shown("reason"))
inert(m)
m$select("management-round", first$id)
settle()
m$wait_for("document.getElementById('management-operations-read') !== null")
m$expand("management-operations-read")
m$click("management-operations-read")
m$wait_text("management-operations-analysis", "I001")
m$expand("management-operations-decisions")
m$wait_text("management-operations-decisions", shown("decision"))
m$wait_for(sprintf("document.getElementById('editorial-source') !== null && document.getElementById('editorial-source').selectize !== undefined && Object.keys(document.getElementById('editorial-source').selectize.options).includes('%s')", source_id))
m$select("editorial-source", source_id)
m$expand("editorial-original_preview")
m$wait_text("editorial-original_preview", shown("answer1"))
m$wait_for(sprintf("document.getElementById('editorial-review_edit') !== null && document.getElementById('editorial-review_edit').selectize !== undefined && Object.keys(document.getElementById('editorial-review_edit').selectize.options).includes('%s')", pending$id))
m$expand("editorial-release")
m$select("editorial-review_edit", pending$id)
settle()
m$click("editorial-preview_review")
m$wait_text("editorial-review_preview", shown("pending"))
# A campaign text typed here is previewed literally.
enrollment <- list_enrollments(admin, panel[[1]], study)
enrollment <- enrollment$id[enrollment$number == 2L]
m$wait_for(sprintf("document.getElementById('communications-round') !== null && document.getElementById('communications-round').selectize !== undefined && Object.keys(document.getElementById('communications-round').selectize.options).includes('%s')", second$id))
m$select("communications-round", second$id)
m$wait_for(sprintf("document.getElementById('communications-enrollments') !== null && document.getElementById('communications-enrollments').selectize !== undefined && Object.keys(document.getElementById('communications-enrollments').selectize.options).includes('%s')", enrollment))
invisible(m$js(sprintf("(function(){document.getElementById('communications-enrollments').selectize.setValue(%s);return true;})()", jsonlite::toJSON(enrollment))))
m$select("communications-kind", "reminder")
m$type("communications-subject", substr(hostile("subject"), 1, 190))
m$type("communications-message", hostile("message"))
settle()
m$click("communications-prepare")
m$wait_text("communications-preview", shown("message"))
m$wait_for("document.getElementById('audit-load') !== null")
m$click("audit-load")
m$wait_text("audit-events", shown("reason"))
m$wait_text("documentation-history", shown("reason"))
stopifnot(identical(m$value("documentation-funding"), hostile("documentation")))
m$wait_text("study_setup-consents", shown("consent"))
m$expand("study_setup-group_apply")
m$wait_text("study_setup-panel", shown("group"))
m$wait_for("document.getElementById('invitations-refresh') !== null")
m$click("invitations-refresh")
m$wait_text("invitations-drafts", "X-1")
m$wait_for("document.getElementById('protocols-saved') !== null")
m$expand("protocols-saved")
# The stored protocol is shown as JSON text, which escapes the slash.
m$wait_text("protocols-saved", "XSS-title<\\/b>")
m$wait_for("document.getElementById('panel_import-preview') !== null")
m$upload("panel_import-file", file.path(files, "panel.csv"))
m$click("panel_import-preview")
m$wait_text("panel_import-status", "Preview passed validation.")
m$wait_text("panel_import-rows", shown("upload"))
inert(m)

# 2. Oversized files are refused; nothing is read or imported.
contacts_before <- qa_count(admin, "SELECT count(*) FROM identity.panel_contacts WHERE study_id=$1", study)
m$upload("panel_import-file", file.path(files, "oversized.csv"))
m$click("panel_import-preview")
m$wait_text("panel_import-status", "Reference:")
refused_upload <- trimws(m$text("panel_import-status"))
stopifnot(grepl("^Action failed", refused_upload))
document <- m$b$DOM$getDocument()
node <- m$b$DOM$querySelector(nodeId = document$root$nodeId, selector = "#panel_import-file")$nodeId
invisible(m$b$DOM$setFileInputFiles(files = list(normalizePath(file.path(files, "huge.csv"))), nodeId = node))
m$wait_for("(function(){var p=document.querySelector('#panel_import-file_progress');return !!p && p.innerText.includes('Maximum upload size exceeded');})()")
stopifnot(qa_count(admin, "SELECT count(*) FROM identity.panel_contacts WHERE study_id=$1", study) == contacts_before)

# 3. A panel member reads the same texts and enters marked text.
s <- open_study(ports[["panel"]])
s$wait_for("document.getElementById('panel-load') !== null && document.getElementById('panel-enrollment').selectize !== undefined && Object.keys(document.getElementById('panel-enrollment').selectize.options).length === 2")
s$select("panel-enrollment", enrollment)
settle(.3)
s$click("panel-load")
s$wait_text("panel-questionnaire", shown("item"))
s$wait_text("panel-questionnaire", shown("redaction"))
q <- get_questionnaire(admin, panel[[1]], enrollment)
comment <- which(q$items$dimension_code == "comment")
field <- sprintf("panel-item_%d_1-value", comment)
if (!s$exists(field)) field <- s$js("(function(){var x=document.querySelector('#panel-questionnaire textarea');return x?x.id:'';})()")
answer <- hostile(paste0("typed-", tag))
s$type(field, answer)
s$wait_for(sprintf("(function(){var x=document.getElementById('%s');return !!x && x.innerText.includes('Saved:');})()", sub("-value$", "-save_status", field)))
stored <- DBI::dbGetQuery(admin$con, current_text, params = list(enrollment))$value_text
stopifnot(identical(stored, answer))
invisible(s$b$Page$reload())
s$wait_for("document.getElementById('panel-load') !== null && document.getElementById('panel-enrollment').selectize !== undefined && Object.keys(document.getElementById('panel-enrollment').selectize.options).length === 2")
s$select("panel-enrollment", enrollment)
settle(.3)
s$click("panel-load")
s$wait_for(sprintf("(function(){var x=document.getElementById('%s');return !!x && x.value.length>0;})()", field))
stopifnot(identical(s$value(field), answer))
inert(s)

# 4. A refused save quotes a reference; the host's log holds that entry.
invisible(transition_round(admin, manager, second$id, "closed", second$hash, hostile("reason"), "close-2"))
late <- hostile(paste0("late-", tag))
s$type(field, late)
status <- sub("-value$", "-save_status", field)
s$wait_text(status, "Reference:")
message <- s$text(status)
stopifnot(grepl("The round is closed or its deadline has passed. Saving is unavailable.", message, fixed = TRUE))
reference <- regmatches(message, regexpr("[0-9a-f]{12}$", trimws(message)))
stopifnot(length(reference) == 1L)
entries <- function(path) Filter(Negate(is.null), lapply(readLines(path, warn = FALSE), function(line) if (startsWith(line, "{")) jsonlite::fromJSON(line)))
panel_entries <- entries(logs[2])
entry <- Filter(function(x) identical(x$correlation_id, reference), panel_entries)
stopifnot(
  length(entry) == 1L, identical(entry[[1]]$operation, "save_response"), identical(entry[[1]]$outcome, "refused"),
  identical(entry[[1]]$error_class, "DEL_ROUND_CLOSED"), identical(entry[[1]]$component, "app"),
  identical(DBI::dbGetQuery(admin$con, current_text, params = list(enrollment))$value_text, answer)
)
# The file refused before any service was called has its own entry.
upload_entry <- Filter(function(x) identical(x$correlation_id, regmatches(refused_upload, regexpr("[0-9a-f]{12}$", refused_upload))), entries(logs[1]))
stopifnot(length(upload_entry) == 1L, identical(upload_entry[[1]]$operation, "interface"), identical(upload_entry[[1]]$outcome, "failed"))
inert(s)

# 5. Neither host wrote a marked value, an answer, a contact or an account.
for (path in logs) {
  text <- paste(readLines(path, warn = FALSE), collapse = "\n")
  stopifnot(
    !grepl("XSS-", text, fixed = TRUE), !grepl("__xss", text, fixed = TRUE), !grepl("example.invalid", text, fixed = TRUE),
    !grepl(study, text, fixed = TRUE), !any(vapply(c(list(manager, reviewer), panel), function(a) grepl(a$principal_id, text, fixed = TRUE), logical(1)))
  )
}
for (session in list(m, s)) {
  if (!identical(session$output_errors(), 0L)) stop("Output errors: ", session$output_error_ids())
  for (mobile in c(TRUE, FALSE)) {
    session$viewport(mobile)
    Sys.sleep(.3)
    stopifnot(session$no_overflow())
  }
  session$close()
}
unlink(files, recursive = TRUE)
DBI::dbDisconnect(admin$con)
print(list(
  hostile_text_shown_literally = TRUE, no_injected_element_or_script = TRUE, typed_markup_stored_and_restored_exactly = TRUE,
  oversized_file_refused = TRUE, upload_beyond_request_limit_refused = TRUE, refused_save_quotes_reference = reference,
  reference_found_in_host_log = TRUE, logs_without_marked_values = TRUE, mobile_overflow = FALSE
))
