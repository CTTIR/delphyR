communications_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

communications_server <- function(id, study, lang, call, services, changed = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    allowed <- shiny::reactiveVal(FALSE)
    rounds <- shiny::reactiveVal(data.frame())
    recipients <- shiny::reactiveVal(data.frame())
    candidate <- shiny::reactiveVal(NULL)
    uncertain <- shiny::reactiveVal(data.frame())
    resolving <- all(c("list_uncertain_deliveries", "resolve_delivery") %in% names(services))
    status <- shiny::reactiveVal("")
    needed <- c("get_capabilities", "list_campaign_rounds", "list_campaign_enrollments", "prepare_campaign", "preview_campaign", "release_campaign", "cancel_campaign")
    ready <- all(needed %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    shiny::observeEvent(study(), {
      candidate(NULL)
      recipients(data.frame())
      rounds(data.frame())
      uncertain(data.frame())
      allowed(FALSE)
      if (ready) {
        attempt(function() {
          allowed("coordinate" %in% call("get_capabilities", study()))
          if (allowed()) rounds(call("list_campaign_rounds", study()))
          if (allowed() && resolving) uncertain(call("list_uncertain_deliveries", study()))
        })
      }
    })
    field <- function(name, default = "") {
      x <- shiny::isolate(input[[name]])
      if (is.null(x)) default else x
    }
    # Rounds prepared or opened and members enrolled in another section.
    if (!is.null(changed)) {
      shiny::observeEvent(changed(),
        {
          if (ready && allowed()) {
            attempt(function() {
              rounds(call("list_campaign_rounds", study()))
              if (length(input$round) == 1L && nzchar(input$round) && input$round %in% rounds()$id) recipients(call("list_campaign_enrollments", input$round))
            })
          }
        },
        ignoreInit = TRUE
      )
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
        shiny::selectInput(ns("kind"), tr(l, "Mitteilungsart", "Message type"), stats::setNames(c("invitation", "round_start", "reminder", "deadline_change", "completion"), tr(l, c("Einladung", "Rundenbeginn", "Erinnerung", "Frist\u00e4nderung", "Studienabschluss"), c("Invitation", "Round opening", "Reminder", "Deadline change", "Study completion"))), selected = field("kind", "invitation")),
        shiny::selectInput(ns("locale"), tr(l, "Sprache der Mitteilung", "Message language"), c("English" = "en", "Fran\u00e7ais" = "fr", "Deutsch" = "de"), selected = field("locale", l)),
        shiny::numericInput(ns("version"), tr(l, "Vorlagenversion", "Template version"), value = field("version", 1), min = 1, step = 1),
        shiny::textInput(ns("subject"), tr(l, "Betreff", "Subject"), value = field("subject"), width = "100%"),
        shiny::textAreaInput(ns("message"), tr(l, "Vollst\u00e4ndiger Nachrichtentext", "Complete message text"), value = field("message"), width = "100%"),
        shiny::actionButton(ns("prepare"), tr(l, "Genaue Vorschau erstellen", "Create exact preview")),
        shiny::uiOutput(ns("preview")), shiny::tableOutput(ns("recipient_preview")),
        shiny::textInput(ns("not_before"), tr(l, "Fr\u00fchester Zeitpunkt mit Zeitzone (leer: sofort)", "Earliest time with timezone (empty: now)"), value = field("not_before"), placeholder = "2026-12-01T09:00:00+01:00"),
        shiny::textAreaInput(ns("reason"), tr(l, "Freigabe- oder Abbruchbegr\u00fcndung", "Approval or cancellation rationale"), value = field("reason"), width = "100%"),
        shiny::checkboxInput(ns("confirm"), tr(l, "Ich habe Text und genaue Empf\u00e4ngerliste gepr\u00fcft.", "I reviewed the text and exact recipient list."), FALSE),
        shiny::tags$div(
          class = "del-actions",
          shiny::actionButton(ns("release"), tr(l, "F\u00fcr lokale Testbelege freigeben", "Approve local test receipts")),
          shiny::actionButton(ns("refresh"), tr(l, "Belegstatus aktualisieren", "Refresh receipt status")),
          shiny::actionButton(ns("cancel"), tr(l, "Ausstehende Testbelege abbrechen", "Cancel pending test receipts"), class = "btn-outline-danger")
        ),
        if (resolving) {
          u <- uncertain()
          shiny::tags$details(
            shiny::tags$summary(paste(tr(l, "Ungewisse Zustellungen kl\u00e4ren", "Resolve uncertain deliveries"), paste0("(", nrow(u), ")"))),
            shiny::tags$p(tr(l, "Eine ungewisse Zustellung wird nie automatisch wiederholt, weil die Nachricht bereits angekommen sein kann. Pr\u00fcfen Sie beim Dienst, ob sie angenommen wurde. Erneutes Einreihen kann zu einer doppelten Nachricht f\u00fchren.", "An uncertain delivery is never repeated automatically, because the message may already have arrived. Check with the provider whether it was accepted. Queuing it again can lead to a duplicate message.")),
            shiny::tableOutput(ns("uncertain")),
            shiny::selectInput(ns("uncertain_message"), tr(l, "Ungewisse Zustellung", "Uncertain delivery"), if (nrow(u)) stats::setNames(u$message_id, paste(tr(l, "Runde", "Round"), u$round_number, "\u00b7", u$pseudonym)) else character(), selected = field("uncertain_message", NULL)),
            shiny::selectInput(ns("resolution"), tr(l, "Entscheidung", "Decision"), stats::setNames(c("confirmed_delivered", "requeue", "abandon"), c(tr(l, "Zustellung best\u00e4tigt, nicht erneut senden", "Delivery confirmed, do not send again"), tr(l, "Erneut einreihen, doppelte Nachricht m\u00f6glich", "Queue again, a duplicate is possible"), tr(l, "Aufgeben, nicht senden", "Abandon, do not send"))), selected = field("resolution", "confirmed_delivered")),
            shiny::textAreaInput(ns("resolution_reason"), tr(l, "Begr\u00fcndung und Art der Pr\u00fcfung", "Rationale and how it was checked"), value = field("resolution_reason"), width = "100%"),
            shiny::checkboxInput(ns("resolution_confirm"), tr(l, "Ich habe diese Zustellung gepr\u00fcft und kenne die Folge meiner Entscheidung.", "I checked this delivery and understand the consequence of my decision."), FALSE),
            shiny::actionButton(ns("resolve"), tr(l, "Entscheidung speichern", "Save decision"))
          )
        },
        status_ui(ns("status"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$uncertain <- shiny::renderTable({
      u <- uncertain()
      shiny::req(nrow(u) > 0)
      out <- data.frame(u$round_number, delivery_kind_label(u$kind, lang()), u$pseudonym, u$adapter, u$updated_at, stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("Runde", "Mitteilungsart", "Pseudonym", "Dienst", "Zeitpunkt (UTC)"), c("Round", "Message type", "Pseudonym", "Provider", "Time (UTC)"))
      out
    })
    shiny::observeEvent(input$resolve, attempt(function() {
      shiny::req(allowed(), resolving, input$uncertain_message, input$resolution)
      reason <- if (is.null(input$resolution_reason)) "" else trimws(input$resolution_reason)
      if (!isTRUE(input$resolution_confirm) || !nzchar(reason)) {
        status(tr(lang(), "Begr\u00fcndung und Best\u00e4tigung sind erforderlich.", "A reason and confirmation are required."))
        return()
      }
      call("resolve_delivery", study(), input$uncertain_message, input$resolution, reason, command_id())
      uncertain(call("list_uncertain_deliveries", study()))
      shiny::updateCheckboxInput(session, "resolution_confirm", value = FALSE)
      status(tr(lang(), "Entscheidung zur Zustellung gespeichert.", "Delivery decision saved."))
    }))
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    shiny::observeEvent(input$round, attempt(function() {
      shiny::req(allowed(), input$round)
      recipients(call("list_campaign_enrollments", input$round))
      candidate(NULL)
    }))
    output$recipients <- shiny::renderUI({
      r <- recipients()
      shiny::req(nrow(r) > 0)
      reminders <- if (is.null(r$reminders)) rep("", nrow(r)) else paste0(" \u00b7 ", tr(lang(), "Erinnerungen:", "reminders:"), " ", r$reminders)
      shiny::selectizeInput(session$ns("enrollments"), tr(lang(), "Genaue Empf\u00e4ngerauswahl (Pseudonyme)", "Exact recipient selection (pseudonyms)"), choices = stats::setNames(r$enrollment_id, paste0(r$pseudonym, " ", state_label(r$state, lang()), reminders)), selected = field("enrollments", character()), multiple = TRUE)
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
      rules <- p$rules
      limits <- c(
        if (!is.null(rules$quiet_start)) paste(tr(lang(), "Ruhezeit:", "Quiet hours:"), rules$quiet_start, "\u2013", rules$quiet_end, rules$timezone),
        if (!is.null(rules$max_reminders)) paste(tr(lang(), "H\u00f6chstzahl der Erinnerungen je Person und Runde:", "Maximum reminders per person and round:"), rules$max_reminders),
        if (!is.null(rules$min_reminder_interval_hours)) paste(tr(lang(), "Mindestabstand zwischen Erinnerungen in Stunden:", "Minimum hours between reminders:"), rules$min_reminder_interval_hours)
      )
      shiny::tagList(
        shiny::tags$h3(p$subject), shiny::tags$p(class = "del-consent", p$body),
        shiny::tags$p(paste(nrow(p$recipients), tr(lang(), "genau ausgew\u00e4hlte Empf\u00e4nger", "exactly selected recipients"))),
        if (length(limits)) shiny::tags$p(class = "del-note", paste(limits, collapse = " \u00b7 ")),
        if (!is.null(p$schedule)) shiny::tags$p(paste(tr(lang(), "Freigegeben ab (UTC):", "Approved from (UTC):"), p$schedule$not_before)),
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
      at <- if (is.null(input$not_before)) "" else trimws(input$not_before)
      tryCatch(
        {
          call("release_campaign", p$id, p$hash, input$reason, command_id(), not_before = if (nzchar(at)) at else NULL)
          candidate(call("preview_campaign", p$id))
          status(tr(lang(), "Freigegeben. Es werden keine E-Mails versendet.", "Approved. No email will be sent."))
        },
        error = function(e) {
          path <- if (inherits(e, "delphyr_error")) e$path else ""
          status(switch(path,
            campaign.reminder_limit = tr(lang(), "Nicht freigegeben: Mindestens eine Person hat die H\u00f6chstzahl an Erinnerungen dieser Runde erreicht. W\u00e4hlen Sie die Empf\u00e4nger neu.", "Not approved: at least one person has reached the maximum number of reminders for this round. Select the recipients again."),
            campaign.reminder_interval = tr(lang(), "Nicht freigegeben: Der Mindestabstand zur vorherigen Erinnerung ist f\u00fcr mindestens eine Person nicht erreicht. W\u00e4hlen Sie einen sp\u00e4teren Zeitpunkt oder andere Empf\u00e4nger.", "Not approved: the minimum interval since the previous reminder has not passed for at least one person. Choose a later time or other recipients."),
            campaign.not_before = tr(lang(), "Nicht freigegeben: Der Zeitpunkt braucht eine Zeitzone, darf nicht vergangen sein und h\u00f6chstens 90 Tage in der Zukunft liegen.", "Not approved: the time needs a timezone, must not be in the past and at most 90 days ahead."),
            safe_error(e, lang())
          ))
        }
      )
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
  values <- tr(
    lang, c(draft = "Entwurf", queued = "Eingereiht", running = "In Bearbeitung", sink_recorded = "Lokaler Beleg gespeichert", suppressed = "Unterdr\u00fcckt", delivery_unknown = "Ergebnis unbekannt", accepted = "Vom Dienst angenommen", failed = "Fehlgeschlagen, nicht gesendet", resolved_delivered = "Zustellung best\u00e4tigt", abandoned = "Aufgegeben"),
    c(draft = "Draft", queued = "Queued", running = "Processing", sink_recorded = "Local receipt recorded", suppressed = "Suppressed", delivery_unknown = "Outcome unknown", accepted = "Accepted by the provider", failed = "Failed, not sent", resolved_delivered = "Delivery confirmed", abandoned = "Abandoned")
  )
  unname(ifelse(state %in% names(values), values[state], state))
}

delivery_kind_label <- function(kind, lang) {
  labels <- tr(lang, c(invitation = "Einladung", round_start = "Rundenbeginn", reminder = "Erinnerung", deadline_change = "Frist\u00e4nderung", completion = "Studienabschluss"), c(invitation = "Invitation", round_start = "Round opening", reminder = "Reminder", deadline_change = "Deadline change", completion = "Study completion"))
  unname(ifelse(kind %in% names(labels), labels[kind], kind))
}
