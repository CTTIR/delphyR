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
panel_server <- function(id, study, lang, call, feedback_available = FALSE, capabilities_available = FALSE, withdrawal_available = FALSE, autosave_ms = 1500, feedback_download_available = FALSE, block_fields = 10L) {
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
        for (x in shiny::isolate(editors())) x$destroy()
        editors(list())
        view(NULL)
        known(NULL)
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
          shiny::updateSelectInput(session, "enrollment", label = tr(lang(), "Runde", "Round"), choices = list_choices(x$id, paste(tr(lang(), "Runde", "Round"), x$number, "\u00b7", state_label(x$round_state, lang()))), selected = if (length(input$enrollment) == 1L && input$enrollment %in% x$id) input$enrollment else current_enrollment(x))
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
    # A long instrument is shown in blocks. Only the fields of the block on
    # screen have live controls; what is known about every other field is the
    # state the server last confirmed to this session.
    blocks <- list()
    slots <- 0L
    view <- shiny::reactiveVal(NULL)
    known <- shiny::reactiveVal(NULL)
    remember <- function(z) {
      found <- match(z$items$id, z$responses$round_item_id)
      known(data.frame(
        id = z$items$id, revision = ifelse(is.na(found), 0L, as.integer(z$responses$revision[found])),
        status = ifelse(is.na(found), "not_answered", as.character(z$responses$status[found])), stringsAsFactors = FALSE
      ))
    }
    saved <- function(id, revision, status) {
      k <- shiny::isolate(known())
      k$revision[k$id == id] <- as.integer(revision)
      k$status[k$id == id] <- status
      known(k)
    }
    # Fields shown one after another in the same place on the page share its
    # outputs, so that a long questionnaire never accumulates them. The
    # controls of a field keep an identifier of their own: an entry can never
    # reach the field that follows it in that place.
    place <- function(slot) {
      name <- function(x) paste0("slot_", slot, "-", x)
      list(
        define = function(x, render) output[[name(x)]] <- render,
        options = function(x, ...) shiny::outputOptions(output, name(x), ...), id = function(x) session$ns(name(x))
      )
    }
    # Pending complete answers are saved before the block on screen is left.
    settle <- function() {
      for (x in shiny::isolate(editors())) if (shiny::isolate(x$dirty()) && is.function(x$save_now)) x$save_now()
      !shiny::isolate(dirty())
    }
    show_block <- function(index, z) {
      for (x in shiny::isolate(editors())) x$destroy()
      generation <<- generation + 1L
      rows <- blocks[[index]]
      ids <- paste0("item_", generation, "_", rows)
      editors(lapply(seq_along(rows), function(slot) {
        rating_server(ids[slot], z, z$items[rows[slot], , drop = FALSE], lang, call, autosave_ms = autosave_ms, place = place(slot), on_saved = saved)
      }))
      # A place the shorter block does not use holds nothing of the previous one.
      for (slot in seq_len(slots)[seq_len(slots) > length(rows)]) for (x in rating_outputs) output[[paste0("slot_", slot, "-", x)]] <- NULL
      slots <<- length(rows)
      remember(z)
      view(list(index = index, ids = ids, rows = rows))
    }
    go <- function(index) {
      z <- shiny::isolate(q())
      if (is.null(z) || length(index) != 1L || is.na(index) || index < 1L || index > length(blocks)) {
        return(invisible(FALSE))
      }
      if (!settle()) {
        status(tr(lang(), "Bitte \u00c4nderungen in diesem Block zuerst speichern oder vervollst\u00e4ndigen.", "Save or complete your changes in this block first."))
        return(invisible(FALSE))
      }
      tryCatch(
        {
          # The block is opened with the state the server holds now.
          fresh <- call("get_questionnaire", z$enrollment$id)
          z[c("responses", "enrollment", "receipt")] <- fresh[c("responses", "enrollment", "receipt")]
          show_block(index, z)
          status("")
          # After the block was sent: the heading that receives the focus is
          # the one of the new block, not the one it replaces.
          session$onFlushed(function() session$sendCustomMessage("delphyr-focus", session$ns("block_heading")), once = TRUE)
          invisible(TRUE)
        },
        error = function(e) {
          status(safe_error(e, lang()))
          invisible(FALSE)
        }
      )
    }
    shiny::observeEvent(input$block_previous, go(view()$index - 1L))
    shiny::observeEvent(input$block_next, go(view()$index + 1L))
    shiny::observeEvent(input$block_go, go(suppressWarnings(as.integer(input$block_choice))))
    shiny::observeEvent(input$load, {
      shiny::req(input$enrollment)
      if (!settle()) {
        status(tr(lang(), "Bitte \u00c4nderungen zuerst speichern. Die ge\u00f6ffnete Runde bleibt erhalten.", "Save your changes first. The current round stays open."))
        return()
      }
      tryCatch(
        {
          z <- call("get_questionnaire", input$enrollment)
          if (feedback_available) z$feedback <- call("get_feedback", input$enrollment)
          blocks <<- question_blocks(z$items, block_fields)
          # Work resumes at the first block that still has an open field.
          open <- !z$items$id %in% z$responses$round_item_id[z$responses$status != "not_answered"]
          resume <- any(open) && !isTRUE(z$enrollment$state %in% c("submitted", "withdrawn"))
          show_block(if (resume) which(vapply(blocks, function(rows) any(open[rows]), logical(1)))[1] else 1L, z)
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
        shiny::uiOutput(ns("round_feedback")),
        if (length(blocks) > 1L) {
          shiny::tags$nav(
            class = "del-blocknav", `aria-label` = tr(l, "Bl\u00f6cke dieser Runde", "Blocks of this round"),
            shiny::selectInput(ns("block_choice"), tr(l, "Block", "Block"), block_labels(z$items, blocks, l), selected = shiny::isolate(view())$index, selectize = FALSE),
            shiny::actionButton(ns("block_go"), tr(l, "Block anzeigen", "Show block"))
          )
        },
        shiny::uiOutput(ns("block")),
        if (length(blocks) > 1L) {
          shiny::tags$div(
            class = "del-actions", shiny::actionButton(ns("block_previous"), tr(l, "Vorheriger Block", "Previous block")),
            shiny::actionButton(ns("block_next"), tr(l, "N\u00e4chster Block", "Next block"))
          )
        },
        shiny::tags$div(class = "del-progress", shiny::uiOutput(ns("progress")), shiny::uiOutput(ns("overview"))),
        shiny::checkboxInput(ns("confirm"), tr(l, "Ich habe meine Antworten gepr\u00fcft. Die Abgabe beendet die Bearbeitung.", "I reviewed my answers. Submission ends editing."), FALSE),
        shiny::actionButton(ns("submit"), tr(l, "Verbindlich abgeben", "Submit final responses"), class = "btn-primary"),
        status_ui(ns("receipt"))
      )
    })
    output$block <- shiny::renderUI({
      v <- view()
      shiny::req(v)
      ns <- session$ns
      shiny::tagList(
        if (length(blocks) > 1L) shiny::tags$h4(id = ns("block_heading"), tabindex = "-1", shiny::textOutput(ns("block_title"), inline = TRUE)),
        lapply(seq_along(v$ids), function(slot) rating_ui(ns(v$ids[slot]), ns(paste0("slot_", slot))))
      )
    })
    output$block_title <- shiny::renderText({
      v <- view()
      z <- q()
      shiny::req(v, z)
      number <- question_numbers(z$items)
      paste(
        tr(lang(), "Block", "Block"), v$index, tr(lang(), "von", "of"), length(blocks), "\u00b7", tr(lang(), "Fragen", "Questions"),
        paste0(min(number[v$rows]), "\u2013", max(number[v$rows])), tr(lang(), "von", "of"), max(number)
      )
    })
    # The list of blocks follows the block on screen and the language. Which
    # blocks still have open fields is stated in the overview before submission.
    shiny::observeEvent(list(lang(), view()), {
      z <- q()
      v <- view()
      shiny::req(z, v, length(blocks) > 1L)
      shiny::updateSelectInput(session, "block_choice", label = tr(lang(), "Block", "Block"), choices = block_labels(z$items, blocks, lang()), selected = v$index)
      shiny::updateActionButton(session, "block_go", label = tr(lang(), "Block anzeigen", "Show block"))
      shiny::updateActionButton(session, "block_previous", label = tr(lang(), "Vorheriger Block", "Previous block"))
      shiny::updateActionButton(session, "block_next", label = tr(lang(), "N\u00e4chster Block", "Next block"))
    })
    # Released qualitative content that is not attached to a displayed item,
    # and the note that accompanies a corrected feedback.
    output$round_feedback <- shiny::renderUI({
      z <- q()
      shiny::req(z, z$feedback)
      general <- qualitative_for(z$feedback$qualitative, NULL, unique(z$items$item_code))
      note <- z$feedback$correction
      if (is.null(note) && !nrow(general)) {
        return(NULL)
      }
      shiny::tags$div(
        class = "del-feedback",
        if (!is.null(note)) shiny::tags$p(class = "del-banner", paste(tr(lang(), "Dieses Feedback wurde korrigiert.", "This feedback was corrected."), note$participant_note)),
        if (nrow(general)) shiny::tagList(shiny::tags$h4(tr(lang(), "Freigegebene Beitr\u00e4ge der Vorrunde", "Released contributions of the previous round")), qualitative_list(general, lang()))
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
      v <- view()
      k <- known()
      shiny::req(q(), v, k)
      pending <- v$rows[vapply(editors(), function(x) isTRUE(x$dirty()), logical(1))]
      n <- sum(k$status != "not_answered" & !seq_len(nrow(k)) %in% pending)
      shiny::tags$p(paste(n, "/", nrow(k), tr(lang(), "Bewertungsfelder best\u00e4tigt gespeichert.", "response fields confirmed saved.")))
    })
    # Before submission: what is answered, deliberately not rated and open.
    output$overview <- shiny::renderUI({
      z <- q()
      k <- known()
      shiny::req(z, k)
      open <- k$status == "not_answered"
      required_open <- open & as.logical(z$items$required)
      l <- lang()
      shiny::tagList(
        shiny::tags$p(class = "del-note", paste0(
          tr(l, "Beantwortet:", "Answered:"), " ", sum(k$status == "answered"), " \u00b7 ", tr(l, "Sonderantwort:", "Special response:"), " ", sum(!open & k$status != "answered"),
          " \u00b7 ", tr(l, "Offen:", "Open:"), " ", sum(open), " \u00b7 ", tr(l, "davon erforderlich:", "of which required:"), " ", sum(required_open)
        )),
        if (any(open) && length(blocks) > 1L) {
          shiny::tags$p(class = "del-note", paste(tr(l, "Offene Felder in Block:", "Open fields in block:"), paste(which(vapply(blocks, function(rows) any(open[rows]), logical(1))), collapse = ", ")))
        },
        if (any(required_open) && length(blocks) > 1L) {
          shiny::tags$p(class = "del-note", paste(tr(l, "Erforderliche Felder sind offen in Block:", "Required fields are open in block:"), paste(which(vapply(blocks, function(rows) any(required_open[rows]), logical(1))), collapse = ", ")))
        }
      )
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
      # Pending complete answers are saved first; submission never outruns a save.
      if (!settle() || !isTRUE(input$confirm)) {
        status(tr(lang(), "Zuerst alle \u00c4nderungen speichern und die Abgabe best\u00e4tigen.", "Save all changes and confirm submission first."))
        return()
      }
      k <- known()
      required_open <- k$status == "not_answered" & as.logical(z$items$required)
      if (any(required_open)) {
        # The first block with an open required field is shown.
        target <- which(vapply(blocks, function(rows) any(required_open[rows]), logical(1)))[1]
        if (length(blocks) > 1L && !identical(target, view()$index)) go(target)
        status(tr(lang(), "Erforderliche Bewertungsfelder sind noch offen. Sie stehen in der \u00dcbersicht vor der Abgabe.", "Required response fields are still open. They are named in the overview above the submit button."))
        return()
      }
      # The submission names exactly the revisions this session saw confirmed.
      revs <- stats::setNames(k$revision, k$id)
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
# Fields of one item stay in one block; a block holds at most `block_fields`
# response fields unless a single item has more.
# The round a person is expected to work on: the latest open round that is
# not yet submitted or withdrawn; without one, the latest round.
current_enrollment <- function(x) {
  if (!nrow(x)) {
    return(NULL)
  }
  number <- if (is.null(x$number)) seq_len(nrow(x)) else x$number
  due <- if (is.null(x$state) || is.null(x$round_state)) rep(FALSE, nrow(x)) else x$round_state == "open" & !x$state %in% c("submitted", "withdrawn")
  rows <- if (any(due)) which(due) else seq_len(nrow(x))
  x$id[rows[which.max(number[rows])]]
}
question_blocks <- function(items, block_fields) {
  codes <- if (is.null(items$item_code)) as.character(seq_len(nrow(items))) else as.character(items$item_code)
  runs <- rle(codes)
  block <- integer(length(runs$lengths))
  current <- 1L
  used <- 0L
  for (i in seq_along(block)) {
    if (used > 0L && used + runs$lengths[i] > block_fields) {
      current <- current + 1L
      used <- 0L
    }
    block[i] <- current
    used <- used + runs$lengths[i]
  }
  unname(split(seq_len(nrow(items)), rep(block, runs$lengths)))
}
# Questions are numbered in their order; the fields of one item share a number.
question_numbers <- function(items) {
  codes <- if (is.null(items$item_code)) as.character(seq_len(nrow(items))) else as.character(items$item_code)
  match(codes, unique(codes))
}
block_labels <- function(items, blocks, lang) {
  number <- question_numbers(items)
  labels <- vapply(seq_along(blocks), function(i) {
    rows <- blocks[[i]]
    paste0(tr(lang, "Block", "Block"), " ", i, " \u00b7 ", tr(lang, "Fragen", "Questions"), " ", min(number[rows]), "\u2013", max(number[rows]))
  }, character(1))
  stats::setNames(as.character(seq_along(blocks)), labels)
}
rating_outputs <- c("title", "form", "save_status", "status", "conflict")
# `outputs` names the place of the field on the page; the controls carry `id`.
rating_ui <- function(id, outputs = id) {
  ns <- shiny::NS(id)
  out <- shiny::NS(outputs)
  shiny::tags$section(
    class = "del-item", shiny::uiOutput(out("title")), shiny::uiOutput(out("form")),
    shiny::actionButton(ns("save"), "Save now", class = "btn-primary"), shiny::uiOutput(out("save_status")), shiny::uiOutput(out("conflict"))
  )
}
rating_server <- function(id, q, item, lang, call, autosave_ms = 1500, place = NULL, on_saved = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    # Without a place the field renders into outputs of its own.
    define <- if (is.null(place)) function(name, render) output[[name]] <- render else place$define
    output_id <- if (is.null(place)) session$ns else place$id
    # Observers are collected so that they end when the field leaves the page.
    observers <- list()
    module <- environment()
    observe_event <- function(...) observers[[length(observers) + 1L]] <<- shiny::observeEvent(..., event.env = module, handler.env = module)
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
    define("title", shiny::renderUI({
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
        if (fallback) shiny::tags$p(class = "del-note", paste(tr(lang(), "Keine genehmigte \u00dcbersetzung verf\u00fcgbar; angezeigte Sprache:", "No approved translation is available; displayed language:"), content_language)),
        # Released feedback of the previous round stands beside its item.
        if (!is.null(q$feedback)) shiny::tags$div(id = output_id("prior"), prior()),
        if (!is.null(q$feedback)) shiny::tags$div(id = output_id("feedback"), feedback_table(q$feedback$aggregate$results, item))
      )
    }))
    prior <- function() {
      f <- q$feedback
      own <- f$own
      own <- own[own$item_code == item$item_code & own$dimension_code == item$dimension_code, , drop = FALSE]
      shiny::tagList(
        shiny::tags$p(tr(lang(), "Freigegebenes Feedback der Vorrunde:", "Released previous-round feedback:")),
        if (nrow(own)) shiny::tags$p(paste(tr(lang(), "Ihre vorherige Antwort:", "Your previous response:"), own$answer_status, own$value_integer, own$value_text)),
        qualitative_list(qualitative_for(f$qualitative, item$item_code), lang()),
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
    }
    rating_choices <- function(l) c(stats::setNames("", tr(l, "Bitte w\u00e4hlen", "Choose a rating")), stats::setNames(as.character(unlist(scale$values)), as.character(unlist(scale$values))))
    define("form", shiny::renderUI({
      ns <- session$ns
      l <- shiny::isolate(lang())
      opts <- response_choices(scale, l)

      shiny::tags$fieldset(
        disabled = if (locked) "disabled" else NULL, shiny::selectInput(ns("kind"), tr(l, "Antworttyp", "Response type"), opts, selected = old_status, selectize = FALSE),
        if (scale$type == "free_text") {
          shiny::textAreaInput(ns("value"), tr(l, "Antworttext", "Response text"), value = old_value, width = "100%")
        } else {
          shiny::selectInput(ns("value"), tr(l, "Bewertung", "Rating"), rating_choices(l), selected = old_value, selectize = FALSE)
        },
        if (!is.null(scale$anchors)) shiny::tags$p(class = "del-note", paste(names(scale$anchors), unlist(scale$anchors), sep = ": ", collapse = "; "))
      )
    }))
    observe_event(lang(), {
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
    observe_event(input$value, {
      if (nzchar(input$value) && !is.null(input$kind) && input$kind != "answered") shiny::updateSelectInput(session, "kind", selected = "answered")
    })
    observe_event(input$kind, {
      if (input$kind != "answered" && !is.null(input$value) && nzchar(input$value)) {
        if (scale$type == "free_text") shiny::updateTextAreaInput(session, "value", value = "") else shiny::updateSelectInput(session, "value", selected = "")
      }
    })
    # Read by everything that depends on the controls of this field. When the
    # field leaves the page it is switched off once, which releases what the
    # session still holds of it.
    alive <- shiny::reactiveVal(TRUE)
    current <- shiny::reactive({
      alive()
      status <- if (is.null(input$kind)) old_status else input$kind
      value <- if (is.null(input$value)) old_value else input$value
      # A value shown beside a special response is never part of the answer.
      list(status = status, value = if (identical(status, "answered")) value else "")
    })
    dirty <- shiny::reactive(!identical(current(), baseline()))
    complete <- shiny::reactive(current()$status != "answered" || nzchar(trimws(current()$value)))
    define("save_status", shiny::renderUI({
      tone <- if (dirty() || save_failed() || conflict()) "attention" else if (revision() > 0) "saved" else "neutral"
      shiny::tags$div(
        class = paste("del-status", paste0("del-status--", tone)),
        role = "status", `aria-live` = "polite", shiny::textOutput(output_id("status"))
      )
    }))
    define("status", shiny::renderText({
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
    }))
    if (is.null(place)) shiny::outputOptions(output, "status", suspendWhenHidden = FALSE) else place$options("status", suspendWhenHidden = FALSE)
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
          if (is.function(on_saved)) on_saved(item$id, r$revision, a$status)
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
    observe_event(input$save, {
      if (shiny::isolate(dirty()) && !shiny::isolate(complete())) {
        return()
      }
      save_now()
    })
    if (is.numeric(autosave_ms) && length(autosave_ms) == 1L && autosave_ms > 0 && !locked) {
      # The pause before an automatic save: every change of the entry starts
      # it again, and when it has passed the entry on screen is saved. It is
      # built from observers of this field, so that it ends with the field.
      now <- function() if (is.function(session$.now)) session$.now() else as.numeric(Sys.time()) * 1000
      due <- shiny::reactiveVal(NULL)
      observe_event(current(), {
        if (awaiting_loaded && !dirty()) awaiting_loaded <<- FALSE
        due(now() + autosave_ms)
      }, ignoreInit = TRUE)
      observers[[length(observers) + 1L]] <- shiny::observe({
        when <- due()
        if (is.null(when)) {
          return()
        }
        left <- when - now()
        if (left > 0) {
          shiny::invalidateLater(left)
          return()
        }
        shiny::isolate(due(NULL))
        # Only the state the person still sees is saved, never a stale one.
        if (!awaiting_loaded && !shiny::isolate(conflict()) && !shiny::isolate(closed())) save_now()
      })
    }
    define("conflict", shiny::renderUI({
      shiny::req(conflict())
      shiny::actionButton(session$ns("reload"), tr(lang(), "Gespeicherten Stand laden und meine Eingabe verwerfen", "Load the saved response and discard my entry"), class = "btn-outline-danger")
    }))
    observe_event(input$reload, {
      shiny::req(conflict())
      tryCatch(
        {
          fresh <- stored(call("get_questionnaire", q$enrollment$id)$responses)
          revision(fresh$revision)
          if (is.function(on_saved)) on_saved(item$id, fresh$revision, fresh$status)
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
    # When another field takes this place, nothing of this one reacts any more.
    destroy <- function() {
      for (observer in observers) observer$destroy()
      observers <<- list()
      shiny::isolate(alive(FALSE))
      invisible(TRUE)
    }
    list(dirty = dirty, revision = revision, answered = answered, save_now = save_now, conflict = conflict, destroy = destroy)
  })
}
# The released panel results of one field as a table; numbers are shown with
# two decimals, as the released feedback states them.
feedback_table <- function(results, item) {
  if (!is.data.frame(results) || !nrow(results)) {
    return(NULL)
  }
  r <- results[results$item_code == item$item_code & results$dimension_code == item$dimension_code, , drop = FALSE]
  if (!nrow(r)) {
    return(NULL)
  }
  cell <- function(v) {
    if (is.list(v)) v <- paste(unlist(v), collapse = ", ")
    if (is.na(v)) "NA" else if (is.numeric(v) && !is.integer(v)) formatC(v, format = "f", digits = 2) else as.character(v)
  }
  shiny::tags$table(
    class = "table shiny-table table-striped spacing-s",
    shiny::tags$thead(shiny::tags$tr(lapply(names(r), function(name) shiny::tags$th(scope = "col", name)))),
    shiny::tags$tbody(lapply(seq_len(nrow(r)), function(i) shiny::tags$tr(lapply(names(r), function(name) shiny::tags$td(cell(r[[name]][i]))))))
  )
}
response_choices <- function(scale, lang) {
  opts <- stats::setNames(c("answered", "not_answered"), c(tr(lang, "Antwort geben", "Give a response"), tr(lang, "Unbeantwortet", "Unanswered")))
  missing <- unlist(scale$missing_options)
  labels <- tr(lang, c(unable_to_judge = "Kann ich nicht beurteilen", abstained = "Enthaltung", not_applicable = "Nicht zutreffend"), c(unable_to_judge = "Unable to judge", abstained = "Abstain", not_applicable = "Not applicable"))
  c(opts, stats::setNames(missing, labels[missing]))
}

# Released qualitative entries for one item, or (item NULL) those attached to
# no item displayed in this round.
qualitative_for <- function(entries, item, displayed = character()) {
  if (!is.data.frame(entries) || !nrow(entries)) {
    return(data.frame(text = character(), kind = character(), source_ref = character(), stringsAsFactors = FALSE))
  }
  codes <- lapply(entries$item_codes, function(x) as.character(unlist(x)))
  keep <- if (is.null(item)) vapply(codes, function(x) !any(x %in% displayed), logical(1)) else vapply(codes, function(x) item %in% x, logical(1))
  entries[keep, c("text", "kind", "source_ref"), drop = FALSE]
}
# A summary is labelled as a summary; it is never presented as a quotation.
qualitative_list <- function(entries, lang) {
  if (!nrow(entries)) {
    return(NULL)
  }
  shiny::tags$ul(class = "del-qualitative", lapply(seq_len(nrow(entries)), function(i) {
    shiny::tags$li(
      shiny::tags$span(class = "del-note", if (identical(entries$kind[i], "summary")) tr(lang, "Moderierte Zusammenfassung (kein Zitat):", "Moderated summary (not a quotation):") else tr(lang, "Redigierter Beitrag:", "Redacted contribution:")),
      " ", entries$text[i]
    )
  }))
}
