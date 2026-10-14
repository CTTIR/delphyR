management_names <- c("get_capabilities", "get_study_setup", "list_rounds", "transition_round", "list_studies", "complete_study", "enroll_panel", "change_round_deadline", "get_operations_status")
management_services <- function(names = management_names) stats::setNames(rep(list(function(...) NULL), length(names)), names)
management_round <- function(number, state) {
  data.frame(id = paste0("round-", number), number = number, state = state, instrument_hash = paste0("hash-", number), deadline = as.POSIXct("2026-12-01 17:00:00", tz = "UTC"), snapshot_id = NA_character_, analysis_id = NA_character_, stringsAsFactors = FALSE)
}
management_refusal <- function(code, path) structure(list(message = paste(code, path), call = NULL, code = code, path = path), class = c(code, "delphyr_error", "error", "condition"))
management_fake <- function(state) {
  function(name, ...) {
    state$calls[[length(state$calls) + 1L]] <- list(name, ...)
    switch(name,
      get_capabilities = state$caps,
      get_study_setup = list(protocol = list(study = list(timezone = "Europe/Berlin"))),
      list_rounds = state$rounds,
      list_studies = data.frame(id = c("study", "other"), title = "Synthetic", state = c(state$study_state, "active"), stringsAsFactors = FALSE),
      transition_round = {
        if (!is.null(state$refuse)) stop(state$refuse)
        list(id = list(...)[[1]], state = list(...)[[2]])
      },
      complete_study = {
        if (!is.null(state$refuse)) stop(state$refuse)
        state$study_state <- "completed"
        list(id = "study", state = "completed")
      },
      get_operations_status = state$status,
      enroll_panel = list(id = list(...)[[1]], added = 0L),
      stop("Unexpected service ", name)
    )
  }
}
management_state <- function(rounds, caps = c("manage", "analyse", "export")) {
  state <- new.env()
  state$calls <- list()
  state$caps <- caps
  state$rounds <- rounds
  state$study_state <- "active"
  state
}
management_called <- function(state, name) Filter(function(x) identical(x[[1]], name), state$calls)

test_that("only the state changes the service admits are offered, the forward step first", {
  expect_identical(round_targets("draft"), c("review", "cancelled"))
  expect_identical(round_targets("review"), c("approved", "cancelled"))
  expect_identical(round_targets("approved"), c("open", "cancelled"))
  expect_identical(round_targets("open"), "closed")
  expect_identical(round_targets("analysed"), "finalized")
  expect_identical(round_targets("released"), "finalized")
  for (state in c("closed", "frozen", "finalized", "cancelled", "unknown", NA)) expect_identical(round_targets(state), character(), info = state)
  expect_identical(round_targets(NULL), character())
  expect_match(round_next_step("closed", "en"), "Freeze it", fixed = TRUE)
  expect_match(round_next_step("frozen", "de"), "Analyse", fixed = TRUE)
  expect_identical(round_next_step("draft", "en"), "No further state change is possible for this round.")
  expect_identical(round_choice_label(management_round(1L, "released"), "en"), "Round 1 \u00b7 Feedback released")
  expect_identical(round_choice_label(management_round(1L, "open")[FALSE, ], "en"), character())
})

