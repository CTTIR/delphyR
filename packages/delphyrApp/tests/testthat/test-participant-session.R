session_questionnaire <- function(state = "eligible", accepted = TRUE, round_state = "open") {
  list(
    protocol = list(
      study = list(timezone = "Europe/Berlin", default_language = "en"),
      instrument = list(
        dimensions = list(list(code = "relevance", scale = "relevance_9")),
        scales = list(relevance_9 = list(type = "ordinal_integer", values = 1:9, anchors = list(low = "not relevant", high = "extremely relevant"), missing_options = "unable_to_judge"))
      )
    ),
    round = list(id = "round-1", number = 1L, state = round_state, in_time = TRUE, deadline = "2026-12-10T17:00:00Z", study_id = "study-A"),
    enrollment = list(id = "enrollment-A", state = state),
    consent = list(id = "consent", locale = "en", content = "Synthetic study information.", accepted = accepted),
    receipt = data.frame(),
    items = data.frame(
      id = c("I001-relevance", "I002-relevance"), item_code = c("I001", "I002"), item_version = 1L, dimension_code = "relevance", scale_code = "relevance_9",
      texts = c('{"en":"Statement I001"}', '{"en":"Statement I002"}'), required = TRUE, display_order = 1:2, stringsAsFactors = FALSE
    ),
    responses = data.frame(round_item_id = character(), revision = integer(), status = character(), value_int = integer(), value_text = character(), stringsAsFactors = FALSE)
  )
}
del_error <- function(code, path) structure(list(message = paste(code, path), call = NULL, code = code, path = path), class = c(code, "delphyr_error", "error", "condition"))
# A stand-in for the services of one member in two studies.
session_services <- function(q = session_questionnaire()) {
  s <- new.env()
  s$q <- q
  s$calls <- list()
  s$fail <- list()
  s$rounds <- list(
    `study-A` = data.frame(id = "enrollment-A", number = 1L, state = "eligible", round_state = "open", stringsAsFactors = FALSE),
    `study-B` = data.frame(id = "enrollment-B", number = 1L, state = "eligible", round_state = "open", stringsAsFactors = FALSE)
  )
  s$call <- function(name, ...) {
    arguments <- list(...)
    s$calls[[length(s$calls) + 1L]] <- c(list(name), arguments)
    if (!is.null(s$fail[[name]])) stop(s$fail[[name]])
    switch(name,
      get_capabilities = "panel",
      list_enrollments = s$rounds[[arguments[[1]]]],
      get_questionnaire = s$q,
      get_feedback = NULL,
      save_response = {
        s$q$responses <- rbind(s$q$responses[s$q$responses$round_item_id != arguments[[2]], , drop = FALSE], data.frame(round_item_id = arguments[[2]], revision = arguments[[4]] + 1L, status = arguments[[3]]$status, value_int = as.integer(arguments[[3]]$value), value_text = NA_character_, stringsAsFactors = FALSE))
        list(revision = arguments[[4]] + 1L, saved_at = "2026-10-05 12:00:00+00")
      },
      record_consent = {
        if (isTRUE(arguments[[3]])) {
          s$q$consent$accepted <- TRUE
          s$q$consent$recorded_at <- "2026-10-05 12:03:00+00"
        }
        list(id = if (isTRUE(arguments[[3]])) "9c1d2e3f-6a7b-4c8d-9e0f-1a2b3c4d5e6f" else "7e6d5c4b-3a29-4180-9f7e-6d5c4b3a2910")
      },
      submit_round = {
        s$q$enrollment$state <- "submitted"
        s$q$receipt <- data.frame(id = "4f2a9c1e-77b0-4d3e-9a51-0c6e2b8d1f37", submitted_at = "2026-10-05 12:03:00+00", stringsAsFactors = FALSE)
        list(id = s$q$receipt$id, submitted_at = s$q$receipt$submitted_at)
      },
      withdraw_participation = list(id = "5d0f3c2a-9b7e-4f51-8a3c-2e6b1d4f7a90"),
      write_participant_feedback = stop("unexpected download"),
      stop("unexpected call: ", name)
    )
  }
  s
}
called <- function(s, name) Filter(function(x) identical(x[[1]], name), s$calls)
text_of <- function(html) trimws(gsub("[[:space:]]+", " ", gsub("<[^>]+>", " ", html)))

