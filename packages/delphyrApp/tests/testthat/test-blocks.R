block_questionnaire <- function(items = 5L, required = TRUE) {
  codes <- sprintf("I%03d", seq_len(items))
  rows <- expand.grid(dimension_code = c("relevance", "clarity"), item_code = codes, stringsAsFactors = FALSE)
  list(
    protocol = list(study = list(timezone = "Europe/Berlin"), instrument = list(scales = list(rating = list(type = "ordinal_integer", values = 1:9, missing_options = c("unable_to_judge", "abstained"))))),
    enrollment = list(id = "own-enrollment", state = "eligible"), round = list(number = 2, deadline = "2026-12-01", study_id = "study"),
    consent = list(id = "consent", content = "Synthetic study information", accepted = TRUE), receipt = data.frame(),
    items = data.frame(
      id = paste0(rows$item_code, "-", rows$dimension_code), item_code = rows$item_code, item_version = 1L, dimension_code = rows$dimension_code,
      scale_code = "rating", texts = sprintf('{"en":"Statement %s","de":"Aussage %s"}', rows$item_code, rows$item_code), required = required, stringsAsFactors = FALSE
    ),
    responses = data.frame(round_item_id = character(), revision = integer(), status = character(), value_int = integer(), value_text = character(), stringsAsFactors = FALSE)
  )
}
# A stand-in for the services that keeps what was saved, as the server does.
block_services <- function(q) {
  state <- new.env()
  state$q <- q
  state$calls <- character()
  state$submitted <- NULL
  state$fail_save <- FALSE
  state$call <- function(name, ...) {
    state$calls <- c(state$calls, name)
    arguments <- list(...)
    switch(name,
      list_enrollments = data.frame(id = "own-enrollment", number = 2, round_state = "open"),
      get_questionnaire = state$q,
      save_response = {
        if (state$fail_save) stop("database unavailable")
        id <- arguments[[2]]
        old <- state$q$responses[state$q$responses$round_item_id == id, , drop = FALSE]
        revision <- if (nrow(old)) old$revision + 1L else 1L
        if (!identical(as.integer(arguments[[4]]), as.integer(revision - 1L))) delphyr::del_abort("DEL_CONFLICT", "revision")
        value <- arguments[[3]]$value
        state$q$responses <- rbind(
          state$q$responses[state$q$responses$round_item_id != id, , drop = FALSE],
          data.frame(round_item_id = id, revision = revision, status = arguments[[3]]$status, value_int = if (is.null(value)) NA_integer_ else as.integer(value), value_text = NA_character_, stringsAsFactors = FALSE)
        )
        list(revision = revision, saved_at = "committed")
      },
      submit_round = {
        state$submitted <- arguments[[2]]
        list(id = "receipt", submitted_at = "now")
      },
      stop("unexpected call")
    )
  }
  state
}

test_that("the fields of an item stay in one block of limited size", {
  q <- block_questionnaire(5L)
  expect_identical(question_blocks(q$items, 4L), list(1:4, 5:8, 9:10))
  expect_identical(question_blocks(q$items, 5L), list(1:4, 5:8, 9:10))
  expect_identical(question_blocks(q$items, 20L), list(1:10))
  # An item with more fields than a block holds has a block of its own.
  expect_identical(question_blocks(q$items, 1L), list(1:2, 3:4, 5:6, 7:8, 9:10))
  expect_identical(question_blocks(q$items[-2, ], 3L), list(1:3, 4:5, 6:7, 8:9))
  single <- data.frame(id = "item", scale_code = "rating", stringsAsFactors = FALSE)
  expect_identical(question_blocks(single, 20L), list(1L))
  expect_identical(question_numbers(q$items), rep(1:5, each = 2L))
  labels <- block_labels(q$items, question_blocks(q$items, 4L), "en")
  expect_identical(names(labels), c("Block 1 \u00b7 Questions 1\u20132", "Block 2 \u00b7 Questions 3\u20134", "Block 3 \u00b7 Questions 5\u20135"))
  expect_identical(unname(labels), c("1", "2", "3"))
  expect_match(names(block_labels(q$items, question_blocks(q$items, 4L), "fr"))[1], "^Bloc 1 \u00b7 Questions 1\u20132$")
  expect_error(run_app(NULL, list(principal_id = "x"), block_fields = 0), "block size")
})

