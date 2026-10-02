editorial_services <- function() {
  stats::setNames(rep(list(function(...) NULL), 10), c(
    "get_capabilities", "get_qualitative_provenance", "list_qualitative_reviews",
    "record_qualitative_source", "redact_qualitative_source", "release_qualitative_edit",
    "create_qualitative_theme", "code_qualitative_source", "link_item_source", "record_item_lineage"
  ))
}

test_that("restricted originals are not fetched for a manager-only reviewer", {
  originals <- FALSE
  released <- list()
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "manage",
      get_qualitative_provenance = {
        originals <<- TRUE
        stop("Forbidden originals")
      },
      list_qualitative_reviews = data.frame(id = "edit", source_ref = "source-ref", kind = "summary", redacted_text = "Reviewed synthetic summary", reason = "Remove identifiers", hash = "exact-edit", released = FALSE, can_review = TRUE),
      release_qualitative_edit = {
        released[[length(released) + 1L]] <<- list(...)
      },
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::editorial_server, args = list(study = function() "study", lang = function() "en", call = call, services = editorial_services()), {
    session$flushReact()
    expect_false(originals)
    expect_false(grepl("Original text", output$body$html, fixed = TRUE))
    session$setInputs(review_edit = "edit", preview_review = 1)
    expect_match(output$review_preview$html, "Summary (not a quotation)", fixed = TRUE)
    session$setInputs(review_reason = "Faithful and preserves dissent", review_confirm = FALSE, release = 1)
    expect_length(released, 0L)
    session$setInputs(review_confirm = TRUE, release = 2)
    expect_length(released, 1L)
    expect_equal(released[[1]][[3]], "exact-edit")
    session$setInputs(release = 3)
    expect_length(released, 1L)
  })
})

test_that("lineage parser rejects extra columns and preserves all split targets", {
  expect_equal(delphyrApp:::parse_lineage_rows("I002,1\nI003,2")$item_code, c("I002", "I003"))
  expect_error(delphyrApp:::parse_lineage_rows("I001,1,extra"), "pair")
  expect_error(delphyrApp:::parse_lineage_rows("I001,1.5"), "Invalid")
  expect_error(delphyrApp:::parse_lineage_rows("I001,1\nI001,2"), "Invalid")
})

campaign_services <- function() {
  stats::setNames(rep(list(function(...) NULL), 7), c(
    "get_capabilities", "list_campaign_rounds", "list_campaign_enrollments",
    "prepare_campaign", "preview_campaign", "release_campaign", "cancel_campaign"
  ))
}

test_that("campaign approval is bound to the exact text and selected pseudonyms", {
  released <- list()
  prepared <- list()
  approved <- FALSE
  preview <- function() {
    list(
      id = "campaign", subject = "Synthetic invitation", body = "Synthetic body", hash = "campaign-hash", released = approved, cancelled = FALSE,
      recipients = data.frame(enrollment_id = "enrollment", pseudonym = "study-pseudonym", delivery_state = "draft")
    )
  }
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "coordinate",
      list_campaign_rounds = data.frame(id = "round", number = 1L, state = "draft"),
      list_campaign_enrollments = data.frame(enrollment_id = "enrollment", pseudonym = "study-pseudonym", state = "eligible"),
      prepare_campaign = {
        prepared <<- list(...)
        list(id = "campaign", hash = "campaign-hash")
      },
      preview_campaign = preview(),
      release_campaign = {
        released[[length(released) + 1L]] <<- list(...)
        approved <<- TRUE
      },
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::communications_server, args = list(study = function() "study", lang = function() "en", call = call, services = campaign_services()), {
    session$setInputs(round = "round", enrollments = "enrollment", kind = "invitation", subject = "Synthetic invitation", message = "Synthetic body", locale = "en", version = 1)
    session$setInputs(prepare = 1)
    expect_equal(prepared[[2]], "enrollment")
    expect_match(output$recipient_preview, "study-pseudonym", fixed = TRUE)
    expect_false(grepl("enrollment", output$recipient_preview, fixed = TRUE))
    session$setInputs(confirm = TRUE, reason = "Exact scope reviewed", subject = "Changed after preview", release = 1)
    expect_length(released, 0L)
    session$setInputs(subject = "Synthetic invitation", release = 2)
    expect_length(released, 1L)
    expect_equal(released[[1]][[2]], "campaign-hash")
    expect_true(candidate()$released)
  })
})

