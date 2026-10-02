# Study documentation, comparability decisions, export profiles, the audit
# history and the participant feedback download in Chromium against PostgreSQL.
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-governance-postgres.R
source("packages/delphyrApp/inst/qa/browser-helpers.R")
ports <- c(manager = 3881L, auditor = 3882L, panel = 3883L)
admin <- qa_admin()
f <- qa_two_round_study(admin)
auditor <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-auditor-", f$code)))
invisible(set_capability(admin, f$manager, f$study_id, auditor$principal_id, "audit", TRUE, "auditor"))
build <- function(repo, data) delphyrApp::run_app(repo, delphyr::demo_actor(repo, data$principal))
hosts <- list(
  qa_host("governance-manager", ports[["manager"]], build, list(principal = f$manager$principal_id)),
  qa_host("governance-auditor", ports[["auditor"]], build, list(principal = auditor$principal_id)),
  qa_host("governance-panel", ports[["panel"]], build, list(principal = f$panel[[1]]$principal_id))
)
on.exit(for (h in hosts) if (h$is_alive()) h$kill(), add = TRUE)
# The export worker is a separate process in operation; here it is stepped
# explicitly under the restricted runtime role.
worker <- qa_connection(Sys.getenv("DELPHYR_DB_RUNTIME", "delphyr_runtime"))
work <- function() while (!identical(worker_step(worker, study_id = f$study_id), FALSE)) NULL
open_study <- function(s, port) {
  qa_open(s, sprintf("http://127.0.0.1:%d", port))
  s$wait_for(sprintf("document.getElementById('study') !== null && document.getElementById('study').value === '%s'", f$study_id))
}
panelists <- DBI::dbGetQuery(admin$con, "SELECT id FROM research.panelists WHERE study_id=$1", params = list(f$study_id))$id
export_through <- function(s, profile) {
  s$wait_for("document.getElementById('exports-profile') !== null && document.getElementById('exports-profile').selectize !== undefined")
  s$select("exports-profile", profile)
  Sys.sleep(.4)
  s$click("exports-request")
  s$wait_text("exports-status", "confirm your entitlement")
  s$click("exports-confirm")
  Sys.sleep(.3)
  s$click("exports-request")
  s$wait_text("exports-status", "Export queued.")
  work()
  s$click("exports-poll")
  s$wait_text("exports-status", "Succeeded")
  qa_unzip(s$download("exports-download"))
}
all_text <- function(directory) paste(unlist(lapply(list.files(directory, full.names = TRUE), function(p) readLines(p, warn = FALSE))), collapse = "\n")

# 1. The manager records the study team's statements for reports.
m <- qa_session()
open_study(m, ports[["manager"]])
m$wait_for("document.getElementById('documentation-save') !== null")
m$type("documentation-authors_responsibilities", "Synthetic author A (lead), synthetic author B (methods).")
m$type("documentation-funding", "No external funding (synthetic).")
Sys.sleep(.5)
m$click("documentation-save")
m$wait_text("documentation-status", "reason and confirmation")
stopifnot(qa_count(admin, "SELECT count(*) FROM research.study_documentation WHERE study_id=$1", f$study_id) == 0L)
m$type("documentation-reason", "Initial author statements")
Sys.sleep(.5)
m$click("documentation-confirm")
m$click("documentation-save")
m$wait_text("documentation-status", "Documentation version saved: 1")
m$wait_text("documentation-history", "Initial author statements")

# 2. An explicit comparability decision for the revised item.
m$wait_for("document.getElementById('editorial-comparable_save') !== null")
m$expand("editorial-comparable_save")
m$type("editorial-comparable_item", "I001")
m$type("editorial-comparable_dimension", "relevance")
m$type("editorial-comparable_reason", "The revision changed the meaning of the item.")
Sys.sleep(.5)
m$click("editorial-comparable_confirm")
m$click("editorial-comparable_save")
m$wait_text("editorial-status", "Comparability decision saved.")
m$wait_text("editorial-comparability", "The revision changed the meaning of the item.")
decision <- DBI::dbGetQuery(admin$con, "SELECT item_code,previous_version,current_version,comparable FROM research.item_comparability WHERE study_id=$1", params = list(f$study_id))
stopifnot(nrow(decision) == 1L, identical(decision$comparable, FALSE), decision$previous_version == 1L, decision$current_version == 2L)

# 3. Export profiles follow the manager's rights; the summary has no individual data.
m$wait_for("document.getElementById('exports-profile') !== null && document.getElementById('exports-profile').selectize !== undefined")
offered <- m$js("Object.keys(document.getElementById('exports-profile').selectize.options).sort().join(',')")
stopifnot(identical(offered, "audit_restricted,research_pseudonymized,study_summary"))
summary <- export_through(m, "study_summary")
text <- all_text(summary)
stopifnot(
  !"responses.csv" %in% list.files(summary), "participation.csv" %in% list.files(summary), "report.html" %in% list.files(summary) || !nzchar(Sys.which("quarto")),
  !any(vapply(panelists, function(id) grepl(id, text, fixed = TRUE), logical(1))), grepl("Synthetic author A (lead)", text, fixed = TRUE),
  identical(utils::read.csv(file.path(summary, "participation.csv"))$submitted, c(4L, 3L))
)
research <- export_through(m, "research_pseudonymized")
again <- reproduce_study_export(research)
changed <- again$comparisons[again$comparisons$item_code == "I001", ]
stopifnot(
  identical(changed$status, "not_comparable"), identical(changed$reason, "The revision changed the meaning of the item."),
  identical(again$comparisons$n_paired[again$comparisons$item_code == "I002"], 3L),
  identical(again$analyses[["2"]]$provenance$result_hash, get_analysis(admin, f$manager, f$analyses[2])$provenance$result_hash),
  !grepl(f$panel[[1]]$principal_id, all_text(research), fixed = TRUE)
)