test_that("a long round is answered block by block and saved before a block is left", {
  s <- block_services(block_questionnaire(5L))
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = s$call, autosave_ms = 60000, block_fields = 4L), {
    session$setInputs(enrollment = "own-enrollment", load = 1)
    expect_identical(view()$index, 1L)
    expect_identical(view()$ids, paste0("item_1_", 1:4))
    expect_length(editors(), 4L)
    expect_match(output$block_title, "Block 1 of 3 \u00b7 Questions 1\u20132 of 5", fixed = TRUE)
    expect_match(output[["slot_1-title"]]$html, "Statement I001", fixed = TRUE)
    expect_match(output$progress$html, "0 / 10 response fields confirmed saved", fixed = TRUE)
    expect_match(output$overview$html, "Open: 10 \u00b7 of which required: 10", fixed = TRUE)
    expect_match(output$overview$html, "Open fields in block: 1, 2, 3", fixed = TRUE)
    expect_match(output$overview$html, "Required fields are open in block: 1, 2, 3", fixed = TRUE)
    # An entry is pending when the next block is requested: it is saved first.
    session$setInputs(`item_1_1-kind` = "answered", `item_1_1-value` = "7")
    expect_true(dirty())
    session$setInputs(block_next = 1)
    expect_identical(tail(s$calls, 2), c("save_response", "get_questionnaire"))
    expect_identical(view()$index, 2L)
    expect_identical(view()$ids, paste0("item_2_", 5:8))
    expect_false(dirty())
    expect_match(output$block_title, "Block 2 of 3 \u00b7 Questions 3\u20134 of 5", fixed = TRUE)
    # The same place now shows the next field; nothing of the previous remains.
    expect_match(output[["slot_1-title"]]$html, "Statement I003", fixed = TRUE)
    expect_false(grepl("I001", output[["slot_1-title"]]$html, fixed = TRUE))
    expect_identical(known()$status[1], "answered")
    expect_identical(known()$revision[1], 1L)
    expect_match(output$progress$html, "1 / 10 response fields confirmed saved", fixed = TRUE)
    # A late entry for the previous block reaches no field and saves nothing.
    saves <- sum(s$calls == "save_response")
    session$setInputs(`item_1_1-value` = "2", `item_1_2-kind` = "answered", `item_1_2-value` = "9")
    session$elapse(120000)
    expect_false(dirty())
    expect_identical(sum(s$calls == "save_response"), saves)
    expect_identical(s$q$responses$value_int[s$q$responses$round_item_id == "I001-relevance"], 7L)
    # An incomplete entry keeps the block open.
    session$setInputs(`item_2_5-kind` = "answered", `item_2_5-value` = "")
    session$setInputs(block_previous = 1)
    expect_identical(view()$index, 2L)
    expect_match(output$status, "Save or complete your changes in this block first", fixed = TRUE)
    session$setInputs(`item_2_5-value` = "4")
    session$setInputs(block_choice = "3", block_go = 1)
    expect_identical(view()$index, 3L)
    expect_identical(view()$ids, paste0("item_3_", 9:10))
    expect_length(editors(), 2L)
    expect_identical(output$status, "")
    # The last block is shorter: its unused places show nothing.
    expect_match(output[["slot_2-title"]]$html, "Statement I005", fixed = TRUE)
    expect_error(output[["slot_3-title"]])
    # Going back shows the committed answer of the first block.
    session$setInputs(block_choice = "1", block_go = 2)
    expect_identical(view()$ids, paste0("item_4_", 1:4))
    expect_match(output[["slot_1-form"]]$html, "value=\"7\" selected", fixed = TRUE)
    # Leaving the last and the first block in the wrong direction does nothing.
    session$setInputs(block_previous = 2)
    expect_identical(view()$index, 1L)
  })
})

test_that("a failed save keeps the block and a submission names required fields that are open", {
  s <- block_services(block_questionnaire(3L))
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = s$call, autosave_ms = 60000, block_fields = 2L), {
    session$setInputs(enrollment = "own-enrollment", load = 1)
    expect_length(view()$ids, 2L)
    s$fail_save <- TRUE
    session$setInputs(`item_1_1-kind` = "answered", `item_1_1-value` = "6")
    session$setInputs(block_next = 1)
    expect_identical(view()$index, 1L)
    expect_true(dirty())
    expect_match(output$status, "Save or complete your changes in this block first", fixed = TRUE)
    s$fail_save <- FALSE
    session$setInputs(`item_1_2-kind` = "abstained")
    session$setInputs(block_next = 2)
    expect_identical(view()$index, 2L)
    expect_match(output$overview$html, "Answered: 1 \u00b7 Special response: 1 \u00b7 Open: 4 \u00b7 of which required: 4", fixed = TRUE)
    # Submitting with open required fields shows the first block that has one.
    session$setInputs(`item_2_3-kind` = "answered", `item_2_3-value` = "8", `item_2_4-kind` = "unable_to_judge")
    session$setInputs(block_next = 3)
    expect_identical(view()$index, 3L)
    session$setInputs(block_choice = "1", block_go = 1)
    session$setInputs(confirm = TRUE, submit = 1)
    expect_null(s$submitted)
    expect_identical(view()$index, 3L)
    expect_match(output$status, "Required response fields are still open", fixed = TRUE)
    expect_match(output$overview$html, "Required fields are open in block: 3", fixed = TRUE)
    expect_identical(view()$ids, c("item_5_5", "item_5_6"))
    session$setInputs(`item_5_5-kind` = "answered", `item_5_5-value` = "5", `item_5_6-kind` = "answered", `item_5_6-value` = "5")
    session$setInputs(submit = 2)
    # The submission names the confirmed revision of every field of every block.
    expect_identical(s$submitted, c(`I001-relevance` = 1L, `I001-clarity` = 1L, `I002-relevance` = 1L, `I002-clarity` = 1L, `I003-relevance` = 1L, `I003-clarity` = 1L))
    expect_identical(receipt()$id, "receipt")
  })
})

