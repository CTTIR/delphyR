setup_lane_services <- function(names) stats::setNames(rep(list(function(...) NULL), length(names)), names)
setup_lane_needed <- c("get_capabilities", "get_study_setup", "publish_consent", "list_study_staff", "register_staff_account", "set_capability", "list_panel", "set_panel_group")
setup_lane_file <- function(protocol = delphyr::demo_protocol(), env = parent.frame()) {
  path <- tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(protocol, auto_unbox = TRUE, null = "null", digits = NA), path)
  withr::defer(unlink(path), envir = env)
  data.frame(name = "protocol.json", size = file.info(path)$size, datapath = path, type = "application/json")
}
setup_lane_call <- function(calls) {
  function(name, ...) {
    calls$list[[length(calls$list) + 1L]] <- list(name, ...)
    switch(name,
      get_capabilities = "manage",
      get_study_setup = list(protocol = list(study = list(languages = list("en", "de")), panel = list(groups = list("professionals", "public_contributors"))), consent_versions = data.frame(id = "consent", locale = "de", content = "Synthetische Information", hash = "h")),
      list_study_staff = data.frame(principal_id = c("lead-id", "reviewer-id"), issuer = "urn:delphyr:demo", subject = c("demo-lead", "demo-reviewer"), active = c(TRUE, FALSE), granted = c("analyse, manage", "manage"), revoked = c("", "export")),
      list_panel = data.frame(panelist_id = c("2fc87382-1c07-4c6e-9409-35e75f5401e5", "eca6054d-e44d-4be9-8e1b-6a833766258a"), group_code = c("professionals", "public_contributors"), active = c(TRUE, FALSE), withdrawn = c(FALSE, FALSE), rounds_enrolled = 1L, rounds_submitted = 1L),
      register_staff_account = list(id = "new-account"),
      set_capability = list(id = "membership"),
      set_panel_group = list(id = "event"),
      publish_consent = list(id = "consent-2"),
      stop("Unexpected service")
    )
  }
}
setup_lane_called <- function(calls, name) Filter(function(x) x[[1]] == name, calls$list)
# The rationale and confirmation of a protocol approval carry the key of
# their form; the approve button does not.
setup_lane_approval <- function(session, key, ...) {
  values <- list(...)
  keyed <- names(values) %in% c("reason", "confirm")
  names(values)[keyed] <- paste0(names(values)[keyed], "_", key)
  do.call(session$setInputs, values)
}

test_that("a change of rights needs an explicit account and says whose rights change", {
  calls <- new.env()
  calls$list <- list()
  shiny::testServer(delphyrApp:::study_setup_server, args = list(study = function() "study", lang = function() "en", call = setup_lane_call(calls), services = setup_lane_services(setup_lane_needed)), {
    session$flushReact()
    html <- output$body$html
    # No account is preselected, the signed-in lead's own included.
    expect_match(html, "<option value=\"\" selected>Choose an account</option>", fixed = TRUE)
    expect_false(grepl("value=\"lead-id\" selected", html, fixed = TRUE))
    # The fields of another account are shown only for that choice.
    expect_match(html, "data-display-if=\"input.staff_account == &#39;new&#39;\"", fixed = TRUE)
    session$setInputs(staff_account = "", staff_capability = "audit", staff_action = "grant", staff_reason = "Reviews the history", staff_confirm = TRUE, staff_apply = 1)
    expect_length(setup_lane_called(calls, "set_capability"), 0L)
    expect_match(output$status, "Choose an account first.", fixed = TRUE)
    expect_identical(output$staff_change, "No account chosen yet.")
    session$setInputs(staff_account = "reviewer-id")
    expect_identical(output$staff_change, "This change grants the right \u201cRead the history (audit)\u201d to demo-reviewer.")
    session$setInputs(staff_action = "revoke")
    expect_identical(output$staff_change, "This change revokes the right \u201cRead the history (audit)\u201d from demo-reviewer.")
    session$setInputs(staff_account = "new", staff_issuer = " ", staff_subject = "subject-9", staff_apply = 2)
    expect_length(setup_lane_called(calls, "register_staff_account"), 0L)
    expect_match(output$status, "Enter the identity provider and the account identifier", fixed = TRUE)
    session$setInputs(staff_issuer = "https://idp.example.invalid")
    expect_identical(output$staff_change, "This change revokes the right \u201cRead the history (audit)\u201d from the account subject-9 of https://idp.example.invalid.")
    session$setInputs(staff_account = "reviewer-id", staff_action = "grant", staff_apply = 3)
    grant <- setup_lane_called(calls, "set_capability")[[1]]
    expect_identical(unname(grant[3:5]), list("reviewer-id", "audit", TRUE))
    expect_length(setup_lane_called(calls, "register_staff_account"), 0L)
    expect_match(output$status, "Change of rights confirmed. Account: demo-reviewer", fixed = TRUE)
  })
  shiny::testServer(delphyrApp:::study_setup_server, args = list(study = function() "study", lang = function() "de", call = setup_lane_call(calls), services = setup_lane_services(setup_lane_needed)), {
    session$flushReact()
    session$setInputs(staff_account = "reviewer-id", staff_capability = "analyse", staff_action = "grant")
    expect_identical(output$staff_change, "Diese \u00c4nderung erteilt demo-reviewer das Recht \u201eAuswertung\u201c.")
  })
})

