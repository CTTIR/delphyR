governance_services <- function(names) stats::setNames(rep(list(function(...) NULL), length(names)), names)

test_that("history is offered to audit and management roles and labels every event", {
  capabilities <- shiny::reactiveVal("audit")
  requests <- list()
  call <- function(name, ...) {
    switch(name,
      get_capabilities = capabilities(),
      list_audit_events = {
        requests[[length(requests) + 1L]] <<- list(...)
        data.frame(
          occurred_at = c("2026-10-02T10:00:00.000Z", "2026-10-02T09:00:00.000Z", "2026-10-02T08:00:00.000Z"),
          action = c("transition_round", "save", "request_export:study_summary"), detail = c("open", NA, "study_summary"),
          object_ref = c("round-id", "revision-id", "job-id"), reason = c("Recruitment complete", NA, NA),
          actor_kind = c("staff", "panel", "staff"), actor_ref = c("staff-principal", NA, "staff-principal"), stringsAsFactors = FALSE
        )
      },
      stop("Unexpected service")
    )
  }
  selected_study <- shiny::reactiveVal("study")
  shiny::testServer(delphyrApp:::audit_server, args = list(study = function() selected_study(), lang = function() "en", call = call, services = governance_services(c("get_capabilities", "list_audit_events"))), {
    session$flushReact()
    expect_true(allowed())
    session$setInputs(limit = 99999, load = 1)
    expect_null(events())
    expect_match(output$status, "No success was confirmed", fixed = TRUE)
    session$setInputs(limit = 50, actions = c("save", "submit"), load = 2)
    expect_identical(requests[[1]]$actions, c("save", "submit"))
    expect_identical(requests[[1]]$limit, 50)
    html <- output$events
    expect_match(html, "Round state changed", fixed = TRUE)
    expect_match(html, "Recruitment complete", fixed = TRUE)
    expect_match(html, "Staff account staff-principal", fixed = TRUE)
    expect_match(html, "Panel member", fixed = TRUE)
    expect_match(html, "Export requested", fixed = TRUE)
    expect_false(grepl("NA", html, fixed = TRUE))
    expect_match(output$status, "3 events shown", fixed = TRUE)
    # Another study never shows the previous study's events.
    capabilities("panel")
    selected_study("other")
    session$flushReact()
    expect_false(allowed())
    expect_null(events())
  })
  expect_identical(audit_action_label(c("save", "unknown_code", "request_export:audit_restricted"), "de"), c("Antwort gespeichert", "unknown_code", "Export beauftragt"))
  expect_true(all(audit_action_label(audit_action_codes(), "en") != audit_action_codes()))
})

test_that("documentation saves only confirmed, reasoned, non-empty versions", {
  saved <- list()
  version <- 1L
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "manage",
      get_study_documentation = list(version = version, hash = "h", fields = list(funding = "Stored funding statement"), history = data.frame(version = seq_len(version), hash = "h", reason = paste("Reason", seq_len(version)), recorded_at = "2026-10-02 10:00:00+00")),
      record_study_documentation = {
        saved[[length(saved) + 1L]] <<- list(...)
        version <<- version + 1L
        list(id = "doc", hash = "h2", version = version)
      },
      stop("Unexpected service")
    )
  }
  services <- governance_services(c("get_capabilities", "get_study_documentation", "record_study_documentation"))
  shiny::testServer(delphyrApp:::documentation_server, args = list(study = function() "study", lang = function() "en", call = call, services = services), {
    session$flushReact()
    expect_match(output$body$html, "Stored funding statement", fixed = TRUE)
    expect_match(output$body$html, "Current documentation version: 1", fixed = TRUE)
    session$setInputs(funding = "Stored funding statement", authors_responsibilities = "Synthetic author", reason = "", confirm = TRUE, save = 1)
    expect_length(saved, 0L)
    session$setInputs(reason = "Authors added", confirm = FALSE, save = 2)
    expect_length(saved, 0L)
    session$setInputs(funding = " ", authors_responsibilities = "", confirm = TRUE, save = 3)
    expect_length(saved, 0L)
    expect_match(output$status, "At least one topic", fixed = TRUE)
    session$setInputs(funding = "Stored funding statement", authors_responsibilities = "Synthetic author", conflicts_of_interest = "", save = 4)
    expect_length(saved, 1L)
    expect_identical(saved[[1]][[2]], list(authors_responsibilities = "Synthetic author", funding = "Stored funding statement"))
    expect_identical(saved[[1]][[3]], 1L)
    expect_identical(saved[[1]][[4]], "Authors added")
    expect_match(output$status, "Documentation version saved: 2", fixed = TRUE)
    expect_match(output$history, "Reason 2", fixed = TRUE)
  })
  expect_identical(unname(documentation_topic_labels("de")[["funding"]]), "Finanzierung")
})