test_that("work resumes at the first block with an open field and a short round has no blocks", {
  q <- block_questionnaire(3L)
  q$responses <- data.frame(round_item_id = q$items$id[1:3], revision = c(1L, 2L, 1L), status = c("answered", "abstained", "answered"), value_int = c(7L, NA, 3L), value_text = NA_character_, stringsAsFactors = FALSE)
  s <- block_services(q)
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = s$call, autosave_ms = 0, block_fields = 2L), {
    session$setInputs(enrollment = "own-enrollment", load = 1)
    expect_identical(view()$index, 2L)
    expect_match(output$questionnaire$html, "block_choice", fixed = TRUE)
    expect_match(output$questionnaire$html, "Previous block", fixed = TRUE)
    expect_match(output$block$html, "block_heading", fixed = TRUE)
    expect_match(output$progress$html, "3 / 6 response fields confirmed saved", fixed = TRUE)
  })
  submitted <- block_services(utils::modifyList(q, list(enrollment = list(id = "own-enrollment", state = "submitted"))))
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = submitted$call, autosave_ms = 0, block_fields = 2L), {
    session$setInputs(enrollment = "own-enrollment", load = 1)
    expect_identical(view()$index, 1L)
  })
  short <- block_services(block_questionnaire(2L))
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = short$call, autosave_ms = 0, block_fields = 20L), {
    session$setInputs(enrollment = "own-enrollment", load = 1)
    expect_identical(view()$ids, paste0("item_1_", 1:4))
    expect_false(grepl("block_choice", output$questionnaire$html, fixed = TRUE))
    expect_false(grepl("block_heading", output$block$html, fixed = TRUE))
    expect_match(output$block$html, "slot_4-form", fixed = TRUE)
    expect_match(output$block$html, "item_1_4-save", fixed = TRUE)
    session$setInputs(block_next = 1)
    expect_identical(view()$index, 1L)
  })
})

test_that("a field outside a block still renders into outputs of its own", {
  q <- block_questionnaire(1L)
  shiny::testServer(delphyrApp:::rating_server, args = list(q = q, item = q$items[1, ], lang = function() "en", call = function(...) list(revision = 1L, saved_at = "now"), autosave_ms = 0), {
    session$setInputs(kind = "answered", value = "7", save = 1)
    expect_match(output$title$html, "Statement I001", fixed = TRUE)
    expect_match(output$status, "Saved:")
    destroy()
    session$setInputs(value = "3", save = 2)
    expect_equal(revision(), 1L)
  })
  html <- as.character(rating_ui("panel-item_1_1"))
  expect_match(html, "id=\"panel-item_1_1-form\"", fixed = TRUE)
  placed <- as.character(rating_ui("panel-item_3_7", "panel-slot_2"))
  expect_match(placed, "id=\"panel-slot_2-form\"", fixed = TRUE)
  expect_match(placed, "id=\"panel-item_3_7-save\"", fixed = TRUE)
})

test_that("the round list starts with the round that is due", {
  rounds <- function(state, round_state) data.frame(id = paste0("e", seq_along(state)), number = seq_along(state), state = state, round_state = round_state)
  # The open round that is not yet submitted, not the first of the list.
  expect_identical(current_enrollment(rounds(c("submitted", "eligible"), c("released", "open"))), "e2")
  expect_identical(current_enrollment(rounds(c("submitted", "in_progress"), c("released", "open"))), "e2")
  # Nothing is due: the latest round.
  expect_identical(current_enrollment(rounds(c("submitted", "submitted"), c("released", "open"))), "e2")
  expect_identical(current_enrollment(rounds(c("submitted", "withdrawn"), c("released", "open"))), "e2")
  expect_identical(current_enrollment(rounds(c("submitted", "eligible"), c("released", "closed"))), "e2")
  # A late member of an earlier open round keeps that round when a later one is closed.
  expect_identical(current_enrollment(rounds(c("eligible", "submitted"), c("open", "finalized"))), "e1")
  expect_identical(current_enrollment(rounds("eligible", "open")), "e1")
  expect_null(current_enrollment(data.frame(id = character(), number = integer(), state = character(), round_state = character())))
  # A listing without state columns falls back to the latest round.
  expect_identical(current_enrollment(data.frame(id = c("a", "b"), number = 1:2)), "b")
  expect_identical(current_enrollment(data.frame(id = c("a", "b"))), "b")
})