test_that("team, panel and study information are shown with labels, names and short pseudonyms", {
  calls <- new.env()
  calls$list <- list()
  language <- shiny::reactiveVal("de")
  shiny::testServer(delphyrApp:::study_setup_server, args = list(study = function() "study", lang = function() language(), call = setup_lane_call(calls), services = setup_lane_services(setup_lane_needed)), {
    session$flushReact()
    staff <- output$staff
    expect_match(staff, "Kontokennung", fixed = TRUE)
    expect_match(staff, "Identit\u00e4tsanbieter", fixed = TRUE)
    expect_match(staff, "Aktiv", fixed = TRUE)
    expect_match(staff, "Gesperrt", fixed = TRUE)
    expect_false(grepl("Subject|active|disabled", staff))
    expect_match(staff, "\u2014", fixed = TRUE)
    language("fr")
    session$flushReact()
    staff <- output$staff
    expect_match(staff, "Identifiant du compte", fixed = TRUE)
    expect_false(grepl("Objet", staff, fixed = TRUE))
    language("en")
    session$flushReact()
    panel <- output$panel$html
    expect_match(panel, "<span class=\"del-ref\" title=\"2fc87382-1c07-4c6e-9409-35e75f5401e5\">2fc87382</span>", fixed = TRUE)
    expect_match(panel, "Public contributors", fixed = TRUE)
    expect_match(panel, "Inactive", fixed = TRUE)
    expect_false(grepl("public_contributors", panel, fixed = TRUE))
    html <- output$body$html
    expect_match(html, "<option value=\"2fc87382-1c07-4c6e-9409-35e75f5401e5\">2fc87382 \u00b7 Professionals</option>", fixed = TRUE)
    expect_match(html, "<option value=\"public_contributors\">Public contributors</option>", fixed = TRUE)
    expect_match(html, "<option value=\"de\">Deutsch</option>", fixed = TRUE)
    expect_match(output$consents, "Deutsch", fixed = TRUE)
    # Every row of buttons is spaced from what follows.
    for (id in c("consent_publish", "staff_apply", "group_apply")) expect_match(html, paste0("<div class=\"del-actions\">\\s*<button[^>]*id=\"[^\"]*", id, "\""))
  })
})

test_that("a group change needs a pseudonym and a group the member is not in", {
  calls <- new.env()
  calls$list <- list()
  shiny::testServer(delphyrApp:::study_setup_server, args = list(study = function() "study", lang = function() "en", call = setup_lane_call(calls), services = setup_lane_services(setup_lane_needed)), {
    session$flushReact()
    expect_match(output$body$html, "<option value=\"\" selected>Choose a pseudonym</option>", fixed = TRUE)
    session$setInputs(group_panelist = "", group_code = "public_contributors", group_reason = "Role changed", group_confirm = TRUE, group_apply = 1)
    expect_match(output$status, "Choose a pseudonym and a new group first.", fixed = TRUE)
    session$setInputs(group_panelist = "2fc87382-1c07-4c6e-9409-35e75f5401e5", group_code = "professionals", group_apply = 2)
    expect_match(output$status, "already in that group", fixed = TRUE)
    expect_length(setup_lane_called(calls, "set_panel_group"), 0L)
    session$setInputs(group_code = "public_contributors", group_apply = 3)
    expect_length(setup_lane_called(calls, "set_panel_group"), 1L)
  })
})