test_that("round controls follow the selected round's state", {
  state <- management_state(rbind(management_round(1L, "released"), management_round(2L, "open")))
  shiny::testServer(delphyrApp:::management_server, args = list(study = function() "study", lang = function() "en", call = management_fake(state), services = management_services()), {
    session$flushReact()
    expect_match(output$body$html, "<option value=\"round-1\">Round 1 \u00b7 Feedback released</option>", fixed = TRUE)
    session$setInputs(round = "round-1")
    html <- output$round_actions$html
    # From released only finalization is possible; nothing else is preselected.
    expect_match(html, "<option value=\"finalized\" selected>Finalized</option>", fixed = TRUE)
    expect_false(grepl("value=\"review\"", html, fixed = TRUE))
    expect_false(grepl("Enroll eligible panel members", html, fixed = TRUE))
    expect_false(grepl("Change the deadline", html, fixed = TRUE))
    expect_match(html, "class=\"del-actions\"", fixed = TRUE)
    session$setInputs(round = "round-2")
    html <- output$round_actions$html
    expect_match(html, "<option value=\"closed\" selected>Closed</option>", fixed = TRUE)
    expect_false(grepl("value=\"cancelled\"", html, fixed = TRUE))
    expect_match(html, "Enroll eligible panel members", fixed = TRUE)
    expect_match(html, "Change the deadline", fixed = TRUE)
  })
  state <- management_state(management_round(1L, "closed"))
  shiny::testServer(delphyrApp:::management_server, args = list(study = function() "study", lang = function() "en", call = management_fake(state), services = management_services()), {
    session$flushReact()
    session$setInputs(round = "round-1")
    html <- output$round_actions$html
    expect_false(grepl("Change state", html, fixed = TRUE))
    expect_match(html, "The round is closed. Freeze it under Analysis and subsequent round to analyse it.", fixed = TRUE)
  })
})

test_that("refusals of a state change say what happened and quote a reference", {
  state <- management_state(management_round(1L, "open"))
  shiny::testServer(delphyrApp:::management_server, args = list(study = function() "study", lang = function() "en", call = management_fake(state), services = management_services()), {
    session$flushReact()
    session$setInputs(round = "round-1", target = "closed", reason = "  ", confirm = TRUE, transition = 1)
    expect_identical(output$status, "A rationale and confirmation are required.")
    state$refuse <- management_refusal("DEL_CONFLICT", "round.transition")
    session$setInputs(reason = "All members submitted", transition = 2)
    expect_match(output$status, "^This transition is not possible in the round\u2019s current state, or the round has changed in the meantime\\. Reference: [0-9a-f]{12}$")
    state$refuse <- management_refusal("DEL_VALIDATION", "round.readiness:no_enrollments")
    session$setInputs(transition = 3)
    expect_match(output$status, "^The round is not ready yet\\. The readiness review lists the findings\\. Reference: [0-9a-f]{12}$")
    expect_match(localize_status(output$status, "de"), "^Die Runde ist noch nicht bereit\\..* Referenz: [0-9a-f]{12}$")
    # A confirmed change clears the rationale so that it is not reused.
    state$refuse <- NULL
    session$setInputs(transition = 4)
    expect_identical(output$status, "State change confirmed.")
    expect_identical(management_called(state, "transition_round")[[1]][[5]], "All members submitted")
  })
})

test_that("completing the study has its own rationale and confirmation and is offered only after the last round", {
  state <- management_state(rbind(management_round(1L, "released"), management_round(2L, "finalized")))
  shiny::testServer(delphyrApp:::management_server, args = list(study = function() "study", lang = function() "en", call = management_fake(state), services = management_services()), {
    session$flushReact()
    html <- output$completion$html
    expect_match(html, "<h3>Complete the study</h3>", fixed = TRUE)
    expect_match(html, "cannot be undone", fixed = TRUE)
    expect_match(html, "id=\"proxy1-complete_reason\"", fixed = TRUE)
    expect_match(html, "I complete the whole study for good", fixed = TRUE)
    expect_false(grepl("Complete study", output$body$html, fixed = TRUE))
    # The round transition's rationale and confirmation do not complete the study.
    session$setInputs(round = "round-2", reason = "Second round is the final round", confirm = TRUE, complete = 1)
    expect_length(management_called(state, "complete_study"), 0L)
    expect_identical(output$completion_status, "A rationale and confirmation are required.")
    session$setInputs(complete_reason = "Two rounds completed; remaining dissent is documented.", complete_confirm = FALSE, complete = 2)
    expect_length(management_called(state, "complete_study"), 0L)
    state$refuse <- management_refusal("DEL_VALIDATION", "completion.decisions")
    session$setInputs(complete_confirm = TRUE, complete = 3)
    expect_match(output$completion_status, "^Not completed: every item of the last round needs a decision of the study team\\. Reference: [0-9a-f]{12}$")
    state$refuse <- NULL
    session$setInputs(complete = 4)
    done <- management_called(state, "complete_study")
    expect_length(done, 2L)
    expect_identical(done[[2]][2:3], list("study", "Two rounds completed; remaining dissent is documented."))
    expect_identical(output$completion_status, "Study completed.")
    expect_match(output$completion$html, "The study is completed.", fixed = TRUE)
    expect_false(grepl("complete_reason", output$completion$html, fixed = TRUE))
  })
  state <- management_state(rbind(management_round(1L, "released"), management_round(2L, "open")))
  shiny::testServer(delphyrApp:::management_server, args = list(study = function() "study", lang = function() "en", call = management_fake(state), services = management_services()), {
    session$flushReact()
    expect_match(output$completion$html, "once its last round is finalized", fixed = TRUE)
    expect_false(grepl("complete_reason", output$completion$html, fixed = TRUE))
  })
})