test_that("another study never keeps the previous study's questionnaire or withdrawal target", {
  s <- session_services()
  selected <- shiny::reactiveVal("study-A")
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() selected(), lang = function() "en", call = s$call, withdrawal_available = TRUE, autosave_ms = 60000), {
    session$setInputs(enrollment = "enrollment-A", load = 1)
    expect_false(is.null(q()))
    session$setInputs(`item_1_1-value` = "6")
    selected("study-B")
    session$flushReact()
    # A pending entry was saved to its own study first; then nothing remains.
    expect_identical(called(s, "save_response")[[1]][[2]], "enrollment-A")
    expect_null(q())
    expect_null(view())
    expect_length(editors(), 0L)
    expect_error(output$questionnaire)
    session$setInputs(withdraw_confirm = TRUE, withdraw = 1)
    expect_identical(called(s, "withdraw_participation")[[1]][[2]], "study-B")
  })
})

test_that("a change of the interface language keeps receipts and calls no service", {
  s <- session_services(session_questionnaire(accepted = FALSE))
  language <- shiny::reactiveVal("en")
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study-A", lang = function() language(), call = s$call, withdrawal_available = TRUE), {
    session$setInputs(enrollment = "enrollment-A", load = 1)
    session$setInputs(consent_check = TRUE, consent = 1)
    expect_identical(output$status, "Consent saved. Receipt: 9c1d2e3f")
    before <- length(s$calls)
    language("de")
    session$flushReact()
    expect_identical(output$status, "Einwilligung gespeichert. Beleg: 9c1d2e3f")
    expect_identical(length(s$calls), before)
    language("fr")
    session$flushReact()
    expect_identical(output$status, "Consentement enregistr\u00e9. Re\u00e7u : 9c1d2e3f")
  })
})

test_that("an expired sign-in is named as such, also for a download", {
  s <- session_services()
  s$fail$get_capabilities <- del_error("DEL_UNAUTHORIZED", "session")
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study-A", lang = function() "en", call = s$call, capabilities_available = TRUE), {
    session$flushReact()
    expect_match(output$status, "^Your sign-in has expired\\. Reload the page and sign in again\\..* Reference: [0-9a-f]{12}$")
  })
  s <- session_services()
  s$fail$write_participant_feedback <- del_error("DEL_UNAUTHORIZED", "session")
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study-A", lang = function() "en", call = s$call, feedback_download_available = TRUE), {
    session$setInputs(enrollment = "enrollment-A", load = 1)
    expect_error(output$feedback_download)
    session$flushReact()
    expect_match(output$status, "^Your sign-in has expired")
  })
})

test_that("a round that has not been opened is neither offered nor preselected nor loaded", {
  rounds <- data.frame(id = c("e1", "e2", "e3"), number = 1:3, state = c("submitted", "eligible", "eligible"), round_state = c("released", "approved", "draft"), stringsAsFactors = FALSE)
  shown <- participant_rounds(rounds)
  expect_identical(shown$id, "e1")
  expect_identical(current_enrollment(shown), "e1")
  expect_identical(names(round_choices(shown, "en")), "Round 1 \u00b7 Feedback released \u00b7 Submitted")
  s <- session_services()
  s$rounds$`study-A` <- rounds
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study-A", lang = function() "en", call = s$call), {
    session$setInputs(enrollment = "e3", load = 1)
    expect_length(called(s, "get_questionnaire"), 0L)
  })
  s$rounds$`study-A` <- rounds[2:3, ]
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study-A", lang = function() "en", call = s$call), {
    session$flushReact()
    expect_identical(output$status, "No round has been opened yet.")
  })
})

