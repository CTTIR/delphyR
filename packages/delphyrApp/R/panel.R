panel_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::tags$div(style = "display:none", shiny::textOutput(ns("visible"))),
    shiny::tags$div(id = ns("connection"), class = "del-banner", role = "alert", hidden = "hidden"),
    shiny::tags$script(shiny::HTML(connection_script(ns("connection"), ns("workspace")))),
    shiny::conditionalPanel(
      condition = sprintf("output['%s'] === 'yes'", ns("visible")),
      shiny::tags$section(
        id = ns("workspace"), class = "del-sheet", shiny::uiOutput(ns("heading")),
        shiny::selectInput(ns("enrollment"), "Round", character()),
        shiny::actionButton(ns("load"), "Load round"), status_ui(ns("status")),
        shiny::uiOutput(ns("questionnaire")), shiny::uiOutput(ns("withdrawal"))
      )
    )
  )
}
panel_server <- function(id, study, lang, call, feedback_available = FALSE, capabilities_available = FALSE, withdrawal_available = FALSE, autosave_ms = 1500, feedback_download_available = FALSE) {
  shiny::moduleServer(id, function(input, output, session) {
    visible <- shiny::reactiveVal(!capabilities_available)
    output$visible <- shiny::renderText(if (visible()) "yes" else "no")
    shiny::outputOptions(output, "visible", suspendWhenHidden = FALSE)
    q <- shiny::reactiveVal(NULL)
    editors <- shiny::reactiveVal(list())
    status <- shiny::reactiveVal("")
    receipt <- shiny::reactiveVal(NULL)
    generation <- 0L
    output$withdrawal <- shiny::renderUI({
      shiny::req(withdrawal_available, study(), visible())
      ns <- session$ns
      shiny::tags$details(
        shiny::tags$summary(tr(lang(), "Teilnahme beenden", "End participation")),
        shiny::tags$p(tr(lang(), "Dies beendet weitere Antworten und Einladungen in dieser synthetischen Studie. Bereits gespeicherte Daten bleiben erhalten. Dies ist kein L\u00f6schantrag.", "This stops further responses and invitations in this synthetic study. Previously saved data are retained. This is not a deletion request.")),
        shiny::checkboxInput(ns("withdraw_confirm"), tr(lang(), "Ich m\u00f6chte meine Teilnahme beenden und verstehe den beschriebenen Datenverbleib.", "I want to end participation and understand the stated data retention."), FALSE),
        shiny::actionButton(ns("withdraw"), tr(lang(), "Teilnahme verbindlich beenden", "Confirm end of participation"), class = "btn-outline-danger")
      )
    })
    shiny::observeEvent(input$withdraw, {
      shiny::req(withdrawal_available, study())
      if (!isTRUE(input$withdraw_confirm)) {
        status(tr(lang(), "Bitte den Teilnahmer\u00fcckzug ausdr\u00fccklich best\u00e4tigen.", "Explicitly confirm withdrawal first."))
        return()
      }
      tryCatch({
        result <- call("withdraw_participation", study(), "synthetic_retain_prior_data", command_id())
        editors(list())
        q(NULL)
        receipt(NULL)
        status(paste(tr(lang(), "Teilnahme beendet. Gespeicherte Daten bleiben erhalten. Beleg:", "Participation ended. Saved data are retained. Receipt:"), result$id))
        shiny::updateCheckboxInput(session, "withdraw_confirm", value = FALSE)
      }, error = function(e) status(safe_error(e, lang())))
    })
    output$heading <- shiny::renderUI(shiny::tags$h2(tr(lang(), "Meine Teilnahme", "My participation")))
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    shiny::observeEvent(list(study(), lang()), {
      tryCatch(
        {
          if (capabilities_available) {
            visible("panel" %in% call("get_capabilities", study()))
            if (!visible()) {
              return()
            }
          }
          x <- call("list_enrollments", study())
          shiny::updateSelectInput(session, "enrollment", label = tr(lang(), "Runde", "Round"), choices = stats::setNames(x$id, paste(tr(lang(), "Runde", "Round"), x$number, "\u00b7", state_label(x$round_state, lang()))), selected = if (length(input$enrollment) == 1L && input$enrollment %in% x$id) input$enrollment else utils::head(x$id, 1))
          status(if (!nrow(x)) tr(lang(), "Keine zugewiesene Runde.", "No assigned round.") else "")
        },
        error = function(e) {
          shiny::updateSelectInput(session, "enrollment", choices = character())
          status(tr(lang(), "Keine Panelansicht f\u00fcr diese Studie verf\u00fcgbar.", "No panel view is available for this study."))
        }
      )
    })
    shiny::observeEvent(lang(), shiny::updateActionButton(session, "load", label = tr(lang(), "Runde laden", "Load round")))
    dirty <- shiny::reactive(any(vapply(editors(), function(x) isTRUE(x$dirty()), logical(1))))
    shiny::observeEvent(input$load, {
      shiny::req(input$enrollment)
      for (x in editors()) if (shiny::isolate(x$dirty()) && is.function(x$save_now)) x$save_now()
      if (dirty()) {
        status(tr(lang(), "Bitte \u00c4nderungen zuerst speichern. Die ge\u00f6ffnete Runde bleibt erhalten.", "Save your changes first. The current round stays open."))
        return()
      }
      tryCatch(
        {
          z <- call("get_questionnaire", input$enrollment)
          if (feedback_available) z$feedback <- call("get_feedback", input$enrollment)
          generation <<- generation + 1L
          mods <- list()
          ids <- character(nrow(z$items))
          for (i in seq_len(nrow(z$items))) {
            mid <- paste0("item_", generation, "_", i)
            ids[i] <- mid
            mods[[i]] <- rating_server(mid, z, z$items[i, , drop = FALSE], lang, call, autosave_ms = autosave_ms)
          }
          z$module_ids <- ids
          editors(mods)
          receipt(NULL)
          q(z)
          status("")
        },
        error = function(e) status(safe_error(e, lang()))
      )
    })
    output$questionnaire <- shiny::renderUI({
      z <- q()
      shiny::req(z)
      ns <- session$ns
      # Interface language changes never recreate response controls.
      l <- shiny::isolate(lang())
      shiny::tagList(
        shiny::tags$h3(shiny::textOutput(ns("round_heading"))),
        shiny::tags$p(shiny::textOutput(ns("deadline"))),
        shiny::tags$details(shiny::tags$summary(shiny::textOutput(ns("information_label"), inline = TRUE)), shiny::tags$p(class = "del-consent", z$consent$content)),
        shiny::checkboxInput(ns("consent_check"), tr(l, "Ich stimme der angezeigten Studieninformation zu.", "I consent to the displayed study information."), FALSE),
        shiny::actionButton(ns("consent"), tr(l, "Einwilligung speichern", "Save consent")),
        if (isTRUE(z$consent$accepted)) shiny::tags$p(tr(l, "Einwilligung liegt vor.", "Consent is recorded.")),
        if (nrow(z$receipt)) shiny::tags$p(paste(tr(l, "Abgabebeleg:", "Submission receipt:"), z$receipt$id, z$receipt$submitted_at)),
        if (feedback_download_available && !is.null(z$feedback)) shiny::downloadButton(ns("feedback_download"), tr(l, "Mein Feedback herunterladen", "Download my feedback")),
        shiny::tags$p(class = "del-note", shiny::textOutput(ns("save_note"))),
        shiny::tags$p(class = "del-note", shiny::textOutput(ns("content_note"))),
        lapply(z$module_ids, function(x) rating_ui(ns(x))),
        shiny::tags$div(class = "del-progress", shiny::uiOutput(ns("progress"))),
        shiny::checkboxInput(ns("confirm"), tr(l, "Ich habe meine Antworten gepr\u00fcft. Die Abgabe beendet die Bearbeitung.", "I reviewed my answers. Submission ends editing."), FALSE),
        shiny::actionButton(ns("submit"), tr(l, "Verbindlich abgeben", "Submit final responses"), class = "btn-primary"),
        status_ui(ns("receipt"))
      )
    })
    output$round_heading <- shiny::renderText({
      shiny::req(q())
      paste(tr(lang(), "Runde", "Round"), q()$round$number)
    })
    output$content_note <- shiny::renderText(tr(lang(), "Studientexte, Skalenanker und Einwilligung bleiben in ihrer genehmigten Sprache.", "Study text, scale anchors and consent remain in their approved language."))
    output$information_label <- shiny::renderText(tr(lang(), "Studieninformation", "Study information"))
    automatic <- is.numeric(autosave_ms) && length(autosave_ms) == 1L && autosave_ms > 0
    output$save_note <- shiny::renderText(if (automatic) {
      tr(lang(), "Antworten werden kurz nach jeder \u00c4nderung automatisch gespeichert. Nur die Best\u00e4tigung neben einem Feld belegt die Speicherung.", "Responses are saved automatically shortly after each change. Only the confirmation shown beside a field establishes a save.")
    } else {
      tr(lang(), "Jedes Bewertungsfeld einzeln speichern. Keine automatische Speicherung.", "Save each response field explicitly. Saving is not automatic.")
    })
    output$deadline <- shiny::renderText({
      shiny::req(q())
      zone <- q()$protocol$study$timezone
      if (is.null(zone)) zone <- "UTC"
      paste(tr(lang(), "Abgabe bis:", "Submit by:"), format(as.POSIXct(q()$round$deadline, tz = "UTC"), format = "%d.%m.%Y %H:%M %z", tz = zone), zone)
    })
    shiny::observeEvent(list(lang(), q()), {
      shiny::updateCheckboxInput(session, "consent_check", label = tr(lang(), "Ich stimme der angezeigten Studieninformation zu.", "I consent to the displayed study information."))
      shiny::updateActionButton(session, "consent", label = tr(lang(), "Einwilligung speichern", "Save consent"))
      shiny::updateCheckboxInput(session, "confirm", label = tr(lang(), "Ich habe meine Antworten gepr\u00fcft. Die Abgabe beendet die Bearbeitung.", "I reviewed my answers. Submission ends editing."))
      shiny::updateActionButton(session, "submit", label = tr(lang(), "Verbindlich abgeben", "Submit final responses"))
    })
    shiny::observeEvent(input$consent, {
      z <- q()
      shiny::req(z)
      if (!isTRUE(input$consent_check)) {
        status(tr(lang(), "Bitte die Einwilligung bewusst ausw\u00e4hlen.", "Select consent explicitly first."))
        return()
      }
      tryCatch(
        {
          r <- call("record_consent", z$round$study_id, z$consent$id, TRUE, command_id())
          status(paste(tr(lang(), "Einwilligung gespeichert. Beleg:", "Consent saved. Receipt:"), r$id))
        },
        error = function(e) status(safe_error(e, lang()))
      )
    })
    output$progress <- shiny::renderUI({
      shiny::req(q())
      a <- editors()
      n <- sum(vapply(a, function(x) x$answered() && !x$dirty(), logical(1)))
      shiny::tags$p(paste(n, "/", length(a), tr(lang(), "Bewertungsfelder best\u00e4tigt gespeichert.", "response fields confirmed saved.")))
    })
    output$receipt <- shiny::renderText({
      r <- receipt()
      if (is.null(r)) {
        return("")
      }
      paste(tr(lang(), "Abgabe best\u00e4tigt:", "Submission confirmed:"), r$id, r$submitted_at)
    })
    shiny::outputOptions(output, "receipt", suspendWhenHidden = FALSE)
    shiny::observeEvent(input$submit, {
      z <- q()
      shiny::req(z)
      a <- editors()
      # Pending complete answers are saved first; submission never outruns a save.
      for (x in a) if (shiny::isolate(x$dirty()) && is.function(x$save_now)) x$save_now()
      if (dirty() || !isTRUE(input$confirm)) {
        status(tr(lang(), "Zuerst alle \u00c4nderungen speichern und die Abgabe best\u00e4tigen.", "Save all changes and confirm submission first."))
        return()
      }
      revs <- vapply(a, function(x) as.integer(x$revision()), integer(1))
      names(revs) <- z$items$id
      revs <- revs[revs > 0]
      tryCatch(
        {
          r <- call("submit_round", z$enrollment$id, revs, command_id())
          receipt(r)
          status(tr(lang(), "Abgegeben. Eine weitere Bearbeitung ist nicht m\u00f6glich.", "Submitted. Further editing is unavailable."))
        },
        error = function(e) status(safe_error(e, lang()))
      )
    })
    # The participant-feedback profile: the released aggregate and only this
    # person's own previous answers, written to a private temporary directory.
    output$feedback_download <- shiny::downloadHandler(
      filename = function() "delphyr-feedback.zip",
      content = function(file) {
        z <- q()
        shiny::req(feedback_download_available, z)
        directory <- tempfile("delphyr-feedback-")
        dir.create(directory, mode = "0700")
        on.exit(unlink(directory, recursive = TRUE), add = TRUE)
        call("write_participant_feedback", z$enrollment$id, directory)
        zip::zipr(file, list.files(directory, full.names = TRUE), root = directory)
      }, contentType = "application/zip"
    )
    list(dirty = dirty, questionnaire = q, receipt = receipt)
  })
}
rating_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tags$section(
    class = "del-item", shiny::uiOutput(ns("title")), shiny::uiOutput(ns("prior")), shiny::tableOutput(ns("feedback")), shiny::uiOutput(ns("form")),
    shiny::actionButton(ns("save"), "Save now", class = "btn-primary"), shiny::uiOutput(ns("save_status")), shiny::uiOutput(ns("conflict"))
  )
}
rating_server <- function(id, q, item, lang, call, autosave_ms = 1500) {
  shiny::moduleServer(id, function(input, output, session) {
    scale <- q$protocol$instrument$scales[[item$scale_code]]
    stored <- function(responses) {
      old <- responses[responses$round_item_id == item$id, , drop = FALSE]
      status <- if (nrow(old)) old$status[1] else "not_answered"
      value <- if (nrow(old) && status == "answered") {
        if (scale$type == "free_text") old$value_text[1] else as.character(old$value_int[1])
      } else {
        ""
      }
      list(revision = if (nrow(old)) old$revision[1] else 0L, status = status, value = value)
    }
    initial <- stored(q$responses)
    old_status <- initial$status
    old_value <- initial$value
    revision <- shiny::reactiveVal(initial$revision)
    baseline <- shiny::reactiveVal(list(status = old_status, value = old_value))
    message <- shiny::reactiveVal("")
    save_failed <- shiny::reactiveVal(FALSE)
    # A conflict or closed round stops automatic attempts until the person acts.
    conflict <- shiny::reactiveVal(FALSE)
    closed <- shiny::reactiveVal(FALSE)
    answered <- shiny::reactiveVal(old_status != "not_answered")
    locked <- isTRUE(q$enrollment$state %in% c("submitted", "withdrawn"))
    last_attempt <- NULL
    # After deliberately loading the saved response, nothing is saved
    # automatically until the form shows that loaded state.
    awaiting_loaded <- FALSE
    output$title <- shiny::renderUI({
      texts <- jsonlite::fromJSON(item$texts)
      text <- texts[[lang()]]
      fallback <- is.null(text)
      content_language <- lang()
      if (fallback) {
        preferred <- q$protocol$study$default_language
        content_language <- if (!is.null(preferred) && preferred %in% names(texts)) preferred else names(texts)[1]
        text <- texts[[content_language]]
      }
      shiny::tagList(
        shiny::tags$h3(shiny::tags$span(lang = content_language, text), shiny::tags$small(paste0(" (", if (item$required) tr(lang(), "erforderlich", "required") else tr(lang(), "optional", "optional"), ")"))),
        if (fallback) shiny::tags$p(class = "del-note", paste(tr(lang(), "Keine genehmigte \u00dcbersetzung verf\u00fcgbar; angezeigte Sprache:", "No approved translation is available; displayed language:"), content_language))
      )
    })
    output$prior <- shiny::renderUI({
      f <- q$feedback
      shiny::req(f)
      own <- f$own
      own <- own[own$item_code == item$item_code & own$dimension_code == item$dimension_code, , drop = FALSE]
      shiny::tagList(
        shiny::tags$p(tr(lang(), "Freigegebenes Feedback der Vorrunde:", "Released previous-round feedback:")),
        if (nrow(own)) shiny::tags$p(paste(tr(lang(), "Ihre vorherige Antwort:", "Your previous response:"), own$answer_status, own$value_integer, own$value_text)),
        if (nrow(own) && any(own$item_version != item$item_version)) {
          decided <- f$comparability
          comparable <- is.data.frame(decided) && nrow(decided) && any(decided$item_code == item$item_code & decided$dimension_code == item$dimension_code & decided$previous_version %in% own$item_version & decided$current_version == item$item_version & decided$comparable)
          shiny::tags$p(if (isTRUE(comparable)) {
            tr(lang(), "Der Wortlaut wurde \u00fcberarbeitet. Das Studienteam hat beide Fassungen als vergleichbar eingestuft.", "The wording was revised. The study team assessed both versions as comparable.")
          } else {
            tr(lang(), "Der Wortlaut wurde ge\u00e4ndert. Bewertungen sind nicht unmittelbar vergleichbar.", "The wording changed. Ratings are not directly comparable.")
          })
        }
      )
    })
    output$feedback <- shiny::renderTable(
      {
        f <- q$feedback
        shiny::req(f)
        r <- f$aggregate$results
        r[r$item_code == item$item_code & r$dimension_code == item$dimension_code, , drop = FALSE]
      },
      striped = TRUE
    )
    rating_choices <- function(l) c(stats::setNames("", tr(l, "Bitte w\u00e4hlen", "Choose a rating")), stats::setNames(as.character(unlist(scale$values)), as.character(unlist(scale$values))))
    output$form <- shiny::renderUI({
      ns <- session$ns
      l <- shiny::isolate(lang())
      opts <- response_choices(scale, l)

      shiny::tags$fieldset(
        disabled = if (locked) "disabled" else NULL, shiny::selectInput(ns("kind"), tr(l, "Antworttyp", "Response type"), opts, selected = old_status),
        if (scale$type == "free_text") {
          shiny::textAreaInput(ns("value"), tr(l, "Antworttext", "Response text"), value = old_value, width = "100%")
        } else {
          shiny::selectInput(ns("value"), tr(l, "Bewertung", "Rating"), rating_choices(l), selected = old_value)
        },
        if (!is.null(scale$anchors)) shiny::tags$p(class = "del-note", paste(names(scale$anchors), unlist(scale$anchors), sep = ": ", collapse = "; "))
      )
    })
    shiny::observeEvent(lang(), {
      shiny::updateSelectInput(session, "kind", label = tr(lang(), "Antworttyp", "Response type"), choices = response_choices(scale, lang()), selected = if (is.null(input$kind)) old_status else input$kind)
      if (scale$type == "free_text") {
        shiny::updateTextAreaInput(session, "value", label = tr(lang(), "Antworttext", "Response text"))
      } else {
        shiny::updateSelectInput(session, "value", label = tr(lang(), "Bewertung", "Rating"), choices = rating_choices(lang()), selected = if (is.null(input$value)) old_value else input$value)
      }
      shiny::updateActionButton(session, "save", label = tr(lang(), "Jetzt speichern", "Save now"))
    })
    # Entering a value means answering; choosing a special response clears it.
    # The pair shown on screen is therefore always the pair that is stored.
    shiny::observeEvent(input$value, {
      if (nzchar(input$value) && !is.null(input$kind) && input$kind != "answered") shiny::updateSelectInput(session, "kind", selected = "answered")
    })
    shiny::observeEvent(input$kind, {
      if (input$kind != "answered" && !is.null(input$value) && nzchar(input$value)) {
        if (scale$type == "free_text") shiny::updateTextAreaInput(session, "value", value = "") else shiny::updateSelectInput(session, "value", selected = "")
      }
    })
    current <- shiny::reactive({
      status <- if (is.null(input$kind)) old_status else input$kind
      value <- if (is.null(input$value)) old_value else input$value
      # A value shown beside a special response is never part of the answer.
      list(status = status, value = if (identical(status, "answered")) value else "")
    })
    dirty <- shiny::reactive(!identical(current(), baseline()))
    complete <- shiny::reactive(current()$status != "answered" || nzchar(trimws(current()$value)))
    output$save_status <- shiny::renderUI({
      tone <- if (dirty() || save_failed() || conflict()) "attention" else if (revision() > 0) "saved" else "neutral"
      shiny::tags$div(
        class = paste("del-status", paste0("del-status--", tone)),
        role = "status", `aria-live` = "polite", shiny::textOutput(session$ns("status"))
      )
    })
    output$status <- shiny::renderText({
      if (conflict()) {
        return(localize_status(message(), lang()))
      }
      if (dirty()) {
        return(paste(
          tr(lang(), "Ungespeicherte \u00c4nderung.", "Unsaved change."),
          if (save_failed()) {
            localize_status(message(), lang())
          } else if (!complete()) {
            if (scale$type == "free_text") tr(lang(), "Bitte Text eingeben oder einen anderen Antworttyp angeben.", "Enter text or select another response type.") else tr(lang(), "Bitte eine Bewertung w\u00e4hlen oder einen anderen Antworttyp angeben.", "Choose a rating or select another response type.")
          } else {
            ""
          }
        ))
      }
      if (nzchar(message())) localize_status(message(), lang()) else if (revision() > 0) tr(lang(), "Gespeicherter Stand", "Saved response") else tr(lang(), "Noch nicht gespeichert", "Not yet saved")
    })
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    save_now <- function() {
      a <- shiny::isolate(current())
      if (locked || !shiny::isolate(dirty())) {
        return(!shiny::isolate(dirty()))
      }
      if (!shiny::isolate(complete())) {
        return(FALSE)
      }
      value <- if (a$status != "answered") NULL else if (scale$type == "free_text") a$value else suppressWarnings(as.numeric(a$value))
      expected <- shiny::isolate(revision())
      # An identical retry reuses its key, so a save whose reply was lost
      # returns the original receipt instead of a false conflict.
      attempt <- list(payload = a, revision = expected)
      key <- if (!is.null(last_attempt) && identical(last_attempt$attempt, attempt)) last_attempt$key else command_id()
      last_attempt <<- list(attempt = attempt, key = key)
      message(tr(lang(), "Wird gespeichert \u2026", "Saving \u2026"))
      tryCatch(
        {
          r <- call("save_response", q$enrollment$id, item$id, list(value = value, status = a$status), expected, key)
          save_failed(FALSE)
          conflict(FALSE)
          revision(r$revision)
          baseline(a)
          answered(a$status != "not_answered")
          message(paste(tr(lang(), "Gespeichert:", "Saved:"), r$saved_at))
          TRUE
        },
        error = function(e) {
          save_failed(TRUE)
          if (inherits(e, "DEL_CONFLICT")) conflict(TRUE)
          if (inherits(e, "DEL_ROUND_CLOSED")) closed(TRUE)
          message(safe_error(e, lang()))
          FALSE
        }
      )
    }
    shiny::observeEvent(input$save, {
      if (shiny::isolate(dirty()) && !shiny::isolate(complete())) {
        return()
      }
      save_now()
    })
    if (is.numeric(autosave_ms) && length(autosave_ms) == 1L && autosave_ms > 0 && !locked) {
      settled <- shiny::debounce(current, autosave_ms)
      shiny::observeEvent(current(), {
        if (awaiting_loaded && !dirty()) awaiting_loaded <<- FALSE
      })
      shiny::observeEvent(settled(), {
        # Save only the settled state the person still sees, never a stale one.
        if (!awaiting_loaded && identical(settled(), shiny::isolate(current())) && !shiny::isolate(conflict()) && !shiny::isolate(closed())) save_now()
      }, ignoreInit = TRUE)
    }
    output$conflict <- shiny::renderUI({
      shiny::req(conflict())
      shiny::actionButton(session$ns("reload"), tr(lang(), "Gespeicherten Stand laden und meine Eingabe verwerfen", "Load the saved response and discard my entry"), class = "btn-outline-danger")
    })
    shiny::observeEvent(input$reload, {
      shiny::req(conflict())
      tryCatch(
        {
          fresh <- stored(call("get_questionnaire", q$enrollment$id)$responses)
          revision(fresh$revision)
          baseline(list(status = fresh$status, value = fresh$value))
          awaiting_loaded <<- !identical(shiny::isolate(current()), list(status = fresh$status, value = fresh$value))
          answered(fresh$status != "not_answered")
          shiny::updateSelectInput(session, "kind", selected = fresh$status)
          if (scale$type == "free_text") shiny::updateTextAreaInput(session, "value", value = fresh$value) else shiny::updateSelectInput(session, "value", selected = fresh$value)
          last_attempt <<- NULL
          save_failed(FALSE)
          conflict(FALSE)
          message(tr(lang(), "Gespeicherter Stand geladen.", "Saved response loaded."))
        },
        error = function(e) message(safe_error(e, lang()))
      )
    })
    list(dirty = dirty, revision = revision, answered = answered, save_now = save_now, conflict = conflict)
  })
}
response_choices <- function(scale, lang) {
  opts <- stats::setNames(c("answered", "not_answered"), c(tr(lang, "Antwort geben", "Give a response"), tr(lang, "Unbeantwortet", "Unanswered")))
  missing <- unlist(scale$missing_options)
  labels <- tr(lang, c(unable_to_judge = "Kann ich nicht beurteilen", abstained = "Enthaltung", not_applicable = "Nicht zutreffend"), c(unable_to_judge = "Unable to judge", abstained = "Abstain", not_applicable = "Not applicable"))
  c(opts, stats::setNames(missing, labels[missing]))
}
