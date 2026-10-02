management_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tags$section(class = "del-sheet del-management", shiny::uiOutput(ns("body")), status_ui(ns("status")), operations_ui(ns("operations")))
}
management_server <- function(id, study, lang, call, services, changed = NULL, touch = function() NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    field <- function(name, default = "") {
      value <- shiny::isolate(input[[name]])
      if (is.null(value)) default else value
    }
    rounds <- shiny::reactiveVal(data.frame())
    allowed <- shiny::reactiveVal(FALSE)
    timezone <- shiny::reactiveVal("UTC")
    status <- shiny::reactiveVal("")
    # The instrument and readiness findings last shown for one exact round.
    review <- shiny::reactiveVal(NULL)
    reviewable <- all(c("get_round_instrument", "get_round_readiness") %in% names(services))
    background <- shiny::reactiveVal(NULL)
    load_review <- function(id) review(list(id = id, instrument = call("get_round_instrument", id), readiness = call("get_round_readiness", id)))
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
    shiny::observeEvent(study(), {
      review(NULL)
      refresh()
    })
    shiny::observeEvent(input$round, review(NULL))
    output$status <- shiny::renderText(localize_status(status(), lang()))
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
        shiny::selectInput(ns("round"), tr(lang(), "Runde", "Round"), stats::setNames(r$id, paste(tr(lang(), "Runde", "Round"), r$number, round_state_label(r$state, lang()))), selected = field("round", if (nrow(r)) utils::tail(r$id, 1) else NULL)),
        if (reviewable) {
          shiny::tagList(
            shiny::tags$div(
              class = "del-actions",
              shiny::actionButton(ns("review"), tr(lang(), "Instrument und Bereitschaft pr\u00fcfen", "Review instrument and readiness")),
              if ("enroll_panel" %in% names(services)) shiny::actionButton(ns("enroll"), tr(lang(), "Berechtigte Panelmitglieder aufnehmen", "Enroll eligible panel members"))
            ),
            shiny::uiOutput(ns("review_panel"))
          )
        },
        shiny::selectInput(ns("target"), tr(lang(), "Neuer Status", "New state"), stats::setNames(c("review", "approved", "open", "closed", "finalized", "cancelled"), round_state_label(c("review", "approved", "open", "closed", "finalized", "cancelled"), lang())), selected = field("target", "review")),
        shiny::textAreaInput(ns("reason"), tr(lang(), "Begr\u00fcndung", "Reason"), value = field("reason"), width = "100%"),
        shiny::checkboxInput(ns("confirm"), tr(lang(), "Ich habe die ausgew\u00e4hlte Runde und den Zielstatus gepr\u00fcft", "I reviewed the round and target state"), FALSE),
        shiny::actionButton(ns("transition"), tr(lang(), "Status \u00e4ndern", "Change state"), class = "btn-primary"),
        if ("complete_study" %in% names(services)) shiny::actionButton(ns("complete"), tr(lang(), "Studie abschlie\u00dfen", "Complete study")),
        if ("get_operations_status" %in% names(services)) {
          shiny::tags$details(
            shiny::tags$summary(tr(lang(), "Stand der Hintergrundarbeit", "Status of background work")),
            shiny::tags$p(tr(lang(), "Analysen, Exporte und freigegebene Mitteilungen verarbeitet ein getrennter Worker. Lange Wartezeiten oder endg\u00fcltig fehlgeschlagene Auftr\u00e4ge sind dem Betrieb zu melden.", "A separate worker processes analyses, exports and approved messages. Report long waiting times or permanently failed operations to the operator.")),
            shiny::actionButton(ns("background_load"), tr(lang(), "Stand anzeigen", "Show status")),
            shiny::tableOutput(ns("background_jobs")),
            shiny::tableOutput(ns("background_messages"))
          )
        }
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
    operations_server("operations", study, selected, lang, call, services, function() {
      refresh()
      touch()
    }, allowed, changed = changed)
    shiny::observeEvent(input$transition, {
      shiny::req(allowed(), input$round, input$target)
      if (!isTRUE(input$confirm) || is.null(input$reason) || !nzchar(trimws(input$reason))) {
        status(tr(lang(), "Begr\u00fcndung und Best\u00e4tigung sind erforderlich.", "A reason and confirmation are required."))
        return()
      }
      r <- rounds()
      r <- r[r$id == input$round, , drop = FALSE]
      shiny::req(nrow(r) == 1)
      hash <- r$instrument_hash
      if (reviewable && identical(input$target, "approved")) {
        # Approval binds the exact instrument that was displayed for review.
        shown <- review()
        if (is.null(shown) || !identical(shown$id, r$id)) {
          status(tr(lang(), "Vor der Freigabe das Instrument dieser Runde anzeigen und pr\u00fcfen.", "Display and review this round\u2019s instrument before approving it."))
          return()
        }
        hash <- shown$instrument$round$instrument_hash
      }
      tryCatch(
        {
          call("transition_round", r$id, input$target, hash, input$reason, command_id())
          review(NULL)
          refresh()
          touch()
          shiny::updateCheckboxInput(session, "confirm", value = FALSE)
          status(tr(lang(), "Status\u00e4nderung best\u00e4tigt.", "State change confirmed."))
        },
        error = function(e) {
          if (inherits(e, "DEL_VALIDATION") && is.character(e$path) && startsWith(e$path, "round.readiness:")) {
            tryCatch(load_review(r$id), error = function(e2) NULL)
            status(tr(lang(), "Die Runde ist noch nicht bereit. Die Befunde stehen in der Bereitschaftspr\u00fcfung.", "The round is not ready yet. The readiness review lists the findings."))
          } else if (inherits(e, "DEL_CONFLICT")) {
            status(tr(lang(), "Dieser \u00dcbergang ist im aktuellen Status der Runde nicht m\u00f6glich, oder die Runde wurde inzwischen ge\u00e4ndert.", "This transition is not possible in the round\u2019s current state, or the round has changed in the meantime."))
          } else {
            status(safe_error(e, lang()))
          }
        }
      )
    })
    shiny::observeEvent(input$background_load, {
      shiny::req(allowed())
      tryCatch(background(call("get_operations_status", study())), error = function(e) status(safe_error(e, lang())))
    })
    output$background_jobs <- shiny::renderTable({
      x <- background()
      shiny::req(x, nrow(x$jobs) > 0)
      j <- x$jobs
      kind <- ifelse(j$type == "analysis", tr(lang(), "Analyse", "Analysis"), paste(tr(lang(), "Export", "Export"), j$profile))
      out <- data.frame(kind, operation_state_label(j$state, lang()), j$n, j$oldest_waiting_seconds, ifelse(is.na(j$error_codes), "", j$error_codes), stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("Auftrag", "Status", "Anzahl", "\u00c4lteste Wartezeit (s)", "Fehlercode"), c("Operation", "State", "Count", "Oldest waiting (s)", "Error code"))
      out
    })
    output$background_messages <- shiny::renderTable({
      x <- background()
      shiny::req(x, nrow(x$messages) > 0)
      m <- x$messages
      out <- data.frame(delivery_label(m$state, lang()), m$n, m$oldest_waiting_seconds, stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("Mitteilungen", "Anzahl", "\u00c4lteste Wartezeit (s)"), c("Messages", "Count", "Oldest waiting (s)"))
      out
    })
    shiny::observeEvent(input$review, {
      shiny::req(allowed(), reviewable, input$round)
      tryCatch(
        {
          load_review(input$round)
          status("")
        },
        error = function(e) status(safe_error(e, lang()))
      )
    })
    shiny::observeEvent(input$enroll, {
      shiny::req(allowed(), input$round)
      tryCatch(
        {
          result <- call("enroll_panel", input$round, command_id())
          touch()
          if (reviewable) load_review(input$round)
          status(paste(tr(lang(), "Aufgenommene Panelmitglieder:", "Panel members enrolled:"), result$added))
        },
        error = function(e) status(safe_error(e, lang()))
      )
    })
    output$review_panel <- shiny::renderUI({
      x <- review()
      shiny::req(x)
      ns <- session$ns
      l <- lang()
      i <- x$instrument
      zone <- timezone()
      if (is.null(zone) || !nzchar(zone)) zone <- "UTC"
      findings <- x$readiness$issues
      shiny::tags$div(
        class = "del-review",
        shiny::tags$h3(paste(tr(l, "Instrument der Runde", "Instrument of round"), i$round$number)),
        shiny::tags$p(paste(tr(l, "Abgabe bis:", "Submit by:"), format(as.POSIXct(i$round$deadline, tz = "UTC"), "%Y-%m-%d %H:%M %z", tz = zone), zone, "\u00b7", tr(l, "Protokollversion", "Protocol version"), i$protocol$version)),
        shiny::tags$h4(tr(l, "Studieninformation", "Study information")),
        shiny::tags$p(class = "del-consent", lang = i$consent$locale, i$consent$content),
        shiny::tags$h4(tr(l, "Items in allen freigegebenen Sprachfassungen", "Items in every approved language version")),
        shiny::tableOutput(ns("review_items")),
        shiny::tags$h4(tr(l, "Aufgenommene Panelmitglieder", "Enrolled panel members")),
        shiny::tableOutput(ns("review_enrollments")),
        # Readiness concerns a round that has not been opened yet.
        if (i$round$state %in% c("draft", "review", "approved")) {
          shiny::tagList(
            shiny::tags$h4(tr(l, "Bereitschaftspr\u00fcfung", "Readiness review")),
            if (nrow(findings)) shiny::tableOutput(ns("review_readiness")) else shiny::tags$p(tr(l, "Keine Befunde.", "No findings."))
          )
        },
        shiny::tags$details(
          shiny::tags$summary(tr(l, "Freigabeverlauf und technische Angaben", "Approval history and technical details")),
          shiny::tableOutput(ns("review_events")),
          shiny::tags$p(class = "del-note", paste(tr(l, "Inhaltspr\u00fcfsumme:", "Content checksum:"), i$round$instrument_hash))
        )
      )
    })
    output$review_items <- shiny::renderTable(
      {
        x <- review()
        shiny::req(x)
        items <- x$instrument$items
        out <- data.frame(items$item_code, items$item_version, items$dimension_code, items$locale, items$text, ifelse(items$required, tr(lang(), "erforderlich", "required"), tr(lang(), "optional", "optional")), stringsAsFactors = FALSE)
        names(out) <- tr(lang(), c("Item", "Version", "Dimension", "Sprache", "Wortlaut", "Pflicht"), c("Item", "Version", "Dimension", "Language", "Wording", "Requirement"))
        out
      },
      striped = TRUE
    )
    output$review_enrollments <- shiny::renderTable({
      x <- review()
      shiny::req(x)
      e <- x$instrument$enrollments
      if (!nrow(e)) {
        return(NULL)
      }
      out <- data.frame(e$group_code, state_label(e$state, lang()), e$n, stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("Interessengruppe", "Status", "Anzahl"), c("Stakeholder group", "State", "Count"))
      out
    })
    output$review_readiness <- shiny::renderTable({
      x <- review()
      shiny::req(x)
      f <- x$readiness$issues
      shiny::req(nrow(f) > 0)
      out <- data.frame(ifelse(f$severity == "error", tr(lang(), "Blockiert", "Blocking"), tr(lang(), "Hinweis", "Note")), readiness_label(f$code, lang()), f$details, stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("Einstufung", "Befund", "Angabe"), c("Severity", "Finding", "Detail"))
      out
    })
    output$review_events <- shiny::renderTable({
      x <- review()
      shiny::req(x)
      e <- x$instrument$events
      if (!nrow(e)) {
        return(NULL)
      }
      out <- data.frame(round_state_label(e$target_state, lang()), e$reason, e$occurred_at, stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("\u00dcbergang", "Begr\u00fcndung", "Zeitpunkt (UTC)"), c("Transition", "Reason", "Time (UTC)"))
      out
    })
  })
}

