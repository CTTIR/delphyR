test_that("each server session resolves one actor and browser inputs cannot replace it", {
  actors <- 0L
  repositories <- 0L
  calls <- list()
  observe_call <- function(repo, actor, ...) {
    calls[[length(calls) + 1L]] <<- list(repository = repo$id, principal = actor$principal_id)
  }
  services <- list(
    list_studies = function(repo, actor) {
      observe_call(repo, actor)
      data.frame(id = "study", title = "Synthetic")
    },
    list_enrollments = function(repo, actor, study) {
      observe_call(repo, actor)
      data.frame(id = character(), number = integer(), round_state = character())
    },
    get_questionnaire = function(...) stop("unused"), record_consent = function(...) stop("unused"),
    save_response = function(...) stop("unused"), submit_round = function(...) stop("unused")
  )
  app <- run_app(
    services = services,
    repo_factory = function() {
      repositories <<- repositories + 1L
      list(id = paste0("repo-", repositories))
    },
    actor_factory = function(session, repo) {
      actors <<- actors + 1L
      list(principal_id = paste0("principal-", actors))
    }
  )
  for (i in 1:2) {
    shiny::testServer(app, {
      session$setInputs(language = "en", study = "study", principal_id = "forged", actor = "forged", role = "manage")
      session$flushReact()
      expect_equal(session_actor$principal_id, paste0("principal-", i))
      expect_equal(session_repo$id, paste0("repo-", i))
      expect_false(session$isClosed())
    })
  }
  expect_equal(actors, 2L)
  expect_equal(repositories, 2L)
  expect_equal(unique(vapply(calls, `[[`, character(1), "principal")), c("principal-1", "principal-2"))
  expect_true(all(vapply(calls, function(x) sub("repo", "principal", x$repository) == x$principal, logical(1))))
})

test_that("failed or missing trusted session identities close before service access", {
  accessed <- FALSE
  deny <- function(...) {
    accessed <<- TRUE
    stop("Should not be called")
  }
  services <- stats::setNames(rep(list(deny), 6), c("list_studies", "list_enrollments", "get_questionnaire", "record_consent", "save_response", "submit_round"))
  for (factory in list(function(session, repo) NULL, function(session, repo) stop("Authentication failed"))) {
    app <- run_app(repo = list(), actor_factory = factory, services = services)
    shiny::testServer(app, {
      expect_true(session$isClosed())
    })
    expect_false(accessed)
  }
  expect_error(run_app(actor = list(principal_id = "fixed"), actor_factory = function(...) NULL, services = services), "one trusted")
})

test_that("workspace navigation follows selected-study rights and role-specific guidance", {
  services <- list(
    list_studies = function(...) data.frame(id = c("managed", "own"), title = c("Managed study", "Own panel study")),
    get_capabilities = function(repo, actor, study) if (study == "managed") c("manage", "edit", "coordinate") else "panel",
    list_enrollments = function(...) data.frame(id = character(), number = integer(), round_state = character()),
    get_questionnaire = function(...) stop("unused"), record_consent = function(...) stop("unused"),
    save_response = function(...) stop("unused"), submit_round = function(...) stop("unused")
  )
  app <- run_app(actor = list(principal_id = "trusted"), services = services)
  shiny::testServer(app, {
    session$setInputs(language = "en", study = "managed")
    expect_match(output$navigation$html, "#section-protocols", fixed = TRUE)
    expect_match(output$navigation$html, "#section-panel-import", fixed = TRUE)
    expect_false(grepl("#section-panel\"", output$navigation$html, fixed = TRUE))
    expect_match(output$intro$html, "Manage the protocol", fixed = TRUE)
    session$setInputs(study = "own")
    expect_match(output$navigation$html, "#section-panel\"", fixed = TRUE)
    expect_false(grepl("#section-protocols", output$navigation$html, fixed = TRUE))
    expect_false(grepl("#section-panel-import", output$navigation$html, fixed = TRUE))
    expect_match(output$intro$html, "Save each response", fixed = TRUE)
  })
})

