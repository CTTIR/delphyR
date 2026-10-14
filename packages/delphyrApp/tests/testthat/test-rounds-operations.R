rounds_operation_names <- c(
  "freeze_round", "request_analysis", "get_operation", "get_analysis", "create_feedback", "get_feedback_candidate", "release_feedback", "assign_feedback",
  "request_export", "download_artifact", "get_study_setup", "prepare_round", "record_item_decision", "list_item_decisions", "get_round_instrument",
  "list_released_edits", "list_released_feedback", "release_feedback_correction"
)
rounds_services <- function(names = rounds_operation_names) stats::setNames(rep(list(function(...) NULL), length(names)), names)
rounds_round <- function(id, number, state, snapshot = state %in% c("frozen", "analysed", "released", "finalized"), analysis = state %in% c("analysed", "released", "finalized")) {
  data.frame(id = id, number = number, state = state, instrument_hash = paste0("hash-", id), deadline = as.POSIXct("2026-12-01 17:00:00", tz = "UTC"), snapshot_id = if (snapshot) paste0("snapshot-", number) else NA_character_, analysis_id = if (analysis) paste0("analysis-", number) else NA_character_, stringsAsFactors = FALSE)
}
rounds_analysis <- function() {
  list(
    results = data.frame(
      round_number = 1L, item_code = c("I001", "I001", "I002", "I002"), item_version = 1L, dimension_code = c("relevance", "comment", "relevance", "comment"), scale_code = c("relevance_9", "comment_text", "relevance_9", "comment_text"),
      stratum = "overall", n_assigned = 8L, n_submitted = 8L, n_answered = c(8L, 2L, 2L, 0L), n_not_answered = 0L, n_unable = 0L, n_abstained = 0L, n_not_applicable = 0L,
      n_valid = c(8L, 0L, 2L, 0L), n_agree = c(6L, 0L, 1L, 0L), n_disagree = 0L, p_agree = c(0.75, NA, 0.5, NA), p_disagree = c(0, NA, 0, NA),
      classification = c("consensus_in", "not_rated", "insufficient_data", "not_rated"), median = c(7.5, NA, 6, NA), q1 = c(6.75, NA, 5.5, NA), q3 = c(8.25, NA, 6.5, NA), iqr = c(1.5, NA, 1, NA),
      stringsAsFactors = FALSE
    ),
    decisions = data.frame(item_code = c("I001", "I001", "I002", "I002"), item_version = 1L, dimension_code = c("relevance", "comment", "relevance", "comment"), classification = c("consensus_in", "not_rated", "insufficient_data", "not_rated"), stringsAsFactors = FALSE),
    settings = list(agree_values = 7:9, min_valid_n = 3)
  )
}
rounds_instrument <- function() {
  list(items = data.frame(
    item_code = c("I001", "I001", "I002", "I002"), item_version = 1L, dimension_code = "relevance", scale_code = "relevance_9", locale = c("de", "en"),
    text = c("Erste synthetische Aussage", "First synthetic statement", "Zweite synthetische Aussage", "Second synthetic statement"),
    required = TRUE, display_order = c(1L, 1L, 2L, 2L), source_ref = "SRC", stringsAsFactors = FALSE
  ))
}
rounds_error <- function(code, path) structure(list(message = paste(code, path), call = NULL, code = code, path = path), class = c(code, "delphyr_error", "error", "condition"))
rounds_call <- function(state) {
  function(name, ...) {
    state$calls[[length(state$calls) + 1L]] <- list(name, ...)
    switch(name,
      get_study_setup = state$setup,
      get_analysis = c(rounds_analysis(), list(id = list(...)[[1]])),
      get_round_instrument = c(rounds_instrument(), list(protocol = list(version = 1L, config = state$frozen))),
      get_round_readiness = list(valid = TRUE, issues = state$readiness),
      list_item_decisions = state$decisions,
      record_item_decision = list(id = "decision"),
      list_released_edits = state$edits,
      list_released_feedback = state$released,
      assign_feedback = {
        # The service assigns the feedback to the members enrolled in the round.
        if (state$enrolled) state$readiness <- state$readiness[state$readiness$code != "feedback_unassigned", , drop = FALSE]
        list(id = list(...)[[1]])
      },
      request_analysis = list(id = "analysis-job"),
      request_export = list(id = "export-job"),
      get_operation = state$operation,
      prepare_round = {
        if (!is.null(state$refuse)) stop(rounds_error("DEL_CONFLICT", state$refuse))
        list(id = "round-new", hash = "h")
      },
      stop("unexpected service ", name)
    )
  }
}
rounds_state <- function() {
  state <- new.env()
  state$calls <- list()
  state$setup <- list(protocol = list(study = list(timezone = "Europe/Berlin", languages = c("de", "en")), instrument = list(dimensions = list(list(code = "relevance", scale = "relevance_9")), scales = list(relevance_9 = list(type = "ordinal_integer"))), stopping = list(max_rounds = 3)), consent_versions = data.frame(id = "consent-1", locale = "en", content = "Synthetic study information", hash = "c1", stringsAsFactors = FALSE))
  state$decisions <- data.frame(round_number = 1L, item_code = "I002", disposition = "retain", reason = "Kept after discussion", decided_at = "2026-10-02 10:00:00+00", stringsAsFactors = FALSE)
  state$edits <- data.frame(edit_id = character(), source_ref = character(), kind = character(), text = character(), stringsAsFactors = FALSE)
  state$released <- data.frame(round_number = integer(), feedback_id = character(), hash = character(), assigned_round = integer(), replacement_id = character(), reason = character(), impact_note = character(), participant_note = character(), corrected_at = character(), is_correction = logical(), stringsAsFactors = FALSE)
  state$operation <- data.frame(state = "queued", result_ref = NA_character_)
  # The protocol frozen with the round, as its instrument returns it.
  state$frozen <- list(instrument = list(scales = list(relevance_9 = list(type = "ordinal_integer"))))
  state$readiness <- data.frame(severity = "warning", code = "feedback_unassigned", path = "round.feedback", message_key = "readiness.feedback_unassigned", details = "", stringsAsFactors = FALSE)
  state$enrolled <- TRUE
  state
}
rounds_called <- function(state, name) Filter(function(x) identical(x[[1]], name), state$calls)

