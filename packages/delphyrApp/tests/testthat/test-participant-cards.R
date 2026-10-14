# A round of statements rated on a 1-9 scale with an optional comment each.
participant_protocol <- function() {
  list(
    study = list(timezone = "Europe/Berlin", default_language = "en"),
    instrument = list(
      dimensions = list(list(code = "relevance", scale = "relevance_9"), list(code = "comment", scale = "comment_text")),
      scales = list(
        relevance_9 = list(type = "ordinal_integer", values = 1:9, anchors = list(low = "not relevant", high = "extremely relevant"), missing_options = c("unable_to_judge", "abstained")),
        comment_text = list(type = "free_text", values = list(), missing_options = "unable_to_judge")
      )
    ),
    analysis = list(consensus = list(agree_values = 7:9)),
    feedback = list(own_previous_rating = TRUE, median = TRUE, iqr = TRUE)
  )
}
participant_questionnaire <- function(statements = 2L, state = "eligible", accepted = TRUE) {
  codes <- sprintf("I%03d", seq_len(statements))
  # The server orders the fields of an item by their dimension code.
  rows <- expand.grid(dimension_code = c("comment", "relevance"), item_code = codes, stringsAsFactors = FALSE)
  list(
    protocol = participant_protocol(),
    round = list(id = "round-2", number = 2L, state = "open", in_time = TRUE, deadline = "2026-12-10T17:00:00Z", study_id = "study"),
    enrollment = list(id = "enrollment-2", state = state),
    consent = list(id = "consent", locale = "en", content = "Synthetic study information.", accepted = accepted),
    receipt = data.frame(),
    items = data.frame(
      id = paste0(rows$item_code, "-", rows$dimension_code), item_code = rows$item_code, item_version = 1L, dimension_code = rows$dimension_code,
      scale_code = ifelse(rows$dimension_code == "relevance", "relevance_9", "comment_text"),
      texts = sprintf('{"en":"Statement %s","de":"Aussage %s"}', rows$item_code, rows$item_code), required = rows$dimension_code == "relevance",
      display_order = match(rows$item_code, codes), stringsAsFactors = FALSE
    ),
    responses = data.frame(round_item_id = character(), revision = integer(), status = character(), value_int = integer(), value_text = character(), created_at = character(), stringsAsFactors = FALSE)
  )
}
# A stand-in for the services that keeps what was saved, as the server does.
participant_services <- function(q) {
  s <- new.env()
  s$q <- q
  s$calls <- list()
  s$fail <- list()
  s$call <- function(name, ...) {
    arguments <- list(...)
    s$calls[[length(s$calls) + 1L]] <- c(list(name), arguments)
    if (!is.null(s$fail[[name]])) stop(s$fail[[name]])
    switch(name,
      list_enrollments = data.frame(id = s$q$enrollment$id, number = 2L, state = s$q$enrollment$state, round_state = "open", stringsAsFactors = FALSE),
      get_questionnaire = s$q,
      save_response = {
        id <- arguments[[2]]
        old <- s$q$responses[s$q$responses$round_item_id == id, , drop = FALSE]
        revision <- if (nrow(old)) old$revision + 1L else 1L
        if (!identical(as.integer(arguments[[4]]), as.integer(revision - 1L))) delphyr::del_abort("DEL_CONFLICT", "revision")
        value <- arguments[[3]]$value
        at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S+00", tz = "UTC")
        s$q$responses <- rbind(
          s$q$responses[s$q$responses$round_item_id != id, , drop = FALSE],
          data.frame(
            round_item_id = id, revision = revision, status = arguments[[3]]$status, value_int = if (is.numeric(value)) as.integer(value) else NA_integer_,
            value_text = if (is.character(value)) value else NA_character_, created_at = at, stringsAsFactors = FALSE
          )
        )
        list(revision = revision, saved_at = at)
      },
      submit_round = list(id = "4f2a9c1e-77b0-4d3e-9a51-0c6e2b8d1f37", submitted_at = "2026-10-05 12:03:00+00"),
      stop("unexpected call: ", name)
    )
  }
  s
}
calls_of <- function(s, name) Filter(function(x) identical(x[[1]], name), s$calls)

