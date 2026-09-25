ui_translation_keys <- function(paths) {
  keys <- character()
  unresolved <- character()
  literal <- function(node, env) {
    if (is.character(node)) return(node)
    if (is.symbol(node)) return(get0(as.character(node), envir = env, inherits = TRUE))
    if (is.call(node) && identical(node[[1]], as.name("c"))) {
      parts <- lapply(as.list(node)[-1], literal, env = env)
      if (all(vapply(parts, is.character, logical(1)))) return(do.call(c, parts))
    }
    NULL
  }
  walk <- function(node, env) {
    if (missing(node)) return(invisible(NULL))
    if (is.expression(node) || is.pairlist(node)) {
      for (part in node) walk(part, env)
    } else if (is.call(node)) {
      if (identical(node[[1]], as.name("function"))) {
        walk(node[[3]], new.env(parent = env))
        return(invisible(NULL))
      }
      if (identical(node[[1]], as.name("<-")) && is.symbol(node[[2]])) {
        value <- literal(node[[3]], env)
        if (is.character(value)) assign(as.character(node[[2]]), value, env)
      }
      if (identical(node[[1]], as.name("tr"))) {
        value <- literal(node[[4]], env)
        if (is.character(value)) keys <<- c(keys, unname(value)) else unresolved <<- c(unresolved, deparse(node))
      }
      for (part in as.list(node)[-1]) walk(part, env)
    }
    invisible(NULL)
  }
  for (path in paths) walk(parse(path), new.env(parent = baseenv()))
  list(keys = unique(keys), unresolved = unresolved)
}

test_that("all literal and vector interface keys have explicit French translations", {
  paths <- list.files(testthat::test_path("..", "..", "R"), pattern = "[.]R$", full.names = TRUE)
  paths <- paths[basename(paths) != "i18n.R"]
  declared <- readLines(system.file("i18n", "ui-keys.txt", package = "delphyrApp"), encoding = "UTF-8")
  extracted <- if (length(paths)) ui_translation_keys(paths) else list(keys = declared, unresolved = character())
  expect_setequal(extracted$keys, declared)
  expect_length(extracted$unresolved, 0)
  expect_gt(length(extracted$keys), 250)
  expect_setequal(setdiff(extracted$keys, names(translation_catalog())), character())
  expect_true(all(nzchar(translation_catalog())))
  expect_error(tr("fr", "Unbekannt", "Unregistered UI label"), "Missing French")
})

test_that("language selection preserves names and exact status metadata", {
  expect_identical(tr(NULL, "Studie", "Study"), "Study")
  expect_identical(tr("fr", c(a = "Studie", b = "Runde"), c(a = "Study", b = "Round")), c(a = "\u00c9tude", b = "Tour"))
  expect_identical(tr("de", "Studie", "Study"), "Studie")
  expect_error(tr("xx", "Studie", "Study"), "Unsupported")
  tr("de", "Einwilligung gespeichert. Beleg:", "Consent saved. Receipt:")
  expect_identical(localize_status("Einwilligung gespeichert. Beleg: receipt-123", "fr"), "Consentement enregistr\u00e9. Re\u00e7u : receipt-123")
  expect_identical(localize_status("Consentement enregistr\u00e9. Re\u00e7u : receipt-123", "en"), "Consent saved. Receipt: receipt-123")
  expect_identical(localize_status("StudyXYZ user content", "fr"), "StudyXYZ user content")
  expect_identical(state_label(c("open", "succeeded"), "fr"), c("Ouvert", "R\u00e9ussi"))
  expect_identical(workspace_sections("panel", "fr")$label, "Ma participation")
})

test_that("connection notices cover each interface language", {
  script <- connection_script("notice", "workspace")
  expect_match(script, "Connexion interrompue", fixed = TRUE)
  expect_match(script, "Connection lost", fixed = TRUE)
  expect_match(script, "Verbindung unterbrochen", fixed = TRUE)
  expect_match(script, "messages[lang]", fixed = TRUE)
})

test_that("app defaults to English and switches its live chrome without changing study", {
  services <- list(
    list_studies = function(...) data.frame(id = "study", title = "Approved study title"),
    get_capabilities = function(...) "manage",
    list_enrollments = function(...) data.frame(id = character(), number = integer(), round_state = character()),
    get_questionnaire = function(...) stop("unused"), record_consent = function(...) stop("unused"),
    save_response = function(...) stop("unused"), submit_round = function(...) stop("unused")
  )
  app <- run_app(actor = list(principal_id = "trusted"), services = services)
  html <- app$httpHandler(list(PATH_INFO = "/", REQUEST_METHOD = "GET", QUERY_STRING = ""))$content
  expect_match(html, "document.documentElement.lang=\"en\"", fixed = TRUE)
  expect_match(html, 'value="fr"', fixed = TRUE)
  shiny::testServer(app, {
    expect_identical(lang(), "en")
    session$setInputs(study = "study", language = "fr")
    expect_match(output$navigation$html, "Tours et analyse", fixed = TRUE)
    expect_match(output$intro$html, "G\u00e9rez le protocole", fixed = TRUE)
    expect_identical(study(), "study")
    session$setInputs(language = "de")
    expect_match(output$navigation$html, "Runden und Auswertung", fixed = TRUE)
    expect_identical(study(), "study")
    session$setInputs(language = "en")
    expect_match(output$navigation$html, "Rounds and analysis", fixed = TRUE)
  })
})
