invitation_services <- function(names) stats::setNames(rep(list(function(...) NULL), length(names)), names)
coordinator_services <- function() invitation_services(c("get_capabilities", "list_panel_invitations", "register_invited_account", "issue_panel_invitation", "revoke_panel_invitation"))
study_a <- "11111111-1111-4111-8111-111111111111"
invitation_a <- "22222222-2222-4222-8222-222222222222"

test_that("issuing needs rationale and confirmation and shows the hand-over code once", {
  calls <- list()
  state <- "unbound"
  call <- function(name, ...) {
    calls[[length(calls) + 1L]] <<- list(name, ...)
    switch(name,
      get_capabilities = "coordinate",
      list_panel_invitations = data.frame(draft_id = "draft", external_ref = "REF1", display_name = "Synthetic", stakeholder_group = "professionals", locale = "en", invitation_id = if (state == "unbound") NA_character_ else invitation_a, expires_at = if (state == "unbound") NA_character_ else "2026-10-02 12:15:00+00", state = state),
      register_invited_account = list(id = "principal"),
      issue_panel_invitation = {
        state <<- "outstanding"
        list(id = invitation_a, expires_at = "2026-10-02 12:15:00+00")
      },
      revoke_panel_invitation = {
        state <<- "revoked"
        list(id = invitation_a)
      },
      stop("Unexpected service")
    )
  }
  selected_study <- shiny::reactiveVal(study_a)
  shiny::testServer(delphyrApp:::invitations_server, args = list(study = function() selected_study(), lang = function() "en", call = call, services = coordinator_services(), default_issuer = "https://idp.example.invalid"), {
    session$flushReact()
    expect_match(output$body$html, "https://idp.example.invalid", fixed = TRUE)
    expect_match(output$drafts, "Not yet issued", fixed = TRUE)
    session$setInputs(draft = "draft", issuer = "https://idp.example.invalid", subject = "subject-1", ttl = 15, reason = "", confirm = TRUE, issue = 1)
    expect_match(output$status, "reason and confirmation")
    expect_false(any(vapply(calls, function(x) x[[1]] == "issue_panel_invitation", logical(1))))
    session$setInputs(reason = "Reviewed stable account", confirm = FALSE, issue = 2)
    expect_null(issued())
    session$setInputs(confirm = TRUE, ttl = 2000, issue = 3)
    expect_null(issued())
    expect_match(output$status, "No success was confirmed")
    session$setInputs(ttl = 15, issue = 4)
    register <- Filter(function(x) x[[1]] == "register_invited_account", calls)[[1]]
    issue <- Filter(function(x) x[[1]] == "issue_panel_invitation", calls)[[1]]
    expect_identical(register[2:4], list(study_a, "https://idp.example.invalid", "subject-1"))
    expect_identical(issue[[3]], "draft")
    expect_identical(issue[[4]], "principal")
    expect_identical(issue[[6]], 900)
    token <- as.character(issue[[5]])
    expect_match(token, "^[0-9a-f]{64}$")
    expect_identical(issued()$code, paste("dlp1", study_a, invitation_a, token, sep = "."))
    expect_match(output$issued$html, token, fixed = TRUE)
    expect_match(output$drafts, "Awaiting acceptance", fixed = TRUE)
    expect_false(grepl(token, output$drafts, fixed = TRUE))
    session$setInputs(hide = 1)
    expect_null(issued())
    session$setInputs(ttl = 15, confirm = TRUE, issue = 5)
    expect_false(is.null(issued()))
    selected_study("33333333-3333-4333-8333-333333333333")
    session$flushReact()
    expect_null(issued())
    session$setInputs(outstanding = invitation_a, revoke_reason = "Wrong account", revoke_confirm = FALSE, revoke = 1)
    expect_false(any(vapply(calls, function(x) x[[1]] == "revoke_panel_invitation", logical(1))))
    session$setInputs(revoke_confirm = TRUE, revoke = 2)
    expect_match(output$status, "Invitation revoked")
    expect_match(output$drafts, "Revoked", fixed = TRUE)
  })
})