test_that("each statement is one card: its heading once, the rating first, the comment named", {
  s <- participant_services(participant_questionnaire(2L))
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = s$call, autosave_ms = 1500), {
    session$setInputs(enrollment = "enrollment-2", load = 1)
    # Rated dimensions come before free text, whatever order the server used.
    expect_identical(q()$items$id, c("I001-relevance", "I001-comment", "I002-relevance", "I002-comment"))
    expect_identical(view()$cards, list(1:2, 3:4))
    block <- output$block$html
    expect_length(gregexpr("class=\"del-statement\"", block, fixed = TRUE)[[1]], 2L)
    expect_match(block, "aria-labelledby=\"proxy1-slot_1-heading\"", fixed = TRUE)
    lead <- output[["slot_1-title"]]$html
    expect_match(lead, "<h4 id=\"proxy1-slot_1-heading\">\\s*1\\.\\s*<span lang=\"en\">Statement I001</span>\\s*<small>\\(required\\)</small>")
    # The comment of the same statement repeats nothing of it.
    expect_false(grepl("Statement I001", output[["slot_2-title"]]$html, fixed = TRUE))
    comment <- output[["slot_2-form"]]$html
    expect_match(comment, "<label class=\"control-label\" id=\"proxy1-item_1_2-value-label\" for=\"proxy1-item_1_2-value\">Comment (optional)</label>", fixed = TRUE)
    # An optional comment needs no response type: text answers it.
    expect_false(grepl("item_1_2-kind", comment, fixed = TRUE))
    rating <- output[["slot_1-form"]]$html
    expect_match(rating, "item_1_1-kind", fixed = TRUE)
    expect_match(rating, "aria-describedby=\"proxy1-item_1_1-anchors\"", fixed = TRUE)
    # Anchors are tied to the numbers; the protocol's keys never appear.
    expect_match(rating, "<p id=\"proxy1-item_1_1-anchors\" class=\"del-anchors\" lang=\"en\">1 = not relevant \u2026 9 = extremely relevant</p>", fixed = TRUE)
    expect_false(grepl("low:", rating, fixed = TRUE))
    # With automatic saving the per-field save is small and secondary.
    expect_match(block, "<button class=\"btn btn-default action-button btn-sm\" id=\"proxy1-item_1_1-save\" type=\"button\">", fixed = TRUE)
    expect_false(grepl("btn-primary", block, fixed = TRUE))
    # Untouched fields say nothing.
    expect_identical(output[["card_1-status"]], "")
  })
})

test_that("one status line per statement says when its answers were saved", {
  s <- participant_services(participant_questionnaire(1L))
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = s$call, autosave_ms = 1500), {
    session$setInputs(enrollment = "enrollment-2", load = 1)
    session$setInputs(`item_1_1-kind` = "answered", `item_1_1-value` = "7")
    expect_identical(output[["card_1-status"]], "Not saved yet.")
    expect_match(output[["card_1-line"]]$html, "del-status--attention", fixed = TRUE)
    session$elapse(1600)
    expect_match(output[["card_1-status"]], "^Saved at [0-9]{2}:[0-9]{2}$")
    expect_match(output[["card_1-line"]]$html, "del-status--saved", fixed = TRUE)
    # Two fields with different states are named.
    session$setInputs(`item_1_2-value` = "Needs a picture.")
    expect_match(output[["card_1-status"]], "^Rating: Saved at [0-9]{2}:[0-9]{2} \u00b7 Comment: Not saved yet\\.$")
    session$elapse(1600)
    expect_identical(s$q$responses$value_text[s$q$responses$round_item_id == "I001-comment"], "Needs a picture.")
    expect_identical(s$q$responses$status[s$q$responses$round_item_id == "I001-comment"], "answered")
  })
  # An older save shows its moment in the study's time zone.
  expect_identical(saved_text("2026-10-03 17:49:28.629925+00", "Europe/Berlin", "de"), "Gespeichert am 3. Okt. 2026, 19:49 (Europe/Berlin, UTC+2)")
  expect_identical(saved_text(NULL, "Europe/Berlin", "en"), "Saved")
  expect_identical(card_text(list(list(text = "Saved", label = "Rating"), list(text = "", label = "Comment")), "en"), "Saved")
  expect_identical(card_text(list(list(text = "Saved", label = "Rating"), list(text = "Not saved yet.", label = "Comment")), "fr"), "Rating : Saved \u00b7 Comment : Not saved yet.")
})

