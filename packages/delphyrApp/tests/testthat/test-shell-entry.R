shell_services <- function(...) {
  utils::modifyList(list(
    list_studies = function(...) data.frame(id = "study", title = "Synthetic"),
    list_enrollments = function(...) data.frame(id = character(), number = integer(), round_state = character()),
    get_questionnaire = function(...) stop("unused"), record_consent = function(...) stop("unused"),
    save_response = function(...) stop("unused"), submit_round = function(...) stop("unused")
  ), list(...))
}
shell_log <- function(env = parent.frame()) {
  lines <- character()
  withr::local_options(list(delphyr.log_level = "info", delphyr.log_sink = function(line) lines <<- c(lines, line)), .local_envir = env)
  function() lapply(lines, jsonlite::fromJSON)
}
shell_page <- function(app) app$httpHandler(list(REQUEST_METHOD = "GET", PATH_INFO = "/", QUERY_STRING = ""))$content

test_that("a refused account and a session that cannot start are told apart", {
  entries <- shell_log()
  accessed <- FALSE
  services <- shell_services(list_studies = function(...) {
    accessed <<- TRUE
    data.frame(id = "study", title = "Synthetic")
  })
  refused <- list(
    function(session, repo) NULL,
    function(session, repo) delphyr::del_abort("DEL_UNAUTHORIZED", "authentication.principal"),
    function(session, repo) delphyr::del_abort("DEL_NOT_FOUND", "object")
  )
  for (factory in refused) {
    shiny::testServer(run_app(repo = list(), actor_factory = factory, services = services), {
      expect_true(session$isClosed())
      expect_identical(refusal, list(reason = "refused"))
    })
  }
  # The database fails during the identity lookup: no word about the account,
  # but a reference to the entry of the technical log.
  shiny::testServer(run_app(repo = list(), actor_factory = function(session, repo) stop("server closed the connection unexpectedly"), services = services), {
    expect_true(session$isClosed())
    expect_identical(refusal$reason, "unavailable")
    expect_match(refusal$reference, "^[0-9a-f]{12}$")
    failed <- Filter(function(x) identical(x$correlation_id, refusal$reference), entries())
    expect_identical(failed[[1]][c("operation", "outcome")], list(operation = "session_identity", outcome = "failed"))
  })
  # The database cannot be reached when the page loads: the repository of the
  # session fails, and the identity is never asked for.
  asked <- FALSE
  shiny::testServer(run_app(
    repo_factory = function() stop("could not connect to server: Connection refused"),
    actor_factory = function(session, repo) {
      asked <<- TRUE
      list(principal_id = "p")
    }, services = services
  ), {
    expect_true(session$isClosed())
    expect_identical(refusal$reason, "unavailable")
    failed <- Filter(function(x) identical(x$correlation_id, refusal$reference), entries())
    expect_identical(failed[[1]][c("operation", "outcome", "error_class")], list(operation = "session_repository", outcome = "failed", error_class = "simpleError"))
  })
  expect_false(asked)
  expect_false(accessed)
  # Neither message quotes the cause.
  expect_false(any(grepl("Connection refused|closed the connection", unlist(entries()))))
})

test_that("the page explains a closed session in each language, the configured one first", {
  html <- shell_page(run_app(actor = list(principal_id = "p"), services = shell_services(), language = "de", sign_out_url = "/oauth2/sign_out"))
  notice <- function(id) regmatches(html, regexpr(sprintf("(?s)<div id=\"%s\"[^>]*>.*?</div>", id), html, perl = TRUE))
  refused <- notice("unregistered")
  unavailable <- notice("unavailable")
  for (box in c(refused, unavailable)) {
    expect_match(box, "hidden=\"hidden\"", fixed = TRUE)
    expect_match(box, "role=\"alert\"", fixed = TRUE)
    expect_identical(regmatches(box, gregexpr("(?<=<section lang=\")[a-z]{2}", box, perl = TRUE))[[1]], c("de", "en", "fr"))
  }
  expect_match(refused, "Your account is not registered for this application.", fixed = TRUE)
  expect_match(refused, "Votre compte n\u2019est pas enregistr\u00e9", fixed = TRUE)
  expect_match(refused, "Ihr Konto ist f\u00fcr diese Anwendung nicht registriert.", fixed = TRUE)
  # Someone signed in with another account can leave the sign-in.
  expect_identical(lengths(regmatches(refused, gregexpr("href=\"/oauth2/sign_out\"", refused, fixed = TRUE))), 3L)
  expect_match(unavailable, "Nothing was changed. Reload the page in a few minutes.", fixed = TRUE)
  expect_match(unavailable, "data-reference", fixed = TRUE)
  expect_false(grepl("not registered", unavailable, fixed = TRUE))
  # The page shows the notice the server names, and a close without word as
  # an unavailable service; the panel's connection notice ignores a session
  # that was never accepted.
  expect_match(html, "Shiny.addCustomMessageHandler('delphyr-closed'", fixed = TRUE)
  expect_match(html, "if(x){reason=x;}else if(!reason){reason={reason:'unavailable'};}", fixed = TRUE)
  expect_match(connection_script("notice", "workspace"), "function drop(){if(!window.delphyrAccepted)return;", fixed = TRUE)
  expect_false(grepl("on('shiny:disconnected',function(){lost=true", connection_script("notice", "workspace"), fixed = TRUE))
  # Once closed, the page shows the notice and not a dimmed copy of the study page.
  expect_match(app_css(), ".del-closed #main,.del-closed .del-account,.del-closed #shiny-disconnected-overlay {display:none;}", fixed = TRUE)
  plain <- shell_page(run_app(actor = list(principal_id = "p"), services = shell_services()))
  expect_false(grepl("Sign out to use another account", plain, fixed = TRUE))
})

