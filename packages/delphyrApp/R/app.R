#' Build a synthetic study application with a trusted server identity
#'
#' The hosting application must resolve the actor on the server. Never derive
#' the actor from an input, URL parameter or a browser-supplied role. This P0
#' interface uses explicit saves; autosave, production authentication, mail,
#' and deployment qualification are outside this interface's acceptance scope.
#'
#' @param repo A connected delphyr repository; lifetime is managed by the caller.
#' @param actor Trusted actor supplied by server-side session setup.
#' @param actor_factory Optional trusted function(session, repo) resolving each
#'   session identity independently. Mutually exclusive with actor.
#' @param repo_factory Optional function creating a repository for each session;
#'   its DBI connection is closed when the session ends.
#' @param language Initial interface language: en (default), fr or de.
#' @param services Named list of service functions, each accepting repo and actor
#'   as their first two arguments. NULL uses exported delphyr services.
#' @return A shiny.appobj, runnable with shiny::runApp().
#' @export
#' @examples
#' if (interactive() && FALSE) {
#'   # Resolve repo and actor on the server before constructing the application.
#'   shiny::runApp(run_app(repo, actor))
#' }
run_app <- function(repo = NULL, actor = NULL, language = c("en", "fr", "de"), services = NULL,
                    actor_factory = NULL, repo_factory = NULL) {
  language <- match.arg(language)
  if (is.null(actor_factory)) {
    if (is.null(actor) || !is.list(actor)) stop("A trusted server actor is required.", call. = FALSE)
  } else if (!is.function(actor_factory) || !is.null(actor)) {
    stop("Use one trusted server identity factory or one fixed demo actor.", call. = FALSE)
  }
  if (!is.null(repo_factory) && !is.function(repo_factory)) stop("Invalid repository factory.", call. = FALSE)
  if (is.null(services)) {
    n <- c(
      "list_studies", "list_enrollments", "get_questionnaire", "record_consent",
      "save_response", "submit_round", "list_rounds", "transition_round", "get_capabilities", "freeze_round", "request_analysis", "get_operation", "get_analysis",
      "create_feedback", "get_feedback_candidate", "release_feedback", "assign_feedback", "request_export",
      "download_artifact", "get_study_setup", "prepare_round", "get_feedback", "complete_study",
      "get_qualitative_provenance", "list_qualitative_reviews", "record_qualitative_source",
      "redact_qualitative_source", "release_qualitative_edit", "create_qualitative_theme",
      "code_qualitative_source", "link_item_source", "record_item_lineage",
      "list_campaign_rounds", "list_campaign_enrollments", "prepare_campaign",
      "preview_campaign", "release_campaign", "cancel_campaign", "list_protocol_versions", "amend_protocol", "withdraw_participation", "preview_panel_import", "import_panel", "get_panel_import_receipt"
    )
    services <- stats::setNames(lapply(n, function(x) getExportedValue("delphyr", x)), n)
  }
  required <- c("list_studies", "list_enrollments", "get_questionnaire", "record_consent", "save_response", "submit_round")
  if (!all(required %in% names(services)) || !all(vapply(services, is.function, logical(1)))) stop("Incomplete service adapter.", call. = FALSE)
  shiny::addResourcePath("delphyr-brand", system.file("www", package = "delphyrApp"))
  ui <- shiny::fluidPage(
    theme = bslib::bs_theme(version = 5, bg = "#eceff2", fg = "#22303c", primary = "#0e6e78", success = "#0e6e78", danger = "#b3372b", base_font = "system-ui"),
    shiny::tags$head(shiny::tags$script(shiny::HTML(sprintf("document.documentElement.lang=%s; $(document).on('shiny:connected',function(){Shiny.addCustomMessageHandler('delphyr-language',function(lang){document.documentElement.lang=lang;});});", jsonlite::toJSON(language, auto_unbox = TRUE)))), shiny::tags$style(shiny::HTML(app_css())),
      shiny::tags$link(rel = "icon", type = "image/png", href = "delphyr-brand/delphyR-hex.png")),
    shiny::tags$div(
      class = "del-wrap",
      shiny::tags$header(
        class = "del-header", shiny::tags$div(class = "del-brand",
          shiny::tags$img(class = "del-logo", src = "delphyr-brand/delphyR-hex.png", alt = "", width = 72, height = 84),
          shiny::tags$h1("delphyR")),
        shiny::selectInput("language", tr(language, "Sprache", "Language"), c("English" = "en", "Fran\u00e7ais" = "fr", "Deutsch" = "de"), selected = language, width = "190px")
      ),
      shiny::uiOutput("banner"),
      shiny::tags$main(
        id = "main", shiny::tags$section(
          class = "del-sheet",
          shiny::uiOutput("intro"), shiny::selectInput("study", tr(language, "Studie", "Study"), character()), status_ui("status")
        ),
        shiny::uiOutput("navigation"),
        shiny::tags$div(id = "section-panel", panel_ui("panel")),
        shiny::tags$div(id = "section-protocols", protocols_ui("protocols")),
        shiny::tags$div(id = "section-management", management_ui("management")),
        shiny::tags$div(id = "section-editorial", editorial_ui("editorial")),
        shiny::tags$div(id = "section-panel-import", panel_import_ui("panel_import")),
        shiny::tags$div(id = "section-communications", communications_ui("communications"))
      ),
      shiny::tags$footer(class = "del-note", "CTTIR \u00b7 delphyR \u00b7 0.0.1")
    )
  )
  server <- function(input, output, session) {
    session_repo <- if (is.null(repo_factory)) repo else repo_factory()
    if (!is.null(repo_factory) && inherits(session_repo$con, "DBIConnection")) {
      session$onSessionEnded(function() DBI::dbDisconnect(session_repo$con))
    }
    session_actor <- if (is.null(actor_factory)) {
      actor
    } else {
      tryCatch(
        actor_factory(session, session_repo),
        error = function(e) NULL
      )
    }
    if (is.null(session_actor)) {
      session$close()
      return(invisible(NULL))
    }
    call <- function(name, ...) services[[name]](session_repo, session_actor, ...)
    lang <- shiny::reactive(if (is.null(input$language)) language else input$language)
    shiny::observeEvent(lang(), {
      session$sendCustomMessage("delphyr-language", lang())
      shiny::updateSelectInput(session, "language", label = tr(lang(), "Sprache", "Language"))
      shiny::updateSelectInput(session, "study", label = tr(lang(), "Studie", "Study"))
    })
    capabilities <- shiny::reactiveVal(character())
    studies <- shiny::reactiveVal(data.frame())
    status <- shiny::reactiveVal("")
    output$banner <- shiny::renderUI(shiny::tags$aside(class = "del-banner", tr(
      lang(),
      "Synthetische Entwicklungsumgebung. Keine realen Teilnehmendendaten eingeben. E-Mails werden nicht versendet.",
      "Synthetic development environment. Do not enter real participant data. No email is sent."
    )))
    output$intro <- shiny::renderUI(shiny::tagList(
      shiny::tags$h2(tr(lang(), "Gemeinsam Wissen bewerten", "Assess evidence together")),
      shiny::tags$p(workspace_intro(capabilities(), lang()))
    ))
    output$status <- shiny::renderText(localize_status(status(), lang()))
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
    shiny::observeEvent(study(), {
      capabilities(character())
      if ("get_capabilities" %in% names(services)) {
        tryCatch(capabilities(call("get_capabilities", study())), error = function(e) status(safe_error(e, lang())))
      }
    })
    output$navigation <- shiny::renderUI({
      links <- workspace_sections(capabilities(), lang())
      if (!nrow(links)) {
        return(NULL)
      }
      shiny::tags$nav(
        class = "del-nav", `aria-label` = tr(lang(), "Bereiche dieser Studie", "Study sections"),
        shiny::tags$ul(lapply(seq_len(nrow(links)), function(i) shiny::tags$li(shiny::tags$a(href = paste0("#", links$id[i]), links$label[i]))))
      )
    })
    panel_server("panel", study, lang, call, feedback_available = "get_feedback" %in% names(services), capabilities_available = "get_capabilities" %in% names(services), withdrawal_available = "withdraw_participation" %in% names(services))
    management_server("management", study, lang, call, services)
    editorial_server("editorial", study, lang, call, services)
    communications_server("communications", study, lang, call, services)
    protocols_server("protocols", study, lang, call, services)
    panel_import_server("panel_import", study, lang, call, services)
  }
  shiny::shinyApp(ui, server)
}