test_that("a rating chosen while the response type reads Unanswered is part of the entry at once", {
  s <- participant_services(participant_questionnaire(3L))
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = s$call, autosave_ms = 60000, block_fields = 2L), {
    session$setInputs(enrollment = "enrollment-2", load = 1)
    # Only the value arrives; the browser has not yet reported the new type.
    session$setInputs(`item_1_1-value` = "7")
    expect_true(dirty())
    session$setInputs(block_next = 1)
    expect_identical(view()$index, 2L)
    stored <- s$q$responses[s$q$responses$round_item_id == "I001-relevance", ]
    expect_identical(c(stored$status, as.character(stored$value_int)), c("answered", "7"))
    # A comment that is cleared again is withdrawn, never an incomplete entry.
    session$setInputs(`item_2_4-value` = "First thought")
    session$setInputs(`item_2_4-value` = "")
    expect_false(dirty())
    session$setInputs(block_next = 2)
    expect_identical(view()$index, 3L)
  })
  # The same in a round of one block, before submission.
  one <- participant_services(participant_questionnaire(1L))
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = one$call, autosave_ms = 60000), {
    session$setInputs(enrollment = "enrollment-2", load = 1)
    session$setInputs(`item_1_1-value` = "8")
    session$setInputs(confirm = TRUE, submit = 1)
    expect_identical(calls_of(one, "submit_round")[[1]][[3]], c(`I001-relevance` = 1L))
  })
})

test_that("discarding an entry for the saved response never saves the discarded entry", {
  q <- participant_questionnaire(3L)
  q$responses <- data.frame(round_item_id = "I001-relevance", revision = 1L, status = "answered", value_int = 4L, value_text = NA_character_, created_at = "2026-10-05 10:00:00+00", stringsAsFactors = FALSE)
  s <- participant_services(q)
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = s$call, autosave_ms = 1500, block_fields = 2L), {
    session$setInputs(enrollment = "enrollment-2", load = 1)
    # Another tab saves 5 while this one still shows 4; this tab's 7 conflicts.
    s$q$responses$revision <- 2L
    s$q$responses$value_int <- 5L
    session$setInputs(`item_1_1-kind` = "answered", `item_1_1-value` = "7")
    session$elapse(1600)
    expect_match(output[["slot_1-conflict"]]$html, "Load the saved response and discard my entry", fixed = TRUE)
    saves <- length(calls_of(s, "save_response"))
    session$setInputs(`item_1_1-reload` = 1)
    # The browser still shows 7 when the person saves, leaves or submits.
    session$setInputs(`item_1_1-save` = 1)
    session$setInputs(block_next = 1)
    expect_identical(view()$index, 2L)
    expect_identical(length(calls_of(s, "save_response")), saves)
    expect_identical(s$q$responses$value_int, 5L)
    expect_identical(known()$revision[1], 2L)
  })
})

test_that("free text with a leading line break shows and compares as stored", {
  q <- participant_questionnaire(1L)
  q$responses <- data.frame(round_item_id = "I001-comment", revision = 1L, status = "answered", value_int = NA_integer_, value_text = "\nFirst point", created_at = "2026-10-05 10:00:00+00", stringsAsFactors = FALSE)
  item <- q$items[q$items$id == "I001-comment", ]
  saves <- 0L
  shiny::testServer(delphyrApp:::rating_server, args = list(q = q, item = item, lang = function() "en", call = function(...) {
    saves <<- saves + 1L
    list(revision = 2L, saved_at = "2026-10-05 10:05:00+00")
  }, autosave_ms = 1500), {
    # The parser drops one line feed after the start tag; the stored one stays.
    expect_match(output$form$html, ">\n\nFirst point</textarea>", fixed = TRUE)
    session$setInputs(value = "\nFirst point")
    session$elapse(2000)
    expect_false(dirty())
    expect_identical(saves, 0L)
    # Line ends are compared as the browser reports them.
    session$setInputs(value = "\r\nFirst point")
    expect_false(dirty())
  })
  # A submitted round is never held by a difference the person cannot edit.
  submitted <- participant_questionnaire(1L, state = "submitted")
  submitted$responses <- q$responses
  s <- participant_services(submitted)
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = s$call, block_fields = 2L), {
    session$setInputs(enrollment = "enrollment-2", load = 1)
    session$setInputs(`item_1_2-value` = "First point")
    expect_false(dirty())
    session$setInputs(load = 2)
    expect_false(grepl("Save your changes first", output$status, fixed = TRUE))
  })
})