test_that("a demonstration identity is made anew for every session", {
  made <- 0L
  testthat::local_mocked_bindings(
    demo_actor = function(repo, principal_id, lifetime_seconds = 3600) {
      made <<- made + 1L
      structure(list(principal_id = principal_id, expires_at = Sys.time() + lifetime_seconds, made = made), class = "delphyr_actor")
    },
    .package = "delphyr"
  )
  seen <- list()
  services <- shell_services(list_studies = function(repo, actor) {
    seen[[length(seen) + 1L]] <<- actor
    data.frame(id = "study", title = "Synthetic")
  })
  # Started an hour ago: the actor given to run_app has expired.
  expired <- structure(list(principal_id = "demo-principal", expires_at = Sys.time() - 1), class = "delphyr_actor")
  app <- run_app(repo = list(environment = "development"), actor = expired, services = services)
  for (i in 1:2) {
    shiny::testServer(app, {
      session$flushReact()
      expect_false(session$isClosed())
      expect_identical(session_actor$made, i)
      expect_true(session_actor$expires_at > Sys.time())
    })
  }
  expect_identical(vapply(seen, function(x) x$made, integer(1)), 1:2)
  expect_identical(unique(vapply(seen, function(x) x$principal_id, character(1))), "demo-principal")
  # An account no longer active is refused like any unknown account.
  testthat::local_mocked_bindings(demo_actor = function(...) delphyr::del_abort("DEL_NOT_FOUND", "object"), .package = "delphyr")
  shiny::testServer(run_app(repo = list(environment = "development"), actor = expired, services = services), {
    expect_true(session$isClosed())
    expect_identical(refusal$reason, "refused")
  })
  # A trusted actor that is not a demonstration identity is used as given.
  fixed <- list(principal_id = "trusted")
  shiny::testServer(run_app(actor = fixed, services = services), expect_identical(session_actor, fixed))
  expect_identical(made, 2L)
})

test_that("a person without any study is told what can be done next", {
  rights <- function(create) list(get_account_rights = function(...) list(can_create_study = create), create_study = function(...) stop("unused"))
  none <- function(...) data.frame(id = character(), title = character())
  shown <- function(app) {
    text <- NULL
    shiny::testServer(app, {
      session$flushReact()
      expect_identical(output$has_studies, "no")
      expect_match(output$intro$html, "Your studies", fixed = TRUE)
      # Nothing asks to choose from an empty list.
      expect_false(grepl("Choose a study", output$intro$html, fixed = TRUE))
      text <<- status()
    })
    text
  }
  expect_identical(shown(run_app(actor = list(principal_id = "p"), services = do.call(shell_services, c(list(list_studies = none), rights(TRUE))))), "No accessible study yet. You can create a study below.")
  expect_identical(shown(run_app(actor = list(principal_id = "p"), services = do.call(shell_services, c(list(list_studies = none), rights(FALSE))))), "No accessible study yet. Contact the study team.")
  # Behind a gateway an invited person can enter the code of the invitation.
  invited <- list(principal_id = "p", issuer = "https://idp.example.invalid/realms/synthetic")
  accepting <- list(preview_panel_invitation = function(...) stop("unused"), accept_panel_invitation = function(...) stop("unused"))
  expect_identical(shown(run_app(actor = invited, services = do.call(shell_services, c(list(list_studies = none), rights(FALSE), accepting)))), "No accessible study yet. Enter the hand-over code of your invitation above, or contact the study team.")
  expect_identical(shown(run_app(actor = invited, services = do.call(shell_services, c(list(list_studies = none), rights(TRUE), accepting)))), "No accessible study yet. You can create a study below or enter the hand-over code of an invitation above.")
  shiny::testServer(run_app(actor = list(principal_id = "p"), services = do.call(shell_services, c(list(list_studies = none), rights(TRUE)))), {
    session$setInputs(language = "fr")
    expect_identical(output$status, "Aucune \u00e9tude accessible pour le moment. Vous pouvez cr\u00e9er une \u00e9tude ci-dessous.")
  })
  # With a study the list is offered and nothing is reported.
  shiny::testServer(run_app(actor = list(principal_id = "p"), services = shell_services(get_capabilities = function(...) "panel")), {
    session$setInputs(study = "study")
    expect_identical(output$has_studies, "yes")
    expect_identical(status(), "")
    expect_match(output$intro$html, "Save each response", fixed = TRUE)
  })
})

test_that("the header shows a clean mark, plain lists and nothing empty beside the language", {
  html <- shell_page(run_app(actor = list(principal_id = "p"), services = shell_services()))
  expect_match(html, "<img class=\"del-logo\" src=\"delphyr-brand/delphyR-mark.svg\"", fixed = TRUE)
  expect_true(file.exists(system.file("www", "delphyR-mark.svg", package = "delphyrApp")))
  expect_false(grepl("delphyR-hex.png", html, fixed = TRUE))
  # The language and study lists are the browser's own, like the other lists.
  expect_match(html, "<select class=\"shiny-input-select form-control\" id=\"language\">", fixed = TRUE)
  expect_match(html, "<select class=\"shiny-input-select form-control\" id=\"study\">", fixed = TRUE)
  expect_false(grepl("data-for=\"(language|study)\"", html))
  # Without an address to end the sign-in the account area holds nothing.
  expect_false(grepl("id=\"account\"", html, fixed = TRUE))
  expect_match(shell_page(run_app(actor = list(principal_id = "p"), services = shell_services(), sign_out_url = "/oauth2/sign_out")), "id=\"account\"", fixed = TRUE)
})