test_that("invitation management stays hidden without coordination rights", {
  call <- function(name, ...) if (name == "get_capabilities") "panel" else stop("must not be called")
  shiny::testServer(delphyrApp:::invitations_server, args = list(study = function() study_a, lang = function() "en", call = call, services = coordinator_services()), {
    session$flushReact()
    expect_false(allowed())
    expect_error(output$body)
    session$setInputs(draft = "draft", issuer = "https://idp.example.invalid", subject = "s", ttl = 15, reason = "x", confirm = TRUE, issue = 1)
    expect_null(issued())
  })
})

test_that("acceptance previews read-only, requires confirmation and reuses one command key", {
  token <- paste(rep("ab", 32), collapse = "")
  code <- paste("dlp1", study_a, invitation_a, token, sep = ".")
  calls <- list()
  fail_accept <- TRUE
  joined <- character()
  call <- function(name, ...) {
    calls[[length(calls) + 1L]] <<- list(name, ...)
    switch(name,
      preview_panel_invitation = list(id = invitation_a, study_title = "Synthetic study", expires_at = "2026-10-02 12:15:00+00"),
      accept_panel_invitation = {
        if (fail_accept) stop("connection lost")
        list(id = invitation_a, membership_id = "membership", panelist_id = "panelist")
      },
      stop("Unexpected service")
    )
  }
  services <- invitation_services(c("preview_panel_invitation", "accept_panel_invitation"))
  shiny::testServer(delphyrApp:::invitation_accept_server, args = list(lang = function() "en", call = call, services = services, verified = TRUE, on_accepted = function(id) joined <<- c(joined, id)), {
    session$setInputs(code = "not-a-code", check = 1)
    expect_match(output$status, "not available for your account")
    expect_length(calls, 0L)
    session$setInputs(code = code, check = 2)
    expect_match(output$preview$html, "Synthetic study", fixed = TRUE)
    expect_identical(calls[[1]][[1]], "preview_panel_invitation")
    session$setInputs(confirm = FALSE, accept = 1)
    expect_match(output$status, "confirm acceptance")
    expect_length(calls, 1L)
    session$setInputs(confirm = TRUE, accept = 2)
    expect_null(receipt())
    expect_match(output$status, "not available for your account")
    fail_accept <<- FALSE
    session$setInputs(accept = 3)
    accepts <- Filter(function(x) x[[1]] == "accept_panel_invitation", calls)
    expect_length(accepts, 2L)
    expect_identical(accepts[[1]][[6]], accepts[[2]][[6]])
    expect_true(accepts[[2]][[5]])
    expect_identical(as.character(accepts[[2]][[4]]), token)
    expect_identical(receipt()$id, invitation_a)
    expect_identical(joined, study_a)
    expect_false(grepl(token, output$preview$html, fixed = TRUE))
    expect_false(grepl("panelist", output$preview$html, fixed = TRUE))
  })
})

test_that("changing the code discards a stale preview and unverified sessions see nothing", {
  token <- paste(rep("cd", 32), collapse = "")
  code <- paste("dlp1", study_a, invitation_a, token, sep = ".")
  calls <- 0L
  call <- function(name, ...) {
    calls <<- calls + 1L
    list(id = invitation_a, study_title = "Synthetic study", expires_at = "later")
  }
  services <- invitation_services(c("preview_panel_invitation", "accept_panel_invitation"))
  shiny::testServer(delphyrApp:::invitation_accept_server, args = list(lang = function() "en", call = call, services = services, verified = TRUE), {
    session$setInputs(code = code, check = 1)
    expect_false(is.null(previewed()))
    session$setInputs(code = paste0(code, "x"))
    expect_null(previewed())
    session$setInputs(confirm = TRUE, accept = 1)
    expect_identical(calls, 1L)
  })
  shiny::testServer(delphyrApp:::invitation_accept_server, args = list(lang = function() "en", call = call, services = services, verified = FALSE), {
    expect_error(output$body)
    session$setInputs(code = code, check = 1)
    expect_identical(calls, 1L)
  })
})

test_that("navigation offers invitations only to coordinators", {
  expect_true("section-invitations" %in% workspace_sections("coordinate", "en")$id)
  expect_false("section-invitations" %in% workspace_sections(c("panel", "manage", "edit"), "en")$id)
  expect_identical(invitation_state_label(c("unbound", "accepted", "other"), "de"), c("Noch nicht ausgestellt", "Angenommen", "other"))
})