test_that("a saved special response says so in the rating control", {
  q <- participant_questionnaire(1L)
  q$responses <- data.frame(round_item_id = "I001-relevance", revision = 1L, status = "unable_to_judge", value_int = NA_integer_, value_text = NA_character_, created_at = "2026-10-05 10:00:00+00", stringsAsFactors = FALSE)
  item <- q$items[q$items$id == "I001-relevance", ]
  shiny::testServer(delphyrApp:::rating_server, args = list(q = q, item = item, lang = function() "en", call = function(...) stop("unused"), autosave_ms = 0), {
    expect_match(output$form$html, "<option value=\"\" selected>No rating (Unable to judge)</option>", fixed = TRUE)
    expect_false(grepl("Choose a rating", output$form$html, fixed = TRUE))
  })
})

test_that("explicit saving keeps a normal button and a submitted round has none", {
  s <- participant_services(participant_questionnaire(1L))
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = s$call, autosave_ms = 0), {
    session$setInputs(enrollment = "enrollment-2", load = 1)
    expect_match(output$block$html, "id=\"proxy1-item_1_1-save\" type=\"button\" class=\"btn btn-default action-button\"", fixed = TRUE)
  })
  done <- participant_services(participant_questionnaire(1L, state = "submitted"))
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = done$call), {
    session$setInputs(enrollment = "enrollment-2", load = 1)
    expect_false(grepl("-save\"", output$block$html, fixed = TRUE))
    expect_match(output[["slot_1-form"]]$html, "<fieldset disabled=\"disabled\">", fixed = TRUE)
  })
})

test_that("a statement rated on two dimensions names each of them", {
  q <- participant_questionnaire(1L)
  q$items <- data.frame(
    id = c("I001-relevance", "I001-clarity"), item_code = "I001", item_version = 1L, dimension_code = c("relevance", "clarity"), scale_code = "relevance_9",
    texts = '{"en":"Statement I001"}', required = TRUE, display_order = 1L, stringsAsFactors = FALSE
  )
  s <- participant_services(q)
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = s$call, autosave_ms = 1500), {
    session$setInputs(enrollment = "enrollment-2", load = 1)
    expect_identical(view()$cards, list(1:2))
    expect_match(output[["slot_1-form"]]$html, ">Rating: Relevance</label>", fixed = TRUE)
    expect_match(output[["slot_2-form"]]$html, ">Rating: Clarity</label>", fixed = TRUE)
    session$setInputs(`item_1_2-value` = "6")
    expect_identical(output[["card_1-status"]], "Not saved yet.")
    session$elapse(1600)
    session$setInputs(`item_1_1-value` = "9")
    expect_match(output[["card_1-status"]], "^Relevance: Not saved yet\\. \u00b7 Clarity: Saved at [0-9]{2}:[0-9]{2}$")
  })
})

test_that("progress counts statements and counts written comments on their own", {
  s <- participant_services(participant_questionnaire(3L))
  language <- shiny::reactiveVal("en")
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() language(), call = s$call, autosave_ms = 1500), {
    session$setInputs(enrollment = "enrollment-2", load = 1)
    expect_match(output$progress$html, "Statements answered and saved: 0 of 3.", fixed = TRUE)
    expect_match(output$overview$html, "With a special response: 0 \u00b7 Open: 3 \u00b7 of which required: 3 \u00b7 Comments: 0", fixed = TRUE)
    session$setInputs(`item_1_1-value` = "8", `item_1_2-value` = "Needs a picture.", `item_1_3-kind` = "unable_to_judge")
    session$elapse(1600)
    expect_match(output$progress$html, "Statements answered and saved: 2 of 3.", fixed = TRUE)
    # An empty optional comment is never open.
    expect_match(output$overview$html, "With a special response: 1 \u00b7 Open: 1 \u00b7 of which required: 1 \u00b7 Comments: 1", fixed = TRUE)
    language("de")
    session$flushReact()
    expect_match(output$progress$html, "Beantwortete und gespeicherte Aussagen: 2 von 3.", fixed = TRUE)
    expect_match(output$overview$html, "Mit Sonderantwort: 1 \u00b7 Offen: 1 \u00b7 davon erforderlich: 1 \u00b7 Kommentare: 1", fixed = TRUE)
    language("fr")
    session$flushReact()
    expect_match(output$progress$html, "\u00c9nonc\u00e9s avec une r\u00e9ponse enregistr\u00e9e : 2 sur 3.", fixed = TRUE)
    expect_match(output$overview$html, "Avec une r\u00e9ponse particuli\u00e8re : 1 \u00b7 Ouvert : 1 \u00b7 dont obligatoires : 1 \u00b7 Commentaires : 1", fixed = TRUE)
  })
})
