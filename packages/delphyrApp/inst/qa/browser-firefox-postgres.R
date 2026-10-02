# The participant's path and the management view in Firefox, driven through
# WebDriver (geckodriver) against PostgreSQL:
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-firefox-postgres.R
#
# The other browser checks use Chromium. This one establishes that consent,
# rating with confirmed saves, block navigation, submission, reload and the
# management review work in a second browser engine.
source("packages/delphyrApp/inst/qa/browser-helpers.R")
geckodriver <- Sys.which("geckodriver")
if (!nzchar(geckodriver)) stop("geckodriver is not installed.")
ports <- c(panel = 3893L, manager = 3894L, driver = 4455L)
admin <- qa_admin()
tag <- substr(uuid::UUIDgenerate(), 1, 8)
code <- paste0("QA-FIREFOX-", tag)
manager <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-manager-", code), TRUE))
p <- demo_protocol()
p$study$code <- code
p$study$title <- paste("Synthetic Firefox study", tag)
p$study$languages <- "en"
study <- create_study(admin, manager, p, "create")$id
consent <- publish_consent(admin, manager, study, "Synthetic demonstration only.", "en", "consent")$id
member <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-", code, "-1")))
invisible(add_panelist(admin, manager, study, member$principal_id, unlist(p$panel$groups)[1], "panel-1"))
codes <- sprintf("I%03d", 1:12)
items <- data.frame(item_code = codes, item_version = 1L, locale = "en", text = paste("Synthetic statement", codes), dimension_code = "relevance", scale_code = "relevance_9", source_ref = "SRC", required = TRUE, display_order = seq_along(codes))
round <- prepare_round(admin, manager, study, items, consent, format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), "round")
for (state in c("review", "approved", "open")) invisible(transition_round(admin, manager, round$id, state, round$hash, "Synthetic qualification", state))
enrollment <- list_enrollments(admin, member, study)$id

build <- function(repo, data) delphyrApp::run_app(repo, delphyr::demo_actor(repo, data$principal))
hosts <- list(
  qa_host(paste0("firefox-panel-", tag), ports[["panel"]], build, list(principal = member$principal_id)),
  qa_host(paste0("firefox-manager-", tag), ports[["manager"]], build, list(principal = manager$principal_id))
)
driver <- processx::process$new(geckodriver, c("--port", as.character(ports[["driver"]])), stdout = file.path(qa_root, ".checks", paste0("geckodriver-", tag, ".log")), stderr = "2>&1")
session_id <- NULL
wd <- function(method, path, body = NULL) {
  request <- httr2::request(sprintf("http://127.0.0.1:%d%s", ports[["driver"]], path)) |> httr2::req_method(method) |> httr2::req_error(is_error = function(resp) FALSE) |> httr2::req_timeout(120)
  if (!is.null(body) || method == "POST") request <- httr2::req_body_json(request, if (is.null(body)) structure(list(), names = character()) else body, auto_unbox = TRUE)
  response <- httr2::req_perform(request)
  value <- httr2::resp_body_json(response)$value
  if (httr2::resp_status(response) >= 400) stop("WebDriver: ", value$error, ": ", substr(value$message, 1, 200))
  value
}
on.exit({
  if (!is.null(session_id)) try(wd("DELETE", paste0("/session/", session_id)), silent = TRUE)
  if (driver$is_alive()) driver$kill()
  for (h in hosts) if (h$is_alive()) h$kill()
}, add = TRUE)
for (attempt in 1:100) {
  ready <- tryCatch(isTRUE(wd("GET", "/status")$ready), error = function(e) FALSE)
  if (ready) break
  Sys.sleep(.2)
}
if (!ready) stop("geckodriver did not start.")
session <- wd("POST", "/session", list(capabilities = list(alwaysMatch = list(browserName = "firefox", `moz:firefoxOptions` = list(args = list("-headless"))))))
session_id <- session$sessionId
at <- function(path) paste0("/session/", session_id, path)
js <- function(script, ...) wd("POST", at("/execute/sync"), list(script = script, args = list(...)))
element <- function(css) wd("POST", at("/element"), list(using = "css selector", value = css))[[1]]
click <- function(css) invisible(wd("POST", at(paste0("/element/", element(css), "/click"))))
type <- function(css, text) invisible(wd("POST", at(paste0("/element/", element(css), "/value")), list(text = text)))
wait_for <- function(script, tries = 300L) {
  for (attempt in seq_len(tries)) {
    if (isTRUE(tryCatch(js(paste("return", script)), error = function(e) FALSE))) return(invisible(TRUE))
    Sys.sleep(.1)
  }
  stop("Firefox condition was not met: ", script)
}
open <- function(port) {
  for (attempt in 1:100) {
    ok <- tryCatch({
      wd("POST", at("/url"), list(url = sprintf("http://127.0.0.1:%d", port)))
      isTRUE(js("return typeof Shiny !== 'undefined'"))
    }, error = function(e) FALSE)
    if (ok) return(invisible(TRUE))
    Sys.sleep(.3)
  }
  stop("Application did not start on port ", port)
}
text <- function(id) js("var x=document.getElementById(arguments[0]); return x ? x.innerText : '';", id)

