operations_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::uiOutput(ns("body"))
}
# `capabilities`, `rounds`, `zone` and `study_state` are reactives of the
# hosting section; without them every control is offered and times are shown
# in the protocol's zone.
operations_server <- function(id, study, round, lang, call, services, refresh, allowed, changed = NULL,
                              capabilities = function() c("manage", "analyse", "export"), rounds = NULL, zone = NULL, study_state = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    # A text cleared after a confirmed action is not restored from the input
    # value the browser has not replaced yet.
    stale <- new.env(parent = emptyenv())
    field <- function(name, default = "") {
      value <- shiny::isolate(input[[name]])
      if (is.null(value) || identical(value, stale[[name]])) default else value
    }
    forget <- function(...) {
      for (name in c(...)) {
        stale[[name]] <- shiny::isolate(input[[name]])
        shiny::updateTextAreaInput(session, name, value = "")
      }
    }
    can <- function(...) any(c(...) %in% capabilities())
    # The analysis on screen, with its id and the round it belongs to.
    analysis <- shiny::reactiveVal(NULL)
    analysis_job <- shiny::reactiveVal(NULL)
    export_job <- shiny::reactiveVal(NULL)
    artifact <- shiny::reactiveVal(NULL)
    feedback <- shiny::reactiveVal(NULL)
    preview <- shiny::reactiveVal(NULL)
    setup <- shiny::reactiveVal(NULL)
    items <- shiny::reactiveVal(NULL)
    decisions <- shiny::reactiveVal(data.frame())
    editorial_versions <- shiny::reactiveVal(data.frame())
    released_feedback <- shiny::reactiveVal(data.frame())
    correction <- shiny::reactiveVal(NULL)
    # Whether released feedback is assigned to the selected round, and whether
    # the protocol frozen with the selected round has free-text questions; NA
    # where it could not be read.
    assignment <- shiny::reactiveVal(NULL)
    export_check <- shiny::reactiveVal(NULL)
    composing <- "list_released_edits" %in% names(services)
    correcting <- all(c("list_released_edits", "list_released_feedback", "release_feedback_correction") %in% names(services))
    listing <- "list_released_feedback" %in% names(services)
    load_editorial <- function() {
      if (composing) editorial_versions(call("list_released_edits", study()))
      if (listing) released_feedback(call("list_released_feedback", study()))
    }
    deciding <- all(c("record_item_decision", "list_item_decisions") %in% names(services))
    status <- shiny::reactiveVal("")
    needed <- c("freeze_round", "request_analysis", "get_operation", "get_analysis", "create_feedback", "get_feedback_candidate", "release_feedback", "assign_feedback", "request_export", "download_artifact", "get_study_setup", "prepare_round")
    ready <- all(needed %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    # Scales without statistics; the feedback lists their dimensions only as text.
    free_scales <- function() {
      s <- shiny::isolate(setup())$protocol$instrument$scales
      names(s)[vapply(s, function(z) identical(z$type, "free_text"), logical(1))]
    }
    study_zone <- function() {
      z <- if (is.function(zone)) zone() else NULL
      if (!is.character(z) || length(z) != 1L || is.na(z) || !nzchar(z)) z <- setup()$protocol$study$timezone
      if (!is.character(z) || length(z) != 1L || is.na(z) || !nzchar(z)) "UTC" else z
    }
    shiny::observeEvent(study(), {
      analysis(NULL)
      analysis_job(NULL)
      export_job(NULL)
      artifact(NULL)
      feedback(NULL)
      preview(NULL)
      items(NULL)
      setup(NULL)
      decisions(data.frame())
      editorial_versions(data.frame())
      released_feedback(data.frame())
      correction(NULL)
      assignment(NULL)
      export_check(NULL)
      status("")
      if (ready && allowed()) {
        attempt(load_editorial)
        if (can("manage")) attempt(function() setup(call("get_study_setup", study())))
        if (deciding) attempt(function() decisions(call("list_item_decisions", study())))
      }
    })
    # Study information published or a protocol amended in another section.
    if (!is.null(changed)) {
      shiny::observeEvent(changed(),
        {
          if (ready && allowed() && can("manage")) attempt(function() setup(call("get_study_setup", study())))
        },
        ignoreInit = TRUE
      )
    }
    # The selected round as far as the controls depend on it. Another round
    # discards the analysis, drafts and corrections shown for the previous one.
    key <- shiny::reactiveVal(NULL)
    shiny::observe({
      r <- round()
      k <- if (nrow(r) == 1L) round_key(r) else NULL
      if (!identical(k$id, shiny::isolate(key())$id)) {
        analysis(NULL)
        feedback(NULL)
        preview(NULL)
        correction(NULL)
      }
      key(k)
    })
    selected <- function() {
      r <- round()
      shiny::req(nrow(r) == 1)
      r
    }
    # A round receives released feedback once; the readiness review of a later
    # round reports whether it is still missing.
    assessing <- "get_round_readiness" %in% names(services)
    read_assignment <- function(k) {
      if (!assessing || is.null(k) || !can("manage") || !isTRUE(k$state %in% c("draft", "review", "approved")) || !isTRUE(k$number > 1)) {
        return(NULL)
      }
      issues <- call("get_round_readiness", k$id)$issues
      list(round_id = k$id, assigned = if (is.data.frame(issues) && "code" %in% names(issues)) !"feedback_unassigned" %in% issues$code else NA)
    }
    # The round export does not cover free text. The protocol frozen with the
    # round decides, not the current one: a flag of the listed round where the
    # service provides it, otherwise the round's instrument, which study
    # leadership reads.
    frozen_free_text <- function(k) {
      if (is.logical(k$free_text) && !is.na(k$free_text)) {
        return(k$free_text)
      }
      if (!can("manage") || !"get_round_instrument" %in% names(services)) {
        return(NA)
      }
      scales <- call("get_round_instrument", k$id)$protocol$config$instrument$scales
      if (!length(scales)) {
        return(NA)
      }
      any(vapply(scales, function(s) identical(s$type, "free_text"), logical(1)))
    }
    shiny::observe({
      k <- key()
      manage <- can("manage")
      export <- can("export")
      shiny::isolate({
        if (is.null(k) || !identical(assignment()$round_id, k$id)) {
          assignment(NULL)
          attempt(function() assignment(read_assignment(k)))
        }
        wanted <- if (!is.null(k) && export && has_value(k$snapshot_id)) list(snapshot_id = k$snapshot_id, manage = manage) else NULL
        known <- export_check()
        if (!identical(if (is.null(known)) NULL else known[c("snapshot_id", "manage")], wanted)) {
          export_check(NULL)
          if (!is.null(wanted)) {
            free_text <- NA
            attempt(function() free_text <<- frozen_free_text(k))
            export_check(c(wanted, list(free_text = free_text)))
          }
        }
      })
    })
    output$body <- shiny::renderUI({
      shiny::req(ready, allowed())
      l <- lang()
      ns <- session$ns
      k <- key()
      manage <- can("manage")
      analyse <- can("analyse")
      state <- if (is.null(k)) NA_character_ else k$state
      analysed <- !is.null(k) && has_value(k$analysis_id)
      p <- released_feedback()
      released <- !is.null(k) && nrow(p) > 0 && isTRUE(any(p$round_number == k$number & is.na(p$replacement_id), na.rm = TRUE))
      shiny::tagList(
        shiny::tags$hr(),
        shiny::tags$h3(tr(l, "Auswertung und Folgerunde", "Analysis and subsequent round")),
        shiny::tags$p(class = "del-note", tr(l, "Diese Aktionen beziehen sich auf die oben ausgew\u00e4hlte Runde. Analysen und Exporte werden im Hintergrund vorbereitet; Auftrag pr\u00fcfen zeigt ihren Stand.", "These actions use the round selected above. Analyses and exports are prepared in the background; Check operation shows their progress.")),
        if (!is.null(k)) shiny::uiOutput(ns("analysis_actions")),
        shiny::uiOutput(ns("analysis")),
        if (deciding && analysed && (manage || analyse)) {
          shiny::tags$details(
            shiny::tags$summary(tr(l, "Itementscheidungen", "Item decisions")),
            shiny::tags$p(class = "del-note", tr(l, "Das Regelergebnis der Analyse ist keine Entscheidung. Halten Sie f\u00fcr jedes Item die Entscheidung des Studienteams mit Begr\u00fcndung fest; fehlender Konsens ist ein zul\u00e4ssiges Ergebnis.", "The rule outcome of the analysis is not a decision. Record the study team\u2019s decision for each item with its rationale; no consensus is a legitimate result.")),
            shiny::uiOutput(ns("decision_form")),
            shiny::tableOutput(ns("decisions"))
          )
        },
        if (manage && analyse && identical(state, "analysed")) {
          shiny::tags$details(
            shiny::tags$summary(tr(l, "Feedback pr\u00fcfen und freigeben", "Review and release feedback")),
            if (composing) {
              shiny::tagList(
                shiny::tags$p(class = "del-note", tr(l, "Qualitative Inhalte gelangen nur als Fassung ins Feedback, die eine andere Person freigegeben hat. Zusammenfassungen werden als solche gekennzeichnet, nie als Zitat.", "Qualitative content enters feedback only as a version that another person has released. Summaries are labelled as such, never as quotations.")),
                shiny::uiOutput(ns("released_choice"))
              )
            },
            shiny::tags$div(
              class = "del-actions",
              if (composing) shiny::actionButton(ns("released_refresh"), tr(l, "Freigegebene Fassungen aktualisieren", "Refresh released versions")),
              shiny::actionButton(ns("draft"), tr(l, "Feedback erstellen", "Create feedback"))
            ),
            shiny::uiOutput(ns("preview"))
          )
        },
        # Only the round that released the feedback corrects it; a withdrawn
        # round of the same number has none.
        if (correcting && manage && analyse && released && analysed && isTRUE(state %in% c("released", "finalized"))) {
          shiny::tags$details(
            shiny::tags$summary(tr(l, "Freigegebenes Feedback korrigieren", "Correct released feedback")),
            shiny::tags$p(class = "del-note", tr(l, "Freigegebenes Feedback wird nie ge\u00e4ndert. Eine Korrektur gibt eine neue Fassung frei, die sp\u00e4tere Ansichten ersetzt; fr\u00fchere Anzeigen bleiben der alten Fassung zugeordnet. Beurteilen Sie die Auswirkung auf bereits abgegebene Bewertungen.", "Released feedback is never changed. A correction releases a new version that replaces it for later views; earlier displays remain attributed to the old version. Assess the effect on ratings already given.")),
            shiny::tableOutput(ns("published")),
            shiny::uiOutput(ns("correction_choice")),
            # The feedback group with the same control is never shown at the same time.
            shiny::tags$div(
              class = "del-actions",
              shiny::actionButton(ns("released_refresh"), tr(l, "Freigegebene Fassungen aktualisieren", "Refresh released versions")),
              shiny::actionButton(ns("correction_draft"), tr(l, "Korrigierte Fassung erstellen", "Create corrected version"))
            ),
            shiny::uiOutput(ns("correction_preview")),
            shiny::textAreaInput(ns("correction_reason"), tr(l, "Begr\u00fcndung der Korrektur (intern)", "Rationale for the correction (internal)"), value = field("correction_reason"), width = "100%"),
            shiny::textAreaInput(ns("correction_impact"), tr(l, "Auswirkung auf bereits abgegebene Bewertungen (intern)", "Effect on ratings already given (internal)"), value = field("correction_impact"), width = "100%"),
            shiny::textAreaInput(ns("correction_note"), tr(l, "Hinweis f\u00fcr Teilnehmende", "Note for participants"), value = field("correction_note"), width = "100%"),
            shiny::checkboxInput(ns("correction_confirm"), tr(l, "Ich habe die korrigierte Fassung und alle drei Texte gepr\u00fcft", "I reviewed the corrected version and all three texts"), FALSE),
            shiny::tags$div(class = "del-actions", shiny::actionButton(ns("correction_release"), tr(l, "Korrektur freigeben", "Release correction")))
          )
        },
        if (manage && !is.null(k) && isTRUE(state %in% c("draft", "review", "approved")) && isTRUE(k$number > 1)) {
          shiny::tags$details(
            shiny::tags$summary(tr(l, "Feedback f\u00fcr diese Runde", "Feedback for this round")),
            shiny::uiOutput(ns("assign_choice"))
          )
        },
        shiny::uiOutput(ns("prepare_group")),
        if (can("export") && !is.null(k) && has_value(k$snapshot_id)) {
          shiny::tags$details(
            shiny::tags$summary(sprintf(tr(l, "Daten der Runde %s exportieren", "Export the data of round %s"), k$number)),
            shiny::uiOutput(ns("export_group"))
          )
        },
        status_ui(ns("status"))
      )
    })
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    output$analysis_actions <- shiny::renderUI({
      k <- key()
      shiny::req(k)
      l <- lang()
      ns <- session$ns
      manage <- can("manage")
      analyse <- can("analyse")
      frozen <- has_value(k$snapshot_id)
      analysed <- has_value(k$analysis_id)
      # A withdrawn round was never opened and is not analysed; the round
      # list says so. Requesting an analysis moves the round on, so it needs
      # study leadership as well as the analysis right.
      withdrawn <- identical(k$state, "cancelled")
      buttons <- list(
        if (manage && identical(k$state, "closed")) shiny::actionButton(ns("freeze"), tr(l, "Runde einfrieren", "Freeze round")),
        if (manage && analyse && frozen && !analysed) shiny::actionButton(ns("analyse"), tr(l, "Analyse beauftragen", "Request analysis")),
        if (manage && analyse && !is.null(analysis_job())) shiny::actionButton(ns("poll"), tr(l, "Auftrag pr\u00fcfen", "Check operation")),
        if (analyse && analysed) shiny::actionButton(ns("read"), tr(l, "Analyse anzeigen", "View analysis"))
      )
      buttons <- Filter(Negate(is.null), buttons)
      note <- if (withdrawn) {
        NULL
      } else if (!analyse) {
        tr(l, "Analysen, Itementscheidungen und Feedbackentw\u00fcrfe erfordern das Recht zur Analyse.", "Analyses, item decisions and feedback drafts need the right to analyse.")
      } else if (!frozen) {
        tr(l, "Eine Analyse ist m\u00f6glich, sobald die Runde geschlossen und eingefroren ist.", "An analysis is possible once the round is closed and frozen.")
      } else if (!analysed && !manage) {
        tr(l, "Die Analyse dieser Runde beauftragt die Studienleitung.", "The study lead requests the analysis of this round.")
      }
      shiny::tagList(
        if (length(buttons)) shiny::tags$div(class = "del-actions", buttons),
        if (!is.null(note)) shiny::tags$p(class = "del-note", note)
      )
    })
    shiny::observeEvent(input$freeze, attempt(function() {
      shiny::req(can("manage"))
      r <- selected()
      call("freeze_round", r$id, command_id())
      refresh()
      status(tr(lang(), "Snapshot best\u00e4tigt.", "Snapshot confirmed."))
    }))
    shiny::observeEvent(input$analyse, attempt(function() {
      shiny::req(can("manage"), can("analyse"))
      r <- selected()
      shiny::req(has_value(r$snapshot_id))
      job <- call("request_analysis", r$snapshot_id, command_id())
      analysis_job(list(id = job$id, round_id = r$id, number = round_key(r)$number))
      status(tr(lang(), "Analyse eingereiht. Auftrag pr\u00fcfen.", "Analysis queued. Check the operation."))
    }))
    # The statement wording comes from the round's instrument where the
    # account may read it.
    show_analysis <- function(id, round_id, number) {
      a <- call("get_analysis", id)
      wording <- if (can("manage") && "get_round_instrument" %in% names(services)) tryCatch(call("get_round_instrument", round_id)$items, error = function(e) NULL) else NULL
      analysis(list(id = id, round_id = round_id, number = number, data = a, items = wording, language = shiny::isolate(setup())$protocol$study$default_language))
    }
    shiny::observeEvent(input$poll, attempt(function() {
      job <- analysis_job()
      shiny::req(job)
      r <- call("get_operation", job$id)
      status(operation_status(r, lang()))
      if (identical(r$state, "succeeded")) {
        analysis_job(NULL)
        show_analysis(r$result_ref, job$round_id, job$number)
        refresh()
      } else if (identical(r$state, "dead_letter")) {
        analysis_job(NULL)
      }
    }))
    shiny::observeEvent(input$read, attempt(function() {
      r <- selected()
      shiny::req(has_value(r$analysis_id))
      show_analysis(r$analysis_id, r$id, round_key(r)$number)
    }))
    output$analysis <- shiny::renderUI({
      a <- analysis()
      shiny::req(a)
      analysis_view(a, lang())
    })
    # Decisions are recorded against the analysis on screen, and only while
    # it is the analysis of the selected round.
    output$decision_form <- shiny::renderUI({
      l <- lang()
      ns <- session$ns
      if (!can("manage")) {
        return(shiny::tags$p(class = "del-note", tr(l, "Itementscheidungen h\u00e4lt die Studienleitung fest.", "Item decisions are recorded by the study lead.")))
      }
      # Without the analysis right the analysis cannot be shown; the recorded
      # decisions remain readable below.
      if (!can("analyse")) {
        return(NULL)
      }
      a <- analysis()
      k <- key()
      if (is.null(a) || is.null(k) || !identical(a$round_id, k$id)) {
        return(shiny::tags$p(class = "del-note", tr(l, "Zuerst die Analyse der ausgew\u00e4hlten Runde anzeigen.", "View the analysis of the selected round first.")))
      }
      codes <- unique(as.character(a$data$decisions$item_code))
      shiny::tagList(
        shiny::selectInput(ns("decision_code"), tr(l, "Item der angezeigten Analyse", "Item of the displayed analysis"), list_choices(codes, statement_label(codes, a$items, l, a$language)), selected = shiny::isolate(input$decision_code), width = "100%"),
        shiny::selectInput(ns("disposition"), tr(l, "Entscheidung des Studienteams", "Study team\u2019s decision"), stats::setNames(decision_dispositions(), disposition_label(decision_dispositions(), l)), selected = field("disposition", "rerate")),
        shiny::textAreaInput(ns("decision_reason"), tr(l, "Begr\u00fcndung der Itementscheidung", "Rationale for the item decision"), value = field("decision_reason"), width = "100%"),
        shiny::checkboxInput(ns("decision_confirm"), tr(l, "Ich habe Item, Analyse und Entscheidung gepr\u00fcft", "I reviewed the item, its analysis and the decision"), FALSE),
        shiny::tags$div(class = "del-actions", shiny::actionButton(ns("decide"), tr(l, "Itementscheidung speichern", "Save item decision")))
      )
    })
    output$decisions <- shiny::renderTable({
      d <- decisions()
      k <- key()
      shiny::req(nrow(d) > 0, k)
      d <- d[d$round_number == k$number, , drop = FALSE]
      shiny::req(nrow(d) > 0)
      l <- lang()
      a <- analysis()
      shown <- !is.null(a) && identical(a$round_id, k$id)
      out <- data.frame(statement_label(d$item_code, if (shown) a$items, l, if (shown) a$language), disposition_label(d$disposition, l), d$reason, format_moment(d$decided_at, study_zone(), l), stringsAsFactors = FALSE)
      names(out) <- tr(l, c("Item", "Entscheidung", "Begr\u00fcndung", "Festgehalten"), c("Item", "Decision", "Rationale", "Recorded"))
      out
    })
    shiny::observeEvent(input$decide, attempt(function() {
      shiny::req(deciding, can("manage"))
      r <- selected()
      a <- analysis()
      l <- lang()
      if (is.null(a) || !identical(a$round_id, r$id) || is.null(input$decision_code) || !input$decision_code %in% a$data$decisions$item_code) {
        status(tr(l, "Zuerst die Analyse der ausgew\u00e4hlten Runde anzeigen.", "View the analysis of the selected round first."))
        return()
      }
      reason <- if (is.null(input$decision_reason)) "" else trimws(input$decision_reason)
      if (!isTRUE(input$decision_confirm) || !nzchar(reason)) {
        status(tr(l, "Begr\u00fcndung und Best\u00e4tigung sind erforderlich.", "A rationale and confirmation are required."))
        return()
      }
      call("record_item_decision", a$id, input$decision_code, input$disposition, reason, command_id())
      decisions(call("list_item_decisions", study()))
      shiny::updateCheckboxInput(session, "decision_confirm", value = FALSE)
      forget("decision_reason")
      status(paste(tr(l, "Itementscheidung gespeichert:", "Item decision saved:"), input$decision_code))
    }))
    released_choices <- function() {
      x <- editorial_versions()
      if (!nrow(x)) {
        return(character())
      }
      label <- paste0(ifelse(x$kind == "summary", tr(lang(), "Zusammenfassung", "Summary"), tr(lang(), "Redigierter Beitrag", "Redacted contribution")), " \u00b7 ", x$source_ref, " \u00b7 ", truncate_text(x$text, 70L))
      stats::setNames(x$edit_id, label)
    }
    # Only versions offered now are sent. Where none is offered the list is not
    # shown, and the browser keeps a choice made in another study or round.
    offered_edits <- function(chosen) {
      x <- editorial_versions()
      ids <- if (is.data.frame(x) && "edit_id" %in% names(x)) as.character(x$edit_id) else character()
      sort(intersect(as.character(chosen), ids))
    }
    # A list of released editorial versions, or why there is none.
    editorial_choice <- function(id, label, selected) {
      l <- lang()
      choices <- released_choices()
      if (!length(choices)) {
        return(shiny::tags$p(class = "del-note", tr(l, "Es gibt noch keine freigegebene redaktionelle Fassung; Fassungen werden unter Redaktion freigegeben.", "No editorial version has been released yet; versions are released under Editorial review.")))
      }
      shiny::selectizeInput(session$ns(id), label, choices, selected = selected, multiple = TRUE, width = "100%", options = list(placeholder = tr(l, "Freigegebene Zusammenfassungen oder redigierte Beitr\u00e4ge w\u00e4hlen", "Choose released summaries or redacted contributions")))
    }
    output$released_choice <- shiny::renderUI({
      editorial_choice("released_edits", tr(lang(), "Redaktionelle Fassungen in diesem Feedback", "Editorial versions to include in this feedback"), shiny::isolate(input$released_edits))
    })
    output$correction_choice <- shiny::renderUI({
      p <- feedback_versions(released_feedback())
      k <- key()
      l <- lang()
      current <- if (nrow(p) && !is.null(k)) p[p$round_number == k$number & is.na(p$replacement_id), , drop = FALSE] else p[FALSE, , drop = FALSE]
      shiny::tagList(
        shiny::selectInput(session$ns("correction_target"), tr(l, "Zu ersetzendes Feedback der ausgew\u00e4hlten Runde", "Feedback of the selected round to replace"), list_choices(current$feedback_id, released_feedback_label(current, l, study_zone())), selected = shiny::isolate(input$correction_target), width = "100%"),
        editorial_choice("correction_edits", tr(l, "Redaktionelle Fassungen im korrigierten Feedback", "Editorial versions to include in the corrected feedback"), shiny::isolate(input$correction_edits))
      )
    })
    output$published <- shiny::renderTable({
      p <- feedback_versions(released_feedback())
      k <- key()
      shiny::req(nrow(p) > 0, k)
      p <- p[p$round_number == k$number, , drop = FALSE]
      shiny::req(nrow(p) > 0)
      p <- p[order(p$version), , drop = FALSE]
      l <- lang()
      out <- data.frame(
        feedback_version_label(p$version, l), format_moment(p$released, study_zone(), l),
        ifelse(is.na(p$replacement_id), tr(l, "G\u00fcltig", "Current"), tr(l, "Ersetzt", "Replaced")),
        ifelse(is.na(p$rationale), no_value, p$rationale), short_ref(p$hash, 12L),
        stringsAsFactors = FALSE
      )
      names(out) <- tr(l, c("Fassung", "Freigegeben", "Stand", "Begr\u00fcndung der Korrektur", "Pr\u00fcfsumme"), c("Version", "Released", "Status", "Rationale for the correction", "Checksum"))
      # Without any known release time the column would only hold dashes.
      if (all(is.na(p$released))) out <- out[, -2L, drop = FALSE]
      out
    })
    shiny::observeEvent(input$released_refresh, attempt(load_editorial))
    shiny::observeEvent(input$correction_draft, attempt(function() {
      shiny::req(correcting, can("manage"), can("analyse"))
      r <- selected()
      shiny::req(has_value(r$analysis_id), input$correction_target)
      f <- call("create_feedback", r$analysis_id, list(), command_id(), released_edits = offered_edits(input$correction_edits))
      correction(list(target = input$correction_target, feedback = f, preview = call("get_feedback_candidate", f$id), round_id = r$id))
      shiny::updateCheckboxInput(session, "correction_confirm", value = FALSE)
      status(tr(lang(), "Korrigierte Fassung zur Pr\u00fcfung erstellt.", "Corrected version created for review."))
    }))
    output$correction_preview <- shiny::renderUI({
      x <- correction()
      shiny::req(x)
      feedback_view(x$preview, wording(), lang(), free_scales(), wording_language())
    })
    shiny::observeEvent(input$correction_release, attempt(function() {
      x <- correction()
      shiny::req(correcting, can("manage"), can("analyse"), x)
      texts <- vapply(list(input$correction_reason, input$correction_impact, input$correction_note), function(v) if (is.null(v)) "" else trimws(v), character(1))
      if (!isTRUE(input$correction_confirm) || any(!nzchar(texts))) {
        status(tr(lang(), "Begr\u00fcndung, Auswirkung, Hinweis und Best\u00e4tigung sind erforderlich.", "Rationale, effect, note and confirmation are required."))
        return()
      }
      if (!identical(input$correction_target, x$target) || !identical(x$preview$hash, x$feedback$hash)) stop("Corrected version changed; create it again")
      call("release_feedback_correction", x$target, x$feedback$id, x$feedback$hash, texts[1], texts[2], texts[3], command_id())
      correction(NULL)
      load_editorial()
      shiny::updateCheckboxInput(session, "correction_confirm", value = FALSE)
      forget("correction_reason", "correction_impact", "correction_note")
      status(tr(lang(), "Korrektur freigegeben. Sp\u00e4tere Ansichten zeigen die korrigierte Fassung.", "Correction released. Later views show the corrected version."))
    }))
    # The wording of the selected round's statements, once its analysis is shown.
    wording <- function() {
      a <- analysis()
      k <- key()
      if (!is.null(a) && !is.null(k) && identical(a$round_id, k$id)) a$items else NULL
    }
    wording_language <- function() {
      a <- analysis()
      if (is.null(a)) NULL else a$language
    }
    shiny::observeEvent(input$draft, attempt(function() {
      shiny::req(can("manage"), can("analyse"))
      r <- selected()
      shiny::req(has_value(r$analysis_id))
      f <- if (composing) call("create_feedback", r$analysis_id, list(), command_id(), released_edits = offered_edits(input$released_edits)) else call("create_feedback", r$analysis_id, list(), command_id())
      feedback(f)
      preview(call("get_feedback_candidate", f$id))
      shiny::updateCheckboxInput(session, "reviewed", value = FALSE)
      status(tr(lang(), "Feedback zur Pr\u00fcfung erstellt.", "Feedback created for review."))
    }))
    # The candidate as participants will see it, with what releasing it needs.
    output$preview <- shiny::renderUI({
      x <- preview()
      shiny::req(x)
      l <- lang()
      ns <- session$ns
      shiny::tagList(
        feedback_view(x, wording(), l, free_scales(), wording_language()),
        shiny::checkboxInput(ns("reviewed"), tr(l, "Ich habe dieses Feedback gepr\u00fcft", "I reviewed this feedback"), FALSE),
        shiny::tags$div(class = "del-actions", shiny::actionButton(ns("release"), tr(l, "Feedback freigeben", "Release feedback"), class = "btn-primary"))
      )
    })
    shiny::observeEvent(input$release, attempt(function() {
      shiny::req(can("manage"), can("analyse"), feedback(), preview())
      if (!isTRUE(input$reviewed)) stop("review required")
      f <- feedback()
      if (!identical(preview()$hash, f$hash)) stop("preview hash mismatch")
      call("release_feedback", f$id, f$hash, command_id())
      feedback(NULL)
      preview(NULL)
      refresh()
      if (listing) load_editorial()
      status(tr(lang(), "Feedback freigegeben.", "Feedback released."))
    }))
    # Released feedback of an earlier round, current version only, read from
    # the service so that any session can assign it.
    assignable <- function(k) {
      p <- feedback_versions(released_feedback())
      p[is.na(p$replacement_id) & p$round_number < k$number, , drop = FALSE]
    }
    assigned_note <- function(l) tr(l, "Dieser Runde ist freigegebenes Feedback zugewiesen. Eine sp\u00e4tere Korrektur dieses Feedbacks erreicht die Teilnehmenden der Runde ohne neue Zuweisung.", "Released feedback is assigned to this round. A later correction of that feedback reaches the round\u2019s participants without a new assignment.")
    output$assign_choice <- shiny::renderUI({
      k <- key()
      shiny::req(k)
      l <- lang()
      a <- assignment()
      if (!is.null(a) && identical(a$round_id, k$id) && isTRUE(a$assigned)) {
        return(shiny::tags$p(class = "del-note", assigned_note(l)))
      }
      intro <- shiny::tags$p(class = "del-note", tr(l, "Die Teilnehmenden dieser Runde sehen das freigegebene Feedback einer fr\u00fcheren Runde, das ihr hier zugewiesen wird. Weisen Sie es vor der \u00d6ffnung zu.", "Participants of this round see the released feedback of an earlier round that is assigned to it here. Assign it before the round opens."))
      candidates <- assignable(k)
      if (!nrow(candidates)) {
        return(shiny::tagList(intro, shiny::tags$p(class = "del-note", tr(l, "Es gibt noch kein freigegebenes Feedback einer fr\u00fcheren Runde.", "No released feedback of an earlier round exists yet."))))
      }
      candidates <- candidates[order(candidates$round_number, decreasing = TRUE), , drop = FALSE]
      chosen <- shiny::isolate(input$assign_feedback)
      shiny::tagList(
        intro,
        shiny::selectInput(session$ns("assign_feedback"), tr(l, "Freigegebenes Feedback", "Released feedback"), stats::setNames(candidates$feedback_id, released_feedback_label(candidates, l, study_zone(), assigned = TRUE)), selected = if (length(chosen) == 1L && chosen %in% candidates$feedback_id) chosen else candidates$feedback_id[1], width = "100%"),
        shiny::tags$div(class = "del-actions", shiny::actionButton(session$ns("assign"), tr(l, "Feedback zuweisen", "Assign feedback")))
      )
    })
    shiny::observeEvent(input$assign, attempt(function() {
      shiny::req(can("manage"))
      r <- selected()
      k <- round_key(r)
      l <- lang()
      if (length(input$assign_feedback) != 1L || !input$assign_feedback %in% assignable(k)$feedback_id) {
        status(tr(l, "Zuerst freigegebenes Feedback w\u00e4hlen.", "Choose released feedback first."))
        return()
      }
      # Another session may have assigned feedback since this round was shown.
      before <- read_assignment(k)
      if (!is.null(before)) assignment(before)
      if (isTRUE(before$assigned)) {
        status(assigned_note(l))
        return()
      }
      call("assign_feedback", r$id, input$assign_feedback, command_id())
      after <- read_assignment(k)
      if (!is.null(after)) assignment(after)
      if (listing) load_editorial()
      # The service assigns the feedback to the members enrolled in the round.
      status(if (identical(after$assigned, FALSE)) {
        tr(l, "Kein Feedback zugewiesen: Die Runde hat noch keine aufgenommenen Panelmitglieder. Nehmen Sie sie zuerst auf.", "No feedback was assigned: the round has no enrolled panel members yet. Enroll them first.")
      } else {
        tr(l, "Feedback zugewiesen.", "Feedback assigned.")
      })
    }))
    # The latest round that was not withdrawn: its instrument is the usual
    # starting point of the next one.
    latest_round <- function() {
      x <- if (is.function(rounds)) rounds() else NULL
      if (!is.data.frame(x) || !nrow(x)) {
        return(NULL)
      }
      x <- x[x$state != "cancelled", , drop = FALSE]
      if (nrow(x)) x[which.max(x$number), , drop = FALSE] else NULL
    }
    output$prepare_group <- shiny::renderUI({
      shiny::req(ready, allowed(), can("manage"))
      if (is.function(study_state) && identical(study_state(), "completed")) {
        return(NULL)
      }
      l <- lang()
      ns <- session$ns
      x <- if (is.function(rounds)) rounds() else NULL
      if (is.data.frame(x) && nrow(x)) {
        live <- x[x$state != "cancelled", , drop = FALSE]
        busy <- live[!live$state %in% c("released", "finalized"), , drop = FALSE]
        if (nrow(busy)) {
          return(shiny::tags$p(class = "del-note", sprintf(tr(l, "Eine neue Runde kann vorbereitet werden, sobald das Feedback der Runde %s freigegeben ist.", "A new round can be prepared once the feedback of round %s has been released."), max(busy$number))))
        }
        limit <- shiny::isolate(setup())$protocol$stopping$max_rounds
        if (length(limit) == 1L && !is.na(limit) && nrow(live) >= limit) {
          return(shiny::tags$p(class = "del-note", sprintf(tr(l, "Das Protokoll erlaubt h\u00f6chstens %s Runden.", "The protocol allows at most %s rounds."), limit)))
        }
      }
      last <- latest_round()
      typed <- read_moment(field("deadline_date", NA), field("deadline_time"), shiny::isolate(study_zone()))
      shiny::tags$details(
        shiny::tags$summary(tr(l, "Neue Runde vorbereiten", "Prepare a new round")),
        shiny::uiOutput(ns("csv_guide")),
        if (!is.null(last) && "get_round_instrument" %in% names(services)) {
          shiny::tags$div(class = "del-actions", shiny::downloadButton(ns("template"), sprintf(tr(l, "Instrument der Runde %s herunterladen (CSV)", "Download the instrument of round %s (CSV)"), last$number)))
        },
        file_input(ns("csv"), tr(l, "Instrument (CSV, Protokollsprachen)", "Instrument (CSV, protocol languages)"), accept = ".csv", width = "100%", buttonLabel = tr(l, "Durchsuchen\u2026", "Browse\u2026"), placeholder = tr(l, "Keine Datei ausgew\u00e4hlt", "No file selected")),
        shiny::tags$div(class = "del-actions", shiny::actionButton(ns("validate"), tr(l, "Import pr\u00fcfen", "Validate import"))),
        shiny::uiOutput(ns("items")),
        shiny::uiOutput(ns("consents")),
        moment_input(ns("deadline"), tr(l, "Frist", "Deadline"), shiny::isolate(study_zone()), l, value = typed$value),
        shiny::tags$div(class = "del-actions", shiny::actionButton(ns("prepare"), tr(l, "Runde vorbereiten", "Prepare round"), class = "btn-primary"))
      )
    })
    output$csv_guide <- shiny::renderUI(instrument_guide(setup()$protocol, lang()))
    output$template <- shiny::downloadHandler(
      filename = function() {
        last <- latest_round()
        sprintf("instrument-round-%s.csv", if (is.null(last)) "" else last$number)
      },
      content = function(file) {
        last <- latest_round()
        shiny::req(last)
        x <- call("get_round_instrument", last$id)$items
        columns <- c("item_code", "item_version", "locale", "text", "dimension_code", "scale_code", "source_ref", "required", "display_order")
        utils::write.csv(x[, columns, drop = FALSE], file, row.names = FALSE, fileEncoding = "UTF-8")
      },
      contentType = "text/csv"
    )
    shiny::observeEvent(input$csv, items(NULL))
    shiny::observeEvent(input$validate, attempt(function() {
      shiny::req(can("manage"), input$csv)
      # The protocol and the published study information may have changed
      # since this section was opened; validate against the current state.
      setup(call("get_study_setup", study()))
      if (input$csv$size > 5e6) stop("file too large")
      x <- utils::read.csv(input$csv$datapath, stringsAsFactors = FALSE, fileEncoding = "UTF-8", check.names = FALSE)
      delphyr::validate_items(x, setup()$protocol)
      items(x)
      status(tr(lang(), "Import g\u00fcltig. Noch keine Runde angelegt.", "Import validated. No round created yet."))
    }))
    output$items <- shiny::renderUI({
      x <- items()
      shiny::req(x)
      l <- lang()
      shown <- utils::head(x, 20)
      rows <- lapply(seq_len(nrow(shown)), function(i) {
        list(shown$item_code[i], shown$item_version[i], language_name(shown$locale[i], l), humanize_code(shown$dimension_code[i]), shown$text[i], if (isTRUE(as.logical(shown$required[i]))) tr(l, "erforderlich", "required") else tr(l, "optional", "optional"))
      })
      header <- tr(l, c("Item", "Version", "Sprache", "Dimension", "Wortlaut", "Pflicht"), c("Item", "Version", "Language", "Dimension", "Wording", "Requirement"))
      display_table(header, rows, sprintf(tr(l, "Gepr\u00fcfte Zeilen: %s; die ersten 20 sind aufgef\u00fchrt", "Validated rows: %s; the first 20 are listed"), nrow(x)), wide_first = FALSE)
    })
    output$consents <- shiny::renderUI({
      shiny::req(setup())
      l <- lang()
      x <- setup()$consent_versions
      if (!nrow(x)) {
        return(shiny::tags$p(class = "del-status del-status--attention", tr(l, "Zuerst unter Einrichtung eine Studieninformation ver\u00f6ffentlichen.", "Publish the study information under Setup first.")))
      }
      # The newest version comes first in the reading of a person and is
      # preselected; a choice made stays while it is offered.
      chosen <- shiny::isolate(input$consent)
      shiny::tagList(
        shiny::selectInput(session$ns("consent"), tr(l, "Studieninformation", "Study information"), stats::setNames(rev(x$id), rev(consent_version_label(x, l, study_zone()))), selected = if (length(chosen) == 1L && chosen %in% x$id) chosen else x$id[nrow(x)], width = "100%"),
        shiny::uiOutput(session$ns("consent_text"))
      )
    })
    output$consent_text <- shiny::renderUI({
      x <- setup()$consent_versions
      shiny::req(is.data.frame(x), nrow(x) > 0)
      id <- if (length(input$consent) == 1L && input$consent %in% x$id) input$consent else x$id[nrow(x)]
      v <- x[x$id == id, , drop = FALSE]
      shiny::tags$blockquote(class = "del-consent", lang = v$locale, v$content)
    })
    shiny::observeEvent(input$prepare, attempt(function() {
      shiny::req(can("manage"))
      l <- lang()
      if (is.null(items())) {
        status(tr(l, "Zuerst eine Instrumentdatei pr\u00fcfen.", "Validate an instrument file first."))
        return()
      }
      if (is.null(input$consent) || !nzchar(input$consent)) {
        status(tr(l, "Zuerst unter Einrichtung eine Studieninformation ver\u00f6ffentlichen.", "Publish the study information under Setup first."))
        return()
      }
      moment <- read_moment(input$deadline_date, input$deadline_time, study_zone())
      if (!is.null(moment$error)) {
        status(paste(tr(l, "Keine Runde angelegt:", "No round created:"), moment_error_text(moment$error, l)))
        return()
      }
      tryCatch(
        {
          call("prepare_round", study(), items(), input$consent, moment$value, command_id())
          refresh()
          status(tr(l, "Rundenentwurf erstellt. Vor \u00d6ffnung pr\u00fcfen und freigeben.", "Round draft created. Review and approve before opening."))
        },
        error = function(e) {
          path <- if (inherits(e, "delphyr_error")) e$path else ""
          refused <- switch(path,
            deadline.past = tr(l, "Keine Runde angelegt: Die Frist muss in der Zukunft liegen.", "No round created: the deadline must lie in the future."),
            round.previous = tr(l, "Keine Runde angelegt: Zuerst muss das Feedback der laufenden Runde freigegeben werden.", "No round created: the feedback of the current round must be released first."),
            round.max = tr(l, "Keine Runde angelegt: Das Protokoll erlaubt keine weitere Runde.", "No round created: the protocol allows no further round."),
            items.version_content = tr(l, "Keine Runde angelegt: Ein Item beh\u00e4lt seine Versionsnummer, obwohl sich Wortlaut, Skala oder Quelle ge\u00e4ndert haben. Geben Sie ihm eine neue Version.", "No round created: an item keeps its version number although its wording, scale or source changed. Give it a new version."),
            NULL
          )
          status(if (is.null(refused)) safe_error(e, l) else paste(refused, reference_text(error_reference(e), l)))
        }
      )
    }))
    # The export of one round: what it holds, why it is requested, and the
    # download once it is ready.
    output$export_group <- shiny::renderUI({
      k <- key()
      shiny::req(k)
      l <- lang()
      ns <- session$ns
      check <- export_check()
      free_text <- if (!is.null(check) && identical(check$snapshot_id, k$snapshot_id)) check$free_text else NA
      if (isTRUE(free_text)) {
        return(shiny::tags$p(class = "del-note", tr(l, "Diese Runde enth\u00e4lt Freitextfragen; der Rundenexport ist daf\u00fcr nicht freigegeben. Exportieren Sie die Studie unter Exporte mit dem Profil Pseudonymisierte Forschungsdaten.", "This round contains free-text questions, for which the round export is not approved. Export the study under Exports with the profile Pseudonymized research data.")))
      }
      # The worker refuses a round with free text; while that cannot be ruled
      # out, nothing is offered that would fail.
      if (!identical(free_text, FALSE)) {
        return(shiny::tags$p(class = "del-note", tr(l, "Hier l\u00e4sst sich nicht pr\u00fcfen, ob diese Runde Freitextfragen enth\u00e4lt, die der Rundenexport nicht abdeckt. Exportieren Sie die Studie unter Exporte.", "Whether this round has free-text questions, which the round export does not cover, cannot be checked here. Export the study under Exports.")))
      }
      shiny::tagList(
        shiny::tags$p(class = "del-note", tr(l, "Der Export enth\u00e4lt die eingefrorenen Antworten dieser Runde unter Pseudonymen, ihre Analyse und einen Bericht. Die Datei verl\u00e4sst die Zugriffskontrolle dieser Anwendung. Exporte der ganzen Studie stehen unter Exporte.", "The export holds the frozen answers of this round under pseudonyms, their analysis and a report. The file leaves the access control of this application. Exports of the whole study are under Exports.")),
        shiny::textAreaInput(ns("export_purpose"), tr(l, "Zweck des Exports (10 bis 500 Zeichen)", "Purpose of the export (10 to 500 characters)"), value = field("export_purpose"), width = "100%"),
        shiny::uiOutput(ns("export_actions"))
      )
    })
    output$export_actions <- shiny::renderUI({
      k <- key()
      shiny::req(k)
      l <- lang()
      ns <- session$ns
      ready_file <- artifact()
      shiny::tags$div(
        class = "del-actions",
        shiny::actionButton(ns("export"), tr(l, "Export beauftragen", "Request export")),
        if (!is.null(export_job())) shiny::actionButton(ns("export_poll"), tr(l, "Auftrag pr\u00fcfen", "Check operation")),
        if (!is.null(ready_file) && identical(ready_file$round_id, k$id)) shiny::downloadButton(ns("download"), tr(l, "Export herunterladen", "Download export"))
      )
    })
    shiny::observeEvent(input$export, attempt(function() {
      shiny::req(can("export"))
      r <- selected()
      check <- export_check()
      shiny::req(has_value(r$snapshot_id), identical(check$snapshot_id, r$snapshot_id), identical(check$free_text, FALSE))
      purpose <- if (is.null(input$export_purpose)) "" else trimws(input$export_purpose)
      if (nchar(purpose) < 10L || nchar(purpose) > 500L) {
        status(tr(lang(), "Bitte den Zweck des Exports angeben (10 bis 500 Zeichen).", "Enter the purpose of the export (10 to 500 characters)."))
        return()
      }
      job <- call("request_export", r$snapshot_id, command_id(), purpose = purpose)
      export_job(list(id = job$id, round_id = r$id, number = round_key(r)$number))
      artifact(NULL)
      status(tr(lang(), "Export eingereiht. Auftrag pr\u00fcfen.", "Export queued. Check the operation."))
    }))
    shiny::observeEvent(input$export_poll, attempt(function() {
      job <- export_job()
      shiny::req(job)
      r <- call("get_operation", job$id)
      status(operation_status(r, lang()))
      if (identical(r$state, "succeeded")) {
        export_job(NULL)
        artifact(list(id = r$result_ref, round_id = job$round_id, number = job$number))
      } else if (identical(r$state, "dead_letter")) {
        export_job(NULL)
      }
    }))
    output$download <- shiny::downloadHandler(filename = function() {
      x <- artifact()
      sprintf("delphyr-round-%s-export.zip", if (is.null(x)) "" else x$number)
    }, content = function(file) {
      x <- artifact()
      shiny::req(x)
      path <- call("download_artifact", x$id)
      files <- list.files(path, full.names = TRUE)
      zip::zipr(file, files, root = path)
    }, contentType = "application/zip")
  })
}

