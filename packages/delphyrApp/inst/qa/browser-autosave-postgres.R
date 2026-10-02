# Automatic saving, a two-tab conflict, connection loss and submission with a
# pending entry, in Chromium against PostgreSQL. Run from the repository root:
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-autosave-postgres.R
source("packages/delphyrApp/inst/qa/browser-helpers.R")
port <- 3879L
admin <- qa_admin()
f <- demo_study(admin, n = 2L, item_count = 2L)
for (target in c("review", "approved", "open")) transition_round(admin, f$manager, f$round$id, target, f$round$hash, "Synthetic autosave qualification", target)
panelist <- f$panel[[1]]$principal_id
enrollment <- list_enrollments(admin, f$panel[[1]], f$study_id)$id
items <- DBI::dbGetQuery(admin$con, "SELECT id,item_code FROM research.round_items WHERE round_id=$1 ORDER BY display_order", params = list(f$round$id))
host <- qa_host("autosave-panel", port, function(repo, data) delphyrApp::run_app(repo, delphyr::demo_actor(repo, data$principal)), list(principal = panelist))
on.exit(if (host$is_alive()) host$kill(), add = TRUE)
url <- sprintf("http://127.0.0.1:%d", port)
current <- function(item) DBI::dbGetQuery(admin$con, "SELECT v.revision,v.status,v.value_int FROM research.response_current c JOIN research.response_revisions v ON v.study_id=c.study_id AND v.enrollment_id=c.enrollment_id AND v.round_item_id=c.round_item_id AND v.revision=c.revision WHERE c.enrollment_id=$1 AND c.round_item_id=$2", params = list(enrollment, items$id[item]))
revisions <- function() qa_count(admin, "SELECT count(*) FROM research.response_revisions WHERE enrollment_id=$1", enrollment)
load_round <- function(s) {
  s$wait_for("document.getElementById('panel-load') !== null && document.getElementById('panel-enrollment').value !== ''")
  s$click("panel-load")
  s$wait_for("document.getElementById('panel-item_1_1-value') !== null && document.getElementById('panel-item_1_1-value').selectize !== undefined")
}
saved <- function(s, item) s$wait_for(sprintf("document.querySelector('#panel-item_1_%d-save_status .del-status--saved') !== null && document.getElementById('panel-item_1_%d-status').innerText.startsWith('Saved:')", item, item))

# 1. A rating alone is an answer and is saved without any button.
a <- qa_session()
qa_open(a, url)
load_round(a)
a$wait_text("panel-save_note", "saved automatically")
a$click("panel-consent_check")
a$click("panel-consent")
a$wait_text("panel-status", "Consent saved.")
stopifnot(identical(a$value("panel-item_1_1-kind"), "not_answered"), identical(a$value("panel-item_1_1-value"), ""))
a$select("panel-item_1_1-value", "7")
a$wait_for("document.getElementById('panel-item_1_1-kind').value === 'answered'")
a$wait_text("panel-item_1_1-status", "Unsaved change")
stopifnot(revisions() == 0L)
saved(a, 1)
x <- current(1)
stopifnot(x$revision == 1L, x$status == "answered", x$value_int == 7L)

# 2. A changed rating is unsaved until its own commit is confirmed.
a$select("panel-item_1_1-value", "8")
a$wait_text("panel-item_1_1-status", "Unsaved change")
stopifnot(!grepl("Saved:", a$text("panel-item_1_1-status"), fixed = TRUE), current(1)$value_int == 7L)
saved(a, 1)
stopifnot(current(1)$revision == 2L, current(1)$value_int == 8L)

# 3. A special response clears the rating shown beside it.
a$select("panel-item_1_2-value", "3")
a$wait_for("document.getElementById('panel-item_1_2-kind').value === 'answered'")
a$select("panel-item_1_2-kind", "abstained")
a$wait_for("document.getElementById('panel-item_1_2-value').value === ''")
saved(a, 2)
x <- current(2)
stopifnot(x$status == "abstained", is.na(x$value_int))
abstained_revision <- x$revision

# 4. A second tab of the same person commits a newer revision.
b <- qa_session()
qa_open(b, url)
load_round(b)
stopifnot(identical(b$value("panel-item_1_1-value"), "8"))
b$select("panel-item_1_1-value", "5")
saved(b, 1)
stopifnot(current(1)$revision == 3L, current(1)$value_int == 5L)

