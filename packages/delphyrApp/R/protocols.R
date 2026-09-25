protocols_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

protocols_server <- function(id, study, lang, call, services) {
  shiny::moduleServer(id, function(input, output, session) {
    allowed <- shiny::reactiveVal(FALSE)
    versions <- shiny::reactiveVal(data.frame())
    candidate <- shiny::reactiveVal(NULL)
    status <- shiny::reactiveVal("")
    ready <- all(c("get_capabilities", "list_protocol_versions", "amend_protocol") %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    refresh <- function() versions(call("list_protocol_versions", study()))
    shiny::observeEvent(study(), {
      candidate(NULL)
      versions(data.frame())
      allowed(FALSE)
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
        shiny::uiOutput(ns("version_selector")),
        shiny::tags$details(shiny::tags$summary(tr(l, "Gespeicherte Fassung ansehen", "Inspect saved version")), shiny::verbatimTextOutput(ns("saved"))),
        shiny::fileInput(ns("file"), tr(l, "Vollst\u00e4ndiges neues Protokoll (JSON, h\u00f6chstens 1 MB)", "Complete new protocol (JSON, maximum 1 MB)"), accept = ".json"),
        shiny::actionButton(ns("validate"), tr(l, "Validieren und genaue Vorschau erstellen", "Validate and preview exact protocol")),
        shiny::uiOutput(ns("preview_heading")),
        shiny::tableOutput(ns("changes")),
        shiny::tags$details(shiny::tags$summary(tr(l, "Vollst\u00e4ndige Vorschau", "Complete preview")), shiny::verbatimTextOutput(ns("preview"))),
        shiny::textAreaInput(ns("reason"), tr(l, "Begr\u00fcndung der Protokoll\u00e4nderung", "Protocol amendment rationale"), width = "100%"),
        shiny::checkboxInput(ns("confirm"), tr(l, "Ich habe diese genaue Fassung und ihre Geltung nur f\u00fcr zuk\u00fcnftige Runden gepr\u00fcft.", "I reviewed this exact version and its application only to future rounds."), FALSE),
        shiny::actionButton(ns("approve"), tr(l, "Neue Protokollversion freigeben", "Approve new protocol version")),
        status_ui(ns("status"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(status())
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    output$version_selector <- shiny::renderUI({
      v <- versions()
      shiny::req(nrow(v))
      shiny::selectInput(session$ns("version"), tr(lang(), "Gespeicherte Version", "Saved version"), stats::setNames(v$id, paste(tr(lang(), "Version", "Version"), v$version)), selected = utils::tail(v$id, 1))
    })
    output$history <- shiny::renderTable({
      v <- versions()
      shiny::req(nrow(v))
      out <- data.frame(version = v$version, reason = ifelse(is.na(v$reason), tr(lang(), "Erstfassung", "Initial version"), v$reason), stringsAsFactors = FALSE)
      names(out) <- c(tr(lang(), "Version", "Version"), tr(lang(), "Begr\u00fcndung", "Rationale"))
      out
    })
    output$saved <- shiny::renderText({
      v <- versions()
      shiny::req(input$version)
      x <- v$config[v$id == input$version]
      shiny::req(length(x) == 1)
      jsonlite::prettify(x)
    })
    shiny::observeEvent(input$file,
      {
        candidate(NULL)
        shiny::updateCheckboxInput(session, "confirm", value = FALSE)
      },
      ignoreNULL = FALSE
    )
    shiny::observeEvent(input$validate, attempt(function() {
      shiny::req(allowed(), input$file)
      p <- read_protocol_upload(input$file)
      v <- call("list_protocol_versions", study())
      shiny::req(nrow(v))
      latest <- v[which.max(v$version), , drop = FALSE]
      previous <- delphyr::new_protocol(jsonlite::fromJSON(latest$config, simplifyVector = FALSE))
      hash <- delphyr::content_hash(p)
      if (identical(hash, latest$hash)) stop("Protocol is unchanged")
      candidate(list(protocol = p, hash = hash, expected_hash = latest$hash, based_on = latest$version, previous = previous))
      shiny::updateCheckboxInput(session, "confirm", value = FALSE)
      status(tr(lang(), "Protokoll validiert. Noch keine neue Fassung gespeichert.", "Protocol validated. No new version has been saved."))
    }))
    output$preview_heading <- shiny::renderUI({
      x <- candidate()
      shiny::req(x)
      shiny::tags$p(paste(tr(lang(), "Vorschau auf Basis von Version", "Preview based on version"), x$based_on))
    })
    output$preview <- shiny::renderText({
      x <- candidate()
      shiny::req(x)
      jsonlite::toJSON(unclass(x$protocol), auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
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
      shiny::req(allowed(), x, isTRUE(input$confirm), input$file)
      if (is.null(input$reason) || !nzchar(trimws(input$reason))) stop("Amendment rationale is required")
      current <- read_protocol_upload(input$file)
      if (!identical(delphyr::content_hash(current), x$hash)) stop("Upload changed since preview")
      result <- call("amend_protocol", study(), x$protocol, x$expected_hash, input$reason, command_id())
      candidate(NULL)
      refresh()
      shiny::updateCheckboxInput(session, "confirm", value = FALSE)
      status(paste(tr(lang(), "Neue Version best\u00e4tigt:", "New version confirmed:"), result$version))
    }))
  })
}

read_protocol_upload <- function(file) {
  if (is.null(file$size) || length(file$size) != 1L || !is.finite(file$size) || file$size < 1 || file$size > 1e6 || file.info(file$datapath)$size > 1e6) stop("Protocol file must be at most 1 MB")
  delphyr::new_protocol(jsonlite::fromJSON(file$datapath, simplifyVector = FALSE))
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