test_that("an item decision binds the analysis on screen and never another round's", {
  state <- rounds_state()
  current <- shiny::reactiveVal(rounds_round("round-1", 1L, "released"))
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() current(), lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE, zone = function() "Europe/Berlin"), {
    session$flushReact()
    expect_match(output$decision_form$html, "View the analysis of the selected round first.", fixed = TRUE)
    session$setInputs(read = 1)
    expect_identical(analysis()$id, "analysis-1")
    expect_identical(analysis()$round_id, "round-1")
    form <- output$decision_form$html
    # The item is named with its wording, here in the interface language.
    expect_match(form, "I001 \u00b7 First synthetic statement", fixed = TRUE)
    expect_false(grepl("I001 \u00b7 Erste", form, fixed = TRUE))
    expect_match(form, "I reviewed the item, its analysis and the decision<", fixed = TRUE)
    decided <- output$decisions
    expect_match(decided, "I002 \u00b7 Second synthetic statement", fixed = TRUE)
    expect_match(decided, "Rationale", fixed = TRUE)
    expect_match(decided, "2 Oct 2026, 12:00 (Europe/Berlin, UTC+2)", fixed = TRUE)
    # Selecting another round takes the analysis of the previous one off the screen.
    current(rounds_round("round-2", 2L, "analysed"))
    session$flushReact()
    expect_null(analysis())
    session$setInputs(decision_code = "I001", disposition = "rerate", decision_reason = "Rated again", decision_confirm = TRUE, decide = 1)
    expect_length(rounds_called(state, "record_item_decision"), 0L)
    expect_match(output$status, "View the analysis of the selected round first.", fixed = TRUE)
    # An analysis finished for round 1 while round 2 is selected is shown as
    # round 1's and takes no decision for round 2.
    analysis_job(list(id = "job", round_id = "round-1", number = 1L))
    state$operation <- data.frame(state = "succeeded", result_ref = "analysis-1")
    session$setInputs(poll = 1)
    expect_match(output$analysis$html, "Analysis of round 1", fixed = TRUE)
    session$setInputs(decide = 2)
    expect_length(rounds_called(state, "record_item_decision"), 0L)
    session$setInputs(read = 2)
    session$setInputs(decide = 3)
    recorded <- rounds_called(state, "record_item_decision")
    expect_length(recorded, 1L)
    expect_identical(recorded[[1]][2:5], list("analysis-2", "I001", "rerate", "Rated again"))
    expect_match(output$status, "Item decision saved: I001", fixed = TRUE)
  })
})

