communications_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

communications_server <- function(id, study, lang, call, services) {
  shiny::moduleServer(id, function(input, output, session) {
    allowed <- shiny::reactiveVal(FALSE)
    rounds <- shiny::reactiveVal(data.frame())
    recipients <- shiny::reactiveVal(data.frame())
    candidate <- shiny::reactiveVal(NULL)
    status <- shiny::reactiveVal("")
    needed <- c("get_capabilities", "list_campaign_rounds", "list_campaign_enrollments", "prepare_campaign", "preview_campaign", "release_campaign", "cancel_campaign")
    ready <- all(needed %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    shiny::observeEvent(study(), {
      candidate(NULL)
      recipients(data.frame())
      rounds(data.frame())
      allowed(FALSE)
      if (ready) {
        attempt(function() {
          allowed("coordinate" %in% call("get_capabilities", study()))
          if (allowed()) rounds(call("list_campaign_rounds", study()))
        })
      }
    })
    field <- function(name, default = "") {
      x <- shiny::isolate(input[[name]])
      if (is.null(x)) default else x
    }
    output$body <- shiny::renderUI({
      shiny::req(allowed())
      ns <- session$ns
      l <- lang()
      r <- rounds()
      shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Synthetische Kommunikation", "Synthetic communications")),
        shiny::tags$p(class = "del-banner", tr(l, "Nur lokale Testbelege. Diese Anwendung versendet keine E-Mails. Empf\u00e4nger werden ausschlie\u00dflich durch Studienpseudonyme dargestellt.", "Local test receipts only. This application sends no email. Recipients are represented only by study pseudonyms.")),
        shiny::selectInput(ns("round"), tr(l, "Runde", "Round"), if (nrow(r)) stats::setNames(r$id, paste(tr(l, "Runde", "Round"), r$number, state_label(r$state, l))) else character(), selected = field("round", if (nrow(r)) r$id[1] else NULL)),
        shiny::uiOutput(ns("recipients")),
        shiny::selectInput(ns("kind"), tr(l, "Mitteilungsart", "Message type"), stats::setNames(c("invitation", "round_start", "reminder", "deadline_change", "completion"), if (l == "en") c("Invitation", "Round opening", "Reminder", "Deadline change", "Study completion") else c("Einladung", "Rundenbeginn", "Erinnerung", "Frist\u00e4nderung", "Studienabschluss")), selected = field("kind", "invitation")),
        shiny::selectInput(ns("locale"), tr(l, "Sprache der Mitteilung", "Message language"), c("Deutsch" = "de", "English" = "en"), selected = field("locale", l)),
        shiny::numericInput(ns("version"), tr(l, "Vorlagenversion", "Template version"), value = field("version", 1), min = 1, step = 1),
        shiny::textInput(ns("subject"), tr(l, "Betreff", "Subject"), value = field("subject"), width = "100%"),
        shiny::textAreaInput(ns("message"), tr(l, "Vollst\u00e4ndiger Nachrichtentext", "Complete message text"), value = field("message"), width = "100%"),
        shiny::actionButton(ns("prepare"), tr(l, "Genaue Vorschau erstellen", "Create exact preview")),
        shiny::uiOutput(ns("preview")), shiny::tableOutput(ns("recipient_preview")),
        shiny::textAreaInput(ns("reason"), tr(l, "Freigabe- oder Abbruchbegr\u00fcndung", "Approval or cancellation rationale"), value = field("reason"), width = "100%"),
        shiny::checkboxInput(ns("confirm"), tr(l, "Ich habe Text und genaue Empf\u00e4ngerliste gepr\u00fcft.", "I reviewed the text and exact recipient list."), FALSE),
        shiny::tags$div(
          class = "del-actions",
          shiny::actionButton(ns("release"), tr(l, "F\u00fcr lokale Testbelege freigeben", "Approve local test receipts")),
          shiny::actionButton(ns("refresh"), tr(l, "Belegstatus aktualisieren", "Refresh receipt status")),
          shiny::actionButton(ns("cancel"), tr(l, "Ausstehende Testbelege abbrechen", "Cancel pending test receipts"))
        ),
        status_ui(ns("status"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(status())
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    shiny::observeEvent(input$round, attempt(function() {
      shiny::req(allowed(), input$round)
      recipients(call("list_campaign_enrollments", input$round))
      candidate(NULL)
    }))
    output$recipients <- shiny::renderUI({
      r <- recipients()
      shiny::req(nrow(r))
      shiny::selectizeInput(session$ns("enrollments"), tr(lang(), "Genaue Empf\u00e4ngerauswahl (Pseudonyme)", "Exact recipient selection (pseudonyms)"), choices = stats::setNames(r$enrollment_id, paste(r$pseudonym, state_label(r$state, lang()))), selected = field("enrollments", character()), multiple = TRUE)
    })
    draft <- function() list(round = input$round, enrollments = sort(input$enrollments), kind = input$kind, subject = input$subject, message = input$message, locale = input$locale, version = input$version)
    frozen_draft <- shiny::reactiveVal(NULL)
    shiny::observeEvent(input$prepare, attempt(function() {
      shiny::req(allowed(), input$round, length(input$enrollments) > 0)
      d <- draft()
      r <- call("prepare_campaign", d$round, d$enrollments, d$kind, d$subject, d$message, locale = d$locale, template_version = d$version, command_id = command_id())
      p <- call("preview_campaign", r$id)
      if (!identical(p$hash, r$hash) || !setequal(p$recipients$enrollment_id, d$enrollments)) stop("Preview does not match prepared campaign")
      candidate(p)
      frozen_draft(d)
      shiny::updateCheckboxInput(session, "confirm", value = FALSE)
      status(tr(lang(), "Vorschau erstellt. Noch keine Freigabe.", "Preview created. Approval is still required."))
    }))
    output$preview <- shiny::renderUI({
      p <- candidate()
      shiny::req(p)
      shiny::tagList(
        shiny::tags$h3(p$subject), shiny::tags$p(class = "del-consent", p$body),
        shiny::tags$p(paste(nrow(p$recipients), tr(lang(), "genau ausgew\u00e4hlte Empf\u00e4nger", "exactly selected recipients"))),
        shiny::tags$p(if (p$cancelled) tr(lang(), "Abgebrochen", "Cancelled") else if (p$released) tr(lang(), "F\u00fcr lokale Testbelege freigegeben", "Approved for local test receipts") else tr(lang(), "Entwurf", "Draft"))
      )
    })
    output$recipient_preview <- shiny::renderTable({
      p <- candidate()
      shiny::req(p)
      r <- p$recipients[, c("pseudonym", "delivery_state"), drop = FALSE]
      r$delivery_state <- delivery_label(r$delivery_state, lang())
      names(r) <- c(tr(lang(), "Pseudonym", "Pseudonym"), tr(lang(), "Belegstatus", "Receipt state"))
      r
    })
    shiny::observeEvent(input$release, attempt(function() {
      p <- candidate()
      shiny::req(p, isTRUE(input$confirm))
      if (!identical(frozen_draft(), draft())) stop("Draft changed; create a new preview")
      call("release_campaign", p$id, p$hash, input$reason, command_id())
      candidate(call("preview_campaign", p$id))
      status(tr(lang(), "Freigegeben. Es werden keine E-Mails versendet.", "Approved. No email will be sent."))
    }))
    shiny::observeEvent(input$refresh, attempt(function() {
      p <- candidate()
      shiny::req(p)
      candidate(call("preview_campaign", p$id))
    }))
    shiny::observeEvent(input$cancel, attempt(function() {
      p <- candidate()
      shiny::req(p, isTRUE(input$confirm))
      call("cancel_campaign", p$id, input$reason, command_id())
      candidate(call("preview_campaign", p$id))
      status(tr(lang(), "Ausstehende Belege abgebrochen. Bereits gespeicherte Belege bleiben erhalten.", "Pending receipts cancelled. Existing receipts are preserved."))
    }))
  })
}

delivery_label <- function(state, lang) {
  values <- if (identical(lang, "en")) c(draft = "Draft", queued = "Queued", running = "Processing", sink_recorded = "Local receipt recorded", suppressed = "Suppressed", delivery_unknown = "Outcome unknown") else c(draft = "Entwurf", queued = "Eingereiht", running = "In Bearbeitung", sink_recorded = "Lokaler Beleg gespeichert", suppressed = "Unterdr\u00fcckt", delivery_unknown = "Ergebnis unbekannt")
  unname(ifelse(state %in% names(values), values[state], state))
}