test_that("coordinate UI is absent without the coordinate capability", {
  call <- function(name, ...) {
    if (name == "get_capabilities") {
      return("panel")
    }
    stop("Unauthorized read")
  }
  shiny::testServer(delphyrApp:::communications_server, args = list(study = function() "study", lang = function() "en", call = call, services = campaign_services()), {
    session$flushReact()
    expect_false(allowed())
  })
})

test_that("an editor can start from empty provenance tables", {
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "edit",
      get_qualitative_provenance = list(
        sources = data.frame(id = character(), source_ref = character()),
        themes = data.frame(id = character(), label = character(), version = integer())
      ),
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::editorial_server, args = list(study = function() "study", lang = function() "en", call = call, services = editorial_services()), {
    session$flushReact()
    expect_match(output$body$html, "Preserve original", fixed = TRUE)
    expect_false(grepl("Independent review", output$body$html, fixed = TRUE))
  })
})

test_that("a round without enrollments shows no recipient control and no output error", {
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "coordinate",
      list_campaign_rounds = data.frame(id = "round", number = 1L, state = "draft"),
      list_campaign_enrollments = data.frame(enrollment_id = character(), pseudonym = character(), state = character()),
      stop("Unexpected service")
    )
  }
  names <- c("get_capabilities", "list_campaign_rounds", "list_campaign_enrollments", "prepare_campaign", "preview_campaign", "release_campaign", "cancel_campaign")
  services <- stats::setNames(rep(list(function(...) NULL), length(names)), names)
  shiny::testServer(delphyrApp:::communications_server, args = list(study = function() "study", lang = function() "en", call = call, services = services), {
    session$flushReact()
    session$setInputs(round = "round")
    # An empty recipient list is a silent, empty output rather than an error.
    expect_error(output$recipients, class = "shiny.silent.error")
  })
})

delivery_module_services <- function() {
  names <- c("get_capabilities", "list_campaign_rounds", "list_campaign_enrollments", "prepare_campaign", "preview_campaign", "release_campaign", "cancel_campaign", "list_uncertain_deliveries", "resolve_delivery")
  stats::setNames(rep(list(function(...) NULL), length(names)), names)
}

test_that("approval passes the send time and explains refused reminder limits", {
  released <- list()
  refusal <- "campaign.reminder_limit"
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "coordinate",
      list_campaign_rounds = data.frame(id = "round", number = 1L, state = "open"),
      list_campaign_enrollments = data.frame(enrollment_id = c("e1", "e2"), pseudonym = c("p1", "p2"), state = "eligible", reminders = c(0L, 2L)),
      list_uncertain_deliveries = data.frame(),
      prepare_campaign = list(id = "campaign", hash = "hash", n_recipients = 1L),
      preview_campaign = list(
        id = "campaign", kind = "reminder", subject = "Synthetic subject", body = "Synthetic body", locale = "en", hash = "hash",
        rules = list(timezone = "Europe/Berlin", quiet_start = "20:00", quiet_end = "08:00", max_reminders = 2, min_reminder_interval_hours = 48),
        schedule = if (length(released)) list(not_before = "2026-12-01T08:00:00Z") else NULL, released = length(released) > 0, cancelled = FALSE,
        recipients = data.frame(enrollment_id = "e1", pseudonym = "p1", delivery_state = if (length(released)) "queued" else "draft", reason = NA)
      ),
      release_campaign = {
        if (!is.null(refusal)) stop(structure(list(message = "conflict", call = NULL, code = "DEL_CONFLICT", path = refusal), class = c("DEL_CONFLICT", "delphyr_error", "error", "condition")))
        released[[length(released) + 1L]] <<- list(...)
        list(id = "campaign", n_recipients = 1L, not_before = "2026-12-01T08:00:00Z")
      },
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::communications_server, args = list(study = function() "study", lang = function() "en", call = call, services = delivery_module_services()), {
    session$flushReact()
    session$setInputs(round = "round")
    expect_match(output$recipients$html, "reminders: 2", fixed = TRUE)
    session$setInputs(enrollments = "e1", kind = "reminder", subject = "Synthetic subject", message = "Synthetic body", locale = "en", version = 1, prepare = 1)
    expect_match(output$preview$html, "Quiet hours: 20:00", fixed = TRUE)
    expect_match(output$preview$html, "Maximum reminders per person and round: 2", fixed = TRUE)
    session$setInputs(reason = "Reviewed", confirm = TRUE, not_before = "2026-12-01T09:00:00+01:00", release = 1)
    expect_match(output$status, "maximum number of reminders", fixed = TRUE)
    expect_length(released, 0L)
    refusal <<- "campaign.reminder_interval"
    session$setInputs(release = 2)
    expect_match(output$status, "minimum interval", fixed = TRUE)
    refusal <<- "campaign.not_before"
    session$setInputs(release = 3)
    expect_match(output$status, "needs a timezone", fixed = TRUE)
    refusal <<- NULL
    session$setInputs(release = 4)
    expect_identical(released[[1]]$not_before, "2026-12-01T09:00:00+01:00")
    expect_match(output$status, "No email will be sent", fixed = TRUE)
    expect_match(output$preview$html, "Approved from (UTC): 2026-12-01T08:00:00Z", fixed = TRUE)
  })
})