test_that("text typed into a setup form is not offered for another study", {
  calls <- new.env()
  calls$list <- list()
  selected <- shiny::reactiveVal("A")
  language <- shiny::reactiveVal("en")
  shiny::testServer(delphyrApp:::study_setup_server, args = list(study = function() selected(), lang = function() language(), call = setup_lane_call(calls), services = setup_lane_services(setup_lane_needed)), {
    session$flushReact()
    session$setInputs(consent_text = "Information written for study A", staff_reason = "Rationale for study A")
    # Within the same study typed text survives a new drawing of the form.
    language("de")
    session$flushReact()
    expect_match(output$body$html, "Information written for study A", fixed = TRUE)
    selected("B")
    session$flushReact()
    html <- output$body$html
    expect_false(grepl("study A", html, fixed = TRUE))
  })
})

test_that("creating a study starts with a heading, the steps and an example protocol", {
  file <- setup_lane_file()
  call <- function(name, ...) {
    switch(name,
      get_account_rights = list(can_create_study = TRUE),
      list_studies = data.frame(id = character(), title = character()),
      stop("Unexpected service")
    )
  }
  services <- setup_lane_services(c("get_account_rights", "create_study", "list_studies"))
  shiny::testServer(delphyrApp:::study_create_server, args = list(lang = function() "en", call = call, services = services), {
    html <- output$body$html
    expect_match(html, "<h2>Create a new study</h2>", fixed = TRUE)
    expect_false(grepl("<details", html, fixed = TRUE))
    expect_match(html, "Download the example protocol (JSON)", fixed = TRUE)
    # The note promises only what the example and the validation give.
    expect_match(html, "The example is a complete, valid protocol with example values", fixed = TRUE)
    expect_match(html, "the validation names the field in question", fixed = TRUE)
    expect_false(grepl("fields of the protocol are described", html, fixed = TRUE))
    example <- output$example
    expect_identical(unclass(delphyr::new_protocol(jsonlite::fromJSON(example, simplifyVector = FALSE)))$study$code, "DEMO-001")
    # Validation is offered only once a file is chosen.
    expect_match(output$validate_action$html, "disabled", fixed = TRUE)
    expect_match(output$validate_action$html, "Choose a protocol file first.", fixed = TRUE)
    session$setInputs(validate = 1)
    expect_match(output$status, "Choose a protocol file first.", fixed = TRUE)
    session$setInputs(file = file)
    expect_false(grepl("disabled", output$validate_action$html, fixed = TRUE))
    session$setInputs(validate = 2)
    expect_match(output$summary, "Consensus for exclusion", fixed = TRUE)
    expect_match(output$summary, "at least 70% agreement (7\u20139) and less than 15% disagreement (1\u20133)", fixed = TRUE)
    expect_match(output$summary, "Professionals, Public contributors", fixed = TRUE)
    expect_match(output$summary, "Deutsch, English", fixed = TRUE)
    expect_match(output$summary, "Modified Delphi in rounds", fixed = TRUE)
    expect_match(output$confirmation$html, "methodological decisions of the study team", fixed = TRUE)
  })
  # An account that already has studies sees the steps behind a summary line.
  call <- function(name, ...) if (name == "get_account_rights") list(can_create_study = TRUE) else data.frame(id = "s", title = "Study")
  shiny::testServer(delphyrApp:::study_create_server, args = list(lang = function() "en", call = call, services = services), {
    html <- output$body$html
    expect_match(html, "<h2>Create a new study</h2>", fixed = TRUE)
    expect_match(html, "<summary>Show the steps and the form</summary>", fixed = TRUE)
  })
})