test_that("background work is named in words, waits are shown only for waiting work, and nothing carries over to another study", {
  state <- management_state(management_round(1L, "open"))
  state$status <- list(
    jobs = data.frame(type = c("analysis", "export", "export"), profile = c("analysis", "research_round", "study_summary"), state = c("running", "succeeded", "queued"), n = c(1L, 1L, 2L), oldest_waiting_seconds = c(0L, 0L, 300L), error_codes = c(NA, NA, "DEL_RENDER"), stringsAsFactors = FALSE),
    messages = data.frame(state = c("queued", "recorded"), n = c(3L, 8L), oldest_waiting_seconds = c(45L, 0L), stringsAsFactors = FALSE), uncertain_deliveries = 0L
  )
  chosen <- shiny::reactiveVal("study")
  shiny::testServer(delphyrApp:::management_server, args = list(study = function() chosen(), lang = function() "en", call = management_fake(state), services = management_services()), {
    session$flushReact()
    session$setInputs(background_load = 1)
    jobs <- output$background_jobs
    expect_match(jobs, "Export: Round data (pseudonymized)", fixed = TRUE)
    expect_match(jobs, "Export: Aggregated study summary", fixed = TRUE)
    expect_false(grepl("research_round", jobs, fixed = TRUE))
    expect_match(jobs, "Longest waiting time", fixed = TRUE)
    expect_match(jobs, "5 min", fixed = TRUE)
    # No waiting time for running or finished work, and no error code where none was recorded.
    expect_identical(lengths(regmatches(jobs, gregexpr("\u2014", jobs))), 4L)
    expect_match(jobs, "DEL_RENDER", fixed = TRUE)
    messages <- output$background_messages
    expect_match(messages, "Message state", fixed = TRUE)
    expect_match(messages, "45 s", fixed = TRUE)
    chosen("other")
    session$flushReact()
    expect_null(background())
    expect_error(output$background_jobs)
  })
  expect_identical(format_wait(c(0, 59, 150, 7300, NA), "de"), c("0 s", "59 s", "2 min", "2 h", "\u2014"))
  expect_identical(job_profile_label(c("research_round", "contacts_restricted", "new_profile"), "de"), c("Rundendaten (pseudonymisiert)", "Kontaktdaten", "New profile"))
})

