panel_import_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

panel_import_server <- function(id, study, lang, call, services) {
  shiny::moduleServer(id, function(input, output, session) {
    field <- function(name, default = "") {
      value <- shiny::isolate(input[[name]])
      if (is.null(value)) default else value
    }
    allowed <- shiny::reactiveVal(FALSE)
    preview <- shiny::reactiveVal(NULL)
    receipt <- shiny::reactiveVal(NULL)
    status <- shiny::reactiveVal("")
    ready <- all(c("get_capabilities", "preview_panel_import", "import_panel", "get_panel_import_receipt") %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    shiny::observeEvent(study(), {
      allowed(FALSE)
      preview(NULL)
      receipt(NULL)
      if (ready) attempt(function() allowed("coordinate" %in% call("get_capabilities", study())))
    })
    output$body <- shiny::renderUI({
      shiny::req(allowed())
      ns <- session$ns
      l <- lang()
      shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Synthetischer Panelimport", "Synthetic panel import")),
        shiny::tags$p(class = "del-banner", tr(l, "Nur synthetische Kontakte mit .invalid-Adressen. Der Import erstellt ungebundene Einladungsentw\u00fcrfe. Er erstellt keine Konten, ordnet keine Antworten zu und versendet keine E-Mails.", "Synthetic contacts with .invalid addresses only. Import creates unbound invitation drafts. It does not create accounts, associate responses, or send email.")),
        shiny::tags$p(tr(l, "CSV-Spalten: external_ref, email, display_name, locale, stakeholder_group. UTF-8; die gesamte Datei muss vor dem Import fehlerfrei sein.", "CSV columns: external_ref, email, display_name, locale, stakeholder_group. Use UTF-8; the entire file must pass validation before import.")),
        shiny::fileInput(ns("file"), tr(l, "Paneldatei (CSV, h\u00f6chstens 1 MiB)", "Panel file (CSV, maximum 1 MiB)"), accept = ".csv", buttonLabel = tr(lang(), "Durchsuchen\u2026", "Browse\u2026"), placeholder = tr(lang(), "Keine Datei ausgew\u00e4hlt", "No file selected")),
        shiny::selectInput(ns("schema"), tr(l, "Dateischema", "File schema"), c("1.0" = "1.0"), selected = field("schema", "1.0")),
        shiny::selectInput(ns("delimiter"), tr(l, "Trennzeichen", "Delimiter"), stats::setNames(c(",", ";"), c(tr(l, "Komma", "Comma"), tr(l, "Semikolon", "Semicolon"))), selected = field("delimiter", ",")),
        shiny::actionButton(ns("preview"), tr(l, "Datei pr\u00fcfen und Vorschau erstellen", "Validate file and create preview")),
        shiny::uiOutput(ns("summary")),
        shiny::tableOutput(ns("issues")),
        shiny::tableOutput(ns("rows")),
        shiny::textAreaInput(ns("reason"), tr(l, "Importbegr\u00fcndung", "Import rationale"), value = field("reason"), width = "100%"),
        shiny::checkboxInput(ns("confirm"), tr(l, "Ich habe diese genaue Datei und alle angezeigten Kontakte gepr\u00fcft.", "I reviewed this exact file and every displayed contact."), FALSE),
        shiny::actionButton(ns("approve"), tr(l, "Gepr\u00fcfte Einladungsentw\u00fcrfe importieren", "Import reviewed invitation drafts")),
        shiny::uiOutput(ns("receipt")), status_ui(ns("status"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    shiny::observeEvent(list(input$file, input$schema, input$delimiter),
      {
        preview(NULL)
        shiny::updateCheckboxInput(session, "confirm", value = FALSE)
      },
      ignoreNULL = FALSE
    )
    shiny::observeEvent(input$preview, attempt(function() {
      shiny::req(allowed(), input$file, input$schema, input$delimiter)
      p <- call("preview_panel_import", study(), panel_upload_bytes(input$file), schema_version = input$schema, delimiter = input$delimiter)
      preview(p)
      receipt(NULL)
      shiny::updateCheckboxInput(session, "confirm", value = FALSE)
      status(if (isTRUE(p$valid)) tr(lang(), "Vorschau fehlerfrei. Es wurde noch nichts importiert.", "Preview passed validation. Nothing has been imported yet.") else tr(lang(), "Import gesperrt. Beheben Sie alle Fehler und pr\u00fcfen Sie eine neue Datei.", "Import blocked. Correct every issue and preview a new file."))
    }))
    output$summary <- shiny::renderUI({
      p <- preview()
      shiny::req(p)
      shiny::tagList(
        shiny::tags$h3(tr(lang(), "Gesch\u00fctzte Kontaktvorschau", "Restricted contact preview")),
        shiny::tags$p(paste(nrow(p$rows), tr(lang(), "Zeilen in der Datei.", "rows in the file."))),
        if (!isTRUE(p$valid)) shiny::tags$p(tr(lang(), "Keine Teilimporte: Die gesamte Datei bleibt gesperrt.", "No partial import: the entire file remains blocked."))
      )
    })
    output$issues <- shiny::renderTable({
      p <- preview()
      shiny::req(p)
      if (!nrow(p$issues)) {
        return(NULL)
      }
      x <- p$issues
      x$row <- ifelse(x$row == 0, tr(lang(), "Datei", "File"), as.character(x$row))
      x$code <- panel_issue_label(x$code, lang())
      names(x) <- c(tr(lang(), "Zeile", "Row"), tr(lang(), "Spalte", "Column"), tr(lang(), "Problem", "Issue"))
      x
    })
    output$rows <- shiny::renderTable(
      {
        p <- preview()
        shiny::req(p)
        x <- p$rows[, c("source_row", "external_ref", "normalized_email", "display_name", "locale", "stakeholder_group"), drop = FALSE]
        names(x) <- tr(lang(), c("Zeile", "Quellenreferenz", "Normalisierte E-Mail", "Anzeigename", "Sprache", "Interessengruppe"), c("Row", "Source reference", "Normalized email", "Display name", "Language", "Stakeholder group"))
        x
      },
      striped = TRUE
    )
    shiny::observeEvent(input$approve, attempt(function() {
      p <- preview()
      shiny::req(allowed(), p, isTRUE(input$confirm), input$file)
      if (!isTRUE(p$valid)) stop("Import has blocking issues")
      if (is.null(input$reason) || !nzchar(trimws(input$reason))) stop("Import rationale required")
      if (!identical(panel_upload_bytes(input$file), p$csv) || !identical(input$schema, p$schema_version) || !identical(input$delimiter, p$delimiter)) stop("File or interpretation changed after preview")
      result <- call("import_panel", study(), p, p$hash, input$reason, command_id())
      receipt(call("get_panel_import_receipt", result$id))
      preview(NULL)
      shiny::updateCheckboxInput(session, "confirm", value = FALSE)
      status(tr(lang(), "Import best\u00e4tigt. Die Einladungsentw\u00fcrfe sind weiterhin ungebunden; keine E-Mail wurde versendet.", "Import confirmed. Invitation drafts remain unbound; no email was sent."))
    }))
    output$receipt <- shiny::renderUI({
      x <- receipt()
      shiny::req(x)
      r <- x$receipt
      shiny::tagList(
        shiny::tags$h3(tr(lang(), "Importbeleg", "Import receipt")),
        shiny::tags$p(paste(r$accepted_rows, tr(lang(), "Kontakte importiert;", "contacts imported;"), length(x$invitation_ids), tr(lang(), "ungebundene Einladungsentw\u00fcrfe.", "unbound invitation drafts."))),
        shiny::tags$p(paste(tr(lang(), "Beleg:", "Receipt:"), r$id)),
        shiny::tags$p(paste(format(as.POSIXct(r$imported_at, tz = "UTC"), "%Y-%m-%d %H:%M:%S %z", tz = "UTC"), "UTC"))
      )
    })
  })
}

panel_upload_bytes <- function(file) {
  if (is.null(file$datapath) || is.null(file$size) || length(file$size) != 1L || !is.finite(file$size) || file$size < 1 || file$size > 1024L * 1024L) stop("CSV must be at most 1 MiB")
  bytes <- readBin(file$datapath, what = "raw", n = 1024L * 1024L + 1L)
  if (!length(bytes) || length(bytes) > 1024L * 1024L) stop("CSV must be at most 1 MiB")
  bytes
}

panel_issue_label <- function(code, lang) {
  en <- c(csv_parse_error = "CSV could not be parsed", csv_schema_columns = "Columns do not match the selected schema", empty_import = "No contact rows", invalid_external_ref = "Invalid source reference", invalid_display_name = "Invalid display name", synthetic_email_required = "A valid synthetic .invalid email is required", unsupported_locale = "Language is not supported by this study", unknown_group = "Stakeholder group is not in the protocol", duplicate_in_file = "Duplicate in this file; resolve explicitly", email_case_review = "Email case variants require explicit review", existing_external_ref = "Source reference already exists", existing_email = "Email already exists", existing_email_case_review = "Existing email case variant requires review")
  de <- c(csv_parse_error = "CSV konnte nicht gelesen werden", csv_schema_columns = "Spalten passen nicht zum Dateischema", empty_import = "Keine Kontaktzeilen", invalid_external_ref = "Ung\u00fcltige Quellenreferenz", invalid_display_name = "Ung\u00fcltiger Anzeigename", synthetic_email_required = "G\u00fcltige synthetische .invalid-Adresse erforderlich", unsupported_locale = "Sprache ist f\u00fcr diese Studie nicht vorgesehen", unknown_group = "Interessengruppe fehlt im Protokoll", duplicate_in_file = "Duplikat in dieser Datei; ausdr\u00fccklich aufl\u00f6sen", email_case_review = "Gro\u00df-/Kleinschreibung der Adresse pr\u00fcfen", existing_external_ref = "Quellenreferenz existiert bereits", existing_email = "E-Mail-Adresse existiert bereits", existing_email_case_review = "Schreibvariante vorhandener Adresse pr\u00fcfen")
  labels <- tr(lang, de, en)
  unname(ifelse(code %in% names(labels), labels[code], code))
}
