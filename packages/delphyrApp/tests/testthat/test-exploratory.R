exploratory_services <- function(names) stats::setNames(rep(list(function(...) NULL), length(names)), names)

test_that("editors take over frozen free-text contributions as sources", {
  taken <- 0L
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "edit",
      get_qualitative_provenance = list(sources = data.frame(id = character(), source_ref = character(), original_text = character()), themes = data.frame(id = character(), label = character(), version = integer())),
      list_contribution_rounds = data.frame(round_number = 1:2, snapshot_id = c("snapshot-1", "snapshot-2"), contributions = c(8L, 0L), imported = c(taken, 0L)),
      import_round_contributions = {
        taken <<- 8L
        list(id = list(...)[[1]], imported = 8L)
      },
      stop("Unexpected service")
    )
  }
  names <- c("get_capabilities", "get_qualitative_provenance", "list_qualitative_reviews", "record_qualitative_source", "redact_qualitative_source", "release_qualitative_edit", "create_qualitative_theme", "code_qualitative_source", "link_item_source", "record_item_lineage", "list_contribution_rounds", "import_round_contributions")
  shiny::testServer(delphyrApp:::editorial_server, args = list(study = function() "study", lang = function() "en", call = call, services = exploratory_services(names)), {
    session$flushReact()
    expect_match(output$body$html, "Take over free-text contributions", fixed = TRUE)
    # A round without free-text answers is not offered.
    expect_false(grepl("snapshot-2", output$body$html, fixed = TRUE))
    expect_match(output$contributions, "Free-text answers", fixed = TRUE)
    expect_match(output$contributions, ">   8 </td>", fixed = TRUE)
    session$setInputs(contribution_round = "snapshot-1", contribution_import = 1)
    expect_match(output$status, "Contributions taken over: 8", fixed = TRUE)
    expect_identical(contributions()$imported[1], 8L)
  })
})

test_that("a round frozen in another section is offered without a manual refresh", {
  frozen <- 0L
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "edit",
      get_qualitative_provenance = list(sources = data.frame(id = character(), source_ref = character(), original_text = character()), themes = data.frame(id = character(), label = character(), version = integer())),
      list_contribution_rounds = data.frame(round_number = seq_len(frozen), snapshot_id = sprintf("snapshot-%d", seq_len(frozen)), contributions = rep(3L, frozen), imported = rep(0L, frozen)),
      stop("Unexpected service")
    )
  }
  names <- c("get_capabilities", "get_qualitative_provenance", "list_qualitative_reviews", "record_qualitative_source", "redact_qualitative_source", "release_qualitative_edit", "create_qualitative_theme", "code_qualitative_source", "link_item_source", "record_item_lineage", "list_contribution_rounds", "import_round_contributions")
  changed <- shiny::reactiveVal(0L)
  shiny::testServer(delphyrApp:::editorial_server, args = list(study = function() "study", lang = function() "en", call = call, services = exploratory_services(names), changed = changed), {
    session$flushReact()
    expect_identical(nrow(contributions()), 0L)
    frozen <<- 1L
    changed(1L)
    session$flushReact()
    expect_identical(contributions()$snapshot_id, "snapshot-1")
    expect_match(output$contributions, ">   3 </td>", fixed = TRUE)
    expect_identical(output$status, "")
  })
})