test_that("analysts read rounds and analyses without the controls of study leadership", {
  expect_true("section-management" %in% workspace_sections("analyse", "en")$id)
  expect_identical(workspace_sections("analyse", "de")$label[workspace_sections("analyse", "de")$id == "section-management"], "Runden und Auswertung")
  expect_false("section-management" %in% workspace_sections(c("export", "audit"), "en")$id)
  expect_match(workspace_intro("analyse", "en"), "Read the rounds and analyses", fixed = TRUE)
  expect_match(workspace_intro("analyse", "en"), "exports your role permits", fixed = TRUE)
  expect_match(workspace_intro("export", "fr"), "Demandez les exports", fixed = TRUE)
  state <- management_state(rbind(management_round(1L, "released"), management_round(2L, "closed")), caps = "analyse")
  shiny::testServer(delphyrApp:::management_server, args = list(study = function() "study", lang = function() "en", call = management_fake(state), services = management_services()), {
    session$flushReact()
    html <- output$body$html
    expect_match(html, "Rounds and analysis", fixed = TRUE)
    expect_match(html, "You can read the rounds and their analyses.", fixed = TRUE)
    expect_false(grepl("Status of background work", html, fixed = TRUE))
    session$setInputs(round = "round-2")
    expect_error(output$round_actions)
    expect_error(output$completion)
    session$setInputs(target = "finalized", reason = "Not allowed", confirm = TRUE, transition = 1, complete_reason = "Not allowed", complete_confirm = TRUE, complete = 1)
    expect_length(management_called(state, "transition_round"), 0L)
    expect_length(management_called(state, "complete_study"), 0L)
    # The protocol is read with study leadership only; times are then in UTC.
    expect_length(management_called(state, "get_study_setup"), 0L)
    expect_match(output$rounds, "1 Dec 2026, 17:00 (UTC)", fixed = TRUE)
  })
  analysed <- data.frame(id = "round-1", number = 1L, state = "analysed", snapshot_id = "snapshot-1", analysis_id = "analysis-1", stringsAsFactors = FALSE)
  names <- c("freeze_round", "request_analysis", "get_operation", "get_analysis", "create_feedback", "get_feedback_candidate", "release_feedback", "assign_feedback", "request_export", "download_artifact", "get_study_setup", "prepare_round", "record_item_decision", "list_item_decisions", "get_round_instrument")
  calls <- character()
  call <- function(name, ...) {
    calls <<- c(calls, name)
    switch(name,
      list_item_decisions = data.frame(round_number = 1L, item_code = "I001", disposition = "retain", reason = "Kept", decided_at = NA_character_),
      get_analysis = list(results = data.frame(item_code = "I001", stratum = "overall", n_valid = 8L, n_assigned = 8L, classification = "consensus_in"), decisions = data.frame(item_code = "I001", dimension_code = "relevance", classification = "consensus_in")),
      stop("unexpected service ", name)
    )
  }
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() analysed, lang = function() "en", call = call, services = stats::setNames(rep(list(function(...) NULL), length(names)), names), refresh = function() NULL, allowed = function() TRUE, capabilities = function() "analyse"), {
    session$flushReact()
    expect_match(output$analysis_actions$html, "View analysis", fixed = TRUE)
    expect_false(grepl("Freeze round", output$analysis_actions$html, fixed = TRUE))
    body <- output$body$html
    expect_match(body, "Item decisions", fixed = TRUE)
    for (control in c("Review and release feedback", "Correct released feedback", "Feedback for this round", "Export the data of round")) expect_false(grepl(control, body, fixed = TRUE), info = control)
    expect_error(output$prepare_group)
    expect_match(output$decision_form$html, "Item decisions are recorded by the study lead.", fixed = TRUE)
    expect_match(output$decisions, "Kept", fixed = TRUE)
    session$setInputs(read = 1)
    expect_match(output$analysis$html, "Analysis of round 1", fixed = TRUE)
    # The statement wording is read with study leadership only.
    expect_false("get_round_instrument" %in% calls)
    expect_false("get_study_setup" %in% calls)
  })
  # Study leadership without the analysis right is not offered what needs it.
  closed <- data.frame(id = "round-1", number = 1L, state = "closed", snapshot_id = NA_character_, analysis_id = NA_character_, stringsAsFactors = FALSE)
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = function() closed, lang = function() "en", call = function(name, ...) if (name == "list_item_decisions") data.frame() else list(protocol = list(), consent_versions = data.frame(id = character(), locale = character(), content = character())), services = stats::setNames(rep(list(function(...) NULL), length(names)), names), refresh = function() NULL, allowed = function() TRUE, capabilities = function() "manage"), {
    session$flushReact()
    actions <- output$analysis_actions$html
    expect_match(actions, "Freeze round", fixed = TRUE)
    expect_false(grepl("Request analysis", actions, fixed = TRUE))
    expect_match(actions, "need the right to analyse", fixed = TRUE)
  })
})