test_that("the analysis is a labelled table with statements, outcomes in words and free text summarised", {
  x <- list(id = "analysis-1", round_id = "round-1", number = 1L, data = rounds_analysis(), items = rounds_instrument()$items, language = "en")
  html <- as.character(analysis_view(x, "en"))
  expect_match(html, "<caption>Analysis of round 1</caption>", fixed = TRUE)
  for (label in c("Valid ratings", "Median", "Interquartile range (Q1\u2013Q3)", "In agreement range", "Rule outcome")) expect_match(html, label, fixed = TRUE)
  for (raw in c("n_valid", "p_agree", "stratum", "classification", "consensus_in", "not_rated", ">NA<", "item_code")) expect_false(grepl(raw, html, fixed = TRUE), info = raw)
  # One row per statement and rated dimension; free text is counted in one line.
  expect_identical(lengths(regmatches(html, gregexpr("<tr>", html, fixed = TRUE))), 3L)
  expect_match(html, "<span lang=\"en\">First synthetic statement</span>", fixed = TRUE)
  expect_match(html, "8 of 8", fixed = TRUE)
  expect_match(html, "6.8\u20138.2", fixed = TRUE)
  # Equal quartiles are one value.
  same <- x
  same$data$results$q3[3] <- same$data$results$q1[3]
  expect_match(as.character(analysis_view(same, "en")), "<td>5.5</td>", fixed = TRUE)
  expect_match(html, "75%", fixed = TRUE)
  expect_match(html, "Consensus for inclusion", fixed = TRUE)
  expect_match(html, "Insufficient data (fewer than 3 valid ratings)", fixed = TRUE)
  expect_match(html, "Free-text dimension \u201cComment\u201d: 2 contributions on 1 items.", fixed = TRUE)
  expect_match(html, "Agreement range: ratings from 7 to 9.", fixed = TRUE)
  fr <- as.character(analysis_view(x, "fr"))
  expect_match(fr, "7,5", fixed = TRUE)
  expect_match(fr, "75\u00a0%", fixed = TRUE)
  expect_match(fr, "Consensus pour l\u2019inclusion", fixed = TRUE)
  # Without a French version the study's default language is shown, never a translation.
  expect_match(fr, "<span lang=\"en\">First synthetic statement</span>", fixed = TRUE)
  expect_match(as.character(analysis_view(x, "de")), "<span lang=\"de\">Erste synthetische Aussage</span>", fixed = TRUE)
  # The rule outcome follows the protocol's group policy as recorded in the decision table.
  x$data$decisions$classification[1] <- "no_consensus"
  expect_match(as.character(analysis_view(x, "en")), "No consensus", fixed = TRUE)
  # A real analysis with stakeholder groups: the groups in a collapsible part.
  real <- list(number = 2L, data = delphyr::analyse_round(delphyr::demo_snapshot()), items = NULL)
  shown <- as.character(analysis_view(real, "en"))
  expect_match(shown, "<summary>Results by stakeholder group</summary>", fixed = TRUE)
  expect_match(shown, "Public contributors", fixed = TRUE)
  expect_match(shown, "\u2014", fixed = TRUE)
  expect_false(grepl("NA", gsub("NA[a-z]", "", shown), fixed = TRUE))
})

test_that("the feedback candidate is shown as participants will see it", {
  a <- delphyr::analyse_round(delphyr::demo_snapshot())
  draft <- delphyr::prepare_feedback(a, list(list(text = "A moderated summary of the comments", reviewed = TRUE, source_ref = "R1-001", kind = "summary")), list(group_statistics = FALSE, minimum_display_cell_n = 5L, complementary_suppression = TRUE))
  stored <- jsonlite::fromJSON(delphyr:::json(unclass(draft)))
  html <- as.character(feedback_view(list(content = stored, hash = draft$hash, state = "reviewed"), NULL, "en", free_scales = character()))
  expect_match(html, paste("Checksum:", substr(draft$hash, 1, 12), "\u00b7 Not released yet"), fixed = TRUE)
  expect_false(grepl(draft$hash, html, fixed = TRUE))
  expect_match(html, "group results are not shown", fixed = TRUE)
  expect_match(html, "Values based on fewer than 5 valid ratings are not shown.", fixed = TRUE)
  expect_match(html, "Results for participants", fixed = TRUE)
  expect_match(html, "Moderated summary (not a quotation):", fixed = TRUE)
  expect_match(html, "A moderated summary of the comments", fixed = TRUE)
  for (raw in c("$results", "analysis_hash", "suppressed", "n_valid")) expect_false(grepl(raw, html, fixed = TRUE), info = raw)
  # Cells below the display minimum are named as withheld, not as missing data.
  small <- delphyr::prepare_feedback(a, list(), list(group_statistics = TRUE, minimum_display_cell_n = 11L, complementary_suppression = TRUE))
  shown <- as.character(feedback_view(list(content = jsonlite::fromJSON(delphyr:::json(unclass(small))), hash = small$hash, state = "released"), NULL, "en"))
  expect_match(shown, "Not shown (fewer than 11 valid ratings)", fixed = TRUE)
  expect_match(shown, "Whole panel", fixed = TRUE)
  expect_match(shown, "This feedback contains no texts.", fixed = TRUE)
  expect_match(shown, "\u00b7 Released", fixed = TRUE)
})