# 5. The first tab's stale entry is refused, not merged or overwritten.
before <- revisions()
a$select("panel-item_1_1-value", "9")
a$wait_text("panel-item_1_1-status", "Conflict")
a$wait_for("document.getElementById('panel-item_1_1-reload') !== null")
stopifnot(
  isTRUE(a$js("document.querySelector('#panel-item_1_1-save_status .del-status--attention') !== null")),
  identical(a$value("panel-item_1_1-value"), "9"), revisions() == before, current(1)$value_int == 5L
)
a$select("panel-item_1_1-value", "6")
Sys.sleep(2.5)
stopifnot(revisions() == before, grepl("Conflict", a$text("panel-item_1_1-status"), fixed = TRUE))
a$click("panel-item_1_1-reload")
a$wait_for("document.getElementById('panel-item_1_1-value').value === '5'")
a$wait_text("panel-item_1_1-status", "Saved response loaded.")
Sys.sleep(2.5)
stopifnot(revisions() == before, current(1)$revision == 3L, !a$exists("panel-item_1_1-reload"))

# 6. Connection loss: no confirmation, and a reload shows the committed state.
a$select("panel-item_1_1-value", "4")
a$offline(TRUE)
a$js("Shiny.shinyapp.$socket.close()")
a$wait_text("panel-connection", "Connection lost. Changes are not being saved.")
stopifnot(isTRUE(a$js("document.getElementById('panel-item_1_1-status').parentElement.hidden")))
Sys.sleep(2.5)
stopifnot(revisions() == before, current(1)$value_int == 5L)
a$offline(FALSE)
invisible(a$b$Page$reload())
Sys.sleep(1)
load_round(a)
stopifnot(identical(a$value("panel-item_1_1-value"), "5"), identical(a$value("panel-item_1_2-kind"), "abstained"))

# 7. Submitting with a pending entry saves it first, then submits that revision.
a$select("panel-item_1_1-value", "6")
a$click("panel-confirm")
a$click("panel-submit")
a$wait_for("document.getElementById('panel-receipt').innerText.includes('Submission confirmed:')")
final <- current(1)
entries <- DBI::dbGetQuery(admin$con, "SELECT v.round_item_id,v.revision,v.status,v.value_int FROM research.submission_entries se JOIN research.response_revisions v ON v.id=se.response_revision_id WHERE se.enrollment_id=$1 ORDER BY v.round_item_id", params = list(enrollment))
stopifnot(
  final$revision == 4L, final$value_int == 6L, nrow(entries) == 2L,
  entries$revision[entries$round_item_id == items$id[1]] == 4L, entries$value_int[entries$round_item_id == items$id[1]] == 6L,
  entries$status[entries$round_item_id == items$id[2]] == "abstained", entries$revision[entries$round_item_id == items$id[2]] == abstained_revision,
  identical(DBI::dbGetQuery(admin$con, "SELECT state FROM research.enrollments WHERE id=$1", params = list(enrollment))$state, "submitted")
)
# The audit trail holds exactly the committed saves and one submission.
audit <- DBI::dbGetQuery(admin$con, "SELECT action,count(*)::int AS n FROM ops.audit WHERE study_id=$1 AND actor_id=$2 AND action IN ('save','submit') GROUP BY action", params = list(f$study_id, panelist))
stopifnot(audit$n[audit$action == "save"] == revisions(), audit$n[audit$action == "submit"] == 1L)
for (s in list(a, b)) {
  stopifnot(identical(s$output_errors(), 0L))
  for (mobile in c(TRUE, FALSE)) {
    s$viewport(mobile)
    Sys.sleep(.3)
    stopifnot(s$no_overflow())
  }
  s$close()
}
total <- revisions()
DBI::dbDisconnect(admin$con)
print(list(
  autosave_without_button = TRUE, rating_implies_answer = TRUE, special_response_clears_rating = TRUE,
  second_tab_conflict_refused = TRUE, stale_entry_never_committed = TRUE, deliberate_reload_only = TRUE,
  offline_edit_unconfirmed_and_uncommitted = TRUE, pending_entry_saved_before_submission = TRUE,
  committed_revisions = total, final_item_1 = 6L, mobile_overflow = FALSE
))
