audit_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

# The recorded history of a study for the audit role and study management.
audit_server <- function(id, study, lang, call, services) {
  shiny::moduleServer(id, function(input, output, session) {
    allowed <- shiny::reactiveVal(FALSE)
    events <- shiny::reactiveVal(NULL)
    status <- shiny::reactiveVal("")
    ready <- all(c("get_capabilities", "list_audit_events") %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    shiny::observeEvent(study(), {
      allowed(FALSE)
      events(NULL)
      if (ready) attempt(function() allowed(any(c("audit", "manage") %in% call("get_capabilities", study()))))
    })
    output$body <- shiny::renderUI({
      shiny::req(allowed())
      ns <- session$ns
      l <- lang()
      codes <- audit_action_codes()
      shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Verlauf", "History")),
        shiny::tags$p(tr(l, "Jedes Ereignis nennt Zeitpunkt, Aktion, Objekt und handelnde Stelle, bei begr\u00fcndungspflichtigen Aktionen auch die Begr\u00fcndung. Aktionen von Panelmitgliedern tragen keinen Kontobezug. Antwortinhalte und Kontakte erscheinen hier nicht.", "Each event names its time, action, object and actor, and the rationale where the action required one. Actions of panel members carry no account reference. Response content and contacts do not appear here.")),
        shiny::selectizeInput(ns("actions"), tr(l, "Auf Aktionen beschr\u00e4nken (leer: alle)", "Limit to actions (empty: all)"), stats::setNames(codes, audit_action_label(codes, l)), selected = shiny::isolate(input$actions), multiple = TRUE, width = "100%"),
        shiny::numericInput(ns("limit"), tr(l, "H\u00f6chstzahl der Ereignisse (neueste zuerst)", "Maximum number of events (newest first)"), value = shiny::isolate(if (is.null(input$limit)) 100 else input$limit), min = 1, max = 5000, step = 1),
        shiny::actionButton(ns("load"), tr(l, "Verlauf anzeigen", "Show history")),
        shiny::tableOutput(ns("events")),
        status_ui(ns("status"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    shiny::observeEvent(input$load, attempt(function() {
      shiny::req(allowed())
      limit <- suppressWarnings(as.numeric(input$limit))
      if (length(limit) != 1L || is.na(limit) || limit != floor(limit) || limit < 1 || limit > 5000) stop("Invalid limit")
      x <- call("list_audit_events", study(), actions = if (length(input$actions)) input$actions else NULL, limit = limit)
      events(x)
      status(paste(nrow(x), tr(lang(), "Ereignisse angezeigt.", "events shown.")))
    }))
    output$events <- shiny::renderTable(
      {
        x <- events()
        shiny::req(x)
        if (!nrow(x)) {
          return(NULL)
        }
        l <- lang()
        by <- ifelse(x$actor_kind == "panel", tr(l, "Panelmitglied", "Panel member"), paste(ifelse(x$actor_kind == "worker", tr(l, "Worker, freigegeben von", "Worker, approved by"), tr(l, "Studienkonto", "Staff account")), x$actor_ref))
        blank <- function(v) ifelse(is.na(v), "", v)
        out <- data.frame(x$occurred_at, audit_action_label(x$action, l), blank(x$detail), blank(x$reason), by, x$object_ref, stringsAsFactors = FALSE)
        names(out) <- tr(l, c("Zeitpunkt (UTC)", "Aktion", "Angabe", "Begr\u00fcndung", "Durch", "Objekt"), c("Time (UTC)", "Action", "Detail", "Reason", "By", "Object"))
        out
      },
      striped = TRUE
    )
    list(events = events, allowed = allowed)
  })
}

audit_action_codes <- function() {
  c(
    "create_study", "amend_protocol", "study_documentation", "capability", "publish_consent", "panel_import", "invitation_account", "invitation_issue", "invitation_revoke",
    "invitation_accept", "add_panelist", "panel_group", "enroll_panel", "prepare_round", "transition_round", "consent", "save", "submit", "withdraw_participation", "freeze",
    "request_analysis", "analyse", "feedback_draft", "release_feedback", "assign_feedback", "feedback_displayed", "feedback_download", "decision", "item_comparability", "complete_study",
    "qualitative_source", "qualitative_edit", "qualitative_release", "qualitative_theme", "qualitative_code", "qualitative_item_source", "qualitative_lineage", "qualitative_read", "qualitative_export",
    "campaign_prepare", "campaign_release", "campaign_cancel", "message_sink_recorded", "message_suppressed", "message_accepted", "message_failed", "message_queued",
    "message_delivery_unknown", "delivery_resolution", "request_export", "artifact_download", "staff_account", "qualitative_import", "correct_feedback"
  )
}

audit_action_label <- function(action, lang) {
  en <- c(
    create_study = "Study created", amend_protocol = "Protocol amended", study_documentation = "Study documentation recorded", capability = "Right granted or revoked",
    publish_consent = "Study information published", panel_import = "Panel contacts imported", invitation_account = "Invited account registered", invitation_issue = "Invitation issued",
    invitation_revoke = "Invitation revoked", invitation_accept = "Invitation accepted", add_panelist = "Panel member added", panel_group = "Stakeholder group changed",
    enroll_panel = "Panel members enrolled", prepare_round = "Round prepared", transition_round = "Round state changed", consent = "Consent decision recorded", save = "Response saved",
    submit = "Round submitted", withdraw_participation = "Participation ended", freeze = "Round frozen", request_analysis = "Analysis requested", analyse = "Analysis completed",
    feedback_draft = "Feedback drafted", release_feedback = "Feedback released", assign_feedback = "Feedback assigned", feedback_displayed = "Feedback displayed",
    feedback_download = "Feedback downloaded", decision = "Item decision recorded", item_comparability = "Comparability decided", complete_study = "Study completed",
    qualitative_source = "Original source preserved", qualitative_edit = "Editorial version created", qualitative_release = "Editorial version released",
    qualitative_theme = "Theme version defined", qualitative_code = "Coding decision recorded", qualitative_item_source = "Item linked to source", qualitative_lineage = "Item split or merge recorded",
    qualitative_read = "Editorial records read", qualitative_export = "Editorial records exported", campaign_prepare = "Campaign prepared", campaign_release = "Campaign approved",
    campaign_cancel = "Campaign cancelled", message_sink_recorded = "Local message receipt recorded", message_suppressed = "Message suppressed", request_export = "Export requested",
    artifact_download = "Export downloaded", message_accepted = "Message accepted by the provider", message_failed = "Message failed", message_queued = "Message retry scheduled",
    message_delivery_unknown = "Message outcome unknown", delivery_resolution = "Uncertain delivery resolved", staff_account = "Staff account registered",
    qualitative_import = "Free-text contributions taken over", correct_feedback = "Feedback corrected"
  )
  de <- c(
    create_study = "Studie angelegt", amend_protocol = "Protokoll ge\u00e4ndert", study_documentation = "Studiendokumentation erfasst", capability = "Recht erteilt oder entzogen",
    publish_consent = "Studieninformation ver\u00f6ffentlicht", panel_import = "Panelkontakte importiert", invitation_account = "Eingeladenes Konto registriert", invitation_issue = "Einladung ausgestellt",
    invitation_revoke = "Einladung widerrufen", invitation_accept = "Einladung angenommen", add_panelist = "Panelmitglied hinzugef\u00fcgt", panel_group = "Interessengruppe ge\u00e4ndert",
    enroll_panel = "Panelmitglieder aufgenommen", prepare_round = "Runde vorbereitet", transition_round = "Rundenstatus ge\u00e4ndert", consent = "Einwilligungsentscheidung erfasst", save = "Antwort gespeichert",
    submit = "Runde abgegeben", withdraw_participation = "Teilnahme beendet", freeze = "Runde eingefroren", request_analysis = "Analyse beauftragt", analyse = "Analyse abgeschlossen",
    feedback_draft = "Feedback entworfen", release_feedback = "Feedback freigegeben", assign_feedback = "Feedback zugewiesen", feedback_displayed = "Feedback angezeigt",
    feedback_download = "Feedback heruntergeladen", decision = "Itementscheidung erfasst", item_comparability = "Vergleichbarkeit entschieden", complete_study = "Studie abgeschlossen",
    qualitative_source = "Originalquelle gesichert", qualitative_edit = "Redaktionelle Fassung erstellt", qualitative_release = "Redaktionelle Fassung freigegeben",
    qualitative_theme = "Themenversion definiert", qualitative_code = "Codierentscheidung erfasst", qualitative_item_source = "Item mit Quelle verkn\u00fcpft", qualitative_lineage = "Itemteilung oder Zusammenf\u00fchrung erfasst",
    qualitative_read = "Redaktionsdaten gelesen", qualitative_export = "Redaktionsdaten exportiert", campaign_prepare = "Kampagne vorbereitet", campaign_release = "Kampagne freigegeben",
    campaign_cancel = "Kampagne abgebrochen", message_sink_recorded = "Lokaler Nachrichtenbeleg gespeichert", message_suppressed = "Nachricht unterdr\u00fcckt", request_export = "Export beauftragt",
    artifact_download = "Export heruntergeladen", message_accepted = "Nachricht vom Dienst angenommen", message_failed = "Nachricht fehlgeschlagen", message_queued = "Wiederholung der Nachricht eingeplant",
    message_delivery_unknown = "Ergebnis der Nachricht unbekannt", delivery_resolution = "Ungewisse Zustellung gekl\u00e4rt", staff_account = "Konto des Studienteams registriert",
    qualitative_import = "Freitextbeitr\u00e4ge \u00fcbernommen", correct_feedback = "Feedback korrigiert"
  )
  labels <- tr(lang, de, en)
  # Profile-specific export requests share one label; unknown codes stay visible.
  key <- ifelse(startsWith(action, "request_export"), "request_export", action)
  unname(ifelse(key %in% names(labels), labels[key], action))
}

documentation_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

documentation_topic_labels <- function(lang) {
  tr(
    lang,
    c(authors_responsibilities = "Autorinnen, Autoren und Zust\u00e4ndigkeiten", panel_criteria_recruitment = "Panelkriterien und Rekrutierung", funding = "Finanzierung", conflicts_of_interest = "Interessenkonflikte", institutional_approval = "Institutionelle Genehmigung", methodological_interpretation = "Methodische Interpretation", protocol_deviations = "Protokollabweichungen", reporting_guideline_review = "ACCORD-/CREDES-Pr\u00fcfung", data_software_availability = "Daten- und Softwareverf\u00fcgbarkeit"),
    c(authors_responsibilities = "Authors and responsibilities", panel_criteria_recruitment = "Panel criteria and recruitment", funding = "Funding", conflicts_of_interest = "Conflicts of interest", institutional_approval = "Institutional approval", methodological_interpretation = "Methodological interpretation", protocol_deviations = "Protocol deviations", reporting_guideline_review = "ACCORD/CREDES review", data_software_availability = "Data and software availability")
  )
}

# Author-supplied statements for reports. Nothing is generated; an empty topic
# is reported as not documented.
documentation_server <- function(id, study, lang, call, services) {
  shiny::moduleServer(id, function(input, output, session) {
    allowed <- shiny::reactiveVal(FALSE)
    current <- shiny::reactiveVal(NULL)
    status <- shiny::reactiveVal("")
    ready <- all(c("get_capabilities", "get_study_documentation", "record_study_documentation") %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    topics <- names(documentation_topic_labels("en"))
    shiny::observeEvent(study(), {
      allowed(FALSE)
      current(NULL)
      if (ready) {
        attempt(function() {
          allowed("manage" %in% call("get_capabilities", study()))
          if (allowed()) current(call("get_study_documentation", study()))
        })
      }
    })
    output$body <- shiny::renderUI({
      shiny::req(allowed(), current())
      ns <- session$ns
      l <- lang()
      x <- current()
      labels <- documentation_topic_labels(l)
      value <- function(topic) {
        typed <- shiny::isolate(input[[topic]])
        if (!is.null(typed)) typed else if (!is.null(x$fields[[topic]])) x$fields[[topic]] else ""
      }
      shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Studiendokumentation f\u00fcr Berichte", "Study documentation for reports")),
        shiny::tags$p(tr(l, "Berichte erfinden keine Angaben zu Autorenschaft, Finanzierung, Interessenkonflikten, Genehmigungen, Interpretation oder Abweichungen. Tragen Sie hier die Aussagen des Studienteams ein. Leere Themen erscheinen im Bericht als nicht dokumentiert. Der Verweis auf eine Genehmigung erteilt keine Genehmigung.", "Reports never invent statements on authorship, funding, conflicts of interest, approvals, interpretation or deviations. Enter the study team\u2019s own statements here. Empty topics appear in reports as not documented. Recording a reference to an approval does not grant one.")),
        shiny::tags$p(class = "del-note", paste(tr(l, "Aktuelle Dokumentationsversion:", "Current documentation version:"), x$version)),
        lapply(topics, function(topic) shiny::textAreaInput(ns(topic), labels[[topic]], value = value(topic), width = "100%")),
        shiny::textAreaInput(ns("reason"), tr(l, "Begr\u00fcndung dieser Version", "Rationale for this version"), value = shiny::isolate(if (is.null(input$reason)) "" else input$reason), width = "100%"),
        shiny::checkboxInput(ns("confirm"), tr(l, "Ich habe diese Aussagen gepr\u00fcft. Die neue Version ersetzt die bisherige vollst\u00e4ndig.", "I reviewed these statements. The new version replaces the previous one completely."), FALSE),
        shiny::actionButton(ns("save"), tr(l, "Neue Dokumentationsversion speichern", "Save new documentation version"), class = "btn-primary"),
        shiny::tableOutput(ns("history")),
        status_ui(ns("status"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    output$history <- shiny::renderTable({
      x <- current()
      shiny::req(x)
      if (!nrow(x$history)) {
        return(NULL)
      }
      out <- data.frame(x$history$version, x$history$reason, x$history$recorded_at, stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("Version", "Begr\u00fcndung", "Zeitpunkt (UTC)"), c("Version", "Reason", "Time (UTC)"))
      out
    })
    shiny::observeEvent(input$save, attempt(function() {
      x <- current()
      shiny::req(allowed(), x)
      reason <- if (is.null(input$reason)) "" else trimws(input$reason)
      if (!isTRUE(input$confirm) || !nzchar(reason)) {
        status(tr(lang(), "Begr\u00fcndung und Best\u00e4tigung sind erforderlich.", "A reason and confirmation are required."))
        return()
      }
      fields <- stats::setNames(lapply(topics, function(topic) if (is.null(input[[topic]])) "" else input[[topic]]), topics)
      fields <- fields[vapply(fields, function(v) nzchar(trimws(v)), logical(1))]
      if (!length(fields)) {
        status(tr(lang(), "Mindestens ein Thema muss eine Aussage enthalten.", "At least one topic needs a statement."))
        return()
      }
      result <- call("record_study_documentation", study(), fields, x$version, reason, command_id())
      current(call("get_study_documentation", study()))
      shiny::updateCheckboxInput(session, "confirm", value = FALSE)
      shiny::updateTextAreaInput(session, "reason", value = "")
      status(paste(tr(lang(), "Dokumentationsversion gespeichert:", "Documentation version saved:"), result$version))
    }))
    list(current = current)
  })
}

exports_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

export_profile_capabilities <- function() {
  list(research_pseudonymized = "export", study_summary = c("analyse", "manage"), audit_restricted = c("audit", "manage"), contacts_restricted = "contacts_export")
}

export_profile_label <- function(profile, lang) {
  labels <- tr(
    lang,
    c(research_pseudonymized = "Pseudonymisierte Forschungsdaten", study_summary = "Aggregierte Studienzusammenfassung", audit_restricted = "Verlauf und Freigaben", contacts_restricted = "Kontaktdaten"),
    c(research_pseudonymized = "Pseudonymized research data", study_summary = "Aggregated study summary", audit_restricted = "History and approvals", contacts_restricted = "Contact data")
  )
  unname(labels[profile])
}

export_profile_description <- function(profile, lang) {
  text <- tr(
    lang,
    c(
      research_pseudonymized = "Alle eingefrorenen Runden mit Pseudonymen, Entscheidungen, Herkunft und gepr\u00fcften redaktionellen Fassungen. Pseudonyme sind nicht anonym. Unredigierte Freitexte, Kontakte und Kontozuordnungen fehlen.",
      study_summary = "Verlauf, Instrumente und aggregierte Ergebnisse ohne Einzelantworten. Statistiken unter der Mindestzellgr\u00f6\u00dfe des Protokolls sind unterdr\u00fcckt.",
      audit_restricted = "Ereignisse, Freigaben und Begr\u00fcndungen ohne Antwortinhalte, Kontakte oder redaktionelle Originale.",
      contacts_restricted = "Kontaktfelder der importierten Panelkontakte und ihr Einladungsstatus, ohne Studienpseudonyme."
    ),
    c(
      research_pseudonymized = "Every frozen round with pseudonyms, decisions, lineage and reviewed editorial versions. Pseudonyms are not anonymous. Unredacted free text, contacts and account mappings are excluded.",
      study_summary = "Course, instruments and aggregated results without individual responses. Statistics below the protocol\u2019s display minimum are suppressed.",
      audit_restricted = "Events, approvals and rationales without response content, contacts or editorial originals.",
      contacts_restricted = "Contact fields of imported panel contacts and their invitation state, without study pseudonyms."
    )
  )
  unname(text[profile])
}

# Study-level exports. The offered profiles follow the actor's current rights;
# the services check them again on request, on completion and on download.
exports_server <- function(id, study, lang, call, services, changed = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    profiles <- shiny::reactiveVal(character())
    operation <- shiny::reactiveVal(NULL)
    artifact <- shiny::reactiveVal(NULL)
    status <- shiny::reactiveVal("")
    ready <- all(c("get_capabilities", "request_study_export", "get_operation", "download_artifact") %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    shiny::observeEvent(study(), {
      profiles(character())
      operation(NULL)
      artifact(NULL)
      if (ready) {
        attempt(function() profiles(offered()))
      }
    })
    offered <- function() {
      caps <- call("get_capabilities", study())
      needed <- export_profile_capabilities()
      names(needed)[vapply(needed, function(x) any(x %in% caps), logical(1))]
    }
    # Rights granted or revoked in another section change the offered profiles.
    if (!is.null(changed)) {
      shiny::observeEvent(changed(),
        {
          if (ready) attempt(function() profiles(offered()))
        },
        ignoreInit = TRUE
      )
    }
    output$body <- shiny::renderUI({
      shiny::req(length(profiles()) > 0)
      ns <- session$ns
      l <- lang()
      shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Exporte der Studie", "Study exports")),
        shiny::tags$p(tr(l, "Jedes Profil enth\u00e4lt nur die Daten seines Zwecks. Der Export wird im Hintergrund erstellt und privat gespeichert. Eine heruntergeladene Datei unterliegt nicht mehr der Zugriffskontrolle dieser Anwendung.", "Each profile contains only the data of its purpose. The export is prepared in the background and stored privately. A downloaded file is no longer covered by this application\u2019s access control.")),
        shiny::selectInput(ns("profile"), tr(l, "Exportprofil", "Export profile"), stats::setNames(profiles(), export_profile_label(profiles(), l)), selected = shiny::isolate(input$profile)),
        shiny::tags$p(shiny::textOutput(ns("description"))),
        shiny::checkboxInput(ns("confirm"), tr(l, "Ich bin zum Erhalt dieser Daten berechtigt und behandle die Datei entsprechend ihrem Zweck.", "I am entitled to receive these data and will handle the file according to its purpose."), FALSE),
        shiny::tags$div(
          class = "del-actions",
          shiny::actionButton(ns("request"), tr(l, "Export beauftragen", "Request export")),
          shiny::actionButton(ns("poll"), tr(l, "Auftrag pr\u00fcfen", "Check operation")),
          shiny::downloadButton(ns("download"), tr(l, "Export herunterladen", "Download export"))
        ),
        status_ui(ns("status"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    output$description <- shiny::renderText({
      shiny::req(input$profile)
      export_profile_description(input$profile, lang())
    })
    shiny::observeEvent(input$profile, {
      operation(NULL)
      artifact(NULL)
      shiny::updateCheckboxInput(session, "confirm", value = FALSE)
    })
    shiny::observeEvent(input$request, attempt(function() {
      shiny::req(input$profile %in% profiles())
      if (!isTRUE(input$confirm)) {
        status(tr(lang(), "Bitte die Berechtigung ausdr\u00fccklich best\u00e4tigen.", "Explicitly confirm your entitlement first."))
        return()
      }
      r <- call("request_study_export", study(), input$profile, command_id())
      operation(list(id = r$id, profile = input$profile))
      artifact(NULL)
      status(tr(lang(), "Export eingereiht. Auftrag pr\u00fcfen.", "Export queued. Check the operation."))
    }))
    shiny::observeEvent(input$poll, attempt(function() {
      shiny::req(operation())
      r <- call("get_operation", operation()$id)
      status(operation_status(r, lang()))
      if (identical(r$state, "succeeded")) artifact(r$result_ref)
    }))
    output$download <- shiny::downloadHandler(
      filename = function() paste0("delphyr-", if (is.null(operation())) "export" else operation()$profile, ".zip"),
      content = function(file) {
        shiny::req(artifact())
        path <- call("download_artifact", artifact())
        zip::zipr(file, list.files(path, full.names = TRUE), root = path)
      }, contentType = "application/zip"
    )
    list(profiles = profiles, operation = operation, artifact = artifact)
  })
}