test_that("released feedback is assigned from the service's list, also in a later session", {
  state <- rounds_state()
  state$released <- data.frame(round_number = 1L, feedback_id = "feedback-1", hash = "abcdef0123456789", assigned_round = NA_integer_, replacement_id = NA_character_, reason = NA_character_, impact_note = NA_character_, participant_note = NA_character_, corrected_at = NA_character_, is_correction = FALSE, released_at = "2026-10-03 17:49:00+00", stringsAsFactors = FALSE)
  current <- shiny::reactiveVal(rounds_round("round-2", 2L, "draft"))
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() current(), lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE, zone = function() "Europe/Berlin"), {
    session$flushReact()
    expect_match(output$body$html, "Feedback for this round", fixed = TRUE)
    choice <- output$assign_choice$html
    expect_match(choice, "Round 1 \u00b7 First release \u00b7 released 3 Oct 2026, 19:49 (Europe/Berlin, UTC+2)", fixed = TRUE)
    expect_false(grepl("abcdef", choice, fixed = TRUE))
    # No feedback was drafted in this session.
    expect_null(feedback())
    session$setInputs(assign_feedback = "feedback-1", assign = 1)
    assigned <- rounds_called(state, "assign_feedback")
    expect_length(assigned, 1L)
    expect_identical(assigned[[1]][2:3], list("round-2", "feedback-1"))
    expect_identical(output$status, "Feedback assigned.")
    session$setInputs(assign_feedback = "", assign = 2)
    expect_length(rounds_called(state, "assign_feedback"), 1L)
    expect_identical(output$status, "Choose released feedback first.")
    # The first round has no earlier feedback; an opened round takes none.
    current(rounds_round("round-1", 1L, "draft"))
    session$flushReact()
    expect_false(grepl("Feedback for this round", output$body$html, fixed = TRUE))
    current(rounds_round("round-2", 2L, "open"))
    session$flushReact()
    expect_false(grepl("Feedback for this round", output$body$html, fixed = TRUE))
  })
  state$released <- state$released[FALSE, ]
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-2", 2L, "review"), lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$assign_choice$html, "No released feedback of an earlier round exists yet.", fixed = TRUE)
    expect_false(grepl("proxy1-assign\"", output$assign_choice$html, fixed = TRUE))
  })
})

test_that("released feedback versions are named by round, order and release time", {
  p <- data.frame(
    round_number = c(1L, 1L, 1L, 2L), feedback_id = c("c", "a", "b", "d"), hash = c("hc", "ha", "hb", "hd"), assigned_round = c(NA, 2L, NA, NA),
    replacement_id = c(NA, "b", "c", NA), reason = c(NA, "Direction reversed", "Typo", NA), corrected_at = c(NA, "2026-10-04 08:00:00+00", "2026-10-05 08:00:00+00", NA),
    is_correction = c(TRUE, FALSE, TRUE, FALSE), stringsAsFactors = FALSE
  )
  v <- feedback_versions(p)
  expect_identical(v$version[match(c("a", "b", "c", "d"), v$feedback_id)], c(1L, 2L, 3L, 1L))
  # A correction was released when it replaced its predecessor, for that reason.
  expect_identical(v$released[v$feedback_id == "b"], "2026-10-04 08:00:00+00")
  expect_identical(v$rationale[v$feedback_id == "c"], "Typo")
  expect_true(is.na(v$released[v$feedback_id == "a"]))
  expect_identical(feedback_version_label(c(1L, 3L, NA), "en"), c("First release", "Correction 2", "\u2014"))
  expect_identical(feedback_version_label(2L, "de"), "Korrektur 1")
  labels <- released_feedback_label(v[v$feedback_id %in% c("a", "c"), ], "en", "UTC", assigned = TRUE)
  expect_identical(labels, c("Round 1 \u00b7 Correction 2 \u00b7 released 5 Oct 2026, 08:00 (UTC)", "Round 1 \u00b7 First release \u00b7 assigned to round 2"))
  expect_identical(nrow(feedback_versions(data.frame())), 0L)
})