has_value <- function(x) length(x) == 1L && !is.na(x) && nzchar(as.character(x))
# What the controls of a round depend on; a column missing in a table is NA.
round_key <- function(r) {
  value <- function(name) if (name %in% names(r)) r[[name]][1] else NA
  list(id = r$id[1], number = value("number"), state = value("state"), snapshot_id = value("snapshot_id"), analysis_id = value("analysis_id"), free_text = value("free_text"))
}
truncate_text <- function(x, width) {
  x <- as.character(x)
  ifelse(!is.na(x) & nchar(x) > width, paste0(trimws(substr(x, 1L, width - 1L)), "\u2026"), x)
}

# The wording of a statement in the interface language where the instrument
# has it, otherwise in its first language. Study content is never translated.
statement_text <- function(items, code, lang, fallback = NULL) {
  if (is.null(items) || !is.data.frame(items) || !nrow(items)) {
    return(list(text = NA_character_, locale = NA_character_))
  }
  x <- items[items$item_code == code, , drop = FALSE]
  if (!nrow(x)) {
    return(list(text = NA_character_, locale = NA_character_))
  }
  for (preferred in c(lang, fallback)) {
    own <- x[x$locale == preferred, , drop = FALSE]
    if (nrow(own)) {
      x <- own
      break
    }
  }
  list(text = x$text[1], locale = x$locale[1])
}
statement_label <- function(codes, items, lang, fallback = NULL, width = 70L) {
  codes <- as.character(codes)
  text <- vapply(codes, function(code) statement_text(items, code, lang, fallback)$text, character(1))
  unname(ifelse(is.na(text), codes, paste0(codes, " \u00b7 ", truncate_text(text, width))))
}
statement_cell <- function(code, items, lang, fallback = NULL, dimension = NULL) {
  s <- statement_text(items, code, lang, fallback)
  shiny::tagList(shiny::tags$strong(code), if (length(dimension)) paste0(" \u00b7 ", dimension), if (!is.na(s$text)) shiny::tagList(shiny::tags$br(), shiny::tags$span(lang = s$locale, s$text)))
}