exploratory_operations <- function(state) {
  function(name, ...) {
    state$calls[[length(state$calls) + 1L]] <- list(name, ...)
    switch(name,
      get_study_setup = list(protocol = list(), consent_versions = data.frame(id = "consent", locale = "en", content = "Synthetic")),
      list_released_edits = data.frame(edit_id = c("edit-a", "edit-b"), source_ref = c("R1-X001-a", "R1-X001-b"), kind = c("summary", "redaction"), text = c("A moderated summary", "A redacted contribution"), released_at = "now", item_codes = c("N001", "")),
      list_released_feedback = if (state$corrected) {
        data.frame(round_number = c(1L, 1L), feedback_id = c("feedback-old", "feedback-new"), hash = c("oldhash000000", "newhash000000"), assigned_round = c(2L, NA), replacement_id = c("feedback-new", NA), reason = c("Direction reversed", NA), impact_note = c("None", NA), participant_note = c("Corrected", NA), corrected_at = c("now", NA), is_correction = c(FALSE, TRUE))
      } else {
        data.frame(round_number = 1L, feedback_id = "feedback-old", hash = "oldhash000000", assigned_round = 2L, replacement_id = NA_character_, reason = NA_character_, impact_note = NA_character_, participant_note = NA_character_, corrected_at = NA_character_, is_correction = FALSE)
      },
      create_feedback = list(id = "feedback-new", hash = "newhash000000"),
      get_feedback_candidate = list(content = list(), hash = "newhash000000", state = "reviewed"),
      release_feedback_correction = {
        state$corrected <- TRUE
        list(id = "feedback-new", replaces = "feedback-old")
      },
      stop("unexpected service")
    )
  }
}
exploratory_operation_names <- c("freeze_round", "request_analysis", "get_operation", "get_analysis", "create_feedback", "get_feedback_candidate", "release_feedback", "assign_feedback", "request_export", "download_artifact", "get_study_setup", "prepare_round", "list_released_edits", "list_released_feedback", "release_feedback_correction")

test_that("feedback is composed from released editorial versions only", {
  state <- new.env()
  state$calls <- list()
  state$corrected <- FALSE
  round <- function() data.frame(id = "round", number = 1L, snapshot_id = "snapshot", analysis_id = "analysis")
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = round, lang = function() "en", call = exploratory_operations(state), services = exploratory_services(exploratory_operation_names), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$released_choice$html, "Summary", fixed = TRUE)
    expect_match(output$released_choice$html, "A redacted contribution", fixed = TRUE)
    session$setInputs(released_edits = c("edit-b", "edit-a"), draft = 1)
    created <- Filter(function(x) x[[1]] == "create_feedback", state$calls)[[1]]
    expect_identical(created[[2]], "analysis")
    expect_identical(created[[3]], list())
    expect_identical(created$released_edits, c("edit-a", "edit-b"))
  })
})

test_that("a correction needs the corrected version, three texts and a confirmation", {
  state <- new.env()
  state$calls <- list()
  state$corrected <- FALSE
  round <- function() data.frame(id = "round", number = 1L, snapshot_id = "snapshot", analysis_id = "analysis")
  corrections <- function() Filter(function(x) x[[1]] == "release_feedback_correction", state$calls)
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = round, lang = function() "en", call = exploratory_operations(state), services = exploratory_services(exploratory_operation_names), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$published, "current", fixed = TRUE)
    session$setInputs(correction_target = "feedback-old", correction_reason = "Direction reversed", correction_impact = "None", correction_note = "Corrected", correction_confirm = TRUE, correction_release = 1)
    expect_length(corrections(), 0L)
    session$setInputs(correction_edits = "edit-a", correction_draft = 1)
    expect_match(output$status, "Corrected version created for review", fixed = TRUE)
    session$setInputs(correction_note = " ", correction_confirm = TRUE, correction_release = 2)
    expect_length(corrections(), 0L)
    expect_match(output$status, "Rationale, effect, note and confirmation", fixed = TRUE)
    session$setInputs(correction_note = "Corrected", correction_confirm = FALSE, correction_release = 3)
    expect_length(corrections(), 0L)
    session$setInputs(correction_confirm = TRUE, correction_release = 4)
    done <- corrections()[[1]]
    expect_identical(unname(done[2:7]), list("feedback-old", "feedback-new", "newhash000000", "Direction reversed", "None", "Corrected"))
    expect_match(output$status, "Correction released", fixed = TRUE)
    expect_match(output$published, "replaced", fixed = TRUE)
    expect_match(output$published, "Correction, current", fixed = TRUE)
    expect_null(correction())
  })
})