test_that("multi-selects of released editorial versions explain themselves", {
  state <- rounds_state()
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-1", 1L, "analysed"), lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$released_choice$html, "No editorial version has been released yet", fixed = TRUE)
  })
  state$edits <- data.frame(edit_id = "edit-1", source_ref = "R1-001", kind = "summary", text = "A summary", stringsAsFactors = FALSE)
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-1", 1L, "analysed"), lang = function() "fr", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    html <- output$released_choice$html
    expect_match(html, "Versions \u00e9ditoriales \u00e0 inclure dans ce retour", fixed = TRUE)
    expect_match(html, "Choisir des r\u00e9sum\u00e9s publi\u00e9s ou des contributions expurg\u00e9es", fixed = TRUE)
  })
})

test_that("study information is chosen by version, the newest preselected and the choice kept", {
  state <- rounds_state()
  state$setup$consent_versions <- data.frame(id = c("consent-1", "consent-2"), locale = c("en", "de"), content = c("First synthetic information", "Zweite synthetische Information"), hash = c("c1", "c2"), created_at = c("2026-09-01 10:00:00+00", "2026-10-01 10:00:00+00"), stringsAsFactors = FALSE)
  language <- shiny::reactiveVal("en")
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-1", 1L, "released"), lang = function() language(), call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE, zone = function() "Europe/Berlin"), {
    session$flushReact()
    html <- output$consents$html
    expect_match(html, "<option value=\"consent-2\" selected>Version 2 \u00b7 German \u00b7 1 Oct 2026</option>", fixed = TRUE)
    expect_match(html, "Version 1 \u00b7 English \u00b7 1 Sept 2026|Version 1 \u00b7 English \u00b7 1 Sep 2026")
    expect_false(grepl("First synthetic information", html, fixed = TRUE))
    expect_match(output$consent_text$html, "Zweite synthetische Information", fixed = TRUE)
    session$setInputs(consent = "consent-1")
    expect_match(output$consent_text$html, "<blockquote class=\"del-consent\" lang=\"en\">First synthetic information</blockquote>", fixed = TRUE)
    language("fr")
    session$flushReact()
    expect_match(output$consents$html, "<option value=\"consent-1\" selected>Version 1 \u00b7 Anglais", fixed = TRUE)
  })
})

test_that("a round export states its content, needs a purpose and offers the download only when ready", {
  state <- rounds_state()
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-1", 1L, "released"), lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$body$html, "Export the data of round 1", fixed = TRUE)
    expect_match(output$export_group$html, "leaves the access control", fixed = TRUE)
    expect_match(output$export_group$html, "Purpose of the export", fixed = TRUE)
    expect_false(grepl("Download export", output$export_actions$html, fixed = TRUE))
    expect_false(grepl("Check operation", output$export_actions$html, fixed = TRUE))
    session$setInputs(export_purpose = "Too short", export = 1)
    expect_length(rounds_called(state, "request_export"), 0L)
    expect_match(output$status, "Enter the purpose of the export (10 to 500 characters).", fixed = TRUE)
    session$setInputs(export_purpose = "Replication of the round 1 analysis by the methods group", export = 2)
    requested <- rounds_called(state, "request_export")
    expect_length(requested, 1L)
    expect_identical(requested[[1]][[2]], "snapshot-1")
    expect_identical(requested[[1]]$purpose, "Replication of the round 1 analysis by the methods group")
    expect_match(output$export_actions$html, "Check operation", fixed = TRUE)
    expect_false(grepl("Download export", output$export_actions$html, fixed = TRUE))
    session$setInputs(export_poll = 1)
    expect_match(output$status, "Operation: Queued", fixed = TRUE)
    state$operation <- data.frame(state = "succeeded", result_ref = "artifact-1")
    session$setInputs(export_poll = 2)
    expect_match(output$export_actions$html, "Download export", fixed = TRUE)
    expect_false(grepl("export_poll", output$export_actions$html, fixed = TRUE))
    expect_identical(artifact()$id, "artifact-1")
  })
  # The protocol frozen with the round decides, not the current one: free text
  # added by a later amendment does not concern this round ...
  state$setup$protocol$instrument$scales$comment_text <- list(type = "free_text")
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-1", 1L, "released"), lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$export_group$html, "Purpose of the export", fixed = TRUE)
  })
  # ... while a round frozen with free text has no approved round export.
  state$setup$protocol$instrument$scales$comment_text <- NULL
  state$frozen$instrument$scales$comment_text <- list(type = "free_text")
  state$calls <- list()
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-1", 1L, "released"), lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$export_group$html, "the round export is not approved", fixed = TRUE)
    expect_false(grepl("Purpose of the export", output$export_group$html, fixed = TRUE))
    session$setInputs(export_purpose = "Replication of the round 1 analysis by the methods group", export = 1)
    expect_length(rounds_called(state, "request_export"), 0L)
  })
  # An account with the export and analysis rights but without study
  # leadership cannot read the round's protocol: nothing is offered that the
  # worker would refuse, until the listed round says whether it has free text.
  state$calls <- list()
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-1", 1L, "released"), lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE, capabilities = function() c("analyse", "export")), {
    session$flushReact()
    expect_match(output$body$html, "Export the data of round 1", fixed = TRUE)
    expect_match(output$export_group$html, "cannot be checked here. Export the study under Exports.", fixed = TRUE)
    expect_false(grepl("Purpose of the export", output$export_group$html, fixed = TRUE))
    session$setInputs(export_purpose = "Replication of the round 1 analysis by the methods group", export = 1)
    expect_length(rounds_called(state, "request_export"), 0L)
    expect_length(rounds_called(state, "get_round_instrument"), 0L)
    expect_length(rounds_called(state, "get_study_setup"), 0L)
  })
  for (flag in c(FALSE, TRUE)) {
    listed <- rounds_round("round-1", 1L, "released")
    listed$free_text <- flag
    shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() listed, lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE, capabilities = function() c("analyse", "export")), {
      session$flushReact()
      expect_identical(grepl("Purpose of the export", output$export_group$html, fixed = TRUE), !flag)
      expect_identical(grepl("the round export is not approved", output$export_group$html, fixed = TRUE), flag)
    })
  }
  # Without the export right there is no export at all.
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-1", 1L, "released"), lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE, capabilities = function() c("manage", "analyse")), {
    session$flushReact()
    expect_false(grepl("Export the data of round", output$body$html, fixed = TRUE))
  })
})

