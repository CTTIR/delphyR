protocols_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

protocols_server <- function(id, study, lang, call, services) {
  shiny::moduleServer(id, function(input, output, session) {
    allowed <- shiny::reactiveVal(FALSE)
    versions <- shiny::reactiveVal(data.frame())
    candidate <- shiny::reactiveVal(NULL)
    file_ready <- shiny::reactiveVal(FALSE)
    # The rationale and confirmation of each validated version carry their
    # own input ids: a confirmation counts only for the version it was given
    # for, and text typed for another study or for an approved version is
    # never offered or read again.
    form <- shiny::reactiveVal(0L)
    field_id <- function(name, key = form()) paste0(name, "_", key)
    next_form <- function() form(shiny::isolate(form()) + 1L)
    status <- shiny::reactiveVal("")
    ready <- all(c("get_capabilities", "list_protocol_versions", "amend_protocol") %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    refresh <- function() versions(call("list_protocol_versions", study()))
    shiny::observeEvent(study(), {
      candidate(NULL)
      file_ready(FALSE)
      next_form()
      versions(data.frame())
      allowed(FALSE)
      status("")
      if (ready) {
        attempt(function() {
          allowed("manage" %in% call("get_capabilities", study()))
          if (allowed()) refresh()
        })
      }
    })
    output$body <- shiny::renderUI({
      shiny::req(allowed())
      ns <- session$ns
      l <- lang()
      shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Protokollversionen", "Protocol versions")),
        shiny::tags$p(tr(l, "\u00c4nderungen gelten nur f\u00fcr zuk\u00fcnftige Runden. Bestehende Runden und eingefrorene Daten behalten ihr urspr\u00fcngliches Protokoll. Diese technische Freigabe ersetzt keine institutionelle oder ethische Genehmigung.", "Amendments apply only to future rounds. Existing rounds and frozen data retain their original protocol. This technical approval does not replace institutional or ethics approval.")),
        shiny::tableOutput(ns("history")),
        shiny::tags$h3(tr(l, "Gespeicherte Version ansehen", "Inspect a saved version")),
        shiny::uiOutput(ns("version_selector")),
        shiny::tableOutput(ns("saved_summary")),
        shiny::tags$details(shiny::tags$summary(tr(l, "Vollst\u00e4ndiges Protokoll dieser Version (JSON)", "Complete protocol of this version (JSON)")), shiny::verbatimTextOutput(ns("saved"))),
        shiny::tags$h3(tr(l, "Protokoll \u00e4ndern", "Amend the protocol")),
        shiny::tags$p(tr(l, "Laden Sie das vollst\u00e4ndige neue Protokoll als JSON hoch. Die Vorschau zeigt jede \u00c4nderung gegen\u00fcber der aktuellen Version; erst Ihre Freigabe speichert eine neue Version.", "Upload the complete new protocol as JSON. The preview shows every change from the current version; only your approval saves a new version.")),
        file_input(ns("file"), tr(l, "Neues Protokoll (JSON, h\u00f6chstens 1 MB)", "New protocol (JSON, maximum 1 MB)"), accept = ".json", buttonLabel = tr(l, "Durchsuchen\u2026", "Browse\u2026"), placeholder = tr(l, "Keine Datei ausgew\u00e4hlt", "No file selected")),
        shiny::uiOutput(ns("validate_action")),
        shiny::uiOutput(ns("approval")),
        status_ui(ns("status"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    output$version_selector <- shiny::renderUI({
      v <- versions()
      shiny::req(nrow(v) > 0)
      shiny::selectInput(session$ns("version"), tr(lang(), "Gespeicherte Version", "Saved version"), list_choices(v$id, paste(tr(lang(), "Version", "Version"), v$version)), selected = utils::tail(v$id, 1))
    })
    output$history <- shiny::renderTable({
      v <- versions()
      shiny::req(nrow(v) > 0)
      l <- lang()
      occurred <- if ("occurred_at" %in% names(v)) v$occurred_at else rep(NA, nrow(v))
      # The first version has no amendment; it was approved with the study.
      approved <- ifelse(is.na(occurred), tr(l, "Mit der Studie angelegt", "Created with the study"), format_moment(occurred, protocol_zone(v), l))
      label <- ifelse(v$version == max(v$version), paste(v$version, tr(l, "(aktuell)", "(current)")), as.character(v$version))
      out <- data.frame(label, approved, ifelse(is.na(v$reason), tr(l, "Erstfassung", "Initial version"), v$reason), stringsAsFactors = FALSE)
      names(out) <- tr(l, c("Version", "Freigegeben", "Begr\u00fcndung"), c("Version", "Approved", "Rationale"))
      out
    })
    saved_version <- shiny::reactive({
      v <- versions()
      shiny::req(input$version)
      x <- v$config[v$id == input$version]
      shiny::req(length(x) == 1)
      template_order(jsonlite::fromJSON(x, simplifyVector = FALSE), delphyr::demo_protocol())
    })
    output$saved_summary <- shiny::renderTable(protocol_summary(saved_version(), lang()))
    output$saved <- shiny::renderText(protocol_json(saved_version()))
    output$validate_action <- shiny::renderUI({
      l <- lang()
      chosen <- file_ready()
      shiny::tagList(
        shiny::tags$div(class = "del-actions", shiny::actionButton(session$ns("validate"), tr(l, "Validieren und genaue Vorschau erstellen", "Validate and preview exact protocol"), disabled = !chosen)),
        if (!chosen) shiny::tags$p(class = "del-note", tr(l, "Zuerst eine Protokolldatei ausw\u00e4hlen.", "Choose a protocol file first."))
      )
    })
    shiny::observeEvent(input$file,
      {
        candidate(NULL)
        file_ready(!is.null(input$file))
      },
      ignoreNULL = FALSE
    )
    # A change of language draws an empty file field; nothing chosen before
    # is used without being shown.
    shiny::observeEvent(lang(),
      {
        candidate(NULL)
        file_ready(FALSE)
      },
      ignoreInit = TRUE
    )
    shiny::observeEvent(input$validate, attempt(function() {
      shiny::req(allowed())
      if (!file_ready()) {
        status(tr(lang(), "Zuerst eine Protokolldatei ausw\u00e4hlen.", "Choose a protocol file first."))
        return()
      }
      # A rationale typed for an earlier file of this study and not approved
      # is offered again for the next one; a confirmation is not.
      draft <- input[[field_id("reason")]]
      candidate(NULL)
      p <- tryCatch(read_protocol_upload(input$file), error = function(e) {
        status(protocol_upload_error(e, lang()))
        NULL
      })
      if (is.null(p)) {
        return()
      }
      v <- call("list_protocol_versions", study())
      shiny::req(nrow(v) > 0)
      latest <- v[which.max(v$version), , drop = FALSE]
      previous <- delphyr::new_protocol(jsonlite::fromJSON(latest$config, simplifyVector = FALSE))
      hash <- delphyr::content_hash(p)
      if (identical(hash, latest$hash)) {
        status(tr(lang(), "Das hochgeladene Protokoll entspricht der aktuellen Version; es gibt nichts freizugeben.", "The uploaded protocol is identical to the current version; there is nothing to approve."))
        return()
      }
      next_form()
      candidate(list(protocol = p, hash = hash, expected_hash = latest$hash, based_on = latest$version, previous = previous, draft = if (is.null(draft)) "" else draft))
      status(tr(lang(), "Protokoll validiert. Noch keine neue Fassung gespeichert.", "Protocol validated. No new version has been saved."))
    }))
    # Approval is offered only for a validated preview.
    output$approval <- shiny::renderUI({
      x <- candidate()
      key <- form()
      ns <- session$ns
      l <- lang()
      if (is.null(x)) {
        # Before a file is chosen, the validation step names what is missing.
        if (!file_ready()) {
          return(NULL)
        }
        return(shiny::tags$p(class = "del-note", tr(l, "Nach der Pr\u00fcfung einer Protokolldatei erscheinen hier ihre \u00c4nderungen und die Freigabe.", "After a protocol file is validated, its changes and the approval appear here.")))
      }
      typed <- shiny::isolate(input[[field_id("reason", key)]])
      shiny::tagList(
        shiny::uiOutput(ns("preview_heading")),
        shiny::tableOutput(ns("changes")),
        shiny::tags$details(shiny::tags$summary(tr(l, "Vollst\u00e4ndige Vorschau", "Complete preview")), shiny::verbatimTextOutput(ns("preview"))),
        shiny::textAreaInput(ns(field_id("reason", key)), tr(l, "Begr\u00fcndung der Protokoll\u00e4nderung", "Protocol amendment rationale"), value = if (is.null(typed)) x$draft else typed, width = "100%"),
        shiny::checkboxInput(ns(field_id("confirm", key)), tr(l, "Ich habe diese genaue Fassung und ihre Geltung nur f\u00fcr zuk\u00fcnftige Runden gepr\u00fcft.", "I reviewed this exact version and its application only to future rounds."), FALSE),
        shiny::tags$div(class = "del-actions", shiny::actionButton(ns("approve"), tr(l, "Neue Protokollversion freigeben", "Approve new protocol version"), class = "btn-primary"))
      )
    })
    output$preview_heading <- shiny::renderUI({
      x <- candidate()
      shiny::req(x)
      shiny::tags$h4(paste(tr(lang(), "\u00c4nderungen gegen\u00fcber Version", "Changes from version"), x$based_on))
    })
    output$preview <- shiny::renderText({
      x <- candidate()
      shiny::req(x)
      protocol_json(x$protocol)
    })
    output$changes <- shiny::renderTable({
      x <- candidate()
      shiny::req(x)
      changes <- protocol_changes(x$previous, x$protocol)
      names(changes) <- c(tr(lang(), "Feld", "Field"), tr(lang(), "Bisher", "Previous"), tr(lang(), "Vorgeschlagen", "Proposed"))
      changes
    })
    shiny::observeEvent(input$approve, attempt(function() {
      x <- candidate()
      key <- form()
      shiny::req(allowed(), x)
      # Only the rationale and confirmation of the form shown for this
      # version count.
      reason <- input[[field_id("reason", key)]]
      reason <- if (is.null(reason)) "" else trimws(reason)
      if (!isTRUE(input[[field_id("confirm", key)]]) || !nzchar(reason)) {
        status(tr(lang(), "Begr\u00fcndung und Best\u00e4tigung sind erforderlich.", "A reason and confirmation are required."))
        return()
      }
      current <- if (file_ready()) tryCatch(delphyr::content_hash(read_protocol_upload(input$file)), error = function(e) NA_character_) else NA_character_
      if (!identical(current, x$hash)) {
        status(tr(lang(), "Die Datei wurde nach der Pr\u00fcfung ge\u00e4ndert. Bitte erneut pr\u00fcfen.", "The file changed after it was validated. Validate it again."))
        return()
      }
      result <- call("amend_protocol", study(), x$protocol, x$expected_hash, reason, command_id())
      candidate(NULL)
      next_form()
      refresh()
      status(paste(tr(lang(), "Neue Version best\u00e4tigt:", "New version confirmed:"), result$version))
    }))
    list(candidate = candidate, versions = versions, file_ready = file_ready, form = form)
  })
}

read_protocol_upload <- function(file) {
  if (is.null(file$size) || length(file$size) != 1L || !is.finite(file$size) || file$size < 1 || file$size > 1e6 || file.info(file$datapath)$size > 1e6) stop("Protocol file must be at most 1 MB")
  delphyr::new_protocol(jsonlite::fromJSON(file$datapath, simplifyVector = FALSE))
}

# Why an uploaded protocol cannot be used: the field at fault, or that the
# file is not a protocol of the allowed size.
protocol_upload_error <- function(e, lang) {
  path <- if (inherits(e, "delphyr_error") && is.character(e$path) && length(e$path) == 1L && nzchar(e$path)) e$path else ""
  if (nzchar(path)) {
    return(paste(tr(lang, "Protokoll ung\u00fcltig. Beanstandetes Feld:", "Protocol is invalid. Field in question:"), path))
  }
  tr(lang, "Die Datei ist kein lesbares Protokoll: erwartet wird JSON von h\u00f6chstens 1 MB.", "The file is not a readable protocol: JSON of at most 1 MB is expected.")
}

# The time zone of the study in its current protocol.
protocol_zone <- function(versions) {
  latest <- versions$config[which.max(versions$version)]
  zone <- tryCatch(jsonlite::fromJSON(latest, simplifyVector = FALSE)$study$timezone, error = function(e) NULL)
  if (is.character(zone) && length(zone) == 1L) zone else "UTC"
}

# The keys of a stored protocol in the order of the protocol template; the
# database keeps keys in an order of its own.
template_order <- function(x, template) {
  if (!is.list(x) || !is.list(template)) {
    return(x)
  }
  if (is.null(names(x))) {
    if (length(template) && is.null(names(template))) {
      return(lapply(x, template_order, template = template[[1]]))
    }
    return(x)
  }
  keys <- c(intersect(names(template), names(x)), setdiff(names(x), names(template)))
  out <- x[keys]
  for (k in intersect(keys, names(template))) if (is.list(out[[k]])) out[[k]] <- template_order(out[[k]], template[[k]])
  out
}

protocol_changes <- function(previous, proposed) {
  flatten <- function(x, path = "") {
    if (!is.list(x)) {
      return(stats::setNames(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA), path))
    }
    if (!length(x)) {
      return(stats::setNames("[]", path))
    }
    keys <- names(x)
    if (is.null(keys)) keys <- as.character(seq_along(x))
    unlist(lapply(seq_along(x), function(i) flatten(x[[i]], if (nzchar(path)) paste(path, keys[i], sep = ".") else keys[i])), use.names = TRUE)
  }
  old <- flatten(unclass(previous))
  new <- flatten(unclass(proposed))
  keys <- union(names(old), names(new))
  before <- unname(old[keys])
  after <- unname(new[keys])
  changed <- is.na(before) | is.na(after) | before != after
  data.frame(field = keys[changed], previous = ifelse(is.na(before[changed]), "", before[changed]), proposed = ifelse(is.na(after[changed]), "", after[changed]), stringsAsFactors = FALSE)
}