test_that("a failed reading after a change of study leaves nothing of the previous study on screen", {
  state <- management_state(rbind(management_round(1L, "released"), management_round(2L, "open")))
  fake <- management_fake(state)
  other <- data.frame(id = c("other-1", "other-2"), number = 1:2, state = c("released", "draft"), instrument_hash = "hash-o", deadline = as.POSIXct("2026-12-01 17:00:00", tz = "UTC"), snapshot_id = NA_character_, analysis_id = NA_character_, stringsAsFactors = FALSE)
  refuse <- TRUE
  call <- function(name, ...) {
    if (identical(name, "list_rounds") && identical(list(...)[[1]], "other")) {
      if (refuse) stop(management_refusal("DEL_FORBIDDEN", "authorization"))
      return(other)
    }
    fake(name, ...)
  }
  chosen <- shiny::reactiveVal("study")
  shiny::testServer(delphyrApp:::management_server, args = list(study = function() chosen(), lang = function() "en", call = call, services = management_services()), {
    session$flushReact()
    session$setInputs(round = "round-2")
    expect_true(allowed())
    expect_match(output$round_actions$html, "State of round 2", fixed = TRUE)
    chosen("other")
    session$flushReact()
    expect_false(allowed())
    expect_identical(nrow(rounds()), 0L)
    expect_identical(timezone(), "UTC")
    expect_true(is.na(study_state()))
    expect_error(output$body)
    expect_error(output$round_actions)
    expect_error(output$completion)
    expect_match(output$status, "Reference: [0-9a-f]{12}$")
    # Read successfully, the other study shows its own newest round, not the
    # round chosen in the previous study.
    refuse <<- FALSE
    chosen("study")
    session$flushReact()
    chosen("other")
    session$flushReact()
    expect_true(allowed())
    expect_match(output$body$html, "<option value=\"other-2\" selected>", fixed = TRUE)
    expect_false(grepl("round-1", output$body$html, fixed = TRUE))
  })
})

test_that("the completion has its own status, which does not decide whether the section card is shown", {
  ui <- management_ui("management")
  classes <- vapply(ui$children, function(x) if (inherits(x, "shiny.tag")) paste(x$attribs$class, collapse = " ") else "", character(1))
  # The card is dropped only while the body and the section's own status are empty.
  expect_identical(sum(classes == "del-status"), 1L)
  expect_match(as.character(ui), "id=\"management-completion_status\"", fixed = TRUE)
})

test_that("readiness details are given in words", {
  codes <- c("protocol_superseded", "group_below_minimum", "panel_below_minimum", "panelists_not_enrolled", "translation_missing", "consent_language", "no_items", "dimension_unknown")
  details <- c("round: version 1; current: version 2", "public_contributors: 3 < 10", "8 < 10", "2", "fr,de", "it", "", "relevance_7")
  expect_identical(readiness_detail(codes, details, "en"), c("Round: version 1; current: version 2", "Public contributors: 3 enrolled, minimum valid n 10", "8 enrolled, minimum valid n 10", "2 not yet enrolled", "French, German", "it", "\u2014", "relevance_7"))
  expect_identical(readiness_detail("protocol_superseded", "round: version 1; current: version 2", "fr"), "Tour : version 1 ; actuelle : version 2")
  expect_identical(language_name(c("de", "en", "xx"), "fr"), c("Allemand", "Anglais", "xx"))
})
