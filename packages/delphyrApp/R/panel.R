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
        shiny::tags$div(class = "del-actions", shiny::actionButton(ns("load"), "Load round")),
        status_ui(ns("status")),
        shiny::uiOutput(ns("questionnaire")), shiny::uiOutput(ns("withdrawal"))
      )
    )
  )
}
panel_server <- function(id, study, lang, call, feedback_available = FALSE, capabilities_available = FALSE, withdrawal_available = FALSE, autosave_ms = 1500, feedback_download_available = FALSE, block_fields = 10L) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    automatic <- is.numeric(autosave_ms) && length(autosave_ms) == 1L && autosave_ms > 0
    visible <- shiny::reactiveVal(!capabilities_available)
    output$visible <- shiny::renderText(if (visible()) "yes" else "no")
    shiny::outputOptions(output, "visible", suspendWhenHidden = FALSE)
    # The rounds of the selected study a member may see; a round that has
    # not been opened is never offered.
    rounds <- shiny::reactiveVal(no_rounds())
    q <- shiny::reactiveVal(NULL)
    editors <- shiny::reactiveVal(list())
    # A status is a function of the interface language, or a text whose
    # registered prefix is translated again when the language changes.
    status <- shiny::reactiveVal("")
    receipt <- shiny::reactiveVal(NULL)
    # Set when the server refuses saving in the round on screen: "closed"
    # (round closed or deadline passed), "ended" (enrollment submitted or
    # ended elsewhere) or "submitted" (confirmed here, view not reloaded).
    halted <- shiny::reactiveVal(NULL)
    # The outcome of the last submission attempt, shown beside its button.
    submission <- shiny::reactiveVal(NULL)
    declined <- shiny::reactiveVal(FALSE)
    withdrawn <- shiny::reactiveVal(FALSE)
    # The enrollment whose consent controls are on screen.
    consent_for <- NULL
    generation <- 0L
    dirty <- shiny::reactive(any(vapply(editors(), function(x) isTRUE(x$dirty()), logical(1))))
    output$status <- shiny::renderText({
      s <- status()
      if (is.function(s)) s(lang()) else localize_status(s, lang())
    })
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    output$heading <- shiny::renderUI(shiny::tags$h2(tr(lang(), "Meine Teilnahme", "My participation")))
    # A long instrument is shown in blocks. Only the fields of the block on
    # screen have live controls; what is known about every other field is the
    # state the server last confirmed to this session.
    blocks <- list()
    slots <- 0L
    cards <- 0L
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
    halt <- function(reason) if (is.null(shiny::isolate(halted()))) halted(reason)
    # Fields shown one after another in the same place on the page share its
    # outputs, so that a long questionnaire never accumulates them. The
    # controls of a field keep an identifier of their own: an entry can never
    # reach the field that follows it in that place.
    place <- function(slot) {
      force(slot)
      name <- function(x) paste0("slot_", slot, "-", x)
      list(
        define = function(x, render) output[[name(x)]] <- render,
        options = function(x, ...) shiny::outputOptions(output, name(x), ...), id = function(x) session$ns(name(x))
      )
    }
    # Pending complete answers are saved before the block on screen is left.
    # In a round that no longer accepts answers nothing can be saved, and
    # nothing holds the person in the block.
    settle <- function() {
      if (!is.null(shiny::isolate(halted()))) {
        return(TRUE)
      }
      for (x in shiny::isolate(editors())) if (shiny::isolate(x$dirty()) && is.function(x$save_now)) x$save_now()
      !is.null(shiny::isolate(halted())) || !shiny::isolate(dirty())
    }
    clear <- function() {
      for (x in shiny::isolate(editors())) x$destroy()
      editors(list())
      view(NULL)
      known(NULL)
      q(NULL)
      receipt(NULL)
      halted(NULL)
      submission(NULL)
      declined(FALSE)
      consent_for <<- NULL
      blocks <<- list()
    }
    # One status line per statement: the states of its fields in one place.
    define_card <- function(k, members) {
      force(k)
      force(members)
      name <- function(x) paste0("card_", k, "-", x)
      output[[name("line")]] <- shiny::renderUI({
        tone <- card_tone(lapply(members, function(x) x$report()))
        shiny::tags$div(class = paste("del-status", paste0("del-status--", tone)), role = "status", `aria-live` = "polite", shiny::textOutput(ns(name("status"))))
      })
      output[[name("status")]] <- shiny::renderText(card_text(lapply(members, function(x) x$report()), lang()))
      shiny::outputOptions(output, name("status"), suspendWhenHidden = FALSE)
    }
    show_block <- function(index, z) {
      for (x in shiny::isolate(editors())) x$destroy()
      generation <<- generation + 1L
      rows <- blocks[[index]]
      ids <- paste0("item_", generation, "_", rows)
      groups <- statement_cards(item_codes(z$items)[rows])
      made <- vector("list", length(rows))
      for (k in seq_along(groups)) {
        members <- groups[[k]]
        roles <- card_roles(z, rows[members])
        for (j in seq_along(members)) {
          slot <- members[j]
          made[[slot]] <- rating_server(ids[slot], z, z$items[rows[slot], , drop = FALSE], lang, call,
            autosave_ms = autosave_ms, place = place(slot), on_saved = saved, card = roles[[j]], halted = halted, on_halt = halt
          )
        }
      }
      editors(made)
      for (k in seq_along(groups)) define_card(k, made[groups[[k]]])
      # A place the shorter block does not use holds nothing of the previous one.
      for (slot in seq_len(slots)[seq_len(slots) > length(rows)]) for (x in rating_outputs) output[[paste0("slot_", slot, "-", x)]] <- NULL
      for (k in seq_len(cards)[seq_len(cards) > length(groups)]) for (x in card_outputs) output[[paste0("card_", k, "-", x)]] <- NULL
      slots <<- length(rows)
      cards <<- length(groups)
      remember(z)
      view(list(index = index, ids = ids, rows = rows, cards = groups, mode = questionnaire_mode(z)))
    }
    # The questionnaire after a change of its state: the server's view of
    # the round, the enrollment, the consent and the confirmed responses.
    reopen <- function(z) {
      fresh <- tryCatch(call("get_questionnaire", z$enrollment$id), error = function(e) NULL)
      if (is.null(fresh)) {
        return(NULL)
      }
      for (n in intersect(c("round", "responses", "enrollment", "receipt", "consent"), names(fresh))) z[[n]] <- fresh[[n]]
      z
    }
    show_again <- function(z) {
      v <- shiny::isolate(view())
      show_block(if (is.null(v)) 1L else v$index, z)
      q(z)
    }
    go <- function(index, focus = NULL) {
      z <- shiny::isolate(q())
      if (is.null(z) || length(index) != 1L || is.na(index) || index < 1L || index > length(blocks)) {
        return(invisible(FALSE))
      }
      if (!settle()) {
        status(function(l) tr(l, "Bitte \u00c4nderungen in diesem Block zuerst speichern oder vervollst\u00e4ndigen.", "Save or complete your changes in this block first."))
        return(invisible(FALSE))
      }
      l <- shiny::isolate(lang())
      tryCatch(
        {
          # The block is opened with the state the server holds now.
          fresh <- call("get_questionnaire", z$enrollment$id)
          before <- questionnaire_mode(z)
          for (n in intersect(c("round", "responses", "enrollment", "receipt", "consent"), names(fresh))) z[[n]] <- fresh[[n]]
          show_block(index, z)
          # The round, the enrollment or the consent changed elsewhere.
          if (!identical(questionnaire_mode(z), before)) {
            submission(NULL)
            q(z)
          }
          if (is.null(shiny::isolate(halted()))) status("")
          # After the block was sent: the element that receives the focus is
          # the one of the new block, not the one it replaces.
          target <- if (is.null(focus)) ns("block_heading") else focus
          session$onFlushed(function() session$sendCustomMessage("delphyr-focus", target), once = TRUE)
          invisible(TRUE)
        },
        error = function(e) {
          status(safe_error(e, l))
          invisible(FALSE)
        }
      )
    }
    # After a confirmed step only the labels are refreshed; a failure then
    # leaves the list as it is.
    refresh_rounds <- function(keep = NULL, quiet = FALSE) {
      l <- shiny::isolate(lang())
      tryCatch(
        {
          if (capabilities_available) {
            visible("panel" %in% call("get_capabilities", study()))
            if (!shiny::isolate(visible())) {
              rounds(no_rounds())
              return(invisible(FALSE))
            }
          }
          x <- call("list_enrollments", study())
          shown <- participant_rounds(x)
          rounds(shown)
          chosen <- if (length(keep) == 1L && keep %in% shown$id) keep else current_enrollment(shown)
          shiny::updateSelectInput(session, "enrollment", label = tr(l, "Runde", "Round"), choices = round_choices(shown, l), selected = chosen)
          if (!NROW(x)) {
            status(function(l) tr(l, "Keine zugewiesene Runde.", "No assigned round."))
          } else if (!nrow(shown)) {
            status(function(l) tr(l, "Noch keine Runde ge\u00f6ffnet.", "No round has been opened yet."))
          }
          invisible(TRUE)
        },
        error = function(e) {
          if (quiet) {
            return(invisible(FALSE))
          }
          rounds(no_rounds())
          shiny::updateSelectInput(session, "enrollment", choices = character())
          status(safe_error(e, l))
          invisible(FALSE)
        }
      )
    }
    # Another study never shows the questionnaire, the receipts or the
    # withdrawal of the previous one.
    shiny::observeEvent(study(), {
      settle()
      clear()
      withdrawn(FALSE)
      status("")
      refresh_rounds()
    })
    # A change of the interface language only translates; it calls no service
    # and keeps every status and receipt.
    shiny::observeEvent(lang(), {
      l <- lang()
      shiny::updateActionButton(session, "load", label = tr(l, "Runde laden", "Load round"))
      shown <- rounds()
      shiny::updateSelectInput(session, "enrollment", label = tr(l, "Runde", "Round"), choices = round_choices(shown, l), selected = if (length(input$enrollment) == 1L && input$enrollment %in% shown$id) input$enrollment else current_enrollment(shown))
      shiny::updateCheckboxInput(session, "confirm", label = tr(l, "Ich habe meine Antworten gepr\u00fcft. Die Abgabe beendet die Bearbeitung.", "I reviewed my answers. Submission ends editing."))
      shiny::updateActionButton(session, "submit", label = tr(l, "Verbindlich abgeben", "Submit final responses"))
    })
    shiny::observeEvent(input$block_previous, go(view()$index - 1L))
    shiny::observeEvent(input$block_next, go(view()$index + 1L))
    shiny::observeEvent(input$block_go, go(suppressWarnings(as.integer(input$block_choice))))
    shiny::observeEvent(input$load, {
      shiny::req(input$enrollment)
      if (!input$enrollment %in% rounds()$id) {
        return()
      }
      if (!settle()) {
        status(function(l) tr(l, "Bitte \u00c4nderungen zuerst speichern. Die ge\u00f6ffnete Runde bleibt erhalten.", "Save your changes first. The current round stays open."))
        return()
      }
      l <- lang()
      tryCatch(
        {
          z <- prepare_questionnaire(call("get_questionnaire", input$enrollment))
          if (feedback_available) z$feedback <- call("get_feedback", input$enrollment)
          z$previous_items <- earlier_items(z, rounds(), call)
          blocks <<- question_blocks(z$items, block_fields)
          # Work resumes at the first block that still has an open field.
          open <- !z$items$id %in% z$responses$round_item_id[z$responses$status != "not_answered"]
          resume <- any(open) && questionnaire_mode(z) %in% c("open", "consent")
          halted(NULL)
          submission(NULL)
          declined(FALSE)
          receipt(NULL)
          show_block(if (resume) which(vapply(blocks, function(rows) any(open[rows]), logical(1)))[1] else 1L, z)
          q(z)
          status("")
        },
        error = function(e) status(safe_error(e, l))
      )
    })
    output$questionnaire <- shiny::renderUI({
      z <- q()
      shiny::req(z)
      # Interface language changes never recreate response controls.
      l <- shiny::isolate(lang())
      mode <- questionnaire_mode(z)
      shiny::tagList(
        shiny::tags$h3(shiny::textOutput(ns("round_heading"), inline = TRUE)),
        shiny::uiOutput(ns("round_state")),
        shiny::uiOutput(ns("consent_area")),
        shiny::uiOutput(ns("round_feedback")),
        if (mode %in% c("open", "consent")) shiny::tags$p(class = "del-note", shiny::textOutput(ns("save_note"), inline = TRUE)),
        shiny::tags$p(class = "del-note", shiny::textOutput(ns("content_note"), inline = TRUE)),
        if (length(blocks) > 1L) {
          shiny::tags$nav(
            class = "del-blocknav", `aria-label` = tr(l, "Bl\u00f6cke dieser Runde", "Blocks of this round"),
            shiny::selectInput(ns("block_choice"), tr(l, "Block", "Block"), block_labels(z$items, blocks, l), selected = shiny::isolate(view())$index, selectize = FALSE),
            shiny::actionButton(ns("block_go"), tr(l, "Block anzeigen", "Show block"))
          )
        },
        # The statements are shown before consent, but cannot be answered yet.
        if (identical(mode, "consent")) shiny::tags$p(class = "del-note", shiny::textOutput(ns("consent_wait"), inline = TRUE)),
        shiny::uiOutput(ns("block_head")),
        shiny::uiOutput(ns("block")),
        shiny::uiOutput(ns("pager")),
        shiny::uiOutput(ns("review"))
      )
    })
    output$round_heading <- shiny::renderText({
      shiny::req(q())
      paste(tr(lang(), "Runde", "Round"), q()$round$number)
    })
    # Where the round stands: the deadline of an open round, the receipt of a
    # submitted one, or why answers can no longer be saved.
    output$round_state <- shiny::renderUI({
      z <- q()
      shiny::req(z)
      l <- lang()
      mode <- questionnaire_mode(z)
      reason <- halted()
      if (identical(mode, "submitted") || identical(reason, "submitted")) {
        r <- if (is.data.frame(z$receipt) && nrow(z$receipt)) z$receipt[1, , drop = FALSE] else receipt()
        return(shiny::tags$div(
          id = ns("receipt"), class = "del-status del-status--saved", role = "status", tabindex = "-1",
          if (!is.null(r)) {
            shiny::tags$p(sprintf(tr(l, "Abgabe best\u00e4tigt: %s.", "Submission confirmed: %s."), format_moment(r$submitted_at, study_zone(z), l)), " ", tr(l, "Beleg:", "Receipt:"), " ", ref_tag(r$id))
          },
          shiny::tags$p(tr(l, "Ihre Antworten in dieser Runde k\u00f6nnen nicht mehr ge\u00e4ndert werden.", "Your answers in this round can no longer be changed."))
        ))
      }
      if (!is.null(reason)) {
        return(shiny::tags$div(class = "del-status del-status--attention", role = "alert", closed_text(reason, mode, l)))
      }
      if (mode %in% c("closed", "withdrawn")) {
        return(shiny::tags$p(class = "del-note", closed_text(NULL, mode, l)))
      }
      shiny::tags$p(shiny::textOutput(ns("deadline"), inline = TRUE))
    })
    output$deadline <- shiny::renderText({
      z <- q()
      shiny::req(z)
      paste(tr(lang(), "Abgabe bis:", "Submit by:"), format_moment(z$round$deadline, study_zone(z), lang()))
    })
    # Before consent the study information is shown in full and the round
    # cannot be answered; afterwards only the recorded consent and the
    # information in a disclosure remain, without controls.
    output$consent_area <- shiny::renderUI({
      z <- q()
      shiny::req(z, z$consent)
      l <- lang()
      consent <- z$consent
      info <- shiny::tags$p(class = "del-consent", lang = consent$locale, consent$content)
      if (!identical(questionnaire_mode(z), "consent")) {
        consent_for <<- NULL
        return(shiny::tagList(
          if (isTRUE(as.logical(consent$accepted))) shiny::tags$p(consent_text(consent, study_zone(z), l)),
          shiny::tags$details(shiny::tags$summary(tr(l, "Studieninformation", "Study information")), info)
        ))
      }
      # Translating the step keeps a tick given for this round; another round
      # always starts without one.
      ticked <- identical(consent_for, z$enrollment$id) && isTRUE(shiny::isolate(input$consent_check))
      consent_for <<- z$enrollment$id
      shiny::tagList(
        shiny::tags$h4(tr(l, "Studieninformation und Einwilligung", "Study information and consent")),
        info,
        shiny::tags$p(class = "del-note", tr(l, "Bitte lesen Sie die Studieninformation. Sie k\u00f6nnen die Aussagen beantworten, sobald Sie eingewilligt haben.", "Please read the study information. You can answer the statements once you have given consent.")),
        if (declined()) shiny::tags$p(class = "del-note", tr(l, "Sie haben die Einwilligung abgelehnt. Sie k\u00f6nnen weiterhin einwilligen.", "You declined consent. You can still give consent.")),
        shiny::checkboxInput(ns("consent_check"), tr(l, "Ich habe die Studieninformation oben gelesen und willige in die Teilnahme ein.", "I have read the study information above and consent to take part."), ticked),
        shiny::tags$div(
          class = "del-actions",
          shiny::actionButton(ns("consent"), tr(l, "Einwilligung erteilen", "Give consent"), class = "btn-primary"),
          shiny::actionButton(ns("consent_decline"), tr(l, "Nicht einwilligen", "Do not consent"))
        ),
        shiny::tags$p(class = "del-note", tr(l, "Ohne Einwilligung k\u00f6nnen Sie diese Runde nicht beantworten; Sie k\u00f6nnen sp\u00e4ter noch einwilligen. Wenn Sie nicht mehr an der Studie teilnehmen m\u00f6chten, nutzen Sie \u201eTeilnahme beenden\u201c am Ende dieser Seite.", "Without consent you cannot answer this round; you can still give consent later. To stop taking part in the study, use \u201cEnd participation\u201d at the end of this page."))
      )
    })
    shiny::observeEvent(input$consent, {
      z <- q()
      shiny::req(z)
      if (!isTRUE(input$consent_check)) {
        status(function(l) tr(l, "Bitte die Einwilligung bewusst ausw\u00e4hlen.", "Select consent explicitly first."))
        return()
      }
      l <- lang()
      tryCatch(
        {
          r <- call("record_consent", z$round$study_id, z$consent$id, TRUE, command_id())
          status(function(l) paste(tr(l, "Einwilligung gespeichert. Beleg:", "Consent saved. Receipt:"), short_ref(r$id)))
          fresh <- reopen(z)
          if (is.null(fresh)) {
            fresh <- z
            fresh$consent$accepted <- TRUE
          }
          if (is.null(fresh$consent$recorded_at) && !is.null(r$recorded_at)) fresh$consent$recorded_at <- r$recorded_at
          declined(FALSE)
          # Nothing could be entered before consent: the block is shown again
          # with its controls enabled.
          show_again(fresh)
        },
        error = function(e) status(safe_error(e, l))
      )
    })
    shiny::observeEvent(input$consent_decline, {
      z <- q()
      shiny::req(z)
      l <- lang()
      tryCatch(
        {
          r <- call("record_consent", z$round$study_id, z$consent$id, FALSE, command_id())
          consent_for <<- NULL
          declined(TRUE)
          status(function(l) paste(tr(l, "Ablehnung gespeichert. Beleg:", "Refusal recorded. Receipt:"), short_ref(r$id)))
        },
        error = function(e) status(safe_error(e, l))
      )
    })
    # Released feedback of the previous round: where it is shown, a corrected
    # version's note, contributions attached to no displayed statement and the
    # download of one's own feedback.
    output$round_feedback <- shiny::renderUI({
      z <- q()
      shiny::req(z, z$feedback)
      l <- lang()
      f <- z$feedback
      number <- source_round(f)
      general <- qualitative_for(f$qualitative, NULL, unique(item_codes(z$items)))
      note <- f$correction
      shiny::tags$section(
        class = "del-feedback", `aria-labelledby` = ns("round_feedback_heading"),
        shiny::tags$h4(id = ns("round_feedback_heading"), if (is.na(number)) tr(l, "Feedback aus der vorigen Runde", "Feedback from the previous round") else sprintf(tr(l, "Feedback aus Runde %s", "Feedback from round %s"), number)),
        shiny::tags$p(tr(l, "Die Ergebnisse stehen bei jeder Aussage.", "The results are shown with each statement.")),
        if (!is.null(note)) shiny::tags$p(class = "del-revision", paste(tr(l, "Dieses Feedback wurde korrigiert.", "This feedback was corrected."), note$participant_note)),
        if (nrow(general)) shiny::tagList(shiny::tags$p(shiny::tags$strong(tr(l, "Freigegebene Beitr\u00e4ge der Vorrunde", "Released contributions of the previous round"))), qualitative_list(general, l)),
        if (feedback_download_available) shiny::tags$div(class = "del-actions", shiny::downloadButton(ns("feedback_download"), tr(l, "Mein Feedback herunterladen", "Download my feedback")))
      )
    })
    output$consent_wait <- shiny::renderText(tr(lang(), "Sie k\u00f6nnen die Aussagen beantworten, sobald Sie oben eingewilligt haben.", "You can answer the statements once you have given consent above."))
    output$content_note <- shiny::renderText(tr(lang(), "Studientexte, Skalenanker und Einwilligung bleiben in ihrer genehmigten Sprache.", "Study text, scale anchors and consent remain in their approved language."))
    output$save_note <- shiny::renderText(if (automatic) {
      tr(lang(), "Antworten werden kurz nach jeder \u00c4nderung automatisch gespeichert. Nur die Statuszeile am Ende jeder Aussage best\u00e4tigt die Speicherung.", "Responses are saved automatically shortly after each change. Only the status line at the end of each statement confirms a save.")
    } else {
      tr(lang(), "Jedes Bewertungsfeld einzeln speichern. Keine automatische Speicherung.", "Save each response field explicitly. Saving is not automatic.")
    })
    output$block_head <- shiny::renderUI({
      v <- view()
      z <- q()
      shiny::req(v, z, length(blocks) > 1L)
      l <- lang()
      number <- question_numbers(z$items)
      # The heading receives the focus after a change of block; its frame
      # follows the text, not the width of the page.
      shiny::tags$h4(
        id = ns("block_heading"), tabindex = "-1", style = "width:fit-content;max-width:100%",
        paste(
          tr(l, "Block", "Block"), v$index, tr(l, "von", "of"), length(blocks), "\u00b7", tr(l, "Fragen", "Questions"),
          paste0(min(number[v$rows]), "\u2013", max(number[v$rows])), tr(l, "von", "of"), max(number)
        )
      )
    })
    # One card per statement; its fields keep the identifiers of their block.
    output$block <- shiny::renderUI({
      v <- view()
      shiny::req(v)
      l <- shiny::isolate(lang())
      editable <- identical(v$mode, "open")
      shiny::tagList(lapply(seq_along(v$cards), function(k) {
        members <- v$cards[[k]]
        shiny::tags$section(
          id = ns(paste0("card_", k)), class = "del-statement", tabindex = "-1", `aria-labelledby` = ns(paste0("slot_", members[1], "-heading")),
          lapply(members, function(slot) rating_ui(ns(v$ids[slot]), ns(paste0("slot_", slot)), card = TRUE, save = editable, small = automatic, save_label = tr(l, "Jetzt speichern", "Save now"))),
          shiny::uiOutput(ns(paste0("card_", k, "-line")))
        )
      }))
    })
    # Only the directions that exist are offered.
    output$pager <- shiny::renderUI({
      v <- view()
      shiny::req(v, length(blocks) > 1L)
      l <- lang()
      shiny::tags$div(
        class = "del-actions",
        if (v$index > 1L) shiny::actionButton(ns("block_previous"), tr(l, "Vorheriger Block", "Previous block")),
        if (v$index < length(blocks)) shiny::actionButton(ns("block_next"), tr(l, "N\u00e4chster Block", "Next block"))
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
    })
    # Review and submission; a submitted round or one that no longer accepts
    # answers offers no submission.
    output$review <- shiny::renderUI({
      z <- q()
      shiny::req(z)
      reason <- halted()
      l <- shiny::isolate(lang())
      mode <- questionnaire_mode(z)
      if (mode %in% c("submitted", "withdrawn") || identical(reason, "submitted")) {
        return(NULL)
      }
      shiny::tagList(
        shiny::tags$h4(shiny::textOutput(ns("review_title"), inline = TRUE)),
        shiny::tags$div(class = "del-progress", shiny::uiOutput(ns("progress")), shiny::uiOutput(ns("overview"))),
        if (identical(mode, "open") && is.null(reason)) {
          shiny::tagList(
            shiny::checkboxInput(ns("confirm"), tr(l, "Ich habe meine Antworten gepr\u00fcft. Die Abgabe beendet die Bearbeitung.", "I reviewed my answers. Submission ends editing."), FALSE),
            shiny::tags$div(class = "del-actions", shiny::actionButton(ns("submit"), tr(l, "Verbindlich abgeben", "Submit final responses"), class = "btn-primary")),
            shiny::uiOutput(ns("submission"))
          )
        } else {
          shiny::tags$p(class = "del-note", shiny::textOutput(ns("submit_unavailable"), inline = TRUE))
        }
      )
    })
    output$review_title <- shiny::renderText(tr(lang(), "Pr\u00fcfen und abgeben", "Review and submit"))
    output$submit_unavailable <- shiny::renderText({
      z <- q()
      shiny::req(z)
      mode <- questionnaire_mode(z)
      if (identical(mode, "consent")) tr(lang(), "Sie k\u00f6nnen abgeben, sobald Sie eingewilligt haben.", "You can submit once you have given consent.") else closed_text(halted(), mode, lang())
    })
    # Progress is counted in statements, as confirmed by the server; written
    # comments are counted on their own.
    output$progress <- shiny::renderUI({
      z <- q()
      k <- known()
      shiny::req(z, k)
      p <- round_progress(z, k, blocks)
      shiny::req(p$total > 0L)
      shiny::tags$p(sprintf(tr(lang(), "Beantwortete und gespeicherte Aussagen: %s von %s.", "Statements answered and saved: %s of %s."), p$answered, p$total))
    })
    # Before submission: how many statements have a special response or are
    # still open, and in which blocks.
    output$overview <- shiny::renderUI({
      z <- q()
      k <- known()
      shiny::req(z, k)
      p <- round_progress(z, k, blocks)
      l <- lang()
      facts <- c(
        if (p$total > 0L) {
          c(
            paste(tr(l, "Mit Sonderantwort:", "With a special response:"), p$special), paste(tr(l, "Offen:", "Open:"), p$open),
            paste(tr(l, "davon erforderlich:", "of which required:"), p$required)
          )
        },
        if (p$comment_fields > 0L) paste(tr(l, "Kommentare:", "Comments:"), p$comments)
      )
      several <- length(blocks) > 1L
      shiny::tagList(
        if (length(facts)) shiny::tags$p(class = "del-note", paste(facts, collapse = " \u00b7 ")),
        # Blocks with open optional statements are named only where they differ.
        if (several && length(p$open_blocks) && !identical(p$open_blocks, p$required_blocks)) {
          shiny::tags$p(class = "del-note", paste(tr(l, "Offene Aussagen in Block:", "Open statements in block:"), paste(p$open_blocks, collapse = ", ")))
        },
        if (several && length(p$required_blocks)) {
          shiny::tags$p(class = "del-note", paste(tr(l, "Erforderliche Aussagen sind offen in Block:", "Required statements are open in block:"), paste(p$required_blocks, collapse = ", ")))
        }
      )
    })
    # Beside the submit button: why a submission was refused and, for open
    # required statements, a link to each of them. The list follows the
    # answers confirmed since.
    output$submission <- shiny::renderUI({
      s <- submission()
      z <- q()
      k <- known()
      shiny::req(s, z, k)
      l <- lang()
      box <- function(tone, ...) shiny::tags$div(id = ns("submission_notice"), class = paste("del-status", paste0("del-status--", tone)), role = if (identical(tone, "attention")) "alert" else "status", tabindex = "-1", ...)
      if (is.list(s)) {
        return(box("attention", localize_status(s$error, l)))
      }
      if (identical(s, "pending")) {
        return(box("attention", tr(l, "Bitte \u00c4nderungen in diesem Block zuerst speichern oder vervollst\u00e4ndigen.", "Save or complete your changes in this block first.")))
      }
      if (identical(s, "confirm")) {
        return(box("attention", tr(l, "Bitte best\u00e4tigen Sie zuerst, dass Sie Ihre Antworten gepr\u00fcft haben.", "Confirm first that you reviewed your answers.")))
      }
      rows <- open_required(z, k)
      if (!length(rows)) {
        return(box("saved", tr(l, "Alle erforderlichen Aussagen sind beantwortet. Sie k\u00f6nnen jetzt abgeben.", "All required statements are answered. You can submit now.")))
      }
      box(
        "attention",
        shiny::tags$p(tr(l, "Nicht abgegeben. Diese erforderlichen Aussagen sind noch offen:", "Not submitted. These required statements are still open:")),
        shiny::tags$ul(lapply(rows, function(row) {
          st <- statement_text(z$items[row, , drop = FALSE], z$protocol, l)
          shiny::tags$li(shiny::tags$a(href = "#", onclick = jump_script(ns("jump"), row), sprintf(tr(l, "Frage %s:", "Question %s:"), z$items$number[row]), " ", shiny::tags$span(lang = st$lang, st$text)))
        }))
      )
    })
    # A link of the list opens the block of its statement and focuses it.
    shiny::observeEvent(input$jump, {
      z <- q()
      v <- view()
      row <- suppressWarnings(as.integer(input$jump))
      shiny::req(z, v, length(row) == 1L, !is.na(row), row >= 1L, row <= nrow(z$items))
      index <- which(vapply(blocks, function(rows) row %in% rows, logical(1)))[1]
      groups <- statement_cards(item_codes(z$items)[blocks[[index]]])
      card <- which(vapply(groups, function(members) match(row, blocks[[index]]) %in% members, logical(1)))[1]
      target <- ns(paste0("card_", card))
      if (identical(index, v$index)) session$sendCustomMessage("delphyr-focus", target) else go(index, focus = target)
    })
    shiny::observeEvent(input$submit, {
      z <- q()
      shiny::req(z)
      # Pending complete answers are saved first; submission never outruns a save.
      if (!settle()) {
        submission("pending")
        return()
      }
      if (!is.null(halted())) {
        return()
      }
      if (!isTRUE(input$confirm)) {
        submission("confirm")
        return()
      }
      k <- known()
      required_open <- k$status == "not_answered" & as.logical(z$items$required)
      if (any(required_open)) {
        submission("required")
        session$onFlushed(function() session$sendCustomMessage("delphyr-focus", ns("submission_notice")), once = TRUE)
        return()
      }
      # The submission names exactly the revisions this session saw confirmed.
      revs <- stats::setNames(k$revision, k$id)
      revs <- revs[revs > 0]
      l <- lang()
      tryCatch(
        {
          r <- call("submit_round", z$enrollment$id, revs, command_id())
          receipt(r)
          submission(NULL)
          status("")
          # The fields on screen become read only at once.
          fresh <- reopen(z)
          if (is.null(fresh)) halt("submitted") else show_again(fresh)
          session$onFlushed(function() session$sendCustomMessage("delphyr-focus", ns("receipt")), once = TRUE)
          refresh_rounds(keep = z$enrollment$id, quiet = TRUE)
        },
        error = function(e) {
          if (inherits(e, "DEL_ROUND_CLOSED")) halt("closed")
          submission(list(error = safe_error(e, l)))
        }
      )
    })
    # Ending participation is a study-level step of its own, after the round.
    output$withdrawal <- shiny::renderUI({
      shiny::req(withdrawal_available, study(), visible(), !withdrawn())
      l <- lang()
      shiny::tags$section(
        class = "del-withdrawal", `aria-labelledby` = ns("withdrawal_heading"),
        shiny::tags$h3(id = ns("withdrawal_heading"), tr(l, "Teilnahme beenden", "End participation")),
        shiny::tags$p(tr(l, "Dies beendet weitere Antworten und Einladungen in dieser synthetischen Studie. Bereits gespeicherte Daten bleiben erhalten. Dies ist kein L\u00f6schantrag.", "This stops further responses and invitations in this synthetic study. Previously saved data are retained. This is not a deletion request.")),
        shiny::tags$details(
          shiny::tags$summary(tr(l, "Meine Teilnahme beenden", "End my participation")),
          shiny::checkboxInput(ns("withdraw_confirm"), tr(l, "Ich m\u00f6chte meine Teilnahme beenden und verstehe den beschriebenen Datenverbleib.", "I want to end participation and understand the stated data retention."), FALSE),
          shiny::tags$div(class = "del-actions", shiny::actionButton(ns("withdraw"), tr(l, "Teilnahme verbindlich beenden", "Confirm end of participation"), class = "btn-outline-danger"))
        )
      )
    })
    shiny::observeEvent(input$withdraw, {
      shiny::req(withdrawal_available, study())
      if (!isTRUE(input$withdraw_confirm)) {
        status(function(l) tr(l, "Bitte den Teilnahmer\u00fcckzug ausdr\u00fccklich best\u00e4tigen.", "Explicitly confirm withdrawal first."))
        return()
      }
      l <- lang()
      tryCatch(
        {
          result <- call("withdraw_participation", study(), "synthetic_retain_prior_data", command_id())
          clear()
          withdrawn(TRUE)
          status(function(l) paste(tr(l, "Teilnahme beendet. Gespeicherte Daten bleiben erhalten. Beleg:", "Participation ended. Saved data are retained. Receipt:"), short_ref(result$id)))
        },
        error = function(e) status(safe_error(e, l))
      )
    })
    # The participant-feedback profile: the released aggregate and only this
    # person's own previous answers, written to a private temporary directory.
    # A refused download says why on the page.
    output$feedback_download <- shiny::downloadHandler(
      filename = function() "delphyr-feedback.zip",
      content = function(file) {
        z <- shiny::isolate(q())
        l <- shiny::isolate(lang())
        shiny::req(feedback_download_available, z)
        directory <- tempfile("delphyr-feedback-")
        dir.create(directory, mode = "0700")
        on.exit(unlink(directory, recursive = TRUE), add = TRUE)
        tryCatch(
          {
            call("write_participant_feedback", z$enrollment$id, directory)
            zip::zipr(file, list.files(directory, full.names = TRUE), root = directory)
          },
          error = function(e) {
            status(safe_error(e, l))
            stop(e)
          }
        )
      }, contentType = "application/zip"
    )
    list(dirty = dirty, questionnaire = q, receipt = receipt)
  })
}
no_rounds <- function() data.frame(id = character(), number = integer(), state = character(), round_state = character(), stringsAsFactors = FALSE)
# A member sees a round once it has been opened; a prepared, reviewed or
# approved round may still change or be withdrawn.
participant_rounds <- function(x) {
  if (!is.data.frame(x)) {
    return(no_rounds())
  }
  if (!is.null(x$round_state)) x <- x[!x$round_state %in% c("draft", "review", "approved", "cancelled"), , drop = FALSE]
  rownames(x) <- NULL
  x
}
round_choices <- function(x, lang) {
  if (!is.data.frame(x) || !nrow(x)) {
    return(character())
  }
  state <- if (is.null(x$round_state)) rep("", nrow(x)) else paste0(" \u00b7 ", state_label(x$round_state, lang))
  own <- if (is.null(x$state)) rep("", nrow(x)) else ifelse(x$state %in% "submitted", paste0(" \u00b7 ", state_label("submitted", lang)), "")
  list_choices(x$id, paste0(tr(lang, "Runde", "Round"), " ", x$number, state, own))
}
# The round a person is expected to work on: the latest open round that is
# not yet submitted or withdrawn; without one, the latest round.
current_enrollment <- function(x) {
  if (!NROW(x)) {
    return(NULL)
  }
  number <- if (is.null(x$number)) seq_len(nrow(x)) else x$number
  due <- if (is.null(x$state) || is.null(x$round_state)) rep(FALSE, nrow(x)) else x$round_state == "open" & !x$state %in% c("submitted", "withdrawn")
  rows <- if (any(due)) which(due) else seq_len(nrow(x))
  x$id[rows[which.max(number[rows])]]
}
# What a round on screen allows: "open", "consent" (open, consent missing),
# "closed", "submitted" or "withdrawn".
questionnaire_mode <- function(z) {
  state <- z$enrollment$state
  if (identical(state, "submitted") || (is.data.frame(z$receipt) && nrow(z$receipt) > 0L)) {
    return("submitted")
  }
  if (identical(state, "withdrawn")) {
    return("withdrawn")
  }
  if ((!is.null(z$round$state) && !identical(z$round$state, "open")) || isFALSE(as.logical(z$round$in_time))) {
    return("closed")
  }
  if (isFALSE(as.logical(z$consent$accepted))) {
    return("consent")
  }
  "open"
}
study_zone <- function(z) {
  zone <- z$protocol$study$timezone
  if (is.character(zone) && length(zone) == 1L && !is.na(zone) && zone %in% known_zones()) zone else "UTC"
}
field_scale <- function(z, item) {
  scale <- if (length(item$scale_code) == 1L) z$protocol$instrument$scales[[item$scale_code]] else NULL
  if (is.null(scale)) list(type = "", values = list()) else scale
}
item_codes <- function(items) if (is.null(items$item_code)) as.character(seq_len(nrow(items))) else as.character(items$item_code)
# The fields of a statement follow one another: rated dimensions before free
# text, required before optional, then the order of the protocol.
order_fields <- function(items, protocol) {
  n <- nrow(items)
  codes <- item_codes(items)
  dims <- vapply(protocol$instrument$dimensions, function(d) as.character(d$code)[1], character(1))
  dimension <- if (is.null(items$dimension_code)) rep("", n) else as.character(items$dimension_code)
  free <- if (is.null(items$scale_code)) rep(FALSE, n) else vapply(as.character(items$scale_code), function(s) identical(protocol$instrument$scales[[s]]$type, "free_text"), logical(1))
  required <- if (is.null(items$required)) rep(TRUE, n) else as.logical(items$required)
  rank <- match(dimension, dims)
  rank[is.na(rank)] <- length(dims) + 1L
  out <- items[order(match(codes, unique(codes)), free, !required, rank, seq_len(n)), , drop = FALSE]
  rownames(out) <- NULL
  out
}
prepare_questionnaire <- function(z) {
  if (is.data.frame(z$items) && nrow(z$items)) {
    z$items <- order_fields(z$items, z$protocol)
    z$items$number <- question_numbers(z$items)
  }
  z
}
# Fields of one item stay in one block; a block holds at most `block_fields`
# response fields unless a single item has more.
question_blocks <- function(items, block_fields) {
  runs <- rle(item_codes(items))
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
  codes <- item_codes(items)
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
# The places of a block that hold the fields of one statement.
statement_cards <- function(codes) {
  runs <- rle(as.character(codes))
  ends <- cumsum(runs$lengths)
  lapply(seq_along(ends), function(i) seq.int(ends[i] - runs$lengths[i] + 1L, ends[i]))
}
card_roles <- function(z, rows) {
  free <- vapply(rows, function(r) identical(field_scale(z, z$items[r, , drop = FALSE])$type, "free_text"), logical(1))
  required <- if (is.null(z$items$required)) TRUE else any(as.logical(z$items$required[rows]))
  lapply(seq_along(rows), function(j) list(lead = j == 1L, required = required, several = if (free[j]) sum(free) > 1L else sum(!free) > 1L))
}
card_tone <- function(reports) {
  tones <- vapply(reports, function(x) x$tone, character(1))
  if ("attention" %in% tones) "attention" else if ("saved" %in% tones) "saved" else "neutral"
}
card_text <- function(reports, lang) {
  texts <- vapply(reports, function(x) x$text, character(1))
  labels <- vapply(reports, function(x) x$label, character(1))
  keep <- nzchar(texts)
  if (!any(keep)) {
    return("")
  }
  if (length(unique(texts[keep])) == 1L) {
    return(texts[keep][1])
  }
  paste(sprintf(tr(lang, "%s: %s", "%s: %s"), labels[keep], texts[keep]), collapse = " \u00b7 ")
}
# Where a round stands, in statements. A statement counts once each of its
# fields that counts has a confirmed response; an optional comment never
# counts and is counted on its own.
round_progress <- function(z, k, blocks) {
  n <- nrow(z$items)
  codes <- item_codes(z$items)
  free <- vapply(seq_len(n), function(r) identical(field_scale(z, z$items[r, , drop = FALSE])$type, "free_text"), logical(1))
  required <- if (is.null(z$items$required)) rep(TRUE, n) else as.logical(z$items$required)
  counts <- !free | required
  open <- k$status == "not_answered"
  statements <- unique(codes[counts])
  any_of <- function(test) vapply(statements, function(s) any(test[codes == s & counts]), logical(1), USE.NAMES = FALSE)
  open_s <- any_of(open)
  blocks_with <- function(test) which(vapply(blocks, function(rows) any(test[rows]), logical(1)))
  list(
    total = length(statements), answered = sum(!open_s), open = sum(open_s), required = sum(any_of(open & required)),
    special = sum(!open_s & any_of(!open & k$status != "answered")),
    comment_fields = sum(free & !required), comments = sum(free & !required & k$status == "answered"),
    open_blocks = blocks_with(open & counts), required_blocks = blocks_with(open & required)
  )
}
open_required <- function(z, k) {
  if (is.null(k) || !nrow(k)) {
    return(integer())
  }
  rows <- which(k$status == "not_answered" & as.logical(z$items$required))
  rows[!duplicated(item_codes(z$items)[rows])]
}
jump_script <- function(id, row) sprintf("Shiny.setInputValue(%s, %d, {priority: 'event'}); return false;", jsonlite::toJSON(id, auto_unbox = TRUE), as.integer(row))
closed_text <- function(reason, mode, lang) {
  if (identical(reason, "ended")) {
    return(tr(lang, "Diese Runde wurde bereits abgegeben oder Ihre Teilnahme ist beendet. Laden Sie die Runde erneut, um die gespeicherten Antworten zu sehen.", "This round was already submitted or your participation has ended. Load the round again to see the saved answers."))
  }
  if (identical(reason, "closed")) {
    return(tr(lang, "Diese Runde wurde geschlossen oder ihre Frist ist abgelaufen. Antworten k\u00f6nnen nicht mehr gespeichert oder abgegeben werden; nicht gespeicherte Eingaben bleiben sichtbar, damit Sie sie kopieren k\u00f6nnen. Sie k\u00f6nnen weiterhin zwischen den Bl\u00f6cken wechseln.", "This round has closed or its deadline has passed. Answers can no longer be saved or submitted; entries that were not saved stay visible so that you can copy them. You can still move between blocks."))
  }
  if (identical(mode, "withdrawn")) {
    return(tr(lang, "Sie haben Ihre Teilnahme beendet. Diese Runde kann nicht mehr beantwortet werden.", "You ended your participation. This round can no longer be answered."))
  }
  tr(lang, "Diese Runde ist geschlossen. Antworten k\u00f6nnen nicht mehr gespeichert oder abgegeben werden.", "This round is closed. Answers can no longer be saved or submitted.")
}
consent_text <- function(consent, zone, lang) {
  moment <- if (length(consent$recorded_at) == 1L) parse_moment(consent$recorded_at) else NA
  if (is.na(moment)) {
    return(tr(lang, "Einwilligung liegt vor.", "Consent is recorded."))
  }
  sprintf(tr(lang, "Einwilligung erteilt am %s.", "Consent recorded on %s."), format_moment(moment, zone, lang))
}
# A confirmed save today shows its time of day; an older one its moment.
saved_text <- function(at, zone, lang) {
  moment <- if (length(at) == 1L) parse_moment(at) else NA
  if (is.na(moment)) {
    return(tr(lang, "Gespeichert", "Saved"))
  }
  if (identical(format(moment, "%Y-%m-%d", tz = zone), format(Sys.time(), "%Y-%m-%d", tz = zone))) {
    return(sprintf(tr(lang, "Gespeichert um %s", "Saved at %s"), format(moment, "%H:%M", tz = zone)))
  }
  sprintf(tr(lang, "Gespeichert am %s", "Saved on %s"), format_moment(moment, zone, lang))
}
# The wording of an item version in the interface language, else in the
# study's default language, else in the first approved language.
statement_text <- function(item, protocol, lang) {
  texts <- if (length(item$texts) == 1L && !is.na(item$texts)) tryCatch(jsonlite::fromJSON(item$texts), error = function(e) list()) else list()
  text <- texts[[lang]]
  content <- lang
  if (is.null(text)) {
    preferred <- protocol$study$default_language
    content <- if (!is.null(preferred) && preferred %in% names(texts)) preferred else names(texts)[1]
    text <- if (length(content)) texts[[content]] else NULL
    if (!length(content)) content <- lang
  }
  list(text = if (is.null(text)) "" else as.character(text), lang = content, fallback = !identical(content, lang))
}
# The earlier wording of revised items, from the member's own enrollment in
# the round the displayed feedback comes from.
earlier_items <- function(z, rounds, call) {
  r <- z$feedback$aggregate$results
  if (!is.data.frame(r) || !nrow(r) || is.null(r$item_version) || is.null(r$item_code) || is.null(z$items$item_version)) {
    return(NULL)
  }
  both <- merge(unique(z$items[c("item_code", "item_version")]), unique(r[c("item_code", "item_version")]), by = "item_code", suffixes = c("", "_shown"))
  if (!any(both$item_version != both$item_version_shown)) {
    return(NULL)
  }
  number <- source_round(z$feedback)
  enrollment <- if (is.data.frame(rounds) && nrow(rounds)) rounds$id[rounds$number %in% number] else character()
  if (length(enrollment) != 1L) {
    return(NULL)
  }
  tryCatch(call("get_questionnaire", enrollment)$items, error = function(e) NULL)
}
# The round whose released results the feedback carries.
source_round <- function(f) {
  r <- f$aggregate$results
  n <- if (is.data.frame(r) && !is.null(r$round_number)) unique(stats::na.omit(r$round_number)) else integer()
  if (length(n) == 1L) n else NA
}
cell <- function(r, name) {
  v <- r[[name]]
  if (is.null(v) || !length(v)) NA else v[[1]]
}
# The released result of one field, overall; never recomputed here.
feedback_row <- function(f, item) {
  r <- f$aggregate$results
  if (!is.data.frame(r) || !nrow(r) || is.null(r$item_code) || is.null(r$dimension_code)) {
    return(NULL)
  }
  r <- r[r$item_code %in% item$item_code & r$dimension_code %in% item$dimension_code, , drop = FALSE]
  if (!is.null(r$stratum)) r <- r[r$stratum %in% "overall", , drop = FALSE]
  if (!nrow(r)) {
    return(NULL)
  }
  r[1, , drop = FALSE]
}
# The version the displayed results belong to: of the released result, else
# of the member's own previous answer.
previous_version <- function(f, item) {
  if (is.null(f)) {
    return(NA_integer_)
  }
  r <- feedback_row(f, item)
  version <- if (is.null(r)) NA else cell(r, "item_version")
  if (!is.na(version)) {
    return(as.integer(version))
  }
  own <- f$own
  if (is.data.frame(own) && nrow(own) && !is.null(own$item_version)) {
    v <- own$item_version[own$item_code %in% item$item_code & own$dimension_code %in% item$dimension_code]
    if (length(v)) {
      return(as.integer(v[1]))
    }
  }
  NA_integer_
}
# Where the protocol releases group statistics: the released results of the
# stakeholder groups for the same field and version, in their released order.
feedback_groups <- function(f, item, version) {
  r <- f$aggregate$results
  if (!is.data.frame(r) || !nrow(r) || is.null(r$stratum) || is.null(r$item_code) || is.null(r$dimension_code)) {
    return(NULL)
  }
  keep <- r$item_code %in% item$item_code & r$dimension_code %in% item$dimension_code & !is.na(r$stratum) & !r$stratum %in% "overall"
  if (!is.null(r$item_version) && !is.na(version)) keep <- keep & r$item_version %in% version
  r <- r[keep, , drop = FALSE]
  if (nrow(r)) r else NULL
}
feedback_distribution <- function(f, item, version, stratum = "overall") {
  d <- f$aggregate$distributions
  if (!is.data.frame(d) || !nrow(d) || is.null(d$value) || is.null(d$n) || is.null(d$item_code) || is.null(d$dimension_code)) {
    return(NULL)
  }
  keep <- d$item_code %in% item$item_code & d$dimension_code %in% item$dimension_code
  if (!is.null(d$item_version) && !is.na(version)) keep <- keep & d$item_version %in% version
  keep <- keep & if (is.null(d$stratum)) identical(stratum, "overall") else d$stratum %in% stratum
  d <- d[keep, , drop = FALSE]
  if (!nrow(d)) {
    return(NULL)
  }
  d[order(d$value), c("value", "n"), drop = FALSE]
}
# A result kept back under the minimum cell size carries no numbers.
withheld <- function(r) isTRUE(as.logical(cell(r, "suppressed"))) || is.na(cell(r, "n_valid"))
grouped_feedback <- function(f) {
  r <- f$aggregate$results
  isTRUE(as.logical(f$aggregate$policy$group_statistics)) || (is.data.frame(r) && !is.null(r$stratum) && any(!r$stratum %in% "overall"))
}
# Why a result is kept back. With group statistics a small group keeps back
# the results of the whole panel and of every group for that field.
withheld_reason <- function(f, lang) {
  least <- f$aggregate$policy$minimum_display_cell_n
  if (length(least) != 1L || is.na(least)) {
    return(tr(lang, "zu wenige g\u00fcltige Bewertungen", "too few valid ratings"))
  }
  if (grouped_feedback(f)) {
    return(sprintf(tr(lang, "weniger als %s g\u00fcltige Bewertungen im Panel oder in einer seiner Gruppen", "fewer than %s valid ratings in the panel or in one of its groups"), least))
  }
  sprintf(tr(lang, "weniger als %s g\u00fcltige Bewertungen", "fewer than %s valid ratings"), least)
}
# One released result in words: valid ratings and members, median and
# quartiles where the protocol shows them, and the share in the agreement
# range of the protocol.
result_sentence <- function(r, label, distribution, settings, agree, lang) {
  n_valid <- cell(r, "n_valid")
  submitted <- cell(r, "n_submitted")
  parts <- if (is.na(submitted)) {
    sprintf(tr(lang, "%s: %s g\u00fcltige Bewertungen", "%s: %s valid ratings"), label, n_valid)
  } else {
    sprintf(tr(lang, "%s: %s g\u00fcltige Bewertungen von %s Mitgliedern", "%s: %s valid ratings from %s members"), label, n_valid, submitted)
  }
  median <- cell(r, "median")
  if (!isFALSE(settings$median) && !is.na(median)) {
    middle <- sprintf(tr(lang, "Median %s", "median %s"), format_number(median, lang))
    q1 <- cell(r, "q1")
    q3 <- cell(r, "q3")
    if (!isFALSE(settings$iqr) && !is.na(q1) && !is.na(q3)) middle <- paste0(middle, " (", sprintf(tr(lang, "IQR %s\u2013%s", "IQR %s\u2013%s"), format_number(q1, lang), format_number(q3, lang)), ")")
    parts <- c(parts, middle)
  }
  if (length(agree) > 1L && all(diff(agree) == 1L) && n_valid > 0) {
    count <- if (is.null(distribution)) cell(r, "n_agree") else sum(distribution$n[distribution$value %in% agree])
    if (!is.na(count)) parts <- c(parts, sprintf(tr(lang, "%s mit %s bis %s bewertet", "%s rated %s to %s"), format_percent(count / n_valid, lang), agree[1], agree[length(agree)]))
  }
  paste0(paste(parts, collapse = ", "), ".")
}
# The stakeholder groups' results, one line each; a group is never folded
# into the panel's figure.
group_results <- function(groups, f, item, version, settings, agree, reason, lang) {
  if (is.null(groups) || !nrow(groups)) {
    return(NULL)
  }
  shiny::tagList(
    shiny::tags$p(tr(lang, "Nach Interessengruppe:", "By stakeholder group:")),
    shiny::tags$ul(lapply(seq_len(nrow(groups)), function(i) {
      g <- groups[i, , drop = FALSE]
      label <- humanize_code(g$stratum)
      if (withheld(g)) {
        return(shiny::tags$li(sprintf(tr(lang, "%s: %s (%s)", "%s: %s (%s)"), label, no_value, reason)))
      }
      classification <- classification_label(cell(g, "classification"), lang)
      shiny::tags$li(paste(c(
        result_sentence(g, label, feedback_distribution(f, item, version, g$stratum), settings, agree, lang),
        if (!is.null(classification)) sprintf(tr(lang, "Einstufung: %s.", "Classification: %s."), classification)
      ), collapse = " "))
    }))
  )
}
# The released distributions of the groups shown, named by group.
group_distributions <- function(groups, f, item, version) {
  out <- list()
  for (i in seq_len(if (is.null(groups)) 0L else nrow(groups))) {
    g <- groups[i, , drop = FALSE]
    d <- if (withheld(g)) NULL else feedback_distribution(f, item, version, g$stratum)
    if (!is.null(d)) out[[humanize_code(g$stratum)]] <- d
  }
  out
}
classification_label <- function(code, lang) {
  labels <- tr(lang, c(consensus_in = "Konsens f\u00fcr Einschluss", consensus_out = "Konsens f\u00fcr Ausschluss", no_consensus = "kein Konsens", insufficient_data = "zu wenige g\u00fcltige Bewertungen f\u00fcr eine Einstufung"), c(consensus_in = "consensus for inclusion", consensus_out = "consensus for exclusion", no_consensus = "no consensus", insufficient_data = "too few valid ratings to classify"))
  if (length(code) == 1L && !is.na(code) && code %in% names(labels)) unname(labels[code]) else NULL
}
# The released result of a rated field in words: the panel, its
# classification and the stakeholder groups, then the member's own previous
# answer and the distribution.
feedback_result <- function(f, item, scale, protocol, lang, revised = FALSE, own = NULL) {
  r <- feedback_row(f, item)
  if (is.null(r)) {
    return(NULL)
  }
  number <- cell(r, "round_number")
  if (is.na(number)) number <- source_round(f)
  label <- if (is.na(number)) tr(lang, "Vorige Runde", "Previous round") else sprintf(tr(lang, "Runde %s", "Round %s"), number)
  if (revised) label <- sprintf(tr(lang, "%s (fr\u00fchere Fassung)", "%s (earlier wording)"), label)
  version <- cell(r, "item_version")
  groups <- feedback_groups(f, item, version)
  settings <- protocol$feedback
  agree <- sort(unique(suppressWarnings(as.integer(unlist(protocol$analysis$consensus$agree_values)))))
  reason <- withheld_reason(f, lang)
  mine <- if (!is.null(own)) shiny::tags$p(own)
  if (withheld(r)) {
    # The groups are kept back together with the panel; one reason covers them.
    if (!is.null(groups)) groups <- groups[!vapply(seq_len(nrow(groups)), function(i) withheld(groups[i, , drop = FALSE]), logical(1)), , drop = FALSE]
    return(shiny::tagList(
      shiny::tags$p(sprintf(tr(lang, "%s: %s (%s)", "%s: %s (%s)"), label, no_value, reason)),
      group_results(groups, f, item, version, settings, agree, reason, lang),
      mine
    ))
  }
  distribution <- feedback_distribution(f, item, version)
  classification <- classification_label(cell(r, "classification"), lang)
  shiny::tagList(
    shiny::tags$p(result_sentence(r, label, distribution, settings, agree, lang)),
    if (!is.null(classification)) shiny::tags$p(sprintf(tr(lang, "Einstufung: %s.", "Classification: %s."), classification)),
    group_results(groups, f, item, version, settings, agree, reason, lang),
    mine,
    if (!isFALSE(settings$distribution)) distribution_details(distribution, cell(r, "n_valid"), scale, lang, group_distributions(groups, f, item, version))
  )
}
# The distribution of the valid ratings; with group statistics one column per
# stakeholder group beside the total.
distribution_details <- function(d, n_valid, scale, lang, groups = list()) {
  if (is.null(d)) {
    return(NULL)
  }
  values <- suppressWarnings(as.numeric(unlist(scale$values)))
  label <- as.character(d$value)
  if (length(values) && !all(is.na(values)) && !is.null(scale$anchors)) {
    low <- d$value == min(values, na.rm = TRUE)
    high <- d$value == max(values, na.rm = TRUE)
    label[low] <- paste(d$value[low], "=", scale$anchors$low)
    label[high] <- paste(d$value[high], "=", scale$anchors$high)
  }
  counts <- c(list(d$n), lapply(groups, function(g) g$n[match(d$value, g$value)]))
  heads <- c(if (length(groups)) tr(lang, "Gesamt", "Total") else tr(lang, "Anzahl", "Count"), names(groups))
  shiny::tags$details(
    shiny::tags$summary(sprintf(tr(lang, "Verteilung der %s g\u00fcltigen Bewertungen", "Distribution of the %s valid ratings"), n_valid)),
    shiny::tags$table(
      class = "table",
      shiny::tags$caption(tr(lang, "G\u00fcltige Bewertungen je Wert", "Valid ratings per value")),
      shiny::tags$thead(shiny::tags$tr(shiny::tags$th(scope = "col", tr(lang, "Bewertung", "Rating")), lapply(heads, function(x) shiny::tags$th(scope = "col", x)))),
      shiny::tags$tbody(lapply(seq_len(nrow(d)), function(i) shiny::tags$tr(shiny::tags$td(label[i]), lapply(counts, function(n) shiny::tags$td(if (is.na(n[i])) no_value else n[i])))))
    ),
    shiny::tags$p(class = "del-note", tr(lang, "IQR: In diesem Bereich liegt die mittlere H\u00e4lfte der g\u00fcltigen Bewertungen.", "IQR: the middle half of the valid ratings lies in this range."))
  )
}
# The member's own previous answer to a rated field, in words.
own_answer <- function(f, item, lang) {
  own <- f$own
  if (!is.data.frame(own) || !nrow(own) || is.null(own$answer_status)) {
    return(NULL)
  }
  own <- own[own$item_code %in% item$item_code & own$dimension_code %in% item$dimension_code, , drop = FALSE]
  if (!nrow(own)) {
    return(NULL)
  }
  status <- as.character(own$answer_status[1])
  if (identical(status, "answered")) {
    value <- cell(own, "value_integer")
    return(if (is.na(value)) NULL else sprintf(tr(lang, "Ihre Bewertung: %s", "Your rating: %s"), value))
  }
  if (is.na(status) || identical(status, "not_answered")) {
    return(tr(lang, "Sie haben nicht geantwortet.", "You did not answer."))
  }
  sprintf(tr(lang, "Ihre Wahl: %s", "You chose: %s"), special_label(status, lang))
}
revision_notice <- function(f, item, previous, earlier, protocol, lang) {
  number <- source_round(f)
  decided <- f$comparability
  comparable <- is.data.frame(decided) && nrow(decided) > 0L && isTRUE(any(decided$item_code == item$item_code & decided$dimension_code == item$dimension_code & decided$previous_version %in% previous & decided$current_version == item$item_version & as.logical(decided$comparable)))
  old <- if (is.data.frame(earlier) && nrow(earlier) && !is.null(earlier$item_version)) earlier[earlier$item_code %in% item$item_code & earlier$item_version %in% previous, , drop = FALSE] else NULL
  old <- if (!is.null(old) && nrow(old)) statement_text(old[1, , drop = FALSE], protocol, lang) else NULL
  shiny::tags$div(
    class = "del-revision",
    shiny::tags$p(
      if (is.na(number)) tr(lang, "Der Wortlaut wurde seit der vorigen Runde ge\u00e4ndert.", "The wording changed since the previous round.") else sprintf(tr(lang, "Der Wortlaut wurde seit Runde %s ge\u00e4ndert.", "The wording changed since round %s."), number),
      " ",
      if (comparable) tr(lang, "Das Studienteam hat beide Fassungen als vergleichbar eingestuft.", "The study team assessed both versions as comparable.") else tr(lang, "Ergebnisse der fr\u00fcheren Fassung sind nicht unmittelbar vergleichbar.", "Results of the earlier wording are not directly comparable.")
    ),
    if (!is.null(old) && nzchar(old$text)) shiny::tags$details(shiny::tags$summary(tr(lang, "Fr\u00fchere Fassung", "Earlier wording")), shiny::tags$p(lang = old$lang, old$text))
  )
}
# Feedback beside a field: the released result and the own previous answer of
# a rated dimension, and for the statement its released contributions.
feedback_box <- function(f, item, scale, protocol, lang, id = NULL, lead = TRUE, label = NULL, revised = FALSE) {
  rated <- !identical(scale$type, "free_text")
  entries <- qualitative_for(if (lead) f$qualitative else NULL, item$item_code)
  own <- if (rated) own_answer(f, item, lang) else NULL
  result <- if (rated) feedback_result(f, item, scale, protocol, lang, revised, own) else NULL
  if (is.null(result) && is.null(own) && !nrow(entries)) {
    return(NULL)
  }
  shiny::tags$div(
    id = id, class = "del-feedback",
    if (!is.null(label)) shiny::tags$p(shiny::tags$strong(label)),
    if (is.null(result) && !is.null(own)) shiny::tags$p(own) else result,
    qualitative_list(entries, lang)
  )
}
scale_anchors <- function(scale, protocol, id) {
  anchors <- scale$anchors
  values <- suppressWarnings(as.numeric(unlist(scale$values)))
  if (is.null(anchors$low) || is.null(anchors$high) || !length(values) || all(is.na(values))) {
    return(NULL)
  }
  shiny::tags$p(id = id, class = "del-anchors", lang = protocol$study$default_language, paste0(min(values, na.rm = TRUE), " = ", anchors$low, " \u2026 ", max(values, na.rm = TRUE), " = ", anchors$high))
}
rating_outputs <- c("title", "form", "save_status", "status", "conflict")
card_outputs <- c("line", "status")
# `outputs` names the place of the field on the page; the controls carry `id`.
# Inside a statement card the card shows one status line for all its fields.
rating_ui <- function(id, outputs = id, card = FALSE, save = TRUE, small = FALSE, save_label = "Save now") {
  ns <- shiny::NS(id)
  out <- shiny::NS(outputs)
  button <- if (save) shiny::tags$div(class = "del-actions", shiny::actionButton(ns("save"), save_label, class = if (small) "btn-sm" else NULL))
  if (card) {
    return(shiny::tags$div(class = "del-field", shiny::uiOutput(out("title")), shiny::uiOutput(out("form")), button, shiny::uiOutput(out("conflict"))))
  }
  shiny::tags$section(
    class = "del-item", shiny::uiOutput(out("title")), shiny::uiOutput(out("form")),
    button, shiny::uiOutput(out("save_status")), shiny::uiOutput(out("conflict"))
  )
}
rating_server <- function(id, q, item, lang, call, autosave_ms = 1500, place = NULL, on_saved = NULL, card = NULL, halted = NULL, on_halt = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    # Without a place the field renders into outputs of its own.
    define <- if (is.null(place)) function(name, render) output[[name]] <- render else place$define
    output_id <- if (is.null(place)) session$ns else place$id
    # Observers are collected so that they end when the field leaves the page.
    observers <- list()
    module <- environment()
    observe_event <- function(...) observers[[length(observers) + 1L]] <<- shiny::observeEvent(..., event.env = module, handler.env = module)
    scale <- field_scale(q, item)
    free <- identical(scale$type, "free_text")
    zone <- study_zone(q)
    round_mode <- questionnaire_mode(q)
    # A field that cannot be changed now never counts as pending.
    frozen <- !identical(round_mode, "open")
    lead <- is.null(card) || isTRUE(card$lead)
    several <- isTRUE(card$several)
    required <- if (is.null(card)) isTRUE(as.logical(item$required)) else isTRUE(card$required)
    specials <- as.character(unlist(scale$missing_options))
    stored <- function(responses) {
      old <- if (is.data.frame(responses) && nrow(responses)) responses[responses$round_item_id %in% item$id, , drop = FALSE] else NULL
      if (is.null(old) || !nrow(old)) {
        return(list(revision = 0L, status = "not_answered", value = "", saved_at = NULL))
      }
      status <- as.character(old$status[1])
      value <- if (identical(status, "answered")) {
        if (free) old$value_text[1] else as.character(old$value_int[1])
      } else {
        ""
      }
      list(revision = old$revision[1], status = status, value = if (is.na(value)) "" else value, saved_at = if (is.null(old$created_at)) NULL else old$created_at[1])
    }
    initial <- stored(q$responses)
    old_status <- initial$status
    old_value <- initial$value
    # Optional free text needs no response type: text present answers it,
    # cleared text withdraws it.
    choose_kind <- !free || (length(specials) > 0L && (isTRUE(as.logical(item$required)) || old_status %in% specials))
    revision <- shiny::reactiveVal(initial$revision)
    baseline <- shiny::reactiveVal(list(status = old_status, value = old_value))
    saved_at <- shiny::reactiveVal(initial$saved_at)
    # The response type is decided here, when the entry arrives, not when the
    # browser reports back the type it was told to show.
    kind_now <- shiny::reactiveVal(old_status)
    # After deliberately loading the saved response, the value the browser was
    # told to show stands for the field until the browser reports it.
    shown_value <- shiny::reactiveVal(NULL)
    message <- shiny::reactiveVal("")
    save_failed <- shiny::reactiveVal(FALSE)
    # A conflict or closed round stops automatic attempts until the person acts.
    conflict <- shiny::reactiveVal(FALSE)
    closed <- shiny::reactiveVal(FALSE)
    answered <- shiny::reactiveVal(old_status != "not_answered")
    last_attempt <- NULL
    labelled <- if (old_status %in% specials) old_status else NULL
    stopped <- function() is.function(halted) && !is.null(shiny::isolate(halted()))
    special_of <- function(status, l) if (length(status) == 1L && status %in% specials) special_label(status, l) else NULL
    rating_choices <- function(l, special = NULL) {
      empty <- if (is.null(special)) tr(l, "Bitte w\u00e4hlen", "Choose a rating") else sprintf(tr(l, "Keine Bewertung (%s)", "No rating (%s)"), special)
      c(stats::setNames("", empty), stats::setNames(as.character(unlist(scale$values)), as.character(unlist(scale$values))))
    }
    field_label <- function(l) {
      if (free) {
        base <- if (isTRUE(as.logical(item$required))) tr(l, "Kommentar (erforderlich)", "Comment (required)") else tr(l, "Kommentar (optional)", "Comment (optional)")
        if (several) sprintf(tr(l, "%s: %s", "%s: %s"), humanize_code(item$dimension_code), base) else base
      } else if (several) {
        sprintf(tr(l, "Bewertung: %s", "Rating: %s"), humanize_code(item$dimension_code))
      } else {
        tr(l, "Bewertung", "Rating")
      }
    }
    short_label <- function(l) if (several) humanize_code(item$dimension_code) else if (free) tr(l, "Kommentar", "Comment") else tr(l, "Bewertung", "Rating")
    incomplete <- function(l) if (free) tr(l, "Bitte Text eingeben oder einen anderen Antworttyp angeben.", "Enter text or select another response type.") else tr(l, "Bitte eine Bewertung w\u00e4hlen oder einen anderen Antworttyp angeben.", "Choose a rating or select another response type.")
    define("title", shiny::renderUI({
      l <- lang()
      f <- q$feedback
      st <- statement_text(item, q$protocol, l)
      previous <- previous_version(f, item)
      revised <- !is.na(previous) && length(item$item_version) == 1L && !identical(as.integer(previous), as.integer(item$item_version))
      shiny::tagList(
        if (lead) {
          shiny::tags$h4(
            id = output_id("heading"), if (length(item$number) == 1L) paste0(item$number, ". "), shiny::tags$span(lang = st$lang, st$text), " ",
            shiny::tags$small(paste0("(", if (required) tr(l, "erforderlich", "required") else tr(l, "optional", "optional"), ")"))
          )
        },
        if (lead && st$fallback) shiny::tags$p(class = "del-note", paste(tr(l, "Keine genehmigte \u00dcbersetzung verf\u00fcgbar; angezeigte Sprache:", "No approved translation is available; displayed language:"), st$lang)),
        # A revised statement says so whatever the person answered before.
        if (lead && revised) revision_notice(f, item, previous, q$previous_items, q$protocol, l),
        # Released feedback of the previous round stands beside its statement.
        if (!is.null(f)) feedback_box(f, item, scale, q$protocol, l, id = output_id("feedback"), lead = lead, label = if (several && !free) humanize_code(item$dimension_code), revised = revised)
      )
    }))
    define("form", shiny::renderUI({
      ns <- session$ns
      l <- shiny::isolate(lang())
      kind <- if (choose_kind) shiny::selectInput(ns("kind"), tr(l, "Antworttyp", "Response type"), response_choices(scale, l), selected = old_status, selectize = FALSE)
      controls <- if (free) {
        # The parser drops one line feed after the start tag: a leading line
        # break of the stored text survives the way to the browser.
        shiny::tagList(shiny::textAreaInput(ns("value"), field_label(l), value = paste0("\n", old_value), width = "100%", rows = 3), kind)
      } else {
        rating <- shiny::selectInput(ns("value"), field_label(l), rating_choices(l, special_of(old_status, l)), selected = old_value, selectize = FALSE)
        anchors <- scale_anchors(scale, q$protocol, ns("anchors"))
        if (!is.null(anchors)) rating <- htmltools::tagQuery(rating)$find("select")$addAttrs(`aria-describedby` = ns("anchors"))$allTags()
        shiny::tagList(kind, rating, anchors)
      }
      shiny::tags$fieldset(disabled = if (frozen) "disabled" else NULL, controls)
    }))
    # What the browser shows for the value, as the server last learned it.
    screen_value <- function() {
      pending <- shown_value()
      if (!is.null(pending)) pending else if (is.null(input$value)) old_value else plain_text(input$value)
    }
    observe_event(lang(), {
      l <- lang()
      if (choose_kind) shiny::updateSelectInput(session, "kind", label = tr(l, "Antworttyp", "Response type"), choices = response_choices(scale, l), selected = kind_now())
      if (free) {
        shiny::updateTextAreaInput(session, "value", label = field_label(l))
      } else {
        shiny::updateSelectInput(session, "value", label = field_label(l), choices = rating_choices(l, special_of(labelled, l)), selected = current()$value)
      }
      shiny::updateActionButton(session, "save", label = tr(l, "Jetzt speichern", "Save now"))
    })
    # Entering a value means answering; choosing a special response clears it.
    # The pair shown on screen is therefore always the pair that is stored.
    observe_event(input$value, {
      v <- plain_text(input$value)
      pending <- shown_value()
      if (!is.null(pending)) {
        # Entries sent before the loaded response reached the browser are stale.
        if (identical(v, pending)) shown_value(NULL)
        return()
      }
      k <- kind_now()
      if (nzchar(trimws(v)) && !identical(k, "answered")) {
        kind_now("answered")
        if (choose_kind) shiny::updateSelectInput(session, "kind", selected = "answered")
      } else if (free && !nzchar(trimws(v)) && identical(k, "answered")) {
        kind_now("not_answered")
        if (choose_kind) shiny::updateSelectInput(session, "kind", selected = "not_answered")
      }
    })
    observe_event(input$kind, {
      k <- input$kind
      if (!identical(k, kind_now())) kind_now(k)
      value <- screen_value()
      if (free) {
        if (!identical(k, "answered") && nzchar(value)) shiny::updateTextAreaInput(session, "value", value = "")
      } else {
        special <- if (k %in% specials) k else NULL
        if (!identical(special, labelled) || (!identical(k, "answered") && nzchar(value))) {
          labelled <<- special
          shiny::updateSelectInput(session, "value", choices = rating_choices(lang(), special_of(special, lang())), selected = if (identical(k, "answered")) value else "")
        }
      }
    })
    # Read by everything that depends on the controls of this field. When the
    # field leaves the page it is switched off once, which releases what the
    # session still holds of it.
    alive <- shiny::reactiveVal(TRUE)
    current <- shiny::reactive({
      alive()
      status <- kind_now()
      value <- screen_value()
      # A value shown beside a special response is never part of the answer.
      list(status = status, value = if (identical(status, "answered")) value else "")
    })
    dirty <- shiny::reactive(!frozen && !identical(current(), baseline()))
    complete <- shiny::reactive(current()$status != "answered" || nzchar(trimws(current()$value)))
    # The state of the field in words; untouched fields say nothing.
    report <- shiny::reactive({
      l <- lang()
      out <- function(tone, text) list(tone = tone, text = text, label = short_label(l))
      if (identical(round_mode, "submitted")) {
        return(if (answered()) out("saved", tr(l, "Abgegeben", "Submitted")) else out("neutral", ""))
      }
      if (conflict() || dirty()) {
        detail <- if (conflict() || save_failed()) localize_status(message(), l) else if (!complete()) incomplete(l) else ""
        return(out("attention", trimws(paste(tr(l, "Noch nicht gespeichert.", "Not saved yet."), detail))))
      }
      if (nzchar(message()) && !save_failed()) {
        return(out(if (revision() > 0) "saved" else "neutral", localize_status(message(), l)))
      }
      if (revision() > 0) {
        return(out("saved", saved_text(saved_at(), zone, l)))
      }
      out("neutral", "")
    })
    if (is.null(card)) {
      define("save_status", shiny::renderUI({
        r <- report()
        shiny::tags$div(class = paste("del-status", paste0("del-status--", r$tone)), role = "status", `aria-live` = "polite", shiny::textOutput(output_id("status")))
      }))
      define("status", shiny::renderText(report()$text))
      if (is.null(place)) shiny::outputOptions(output, "status", suspendWhenHidden = FALSE) else place$options("status", suspendWhenHidden = FALSE)
    }
    save_now <- function() {
      if (frozen || !shiny::isolate(dirty())) {
        return(TRUE)
      }
      if (!shiny::isolate(complete())) {
        return(FALSE)
      }
      a <- shiny::isolate(current())
      value <- if (a$status != "answered") NULL else if (free) a$value else suppressWarnings(as.numeric(a$value))
      expected <- shiny::isolate(revision())
      # An identical retry reuses its key, so a save whose reply was lost
      # returns the original receipt instead of a false conflict.
      attempt <- list(payload = a, revision = expected)
      key <- if (!is.null(last_attempt) && identical(last_attempt$attempt, attempt)) last_attempt$key else command_id()
      last_attempt <<- list(attempt = attempt, key = key)
      l <- shiny::isolate(lang())
      tryCatch(
        {
          r <- call("save_response", q$enrollment$id, item$id, list(value = value, status = a$status), expected, key)
          save_failed(FALSE)
          conflict(FALSE)
          closed(FALSE)
          revision(r$revision)
          baseline(a)
          saved_at(r$saved_at)
          answered(a$status != "not_answered")
          message("")
          if (is.function(on_saved)) on_saved(item$id, r$revision, a$status)
          TRUE
        },
        error = function(e) {
          save_failed(TRUE)
          # The enrollment no longer accepts answers: submitted or ended elsewhere.
          ended <- inherits(e, "DEL_CONFLICT") && identical(e$path, "enrollment.state")
          if (inherits(e, "DEL_CONFLICT") && !ended) conflict(TRUE)
          if (inherits(e, "DEL_ROUND_CLOSED") || ended) closed(TRUE)
          message(if (ended) {
            paste(closed_text("ended", round_mode, l), reference_text(error_reference(e), l))
          } else if (inherits(e, "DEL_FORBIDDEN") && identical(e$path, "consent")) {
            paste(tr(l, "Die Einwilligung f\u00fcr diese Runde fehlt. Bitte willigen Sie oben ein, damit Ihre Antworten gespeichert werden k\u00f6nnen.", "Consent for this round is missing. Give consent above so that your answers can be saved."), reference_text(error_reference(e), l))
          } else {
            safe_error(e, l)
          })
          if (is.function(on_halt) && (inherits(e, "DEL_ROUND_CLOSED") || ended)) on_halt(if (ended) "ended" else "closed")
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
    if (is.numeric(autosave_ms) && length(autosave_ms) == 1L && autosave_ms > 0 && !frozen) {
      # The pause before an automatic save: every change of the entry starts
      # it again, and when it has passed the entry on screen is saved. It is
      # built from observers of this field, so that it ends with the field.
      now <- function() if (is.function(session$.now)) session$.now() else as.numeric(Sys.time()) * 1000
      due <- shiny::reactiveVal(NULL)
      observe_event(current(), due(now() + autosave_ms), ignoreInit = TRUE)
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
        if (!shiny::isolate(conflict()) && !shiny::isolate(closed()) && !stopped()) save_now()
      })
    }
    define("conflict", shiny::renderUI({
      shiny::req(conflict())
      shiny::tags$div(class = "del-actions", shiny::actionButton(session$ns("reload"), tr(lang(), "Gespeicherten Stand laden und meine Eingabe verwerfen", "Load the saved response and discard my entry"), class = "btn-outline-danger"))
    }))
    # Loading the saved response discards the entry at once: from here on the
    # field holds the loaded state, also before the browser shows it.
    observe_event(input$reload, {
      shiny::req(conflict())
      l <- lang()
      tryCatch(
        {
          fresh <- stored(call("get_questionnaire", q$enrollment$id)$responses)
          on_screen <- if (is.null(input$value)) old_value else plain_text(input$value)
          revision(fresh$revision)
          saved_at(fresh$saved_at)
          if (is.function(on_saved)) on_saved(item$id, fresh$revision, fresh$status)
          baseline(list(status = fresh$status, value = fresh$value))
          kind_now(fresh$status)
          shown_value(if (identical(on_screen, fresh$value)) NULL else fresh$value)
          answered(fresh$status != "not_answered")
          if (choose_kind) shiny::updateSelectInput(session, "kind", selected = fresh$status)
          if (free) {
            shiny::updateTextAreaInput(session, "value", value = fresh$value)
          } else {
            labelled <<- if (fresh$status %in% specials) fresh$status else NULL
            shiny::updateSelectInput(session, "value", choices = rating_choices(l, special_of(labelled, l)), selected = fresh$value)
          }
          last_attempt <<- NULL
          save_failed(FALSE)
          conflict(FALSE)
          message(tr(l, "Gespeicherter Stand geladen.", "Saved response loaded."))
        },
        error = function(e) message(safe_error(e, l))
      )
    })
    # When another field takes this place, nothing of this one reacts any more.
    destroy <- function() {
      for (observer in observers) observer$destroy()
      observers <<- list()
      shiny::isolate(alive(FALSE))
      invisible(TRUE)
    }
    list(dirty = dirty, revision = revision, answered = answered, save_now = save_now, conflict = conflict, destroy = destroy, report = report)
  })
}
# A browser reports line breaks as line feeds.
plain_text <- function(x) gsub("\r\n?", "\n", as.character(x))
special_labels <- function(lang) tr(lang, c(unable_to_judge = "Kann ich nicht beurteilen", abstained = "Enthaltung", not_applicable = "Nicht zutreffend"), c(unable_to_judge = "Unable to judge", abstained = "Abstain", not_applicable = "Not applicable"))
special_label <- function(code, lang) {
  labels <- special_labels(lang)
  if (length(code) == 1L && code %in% names(labels)) unname(labels[code]) else humanize_code(code)
}
response_choices <- function(scale, lang) {
  opts <- stats::setNames(c("answered", "not_answered"), c(tr(lang, "Antwort geben", "Give a response"), tr(lang, "Unbeantwortet", "Unanswered")))
  missing <- as.character(unlist(scale$missing_options))
  c(opts, stats::setNames(missing, vapply(missing, special_label, character(1), lang = lang)))
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
