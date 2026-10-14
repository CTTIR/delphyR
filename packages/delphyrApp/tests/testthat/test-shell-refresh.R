# A study whose rights, protocol, panel and invitations change through the
# services, as confirmed changes in the sections of a session change them.
refresh_study <- "11111111-1111-4111-8111-111111111111"
refresh_draft <- "22222222-2222-4222-8222-222222222222"
refresh_state <- function() {
  state <- new.env()
  state$caps <- c("manage", "coordinate")
  state$protocol <- delphyr::demo_protocol()
  state$enrolled <- 41L
  state$group <- "professionals"
  state
}
refresh_services <- function(state) {
  unused <- function(...) stop("unused")
  original <- delphyr::new_protocol(delphyr::demo_protocol())
  list(
    list_studies = function(...) data.frame(id = refresh_study, title = "Synthetic"),
    list_enrollments = function(...) data.frame(id = character(), number = integer(), round_state = character()),
    get_questionnaire = unused, record_consent = unused, save_response = unused, submit_round = unused,
    get_capabilities = function(repo, actor, study) state$caps,
    set_capability = function(repo, actor, study, account, capability, enabled, command_id, reason = NULL) {
      if (identical(account, actor$principal_id)) state$caps <- if (enabled) union(state$caps, capability) else setdiff(state$caps, capability)
      list(id = "membership")
    },
    list_protocol_versions = function(...) {
      data.frame(id = "version-1", version = 1L, hash = delphyr::content_hash(original), config = as.character(jsonlite::toJSON(unclass(original), auto_unbox = TRUE, digits = NA, null = "null")), reason = NA_character_)
    },
    amend_protocol = function(repo, actor, study, protocol, expected_hash, reason, command_id) {
      state$protocol <- protocol
      list(version = 2L)
    },
    enroll_panel = function(repo, actor, round, command_id) {
      state$enrolled <- state$enrolled + 1L
      list(added = 1L)
    },
    get_study_setup = function(...) list(protocol = state$protocol, consent_versions = data.frame(id = character(), locale = character(), content = character())),
    list_study_staff = function(...) data.frame(principal_id = "me", subject = "lead", issuer = "urn:delphyr:demo", granted = paste(state$caps, collapse = ", "), revoked = "", active = TRUE),
    list_panel = function(...) data.frame(panelist_id = "P-1", group_code = state$group, withdrawn = FALSE, active = TRUE, rounds_enrolled = state$enrolled, rounds_submitted = 0L),
    set_panel_group = function(repo, actor, study, panelist, group, reason, command_id) {
      state$group <- group
      list(id = "membership")
    },
    publish_consent = unused, register_staff_account = unused,
    preview_panel_import = unused, import_panel = unused, get_panel_import_receipt = unused,
    list_panel_invitations = function(...) {
      data.frame(draft_id = refresh_draft, invitation_id = NA_character_, external_ref = "C-01", display_name = "Synthetic contact", stakeholder_group = "professionals", state = "unbound", expires_at = as.POSIXct(NA))
    },
    register_invited_account = function(...) list(id = "33333333-3333-4333-8333-333333333333"),
    issue_panel_invitation = function(...) list(id = "44444444-4444-4444-8444-444444444444", expires_at = Sys.time() + 900),
    revoke_panel_invitation = unused
  )
}
# A change of the session's own rights, made with Setup's form.
change_own_right <- function(session, capability, action, click) {
  session$setInputs(`study_setup-staff_account` = "me", `study_setup-staff_capability` = capability, `study_setup-staff_action` = action, `study_setup-staff_reason` = "Synthetic change of duties", `study_setup-staff_confirm` = TRUE)
  session$setInputs(`study_setup-staff_apply` = click)
}
html_of <- function(x) if (is.list(x)) as.character(x$html) else as.character(x)
# The id of an input in what a section has rendered, whatever key its form
# carries.
rendered_input <- function(output, outputs, tag, prefix) {
  html <- paste(vapply(outputs, function(name) tryCatch(html_of(output[[name]]), error = function(e) ""), character(1)), collapse = "")
  regmatches(html, regexec(sprintf("<%s id=\"(%s[^\"]*)\"", tag, prefix), html))[[1]][2]
}

test_that("a change of the session's own rights reaches the sections whose rights changed", {
  state <- refresh_state()
  shiny::testServer(run_app(actor = list(principal_id = "me"), services = refresh_services(state)), {
    session$setInputs(language = "en", study = refresh_study)
    expect_match(output$navigation$html, "#section-panel-import", fixed = TRUE)
    expect_match(output[["panel_import-body"]]$html, "Synthetic panel import", fixed = TRUE)
    # Giving up coordination in Setup: the sections go with their links.
    change_own_right(session, "coordinate", "revoke", 1)
    expect_false("coordinate" %in% state$caps)
    expect_false(grepl("#section-panel-import", output$navigation$html, fixed = TRUE))
    expect_error(output[["panel_import-body"]], class = "shiny.silent.error")
    expect_error(output[["invitations-body"]], class = "shiny.silent.error")
    # Setup, which needs management, stays with its confirmation.
    expect_match(output[["study_setup-body"]]$html, "Study setup", fixed = TRUE)
    expect_match(output[["study_setup-status"]], "Change of rights confirmed", fixed = TRUE)
    # Taking it back shows the sections without selecting the study again.
    change_own_right(session, "coordinate", "grant", 2)
    expect_match(output$navigation$html, "#section-panel-import", fixed = TRUE)
    expect_match(output[["panel_import-body"]]$html, "Synthetic panel import", fixed = TRUE)
    expect_match(output[["invitations-body"]]$html, "C-01", fixed = TRUE)
  })
})