test_that("a new round is prepared with a deadline in the study's time zone and only when the previous one allows it", {
  state <- rounds_state()
  all <- shiny::reactiveVal(rounds_round("round-1", 1L, "open"))
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  utils::write.csv(data.frame(item_code = "I001", item_version = 1L, locale = c("de", "en"), text = c("Synthetisches Item", "Synthetic item"), dimension_code = "relevance", scale_code = "relevance_9", source_ref = "SRC", required = TRUE, display_order = 1L), path, row.names = FALSE)
  file <- data.frame(name = "items.csv", size = file.info(path)$size, datapath = path, type = "text/csv")
  state$setup$protocol <- delphyr::demo_protocol()
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-1", 1L, "open"), lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE, rounds = function() all(), zone = function() "Europe/Berlin"), {
    session$flushReact()
    expect_match(output$prepare_group$html, "A new round can be prepared once the feedback of round 1 has been released.", fixed = TRUE)
    all(rounds_round("round-1", 1L, "released"))
    session$flushReact()
    html <- output$prepare_group$html
    expect_match(html, "Prepare a new round", fixed = TRUE)
    expect_match(html, "Download the instrument of round 1 (CSV)", fixed = TRUE)
    expect_match(html, "id=\"proxy1-deadline_date\"", fixed = TRUE)
    expect_match(html, "Time zone of the study: Europe/Berlin", fixed = TRUE)
    expect_false(grepl("2026-12-01T18:00:00+01:00", html, fixed = TRUE))
    guide <- output$csv_guide$html
    expect_match(guide, "Columns of the instrument file", fixed = TRUE)
    expect_match(guide, "relevance_9 (relevance)", fixed = TRUE)
    expect_match(guide, "Language of the text: de, en", fixed = TRUE)
    session$setInputs(prepare = 1)
    expect_identical(output$status, "Validate an instrument file first.")
    session$setInputs(csv = file, validate = 1)
    expect_match(output$items$html, "Validated rows: 2; the first 20 are listed", fixed = TRUE)
    expect_match(output$items$html, "Synthetisches Item", fixed = TRUE)
    session$setInputs(consent = "consent-1", deadline_date = "2026-12-01", prepare = 2)
    expect_match(output$status, "^No round created: Enter a date")
    session$setInputs(deadline_time = "18:00", prepare = 3)
    prepared <- rounds_called(state, "prepare_round")
    expect_length(prepared, 1L)
    expect_identical(prepared[[1]][[4]], "consent-1")
    expect_identical(prepared[[1]][[5]], "2026-12-01T18:00:00+01:00")
    expect_match(output$status, "Round draft created.", fixed = TRUE)
    state$refuse <- "round.previous"
    session$setInputs(prepare = 4)
    expect_match(output$status, "^No round created: the feedback of the current round must be released first\\. Reference: [0-9a-f]{12}$")
    # The protocol's limit of rounds is respected.
    all(rbind(rounds_round("round-1", 1L, "finalized"), rounds_round("round-2", 2L, "finalized"), rounds_round("round-3", 3L, "released")))
    session$flushReact()
    expect_match(output$prepare_group$html, "The protocol allows at most 3 rounds.", fixed = TRUE)
  })
})