test_that("study exports offer only permitted profiles and require an entitlement confirmation", {
  capabilities <- shiny::reactiveVal(c("analyse", "audit"))
  requested <- character()
  state <- "queued"
  call <- function(name, ...) {
    switch(name,
      get_capabilities = capabilities(),
      request_study_export = {
        requested <<- c(requested, list(...)[[2]])
        list(id = "job", state = "queued")
      },
      get_operation = data.frame(id = "job", state = state, result_ref = if (state == "succeeded") "artifact" else NA_character_),
      stop("Unexpected service")
    )
  }
  services <- governance_services(c("get_capabilities", "request_study_export", "get_operation", "download_artifact"))
  selected_study <- shiny::reactiveVal("study")
  shiny::testServer(delphyrApp:::exports_server, args = list(study = function() selected_study(), lang = function() "en", call = call, services = services), {
    session$flushReact()
    expect_identical(profiles(), c("study_summary", "audit_restricted"))
    expect_false(grepl("Contact data", output$body$html, fixed = TRUE))
    expect_false(grepl("Pseudonymized research data", output$body$html, fixed = TRUE))
    session$setInputs(profile = "study_summary", confirm = FALSE, request = 1)
    expect_length(requested, 0L)
    expect_match(output$status, "confirm your entitlement", fixed = TRUE)
    expect_match(output$description, "without individual responses", fixed = TRUE)
    # A profile outside the offered ones is never requested.
    session$setInputs(profile = "contacts_restricted", confirm = TRUE, request = 2)
    expect_length(requested, 0L)
    session$setInputs(profile = "study_summary", confirm = TRUE, request = 3)
    expect_identical(requested, "study_summary")
    session$setInputs(poll = 1)
    expect_null(artifact())
    state <<- "succeeded"
    session$setInputs(poll = 2)
    expect_identical(artifact(), "artifact")
    session$setInputs(profile = "audit_restricted")
    expect_null(artifact())
    capabilities("panel")
    selected_study("other")
    session$flushReact()
    expect_length(profiles(), 0L)
    expect_error(output$body)
  })
})

test_that("navigation and guidance follow audit and export rights", {
  expect_identical(workspace_sections("audit", "en")$id, c("section-exports", "section-audit"))
  expect_identical(workspace_sections("contacts_export", "en")$id, "section-exports")
  expect_identical(workspace_sections("panel", "en")$id, "section-panel")
  expect_true(all(c("section-documentation", "section-exports", "section-audit") %in% workspace_sections("manage", "en")$id))
  expect_match(workspace_intro("audit", "en"), "recorded history", fixed = TRUE)
  expect_match(workspace_intro("analyse", "en"), "exports your role permits", fixed = TRUE)
})

test_that("a revised item shows the study team's comparability decision", {
  q <- list(
    protocol = list(instrument = list(scales = list(rating = list(type = "ordinal_integer", values = 1:9, missing_options = c("unable_to_judge"))))),
    enrollment = list(id = "own"),
    responses = data.frame(round_item_id = character(), revision = integer(), status = character(), value_int = integer(), value_text = character()),
    feedback = list(
      own = data.frame(item_code = "I001", item_version = 1L, dimension_code = "relevance", answer_status = "answered", value_integer = 7L, value_text = NA_character_),
      aggregate = list(results = data.frame(item_code = "I001", dimension_code = "relevance", n_valid = 12L)),
      comparability = data.frame(item_code = "I001", dimension_code = "relevance", previous_version = 1L, current_version = 2L, comparable = TRUE)
    )
  )
  item <- data.frame(id = "item", item_code = "I001", item_version = 2L, scale_code = "rating", texts = '{"en":"Revised question"}', dimension_code = "relevance", required = TRUE)
  shiny::testServer(delphyrApp:::rating_server, args = list(q = q, item = item, lang = function() "en", call = function(...) NULL, autosave_ms = 0), {
    expect_match(output$prior$html, "assessed both versions as comparable", fixed = TRUE)
  })
  q$feedback$comparability$comparable <- FALSE
  shiny::testServer(delphyrApp:::rating_server, args = list(q = q, item = item, lang = function() "en", call = function(...) NULL, autosave_ms = 0), {
    expect_match(output$prior$html, "not directly comparable", fixed = TRUE)
  })
  q$feedback$comparability <- NULL
  shiny::testServer(delphyrApp:::rating_server, args = list(q = q, item = item, lang = function() "en", call = function(...) NULL, autosave_ms = 0), {
    expect_match(output$prior$html, "not directly comparable", fixed = TRUE)
  })
})