test_that("protocol approval appears only after a validated preview and names a missing rationale", {
  old <- delphyr::new_protocol(delphyr::demo_protocol())
  proposed <- unclass(old)
  proposed$stopping$max_rounds <- 4L
  file <- setup_lane_file(proposed)
  saved <- list()
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "manage",
      list_protocol_versions = data.frame(id = "original", version = 1L, hash = "reviewed-base-hash", config = as.character(jsonlite::toJSON(unclass(old), auto_unbox = TRUE, digits = NA, null = "null")), previous_protocol_id = NA_character_, reason = NA_character_, occurred_at = as.POSIXct(NA)),
      amend_protocol = {
        saved[[length(saved) + 1L]] <<- list(...)
        list(version = 2L)
      },
      stop("Unexpected service")
    )
  }
  services <- setup_lane_services(c("get_capabilities", "list_protocol_versions", "amend_protocol"))
  shiny::testServer(delphyrApp:::protocols_server, args = list(study = function() "study", lang = function() "en", call = call, services = services), {
    session$flushReact()
    expect_false(any(grepl("approve", output$approval$html, fixed = TRUE)))
    expect_match(output$validate_action$html, "disabled", fixed = TRUE)
    session$setInputs(file = file)
    approval <- output$approval$html
    expect_match(approval, "After a protocol file is validated", fixed = TRUE)
    expect_false(grepl("approve", approval, fixed = TRUE))
    session$setInputs(validate = 1)
    approval <- output$approval$html
    expect_match(approval, "approve", fixed = TRUE)
    expect_match(approval, paste0("id=\"", session$ns(paste0("reason_", form())), "\""), fixed = TRUE)
    expect_match(output$preview_heading$html, "<h4>Changes from version 1</h4>", fixed = TRUE)
    setup_lane_approval(session, form(), reason = "  ", confirm = TRUE, approve = 1)
    expect_length(saved, 0L)
    expect_match(output$status, "A reason and confirmation are required.", fixed = TRUE)
    expect_false(grepl("Reference", output$status, fixed = TRUE))
    setup_lane_approval(session, form(), reason = "Permit another future round", confirm = FALSE, approve = 2)
    expect_length(saved, 0L)
    expect_match(output$status, "A reason and confirmation are required.", fixed = TRUE)
    setup_lane_approval(session, form(), confirm = TRUE, approve = 3)
    expect_length(saved, 1L)
    expect_identical(saved[[1]][[4]], "Permit another future round")
  })
  # An unchanged protocol is named as such, not as a failure.
  file <- setup_lane_file(unclass(old))
  call_same <- function(name, ...) {
    switch(name,
      get_capabilities = "manage",
      list_protocol_versions = data.frame(id = "original", version = 1L, hash = delphyr::content_hash(old), config = as.character(jsonlite::toJSON(unclass(old), auto_unbox = TRUE, digits = NA, null = "null")), reason = NA_character_),
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::protocols_server, args = list(study = function() "study", lang = function() "en", call = call_same, services = services), {
    session$flushReact()
    session$setInputs(file = file, validate = 1)
    expect_match(output$status, "identical to the current version", fixed = TRUE)
    expect_null(candidate())
  })
})