test_that("the instrument guide is translated and lists what the protocol admits", {
  p <- delphyr::demo_protocol()
  de <- as.character(instrument_guide(p, "de"))
  expect_match(de, "Spalten der Instrumentdatei", fixed = TRUE)
  expect_match(de, "<code>item_code</code>", fixed = TRUE)
  expect_match(de, "Sprache des Textes: de, en", fixed = TRUE)
  fr <- as.character(instrument_guide(p, "fr"))
  expect_match(fr, "Colonnes du fichier d\u2019instrument", fixed = TRUE)
  expect_match(fr, "Dimension \u00e9valu\u00e9e : relevance", fixed = TRUE)
  expect_match(as.character(instrument_guide(NULL, "en")), "Language of the text:<", fixed = TRUE)
})

test_that("a choice of editorial versions made in another study is never sent", {
  state <- rounds_state()
  chosen <- shiny::reactiveVal("A")
  base <- rounds_call(state)
  call <- function(name, ...) {
    switch(name,
      list_released_edits = if (identical(list(...)[[1]], "A")) data.frame(edit_id = "edit-A", source_ref = "R1-001", kind = "summary", text = "Summary of study A", stringsAsFactors = FALSE) else state$edits,
      create_feedback = {
        state$calls[[length(state$calls) + 1L]] <- list(name, ...)
        list(id = "feedback-new", hash = "h")
      },
      get_feedback_candidate = list(content = list(), hash = "h", state = "reviewed"),
      base(name, ...)
    )
  }
  round <- function() data.frame(id = paste0(chosen(), "-round-1"), number = 1L, state = "analysed", snapshot_id = paste0(chosen(), "-snapshot-1"), analysis_id = paste0(chosen(), "-analysis-1"), stringsAsFactors = FALSE)
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() chosen(), round = round, lang = function() "en", call = call, services = rounds_services(), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$released_choice$html, "Summary of study A", fixed = TRUE)
    session$setInputs(released_edits = "edit-A", correction_edits = "edit-A")
    chosen("B")
    session$flushReact()
    # Study B has no released version: a note replaces the list, and the
    # browser still holds the choice made in study A.
    expect_match(output$released_choice$html, "No editorial version has been released yet", fixed = TRUE)
    expect_identical(input$released_edits, "edit-A")
    session$setInputs(draft = 1)
    session$setInputs(correction_target = "feedback-B", correction_draft = 1)
    created <- rounds_called(state, "create_feedback")
    expect_length(created, 2L)
    expect_identical(created[[1]][[2]], "B-analysis-1")
    expect_identical(created[[1]]$released_edits, character())
    expect_identical(created[[2]]$released_edits, character())
    expect_match(output$status, "Corrected version created for review.", fixed = TRUE)
  })
})