analysis_outcome_label <- function(classification, lang) {
  labels <- tr(
    lang,
    c(consensus_in = "Konsens f\u00fcr Aufnahme", consensus_out = "Konsens f\u00fcr Ausschluss", no_consensus = "Kein Konsens", insufficient_data = "Unzureichende Daten", not_rated = "Nicht bewertet"),
    c(consensus_in = "Consensus for inclusion", consensus_out = "Consensus for exclusion", no_consensus = "No consensus", insufficient_data = "Insufficient data", not_rated = "Not rated")
  )
  out <- unname(ifelse(classification %in% names(labels), labels[classification], classification))
  out[is.na(classification)] <- no_value
  out
}
# Display rows of analysis results: the statement with its dimension and
# wording, the rule outcome in words, then valid of assigned ratings, median,
# quartiles and the share in the agreement range. The outcome comes second so
# that it stays in view beside the statement on a phone.
result_rows <- function(res, items, lang, min_valid_n = NA, outcome = NULL, groups = FALSE, hidden = NULL, fallback = NULL, wording = TRUE) {
  col <- function(name) if (name %in% names(res)) res[[name]] else rep(NA, nrow(res))
  n_valid <- col("n_valid")
  n_assigned <- col("n_assigned")
  valid <- ifelse(is.na(n_valid), no_value, ifelse(is.na(n_assigned), as.character(n_valid), paste(n_valid, tr(lang, "von", "of"), n_assigned)))
  q1 <- col("q1")
  q3 <- col("q3")
  low <- format_number(q1, lang)
  high <- format_number(q3, lang)
  spread <- ifelse(is.na(q1) | is.na(q3), no_value, ifelse(low == high, low, paste0(low, "\u2013", high)))
  classification <- if (is.null(outcome)) col("classification") else outcome
  text <- analysis_outcome_label(classification, lang)
  if (length(min_valid_n) == 1L && !is.na(min_valid_n)) {
    few <- classification %in% "insufficient_data"
    text[few] <- paste0(text[few], " (", ifelse(!is.na(n_valid[few]) & n_valid[few] < min_valid_n, sprintf(tr(lang, "weniger als %s g\u00fcltige Bewertungen", "fewer than %s valid ratings"), min_valid_n), sprintf(tr(lang, "eine Gruppe hat weniger als %s g\u00fcltige Bewertungen", "a group has fewer than %s valid ratings"), min_valid_n)), ")")
  }
  if (!is.null(hidden)) text[hidden] <- hidden_text(lang, hidden_n = attr(hidden, "n"))
  rows <- lapply(seq_len(nrow(res)), function(i) {
    cells <- list(statement_cell(as.character(col("item_code")[i]), if (wording) items, lang, fallback, humanize_code(col("dimension_code")[i])))
    if (groups) cells <- c(cells, list(if (identical(col("stratum")[i], "overall")) tr(lang, "Ganzes Panel", "Whole panel") else humanize_code(col("stratum")[i])))
    c(cells, list(text[i], valid[i], format_number(col("median")[i], lang), spread[i], format_percent(col("p_agree")[i], lang)))
  })
  rows
}
hidden_text <- function(lang, hidden_n) {
  if (length(hidden_n) != 1L || is.na(hidden_n)) {
    return(tr(lang, "Nicht angezeigt", "Not shown"))
  }
  sprintf(tr(lang, "Nicht angezeigt (weniger als %s g\u00fcltige Bewertungen)", "Not shown (fewer than %s valid ratings)"), hidden_n)
}
result_header <- function(lang, groups = FALSE) {
  rest <- tr(lang, c("Regelergebnis", "G\u00fcltige Bewertungen", "Median", "Interquartilsbereich (Q1\u2013Q3)", "Im Zustimmungsbereich"), c("Rule outcome", "Valid ratings", "Median", "Interquartile range (Q1\u2013Q3)", "In agreement range"))
  c(tr(lang, "Item und Dimension", "Item and dimension"), if (groups) tr(lang, "Interessengruppe", "Stakeholder group"), rest)
}
# A table of display cells with a caption; the first column holds the
# statement and stays visible when the table scrolls sideways.
display_table <- function(header, rows, caption = NULL, wide_first = TRUE) {
  shiny::tags$table(
    class = "table table-striped",
    if (!is.null(caption)) shiny::tags$caption(caption),
    shiny::tags$thead(shiny::tags$tr(lapply(header, function(h) shiny::tags$th(scope = "col", h)))),
    shiny::tags$tbody(lapply(rows, function(cells) {
      shiny::tags$tr(lapply(seq_along(cells), function(j) if (j == 1L && wide_first) shiny::tags$td(style = "min-width:10rem;max-width:20rem", cells[[j]]) else shiny::tags$td(cells[[j]])))
    }))
  )
}
# Free-text dimensions carry no statistics; their contributions are counted.
free_text_lines <- function(res, lang) {
  col <- function(name) if (name %in% names(res)) res[[name]] else rep(NA, nrow(res))
  free <- res[col("classification") %in% "not_rated" & col("stratum") %in% c("overall", NA), , drop = FALSE]
  if (!nrow(free)) {
    return(character())
  }
  answered <- if ("n_answered" %in% names(free)) free$n_answered else rep(NA, nrow(free))
  vapply(unique(free$dimension_code), function(d) {
    n <- answered[free$dimension_code == d]
    sprintf(tr(lang, "Freitextdimension \u201e%s\u201c: %s Beitr\u00e4ge zu %s Items.", "Free-text dimension \u201c%s\u201d: %s contributions on %s items."), humanize_code(d), sum(n, na.rm = TRUE), sum(n > 0, na.rm = TRUE))
  }, character(1))
}
# The analysis of one round: the whole panel first, the stakeholder groups
# in a collapsible part, free text summarised.
analysis_view <- function(x, lang) {
  a <- x$data
  res <- a$results
  if (!is.data.frame(res) || !nrow(res)) {
    return(shiny::tags$p(class = "del-note", tr(lang, "Die Analyse enth\u00e4lt keine Ergebnisse.", "The analysis has no results.")))
  }
  col <- function(name, fill = NA) if (name %in% names(res)) res[[name]] else rep(fill, nrow(res))
  stratum <- col("stratum", "overall")
  rated <- !col("classification") %in% "not_rated"
  overall <- res[stratum == "overall" & rated, , drop = FALSE]
  groups <- res[stratum != "overall" & rated, , drop = FALSE]
  rule <- a$settings
  min_valid_n <- if (is.numeric(rule$min_valid_n) && length(rule$min_valid_n) == 1L) rule$min_valid_n else NA
  # The rule outcome that the study team decides on follows the protocol's
  # group policy; it is read from the analysis' decision table.
  outcome <- if ("classification" %in% names(overall)) overall$classification else rep(NA_character_, nrow(overall))
  d <- a$decisions
  if (is.data.frame(d) && nrow(d) && all(c("item_code", "dimension_code", "classification") %in% names(d)) && nrow(overall)) {
    key <- function(z) paste(z$item_code, if ("item_version" %in% names(z)) z$item_version else "", z$dimension_code, sep = "\034")
    found <- match(key(overall), key(d))
    outcome <- ifelse(is.na(found), outcome, d$classification[found])
  }
  agree <- suppressWarnings(as.numeric(unlist(rule$agree_values)))
  notes <- c(
    if (length(agree) && !anyNA(agree)) sprintf(tr(lang, "Zustimmungsbereich: Bewertungen von %s bis %s.", "Agreement range: ratings from %s to %s."), min(agree), max(agree)),
    if (anyNA(col("median")[stratum == "overall" & rated])) tr(lang, "\u2014 bedeutet: kein Wert, weil keine g\u00fcltige Bewertung vorliegt.", "\u2014 means: no value, because there is no valid rating."),
    free_text_lines(res, lang)
  )
  shiny::tagList(
    if (nrow(overall)) display_table(result_header(lang), result_rows(overall, x$items, lang, min_valid_n, outcome, fallback = x$language), paste(tr(lang, "Analyse der Runde", "Analysis of round"), x$number)),
    lapply(notes, function(n) shiny::tags$p(class = "del-note", n)),
    if (nrow(groups)) {
      shiny::tags$details(
        shiny::tags$summary(tr(lang, "Ergebnisse nach Interessengruppe", "Results by stakeholder group")),
        display_table(result_header(lang, groups = TRUE), result_rows(groups, x$items, lang, min_valid_n, groups = TRUE, fallback = x$language, wording = FALSE), wide_first = FALSE)
      )
    }
  )
}
feedback_state_label <- function(state, lang) {
  labels <- tr(lang, c(reviewed = "Noch nicht freigegeben", released = "Freigegeben"), c(reviewed = "Not released yet", released = "Released"))
  unname(ifelse(state %in% names(labels), labels[state], state))
}
# A feedback candidate as participants will see it: the statistics after
# suppression, the released texts and the policy applied.
feedback_view <- function(x, items, lang, free_scales = character(), fallback = NULL) {
  content <- x$content
  res <- content$results
  policy <- content$policy
  minimum <- policy$minimum_display_cell_n
  shown_groups <- isTRUE(policy$group_statistics)
  qualitative <- feedback_texts(content$qualitative)
  table <- NULL
  if (is.data.frame(res) && nrow(res)) {
    col <- function(name, fill = NA) if (name %in% names(res)) res[[name]] else rep(fill, nrow(res))
    # Free-text rows are always below the display minimum and carry no
    # statistics, so they are recognised by their scale.
    keep <- !col("classification") %in% "not_rated" & !col("scale_code") %in% free_scales
    res <- res[keep, , drop = FALSE]
    if (nrow(res)) {
      hidden <- if ("suppressed" %in% names(res)) as.logical(res$suppressed) else rep(FALSE, nrow(res))
      hidden[is.na(hidden)] <- FALSE
      attr(hidden, "n") <- if (length(minimum) == 1L) minimum else NA
      table <- display_table(result_header(lang, groups = shown_groups), result_rows(res, items, lang, groups = shown_groups, hidden = hidden, fallback = fallback), tr(lang, "Ergebnisse f\u00fcr die Teilnehmenden", "Results for participants"))
    }
  }
  shiny::tagList(
    shiny::tags$p(paste(tr(lang, "Pr\u00fcfsumme:", "Checksum:"), short_ref(x$hash, 12L), "\u00b7", feedback_state_label(x$state, lang))),
    shiny::tags$p(class = "del-note", paste(
      if (shown_groups) tr(lang, "Die Teilnehmenden sehen die Ergebnisse des ganzen Panels und jeder Interessengruppe.", "Participants see the results of the whole panel and of each stakeholder group.") else tr(lang, "Die Teilnehmenden sehen die Ergebnisse des ganzen Panels; Gruppenergebnisse werden nicht gezeigt.", "Participants see the results of the whole panel; group results are not shown."),
      if (length(minimum) == 1L && !is.na(minimum)) sprintf(tr(lang, "Werte aus weniger als %s g\u00fcltigen Bewertungen werden nicht gezeigt.", "Values based on fewer than %s valid ratings are not shown."), minimum)
    )),
    table,
    shiny::tags$h4(tr(lang, "Texte in diesem Feedback", "Texts in this feedback")),
    if (nrow(qualitative)) {
      shiny::tags$ul(class = "del-qualitative", lapply(seq_len(nrow(qualitative)), function(i) {
        shiny::tags$li(shiny::tags$span(class = "del-note", if (identical(qualitative$kind[i], "summary")) tr(lang, "Moderierte Zusammenfassung (kein Zitat):", "Moderated summary (not a quotation):") else tr(lang, "Redigierter Beitrag:", "Redacted contribution:")), " ", qualitative$text[i])
      }))
    } else {
      shiny::tags$p(class = "del-note", tr(lang, "Dieses Feedback enth\u00e4lt keine Texte.", "This feedback contains no texts."))
    }
  )
}
# Released texts of a feedback, however JSON returned them.
feedback_texts <- function(q) {
  if (is.data.frame(q) && nrow(q) && "text" %in% names(q)) {
    return(data.frame(text = as.character(q$text), kind = if ("kind" %in% names(q)) as.character(q$kind) else NA_character_, stringsAsFactors = FALSE))
  }
  if (is.list(q) && length(q) && !is.data.frame(q)) {
    pick <- function(e, name) if (is.null(e[[name]])) NA_character_ else as.character(e[[name]])[1]
    return(data.frame(text = vapply(q, pick, character(1), name = "text"), kind = vapply(q, pick, character(1), name = "kind"), stringsAsFactors = FALSE))
  }
  data.frame(text = character(), kind = character(), stringsAsFactors = FALSE)
}