test_that("an approved rationale, or one typed for another study, is not offered for the next amendment", {
  base <- unclass(delphyr::new_protocol(delphyr::demo_protocol()))
  rounds <- function(n) {
    p <- base
    p$stopping$max_rounds <- n
    p
  }
  # Each study keeps its own versions; an approval adds one.
  stored <- list(A = list(base), B = list(base))
  reasons <- list(A = NA_character_, B = NA_character_)
  saved <- list()
  call <- function(name, ...) {
    args <- list(...)
    switch(name,
      get_capabilities = "manage",
      list_protocol_versions = {
        s <- args[[1]]
        n <- length(stored[[s]])
        config <- vapply(stored[[s]], function(p) as.character(jsonlite::toJSON(p, auto_unbox = TRUE, digits = NA, null = "null")), character(1))
        data.frame(id = paste0(s, seq_len(n)), version = seq_len(n), hash = paste0("stored-", s, seq_len(n)), config = config, reason = reasons[[s]], stringsAsFactors = FALSE)
      },
      amend_protocol = {
        saved[[length(saved) + 1L]] <<- args
        s <- args[[1]]
        stored[[s]][[length(stored[[s]]) + 1L]] <<- unclass(args[[2]])
        reasons[[s]] <<- c(reasons[[s]], args[[4]])
        list(version = length(stored[[s]]))
      },
      stop("Unexpected service")
    )
  }
  four <- setup_lane_file(rounds(4L))
  five <- setup_lane_file(rounds(5L))
  six <- setup_lane_file(rounds(6L))
  selected <- shiny::reactiveVal("A")
  services <- setup_lane_services(c("get_capabilities", "list_protocol_versions", "amend_protocol"))
  shiny::testServer(delphyrApp:::protocols_server, args = list(study = function() selected(), lang = function() "en", call = call, services = services), {
    session$flushReact()
    session$setInputs(file = four, validate = 1)
    setup_lane_approval(session, form(), reason = "Permit a fourth round", confirm = TRUE, approve = 1)
    expect_length(saved, 1L)
    expect_match(output$status, "New version confirmed: 2", fixed = TRUE)
    # The next amendment starts with an empty rationale and no confirmation.
    session$setInputs(file = five, validate = 2)
    approval <- output$approval$html
    expect_match(output$preview_heading$html, "<h4>Changes from version 2</h4>", fixed = TRUE)
    expect_match(approval, "Protocol amendment rationale", fixed = TRUE)
    expect_false(grepl("Permit a fourth round", approval, fixed = TRUE))
    session$setInputs(approve = 2)
    expect_length(saved, 1L)
    expect_match(output$status, "A reason and confirmation are required.", fixed = TRUE)
    # Text typed for one study is neither shown nor read for another.
    setup_lane_approval(session, form(), reason = "Typed for study A", confirm = TRUE)
    selected("B")
    session$flushReact()
    session$setInputs(file = six, validate = 3)
    approval <- output$approval$html
    expect_match(approval, "Protocol amendment rationale", fixed = TRUE)
    expect_false(grepl("Typed for study A", approval, fixed = TRUE))
    session$setInputs(approve = 3)
    expect_length(saved, 1L)
    expect_match(output$status, "A reason and confirmation are required.", fixed = TRUE)
    # Within one study a rationale not yet approved is offered for the next
    # file, while the confirmation has to be given again.
    setup_lane_approval(session, form(), reason = "Allow up to six rounds", confirm = TRUE)
    session$setInputs(file = five, validate = 4)
    expect_match(output$approval$html, "Allow up to six rounds", fixed = TRUE)
    session$setInputs(approve = 4)
    expect_length(saved, 1L)
    expect_match(output$status, "A reason and confirmation are required.", fixed = TRUE)
    setup_lane_approval(session, form(), reason = "Allow up to five rounds", confirm = TRUE, approve = 5)
    expect_length(saved, 2L)
    expect_identical(saved[[2]][[1]], "B")
    expect_equal(saved[[2]][[2]]$stopping$max_rounds, 5)
    expect_identical(saved[[2]][[4]], "Allow up to five rounds")
    expect_match(output$history, "Allow up to five rounds", fixed = TRUE)
  })
})

test_that("saved protocol versions are dated and summarised, with the JSON in template order", {
  p <- delphyr::demo_protocol()
  stored <- as.character(jsonlite::toJSON(p[rev(names(p))], auto_unbox = TRUE, digits = NA, null = "null"))
  versions <- data.frame(
    id = c("v1", "v2"), version = 1:2, hash = c("h1", "h2"), config = stored, previous_protocol_id = c(NA, "v1"),
    reason = c(NA, "A fourth round may be needed"), occurred_at = as.POSIXct(c(NA, "2026-10-03 17:49:32"), tz = "UTC"), stringsAsFactors = FALSE
  )
  call <- function(name, ...) if (name == "get_capabilities") "manage" else if (name == "list_protocol_versions") versions else stop("Unexpected service")
  services <- setup_lane_services(c("get_capabilities", "list_protocol_versions", "amend_protocol"))
  shiny::testServer(delphyrApp:::protocols_server, args = list(study = function() "study", lang = function() "en", call = call, services = services), {
    session$flushReact()
    history <- output$history
    expect_match(history, "Approved", fixed = TRUE)
    expect_match(history, "Rationale", fixed = TRUE)
    expect_match(history, "Created with the study", fixed = TRUE)
    expect_match(history, "3 Oct 2026, 19:49 (Europe/Berlin, UTC+2)", fixed = TRUE)
    expect_match(history, "2 (current)", fixed = TRUE)
    session$setInputs(version = "v2")
    summary <- output$saved_summary
    expect_match(summary, "DEMO-001", fixed = TRUE)
    expect_match(summary, "Professionals, Public contributors", fixed = TRUE)
    expect_match(summary, "Relevance (relevance_9)", fixed = TRUE)
    expect_false(grepl("gte", summary, fixed = TRUE))
    json <- output$saved
    expect_lt(regexpr("schema_version", json, fixed = TRUE), regexpr("\"study\"", json, fixed = TRUE))
    expect_lt(regexpr("\"study\"", json, fixed = TRUE), regexpr("\"panel\"", json, fixed = TRUE))
  })
})