test_that("released feedback is assigned once, and the round then says so instead of offering it again", {
  state <- rounds_state()
  state$released <- data.frame(round_number = 1L, feedback_id = "feedback-1", hash = "abcdef0123456789", assigned_round = NA_integer_, replacement_id = NA_character_, reason = NA_character_, impact_note = NA_character_, participant_note = NA_character_, corrected_at = NA_character_, is_correction = FALSE, stringsAsFactors = FALSE)
  services <- rounds_services(c(rounds_operation_names, "get_round_readiness"))
  unassigned <- state$readiness
  current <- shiny::reactiveVal(rounds_round("round-2", 2L, "draft"))
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() current(), lang = function() "en", call = rounds_call(state), services = services, refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$assign_choice$html, "id=\"proxy1-assign\"", fixed = TRUE)
    expect_match(output$assign_choice$html, "Assign it before the round opens.", fixed = TRUE)
    session$setInputs(assign_feedback = "another-study-feedback", assign = 1)
    expect_length(rounds_called(state, "assign_feedback"), 0L)
    expect_identical(output$status, "Choose released feedback first.")
    session$setInputs(assign_feedback = "feedback-1", assign = 2)
    expect_length(rounds_called(state, "assign_feedback"), 1L)
    expect_identical(output$status, "Feedback assigned.")
    choice <- output$assign_choice$html
    expect_match(choice, "Released feedback is assigned to this round.", fixed = TRUE)
    expect_false(grepl("proxy1-assign\"", choice, fixed = TRUE))
    expect_false(grepl("Assign it before the round opens.", choice, fixed = TRUE))
    # A click from a view shown before assigns nothing a second time.
    session$setInputs(assign = 3)
    expect_length(rounds_called(state, "assign_feedback"), 1L)
    expect_match(output$status, "^Released feedback is assigned to this round\\.")
    # A change of state keeps the assignment and reads nothing again.
    read <- length(rounds_called(state, "get_round_readiness"))
    current(rounds_round("round-2", 2L, "review"))
    session$flushReact()
    expect_match(output$assign_choice$html, "Released feedback is assigned to this round.", fixed = TRUE)
    expect_length(rounds_called(state, "get_round_readiness"), read)
  })
  # Another session, or the same page after a reload, sees the assignment at once.
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-2", 2L, "approved"), lang = function() "en", call = rounds_call(state), services = services, refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$assign_choice$html, "Released feedback is assigned to this round.", fixed = TRUE)
    expect_false(grepl("proxy1-assign_feedback", output$assign_choice$html, fixed = TRUE))
  })
  # Another manager assigns while this view still offers the assignment.
  state$readiness <- unassigned
  state$calls <- list()
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-2", 2L, "draft"), lang = function() "en", call = rounds_call(state), services = services, refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$assign_choice$html, "id=\"proxy1-assign\"", fixed = TRUE)
    state$readiness <- unassigned[FALSE, ]
    session$setInputs(assign_feedback = "feedback-1", assign = 1)
    expect_length(rounds_called(state, "assign_feedback"), 0L)
    expect_match(output$status, "^Released feedback is assigned to this round\\.")
    expect_false(grepl("proxy1-assign\"", output$assign_choice$html, fixed = TRUE))
  })
  # The service assigns feedback to the enrolled members; without any, the
  # round stays without feedback and says so.
  state$readiness <- unassigned
  state$enrolled <- FALSE
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-2", 2L, "draft"), lang = function() "en", call = rounds_call(state), services = services, refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    session$setInputs(assign_feedback = "feedback-1", assign = 1)
    expect_identical(output$status, "No feedback was assigned: the round has no enrolled panel members yet. Enroll them first.")
    expect_match(output$assign_choice$html, "id=\"proxy1-assign\"", fixed = TRUE)
  })
})

test_that("a withdrawn round offers no correction and no analysis step", {
  state <- rounds_state()
  # Round 2 was withdrawn and prepared again; the conducted round 2 released feedback.
  state$released <- data.frame(round_number = c(1L, 2L), feedback_id = c("feedback-1", "feedback-2"), hash = c("h1", "h2"), assigned_round = c(2L, NA), replacement_id = NA_character_, reason = NA_character_, impact_note = NA_character_, participant_note = NA_character_, corrected_at = NA_character_, is_correction = FALSE, stringsAsFactors = FALSE)
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-2-withdrawn", 2L, "cancelled"), lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    body <- output$body$html
    for (control in c("Correct released feedback", "Review and release feedback", "Feedback for this round", "Item decisions", "Export the data of round")) expect_false(grepl(control, body, fixed = TRUE), info = control)
    expect_false(grepl("An analysis is possible", output$analysis_actions$html, fixed = TRUE))
    expect_false(grepl("del-note", output$analysis_actions$html, fixed = TRUE))
  })
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() rounds_round("round-2", 2L, "released"), lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$body$html, "Correct released feedback", fixed = TRUE)
  })
})

test_that("analysts view analyses but leave requesting them to the study lead", {
  state <- rounds_state()
  frozen <- rounds_round("round-1", 1L, "frozen")
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() frozen, lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE, capabilities = function() "analyse"), {
    session$flushReact()
    actions <- output$analysis_actions$html
    expect_false(grepl("Request analysis", actions, fixed = TRUE))
    expect_match(actions, "The study lead requests the analysis of this round.", fixed = TRUE)
    session$setInputs(analyse = 1)
    expect_length(rounds_called(state, "request_analysis"), 0L)
  })
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() frozen, lang = function() "en", call = rounds_call(state), services = rounds_services(), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$analysis_actions$html, "Request analysis", fixed = TRUE)
    session$setInputs(analyse = 1)
    expect_length(rounds_called(state, "request_analysis"), 1L)
  })
})
