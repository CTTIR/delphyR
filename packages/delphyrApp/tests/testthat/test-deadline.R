deadline_call <- function(state) {
  function(name, ...) {
    state$calls[[length(state$calls) + 1L]] <- list(name, ...)
    switch(name,
      get_capabilities = "manage",
      get_study_setup = list(protocol = list(study = list(timezone = "Europe/Berlin"))),
      list_rounds = data.frame(id = "round", number = 1L, state = "open", instrument_hash = "listed-hash", deadline = as.POSIXct(state$deadline, tz = "UTC")),
      change_round_deadline = {
        if (!is.null(state$refuse)) stop(structure(list(message = paste("refused", state$refuse), call = NULL, code = "DEL_CONFLICT", path = state$refuse), class = c("DEL_CONFLICT", "delphyr_error", "error", "condition")))
        state$deadline <- "2026-12-10 17:00:00"
        list(id = "round", deadline = "2026-12-10T17:00:00Z")
      },
      stop("Unexpected service")
    )
  }
}
deadline_services <- function() stats::setNames(rep(list(function(...) NULL), 5), c("get_capabilities", "get_study_setup", "list_rounds", "transition_round", "change_round_deadline"))

test_that("a deadline change needs a time, a rationale and confirmation and binds the round's hash", {
  state <- new.env()
  state$calls <- list()
  state$deadline <- "2026-12-01 17:00:00"
  touched <- 0L
  changes <- function() Filter(function(x) identical(x[[1]], "change_round_deadline"), state$calls)
  shiny::testServer(delphyrApp:::management_server, args = list(study = function() "study", lang = function() "en", call = deadline_call(state), services = deadline_services(), touch = function() touched <<- touched + 1L), {
    session$flushReact()
    expect_match(output$body$html, "Change the deadline", fixed = TRUE)
    expect_match(output$body$html, "an open round can only be extended", fixed = TRUE)
    session$setInputs(round = "round", deadline = "2026-12-10T18:00:00+01:00", deadline_reason = " ", deadline_confirm = TRUE, deadline_change = 1)
    expect_match(output$status, "A deadline, a reason and confirmation are required", fixed = TRUE)
    session$setInputs(deadline_reason = "Service was interrupted", deadline_confirm = FALSE, deadline_change = 2)
    expect_length(changes(), 0L)
    session$setInputs(deadline_confirm = TRUE, deadline_change = 3)
    sent <- changes()
    expect_length(sent, 1L)
    expect_identical(unlist(sent[[1]][2:5]), c("round", "2026-12-10T18:00:00+01:00", "listed-hash", "Service was interrupted"))
    expect_identical(output$status, "Deadline changed.")
    expect_identical(touched, 1L)
    expect_match(output$rounds, "10 Dec 2026, 18:00 (Europe/Berlin, UTC+1)", fixed = TRUE)
    # Each refusal says what to change; nothing is reported as changed.
    for (case in list(
      list("deadline.format", "needs a date, a time and a timezone"), list("deadline.offset", "needs a date, a time and a timezone"), list("deadline.past", "must lie in the future"),
      list("deadline.earlier", "can only be moved to a later time"), list("round.state", "closed round cannot be changed")
    )) {
      state$refuse <- case[[1]]
      session$setInputs(deadline_reason = "Another change", deadline_confirm = TRUE, deadline_change = stats::runif(1))
      expect_match(output$status, paste0("^Not changed: .*", case[[2]]))
    }
    state$refuse <- "round.hash"
    session$setInputs(deadline_change = stats::runif(1))
    expect_match(output$status, "^Conflict: reload .* Reference: [0-9a-f]{12}$")
    expect_identical(touched, 1L)
  })
})

test_that("the deadline change is offered only where the service exists and is named in the history", {
  state <- new.env()
  state$calls <- list()
  state$deadline <- "2026-12-01 17:00:00"
  services <- deadline_services()
  services$change_round_deadline <- NULL
  shiny::testServer(delphyrApp:::management_server, args = list(study = function() "study", lang = function() "en", call = deadline_call(state), services = services), {
    session$flushReact()
    expect_false(grepl("Change the deadline", output$body$html, fixed = TRUE))
  })
  expect_identical(audit_action_label("round_deadline", "en"), "Round deadline changed")
  expect_identical(audit_action_label("round_deadline", "fr"), "Date limite du tour modifi\u00e9e")
  expect_true("round_deadline" %in% audit_action_codes())
  expect_identical(round_state_label(c("open", "deadline_changed", "cancelled"), "en"), c("Open", "Deadline changed", "Withdrawn (never opened)"))
  expect_identical(round_state_label("deadline_changed", "de"), "Frist ge\u00e4ndert")
})

test_that("a deadline in the hour that occurs twice at the end of summer time is shown unambiguously", {
  # On 25 October 2026 the clocks of Europe/Berlin go back from 03:00 to 02:00:
  # 02:30 occurs twice, one hour apart. Only the offset tells the two apart.
  before <- as.POSIXct("2026-10-25 00:30:00", tz = "UTC")
  after <- as.POSIXct("2026-10-25 01:30:00", tz = "UTC")
  rounds <- data.frame(id = c("a", "b"), number = 1:2, state = "open", deadline = c(before, after))
  shown <- round_display(rounds, "en", "Europe/Berlin")$Deadline
  expect_identical(shown, c("25 Oct 2026, 02:30 (Europe/Berlin, UTC+2)", "25 Oct 2026, 02:30 (Europe/Berlin, UTC+1)"))
  expect_false(identical(shown[1], shown[2]))
  # The start of summer time: 02:30 does not exist on 29 March 2026.
  spring <- round_display(data.frame(id = "c", number = 1L, state = "open", deadline = as.POSIXct("2026-03-29 01:30:00", tz = "UTC")), "en", "Europe/Berlin")$Deadline
  expect_identical(spring, "29 Mar 2026, 03:30 (Europe/Berlin, UTC+2)")
  # A participant sees the same instants with their offsets.
  for (case in list(list(before, "25.10.2026 02:30 +0200 Europe/Berlin"), list(after, "25.10.2026 02:30 +0100 Europe/Berlin"))) {
    q <- list(
      round = list(number = 1, deadline = case[[1]], study_id = "study"), enrollment = list(id = "own", state = "eligible"),
      consent = list(id = "consent", content = "Synthetic study information", accepted = TRUE), receipt = data.frame(),
      protocol = list(study = list(timezone = "Europe/Berlin"), instrument = list(scales = list(relevance_9 = list(type = "ordinal_integer", values = 1:9, anchors = list(low = "not relevant", high = "very relevant"), missing_options = "unable_to_judge")))),
      items = data.frame(id = "item", item_code = "I001", item_version = 1L, dimension_code = "relevance", scale_code = "relevance_9", text = "Synthetic item", locale = "en", required = TRUE, display_order = 1L),
      responses = data.frame(round_item_id = character(), revision = integer(), status = character(), value_int = integer(), value_text = character())
    )
    call <- function(name, ...) switch(name, list_enrollments = data.frame(id = "own", number = 1, state = "eligible", round_state = "open"), get_questionnaire = q, stop("unexpected call"))
    shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = call), {
      session$setInputs(enrollment = "own", load = 1)
      expect_identical(output$deadline, paste("Submit by:", case[[2]]))
    })
  }
})
