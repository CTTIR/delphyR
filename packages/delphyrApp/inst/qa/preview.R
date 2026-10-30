library(delphyrApp)

# One synthetic in-memory study. Start a fresh host for each smoke run.
q <- list(
  round = list(number = 1, deadline = "2026-12-01", study_id = "demo"),
  enrollment = list(id = "own", state = "eligible"),
  consent = list(id = "consent", locale = "en", content = "Synthetic demonstration only. Participation is voluntary.", accepted = FALSE),
  receipt = data.frame(),
  protocol = list(
    study = list(timezone = "Europe/Berlin", default_language = "en"),
    instrument = list(scales = list(rating = list(
      type = "ordinal_integer", values = 1:9,
      anchors = list(low = "Not relevant", high = "Extremely relevant"),
      missing_options = c("unable_to_judge", "abstained")
    )))
  ),
  items = data.frame(
    id = "item", scale_code = "rating",
    texts = '{"de":"Wie relevant ist eine klare Kommunikation im Studienteam?","en":"How relevant is clear communication within the study team?"}',
    dimension_code = "relevance", required = TRUE
  ),
  responses = data.frame(round_item_id = character(), revision = integer(), status = character(), value_int = integer(), value_text = character())
)
services <- list(
  list_studies = function(...) data.frame(id = "demo", title = "Synthetic Delphi panel"),
  list_enrollments = function(...) data.frame(id = "own", number = 1, round_state = "open"),
  get_questionnaire = function(...) q,
  record_consent = function(repo, actor, study_id, consent_version_id, decision, command_id) {
    q$consent$accepted <<- isTRUE(decision)
    q$consent$recorded_at <<- "2026-09-25T12:00:00Z"
    list(id = "synthetic-consent", recorded_at = "2026-09-25T12:00:00Z")
  },
  save_response = function(repo, actor, enrollment_id, round_item_id, response, expected_revision, command_id) {
    stopifnot(isTRUE(q$consent$accepted), q$enrollment$state != "submitted")
    revision <- expected_revision + 1L
    q$responses <<- data.frame(
      round_item_id = round_item_id, revision = revision, status = response$status,
      value_int = if (is.null(response$value)) NA_integer_ else as.integer(response$value),
      value_text = NA_character_, created_at = "2026-09-25T12:00:00Z"
    )
    list(revision = revision, saved_at = "2026-09-25T12:00:00Z")
  },
  submit_round = function(repo, actor, enrollment_id, expected_revision_set, command_id) {
    stopifnot(isTRUE(q$consent$accepted), nrow(q$responses) == 1L)
    q$enrollment$state <<- "submitted"
    q$receipt <<- data.frame(id = "synthetic-submission", submitted_at = "2026-09-25T12:00:01Z")
    list(id = "synthetic-submission", submitted_at = "2026-09-25T12:00:01Z")
  }
)
# Explicit-save mode: browser-smoke.R checks pending and confirmed states.
shiny::runApp(run_app(NULL, list(principal_id = "trusted-synthetic"), language = "en", services = services, autosave_ms = 0), host = "127.0.0.1", port = 3867, launch.browser = FALSE)