test_that("participants see released content labelled by kind and the correction note", {
  entries <- data.frame(text = c("A moderated summary", "A redacted contribution", "A general remark"), kind = c("summary", "redaction", "summary"), source_ref = c("a", "b", "c"), stringsAsFactors = FALSE)
  entries$item_codes <- list("N001", c("N001", "N002"), character())
  expect_identical(qualitative_for(entries, "N001")$text, c("A moderated summary", "A redacted contribution"))
  expect_identical(qualitative_for(entries, "N002")$text, "A redacted contribution")
  # Content attached to no displayed item appears once, above the items.
  expect_identical(qualitative_for(entries, NULL, c("N001", "N002"))$text, "A general remark")
  expect_identical(qualitative_for(entries, NULL, "N002")$text, c("A moderated summary", "A general remark"))
  expect_equal(nrow(qualitative_for(NULL, "N001")), 0L)
  html <- as.character(qualitative_list(qualitative_for(entries, "N001"), "en"))
  expect_match(html, "Moderated summary (not a quotation):", fixed = TRUE)
  expect_match(html, "Redacted contribution:", fixed = TRUE)
  expect_null(qualitative_list(qualitative_for(entries, "N009"), "en"))
  # Text is rendered as text: markup in a released version stays inert.
  hostile <- data.frame(text = "<script>alert(1)</script>", kind = "summary", source_ref = "x", stringsAsFactors = FALSE)
  expect_false(grepl("<script>", as.character(qualitative_list(hostile, "en")), fixed = TRUE))
  q <- list(
    protocol = list(instrument = list(scales = list(rating = list(type = "ordinal_integer", values = 1:9, missing_options = c("unable_to_judge"))))),
    enrollment = list(id = "own"), responses = data.frame(round_item_id = character(), revision = integer(), status = character(), value_int = integer(), value_text = character()),
    feedback = list(own = data.frame(item_code = character(), item_version = integer(), dimension_code = character(), answer_status = character(), value_integer = integer(), value_text = character()), aggregate = list(results = data.frame(item_code = "N001", dimension_code = "relevance")), qualitative = entries)
  )
  item <- data.frame(id = "item", item_code = "N001", item_version = 1L, scale_code = "rating", texts = '{"en":"Derived item"}', dimension_code = "relevance", required = TRUE)
  shiny::testServer(delphyrApp:::rating_server, args = list(q = q, item = item, lang = function() "en", call = function(...) NULL, autosave_ms = 0), {
    expect_match(output$title$html, "A moderated summary", fixed = TRUE)
    expect_match(output$title$html, "A redacted contribution", fixed = TRUE)
    expect_false(grepl("A general remark", output$title$html, fixed = TRUE))
  })
  q$round <- list(number = 2, deadline = "2026-12-01", study_id = "study")
  q$protocol$study <- list(timezone = "Europe/Berlin")
  q$consent <- list(id = "consent", content = "Synthetic study information")
  q$receipt <- data.frame()
  q$items <- item
  q$feedback$correction <- list(participant_note = "The summary of round one was corrected.", corrected_at = "now")
  call <- function(name, ...) {
    switch(name,
      list_enrollments = data.frame(id = "own", number = 2, round_state = "open"),
      get_questionnaire = q,
      get_feedback = q$feedback,
      stop("unexpected call")
    )
  }
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = call, feedback_available = TRUE, autosave_ms = 0), {
    session$setInputs(enrollment = "own", load = 1)
    expect_match(output$round_feedback$html, "This feedback was corrected. The summary of round one was corrected.", fixed = TRUE)
    expect_match(output$round_feedback$html, "A general remark", fixed = TRUE)
    expect_false(grepl("A redacted contribution", output$round_feedback$html, fixed = TRUE))
  })
})
