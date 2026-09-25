operations_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::uiOutput(ns("body"))
}
operations_server <- function(id, study, round, lang, call, services, refresh, allowed) {
  shiny::moduleServer(id, function(input, output, session) {
    operation <- shiny::reactiveVal(NULL)
    job_type <- shiny::reactiveVal(NULL)
    artifact <- shiny::reactiveVal(NULL)
    analysis <- shiny::reactiveVal(NULL)
    feedback <- shiny::reactiveVal(NULL)
    preview <- shiny::reactiveVal(NULL)
    setup <- shiny::reactiveVal(NULL)
    items <- shiny::reactiveVal(NULL)
    status <- shiny::reactiveVal("")
    needed <- c("freeze_round", "request_analysis", "get_operation", "get_analysis", "create_feedback", "get_feedback_candidate", "release_feedback", "assign_feedback", "request_export", "download_artifact", "get_study_setup", "prepare_round")
    ready <- all(needed %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    shiny::observeEvent(study(), {
      operation(NULL)
      artifact(NULL)
      analysis(NULL)
      feedback(NULL)
      preview(NULL)
      items(NULL)
      setup(NULL)
      if (ready && allowed()) attempt(function() setup(call("get_study_setup", study())))
    })
    output$body <- shiny::renderUI({
      shiny::req(ready, allowed())
      ns <- session$ns
      shiny::tagList(
        shiny::tags$hr(), shiny::tags$h3(tr(lang(), "Auswertung und Folgerunde", "Analysis and subsequent round")),
        shiny::tags$p(tr(lang(), "Diese Aktionen beziehen sich auf die oben ausgew\u00e4hlte Runde. Analyse und Export werden im Hintergrund vorbereitet; mit Auftrag pr\u00fcfen sehen Sie den aktuellen Stand.", "These actions use the round selected above. Analysis and exports are prepared in the background; use Check operation to see their progress.")),
        shiny::tags$div(class = "del-actions", shiny::actionButton(ns("freeze"), tr(lang(), "Runde einfrieren", "Freeze round")), shiny::actionButton(ns("analyse"), tr(lang(), "Analyse beauftragen", "Request analysis")), shiny::actionButton(ns("poll"), tr(lang(), "Auftrag pr\u00fcfen", "Check operation")), shiny::actionButton(ns("read"), tr(lang(), "Analyse anzeigen", "View analysis"))),
        shiny::tableOutput(ns("analysis")),
        shiny::tags$details(
          shiny::tags$summary(tr(lang(), "Feedback pr\u00fcfen und freigeben", "Review and release feedback")),
          shiny::actionButton(ns("draft"), tr(lang(), "Feedback erstellen", "Create feedback")), shiny::verbatimTextOutput(ns("preview")),
          shiny::checkboxInput(ns("reviewed"), tr(lang(), "Ich habe dieses Feedback gepr\u00fcft", "I reviewed this feedback"), FALSE),
          shiny::actionButton(ns("release"), tr(lang(), "Feedback freigeben", "Release feedback")),
          shiny::actionButton(ns("assign"), tr(lang(), "Der ausgew\u00e4hlten Folgerunde zuweisen", "Assign to selected subsequent round"))
        ),
        shiny::tags$details(
          shiny::tags$summary(tr(lang(), "Neue Runde vorbereiten", "Prepare a new round")),
          shiny::tags$p("CSV: item_code, item_version, locale, text, dimension_code, scale_code, source_ref, required, display_order. UTF-8; required: TRUE/FALSE."),
          shiny::fileInput(ns("csv"), "Instrument (CSV, DE/EN)", accept = ".csv"), shiny::actionButton(ns("validate"), tr(lang(), "Import pr\u00fcfen", "Validate import")),
          shiny::tableOutput(ns("items")), shiny::uiOutput(ns("consents")),
          shiny::textInput(ns("deadline"), tr(lang(), "Frist mit Zeitzone", "Deadline with timezone"), placeholder = "2026-12-01T18:00:00+01:00"),
          shiny::actionButton(ns("prepare"), tr(lang(), "Runde vorbereiten", "Prepare round"))
        ),
        shiny::tags$div(class = "del-actions", shiny::actionButton(ns("export"), tr(lang(), "Export beauftragen", "Request export")), shiny::downloadButton(ns("download"), tr(lang(), "Export herunterladen", "Download export"))), status_ui(ns("status"))
      )
    })
    output$status <- shiny::renderText(status())
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    selected <- function() {
      r <- round()
      shiny::req(nrow(r) == 1)
      r
    }
    snapshot <- function() {
      r <- selected()
      shiny::req(!is.na(r$snapshot_id), nzchar(r$snapshot_id))
      r$snapshot_id
    }
    shiny::observeEvent(input$freeze, attempt(function() {
      r <- selected()
      call("freeze_round", r$id, command_id())
      refresh()
      status(tr(lang(), "Snapshot best\u00e4tigt.", "Snapshot confirmed."))
    }))
    shiny::observeEvent(input$analyse, attempt(function() {
      r <- call("request_analysis", snapshot(), command_id())
      operation(r$id)
      job_type("analysis")
      status(tr(lang(), "Analyse eingereiht. Auftrag pr\u00fcfen.", "Analysis queued. Check the operation."))
    }))
    shiny::observeEvent(input$export, attempt(function() {
      r <- call("request_export", snapshot(), command_id())
      operation(r$id)
      job_type("export")
      artifact(NULL)
      status(tr(lang(), "Export eingereiht. Auftrag pr\u00fcfen.", "Export queued. Check the operation."))
    }))
    shiny::observeEvent(input$poll, attempt(function() {
      shiny::req(operation())
      r <- call("get_operation", operation())
      status(paste(tr(lang(), "Auftrag:", "Operation:"), r$state))
      if (identical(r$state, "succeeded")) {
        if (job_type() == "export") artifact(r$result_ref) else analysis(call("get_analysis", r$result_ref))
        refresh()
      }
    }))
    shiny::observeEvent(input$read, attempt(function() {
      r <- selected()
      shiny::req(!is.na(r$analysis_id))
      analysis(call("get_analysis", r$analysis_id))
    }))
    output$analysis <- shiny::renderTable(
      {
        a <- analysis()
        shiny::req(a)
        a$results
      },
      striped = TRUE
    )
    shiny::observeEvent(input$draft, attempt(function() {
      r <- selected()
      shiny::req(!is.na(r$analysis_id))
      f <- call("create_feedback", r$analysis_id, list(), command_id())
      feedback(f)
      preview(call("get_feedback_candidate", f$id))
      shiny::updateCheckboxInput(session, "reviewed", value = FALSE)
      status(tr(lang(), "Feedback zur Pr\u00fcfung erstellt.", "Feedback created for review."))
    }))
    output$preview <- shiny::renderPrint({
      shiny::req(preview())
      print(preview())
    })
    shiny::observeEvent(input$release, attempt(function() {
      shiny::req(feedback(), preview())
      if (!isTRUE(input$reviewed)) stop("review required")
      f <- feedback()
      if (!identical(preview()$hash, f$hash)) stop("preview hash mismatch")
      call("release_feedback", f$id, f$hash, command_id())
      refresh()
      status(tr(lang(), "Feedback freigegeben.", "Feedback released."))
    }))
    shiny::observeEvent(input$assign, attempt(function() {
      shiny::req(feedback())
      call("assign_feedback", selected()$id, feedback()$id, command_id())
      status(tr(lang(), "Feedback zugewiesen.", "Feedback assigned."))
    }))
    shiny::observeEvent(input$csv, items(NULL))
    shiny::observeEvent(input$validate, attempt(function() {
      shiny::req(input$csv, setup())
      if (input$csv$size > 5e6) stop("file too large")
      x <- utils::read.csv(input$csv$datapath, stringsAsFactors = FALSE, fileEncoding = "UTF-8", check.names = FALSE)
      delphyr::validate_items(x, setup()$protocol)
      items(x)
      status(tr(lang(), "Import g\u00fcltig. Noch keine Runde angelegt.", "Import validated. No round created yet."))
    }))
    output$items <- shiny::renderTable(
      {
        shiny::req(items())
        utils::head(items(), 20)
      },
      striped = TRUE
    )
    output$consents <- shiny::renderUI({
      shiny::req(setup())
      x <- setup()$consent_versions
      shiny::selectInput(session$ns("consent"), tr(lang(), "Studieninformation", "Study information"), stats::setNames(x$id, paste(x$locale, x$content)))
    })
    shiny::observeEvent(input$prepare, attempt(function() {
      shiny::req(items(), input$consent, input$deadline)
      call("prepare_round", study(), items(), input$consent, input$deadline, command_id())
      refresh()
      status(tr(lang(), "Rundenentwurf erstellt. Vor \u00d6ffnung pr\u00fcfen und freigeben.", "Round draft created. Review and approve before opening."))
    }))
    output$download <- shiny::downloadHandler(filename = function() "delphyr-export.zip", content = function(file) {
      shiny::req(artifact())
      path <- call("download_artifact", artifact())
      files <- list.files(path, full.names = TRUE)
      zip::zipr(file, files, root = path)
    }, contentType = "application/zip")
  })
}