# Released feedback by round: the first release and its corrections, in
# order, with the moment each version was released where it is known.
feedback_versions <- function(p) {
  if (!is.data.frame(p) || !nrow(p)) {
    return(data.frame(round_number = integer(), feedback_id = character(), hash = character(), replacement_id = character(), version = integer(), released = character(), rationale = character(), assigned_round = integer(), stringsAsFactors = FALSE))
  }
  p$version <- NA_integer_
  p$released <- if ("released_at" %in% names(p)) as.character(p$released_at) else NA_character_
  p$rationale <- NA_character_
  correction <- if ("is_correction" %in% names(p)) p$is_correction %in% TRUE else rep(FALSE, nrow(p))
  for (start in which(!correction)) {
    i <- start
    k <- 1L
    while (length(i) == 1L && is.na(p$version[i])) {
      p$version[i] <- k
      following <- if (is.na(p$replacement_id[i])) integer() else which(p$feedback_id == p$replacement_id[i])
      if (length(following) == 1L) {
        if (is.na(p$released[following]) && "corrected_at" %in% names(p)) p$released[following] <- p$corrected_at[i]
        if ("reason" %in% names(p)) p$rationale[following] <- p$reason[i]
      }
      i <- following
      k <- k + 1L
    }
  }
  p
}
feedback_version_label <- function(version, lang) {
  out <- ifelse(version %in% 1L, tr(lang, "Erste Freigabe", "First release"), sprintf(tr(lang, "Korrektur %s", "Correction %s"), version - 1L))
  out[is.na(version)] <- no_value
  out
}
released_feedback_label <- function(p, lang, zone, assigned = FALSE) {
  if (!nrow(p)) {
    return(character())
  }
  label <- paste(tr(lang, "Runde", "Round"), p$round_number, "\u00b7", feedback_version_label(p$version, lang))
  known <- !is.na(p$released)
  label[known] <- paste(label[known], "\u00b7", tr(lang, "freigegeben am", "released"), format_moment(p$released[known], zone, lang))
  if (assigned && "assigned_round" %in% names(p)) {
    to <- !is.na(p$assigned_round)
    label[to] <- paste(label[to], "\u00b7", tr(lang, "zugewiesen an Runde", "assigned to round"), p$assigned_round[to])
  }
  label
}
# A language of the study by its name in the interface language.
language_name <- function(code, lang) {
  labels <- tr(lang, c(en = "Englisch", fr = "Franz\u00f6sisch", de = "Deutsch"), c(en = "English", fr = "French", de = "German"))
  code <- as.character(code)
  unname(ifelse(code %in% names(labels), labels[code], code))
}
# Versions of the published study information: number, language and, where
# known, the day of publication.
consent_version_label <- function(x, lang, zone) {
  label <- paste(tr(lang, "Fassung", "Version"), seq_len(nrow(x)), "\u00b7", language_name(x$locale, lang))
  if ("created_at" %in% names(x)) {
    day <- sub(", [0-9]{2}:[0-9]{2}$", "", format_moment(x$created_at, zone, lang, with_zone = FALSE))
    label <- ifelse(day == no_value, label, paste(label, "\u00b7", day))
  }
  label
}
# The columns of an instrument file and what the protocol admits in them.
instrument_guide <- function(protocol, lang) {
  dimensions <- protocol$instrument$dimensions
  codes <- vapply(dimensions, function(d) as.character(d$code), character(1))
  scales <- vapply(dimensions, function(d) as.character(d$scale), character(1))
  languages <- as.character(unlist(protocol$study$languages))
  allowed <- function(text, values) if (length(values)) paste(text, paste(values, collapse = ", ")) else text
  rows <- list(
    c("item_code", tr(lang, "Code der Aussage, in jeder Runde gleich, zum Beispiel I001", "Code of the statement, the same in every round, for example I001")),
    c("item_version", tr(lang, "Ganze Zahl; ein ge\u00e4nderter Wortlaut braucht eine neue Version", "Whole number; a changed wording needs a new version")),
    c("locale", allowed(tr(lang, "Sprache des Textes:", "Language of the text:"), languages)),
    c("text", tr(lang, "Wortlaut der Aussage in dieser Sprache", "Wording of the statement in that language")),
    c("dimension_code", allowed(tr(lang, "Bewertete Dimension:", "Dimension rated:"), codes)),
    c("scale_code", allowed(tr(lang, "Skala der Dimension:", "Scale of the dimension:"), if (length(codes)) paste0(scales, " (", codes, ")") else character())),
    c("source_ref", tr(lang, "Herkunft der Aussage, zum Beispiel eine Literaturstelle", "Source of the statement, for example a reference")),
    c("required", tr(lang, "TRUE, wenn eine Antwort verlangt ist, sonst FALSE", "TRUE if an answer is required, otherwise FALSE")),
    c("display_order", tr(lang, "Position im Fragebogen: 1, 2, 3 \u2026", "Position in the questionnaire: 1, 2, 3 \u2026"))
  )
  shiny::tagList(
    shiny::tags$p(class = "del-note", tr(lang, "Eine Zeile je Aussage, Dimension und Sprache; UTF-8, durch Kommas getrennt, mit Kopfzeile.", "One row per statement, dimension and language; UTF-8, separated by commas, with a header row.")),
    shiny::tags$table(
      class = "table",
      shiny::tags$caption(tr(lang, "Spalten der Instrumentdatei", "Columns of the instrument file")),
      shiny::tags$thead(shiny::tags$tr(lapply(tr(lang, c("Spalte", "Inhalt"), c("Column", "Content")), function(h) shiny::tags$th(scope = "col", h)))),
      shiny::tags$tbody(lapply(rows, function(x) shiny::tags$tr(shiny::tags$td(shiny::tags$code(x[1])), shiny::tags$td(x[2]))))
    )
  )
}

decision_dispositions <- function() c("retain", "revise", "remove", "split", "merge", "rerate", "finalize")

disposition_label <- function(disposition, lang) {
  labels <- tr(
    lang,
    c(retain = "Beibehalten", revise = "\u00dcberarbeiten", remove = "Entfernen", split = "Teilen", merge = "Zusammenf\u00fchren", rerate = "Erneut bewerten", finalize = "Abschlie\u00dfend aufnehmen"),
    c(retain = "Retain", revise = "Revise", remove = "Remove", split = "Split", merge = "Merge", rerate = "Rate again", finalize = "Finalize")
  )
  unname(ifelse(disposition %in% names(labels), labels[disposition], disposition))
}
