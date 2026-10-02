setup_services <- function(names) stats::setNames(rep(list(function(...) NULL), length(names)), names)
setup_protocol_file <- function(protocol = delphyr::demo_protocol(), env = parent.frame()) {
  path <- tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(protocol, auto_unbox = TRUE, null = "null", digits = NA), path)
  withr::defer(unlink(path), envir = env)
  data.frame(name = "protocol.json", size = file.info(path)$size, datapath = path, type = "application/json")
}

test_that("a study is created only from a validated, displayed and confirmed protocol", {
  created <- list()
  joined <- character()
  call <- function(name, ...) {
    switch(name,
      get_account_rights = list(can_create_study = TRUE),
      create_study = {
        created[[length(created) + 1L]] <<- list(...)
        list(id = "new-study", protocol_id = "protocol")
      },
      stop("Unexpected service")
    )
  }
  file <- setup_protocol_file()
  invalid <- delphyr::demo_protocol()
  invalid$analysis$consensus$min_valid_n <- 0
  bad <- setup_protocol_file(invalid)
  shiny::testServer(delphyrApp:::study_create_server, args = list(lang = function() "en", call = call, services = setup_services(c("get_account_rights", "create_study")), on_created = function(id) joined <<- c(joined, id)), {
    expect_true(allowed())
    session$setInputs(file = bad, validate = 1)
    expect_null(candidate())
    expect_match(output$status, "Protocol is invalid. Field in question: consensus.min_valid_n", fixed = TRUE)
    session$setInputs(file = file, validate = 2)
    expect_match(output$status, "Protocol is valid", fixed = TRUE)
    expect_match(output$summary, "DEMO-001", fixed = TRUE)
    expect_match(output$summary, "in every required group", fixed = TRUE)
    session$setInputs(confirm = FALSE, create = 1)
    expect_length(created, 0L)
    expect_match(output$status, "confirm the protocol", fixed = TRUE)
    # The approved content is bound to the validated upload.
    writeLines(jsonlite::toJSON(invalid, auto_unbox = TRUE, null = "null", digits = NA), file$datapath)
    session$setInputs(confirm = TRUE, create = 2)
    expect_length(created, 0L)
    writeLines(jsonlite::toJSON(delphyr::demo_protocol(), auto_unbox = TRUE, null = "null", digits = NA), file$datapath)
    session$setInputs(create = 3)
    expect_length(created, 1L)
    expect_identical(created[[1]][[1]]$study$code, "DEMO-001")
    expect_identical(joined, "new-study")
    expect_null(candidate())
    expect_match(output$status, "Study created: DEMO-001", fixed = TRUE)
  })
})

test_that("accounts without the creation right are not offered study creation", {
  call <- function(name, ...) if (name == "get_account_rights") list(can_create_study = FALSE) else stop("must not be called")
  shiny::testServer(delphyrApp:::study_create_server, args = list(lang = function() "en", call = call, services = setup_services(c("get_account_rights", "create_study"))), {
    expect_false(allowed())
    expect_error(output$body)
    session$setInputs(file = setup_protocol_file(), validate = 1)
    expect_null(candidate())
  })
})

setup_state <- function() {
  state <- new.env()
  state$calls <- list()
  state$capabilities <- "manage"
  state
}
setup_call <- function(state) {
  function(name, ...) {
    state$calls[[length(state$calls) + 1L]] <- list(name, ...)
    switch(name,
      get_capabilities = state$capabilities,
      get_study_setup = list(protocol = list(study = list(languages = list("en", "de")), panel = list(groups = list("professionals", "public_contributors"))), consent_versions = data.frame(id = "consent", locale = "en", content = "Synthetic information", hash = "h")),
      list_study_staff = data.frame(principal_id = "manager-id", issuer = "urn:delphyr:demo", subject = "demo-manager", active = TRUE, granted = "analyse, manage", revoked = "export"),
      list_panel = data.frame(panelist_id = c("pseudonym-a", "pseudonym-b"), group_code = c("professionals", "public_contributors"), active = c(TRUE, FALSE), withdrawn = c(FALSE, TRUE), rounds_enrolled = c(1L, 1L), rounds_submitted = c(1L, 0L)),
      publish_consent = list(id = "consent-2"),
      register_staff_account = list(id = "new-account"),
      set_capability = list(id = "membership"),
      set_panel_group = list(id = "event", group_code = "public_contributors"),
      stop("Unexpected service")
    )
  }
}
setup_needed <- c("get_capabilities", "get_study_setup", "publish_consent", "list_study_staff", "register_staff_account", "set_capability", "list_panel", "set_panel_group")
setup_called <- function(state, name) Filter(function(x) x[[1]] == name, state$calls)

