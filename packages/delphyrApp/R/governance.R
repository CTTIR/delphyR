audit_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

# Events read per step. "Show older events" reads the next step up to the
# maximum; the restricted audit export holds the complete trail.
audit_step <- 100L
audit_maximum <- 5000L

# The recorded history of a study for the audit role and study management.
audit_server <- function(id, study, lang, call, services) {
  shiny::moduleServer(id, function(input, output, session) {
    allowed <- shiny::reactiveVal(FALSE)
    events <- shiny::reactiveVal(NULL)
    older <- shiny::reactiveVal(FALSE)
    filter <- shiny::reactiveVal(NULL)
    context <- shiny::reactiveVal(list())
    status <- shiny::reactiveVal("")
    ready <- all(c("get_capabilities", "list_audit_events") %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    shiny::observeEvent(study(), {
      allowed(FALSE)
      events(NULL)
      older(FALSE)
      context(list())
      status("")
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
        shiny::selectizeInput(ns("actions"), tr(l, "Auf Aktionen beschr\u00e4nken", "Limit to actions"), stats::setNames(codes, audit_action_label(codes, l)), selected = shiny::isolate(input$actions), multiple = TRUE, width = "100%", options = list(placeholder = tr(l, "Alle Aktionen", "All actions"))),
        shiny::tags$div(class = "del-actions", shiny::actionButton(ns("load"), tr(l, "Verlauf anzeigen", "Show history"))),
        status_ui(ns("status")),
        shiny::uiOutput(ns("events"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    # One more event than shown tells whether older events exist.
    load <- function(actions, limit) {
      capabilities <- call("get_capabilities", study())
      allowed(any(c("audit", "manage") %in% capabilities))
      shiny::req(allowed())
      x <- call("list_audit_events", study(), actions = actions, limit = limit + 1L)
      filter(actions)
      older(nrow(x) > limit)
      context(audit_context(call, services, study(), capabilities))
      events(utils::head(x, limit))
    }
    shiny::observeEvent(input$load, attempt(function() {
      shiny::req(allowed())
      status("")
      load(audit_filter(input$actions), audit_step)
    }))
    shiny::observeEvent(input$older, attempt(function() {
      shiny::req(allowed(), events(), older())
      load(filter(), min(nrow(events()) + audit_step, audit_maximum))
    }))
    output$events <- shiny::renderUI({
      x <- events()
      shiny::req(x)
      l <- lang()
      if (!nrow(x)) {
        return(shiny::tags$p(class = "del-note", tr(l, "Keine aufgezeichneten Ereignisse f\u00fcr diese Auswahl.", "No recorded event matches this selection.")))
      }
      ctx <- context()
      time <- audit_time(x$occurred_at, l)
      action <- audit_action_label(x$action, l)
      detail <- audit_detail_label(x$action, x$detail, l)
      rows <- lapply(seq_len(nrow(x)), function(i) {
        list(
          time[[i]],
          shiny::tagList(
            shiny::tags$div(shiny::tags$strong(action[i]), if (!is.na(detail[i])) paste0(" \u00b7 ", detail[i])),
            shiny::tags$div(class = "del-note", audit_object(x$object_ref[i], ctx, l), " \u00b7 ", audit_actor(x$actor_kind[i], x$actor_ref[i], ctx, l)),
            if (!is.na(x$reason[i]) && nzchar(x$reason[i])) shiny::tags$div(paste(tr(l, "Begr\u00fcndung:", "Rationale:"), x$reason[i]))
          )
        )
      })
      shiny::tagList(
        shiny::tags$p(class = "del-note", audit_count_text(nrow(x), older(), l)),
        markup_table(tr(l, c("Zeitpunkt (UTC)", "Ereignis"), c("Time (UTC)", "Event")), rows),
        if (older()) {
          shiny::tags$div(
            class = "del-actions",
            if (nrow(x) < audit_maximum) {
              shiny::actionButton(session$ns("older"), tr(l, "\u00c4ltere Ereignisse anzeigen", "Show older events"))
            } else {
              shiny::tags$p(class = "del-note", tr(l, "Der vollst\u00e4ndige Verlauf steht im Export \u201eVerlauf und Freigaben\u201c.", "The complete history is in the export \u201cHistory and approvals\u201d."))
            }
          )
        }
      )
    })
    list(events = events, allowed = allowed, older = older)
  })
}

audit_action_codes <- function() {
  c(
    "create_study", "amend_protocol", "study_documentation", "capability", "publish_consent", "panel_import", "invitation_account", "invitation_issue", "invitation_revoke",
    "invitation_accept", "add_panelist", "panel_group", "enroll_panel", "prepare_round", "transition_round", "consent", "save", "submit", "withdraw_participation", "freeze",
    "request_analysis", "analyse", "feedback_draft", "release_feedback", "assign_feedback", "feedback_displayed", "feedback_download", "decision", "item_comparability", "complete_study",
    "qualitative_source", "qualitative_edit", "qualitative_release", "qualitative_theme", "qualitative_code", "qualitative_item_source", "qualitative_lineage", "qualitative_read", "qualitative_export",
    "campaign_prepare", "campaign_release", "campaign_cancel", "message_sink_recorded", "message_suppressed", "message_accepted", "message_failed", "message_queued",
    "message_delivery_unknown", "delivery_resolution", "request_export", "artifact_download", "staff_account", "qualitative_import", "correct_feedback", "round_deadline"
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
    qualitative_import = "Free-text contributions imported as sources", correct_feedback = "Feedback corrected", round_deadline = "Round deadline changed"
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
    qualitative_import = "Freitextbeitr\u00e4ge als Quellen \u00fcbernommen", correct_feedback = "Feedback korrigiert", round_deadline = "Frist der Runde ge\u00e4ndert"
  )
  labels <- tr(lang, de, en)
  # Profile-specific export requests share one label; unknown codes stay visible.
  key <- ifelse(startsWith(action, "request_export"), "request_export", action)
  unname(ifelse(key %in% names(labels), labels[key], action))
}

# The filter entry "Export requested" stands for every export request, as its
# label does in the list: round exports and each study export profile.
audit_filter <- function(actions) {
  if (!length(actions)) {
    return(NULL)
  }
  unique(c(actions, if ("request_export" %in% actions) paste0("request_export:", names(export_profile_capabilities()))))
}

# Grammatical number: French uses the singular for zero and one.
plural_key <- function(n, lang) if ((identical(lang, "fr") && n < 2) || (!identical(lang, "fr") && n == 1)) "one" else "other"

audit_count_text <- function(n, older, lang) {
  if (older) {
    if (n == 1L) {
      return(tr(lang, "Das neueste Ereignis wird angezeigt. Es gibt \u00e4ltere Ereignisse.", "Showing the latest event. Older events exist."))
    }
    return(sprintf(tr(lang, "Die %d neuesten Ereignisse werden angezeigt. Es gibt \u00e4ltere Ereignisse.", "Showing the latest %d events. Older events exist."), n))
  }
  if (n == 1L) tr(lang, "1 Ereignis wird angezeigt.", "Showing 1 event.") else sprintf(tr(lang, "Alle %d Ereignisse werden angezeigt.", "Showing all %d events."), n)
}

# A moment of the history: the date above the time of day.
audit_time <- function(x, lang) {
  lapply(format_moment(x, "UTC", lang, with_zone = FALSE), function(text) {
    parts <- strsplit(text, ", ", fixed = TRUE)[[1]]
    if (length(parts) == 2L) shiny::tagList(parts[1], shiny::tags$br(), parts[2]) else text
  })
}

# Names of accounts and objects for the readers who may see them: study
# management reads the team, the rounds and the versions. Without these reads
# an object or account is shown by its short reference.
audit_context <- function(call, services, study_id, capabilities) {
  out <- list(study = study_id, staff = character(), rounds = NULL, protocols = NULL, consents = NULL)
  if (!"manage" %in% capabilities) {
    return(out)
  }
  read <- function(name, f) if (name %in% names(services)) tryCatch(f(call(name, study_id)), error = function(e) NULL)
  staff <- read("list_study_staff", function(s) stats::setNames(as.character(s$subject), s$principal_id))
  if (length(staff)) out$staff <- staff
  out$rounds <- read("list_rounds", function(r) r)
  out$protocols <- read("list_protocol_versions", function(v) v[, c("id", "version"), drop = FALSE])
  out$consents <- read("get_study_setup", function(s) s$consent_versions)
  out
}

audit_account <- function(ref, ctx, lang) {
  if (is.na(ref) || !nzchar(ref)) {
    return(no_value)
  }
  name <- if (length(ctx$staff) && ref %in% names(ctx$staff)) ctx$staff[[ref]] else NA_character_
  if (!is.na(name)) {
    return(shiny::tags$span(title = ref, name))
  }
  shiny::tagList(tr(lang, "das Studienkonto", "the study team account"), " ", ref_tag(ref))
}

audit_actor <- function(kind, ref, ctx, lang) {
  if (identical(kind, "panel")) {
    return(tr(lang, "durch ein Panelmitglied", "by a panel member"))
  }
  who <- audit_account(ref, ctx, lang)
  if (identical(kind, "worker")) {
    return(shiny::tagList(tr(lang, "durch den Hintergrunddienst, freigegeben von", "by the background worker, approved by"), " ", who))
  }
  shiny::tagList(tr(lang, "durch", "by"), " ", who)
}

audit_object <- function(ref, ctx, lang) {
  if (is.na(ref) || !nzchar(ref)) {
    return(no_value)
  }
  if (identical(ref, ctx$study)) {
    return(tr(lang, "Diese Studie", "This study"))
  }
  find <- function(table, column) if (NROW(table) && column %in% names(table)) match(ref, table[[column]]) else NA_integer_
  rounds <- ctx$rounds
  k <- find(rounds, "id")
  if (!is.na(k)) {
    return(paste(tr(lang, "Runde", "Round"), rounds$number[k]))
  }
  k <- find(rounds, "snapshot_id")
  if (!is.na(k)) {
    return(paste(tr(lang, "Eingefrorene Daten der Runde", "Frozen data of round"), rounds$number[k]))
  }
  k <- find(rounds, "analysis_id")
  if (!is.na(k)) {
    return(paste(tr(lang, "Auswertung der Runde", "Analysis of round"), rounds$number[k]))
  }
  k <- find(ctx$protocols, "id")
  if (!is.na(k)) {
    return(paste(tr(lang, "Protokollversion", "Protocol version"), ctx$protocols$version[k]))
  }
  k <- find(ctx$consents, "id")
  if (!is.na(k)) {
    return(paste0(tr(lang, "Studieninformation, Fassung", "Study information, version"), " ", k, " (", locale_name(ctx$consents$locale[k]), ")"))
  }
  shiny::tagList(tr(lang, "Objekt", "Object"), " ", ref_tag(ref))
}

# The stored detail of an event in words. Codes become the labels the other
# screens use; study content such as item and theme codes stays as recorded,
# and a value without a label is shown unchanged.
audit_detail_label <- function(action, detail, lang) {
  vapply(seq_along(action), function(i) audit_detail_text(action[[i]], detail[[i]], lang), character(1))
}
audit_detail_text <- function(action, detail, lang) {
  if (is.na(detail) || !nzchar(detail)) {
    return(NA_character_)
  }
  pick <- function(labels) if (detail %in% names(labels)) unname(labels[[detail]]) else detail
  parts <- function(pattern) regmatches(detail, regexec(pattern, detail))[[1]]
  if (startsWith(action, "request_export") || identical(action, "artifact_download")) {
    label <- export_profile_label(detail, lang)
    return(if (is.na(label)) detail else label)
  }
  if (startsWith(action, "message_")) {
    return(if (identical(detail, "database_sink")) tr(lang, "Lokaler Testbeleg, keine E-Mail", "Local test receipt, no email") else detail)
  }
  switch(action,
    transition_round = round_state_label(detail, lang),
    round_deadline = paste(tr(lang, "Neue Frist:", "New deadline:"), format_moment(detail, "UTC", lang)),
    consent = pick(tr(lang, c(accepted = "Einwilligung erteilt", declined = "Einwilligung abgelehnt"), c(accepted = "Consent given", declined = "Consent declined"))),
    publish_consent = locale_name(detail),
    add_panelist = ,
    panel_group = humanize_code(detail),
    withdraw_participation = pick(tr(lang, c(synthetic_retain_prior_data = "Fr\u00fchere Antworten bleiben erhalten"), c(synthetic_retain_prior_data = "Earlier answers are kept"))),
    campaign_prepare = delivery_kind_label(detail, lang),
    delivery_resolution = pick(tr(lang, c(confirmed_delivered = "Zustellung best\u00e4tigt", requeue = "Erneut eingereiht", abandon = "Aufgegeben"), c(confirmed_delivered = "Delivery confirmed", requeue = "Queued again", abandon = "Abandoned"))),
    qualitative_edit = pick(tr(lang, c(redaction = "Redigierter Text", summary = "Zusammenfassung (kein Zitat)"), c(redaction = "Redaction", summary = "Summary (not a quotation)"))),
    qualitative_code = pick(tr(lang, c(include = "Einschlie\u00dfen", exclude = "Ausschlie\u00dfen"), c(include = "Include", exclude = "Exclude"))),
    qualitative_lineage = disposition_label(detail, lang),
    qualitative_theme = ,
    qualitative_item_source = {
      m <- parts("^(.+) v([0-9]+)$")
      if (length(m)) paste0(m[2], " \u00b7 ", tr(lang, "Version", "Version"), " ", m[3]) else detail
    },
    capability = {
      m <- parts("^([a-z_]+) (granted|revoked)$")
      if (length(m)) paste0(staff_capability_label(m[2], lang), " \u00b7 ", if (m[3] == "granted") tr(lang, "erteilt", "granted") else tr(lang, "entzogen", "revoked")) else detail
    },
    decision = {
      m <- parts("^(\\S+) ([a-z_]+)$")
      if (length(m)) paste0(m[2], " \u00b7 ", disposition_label(m[3], lang)) else detail
    },
    item_comparability = {
      m <- parts("^(\\S+) (.+) v([0-9]+)->v([0-9]+) (comparable|not comparable)$")
      if (length(m)) paste0(m[2], " \u00b7 ", humanize_code(m[3]), " \u00b7 ", tr(lang, "Version", "Version"), " ", m[4], " \u2192 ", m[5], " \u00b7 ", if (m[6] == "comparable") tr(lang, "Vergleichbar", "Comparable") else tr(lang, "Nicht vergleichbar", "Not comparable")) else detail
    },
    correct_feedback = {
      m <- parts("^replaces (.+)$")
      if (length(m)) paste(tr(lang, "Ersetzt Feedback", "Replaces feedback"), short_ref(m[2])) else detail
    },
    feedback_draft = {
      m <- parts("^([0-9]+) released editorial versions?$")
      if (length(m)) {
        n <- as.integer(m[2])
        words <- tr(lang, c(one = "freigegebene redaktionelle Fassung", other = "freigegebene redaktionelle Fassungen"), c(one = "released editorial version", other = "released editorial versions"))
        paste(n, words[[plural_key(n, lang)]])
      } else {
        detail
      }
    },
    detail
  )
}

# A table whose cells may hold markup. Text in the cells is escaped like any
# other tag content; the classes are those of shiny::renderTable, which also
# aligns numbers to the right.
markup_table <- function(header, rows, caption = NULL) {
  numeric <- if (length(rows)) vapply(rows[[1]], is.numeric, logical(1)) else logical(length(header))
  align <- function(k) if (isTRUE(numeric[k])) "text-end"
  shiny::tags$table(
    class = "table shiny-table table-striped spacing-s", style = "width:auto;",
    if (!is.null(caption)) shiny::tags$caption(caption),
    shiny::tags$thead(shiny::tags$tr(lapply(seq_along(header), function(k) shiny::tags$th(class = align(k), header[[k]])))),
    shiny::tags$tbody(lapply(rows, function(r) shiny::tags$tr(lapply(seq_along(r), function(k) shiny::tags$td(class = align(k), r[[k]])))))
  )
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
    # The fields of one loaded version of one study carry their own input ids,
    # so that text shown for one study is never read for another or for a
    # later version.
    form <- shiny::reactiveVal(0L)
    status <- shiny::reactiveVal("")
    ready <- all(c("get_capabilities", "get_study_documentation", "record_study_documentation") %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    topics <- names(documentation_topic_labels("en"))
    field_id <- function(name, key = form()) paste0(name, "_", key)
    load <- function() {
      current(call("get_study_documentation", study()))
      form(shiny::isolate(form()) + 1L)
    }
    shiny::observeEvent(study(), {
      allowed(FALSE)
      current(NULL)
      status("")
      if (ready) {
        attempt(function() {
          allowed("manage" %in% call("get_capabilities", study()))
          if (allowed()) load()
        })
      }
    })
    output$body <- shiny::renderUI({
      shiny::req(allowed(), current())
      ns <- session$ns
      l <- lang()
      x <- current()
      key <- form()
      labels <- documentation_topic_labels(l)
      # Text typed into these fields survives a change of language.
      value <- function(name, stored) {
        typed <- shiny::isolate(input[[field_id(name, key)]])
        if (!is.null(typed)) typed else if (!is.null(stored)) stored else ""
      }
      shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Studiendokumentation f\u00fcr Berichte", "Study documentation for reports")),
        shiny::tags$p(tr(l, "Berichte erfinden keine Angaben zu Autorenschaft, Finanzierung, Interessenkonflikten, Genehmigungen, Interpretation oder Abweichungen. Tragen Sie hier die Aussagen des Studienteams ein. Leere Themen erscheinen im Bericht als nicht dokumentiert. Der Verweis auf eine Genehmigung erteilt keine Genehmigung.", "Reports never invent statements on authorship, funding, conflicts of interest, approvals, interpretation or deviations. Enter the study team\u2019s own statements here. Empty topics appear in reports as not documented. Recording a reference to an approval does not grant one.")),
        shiny::tags$p(class = "del-note", paste(tr(l, "Aktuelle Dokumentationsversion:", "Current documentation version:"), x$version)),
        lapply(topics, function(topic) shiny::textAreaInput(ns(field_id(topic, key)), labels[[topic]], value = value(topic, x$fields[[topic]]), width = "100%")),
        shiny::textAreaInput(ns(field_id("reason", key)), tr(l, "Begr\u00fcndung dieser Version", "Rationale for this version"), value = value("reason", ""), width = "100%"),
        shiny::checkboxInput(ns(field_id("confirm", key)), tr(l, "Ich habe diese Aussagen gepr\u00fcft. Die neue Version ersetzt die bisherige vollst\u00e4ndig.", "I reviewed these statements. The new version replaces the previous one completely."), FALSE),
        shiny::tags$div(class = "del-actions", shiny::actionButton(ns("save"), tr(l, "Neue Dokumentationsversion speichern", "Save new documentation version"), class = "btn-primary")),
        status_ui(ns("status")),
        shiny::tags$h3(tr(l, "Versionsverlauf", "Version history")),
        shiny::tableOutput(ns("history"))
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
      out <- data.frame(x$history$version, format_moment(x$history$recorded_at, "UTC", lang(), with_zone = FALSE), x$history$reason, stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("Version", "Gespeichert (UTC)", "Begr\u00fcndung"), c("Version", "Saved (UTC)", "Rationale"))
      out
    })
    shiny::observeEvent(input$save, attempt(function() {
      x <- current()
      key <- form()
      shiny::req(allowed(), x)
      # Only the confirmation of the fields shown for this version counts.
      reason <- input[[field_id("reason", key)]]
      reason <- if (is.null(reason)) "" else trimws(reason)
      if (!isTRUE(input[[field_id("confirm", key)]]) || !nzchar(reason)) {
        status(tr(lang(), "Begr\u00fcndung und Best\u00e4tigung sind erforderlich.", "A reason and confirmation are required."))
        return()
      }
      fields <- stats::setNames(lapply(topics, function(topic) {
        v <- input[[field_id(topic, key)]]
        if (is.null(v)) "" else v
      }), topics)
      fields <- fields[vapply(fields, function(v) nzchar(trimws(v)), logical(1))]
      if (!length(fields)) {
        status(tr(lang(), "Mindestens ein Thema muss eine Aussage enthalten.", "At least one topic needs a statement."))
        return()
      }
      result <- call("record_study_documentation", study(), fields, x$version, reason, command_id())
      load()
      status(paste(tr(lang(), "Dokumentationsversion gespeichert:", "Documentation version saved:"), result$version))
    }))
    list(current = current, form = form)
  })
}

exports_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

export_profile_capabilities <- function() {
  list(research_pseudonymized = "export", study_summary = c("analyse", "manage"), audit_restricted = c("audit", "manage"), contacts_restricted = "contacts_export")
}

export_profile_label <- function(profile, lang) {
  labels <- tr(
    lang,
    c(research_pseudonymized = "Pseudonymisierte Forschungsdaten", study_summary = "Aggregierte Studienzusammenfassung", audit_restricted = "Verlauf und Freigaben", contacts_restricted = "Kontaktdaten", research_round = "Pseudonymisierte Daten einer Runde"),
    c(research_pseudonymized = "Pseudonymized research data", study_summary = "Aggregated study summary", audit_restricted = "History and approvals", contacts_restricted = "Contact data", research_round = "Pseudonymized data of one round")
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

# Why a download was refused, without repeating what the server refused; the
# reference links it to one entry of the technical log.
download_error_text <- function(e, lang) {
  if (inherits(e, "DEL_UNAUTHORIZED")) {
    return(safe_error(e, lang))
  }
  text <- if (inherits(e, "DEL_NOT_FOUND")) {
    tr(lang, "Der Export ist nicht mehr verf\u00fcgbar: Downloads sind nur befristet m\u00f6glich. Bitte einen neuen Export beauftragen.", "The export is no longer available: downloads are possible for a limited time only. Request a new export.")
  } else if (inherits(e, "DEL_FORBIDDEN")) {
    tr(lang, "Ihre aktuellen Rechte erlauben diesen Download nicht.", "Your current rights do not permit this download.")
  } else {
    tr(lang, "Der Download ist fehlgeschlagen. Es wurde keine Datei ausgeliefert.", "The download failed. No file was delivered.")
  }
  paste(text, reference_text(error_reference(e), lang))
}

# Exports requested in this session: one row per operation, newest first.
export_requests <- function() data.frame(id = character(), profile = character(), purpose = character(), requested_at = character(), state = character(), artifact = character(), stringsAsFactors = FALSE)

export_state_label <- function(state, lang) if (identical(state, "refused")) tr(lang, "Download verweigert", "Download refused") else operation_state_label(state, lang)

# A failed export names the operation, so that it can be traced.
export_state_text <- function(state, id, lang) {
  label <- export_state_label(state, lang)
  if (state %in% c("retry_wait", "dead_letter")) shiny::tagList(label, " \u00b7 ", tr(lang, "Referenz:", "Reference:"), " ", ref_tag(id, 12L)) else label
}

# Study-level exports. The offered profiles follow the actor's current rights;
# the services check them again on request, on completion and on download.
exports_server <- function(id, study, lang, call, services, changed = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    # A purpose typed into the form belongs to the study it was typed for;
    # the form of another study starts empty.
    form_study <- NULL
    profiles <- shiny::reactiveVal(character())
    requested <- shiny::reactiveVal(export_requests())
    status <- shiny::reactiveVal("")
    ready <- all(c("get_capabilities", "request_study_export", "get_operation", "download_artifact") %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    shiny::observeEvent(study(), {
      profiles(character())
      requested(export_requests())
      status("")
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
      typed <- shiny::isolate(input$purpose)
      purpose <- if (identical(form_study, shiny::isolate(study())) && !is.null(typed)) typed else ""
      ui <- shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Exporte der Studie", "Study exports")),
        shiny::tags$p(tr(l, "Jedes Profil enth\u00e4lt nur die Daten seines Zwecks. Der Export wird im Hintergrund erstellt und privat gespeichert. Eine heruntergeladene Datei unterliegt nicht mehr der Zugriffskontrolle dieser Anwendung.", "Each profile contains only the data of its purpose. The export is prepared in the background and stored privately. A downloaded file is no longer covered by this application\u2019s access control.")),
        shiny::selectInput(ns("profile"), tr(l, "Exportprofil", "Export profile"), stats::setNames(profiles(), export_profile_label(profiles(), l)), selected = shiny::isolate(input$profile)),
        shiny::textOutput(ns("description"), container = shiny::tags$p),
        shiny::textAreaInput(ns("purpose"), tr(l, "Zweck dieses Exports (10 bis 500 Zeichen)", "Purpose of this export (10 to 500 characters)"), value = purpose, width = "100%", rows = 2),
        shiny::tags$p(class = "del-note", tr(l, "Der Zweck wird mit dem Export, im Verlauf und im Manifest der Exportdatei gespeichert.", "The purpose is stored with the export, in the history and in the manifest of the export file.")),
        shiny::checkboxInput(ns("confirm"), tr(l, "Ich bin zum Erhalt dieser Daten berechtigt und behandle die Datei entsprechend ihrem Zweck.", "I am entitled to receive these data and will handle the file according to its purpose."), FALSE),
        shiny::tags$div(class = "del-actions", shiny::actionButton(ns("request"), tr(l, "Export beauftragen", "Request export"), class = "btn-primary")),
        status_ui(ns("status")),
        shiny::uiOutput(ns("requested"))
      )
      form_study <<- shiny::isolate(study())
      ui
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    output$description <- shiny::renderText({
      shiny::req(input$profile)
      export_profile_description(input$profile, lang())
    })
    shiny::observeEvent(input$profile, shiny::updateCheckboxInput(session, "confirm", value = FALSE))
    output$requested <- shiny::renderUI({
      x <- requested()
      shiny::req(nrow(x) > 0)
      ns <- session$ns
      l <- lang()
      # Two columns, so that nothing is pushed out of sight on a phone.
      rows <- lapply(seq_len(nrow(x)), function(i) {
        list(
          shiny::tagList(
            shiny::tags$div(shiny::tags$strong(export_profile_label(x$profile[i], l))),
            shiny::tags$div(class = "del-note", paste(tr(l, "Beauftragt:", "Requested:"), format_moment(x$requested_at[i], "UTC", l))),
            shiny::tags$div(paste(tr(l, "Zweck:", "Purpose:"), x$purpose[i]))
          ),
          shiny::tagList(
            shiny::tags$div(export_state_text(x$state[i], x$id[i], l)),
            if (!is.na(x$artifact[i])) shiny::tags$div(shiny::downloadButton(ns(paste0("download_", x$id[i])), tr(l, "Herunterladen", "Download"), class = "btn-sm", icon = NULL))
          )
        )
      })
      pending <- any(x$state %in% c("queued", "running", "retry_wait"))
      shiny::tagList(
        shiny::tags$h3(tr(l, "Beauftragte Exporte", "Requested exports")),
        shiny::tags$p(class = "del-note", tr(l, "Exporte, die Sie in dieser Sitzung beauftragt haben. Sie werden im Hintergrund erstellt; ein fertiger Export kann befristet heruntergeladen werden.", "Exports you requested in this session. They are prepared in the background; a finished export can be downloaded for a limited time.")),
        markup_table(tr(l, c("Export", "Status"), c("Export", "State")), rows),
        if (pending) shiny::tags$div(class = "del-actions", shiny::actionButton(ns("poll"), tr(l, "Status pr\u00fcfen", "Check status")))
      )
    })
    # Each finished export gets its own download; a refusal names its reason
    # and the export is no longer offered.
    offered_downloads <- character()
    offer_download <- function(key) {
      if (key %in% offered_downloads) {
        return(invisible(NULL))
      }
      offered_downloads <<- c(offered_downloads, key)
      output[[paste0("download_", key)]] <- shiny::downloadHandler(
        filename = function() paste0("delphyr-", shiny::isolate(requested())$profile[match(key, shiny::isolate(requested())$id)], ".zip"),
        content = function(file) {
          x <- shiny::isolate(requested())
          k <- match(key, x$id)
          shiny::req(!is.na(k), !is.na(x$artifact[k]))
          tryCatch(
            {
              path <- call("download_artifact", x$artifact[k])
              zip::zipr(file, list.files(path, full.names = TRUE), root = path)
            },
            error = function(e) {
              refused <- shiny::isolate(requested())
              j <- match(key, refused$id)
              if (!is.na(j)) {
                refused$state[j] <- "refused"
                refused$artifact[j] <- NA_character_
                requested(refused)
              }
              status(download_error_text(e, shiny::isolate(lang())))
              stop(e)
            }
          )
        }, contentType = "application/zip"
      )
    }
    shiny::observeEvent(input$request, attempt(function() {
      shiny::req(input$profile %in% profiles())
      purpose <- if (is.null(input$purpose)) "" else trimws(input$purpose)
      if (nchar(purpose) < 10L || nchar(purpose) > 500L) {
        status(tr(lang(), "Bitte den Zweck des Exports in 10 bis 500 Zeichen angeben.", "Describe the purpose of the export in 10 to 500 characters."))
        return()
      }
      if (!isTRUE(input$confirm)) {
        status(tr(lang(), "Bitte die Berechtigung ausdr\u00fccklich best\u00e4tigen.", "Explicitly confirm your entitlement first."))
        return()
      }
      r <- call("request_study_export", study(), input$profile, command_id(), purpose = purpose)
      x <- requested()
      # A pending request of the same profile is merged by the service.
      x <- x[x$id != r$id, , drop = FALSE]
      row <- data.frame(id = r$id, profile = input$profile, purpose = purpose, requested_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), state = if (is.null(r$state)) "queued" else r$state, artifact = NA_character_, stringsAsFactors = FALSE)
      requested(rbind(row, x))
      shiny::updateCheckboxInput(session, "confirm", value = FALSE)
      shiny::updateTextAreaInput(session, "purpose", value = "")
      status(tr(lang(), "Export eingereiht. Mit \u201eStatus pr\u00fcfen\u201c verfolgen.", "Export queued. Follow it with \u201cCheck status\u201d."))
    }))
    shiny::observeEvent(input$poll, attempt(function() {
      x <- requested()
      open <- which(x$state %in% c("queued", "running", "retry_wait"))
      shiny::req(length(open) > 0)
      for (i in open) {
        r <- call("get_operation", x$id[i])
        x$state[i] <- r$state
        if (identical(r$state, "succeeded")) x$artifact[i] <- r$result_ref
      }
      requested(x)
      for (i in which(!is.na(x$artifact))) offer_download(x$id[i])
      status(paste(tr(lang(), "Status des neuesten Exports:", "State of the latest export:"), export_state_label(x$state[1], lang())))
    }))
    list(profiles = profiles, requested = requested)
  })
}