test_that("a sign-out link is shown only for a configured, plain address", {
  services <- list(
    list_studies = function(...) data.frame(id = "study", title = "Synthetic"),
    list_enrollments = function(...) data.frame(id = character(), number = integer(), round_state = character()),
    get_questionnaire = function(...) stop("unused"), record_consent = function(...) stop("unused"),
    save_response = function(...) stop("unused"), submit_round = function(...) stop("unused")
  )
  actor <- list(principal_id = "trusted")
  shiny::testServer(run_app(actor = actor, services = services), {
    session$setInputs(language = "en")
    expect_null(output$account)
  })
  shiny::testServer(run_app(actor = actor, services = services, sign_out_url = "/oauth2/sign_out"), {
    session$setInputs(language = "en")
    expect_match(output$account$html, "<a id=\"sign_out\" class=\"btn btn-default del-signout\" href=\"/oauth2/sign_out\">Sign out</a>", fixed = TRUE)
    session$setInputs(language = "de")
    expect_match(output$account$html, ">Abmelden</a>", fixed = TRUE)
    session$setInputs(language = "fr")
    expect_match(output$account$html, ">Se déconnecter</a>", fixed = TRUE)
  })
  expect_no_error(run_app(actor = actor, services = services, sign_out_url = "https://gateway.example.invalid/oauth2/sign_out?rd=%2F"))
  for (address in list("javascript:alert(1)", "//other.example.invalid/x", "/a b", "/a\"onmouseover=\"x", "sign_out", c("/a", "/b"), NA_character_, 1L, "")) {
    expect_error(run_app(actor = actor, services = services, sign_out_url = address), "Invalid sign-out address.", fixed = TRUE)
  }
})

test_that("a process registers the scripts and styles of its page before the first request", {
  services <- list(
    list_studies = function(...) data.frame(id = "study", title = "Synthetic"),
    list_enrollments = function(...) data.frame(id = character(), number = integer(), round_state = character()),
    get_questionnaire = function(...) stop("unused"), record_consent = function(...) stop("unused"),
    save_response = function(...) stop("unused"), submit_round = function(...) stop("unused")
  )
  app <- run_app(actor = list(principal_id = "trusted"), services = services)
  page <- c("shiny-javascript-", "jquery-", "bootstrap-", "selectize-")
  registered <- function() vapply(page, function(prefix) any(startsWith(names(shiny::resourcePaths()), prefix)), logical(1))
  for (prefix in names(shiny::resourcePaths())) if (any(startsWith(prefix, page))) shiny::removeResourcePath(prefix)
  expect_false(any(registered()))
  expect_true(register_page_assets(app))
  expect_true(all(registered()))
  # A failure to render never prevents the start of the application.
  expect_false(register_page_assets(list(httpHandler = function(req) stop("unavailable"))))
})

test_that("signing out ends the other sessions of the same account and no others", {
  registry <- session_registry()
  closed <- character()
  fake <- function(name) list(close = function() closed <<- c(closed, name))
  a1 <- registry$add("account-a", fake("a1"))
  a2 <- registry$add("account-a", fake("a2"))
  b1 <- registry$add("account-b", fake("b1"))
  expect_identical(registry$accounts(), 2L)
  for (other in registry$others("account-a", a1)) other$close()
  expect_identical(closed, "a2")
  expect_length(registry$others("account-b", b1), 0L)
  expect_length(registry$others("unknown", "none"), 0L)
  registry$remove("account-a", a2)
  expect_length(registry$others("account-a", a1), 0L)
  registry$remove("account-a", a1)
  registry$remove("account-a", a1)
  registry$remove("account-b", b1)
  expect_identical(registry$accounts(), 0L)

  # In the application: the session is registered, a sign-out closes the other
  # one of the same account, and the end of a session removes its entry.
  services <- list(
    list_studies = function(...) data.frame(id = "study", title = "Synthetic"),
    list_enrollments = function(...) data.frame(id = character(), number = integer(), round_state = character()),
    get_questionnaire = function(...) stop("unused"), record_consent = function(...) stop("unused"),
    save_response = function(...) stop("unused"), submit_round = function(...) stop("unused")
  )
  app <- run_app(actor = list(principal_id = "trusted"), services = services, sign_out_url = "/oauth2/sign_out")
  registry <- get("open_sessions", envir = environment(app$serverFuncSource()))
  ended <- FALSE
  shiny::testServer(app, {
    expect_identical(registry$accounts(), 1L)
    second <- registry$add(account, list(close = function() ended <<- TRUE))
    session$setInputs(sign_out = 1)
    expect_true(ended)
    registry$remove(account, second)
    expect_false(session$isClosed())
  })
  expect_identical(registry$accounts(), 0L)
})