test_that("study information is published only with text and confirmation", {
  state <- setup_state()
  shiny::testServer(delphyrApp:::study_setup_server, args = list(study = function() "study", lang = function() "en", call = setup_call(state), services = setup_services(setup_needed)), {
    session$flushReact()
    expect_match(output$consents, "Synthetic information", fixed = TRUE)
    session$setInputs(consent_text = " ", consent_locale = "en", consent_confirm = TRUE, consent_publish = 1)
    expect_length(setup_called(state, "publish_consent"), 0L)
    session$setInputs(consent_text = "New synthetic information", consent_confirm = FALSE, consent_publish = 2)
    expect_length(setup_called(state, "publish_consent"), 0L)
    expect_match(output$status, "text and confirmation", fixed = TRUE)
    session$setInputs(consent_confirm = TRUE, consent_locale = "de", consent_publish = 3)
    done <- setup_called(state, "publish_consent")[[1]]
    expect_identical(done[2:4], list("study", "New synthetic information", "de"))
    expect_match(output$status, "Study information published", fixed = TRUE)
  })
})

test_that("rights change only for an exact account with rationale and confirmation", {
  state <- setup_state()
  shiny::testServer(delphyrApp:::study_setup_server, args = list(study = function() "study", lang = function() "en", call = setup_call(state), services = setup_services(setup_needed)), {
    session$flushReact()
    expect_match(output$staff, "demo-manager", fixed = TRUE)
    expect_match(output$staff, "Analysis; Study leadership", fixed = TRUE)
    expect_match(output$staff, "Research data export", fixed = TRUE)
    session$setInputs(staff_account = "manager-id", staff_capability = "audit", staff_action = "grant", staff_reason = "", staff_confirm = TRUE, staff_apply = 1)
    expect_length(setup_called(state, "set_capability"), 0L)
    expect_match(output$status, "reason and confirmation", fixed = TRUE)
    session$setInputs(staff_reason = "Reviews the history", staff_confirm = FALSE, staff_apply = 2)
    expect_length(setup_called(state, "set_capability"), 0L)
    session$setInputs(staff_confirm = TRUE, staff_apply = 3)
    grant <- setup_called(state, "set_capability")[[1]]
    expect_identical(unname(grant[2:5]), list("study", "manager-id", "audit", TRUE))
    expect_identical(grant$reason, "Reviews the history")
    expect_length(setup_called(state, "register_staff_account"), 0L)
    session$setInputs(staff_account = "new", staff_issuer = " https://idp.example.invalid ", staff_subject = "subject-9", staff_capability = "export", staff_action = "revoke", staff_reason = "Duty ended", staff_confirm = TRUE, staff_apply = 4)
    registered <- setup_called(state, "register_staff_account")[[1]]
    expect_identical(registered[2:5], list("study", "https://idp.example.invalid", "subject-9", "Duty ended"))
    revoke <- setup_called(state, "set_capability")[[2]]
    expect_identical(unname(revoke[2:5]), list("study", "new-account", "export", FALSE))
    # Giving up the own management right hides the section at once.
    state$capabilities <- "analyse"
    session$setInputs(staff_account = "manager-id", staff_capability = "manage", staff_action = "revoke", staff_reason = "Handover", staff_confirm = TRUE, staff_apply = 5)
    expect_false(allowed())
    expect_error(output$body)
  })
})

test_that("the panel is pseudonymous and a group change needs rationale and confirmation", {
  state <- setup_state()
  shiny::testServer(delphyrApp:::study_setup_server, args = list(study = function() "study", lang = function() "en", call = setup_call(state), services = setup_services(setup_needed)), {
    session$flushReact()
    expect_match(output$panel, "pseudonym-a", fixed = TRUE)
    expect_match(output$panel, "Participation ended", fixed = TRUE)
    session$setInputs(group_panelist = "pseudonym-a", group_code = "public_contributors", group_reason = "Role changed", group_confirm = FALSE, group_apply = 1)
    expect_length(setup_called(state, "set_panel_group"), 0L)
    session$setInputs(group_confirm = TRUE, group_apply = 2)
    changed <- setup_called(state, "set_panel_group")[[1]]
    expect_identical(changed[2:5], list("study", "pseudonym-a", "public_contributors", "Role changed"))
    expect_match(output$status, "Earlier rounds are unchanged", fixed = TRUE)
  })
  call <- function(name, ...) if (name == "get_capabilities") "coordinate" else stop("must not be called")
  shiny::testServer(delphyrApp:::study_setup_server, args = list(study = function() "study", lang = function() "en", call = call, services = setup_services(setup_needed)), {
    session$flushReact()
    expect_false(allowed())
    expect_error(output$body)
  })
})