test_that("before consent the information is open, answers wait, and consent or a refusal is recorded", {
  s <- session_services(session_questionnaire(accepted = FALSE))
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study-A", lang = function() "en", call = s$call), {
    session$setInputs(enrollment = "enrollment-A", load = 1)
    consent <- output$consent_area$html
    # The information is shown in full, not as a disclosure that the page
    # would remember as opened for the one after consent.
    expect_match(consent, "</h4>\\s*<p class=\"del-consent\" lang=\"en\">Synthetic study information.</p>")
    expect_false(grepl("<details", consent, fixed = TRUE))
    expect_match(consent, "I have read the study information above and consent to take part.", fixed = TRUE)
    expect_match(consent, "Give consent", fixed = TRUE)
    expect_match(consent, "Do not consent", fixed = TRUE)
    expect_match(text_of(consent), "use \u201cEnd participation\u201d at the end of this page", fixed = TRUE)
    # The statements are shown but cannot be answered yet, and say why.
    expect_match(output[["slot_1-form"]]$html, "<fieldset disabled=\"disabled\">", fixed = TRUE)
    expect_false(grepl("-save\"", output$block$html, fixed = TRUE))
    expect_identical(output$submit_unavailable, "You can submit once you have given consent.")
    expect_match(output$questionnaire$html, "proxy1-consent_wait", fixed = TRUE)
    expect_identical(output$consent_wait, "You can answer the statements once you have given consent above.")
    session$setInputs(consent = 1)
    expect_identical(output$status, "Select consent explicitly first.")
    session$setInputs(consent_decline = 1)
    expect_identical(called(s, "record_consent")[[1]][[4]], FALSE)
    expect_match(output$consent_area$html, "You declined consent. You can still give consent.", fixed = TRUE)
    expect_identical(output$status, "Refusal recorded. Receipt: 7e6d5c4b")
    session$setInputs(consent_check = TRUE, consent = 2)
    expect_identical(called(s, "record_consent")[[2]][[4]], TRUE)
    # Afterwards the consent is a fact with its moment; the controls are gone.
    consent <- output$consent_area$html
    expect_match(text_of(consent), "Consent recorded on 5 Oct 2026, 14:03 (Europe/Berlin, UTC+2).", fixed = TRUE)
    expect_false(grepl("consent_check", consent, fixed = TRUE))
    expect_match(consent, "<details>\\s*<summary>Study information</summary>")
    expect_false(grepl("disabled", output[["slot_1-form"]]$html, fixed = TRUE))
    expect_match(output$block$html, "-save\"", fixed = TRUE)
  })
  # A save refused for missing consent says so.
  q <- session_questionnaire()
  shiny::testServer(delphyrApp:::rating_server, args = list(q = q, item = q$items[1, ], lang = function() "en", call = function(...) stop(del_error("DEL_FORBIDDEN", "consent")), autosave_ms = 0), {
    session$setInputs(kind = "answered", value = "7", save = 1)
    expect_match(output$status, "^Not saved yet\\. Consent for this round is missing\\. Give consent above so that your answers can be saved\\. Reference: [0-9a-f]{12}$")
  })
})

test_that("a consent tick survives a change of language but never reaches another round", {
  s <- session_services(session_questionnaire(accepted = FALSE))
  s$rounds$`study-A` <- data.frame(id = c("enrollment-A", "enrollment-A2"), number = 1:2, state = "eligible", round_state = "open", stringsAsFactors = FALSE)
  other <- session_questionnaire(accepted = FALSE)
  other$enrollment$id <- "enrollment-A2"
  other$round$number <- 2L
  call <- function(name, ...) if (identical(name, "get_questionnaire") && identical(list(...)[[1]], "enrollment-A2")) other else s$call(name, ...)
  language <- shiny::reactiveVal("en")
  ticked <- function(html) grepl("id=\"proxy1-consent_check\" type=\"checkbox\" class=\"shiny-input-checkbox\" checked=\"checked\"", html, fixed = TRUE)
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study-A", lang = function() language(), call = call), {
    session$setInputs(enrollment = "enrollment-A", load = 1)
    expect_false(ticked(output$consent_area$html))
    session$setInputs(consent_check = TRUE)
    language("de")
    session$flushReact()
    consent <- output$consent_area$html
    expect_match(consent, "Ich habe die Studieninformation oben gelesen und willige in die Teilnahme ein.", fixed = TRUE)
    expect_true(ticked(consent))
    # Another round starts without a tick; the browser then reports the empty box.
    session$setInputs(enrollment = "enrollment-A2", load = 2)
    expect_identical(q()$enrollment$id, "enrollment-A2")
    expect_false(ticked(output$consent_area$html))
    session$setInputs(consent_check = FALSE)
    language("fr")
    session$flushReact()
    expect_false(ticked(output$consent_area$html))
    # A refusal takes the tick away.
    session$setInputs(consent_check = TRUE)
    language("en")
    session$flushReact()
    expect_true(ticked(output$consent_area$html))
    session$setInputs(consent_decline = 1)
    expect_match(output$consent_area$html, "You declined consent.", fixed = TRUE)
    expect_false(ticked(output$consent_area$html))
  })
})