test_that("a change of rights leaves the sections whose rights did not change as they are", {
  state <- refresh_state()
  shiny::testServer(run_app(actor = list(principal_id = "me"), services = refresh_services(state)), {
    session$setInputs(language = "en", study = refresh_study)
    session$setInputs(`invitations-draft` = refresh_draft, `invitations-issuer` = "https://idp.example.invalid/realms/synthetic", `invitations-subject` = "subject-1", `invitations-ttl` = 15, `invitations-reason` = "Account confirmed by the coordinators", `invitations-confirm` = TRUE)
    session$setInputs(`invitations-issue` = 1)
    expect_match(output[["invitations-issued"]]$html, "Hand-over code", fixed = TRUE)
    # Taking the audit right changes nothing that Invitations or Setup read:
    # the code, which cannot be shown again, and Setup's confirmation stay.
    change_own_right(session, "audit", "grant", 1)
    expect_true("audit" %in% state$caps)
    expect_match(output[["invitations-issued"]]$html, "Hand-over code", fixed = TRUE)
    expect_match(output[["study_setup-status"]], "Change of rights confirmed", fixed = TRUE)
    expect_identical(reselected$invitations(), 0L)
    expect_identical(reselected$study_setup(), 0L)
    expect_identical(reselected$audit(), 1L)
  })
})

test_that("Setup offers the current protocol after an amendment in the Protocol section", {
  state <- refresh_state()
  amended <- unclass(delphyr::new_protocol(delphyr::demo_protocol()))
  amended$study$languages <- list("de", "en", "fr")
  amended$panel$groups <- c(amended$panel$groups, list("nurses"))
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path))
  jsonlite::write_json(amended, path, auto_unbox = TRUE, digits = NA, null = "null")
  upload <- data.frame(name = "protocol.json", size = file.info(path)$size, type = "application/json", datapath = path)
  shiny::testServer(run_app(actor = list(principal_id = "me"), services = refresh_services(state)), {
    session$setInputs(language = "en", study = refresh_study)
    body <- output[["study_setup-body"]]$html
    expect_false(grepl("<option value=\"fr\"", body, fixed = TRUE))
    expect_false(grepl("<option value=\"nurses\"", body, fixed = TRUE))
    # The amendment as the Protocol section takes it: validated, with a
    # rationale and a confirmation, then approved.
    session$setInputs(`protocols-file` = upload, `protocols-validate` = 1)
    form <- c("protocols-body", "protocols-approval")
    reason <- rendered_input(output, form, "textarea", "protocols-reason")
    confirm <- rendered_input(output, form, "input", "protocols-confirm")
    expect_false(anyNA(c(reason, confirm)))
    do.call(session$setInputs, stats::setNames(list("French and a group of nurses", TRUE), c(reason, confirm)))
    session$setInputs(`protocols-approve` = 1)
    expect_identical(unlist(state$protocol$study$languages), c("de", "en", "fr"))
    body <- output[["study_setup-body"]]$html
    expect_match(body, "<option value=\"fr\"", fixed = TRUE)
    expect_match(body, "<option value=\"nurses\"", fixed = TRUE)
  })
})

test_that("Setup reads its panel again after changes elsewhere and keeps its own confirmation", {
  state <- refresh_state()
  shiny::testServer(run_app(actor = list(principal_id = "me"), services = refresh_services(state)), {
    session$setInputs(language = "en", study = refresh_study)
    enrolled <- function() grepl(">\\s*42\\s*<", html_of(output[["study_setup-panel"]]))
    expect_false(enrolled())
    # Members enrolled in another section appear in the panel table.
    signalling("management")("enroll_panel", "round", "e-1")
    session$flushReact()
    expect_true(enrolled())
    # A change made in Setup is read again by Setup itself, which therefore
    # is not selected anew and keeps its confirmation.
    elsewhere <- changed_outside_setup()
    session$setInputs(`study_setup-group_panelist` = "P-1", `study_setup-group_code` = "public_contributors", `study_setup-group_reason` = "Moved at the member's request", `study_setup-group_confirm` = TRUE)
    session$setInputs(`study_setup-group_apply` = 1)
    expect_identical(state$group, "public_contributors")
    expect_identical(changed_outside_setup(), elsewhere)
    expect_match(output[["study_setup-status"]], "Stakeholder group changed", fixed = TRUE)
  })
})

test_that("only a confirmed change signals the other sections", {
  state <- refresh_state()
  services <- refresh_services(state)
  services$set_panel_group <- function(...) delphyr::del_abort("DEL_CONFLICT", "panel.group")
  shiny::testServer(run_app(actor = list(principal_id = "me"), services = services), {
    session$setInputs(language = "en", study = refresh_study)
    before <- changed()
    elsewhere <- changed_outside_setup()
    management <- signalling("management")
    management("get_capabilities", refresh_study)
    management("list_panel", refresh_study)
    expect_identical(changed(), before)
    expect_error(management("set_panel_group", refresh_study, "P-1", "nurses", "Moved", "g-1"), class = "DEL_CONFLICT")
    expect_identical(changed(), before)
    expect_identical(changed_outside_setup(), elsewhere)
    management("enroll_panel", "round", "e-1")
    expect_identical(changed(), before + 1L)
    expect_identical(changed_outside_setup(), elsewhere + 1L)
    # A change of rights that is not this session's own reads no section again.
    counts <- vapply(reselected, function(x) x(), integer(1))
    signalling("study_setup")("set_capability", refresh_study, "someone-else", "audit", TRUE, "c-3", reason = "Audit for a colleague")
    session$flushReact()
    expect_identical(vapply(reselected, function(x) x(), integer(1)), counts)
  })
})
