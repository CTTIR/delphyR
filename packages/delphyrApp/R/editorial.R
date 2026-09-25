editorial_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

editorial_server <- function(id, study, lang, call, services) {
  shiny::moduleServer(id, function(input, output, session) {
    caps <- shiny::reactiveVal(character())
    records <- shiny::reactiveVal(NULL)
    reviews <- shiny::reactiveVal(data.frame())
    reviewed <- shiny::reactiveVal(NULL)
    lineage <- shiny::reactiveVal(NULL)
    status <- shiny::reactiveVal("")
    needed <- c("get_capabilities", "get_qualitative_provenance", "list_qualitative_reviews", "record_qualitative_source", "redact_qualitative_source", "release_qualitative_edit", "create_qualitative_theme", "code_qualitative_source", "link_item_source", "record_item_lineage")
    ready <- all(needed %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    refresh <- function() {
      caps(call("get_capabilities", study()))
      records(if ("edit" %in% caps()) call("get_qualitative_provenance", study()) else NULL)
      reviews(if ("manage" %in% caps()) call("list_qualitative_reviews", study()) else data.frame())
    }
    shiny::observeEvent(study(), {
      reviewed(NULL)
      lineage(NULL)
      records(NULL)
      reviews(data.frame())
      caps(character())
      if (ready) attempt(refresh)
    })
    field <- function(name, default = "") {
      value <- shiny::isolate(input[[name]])
      if (is.null(value)) default else value
    }
    output$body <- shiny::renderUI({
      shiny::req(ready, any(c("edit", "manage") %in% caps()))
      ns <- session$ns
      l <- lang()
      p <- records()
      r <- reviews()
      if (nrow(r)) r <- r[!r$released & r$can_review, , drop = FALSE]
      shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Qualitative Redaktion", "Qualitative editorial work")),
        shiny::tags$p(tr(l, "Originale bleiben erhalten. Redaktionelle Fassungen und Zusammenfassungen werden getrennt gespeichert; eine andere Person muss die genaue Fassung freigeben.", "Originals are preserved. Redactions and summaries are stored separately; another person must release the exact version.")),
        if ("edit" %in% caps()) {
          shiny::tagList(
            shiny::tags$details(
              shiny::tags$summary(tr(l, "Originalquelle erfassen", "Record an original source")),
              shiny::textInput(ns("source_ref"), tr(l, "Quellenreferenz", "Source reference"), value = field("source_ref")),
              shiny::textAreaInput(ns("original"), tr(l, "Originaltext (nur synthetisch)", "Original text (synthetic only)"), value = field("original"), width = "100%"),
              shiny::actionButton(ns("record"), tr(l, "Original sichern", "Preserve original"))
            ),
            shiny::selectInput(ns("source"), tr(l, "Quelle f\u00fcr Redaktion, Codierung und Itembezug", "Source for redaction, coding and item linkage"), stats::setNames(p$sources$id, p$sources$source_ref), selected = field("source", NULL)),
            shiny::tags$details(shiny::tags$summary(tr(l, "Gesch\u00fctzten Originaltext ansehen", "View restricted original text")), shiny::verbatimTextOutput(ns("original_preview"))),
            shiny::tags$details(
              shiny::tags$summary(tr(l, "Separate Fassung erstellen", "Create a separate version")),
              shiny::selectInput(ns("kind"), tr(l, "Fassungsart", "Version type"), stats::setNames(c("redaction", "summary"), c(tr(l, "Redigierter Text", "Redaction"), tr(l, "Zusammenfassung (kein Zitat)", "Summary (not a quotation)"))), selected = field("kind", "redaction")),
              shiny::textAreaInput(ns("redacted"), tr(l, "Redigierter Text", "Edited text"), value = field("redacted"), width = "100%"),
              shiny::textAreaInput(ns("edit_reason"), tr(l, "Begr\u00fcndung der \u00c4nderungen", "Reason for changes"), value = field("edit_reason"), width = "100%"),
              shiny::actionButton(ns("redact"), tr(l, "Fassung speichern", "Save version"))
            ),
            shiny::tags$details(
              shiny::tags$summary(tr(l, "Themen und Codierung", "Themes and coding")),
              shiny::textInput(ns("theme_code"), tr(l, "Themencode", "Theme code"), value = field("theme_code")),
              shiny::numericInput(ns("theme_version"), tr(l, "Themenversion", "Theme version"), value = field("theme_version", 1), min = 1, step = 1),
              shiny::textInput(ns("theme_label"), tr(l, "Themenbezeichnung", "Theme label"), value = field("theme_label")),
              shiny::textAreaInput(ns("definition"), tr(l, "Definition und Codierregel", "Definition and coding rule"), value = field("definition"), width = "100%"),
              shiny::actionButton(ns("theme_create"), tr(l, "Themenversion speichern", "Save theme version")),
              shiny::selectInput(ns("theme"), tr(l, "Thema f\u00fcr die gew\u00e4hlte Quelle", "Theme for the selected source"), if (nrow(p$themes)) stats::setNames(p$themes$id, paste(p$themes$label, "v", p$themes$version)) else character(), selected = field("theme", NULL)),
              shiny::selectInput(ns("coding"), tr(l, "Codierentscheidung", "Coding decision"), stats::setNames(c("include", "exclude"), c(tr(l, "Einschlie\u00dfen", "Include"), tr(l, "Ausschlie\u00dfen", "Exclude"))), selected = field("coding", "include")),
              shiny::textAreaInput(ns("coding_reason"), tr(l, "Begr\u00fcndung oder Dissens", "Rationale or dissent"), value = field("coding_reason"), width = "100%"),
              shiny::actionButton(ns("code"), tr(l, "Codierentscheidung speichern", "Save coding decision"))
            ),
            shiny::tags$details(
              shiny::tags$summary(tr(l, "Item auf Quelle zur\u00fcckf\u00fchren", "Link an item to its source")),
              shiny::textInput(ns("item_code"), tr(l, "Itemcode", "Item code"), value = field("item_code")),
              shiny::numericInput(ns("item_version"), tr(l, "Itemversion", "Item version"), value = field("item_version", 1), min = 1, step = 1),
              shiny::textAreaInput(ns("link_reason"), tr(l, "Ableitungsbegr\u00fcndung", "Derivation rationale"), value = field("link_reason"), width = "100%"),
              shiny::actionButton(ns("link"), tr(l, "Quellenbezug speichern", "Save source linkage")),
              shiny::tags$p(tr(l, "Dies importiert oder genehmigt kein Instrumentitem.", "This does not import or approve an instrument item."))
            )
          )
        },
        if ("manage" %in% caps()) {
          shiny::tagList(
            shiny::tags$details(
              shiny::tags$summary(tr(l, "Unabh\u00e4ngige Pr\u00fcfung", "Independent review")),
              shiny::selectInput(ns("review_edit"), tr(l, "Zu pr\u00fcfende Fassung", "Version to review"), stats::setNames(r$id, paste(r$source_ref, r$kind)), selected = field("review_edit", NULL)),
              shiny::actionButton(ns("preview_review"), tr(l, "Genaue Fassung anzeigen", "Preview exact version")),
              shiny::uiOutput(ns("review_preview")),
              shiny::textAreaInput(ns("review_reason"), tr(l, "Pr\u00fcfbegr\u00fcndung einschlie\u00dflich Dissens", "Review rationale including dissent"), value = field("review_reason"), width = "100%"),
              shiny::checkboxInput(ns("review_confirm"), tr(l, "Ich habe diese genaue Fassung unabh\u00e4ngig gepr\u00fcft.", "I independently reviewed this exact version."), FALSE),
              shiny::actionButton(ns("release"), tr(l, "Fassung freigeben", "Release version"))
            ),
            shiny::tags$details(
              shiny::tags$summary(tr(l, "Itemteilung oder Zusammenf\u00fchrung dokumentieren", "Record an item split or merge")),
              shiny::selectInput(ns("relation"), tr(l, "Beziehung", "Relationship"), stats::setNames(c("split", "merge"), c(tr(l, "Teilen", "Split"), tr(l, "Zusammenf\u00fchren", "Merge"))), selected = field("relation", "split")),
              shiny::textAreaInput(ns("parents"), tr(l, "Ausgangsitems: je Zeile Code,Version", "Parent items: one code,version per line"), value = field("parents"), width = "100%"),
              shiny::textAreaInput(ns("children"), tr(l, "Neue Items: je Zeile Code,Version", "New items: one code,version per line"), value = field("children"), width = "100%"),
              shiny::textAreaInput(ns("lineage_reason"), tr(l, "Entscheidungsbegr\u00fcndung", "Decision rationale"), value = field("lineage_reason"), width = "100%"),
              shiny::actionButton(ns("lineage_preview"), tr(l, "Beziehung pr\u00fcfen", "Review relationship")),
              shiny::tableOutput(ns("lineage")),
              shiny::checkboxInput(ns("lineage_confirm"), tr(l, "Ich best\u00e4tige die angezeigte Beziehung.", "I confirm the displayed relationship."), FALSE),
              shiny::actionButton(ns("lineage_save"), tr(l, "Beziehung speichern", "Save relationship"))
            )
          )
        },
        shiny::actionButton(ns("refresh"), tr(l, "Redaktionsstand aktualisieren", "Refresh editorial records")),
        status_ui(ns("status"))
      )
    })
    output$status <- shiny::renderText(status())
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$original_preview <- shiny::renderText({
      shiny::req(records(), input$source)
      x <- records()$sources
      x$original_text[x$id == input$source]
    })
    success <- function() {
      refresh()
      status(tr(lang(), "Gespeichert. Der Originalverlauf bleibt erhalten.", "Saved. Original history is preserved."))
    }
    shiny::observeEvent(input$refresh, attempt(refresh))
    shiny::observeEvent(input$record, attempt(function() {
      call("record_qualitative_source", study(), input$original, input$source_ref, command_id())
      success()
    }))
    shiny::observeEvent(input$redact, attempt(function() {
      shiny::req(input$source)
      call("redact_qualitative_source", study(), input$source, input$redacted, input$edit_reason, command_id(), kind = input$kind)
      success()
    }))
    shiny::observeEvent(input$theme_create, attempt(function() {
      call("create_qualitative_theme", study(), input$theme_code, input$theme_version, input$theme_label, input$definition, command_id())
      success()
    }))
    shiny::observeEvent(input$code, attempt(function() {
      shiny::req(input$source, input$theme)
      call("code_qualitative_source", study(), input$source, input$theme, input$coding, input$coding_reason, command_id())
      success()
    }))
    shiny::observeEvent(input$link, attempt(function() {
      shiny::req(input$source)
      call("link_item_source", study(), input$item_code, input$item_version, input$source, input$link_reason, command_id())
      success()
    }))
    shiny::observeEvent(input$review_edit, {
      reviewed(NULL)
      shiny::updateCheckboxInput(session, "review_confirm", value = FALSE)
    })
    shiny::observeEvent(input$preview_review, attempt(function() {
      fresh <- call("list_qualitative_reviews", study())
      x <- fresh[fresh$id == input$review_edit, , drop = FALSE]
      shiny::req(nrow(x) == 1, isTRUE(x$can_review), !isTRUE(x$released))
      reviewed(x)
      shiny::updateCheckboxInput(session, "review_confirm", value = FALSE)
    }))
    output$review_preview <- shiny::renderUI({
      x <- reviewed()
      shiny::req(x)
      shiny::tagList(
        shiny::tags$h3(if (x$kind == "summary") tr(lang(), "Zusammenfassung (kein Zitat)", "Summary (not a quotation)") else tr(lang(), "Redigierte Fassung", "Redacted version")),
        shiny::tags$p(x$source_ref), shiny::tags$p(class = "del-consent", x$redacted_text), shiny::tags$p(x$reason)
      )
    })
    shiny::observeEvent(input$release, attempt(function() {
      x <- reviewed()
      shiny::req(x, isTRUE(input$review_confirm))
      if (!identical(input$review_edit, x$id)) stop("Preview differs from selection")
      call("release_qualitative_edit", study(), x$id, x$hash, input$review_reason, command_id())
      reviewed(NULL)
      success()
    }))
    lineage_values <- function() list(parents = parse_lineage_rows(input$parents), children = parse_lineage_rows(input$children), relation = input$relation, reason = input$lineage_reason)
    shiny::observeEvent(input$lineage_preview, attempt(function() {
      lineage(lineage_values())
      shiny::updateCheckboxInput(session, "lineage_confirm", value = FALSE)
    }))
    output$lineage <- shiny::renderTable({
      x <- lineage()
      shiny::req(x)
      rbind(data.frame(role = tr(lang(), "Ausgang", "Parent"), x$parents), data.frame(role = tr(lang(), "Neu", "New"), x$children))
    })
    shiny::observeEvent(input$lineage_save, attempt(function() {
      x <- lineage()
      shiny::req(x, isTRUE(input$lineage_confirm))
      if (!identical(x, lineage_values())) stop("Relationship changed since preview")
      call("record_item_lineage", study(), x$parents, x$children, x$relation, x$reason, command_id())
      lineage(NULL)
      success()
    }))
  })
}

parse_lineage_rows <- function(text) {
  if (!is.character(text) || length(text) != 1L || !nzchar(trimws(text))) stop("Enter item rows")
  rows <- strsplit(trimws(text), "\n", fixed = TRUE)[[1]]
  parts <- strsplit(rows, ",", fixed = TRUE)
  if (length(parts) > 100L || any(lengths(parts) != 2L)) stop("Use one code,version pair per line")
  codes <- trimws(vapply(parts, `[[`, character(1), 1L))
  versions <- trimws(vapply(parts, `[[`, character(1), 2L))
  if (any(!grepl("^[A-Za-z0-9_-]{1,80}$", codes)) || any(!grepl("^[1-9][0-9]*$", versions)) || anyDuplicated(codes)) stop("Invalid item rows")
  data.frame(item_code = codes, item_version = as.numeric(versions), stringsAsFactors = FALSE)
}
