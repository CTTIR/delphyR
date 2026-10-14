management_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tags$section(
    class = "del-sheet del-management",
    shiny::uiOutput(ns("body")), status_ui(ns("status")), operations_ui(ns("operations")),
    # The section keeps its card while its own status has a message; the
    # status of the completion is therefore not a direct child.
    shiny::tags$div(shiny::uiOutput(ns("completion")), status_ui(ns("completion_status")))
  )
}
management_server <- function(id, study, lang, call, services, changed = NULL, touch = function() NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    # A text cleared after a confirmed action is not restored from the input
    # value the browser has not replaced yet.
    stale <- new.env(parent = emptyenv())
    field <- function(name, default = "") {
      value <- shiny::isolate(input[[name]])
      if (is.null(value) || identical(value, stale[[name]])) default else value
    }
    forget <- function(name) {
      stale[[name]] <- shiny::isolate(input[[name]])
      shiny::updateTextAreaInput(session, name, value = "")
    }
    rounds <- shiny::reactiveVal(data.frame())
    capabilities <- shiny::reactiveVal(character())
    # The section is shown to study leadership and, read only, to analysts.
    allowed <- shiny::reactiveVal(FALSE)
    timezone <- shiny::reactiveVal("UTC")
    study_state <- shiny::reactiveVal(NA_character_)
    status <- shiny::reactiveVal("")
    completion_status <- shiny::reactiveVal("")
    # The instrument and readiness findings last shown for one exact round.
    review <- shiny::reactiveVal(NULL)
    reviewable <- all(c("get_round_instrument", "get_round_readiness") %in% names(services))
    background <- shiny::reactiveVal(NULL)
    can <- function(...) any(c(...) %in% capabilities())
    load_review <- function(id) review(list(id = id, instrument = call("get_round_instrument", id), readiness = call("get_round_readiness", id)))
    # Nothing read earlier, or for another study, stays on screen when a
    # reading fails: the section is shown again only once every reading of
    # the current study has succeeded.
    refresh <- function() {
      allowed(FALSE)
      capabilities(character())
      rounds(data.frame())
      timezone("UTC")
      study_state(NA_character_)
      if (!all(c("get_capabilities", "list_rounds", "transition_round") %in% names(services))) {
        return()
      }
      tryCatch(
        {
          caps <- call("get_capabilities", study())
          capabilities(caps)
          if (any(c("manage", "analyse") %in% caps)) {
            listed <- call("list_rounds", study())
            # The protocol is read with study leadership; otherwise times are in UTC.
            zone <- "UTC"
            if ("manage" %in% caps && "get_study_setup" %in% names(services)) zone <- call("get_study_setup", study())$protocol$study$timezone
            state <- NA_character_
            if ("list_studies" %in% names(services)) {
              s <- call("list_studies")
              if (is.data.frame(s) && "state" %in% names(s) && any(s$id == study())) state <- s$state[s$id == study()][1]
            }
            rounds(listed)
            timezone(if (is.character(zone) && length(zone) == 1L && !is.na(zone) && nzchar(zone)) zone else "UTC")
            study_state(state)
            allowed(TRUE)
          }
        },
        error = function(e) status(safe_error(e, lang()))
      )
    }
    shiny::observeEvent(study(), {
      review(NULL)
      background(NULL)
      status("")
      completion_status("")
      refresh()
    })
    shiny::observeEvent(input$round, review(NULL))
    output$status <- shiny::renderText(localize_status(status(), lang()))
    output$completion_status <- shiny::renderText(localize_status(completion_status(), lang()))
    output$body <- shiny::renderUI({
      shiny::req(allowed())
      r <- rounds()
      l <- lang()
      ns <- session$ns
      manage <- can("manage")
      # The newest round is preselected; a choice stays while it is listed,
      # and a round of another study is never kept.
      chosen <- field("round", NA_character_)
      shiny::tagList(
        shiny::tags$h2(tr(l, "Runden und Auswertung", "Rounds and analysis")),
        shiny::tags$p(if (manage) {
          tr(l, "Pr\u00fcfen Sie den Rundenstatus und begr\u00fcnden Sie jeden \u00dcbergang. Rechte und Zust\u00e4nde werden beim Ausf\u00fchren erneut gepr\u00fcft.", "Review the round state and record a rationale for every transition. Permissions and state are checked again when the action runs.")
        } else {
          tr(l, "Sie sehen die Runden und ihre Analysen. Status\u00e4nderungen, Itementscheidungen und die Freigabe von Feedback nimmt die Studienleitung vor.", "You can read the rounds and their analyses. Changes of state, item decisions and feedback releases are made by the study lead.")
        }),
        shiny::tableOutput(ns("rounds")),
        shiny::selectInput(ns("round"), tr(l, "Runde", "Round"), list_choices(r$id, round_choice_label(r, l)), selected = if (isTRUE(chosen %in% r$id)) chosen else if (nrow(r)) utils::tail(r$id, 1) else NULL, width = "100%"),
        shiny::uiOutput(ns("round_actions")),
        if (manage && "get_operations_status" %in% names(services)) {
          shiny::tags$details(
            shiny::tags$summary(tr(l, "Stand der Hintergrundarbeit", "Status of background work")),
            shiny::tags$p(class = "del-note", tr(l, "Analysen, Exporte und freigegebene Mitteilungen verarbeitet ein getrennter Worker. Lange Wartezeiten oder endg\u00fcltig fehlgeschlagene Auftr\u00e4ge sind dem Betrieb zu melden.", "A separate worker processes analyses, exports and approved messages. Report long waiting times or permanently failed operations to the operator.")),
            shiny::tags$div(class = "del-actions", shiny::actionButton(ns("background_load"), tr(l, "Stand anzeigen", "Show status"))),
            shiny::tableOutput(ns("background_jobs")),
            shiny::tableOutput(ns("background_messages"))
          )
        }
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    shiny::outputOptions(output, "completion_status", suspendWhenHidden = FALSE)
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
    selected <- shiny::reactive({
      r <- rounds()
      if (!nrow(r) || is.null(input$round)) {
        return(r[FALSE, , drop = FALSE])
      }
      r[r$id == input$round, , drop = FALSE]
    })
    # The deadline form shows the selected round's deadline; a value being
    # entered survives a new rendering of the same round, for example a change
    # of language.
    deadline_round <- NULL
    deadline_value <- function(r) {
      keep <- identical(deadline_round, r$id)
      deadline_round <<- r$id
      typed <- if (keep) read_moment(field("deadline_date", NA), field("deadline_time"), timezone()) else list()
      if (!is.null(typed$value)) typed$value else r$deadline
    }
    # Only what the selected round's state admits is offered; services check again.
    output$round_actions <- shiny::renderUI({
      shiny::req(allowed(), can("manage"))
      r <- selected()
      shiny::req(nrow(r) == 1L)
      l <- lang()
      ns <- session$ns
      targets <- round_targets(r$state)
      editable <- isTRUE(r$state %in% c("draft", "review", "approved", "open"))
      shiny::tagList(
        shiny::tags$div(
          class = "del-actions",
          if (reviewable) shiny::actionButton(ns("review"), tr(l, "Instrument und Bereitschaft pr\u00fcfen", "Review instrument and readiness")),
          if (editable && "enroll_panel" %in% names(services)) shiny::actionButton(ns("enroll"), tr(l, "Berechtigte Panelmitglieder aufnehmen", "Enroll eligible panel members"))
        ),
        if (reviewable) shiny::uiOutput(ns("review_panel")),
        shiny::tags$h3(paste(tr(l, "Status der Runde", "State of round"), r$number)),
        if (length(targets)) {
          shiny::tagList(
            shiny::selectInput(ns("target"), tr(l, "Neuer Status", "New state"), stats::setNames(targets, round_state_label(targets, l)), selected = if (field("target") %in% targets) field("target") else targets[1]),
            shiny::textAreaInput(ns("reason"), tr(l, "Begr\u00fcndung", "Rationale"), value = field("reason"), width = "100%"),
            shiny::checkboxInput(ns("confirm"), tr(l, "Ich habe die ausgew\u00e4hlte Runde und den Zielstatus gepr\u00fcft", "I reviewed the round and target state"), FALSE),
            shiny::tags$div(class = "del-actions", shiny::actionButton(ns("transition"), tr(l, "Status \u00e4ndern", "Change state"), class = "btn-primary"))
          )
        } else {
          shiny::tags$p(class = "del-note", round_next_step(r$state, l))
        },
        if (editable && "change_round_deadline" %in% names(services)) {
          shiny::tags$details(
            shiny::tags$summary(tr(l, "Frist \u00e4ndern", "Change the deadline")),
            shiny::tags$p(class = "del-note", tr(l, "Die Frist geh\u00f6rt nicht zum gepr\u00fcften Instrument. Vor der \u00d6ffnung ist jeder k\u00fcnftige Zeitpunkt m\u00f6glich; eine offene Runde kann nur verl\u00e4ngert werden. Eine geschlossene Runde wird nicht wieder ge\u00f6ffnet.", "The deadline is not part of the reviewed instrument. Before a round opens any future time is possible; an open round can only be extended. A closed round is not reopened.")),
            moment_input(ns("deadline"), tr(l, "Neue Frist", "New deadline"), timezone(), l, value = deadline_value(r)),
            shiny::textAreaInput(ns("deadline_reason"), tr(l, "Begr\u00fcndung der Frist\u00e4nderung", "Rationale for the deadline change"), value = field("deadline_reason"), width = "100%"),
            shiny::checkboxInput(ns("deadline_confirm"), tr(l, "Ich habe Runde und neue Frist gepr\u00fcft", "I reviewed the round and the new deadline"), FALSE),
            shiny::tags$div(class = "del-actions", shiny::actionButton(ns("deadline_change"), tr(l, "Frist \u00e4ndern", "Change the deadline")))
          )
        }
      )
    })
    # A refusal says what to change and quotes the reference of its log entry.
    refusal <- function(text, e) paste(text, reference_text(error_reference(e), lang()))
    shiny::observeEvent(input$deadline_change, {
      shiny::req(allowed(), can("manage"))
      r <- selected()
      shiny::req(nrow(r) == 1L)
      l <- lang()
      reason <- if (is.null(input$deadline_reason)) "" else trimws(input$deadline_reason)
      if (!isTRUE(input$deadline_confirm) || !nzchar(reason)) {
        status(tr(l, "Frist, Begr\u00fcndung und Best\u00e4tigung sind erforderlich.", "A deadline, a rationale and confirmation are required."))
        return()
      }
      moment <- read_moment(input$deadline_date, input$deadline_time, timezone())
      if (!is.null(moment$error)) {
        status(paste(tr(l, "Nicht ge\u00e4ndert:", "Not changed:"), moment_error_text(moment$error, l)))
        return()
      }
      tryCatch(
        {
          call("change_round_deadline", r$id, moment$value, r$instrument_hash, reason, command_id())
          shiny::updateCheckboxInput(session, "deadline_confirm", value = FALSE)
          forget("deadline_reason")
          review(NULL)
          refresh()
          touch()
          status(tr(l, "Frist ge\u00e4ndert.", "Deadline changed."))
        },
        error = function(e) {
          path <- if (inherits(e, "delphyr_error")) e$path else ""
          status(switch(path,
            deadline.offset = ,
            deadline.format = refusal(tr(l, "Nicht ge\u00e4ndert: Datum oder Uhrzeit der Frist sind ung\u00fcltig.", "Not changed: the date or time of the deadline is not valid."), e),
            deadline.past = refusal(tr(l, "Nicht ge\u00e4ndert: Die Frist muss in der Zukunft liegen.", "Not changed: the deadline must lie in the future."), e),
            deadline.earlier = refusal(tr(l, "Nicht ge\u00e4ndert: Die Frist einer offenen Runde kann nur auf einen sp\u00e4teren Zeitpunkt verlegt werden.", "Not changed: the deadline of an open round can only be moved to a later time."), e),
            round.state = refusal(tr(l, "Nicht ge\u00e4ndert: Die Frist einer geschlossenen Runde kann nicht ge\u00e4ndert werden.", "Not changed: the deadline of a closed round cannot be changed."), e),
            safe_error(e, l)
          ))
        }
      )
    })
    operations_server("operations", study, selected, lang, call, services, function() {
      refresh()
      touch()
    }, allowed, changed = changed, capabilities = capabilities, rounds = rounds, zone = timezone, study_state = study_state)
    shiny::observeEvent(input$transition, {
      shiny::req(allowed(), can("manage"), input$round, input$target)
      l <- lang()
      if (!isTRUE(input$confirm) || is.null(input$reason) || !nzchar(trimws(input$reason))) {
        status(tr(l, "Begr\u00fcndung und Best\u00e4tigung sind erforderlich.", "A rationale and confirmation are required."))
        return()
      }
      r <- selected()
      shiny::req(nrow(r) == 1)
      hash <- r$instrument_hash
      if (reviewable && identical(input$target, "approved")) {
        # Approval binds the exact instrument that was displayed for review.
        shown <- review()
        if (is.null(shown) || !identical(shown$id, r$id)) {
          status(tr(l, "Vor der Freigabe das Instrument dieser Runde anzeigen und pr\u00fcfen.", "Display and review this round\u2019s instrument before approving it."))
          return()
        }
        hash <- shown$instrument$round$instrument_hash
      }
      tryCatch(
        {
          call("transition_round", r$id, input$target, hash, trimws(input$reason), command_id())
          review(NULL)
          shiny::updateCheckboxInput(session, "confirm", value = FALSE)
          forget("reason")
          refresh()
          touch()
          status(tr(l, "Status\u00e4nderung best\u00e4tigt.", "State change confirmed."))
        },
        error = function(e) {
          if (inherits(e, "DEL_VALIDATION") && is.character(e$path) && startsWith(e$path, "round.readiness:")) {
            tryCatch(load_review(r$id), error = function(e2) NULL)
            status(refusal(tr(l, "Die Runde ist noch nicht bereit. Die Befunde stehen in der Bereitschaftspr\u00fcfung.", "The round is not ready yet. The readiness review lists the findings."), e))
          } else if (inherits(e, "DEL_CONFLICT")) {
            status(refusal(tr(l, "Dieser \u00dcbergang ist im aktuellen Status der Runde nicht m\u00f6glich, oder die Runde wurde inzwischen ge\u00e4ndert.", "This transition is not possible in the round\u2019s current state, or the round has changed in the meantime."), e))
          } else {
            status(safe_error(e, l))
          }
        }
      )
    })
    # Completing ends the whole study; it has its own rationale and confirmation.
    output$completion <- shiny::renderUI({
      shiny::req(allowed(), can("manage"), "complete_study" %in% names(services))
      r <- rounds()
      shiny::req(nrow(r) > 0)
      l <- lang()
      ns <- session$ns
      live <- r[r$state != "cancelled", , drop = FALSE]
      last <- if (nrow(live)) live$state[which.max(live$number)] else NA_character_
      shiny::tagList(
        shiny::tags$hr(),
        shiny::tags$h3(tr(l, "Studie abschlie\u00dfen", "Complete the study")),
        if (identical(study_state(), "completed")) {
          shiny::tags$p(class = "del-note", tr(l, "Die Studie ist abgeschlossen.", "The study is completed."))
        } else if (!identical(last, "finalized")) {
          shiny::tags$p(class = "del-note", tr(l, "Die Studie kann abgeschlossen werden, sobald ihre letzte Runde abgeschlossen ist und das Studienteam f\u00fcr jedes Item dieser Runde eine Entscheidung festgehalten hat.", "The study can be completed once its last round is finalized and the study team has recorded a decision for every item of that round."))
        } else {
          shiny::tagList(
            shiny::tags$p(class = "del-note", tr(l, "Der Abschluss beendet die gesamte Studie und kann nicht r\u00fcckg\u00e4ngig gemacht werden. Nennen Sie in der Begr\u00fcndung auch fortbestehenden Dissens.", "Completing ends the whole study and cannot be undone. Mention any persistent dissent in the rationale.")),
            shiny::textAreaInput(ns("complete_reason"), tr(l, "Begr\u00fcndung des Studienabschlusses", "Rationale for completing the study"), value = field("complete_reason"), width = "100%"),
            shiny::checkboxInput(ns("complete_confirm"), tr(l, "Ich schlie\u00dfe die gesamte Studie endg\u00fcltig ab", "I complete the whole study for good"), FALSE),
            shiny::tags$div(class = "del-actions", shiny::actionButton(ns("complete"), tr(l, "Studie abschlie\u00dfen", "Complete study"), class = "btn-outline-danger"))
          )
        }
      )
    })
    shiny::outputOptions(output, "completion", suspendWhenHidden = FALSE)
    shiny::observeEvent(input$complete, {
      shiny::req(allowed(), can("manage"))
      l <- lang()
      reason <- if (is.null(input$complete_reason)) "" else trimws(input$complete_reason)
      if (!isTRUE(input$complete_confirm) || !nzchar(reason)) {
        completion_status(tr(l, "Begr\u00fcndung und Best\u00e4tigung sind erforderlich.", "A rationale and confirmation are required."))
        return()
      }
      tryCatch(
        {
          call("complete_study", study(), reason, command_id())
          shiny::updateCheckboxInput(session, "complete_confirm", value = FALSE)
          forget("complete_reason")
          refresh()
          touch()
          completion_status(tr(l, "Studie abgeschlossen.", "Study completed."))
        },
        error = function(e) {
          path <- if (inherits(e, "delphyr_error")) e$path else ""
          completion_status(switch(path,
            study.state = refusal(tr(l, "Nicht abgeschlossen: Die Studie ist nicht aktiv; vielleicht ist sie bereits abgeschlossen.", "Not completed: the study is not active; it may already be completed."), e),
            completion.round = refusal(tr(l, "Nicht abgeschlossen: Zuerst muss die letzte Runde abgeschlossen werden.", "Not completed: the last round must be finalized first."), e),
            completion.decisions = refusal(tr(l, "Nicht abgeschlossen: Jedes Item der letzten Runde braucht eine Entscheidung des Studienteams.", "Not completed: every item of the last round needs a decision of the study team."), e),
            safe_error(e, l)
          ))
        }
      )
    })
    shiny::observeEvent(input$background_load, {
      shiny::req(allowed(), can("manage"))
      tryCatch(background(call("get_operations_status", study())), error = function(e) status(safe_error(e, lang())))
    })
    output$background_jobs <- shiny::renderTable({
      x <- background()
      shiny::req(x, nrow(x$jobs) > 0)
      j <- x$jobs
      l <- lang()
      kind <- ifelse(j$type == "analysis", tr(l, "Analyse", "Analysis"), paste(tr(l, "Export:", "Export:"), job_profile_label(j$profile, l)))
      # Only work that is still waiting has a waiting time.
      waiting <- ifelse(j$state %in% c("queued", "retry_wait"), format_wait(j$oldest_waiting_seconds, l), no_value)
      out <- data.frame(kind, operation_state_label(j$state, l), j$n, waiting, ifelse(is.na(j$error_codes) | !nzchar(j$error_codes), no_value, j$error_codes), stringsAsFactors = FALSE)
      names(out) <- tr(l, c("Auftrag", "Status", "Anzahl", "L\u00e4ngste Wartezeit", "Fehlercode"), c("Operation", "State", "Count", "Longest waiting time", "Error code"))
      out
    })
    output$background_messages <- shiny::renderTable({
      x <- background()
      shiny::req(x, nrow(x$messages) > 0)
      m <- x$messages
      l <- lang()
      waiting <- ifelse(m$state == "queued", format_wait(m$oldest_waiting_seconds, l), no_value)
      out <- data.frame(delivery_label(m$state, l), m$n, waiting, stringsAsFactors = FALSE)
      names(out) <- tr(l, c("Stand der Mitteilungen", "Anzahl", "L\u00e4ngste Wartezeit"), c("Message state", "Count", "Longest waiting time"))
      out
    })
    shiny::observeEvent(input$review, {
      shiny::req(allowed(), can("manage"), reviewable, input$round)
      tryCatch(
        {
          load_review(input$round)
          status("")
        },
        error = function(e) status(safe_error(e, lang()))
      )
    })
    shiny::observeEvent(input$enroll, {
      shiny::req(allowed(), can("manage"), input$round)
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
        shiny::tags$p(paste(tr(l, "Abgabe bis:", "Submit by:"), format_moment(i$round$deadline, zone, l), "\u00b7", tr(l, "Protokollversion", "Protocol version"), i$protocol$version)),
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
      out <- data.frame(ifelse(f$severity == "error", tr(lang(), "Blockiert", "Blocking"), tr(lang(), "Hinweis", "Note")), readiness_label(f$code, lang()), readiness_detail(f$code, f$details, lang()), stringsAsFactors = FALSE)
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
      out <- data.frame(round_state_label(e$target_state, lang()), e$reason, format_moment(e$occurred_at, timezone(), lang()), stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("\u00dcbergang", "Begr\u00fcndung", "Zeitpunkt"), c("Transition", "Rationale", "Time"))
      out
    })
  })
}

# Round states as shown to study staff. A candidate that was never opened is
# described as withdrawn rather than with the generic job wording.
round_state_label <- function(state, lang) {
  extra <- tr(lang, c(cancelled = "Zur\u00fcckgezogen (nie ge\u00f6ffnet)", deadline_changed = "Frist ge\u00e4ndert"), c(cancelled = "Withdrawn (never opened)", deadline_changed = "Deadline changed"))
  out <- state_label(state, lang)
  out[state %in% names(extra)] <- extra[state[state %in% names(extra)]]
  unname(out)
}
round_choice_label <- function(rounds, lang) {
  if (!nrow(rounds)) {
    return(character())
  }
  paste(tr(lang, "Runde", "Round"), rounds$number, "\u00b7", round_state_label(rounds$state, lang))
}
# The transitions transition_round() admits, by the state a round leaves; the
# forward step comes first.
round_targets <- function(state) {
  from <- list(review = "draft", approved = "review", open = "approved", closed = "open", finalized = c("analysed", "released"), cancelled = c("draft", "review", "approved"))
  names(from)[vapply(from, function(s) length(state) == 1L && isTRUE(state %in% s), logical(1))]
}
round_next_step <- function(state, lang) {
  steps <- tr(
    lang,
    c(closed = "Die Runde ist geschlossen. Frieren Sie sie unter Auswertung und Folgerunde ein, um sie auszuwerten.", frozen = "Die Runde ist eingefroren. Beauftragen Sie unter Auswertung und Folgerunde ihre Analyse.", finalized = "Die Runde ist abgeschlossen; ihr Status \u00e4ndert sich nicht mehr.", cancelled = "Die Runde wurde zur\u00fcckgezogen; ihr Status \u00e4ndert sich nicht mehr."),
    c(closed = "The round is closed. Freeze it under Analysis and subsequent round to analyse it.", frozen = "The round is frozen. Request its analysis under Analysis and subsequent round.", finalized = "The round is finalized; its state no longer changes.", cancelled = "The round was withdrawn; its state no longer changes.")
  )
  if (length(state) == 1L && isTRUE(state %in% names(steps))) unname(steps[state]) else tr(lang, "F\u00fcr diese Runde ist keine weitere Status\u00e4nderung m\u00f6glich.", "No further state change is possible for this round.")
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
# The detail of a readiness finding in words. The service writes it in a
# fixed technical form; codes it does not explain stay as they are.
readiness_detail <- function(code, details, lang) {
  details <- ifelse(is.na(details), "", as.character(details))
  out <- details
  for (i in seq_along(code)) {
    d <- details[i]
    numbers <- regmatches(d, gregexpr("[0-9]+", d))[[1]]
    out[i] <- switch(code[i],
      protocol_superseded = if (length(numbers) == 2L) sprintf(tr(lang, "Runde: Fassung %s; aktuell: Fassung %s", "Round: version %s; current: version %s"), numbers[1], numbers[2]) else d,
      group_below_minimum = {
        parts <- regmatches(d, regexec("^(.+): ([0-9]+) < ([0-9]+)$", d))[[1]]
        if (length(parts) == 4L) paste0(humanize_code(parts[2]), ": ", sprintf(tr(lang, "%s aufgenommen, Mindest-n %s", "%s enrolled, minimum valid n %s"), parts[3], parts[4])) else d
      },
      panel_below_minimum = if (length(numbers) == 2L) sprintf(tr(lang, "%s aufgenommen, Mindest-n %s", "%s enrolled, minimum valid n %s"), numbers[1], numbers[2]) else d,
      panelists_not_enrolled = if (length(numbers) == 1L) sprintf(tr(lang, "%s noch nicht aufgenommen", "%s not yet enrolled"), numbers[1]) else d,
      translation_missing = ,
      consent_language = paste(language_name(strsplit(d, ",", fixed = TRUE)[[1]], lang), collapse = ", "),
      d
    )
  }
  out[!nzchar(out)] <- no_value
  out
}
# The profile of an export in words; the round export has its own profile.
job_profile_label <- function(profile, lang) {
  out <- export_profile_label(profile, lang)
  out[profile %in% "research_round"] <- tr(lang, "Rundendaten (pseudonymisiert)", "Round data (pseudonymized)")
  out[is.na(out)] <- humanize_code(profile[is.na(out)])
  out
}
# A waiting time in seconds, minutes or hours.
format_wait <- function(seconds, lang) {
  s <- suppressWarnings(as.numeric(seconds))
  out <- ifelse(s < 120, paste(format_number(s, lang, 0L), "s"), ifelse(s < 7200, paste(format_number(s / 60, lang, 0L), "min"), paste(format_number(s / 3600, lang, 0L), "h")))
  out[is.na(s)] <- no_value
  out
}

# A background operation that did not succeed quotes its ID; the worker's
# entry in the technical log carries the same reference.
operation_status <- function(operation, lang) {
  text <- paste(tr(lang, "Auftrag:", "Operation:"), operation_state_label(operation$state, lang))
  if (operation$state %in% c("retry_wait", "dead_letter")) paste(text, reference_text(operation$id, lang)) else text
}
operation_state_label <- function(state, lang) {
  labels <- tr(lang, c(queued = "Eingereiht", running = "In Bearbeitung", succeeded = "Erfolgreich", retry_wait = "Wartet auf Wiederholung", dead_letter = "Endg\u00fcltig fehlgeschlagen"), c(queued = "Queued", running = "Processing", succeeded = "Succeeded", retry_wait = "Waiting to retry", dead_letter = "Permanently failed"))
  unname(ifelse(state %in% names(labels), labels[state], state))
}
