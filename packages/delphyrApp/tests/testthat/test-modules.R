fixture <- function() {
  list(
    protocol = list(instrument = list(scales = list(rating = list(type = "ordinal_integer", values = 1:9, missing_options = c("unable_to_judge", "abstained"))))),
    enrollment = list(id = "own-enrollment"),
    items = data.frame(id = "item", scale_code = "rating", texts = '{"de":"Testfrage","en":"Test question"}', dimension_code = "relevance", required = TRUE),
    responses = data.frame(round_item_id = character(), revision = integer(), status = character(), value_int = integer(), value_text = character())
  )
}
test_that("save failures never advance revisions or clear pending changes", {
  q <- fixture()
  calls <- list()
  fail <- TRUE
  call <- function(name, ...) {
    calls[[length(calls) + 1L]] <<- list(name, ...)
    if (fail) stop("database unavailable")
    list(revision = 1L, saved_at = "2026-09-25 12:00:00+00")
  }
  shiny::testServer(delphyrApp:::rating_server, args = list(q = q, item = q$items, lang = function() "en", call = call), {
    session$setInputs(kind = "answered", value = "7")
    expect_true(dirty())
    session$setInputs(save = 1)
    expect_equal(revision(), 0L)
    expect_true(dirty())
    expect_match(output$status, "failed")
    expect_match(output$save_status$html, "del-status--attention", fixed = TRUE)
    fail <<- FALSE
    session$setInputs(save = 2)
    expect_equal(revision(), 1L)
    expect_false(dirty())
    expect_true(answered())
    expect_match(output$status, "Saved:")
    expect_match(output$save_status$html, "del-status--saved", fixed = TRUE)
    expect_equal(calls[[2]][[2]], "own-enrollment")
    expect_equal(calls[[2]][[4]], list(value = 7, status = "answered"))
  })
})
test_that("interface language changes preserve pending responses", {
  q <- fixture()
  language <- shiny::reactiveVal("de")
  shiny::testServer(delphyrApp:::rating_server, args = list(q = q, item = q$items, lang = function() language(), call = function(...) stop("unused")), {
    session$setInputs(kind = "answered", value = "8")
    expect_equal(current()$value, "8")
    expect_true(dirty())
    expect_match(output$title$html, "Testfrage")
    language("en")
    session$flushReact()
    expect_match(output$title$html, "Test question")
    expect_equal(current()$value, "8")
    expect_true(dirty())
    expect_false(grepl("value=\"5\" selected", output$form$html, fixed = TRUE))
  })
})
test_that("actor is required and is not an input control", {
  expect_error(run_app(NULL, NULL), "trusted")
  stub <- function(...) data.frame()
  services <- stats::setNames(rep(list(stub), 6), c("list_studies", "list_enrollments", "get_questionnaire", "record_consent", "save_response", "submit_round"))
  app <- run_app(NULL, list(principal_id = "server-only"), services = services)
  expect_s3_class(app, "shiny.appobj")
  html <- app$httpHandler(list(PATH_INFO = "/", REQUEST_METHOD = "GET"))$content
  expect_false(grepl("server-only", html, fixed = TRUE))
})
test_that("panel blocks submitting and changing questionnaires with pending changes", {
  q <- fixture()
  q$round <- list(number = 1, deadline = "2026-12-01", study_id = "study")
  q$protocol$study <- list(timezone = "Europe/Berlin")
  q$consent <- list(id = "consent", content = "Synthetic study information")
  q$receipt <- data.frame()
  submits <- 0L
  loads <- 0L
  call <- function(name, ...) {
    switch(name,
      list_enrollments = data.frame(id = "own-enrollment", number = 1, round_state = "open"),
      get_questionnaire = {
        loads <<- loads + 1L
        q
      },
      submit_round = {
        submits <<- submits + 1L
        list(id = "receipt", submitted_at = "now")
      },
      stop("unexpected call")
    )
  }
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = call), {
    session$setInputs(enrollment = "own-enrollment", load = 1)
    expect_equal(loads, 1L)
    expect_match(output$deadline, "01:00 +0100 Europe/Berlin", fixed = TRUE)
    session$setInputs(`item_1_1-kind` = "answered", `item_1_1-value` = "7")
    expect_true(dirty())
    session$setInputs(confirm = TRUE, submit = 1)
    expect_equal(submits, 0L)
    expect_match(output$status, "Save all changes")
    session$setInputs(load = 2)
    expect_equal(loads, 1L)
    expect_match(output$status, "Save your changes first")
  })
})
test_that("feedback release requires review of the exact candidate and jobs retain results", {
  names <- c("freeze_round", "request_analysis", "get_operation", "get_analysis", "create_feedback", "get_feedback_candidate", "release_feedback", "assign_feedback", "request_export", "download_artifact", "get_study_setup", "prepare_round")
  services <- stats::setNames(rep(list(function(...) NULL), length(names)), names)
  released <- 0L
  refreshes <- 0L
  call <- function(name, ...) {
    switch(name,
      get_study_setup = list(protocol = list(), consent_versions = data.frame(id = "consent", locale = "en", content = "Synthetic")),
      request_analysis = list(id = "job"),
      get_operation = data.frame(state = "succeeded", result_ref = "analysis"),
      get_analysis = list(results = data.frame(item = "example", n_valid = 20)),
      create_feedback = list(id = "feedback", hash = "exact-hash"),
      get_feedback_candidate = list(content = list(), hash = "exact-hash", state = "reviewed"),
      release_feedback = {
        expect_equal(list(...)[[2]], "exact-hash")
        released <<- released + 1L
      },
      stop("unexpected service")
    )
  }
  round <- function() data.frame(id = "round", snapshot_id = "snapshot", analysis_id = "analysis")
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = round, lang = function() "en", call = call, services = services, refresh = function() {
    refreshes <<- refreshes + 1L
  }, allowed = function() TRUE), {
    session$setInputs(analyse = 1)
    expect_equal(operation(), "job")
    session$setInputs(poll = 1)
    expect_equal(analysis()$results$n_valid, 20)
    session$setInputs(draft = 1, reviewed = FALSE)
    session$setInputs(release = 1)
    expect_equal(released, 0L)
    session$setInputs(reviewed = TRUE, release = 2)
    expect_equal(released, 1L)
    preview(list(hash = "changed"))
    session$setInputs(release = 3)
    expect_equal(released, 1L)
  })
})