test_that("a confirmed submission makes the round read only at once and shows its receipt", {
  s <- session_services()
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study-A", lang = function() "en", call = s$call, autosave_ms = 1500), {
    session$setInputs(enrollment = "enrollment-A", load = 1)
    session$setInputs(`item_1_1-value` = "7", `item_1_2-value` = "8")
    # A failed refresh of the round list after the submission changes nothing.
    s$fail$list_enrollments <- simpleError("connection lost")
    session$setInputs(confirm = TRUE, submit = 1)
    expect_length(called(s, "submit_round"), 1L)
    expect_identical(rounds()$id, "enrollment-A")
    expect_identical(output$status, "")
    expect_identical(view()$mode, "submitted")
    expect_match(output[["slot_1-form"]]$html, "<fieldset disabled=\"disabled\">", fixed = TRUE)
    expect_false(grepl("-save\"", output$block$html, fixed = TRUE))
    expect_identical(output[["card_1-status"]], "Submitted")
    state <- output$round_state$html
    expect_match(state, "id=\"proxy1-receipt\"", fixed = TRUE)
    expect_match(text_of(state), "Submission confirmed: 5 Oct 2026, 14:03 (Europe/Berlin, UTC+2). Receipt: 4f2a9c1e Your answers in this round can no longer be changed.", fixed = TRUE)
    expect_match(state, "title=\"4f2a9c1e-77b0-4d3e-9a51-0c6e2b8d1f37\"", fixed = TRUE)
    expect_false(grepl("Submit by", state, fixed = TRUE))
    # No submission, saving or editing is offered any more.
    expect_null(output$review)
    session$setInputs(`item_2_1-value` = "3")
    session$elapse(2000)
    expect_length(called(s, "save_response"), 2L)
    expect_false(dirty())
  })
})

test_that("a round that closes while on screen keeps entries visible and never holds the person", {
  s <- session_services()
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study-A", lang = function() "en", call = s$call, autosave_ms = 1500, block_fields = 1L), {
    session$setInputs(enrollment = "enrollment-A", load = 1)
    s$fail$save_response <- del_error("DEL_ROUND_CLOSED", "round")
    session$setInputs(`item_1_1-kind` = "answered", `item_1_1-value` = "7")
    session$elapse(1600)
    expect_match(output[["card_1-status"]], "^Not saved yet\\. The round is closed or its deadline has passed\\.")
    expect_match(text_of(output$round_state$html), "This round has closed or its deadline has passed.", fixed = TRUE)
    expect_match(output$round_state$html, "role=\"alert\"", fixed = TRUE)
    expect_false(grepl("proxy1-submit\"", output$review$html, fixed = TRUE))
    session$setInputs(block_next = 1)
    expect_identical(view()$index, 2L)
    session$setInputs(load = 2)
    expect_false(grepl("Save your changes first", output$status, fixed = TRUE))
  })
  # A round loaded after it closed is read only and says so.
  closed <- session_services(session_questionnaire(round_state = "closed"))
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study-A", lang = function() "en", call = closed$call), {
    session$setInputs(enrollment = "enrollment-A", load = 1)
    expect_match(text_of(output$round_state$html), "This round is closed. Answers can no longer be saved or submitted.", fixed = TRUE)
    expect_match(output[["slot_1-form"]]$html, "<fieldset disabled=\"disabled\">", fixed = TRUE)
  })
  # A round submitted elsewhere stops saving here and says why.
  ended <- session_services()
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study-A", lang = function() "en", call = ended$call, autosave_ms = 1500), {
    session$setInputs(enrollment = "enrollment-A", load = 1)
    ended$fail$save_response <- del_error("DEL_CONFLICT", "enrollment.state")
    session$setInputs(`item_1_1-value` = "7")
    session$elapse(1600)
    expect_match(output[["card_1-status"]], "This round was already submitted or your participation has ended.", fixed = TRUE)
    expect_error(output[["slot_1-conflict"]])
    session$setInputs(load = 2)
    expect_length(called(ended, "get_questionnaire"), 2L)
  })
})

test_that("an element id occurs once on the page, whatever the state of the round", {
  ids_in <- function(html) sub("^id=\"(.*)\"$", "\\1", regmatches(html, gregexpr("id=\"[^\"]+\"", html))[[1]])
  # The ids of an output and of every output nested in it, as the page has them.
  page_ids <- function(output, name) {
    html <- tryCatch(as.character(output[[name]]$html), error = function(e) "")
    nested <- sub("^id=\"proxy1-(.*)\" class.*$", "\\1", regmatches(html, gregexpr("id=\"proxy1-[^\"]+\" class=\"shiny-html-output", html))[[1]])
    c(ids_in(html), unlist(lapply(nested, function(x) page_ids(output, x))))
  }
  for (accepted in c(FALSE, TRUE)) {
    s <- session_services(session_questionnaire(accepted = accepted))
    shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study-A", lang = function() "en", call = s$call, withdrawal_available = TRUE, block_fields = 1L), {
      session$setInputs(enrollment = "enrollment-A", load = 1)
      if (accepted) session$setInputs(confirm = TRUE, submit = 1)
      ids <- c(page_ids(output, "questionnaire"), page_ids(output, "withdrawal"))
      expect_true(length(ids) > 10L)
      expect_identical(ids[duplicated(ids)], character())
      expect_true("proxy1-consent_area" %in% ids)
    })
  }
})