test_that("comparability decisions need rationale and confirmation in the editorial module", {
  recorded <- list()
  call <- function(name, ...) {
    switch(name,
      get_capabilities = c("manage", "edit"),
      get_qualitative_provenance = list(sources = data.frame(id = character(), source_ref = character(), original_text = character()), themes = data.frame(id = character(), label = character(), version = integer())),
      list_qualitative_reviews = data.frame(id = character(), source_ref = character(), kind = character(), released = logical(), can_review = logical()),
      get_item_comparability = if (length(recorded)) data.frame(item_code = "I001", dimension_code = "relevance", previous_version = 1L, current_version = 2L, comparable = TRUE, reason = "Clarified wording only", recorded_at = "now", effective = TRUE) else data.frame(),
      record_item_comparability = {
        recorded[[length(recorded) + 1L]] <<- list(...)
        list(id = "decision")
      },
      stop("Unexpected service")
    )
  }
  names <- c("get_capabilities", "get_qualitative_provenance", "list_qualitative_reviews", "record_qualitative_source", "redact_qualitative_source", "release_qualitative_edit", "create_qualitative_theme", "code_qualitative_source", "link_item_source", "record_item_lineage", "record_item_comparability", "get_item_comparability")
  shiny::testServer(delphyrApp:::editorial_server, args = list(study = function() "study", lang = function() "en", call = call, services = governance_services(names)), {
    session$flushReact()
    expect_match(output$body$html, "Decide the comparability of two item versions", fixed = TRUE)
    session$setInputs(comparable_item = " I001 ", comparable_dimension = "relevance", comparable_previous = 1, comparable_current = 2, comparable_decision = "yes", comparable_reason = "", comparable_confirm = TRUE, comparable_save = 1)
    expect_length(recorded, 0L)
    session$setInputs(comparable_reason = "Clarified wording only", comparable_confirm = FALSE, comparable_save = 2)
    expect_length(recorded, 0L)
    session$setInputs(comparable_confirm = TRUE, comparable_save = 3)
    expect_identical(recorded[[1]][2:6], list("I001", "relevance", 1, 2, TRUE))
    expect_identical(recorded[[1]][[7]], "Clarified wording only")
    expect_match(output$status, "Comparability decision saved", fixed = TRUE)
    expect_match(output$comparability, "Clarified wording only", fixed = TRUE)
  })
})

test_that("a change in another section refreshes rounds, drafts and offered profiles", {
  signal <- shiny::reactiveVal(0L)
  available_rounds <- data.frame(id = character(), number = integer(), state = character())
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "coordinate",
      list_campaign_rounds = available_rounds,
      list_campaign_enrollments = data.frame(enrollment_id = "e1", pseudonym = "p1", state = "eligible"),
      stop("Unexpected service")
    )
  }
  names <- c("get_capabilities", "list_campaign_rounds", "list_campaign_enrollments", "prepare_campaign", "preview_campaign", "release_campaign", "cancel_campaign")
  shiny::testServer(delphyrApp:::communications_server, args = list(study = function() "study", lang = function() "en", call = call, services = governance_services(names), changed = function() signal()), {
    session$flushReact()
    expect_false(grepl("Round 1", output$body$html, fixed = TRUE))
    available_rounds <<- data.frame(id = "round", number = 1L, state = "open")
    signal(1L)
    session$flushReact()
    expect_match(output$body$html, "Round 1 Open", fixed = TRUE)
  })
  granted <- "analyse"
  call <- function(name, ...) if (name == "get_capabilities") granted else stop("Unexpected service")
  shiny::testServer(delphyrApp:::exports_server, args = list(study = function() "study", lang = function() "en", call = call, services = governance_services(c("get_capabilities", "request_study_export", "get_operation", "download_artifact")), changed = function() signal()), {
    session$flushReact()
    expect_identical(profiles(), "study_summary")
    granted <<- c("analyse", "contacts_export")
    signal(2L)
    session$flushReact()
    expect_identical(profiles(), c("study_summary", "contacts_restricted"))
  })
  draft_reads <- 0L
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "coordinate",
      list_panel_invitations = {
        draft_reads <<- draft_reads + 1L
        data.frame(draft_id = character(), external_ref = character(), display_name = character(), stakeholder_group = character(), locale = character(), invitation_id = character(), expires_at = character(), state = character())
      },
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::invitations_server, args = list(study = function() "study", lang = function() "en", call = call, services = governance_services(c("get_capabilities", "list_panel_invitations", "register_invited_account", "issue_panel_invitation", "revoke_panel_invitation")), changed = function() signal()), {
    session$flushReact()
    expect_identical(draft_reads, 1L)
    signal(3L)
    session$flushReact()
    expect_identical(draft_reads, 2L)
  })
})
