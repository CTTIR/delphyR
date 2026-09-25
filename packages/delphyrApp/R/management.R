management_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tags$section(class = "del-sheet del-management", shiny::uiOutput(ns("body")), status_ui(ns("status")), operations_ui(ns("operations")))
}
management_server <- function(id, study, lang, call, services) {
  shiny::moduleServer(id, function(input, output, session) {
    rounds <- shiny::reactiveVal(data.frame())
    allowed <- shiny::reactiveVal(FALSE)
    timezone <- shiny::reactiveVal("UTC")
    status <- shiny::reactiveVal("")
    refresh <- function() {
      allowed(FALSE)
      if (!all(c("get_capabilities", "list_rounds", "transition_round") %in% names(services))) {
        return()
      }
      tryCatch(
        {
          caps <- call("get_capabilities", study())
          allowed("manage" %in% caps)
          if (allowed()) {
            rounds(call("list_rounds", study()))
            if ("get_study_setup" %in% names(services)) {
              timezone(call("get_study_setup", study())$protocol$study$timezone)
            }
          }
        },
        error = function(e) status(safe_error(e, lang()))
      )
    }
    shiny::observeEvent(study(), refresh())
    output$status <- shiny::renderText(status())
    output$body <- shiny::renderUI({
      shiny::req(allowed())
      r <- rounds()
      ns <- session$ns
      shiny::tagList(
        shiny::tags$h2(tr(lang(), "Studienbereich", "Study management")),
        shiny::tags$p(tr(
          lang(), "Pr\u00fcfen Sie den Rundenstatus und begr\u00fcnden Sie jeden \u00dcbergang. Rechte und Zust\u00e4nde werden beim Ausf\u00fchren erneut gepr\u00fcft.",
          "Review the round state and record a reason for every transition. Permissions and state are checked again when the action runs."
        )),
        shiny::tableOutput(ns("rounds")),
        shiny::selectInput(ns("round"), tr(lang(), "Runde", "Round"), stats::setNames(r$id, paste(tr(lang(), "Runde", "Round"), r$number, state_label(r$state, lang())))),
        shiny::selectInput(ns("target"), tr(lang(), "Neuer Status", "New state"), stats::setNames(c("review", "approved", "open", "closed", "finalized"), state_label(c("review", "approved", "open", "closed", "finalized"), lang()))),
        shiny::textAreaInput(ns("reason"), tr(lang(), "Begr\u00fcndung", "Reason"), width = "100%"),
        shiny::checkboxInput(ns("confirm"), tr(lang(), "Ich habe die ausgew\u00e4hlte Runde und den Zielstatus gepr\u00fcft", "I reviewed the round and target state"), FALSE),
        shiny::actionButton(ns("transition"), tr(lang(), "Status \u00e4ndern", "Change state"), class = "btn-primary"),
        if ("complete_study" %in% names(services)) shiny::actionButton(ns("complete"), tr(lang(), "Studie abschlie\u00dfen", "Complete study"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    output$rounds <- shiny::renderTable(
      {
        r <- rounds()
        if (!nrow(r)) {
          return(NULL)
        }
        round_display(r, lang(), timezone())
      },
      striped = TRUE,
      rownames = FALSE
    )
    shiny::observeEvent(input$complete, {
      shiny::req(allowed(), isTRUE(input$confirm), input$reason)
      if (!nzchar(trimws(input$reason))) {
        return()
      }
      tryCatch(
        {
          call("complete_study", study(), input$reason, command_id())
          refresh()
          status(tr(lang(), "Studie abgeschlossen.", "Study completed."))
        },
        error = function(e) status(safe_error(e, lang()))
      )
    })
    selected <- shiny::reactive({
      r <- rounds()
      r[r$id == input$round, , drop = FALSE]
    })
    operations_server("operations", study, selected, lang, call, services, refresh, allowed)
    shiny::observeEvent(input$transition, {
      shiny::req(allowed(), input$round, input$target)
      if (!isTRUE(input$confirm) || is.null(input$reason) || !nzchar(trimws(input$reason))) {
        status(tr(lang(), "Begr\u00fcndung und Best\u00e4tigung sind erforderlich.", "A reason and confirmation are required."))
        return()
      }
      r <- rounds()
      r <- r[r$id == input$round, , drop = FALSE]
      shiny::req(nrow(r) == 1)
      tryCatch(
        {
          call("transition_round", r$id, input$target, r$instrument_hash, input$reason, command_id())
          refresh()
          status(tr(lang(), "Status\u00e4nderung best\u00e4tigt.", "State change confirmed."))
        },
        error = function(e) status(safe_error(e, lang()))
      )
    })
  })
}
