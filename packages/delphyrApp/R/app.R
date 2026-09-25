#' Build a synthetic study application with a trusted server identity
#'
#' The hosting application must resolve the actor on the server. Never derive
#' the actor from an input, URL parameter or a browser-supplied role. This P0
#' interface uses explicit saves; autosave, production authentication, mail,
#' and deployment qualification are outside this interface's acceptance scope.
#'
#' @param repo A connected delphyr repository; lifetime is managed by the caller.
#' @param actor Trusted actor supplied by server-side session setup.
#' @param language Initial interface language, de or en.
#' @param services Named list of service functions, each accepting repo and actor
#'   as their first two arguments. NULL uses exported delphyr services.
#' @return A shiny.appobj, runnable with shiny::runApp().
#' @export
#' @examples
#' if (interactive() && FALSE) {
#'   # Resolve repo and actor on the server before constructing the application.
#'   shiny::runApp(run_app(repo, actor))
#' }
run_app <- function(repo, actor, language = c("de", "en"), services = NULL) {
  language <- match.arg(language)
  if (is.null(actor) || !is.list(actor)) stop("A trusted server actor is required.", call. = FALSE)
  if (is.null(services)) {
    n <- c(
      "list_studies", "list_enrollments", "get_questionnaire", "record_consent",
      "save_response", "submit_round", "list_rounds", "transition_round", "get_capabilities", "freeze_round", "request_analysis", "get_operation", "get_analysis",
      "create_feedback", "get_feedback_candidate", "release_feedback", "assign_feedback", "request_export",
      "download_artifact", "get_study_setup", "prepare_round", "get_feedback", "complete_study"
    )
    services <- stats::setNames(lapply(n, function(x) getExportedValue("delphyr", x)), n)
  }
  required <- c("list_studies", "list_enrollments", "get_questionnaire", "record_consent", "save_response", "submit_round")
  if (!all(required %in% names(services)) || !all(vapply(services, is.function, logical(1)))) stop("Incomplete service adapter.", call. = FALSE)
  call <- function(name, ...) services[[name]](repo, actor, ...)
  ui <- shiny::fluidPage(
    theme = bslib::bs_theme(version = 5, primary = "#0e6e78", base_font = "system-ui"),
    shiny::tags$head(shiny::tags$style(shiny::HTML(app_css()))),
    shiny::tags$div(
      class = "del-wrap",
      shiny::tags$header(
        class = "del-header", shiny::tags$h1("delphyR"),
        shiny::selectInput("language", tr(language, "Sprache", "Language"), c("Deutsch" = "de", "English" = "en"), selected = language, width = "190px")
      ),
      shiny::uiOutput("banner"),
      shiny::tags$main(
        id = "main", shiny::tags$section(
          class = "del-sheet",
          shiny::uiOutput("intro"), shiny::selectInput("study", tr(language, "Studie", "Study"), character()), status_ui("status")
        ),
        panel_ui("panel"), management_ui("management")
      ),
      shiny::tags$footer(class = "del-note", "CTTIR \u00b7 delphyR \u00b7 0.0.1")
    )
  )
  server <- function(input, output, session) {
    lang <- shiny::reactive(input$language)
    shiny::observeEvent(lang(), {
      shiny::updateSelectInput(session, "language", label = tr(lang(), "Sprache", "Language"))
      shiny::updateSelectInput(session, "study", label = tr(lang(), "Studie", "Study"))
    })
    studies <- shiny::reactiveVal(data.frame())
    status <- shiny::reactiveVal("")
    output$banner <- shiny::renderUI(shiny::tags$aside(class = "del-banner", tr(
      lang(),
      "Synthetische Entwicklungsumgebung. Keine realen Teilnehmendendaten eingeben. E-Mails werden nicht versendet.",
      "Synthetic development environment. Do not enter real participant data. No email is sent."
    )))
    output$intro <- shiny::renderUI(shiny::tagList(
      shiny::tags$h2(tr(lang(), "Gemeinsam Wissen bewerten", "Assess evidence together")),
      shiny::tags$p(tr(
        lang(), "W\u00e4hlen Sie Ihre Studie. Antworten werden erst nach best\u00e4tigtem Speichern \u00fcbernommen; die Abgabe erfolgt anschlie\u00dfend ausdr\u00fccklich.",
        "Choose your study. Responses are retained after a confirmed save; submission is a separate explicit action."
      ))
    ))
    output$status <- shiny::renderText(status())
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    shiny::observeEvent(TRUE,
      {
        tryCatch(
          {
            s <- call("list_studies")
            studies(s)
            shiny::updateSelectInput(session, "study", choices = stats::setNames(s$id, s$title))
            if (!nrow(s)) status(tr(lang(), "Keine berechtigte Studie. Wenden Sie sich an die Studienleitung.", "No accessible study. Contact the study team."))
          },
          error = function(e) status(safe_error(e, lang()))
        )
      },
      once = TRUE
    )
    study <- shiny::reactive({
      shiny::req(input$study)
      input$study
    })
    panel_server("panel", study, lang, call, feedback_available = "get_feedback" %in% names(services), capabilities_available = "get_capabilities" %in% names(services))
    management_server("management", study, lang, call, services)
  }
  shiny::shinyApp(ui, server)
}
