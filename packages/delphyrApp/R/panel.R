panel_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::tags$div(style = "display:none", shiny::textOutput(ns("visible"))),
    shiny::conditionalPanel(
      condition = sprintf("output['%s'] === 'yes'", ns("visible")),
      shiny::tags$section(
        class = "del-sheet", shiny::uiOutput(ns("heading")),
        shiny::selectInput(ns("enrollment"), "Runde", character()),
        shiny::actionButton(ns("load"), "Runde laden"), status_ui(ns("status")),
        shiny::uiOutput(ns("questionnaire"))
      )
    )
  )
}
panel_server <- function(id, study, lang, call, feedback_available = FALSE, capabilities_available = FALSE) {
  shiny::moduleServer(id, function(input, output, session) {
    visible <- shiny::reactiveVal(!capabilities_available)
    output$visible <- shiny::renderText(if (visible()) "yes" else "no")
    shiny::outputOptions(output, "visible", suspendWhenHidden = FALSE)
    q <- shiny::reactiveVal(NULL)
    editors <- shiny::reactiveVal(list())
    status <- shiny::reactiveVal("")
    receipt <- shiny::reactiveVal(NULL)
    generation <- 0L
    output$heading <- shiny::renderUI(shiny::tags$h2(tr(lang(), "Meine Teilnahme", "My participation")))
    output$status <- shiny::renderText(status())
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
            mods[[i]] <- rating_server(mid, z, z$items[i, , drop = FALSE], lang, call)
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
        shiny::tags$p(class = "del-note", shiny::textOutput(ns("save_note"))),
        lapply(z$module_ids, function(x) rating_ui(ns(x))),
        shiny::uiOutput(ns("progress")),
        shiny::checkboxInput(ns("confirm"), tr(l, "Ich habe meine Antworten gepr\u00fcft. Die Abgabe beendet die Bearbeitung.", "I reviewed my answers. Submission ends editing."), FALSE),
        shiny::actionButton(ns("submit"), tr(l, "Verbindlich abgeben", "Submit final responses"), class = "btn-primary"),
        status_ui(ns("receipt"))
      )
    })
    output$round_heading <- shiny::renderText({
      shiny::req(q())
      paste(tr(lang(), "Runde", "Round"), q()$round$number)
    })
    output$information_label <- shiny::renderText(tr(lang(), "Studieninformation", "Study information"))
    output$save_note <- shiny::renderText(tr(lang(), "Jedes Bewertungsfeld einzeln speichern. Keine automatische Speicherung.", "Save each response field explicitly. Saving is not automatic."))
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
      n <- sum(vapply(a, function(x) x$answered(), logical(1)))
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
      if (dirty() || !isTRUE(input$confirm)) {
        status(tr(lang(), "Zuerst alle \u00c4nderungen speichern und die Abgabe best\u00e4tigen.", "Save all changes and confirm submission first."))
        return()
      }
      a <- editors()
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
    list(dirty = dirty, questionnaire = q, receipt = receipt)
  })
}
rating_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tags$section(
    class = "del-item", shiny::uiOutput(ns("title")), shiny::uiOutput(ns("prior")), shiny::tableOutput(ns("feedback")), shiny::uiOutput(ns("form")),
    shiny::actionButton(ns("save"), "Antwort speichern / Save response"), status_ui(ns("status"))
  )
}
rating_server <- function(id, q, item, lang, call) {
  shiny::moduleServer(id, function(input, output, session) {
    scale <- q$protocol$instrument$scales[[item$scale_code]]
    old <- q$responses[q$responses$round_item_id == item$id, , drop = FALSE]
    revision <- shiny::reactiveVal(if (nrow(old)) old$revision[1] else 0L)
    old_status <- if (nrow(old)) old$status[1] else "not_answered"
    old_value <- if (nrow(old) && old_status == "answered") {
      if (scale$type == "free_text") old$value_text[1] else as.character(old$value_int[1])
    } else {
      ""
    }
    baseline <- shiny::reactiveVal(list(status = old_status, value = old_value))
    message <- shiny::reactiveVal("")
    answered <- shiny::reactiveVal(old_status != "not_answered")
    output$title <- shiny::renderUI({
      texts <- jsonlite::fromJSON(item$texts)
      text <- texts[[lang()]]
      if (is.null(text)) text <- texts[[1]]
      shiny::tags$h3(text, shiny::tags$small(paste0(" (", if (item$required) tr(lang(), "erforderlich", "required") else tr(lang(), "optional", "optional"), ")")))
    })
    output$prior <- shiny::renderUI({
      f <- q$feedback
      shiny::req(f)
      own <- f$own
      own <- own[own$item_code == item$item_code & own$dimension_code == item$dimension_code, , drop = FALSE]
      shiny::tagList(
        shiny::tags$p(tr(lang(), "Freigegebenes Feedback der Vorrunde:", "Released previous-round feedback:")),
        if (nrow(own)) shiny::tags$p(paste(tr(lang(), "Ihre vorherige Antwort:", "Your previous response:"), own$answer_status, own$value_integer, own$value_text)),
        if (nrow(own) && any(own$item_version != item$item_version)) shiny::tags$p(tr(lang(), "Der Wortlaut wurde ge\u00e4ndert. Bewertungen sind nicht unmittelbar vergleichbar.", "The wording changed. Ratings are not directly comparable."))
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
    output$form <- shiny::renderUI({
      ns <- session$ns
      l <- shiny::isolate(lang())
      opts <- response_choices(scale, l)

      shiny::tags$fieldset(
        disabled = if (identical(q$enrollment$state, "submitted")) "disabled" else NULL, shiny::selectInput(ns("kind"), tr(l, "Antworttyp", "Response type"), opts, selected = old_status),
        if (scale$type == "free_text") {
          shiny::textAreaInput(ns("value"), tr(l, "Antworttext", "Response text"), value = old_value, width = "100%")
        } else {
          shiny::selectInput(ns("value"), tr(l, "Bewertung", "Rating"), c(stats::setNames("", tr(l, "Bitte w\u00e4hlen", "Choose a rating")), stats::setNames(as.character(unlist(scale$values)), as.character(unlist(scale$values)))), selected = old_value)
        },
        if (!is.null(scale$anchors)) shiny::tags$p(class = "del-note", paste(names(scale$anchors), unlist(scale$anchors), sep = ": ", collapse = "; "))
      )
    })
    shiny::observeEvent(lang(), {
      shiny::updateSelectInput(session, "kind", label = tr(lang(), "Antworttyp", "Response type"), choices = response_choices(scale, lang()), selected = if (is.null(input$kind)) old_status else input$kind)
      if (scale$type == "free_text") {
        shiny::updateTextAreaInput(session, "value", label = tr(lang(), "Antworttext", "Response text"))
      } else {
        shiny::updateSelectInput(session, "value", label = tr(lang(), "Bewertung", "Rating"), choices = c(stats::setNames("", tr(lang(), "Bitte w\u00e4hlen", "Choose a rating")), stats::setNames(as.character(unlist(scale$values)), as.character(unlist(scale$values)))), selected = if (is.null(input$value)) old_value else input$value)
      }
      shiny::updateActionButton(session, "save", label = tr(lang(), "Antwort speichern", "Save response"))
    })
    current <- shiny::reactive({
      list(status = if (is.null(input$kind)) old_status else input$kind, value = if (is.null(input$value)) old_value else input$value)
    })
    dirty <- shiny::reactive(!identical(current(), baseline()))
    output$status <- shiny::renderText(if (dirty()) paste(tr(lang(), "Ungespeicherte \u00c4nderung.", "Unsaved change."), message()) else if (nzchar(message())) message() else if (revision() > 0) tr(lang(), "Gespeicherter Stand", "Saved response") else tr(lang(), "Noch nicht gespeichert", "Not yet saved"))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    shiny::observeEvent(input$save, {
      a <- current()
      value <- if (a$status != "answered") NULL else if (scale$type == "free_text") a$value else suppressWarnings(as.numeric(a$value))
      message(tr(lang(), "Wird gespeichert \u2026", "Saving \u2026"))
      tryCatch(
        {
          r <- call("save_response", q$enrollment$id, item$id, list(value = value, status = a$status), revision(), command_id())
          revision(r$revision)
          baseline(a)
          answered(a$status != "not_answered")
          message(paste(tr(lang(), "Gespeichert:", "Saved:"), r$saved_at))
        },
        error = function(e) message(safe_error(e, lang()))
      )
    })
    list(dirty = dirty, revision = revision, answered = answered)
  })
}
response_choices <- function(scale, lang) {
  opts <- stats::setNames(c("answered", "not_answered"), c(tr(lang, "Antwort geben", "Give a response"), tr(lang, "Unbeantwortet", "Unanswered")))
  missing <- unlist(scale$missing_options)
  labels <- if (identical(lang, "en")) c(unable_to_judge = "Unable to judge", abstained = "Abstain", not_applicable = "Not applicable") else c(unable_to_judge = "Kann ich nicht beurteilen", abstained = "Enthaltung", not_applicable = "Nicht zutreffend")
  c(opts, stats::setNames(missing, labels[missing]))
}