# 1. Consent, ratings with confirmed saves across two blocks, submission.
open(ports[["panel"]])
wait_for(sprintf("document.getElementById('study') !== null && document.getElementById('study').value === '%s'", study))
wait_for("document.getElementById('panel-load') !== null && !!document.getElementById('panel-enrollment').selectize && Object.keys(document.getElementById('panel-enrollment').selectize.options).length === 1")
click("#panel-load")
wait_for("document.querySelectorAll('#panel-block section.del-item').length === 10")
click("#panel-consent_check")
click("#panel-consent")
wait_for("document.getElementById('panel-status').innerText.includes('Consent saved.')")
rate <- function(generation, rows, digit) {
  for (slot in seq_along(rows)) {
    control <- sprintf("#panel-item_%d_%d-value", generation, rows[slot])
    # A key press in the list, as a person would choose a rating.
    type(control, digit)
    wait_for(sprintf("(function(){var x=document.querySelector('#panel-slot_%d-save_status .del-status--saved');return !!x && x.innerText.includes('Saved:');})()", slot))
    stopifnot(identical(js("return document.querySelector(arguments[0]).value;", control), digit))
  }
}
rate(1L, 1:10, "7")
stopifnot(grepl("10 / 12 response fields confirmed saved", text("panel-progress"), fixed = TRUE), grepl("Block 1 of 2", text("panel-block_heading"), fixed = TRUE))
click("#panel-block_next")
wait_for("document.querySelectorAll('#panel-block section.del-item').length === 2")
wait_for("document.activeElement && document.activeElement.id === 'panel-block_heading'")
rate(2L, 11:12, "4")
click("#panel-confirm")
click("#panel-submit")
wait_for("document.getElementById('panel-receipt').innerText.includes('Submission confirmed:')")
stored <- get_questionnaire(admin, member, enrollment)
stopifnot(nrow(stored$receipt) == 1L, identical(sort(stored$responses$value_int), c(rep(4L, 2), rep(7L, 10))))
# A reload shows the committed answers and no longer accepts changes.
open(ports[["panel"]])
wait_for("document.getElementById('panel-load') !== null && !!document.getElementById('panel-enrollment').selectize && Object.keys(document.getElementById('panel-enrollment').selectize.options).length === 1")
click("#panel-load")
wait_for("document.querySelectorAll('#panel-block section.del-item').length === 10 && document.getElementById('panel-item_1_10-value') !== null")
stopifnot(
  identical(js("return document.getElementById('panel-item_1_1-value').value;"), "7"),
  isTRUE(js("return document.getElementById('panel-item_1_1-value').closest('fieldset').disabled;")),
  grepl("Submission receipt:", text("panel-questionnaire"), fixed = TRUE)
)
overflow <- function(width) {
  invisible(wd("POST", at("/window/rect"), list(width = width, height = 900)))
  Sys.sleep(.5)
  isTRUE(js("return document.documentElement.scrollWidth <= window.innerWidth;"))
}
narrow_panel <- overflow(500)
errors <- function() js("return Array.from(document.querySelectorAll('.shiny-output-error')).filter(function(x){return !x.classList.contains('shiny-output-error-shiny.silent.error') && x.innerText.trim().length>0;}).length;")
stopifnot(identical(errors(), 0L))

# 2. Study management shows the round and its instrument.
invisible(wd("POST", at("/window/rect"), list(width = 1280, height = 900)))
open(ports[["manager"]])
wait_for(sprintf("document.getElementById('study') !== null && document.getElementById('study').value === '%s'", study))
wait_for("document.getElementById('management-review') !== null && document.getElementById('management-rounds').innerText.includes('Open')")
click("#management-review")
wait_for("document.getElementById('management-review_items') !== null && document.getElementById('management-review_items').innerText.includes('Synthetic statement I012')")
click("#audit-load")
wait_for("document.getElementById('audit-events').innerText.includes('Round submitted')")
stopifnot(identical(errors(), 0L), !grepl(member$principal_id, js("return document.body.innerText;"), fixed = TRUE))
narrow_manager <- overflow(500)
stopifnot(narrow_panel, narrow_manager)
version <- paste(session$capabilities$browserName, session$capabilities$browserVersion)
invisible(wd("DELETE", paste0("/session/", session_id)))
session_id <- NULL
DBI::dbDisconnect(admin$con)
print(list(
  browser = version, consent_recorded = TRUE, ratings_saved_and_confirmed = 12L, block_navigation = TRUE, submission_confirmed = TRUE,
  reload_shows_committed_answers = TRUE, management_review_and_history = TRUE, output_errors = 0L, narrow_window_overflow = FALSE
))