# Round states as shown to study staff. A candidate that was never opened is
# described as withdrawn rather than with the generic job wording.
round_state_label <- function(state, lang) {
  extra <- tr(lang, c(cancelled = "Zur\u00fcckgezogen (nie ge\u00f6ffnet)"), c(cancelled = "Withdrawn (never opened)"))
  out <- state_label(state, lang)
  out[state %in% names(extra)] <- extra[state[state %in% names(extra)]]
  unname(out)
}

readiness_label <- function(code, lang) {
  en <- c(
    study_not_active = "The study is not in a state that allows data collection.",
    protocol_superseded = "The round was prepared under an earlier protocol version. Withdraw it and prepare a new round under the current protocol.",
    protocol_invalid = "The round\u2019s protocol no longer validates.",
    consent_language = "The study information is not in one of the protocol languages.",
    no_items = "The round has no items.",
    dimension_unknown = "An item uses a dimension or scale that the protocol does not define.",
    translation_missing = "An item lacks an approved language version.",
    deadline_passed = "The deadline has passed.",
    no_enrollments = "No eligible panel member is enrolled.",
    group_below_minimum = "A required group has fewer enrolled members than the minimum valid n; its results would be insufficient data.",
    panel_below_minimum = "Fewer members are enrolled than the minimum valid n; results would be insufficient data.",
    panelists_not_enrolled = "Eligible panel members are not yet enrolled in this round.",
    feedback_unassigned = "No released feedback is assigned to this round."
  )
  de <- c(
    study_not_active = "Die Studie befindet sich in keinem Zustand, der eine Erhebung erlaubt.",
    protocol_superseded = "Die Runde wurde unter einer fr\u00fcheren Protokollversion vorbereitet. Ziehen Sie sie zur\u00fcck und bereiten Sie eine neue Runde unter dem aktuellen Protokoll vor.",
    protocol_invalid = "Das Protokoll der Runde ist nicht mehr g\u00fcltig.",
    consent_language = "Die Studieninformation liegt in keiner Protokollsprache vor.",
    no_items = "Die Runde enth\u00e4lt keine Items.",
    dimension_unknown = "Ein Item verwendet eine Dimension oder Skala, die das Protokoll nicht definiert.",
    translation_missing = "Einem Item fehlt eine freigegebene Sprachfassung.",
    deadline_passed = "Die Frist ist abgelaufen.",
    no_enrollments = "Kein berechtigtes Panelmitglied ist aufgenommen.",
    group_below_minimum = "Eine erforderliche Gruppe hat weniger aufgenommene Mitglieder als das g\u00fcltige Mindest-n; ihre Ergebnisse w\u00e4ren unzureichende Daten.",
    panel_below_minimum = "Es sind weniger Mitglieder aufgenommen als das g\u00fcltige Mindest-n; die Ergebnisse w\u00e4ren unzureichende Daten.",
    panelists_not_enrolled = "Berechtigte Panelmitglieder sind in dieser Runde noch nicht aufgenommen.",
    feedback_unassigned = "Dieser Runde ist kein freigegebenes Feedback zugewiesen."
  )
  labels <- tr(lang, de, en)
  unname(ifelse(code %in% names(labels), labels[code], code))
}

operation_state_label <- function(state, lang) {
  labels <- tr(lang, c(queued = "Eingereiht", running = "In Bearbeitung", succeeded = "Erfolgreich", retry_wait = "Wartet auf Wiederholung", dead_letter = "Endg\u00fcltig fehlgeschlagen"), c(queued = "Queued", running = "Processing", succeeded = "Succeeded", retry_wait = "Waiting to retry", dead_letter = "Permanently failed"))
  unname(ifelse(state %in% names(labels), labels[state], state))
}