# 4. The history shows these actions with their rationale.
m$wait_for("document.getElementById('audit-load') !== null")
m$click("audit-load")
m$wait_text("audit-events", "Study documentation recorded")
history <- m$text("audit-events")
stopifnot(
  grepl("Initial author statements", history, fixed = TRUE), grepl("Comparability decided", history, fixed = TRUE),
  grepl("Export downloaded", history, fixed = TRUE), grepl("Panel member", history, fixed = TRUE),
  !any(vapply(f$panel, function(a) grepl(a$principal_id, history, fixed = TRUE), logical(1)))
)

# 5. The audit role sees history and its own export, nothing else.
a <- qa_session()
open_study(a, ports[["auditor"]])
a$wait_for("document.querySelector('nav.del-nav') !== null")
stopifnot(identical(a$js("Array.from(document.querySelectorAll('nav.del-nav a')).map(function(x){return x.getAttribute('href');}).join(',')"), "#section-exports,#section-audit"))
stopifnot(!a$exists("management-transition"), !a$exists("documentation-save"), !a$exists("panel-load") || isTRUE(a$js("document.getElementById('panel-workspace').offsetParent === null")))
a$wait_for("document.getElementById('exports-profile') !== null && document.getElementById('exports-profile').selectize !== undefined")
stopifnot(identical(a$js("Object.keys(document.getElementById('exports-profile').selectize.options).join(',')"), "audit_restricted"))
audit <- export_through(a, "audit_restricted")
events <- utils::read.csv(file.path(audit, "audit_events.csv"), stringsAsFactors = FALSE)
stopifnot(
  setequal(list.files(audit), c("README.md", "manifest.json", "audit_events.csv", "round_events.csv", "protocol_versions.csv", "campaign_approvals.csv", "staff_rights.csv", "qualitative_releases.csv", "documentation_versions.csv")),
  all(c("save", "submit", "study_documentation", "item_comparability") %in% events$action),
  all(is.na(events$actor_ref[events$actor_kind == "panel"]) | events$actor_ref[events$actor_kind == "panel"] == ""),
  !any(vapply(f$panel, function(p) grepl(p$principal_id, all_text(audit), fixed = TRUE), logical(1)))
)
a$click("audit-load")
a$wait_text("audit-events", "Round state changed")

# 6. A panel member reads the comparability notice and downloads only own feedback.
p <- qa_session()
open_study(p, ports[["panel"]])
p$wait_for("document.getElementById('panel-load') !== null && document.getElementById('panel-enrollment').selectize !== undefined && Object.keys(document.getElementById('panel-enrollment').selectize.options).length === 2")
second <- utils::tail(list_enrollments(admin, f$panel[[1]], f$study_id)$id, 1)
p$select("panel-enrollment", second)
Sys.sleep(.3)
p$click("panel-load")
p$wait_text("panel-item_1_1-prior", "The wording changed. Ratings are not directly comparable.")
stopifnot(!p$exists("exports-profile"), !p$exists("audit-load"))
own <- qa_unzip(p$download("panel-feedback_download"))
answers <- utils::read.csv(file.path(own, "own_previous_responses.csv"), stringsAsFactors = FALSE)
stopifnot(
  setequal(list.files(own), c("README.md", "panel_results.csv", "own_previous_responses.csv", "feedback.json")),
  setequal(answers$value_integer, c(8L, 7L)), !any(vapply(panelists, function(id) grepl(id, all_text(own), fixed = TRUE), logical(1)))
)
downloads <- DBI::dbGetQuery(admin$con, "SELECT action,detail FROM ops.audit WHERE study_id=$1 AND action IN ('artifact_download','feedback_download') ORDER BY occurred_at", params = list(f$study_id))
stopifnot(identical(downloads$detail[downloads$action == "artifact_download"], c("study_summary", "research_pseudonymized", "audit_restricted")), sum(downloads$action == "feedback_download") == 1L)
for (s in list(m, a, p)) {
  stopifnot(identical(s$output_errors(), 0L))
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
  documentation_version_recorded = TRUE, comparability_decision_recorded = TRUE, profiles_follow_rights = TRUE,
  summary_without_individual_data = TRUE, research_export_reproduced = TRUE, history_with_rationales = TRUE,
  auditor_sees_only_history_and_audit_export = TRUE, participant_downloads_only_own_feedback = TRUE, downloads_audited = TRUE, mobile_overflow = FALSE
))
