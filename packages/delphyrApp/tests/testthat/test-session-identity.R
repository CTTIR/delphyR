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