test_that("manager table formats database timestamps and states for people", {
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "manage",
      get_study_setup = list(protocol = list(study = list(timezone = "Europe/Berlin"))),
      list_rounds = data.frame(
        id = "round", number = 1L, state = "draft", instrument_hash = "hash",
        deadline = as.POSIXct("2026-10-02 10:00:00", tz = "UTC")
      ),
      stop("Unexpected service")
    )
  }
  services <- stats::setNames(rep(list(function(...) NULL), 4), c("get_capabilities", "get_study_setup", "list_rounds", "transition_round"))
  shiny::testServer(delphyrApp:::management_server, args = list(
    study = function() "study", lang = function() "en", call = call, services = services
  ), {
    session$flushReact()
    html <- output$rounds
    expect_match(html, "2026-10-02 12:00 +0200 Europe/Berlin", fixed = TRUE)
    expect_match(html, "Draft", fixed = TRUE)
    expect_match(html, "Deadline", fixed = TRUE)
    expect_false(grepl("179093", html, fixed = TRUE))
    expect_false(grepl(">draft<", html, fixed = TRUE))
  })
})

test_that("manager without panel capability has no participation section", {
  enrollments_read <- FALSE
  call <- function(name, ...) {
    if (name == "get_capabilities") {
      return("manage")
    }
    enrollments_read <<- TRUE
    stop("Panel data should not be read")
  }
  shiny::testServer(delphyrApp:::panel_server, args = list(
    study = function() "study", lang = function() "en", call = call,
    capabilities_available = TRUE
  ), {
    session$flushReact()
    expect_identical(output$visible, "no")
    expect_false(enrollments_read)
  })
})

test_that("editing a committed answer never labels the new value saved", {
  q <- fixture()
  q$responses <- data.frame(round_item_id = "item", revision = 1L, status = "answered", value_int = 7L, value_text = NA_character_)
  shiny::testServer(delphyrApp:::rating_server, args = list(q = q, item = q$items, lang = function() "en", call = function(...) list(revision = 2L, saved_at = "committed-time")), {
    session$setInputs(kind = "answered", value = "7", save = 1)
    expect_match(output$status, "Saved:", fixed = TRUE)
    session$setInputs(value = "8")
    expect_match(output$status, "Unsaved change", fixed = TRUE)
    expect_false(grepl("Saved:", output$status, fixed = TRUE))
    expect_equal(revision(), 2L)
  })
})

test_that("withdrawal needs explicit confirmation and reports the durable receipt", {
  withdrawals <- 0L
  call <- function(name, ...) {
    if (name == "list_enrollments") return(data.frame(id = character(), number = integer(), round_state = character()))
    if (name == "withdraw_participation") {
      withdrawals <<- withdrawals + 1L
      expect_equal(list(...)[[2]], "synthetic_retain_prior_data")
      return(list(id = "withdrawal-receipt"))
    }
    stop("unexpected service")
  }
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = call, withdrawal_available = TRUE), {
    session$flushReact()
    session$setInputs(withdraw = 1)
    expect_equal(withdrawals, 0L)
    expect_match(output$status, "confirm withdrawal")
    session$setInputs(withdraw_confirm = TRUE, withdraw = 2)
    expect_equal(withdrawals, 1L)
    expect_match(output$status, "withdrawal-receipt")
    expect_null(q())
  })
})