test_that("item decisions bind the displayed analysis and need rationale and confirmation", {
  names <- c("freeze_round", "request_analysis", "get_operation", "get_analysis", "create_feedback", "get_feedback_candidate", "release_feedback", "assign_feedback", "request_export", "download_artifact", "get_study_setup", "prepare_round", "record_item_decision", "list_item_decisions")
  recorded <- list()
  call <- function(name, ...) {
    switch(name,
      get_study_setup = list(protocol = list(), consent_versions = data.frame(id = "consent", locale = "en", content = "Synthetic")),
      get_analysis = list(results = data.frame(item_code = "I001", n_valid = 12), decisions = data.frame(item_code = c("I001", "I002"), classification = c("no_consensus", "consensus_in"))),
      list_item_decisions = if (length(recorded)) data.frame(round_number = 1L, item_code = "I002", disposition = "finalize", reason = "Consensus reached", decided_at = "now") else data.frame(),
      record_item_decision = {
        recorded[[length(recorded) + 1L]] <<- list(...)
        list(id = "decision")
      },
      stop("unexpected service")
    )
  }
  round <- function() data.frame(id = "round", number = 1L, snapshot_id = "snapshot", analysis_id = "analysis")
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = round, lang = function() "en", call = call, services = setup_services(names), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$body$html, "Item decisions", fixed = TRUE)
    session$setInputs(decision_code = "I002", disposition = "finalize", decision_reason = "Consensus reached", decision_confirm = TRUE, decide = 1)
    expect_length(recorded, 0L)
    expect_match(output$status, "View the analysis", fixed = TRUE)
    session$setInputs(read = 1)
    session$setInputs(decision_reason = "", decide = 2)
    expect_length(recorded, 0L)
    session$setInputs(decision_reason = "Consensus reached", decision_confirm = FALSE, decide = 3)
    expect_length(recorded, 0L)
    session$setInputs(decision_confirm = TRUE, decide = 4)
    expect_identical(recorded[[1]][1:4], list("analysis", "I002", "finalize", "Consensus reached"))
    expect_match(output$status, "Item decision saved: I002", fixed = TRUE)
    expect_match(output$decisions, "Finalize", fixed = TRUE)
    expect_match(output$decisions, "Consensus reached", fixed = TRUE)
  })
  expect_identical(disposition_label(c("rerate", "other"), "de"), c("Erneut bewerten", "other"))
  expect_identical(staff_capability_label(c("manage", "contacts_export"), "en"), c("Study leadership", "Contact export"))
})

test_that("instrument validation uses the current protocol and study information", {
  names <- c("freeze_round", "request_analysis", "get_operation", "get_analysis", "create_feedback", "get_feedback_candidate", "release_feedback", "assign_feedback", "request_export", "download_artifact", "get_study_setup", "prepare_round")
  published <- FALSE
  prepared <- list()
  call <- function(name, ...) {
    switch(name,
      get_study_setup = list(protocol = delphyr::demo_protocol(), consent_versions = if (published) data.frame(id = "consent", locale = "en", content = "Synthetic") else data.frame(id = character(), locale = character(), content = character())),
      prepare_round = {
        prepared[[length(prepared) + 1L]] <<- list(...)
        list(id = "round", hash = "h")
      },
      stop("unexpected service")
    )
  }
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  utils::write.csv(data.frame(item_code = "I001", item_version = 1L, locale = c("de", "en"), text = c("Synthetisches Item", "Synthetic item"), dimension_code = "relevance", scale_code = "relevance_9", source_ref = "SRC", required = TRUE, display_order = 1L), path, row.names = FALSE)
  file <- data.frame(name = "items.csv", size = file.info(path)$size, datapath = path, type = "text/csv")
  round <- function() data.frame(id = "round", number = 1L, snapshot_id = NA_character_, analysis_id = NA_character_)
  shiny::testServer(delphyrApp:::operations_server, args = list(study = function() "study", round = round, lang = function() "en", call = call, services = setup_services(names), refresh = function() NULL, allowed = function() TRUE), {
    session$flushReact()
    expect_match(output$consents$html, "Publish the study information under Setup first.", fixed = TRUE)
    # The study information is published in another section of the same session.
    published <<- TRUE
    session$setInputs(csv = file, validate = 1)
    expect_match(output$status, "Import validated", fixed = TRUE)
    expect_match(output$consents$html, "Synthetic", fixed = TRUE)
    session$setInputs(consent = "consent", deadline = "2026-12-01T18:00:00+01:00", prepare = 1)
    expect_length(prepared, 1L)
    expect_identical(prepared[[1]][[3]], "consent")
  })
})