test_that("an uncertain delivery is resolved only with rationale and confirmation", {
  pending <- TRUE
  resolved <- list()
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "coordinate",
      list_campaign_rounds = data.frame(id = "round", number = 1L, state = "open"),
      list_campaign_enrollments = data.frame(enrollment_id = "e1", pseudonym = "p1", state = "eligible", reminders = 0L),
      list_uncertain_deliveries = if (pending) data.frame(message_id = "message", kind = "reminder", round_number = 1L, pseudonym = "p1", reason = "adapter_outcome_unknown", adapter = "test_provider", attempts = 1L, updated_at = "2026-10-02 10:00:00+00") else data.frame(),
      resolve_delivery = {
        resolved[[length(resolved) + 1L]] <<- list(...)
        pending <<- FALSE
        list(id = "message", state = "abandoned")
      },
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::communications_server, args = list(study = function() "study", lang = function() "en", call = call, services = delivery_module_services()), {
    session$flushReact()
    expect_match(output$body$html, "Resolve uncertain deliveries (1)", fixed = TRUE)
    expect_match(output$uncertain, "test_provider", fixed = TRUE)
    expect_match(output$uncertain, "Reminder", fixed = TRUE)
    session$setInputs(uncertain_message = "message", resolution = "abandon", resolution_reason = "", resolution_confirm = TRUE, resolve = 1)
    expect_length(resolved, 0L)
    session$setInputs(resolution_reason = "Provider confirms no acceptance", resolution_confirm = FALSE, resolve = 2)
    expect_length(resolved, 0L)
    session$setInputs(resolution_confirm = TRUE, resolve = 3)
    expect_identical(resolved[[1]], list("study", "message", "abandon", "Provider confirms no acceptance", resolved[[1]][[5]]))
    expect_match(output$status, "Delivery decision saved", fixed = TRUE)
    expect_match(output$body$html, "Resolve uncertain deliveries (0)", fixed = TRUE)
  })
  expect_identical(delivery_label(c("accepted", "abandoned", "other"), "en"), c("Accepted by the provider", "Abandoned", "other"))
  expect_identical(operation_state_label(c("dead_letter", "retry_wait"), "de"), c("Endg\u00fcltig fehlgeschlagen", "Wartet auf Wiederholung"))
})

test_that("managers read the status of background work without content", {
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "manage",
      get_study_setup = list(protocol = list(study = list(timezone = "UTC"))),
      list_rounds = data.frame(id = "round", number = 1L, state = "open", instrument_hash = "h", deadline = as.POSIXct("2026-12-01 10:00:00", tz = "UTC")),
      get_operations_status = list(
        jobs = data.frame(type = c("analysis", "export"), profile = c("analysis", "study_summary"), state = c("succeeded", "dead_letter"), n = c(1L, 1L), oldest_waiting_seconds = c(0L, 0L), error_codes = c(NA, "DEL_RENDER")),
        messages = data.frame(state = c("queued", "delivery_unknown"), n = c(2L, 1L), oldest_waiting_seconds = c(40L, 0L)), uncertain_deliveries = 1L
      ),
      stop("Unexpected service")
    )
  }
  names <- c("get_capabilities", "get_study_setup", "list_rounds", "transition_round", "get_operations_status")
  services <- stats::setNames(rep(list(function(...) NULL), length(names)), names)
  shiny::testServer(delphyrApp:::management_server, args = list(study = function() "study", lang = function() "en", call = call, services = services), {
    session$flushReact()
    expect_match(output$body$html, "Status of background work", fixed = TRUE)
    session$setInputs(background_load = 1)
    expect_match(output$background_jobs, "Export study_summary", fixed = TRUE)
    expect_match(output$background_jobs, "Permanently failed", fixed = TRUE)
    expect_match(output$background_jobs, "DEL_RENDER", fixed = TRUE)
    expect_match(output$background_messages, "Outcome unknown", fixed = TRUE)
  })
})
