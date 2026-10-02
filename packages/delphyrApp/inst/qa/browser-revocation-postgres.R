# A right revoked during an open session, and an identifier of another person
# sent by a manipulated page, in Chromium against PostgreSQL:
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-revocation-postgres.R
#
# An analyst has an export on screen. The study lead revokes the analyst's
# rights in the interface. The analyst's next request and download in the
# same, still open session are refused. A panel member's page then asks for
# another member's questionnaire and receives nothing.
source("packages/delphyrApp/inst/qa/browser-helpers.R")
ports <- c(lead = 3895L, analyst = 3896L, member = 3897L)
admin <- qa_admin()
f <- qa_two_round_study(admin)
tag <- substr(uuid::UUIDgenerate(), 1, 8)
analyst <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-analyst-", f$code)))
for (right in c("analyse", "export")) invisible(set_capability(admin, f$manager, f$study_id, analyst$principal_id, right, TRUE, paste("grant", right), reason = "Methodologist of the study"))
build <- function(repo, data) delphyrApp::run_app(repo, delphyr::demo_actor(repo, data$principal))
names <- paste0("revocation-", c("lead", "analyst", "member"), "-", tag)
hosts <- list(
  qa_host(names[1], ports[["lead"]], build, list(principal = f$manager$principal_id)),
  qa_host(names[2], ports[["analyst"]], build, list(principal = analyst$principal_id)),
  qa_host(names[3], ports[["member"]], build, list(principal = f$panel[[1]]$principal_id))
)
on.exit(for (h in hosts) if (h$is_alive()) h$kill(), add = TRUE)
logs <- file.path(qa_root, ".checks", paste0(names, ".log"))
worker <- qa_connection(Sys.getenv("DELPHYR_DB_RUNTIME", "delphyr_runtime"))
work <- function() while (!identical(worker_step(worker, study_id = f$study_id), FALSE)) NULL
open_study <- function(port) {
  s <- qa_session()
  qa_open(s, sprintf("http://127.0.0.1:%d", port))
  s$wait_for(sprintf("document.getElementById('study') !== null && document.getElementById('study').value === '%s'", f$study_id))
  s
}
settle <- function(seconds = .45) Sys.sleep(seconds)
# Arguments are evaluated before the statement is sent: one of them may run a
# query of its own.
value <- function(sql, ...) {
  params <- list(...)
  DBI::dbGetQuery(admin$con, sql, params = params)
}
entries <- function(path) Filter(Negate(is.null), lapply(readLines(path, warn = FALSE), function(line) if (startsWith(line, "{")) jsonlite::fromJSON(line)))
reference <- function(text) regmatches(trimws(text), regexpr("[0-9a-f]{12}$", trimws(text)))
request_export <- function(s, profile) {
  s$wait_for("document.getElementById('exports-profile') !== null && document.getElementById('exports-profile').selectize !== undefined")
  s$select("exports-profile", profile)
  settle()
  if (!isTRUE(s$js("document.getElementById('exports-confirm').checked"))) s$click("exports-confirm")
  settle(.3)
  s$click("exports-request")
}

# 1. The analyst requests and downloads the summary export.
a <- open_study(ports[["analyst"]])
a$wait_for("document.getElementById('exports-profile') !== null && document.getElementById('exports-profile').selectize !== undefined && Object.keys(document.getElementById('exports-profile').selectize.options).length > 0")
stopifnot(identical(a$js("Object.keys(document.getElementById('exports-profile').selectize.options).sort().join(',')"), "research_pseudonymized,study_summary"))
request_export(a, "study_summary")
a$wait_text("exports-status", "Export queued.")
work()
a$click("exports-poll")
a$wait_text("exports-status", "Succeeded")
summary <- qa_unzip(a$download("exports-download"))
stopifnot("participation.csv" %in% list.files(summary))
jobs_before <- value("SELECT count(*)::int AS n FROM ops.jobs WHERE study_id=$1", f$study_id)$n

# 2. The study lead revokes both rights of the analyst in the interface.
l <- open_study(ports[["lead"]])
revoke <- function(right) {
  l$wait_for(sprintf("document.getElementById('study_setup-staff_account') !== null && document.getElementById('study_setup-staff_account').selectize !== undefined && Object.keys(document.getElementById('study_setup-staff_account').selectize.options).includes('%s')", analyst$principal_id))
  l$expand("study_setup-staff_apply")
  l$select("study_setup-staff_account", analyst$principal_id)
  l$select("study_setup-staff_capability", right)
  l$select("study_setup-staff_action", "revoke")
  l$type("study_setup-staff_reason", "The analyst left the study team.")
  settle()
  if (!isTRUE(l$js("document.getElementById('study_setup-staff_confirm').checked"))) l$click("study_setup-staff_confirm")
  settle(.3)
  l$mark("study_setup-staff_account")
  l$click("study_setup-staff_apply")
  l$replaced("study_setup-staff_account")
  l$wait_text("study_setup-status", "Change of rights confirmed.")
}
revoke("analyse")
revoke("export")
rights <- value("SELECT c.capability FROM identity.capabilities c JOIN identity.memberships m ON m.study_id=c.study_id AND m.id=c.membership_id WHERE c.study_id=$1 AND m.principal_id=$2 AND c.revoked_at IS NULL", f$study_id, analyst$principal_id)
stopifnot(nrow(rights) == 0L)

# 3. The analyst's open session: every further request is refused.
stopifnot(a$exists("exports-request"), grepl("Succeeded", a$text("exports-status"), fixed = TRUE))
a$click("exports-request")
a$wait_text("exports-status", "Reference:")
refused <- a$text("exports-status")
stopifnot(grepl("^Action failed", refused), value("SELECT count(*)::int AS n FROM ops.jobs WHERE study_id=$1", f$study_id)$n == jobs_before)
entry <- Filter(function(x) identical(x$correlation_id, reference(refused)), entries(logs[2]))
stopifnot(length(entry) == 1L, identical(entry[[1]]$operation, "request_study_export"), identical(entry[[1]]$outcome, "refused"), entry[[1]]$error_class %in% c("DEL_FORBIDDEN", "DEL_NOT_FOUND"))
# The export produced before the revocation is no longer delivered.
download <- tryCatch(a$download("exports-download"), error = function(e) conditionMessage(e))
stopifnot(is.character(download), grepl("HTTP", download, fixed = TRUE))
a$click("exports-poll")
a$wait_text("exports-status", "Reference:")
downloads <- value("SELECT count(*)::int AS n FROM ops.audit WHERE study_id=$1 AND action='artifact_download' AND actor_id=$2", f$study_id, analyst$principal_id)$n
stopifnot(downloads == 1L)
# What was already on screen is not recalled; after a reload nothing is offered.
invisible(a$b$Page$reload())
a$wait_for("document.getElementById('status') !== null && document.getElementById('status').innerText.length > 0 || document.querySelector('nav.del-nav') === null")
settle(1)
stopifnot(isTRUE(a$js("(function(){var x=document.getElementById('exports-profile');return !x || !x.selectize || Object.keys(x.selectize.options).length === 0 || x.offsetParent === null;})()")))

# 4. A manipulated page asks for another member's questionnaire.
m <- open_study(ports[["member"]])
m$wait_for("document.getElementById('panel-load') !== null && document.getElementById('panel-enrollment').selectize !== undefined && Object.keys(document.getElementById('panel-enrollment').selectize.options).length === 2")
other <- utils::tail(list_enrollments(admin, f$panel[[2]], f$study_id)$id, 1)
own <- list_enrollments(admin, f$panel[[1]], f$study_id)$id
stopifnot(!other %in% own)
invisible(m$js(sprintf("(function(){Shiny.setInputValue('panel-enrollment', '%s');return true;})()", other)))
settle()
m$click("panel-load")
m$wait_text("panel-status", "Reference:")
stopifnot(grepl("^Action failed", m$text("panel-status")), identical(m$js("document.querySelectorAll('#panel-questionnaire section.del-item').length"), 0L))
foreign <- Filter(function(x) identical(x$correlation_id, reference(m$text("panel-status"))), entries(logs[3]))
stopifnot(length(foreign) == 1L, identical(foreign[[1]]$operation, "get_questionnaire"), identical(foreign[[1]]$error_class, "DEL_NOT_FOUND"))
page <- m$js("document.documentElement.outerHTML")
stopifnot(!grepl(other, gsub(sprintf("Shiny.setInputValue\\('panel-enrollment', '%s'\\)", other), "", page), fixed = TRUE) || !grepl("del-item", page, fixed = TRUE))
# The audit trail names who revoked which right and why.
history <- value("SELECT detail,reason FROM ops.audit WHERE study_id=$1 AND action='capability' AND reason=$2 ORDER BY occurred_at", f$study_id, "The analyst left the study team.")
stopifnot(identical(history$detail, c("analyse revoked", "export revoked")))
for (s in list(a, l, m)) s$close()
DBI::dbDisconnect(worker$con)
DBI::dbDisconnect(admin$con)
print(list(
  export_before_revocation = TRUE, rights_revoked_in_interface = c("analyse", "export"), next_request_in_open_session_refused = TRUE,
  earlier_export_no_longer_delivered = TRUE, nothing_offered_after_reload = TRUE, foreign_questionnaire_refused = TRUE, revocation_in_audit_trail = TRUE
))
