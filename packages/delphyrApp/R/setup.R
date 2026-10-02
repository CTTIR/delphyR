study_create_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

# Key facts of a protocol for review before a study is created from it.
protocol_summary <- function(p, lang) {
  rule <- p$analysis$consensus
  bound <- function(b) paste(switch(b$operator, gte = "\u2265", gt = ">", lte = "\u2264", lt = "<"), b$proportion)
  dimensions <- vapply(p$instrument$dimensions, function(d) paste0(d$code, " (", d$scale, ")"), character(1))
  values <- c(
    p$study$code, p$study$title, p$study$design, paste(unlist(p$study$languages), collapse = ", "), p$study$timezone,
    paste(unlist(p$panel$groups), collapse = ", "), paste(dimensions, collapse = ", "),
    paste0(tr(lang, "Zustimmung", "agreement"), " ", paste(range(unlist(rule$agree_values)), collapse = "\u2013"), " ", bound(rule$`in`$agree), "; ", tr(lang, "Ablehnung", "disagreement"), " ", paste(range(unlist(rule$disagree_values)), collapse = "\u2013"), " ", bound(rule$`in`$disagree)),
    as.character(rule$min_valid_n), if (identical(rule$group_policy, "all_required_groups")) tr(lang, "in jeder erforderlichen Gruppe", "in every required group") else tr(lang, "im Gesamtpanel", "in the pooled panel"),
    as.character(p$stopping$max_rounds), as.character(p$feedback$minimum_display_cell_n)
  )
  out <- data.frame(tr(lang, c("Studiencode", "Titel", "Design", "Sprachen", "Zeitzone", "Interessengruppen", "Dimensionen (Skalen)", "Konsens f\u00fcr Aufnahme", "G\u00fcltiges Mindest-n", "Gruppenregel", "H\u00f6chstzahl der Runden", "Mindestzellgr\u00f6\u00dfe der Anzeige"), c("Study code", "Title", "Design", "Languages", "Timezone", "Stakeholder groups", "Dimensions (scales)", "Consensus for inclusion", "Minimum valid n", "Group rule", "Maximum number of rounds", "Display minimum cell size")), values, stringsAsFactors = FALSE)
  names(out) <- tr(lang, c("Feld", "Wert"), c("Field", "Value"))
  out
}

# Creating a study is an account right granted by the operator. The exact
# uploaded protocol is validated, shown and confirmed before anything is stored.
study_create_server <- function(id, lang, call, services, on_created = function(study_id) NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ready <- all(c("get_account_rights", "create_study") %in% names(services))
    allowed <- shiny::reactiveVal(FALSE)
    candidate <- shiny::reactiveVal(NULL)
    status <- shiny::reactiveVal("")
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    if (ready) attempt(function() allowed(isTRUE(call("get_account_rights")$can_create_study)))
    output$body <- shiny::renderUI({
      shiny::req(allowed())
      ns <- session$ns
      l <- lang()
      shiny::tags$section(
        class = "del-sheet",
        shiny::tags$details(
          shiny::tags$summary(tr(l, "Neue Studie anlegen", "Create a new study")),
          shiny::tags$p(tr(l, "Laden Sie ein vollst\u00e4ndiges Studienprotokoll als JSON hoch. Es wird gepr\u00fcft und angezeigt; erst Ihre Best\u00e4tigung legt die Studie mit Protokollversion 1 an. Schwellenwerte sind methodische Entscheidungen des Studienteams. In dieser Entwicklungsumgebung sind nur synthetische Studien zul\u00e4ssig.", "Upload a complete study protocol as JSON. It is validated and displayed; only your confirmation creates the study with protocol version 1. Thresholds are methodological decisions of the study team. Only synthetic studies are permitted in this development environment.")),
          shiny::fileInput(ns("file"), tr(l, "Studienprotokoll (JSON, h\u00f6chstens 1 MB)", "Study protocol (JSON, maximum 1 MB)"), accept = ".json", buttonLabel = tr(l, "Durchsuchen\u2026", "Browse\u2026"), placeholder = tr(l, "Keine Datei ausgew\u00e4hlt", "No file selected")),
          shiny::actionButton(ns("validate"), tr(l, "Protokoll pr\u00fcfen", "Validate protocol")),
          shiny::tableOutput(ns("summary")),
          shiny::uiOutput(ns("confirmation"))
        ),
        status_ui(ns("status"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    shiny::observeEvent(input$file, candidate(NULL), ignoreNULL = FALSE)
    shiny::observeEvent(input$validate, {
      shiny::req(allowed(), input$file)
      candidate(NULL)
      tryCatch(
        {
          p <- read_protocol_upload(input$file)
          candidate(list(protocol = p, hash = delphyr::content_hash(p)))
          status(tr(lang(), "Protokoll g\u00fcltig. Noch keine Studie angelegt.", "Protocol is valid. No study has been created yet."))
        },
        error = function(e) {
          path <- if (inherits(e, "delphyr_error") && is.character(e$path) && nzchar(e$path)) e$path else ""
          status(paste(tr(lang(), "Protokoll ung\u00fcltig. Beanstandetes Feld:", "Protocol is invalid. Field in question:"), path))
        }
      )
    })
    output$summary <- shiny::renderTable({
      x <- candidate()
      shiny::req(x)
      protocol_summary(x$protocol, lang())
    })
    output$confirmation <- shiny::renderUI({
      x <- candidate()
      shiny::req(x)
      ns <- session$ns
      shiny::tagList(
        shiny::tags$details(shiny::tags$summary(tr(lang(), "Vollst\u00e4ndiges Protokoll", "Complete protocol")), shiny::tags$pre(jsonlite::toJSON(unclass(x$protocol), auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA))),
        shiny::checkboxInput(ns("confirm"), tr(lang(), "Ich habe dieses genaue Protokoll gepr\u00fcft und lege die Studie damit an.", "I reviewed this exact protocol and create the study with it."), FALSE),
        shiny::actionButton(ns("create"), tr(lang(), "Studie anlegen", "Create study"), class = "btn-primary")
      )
    })
    shiny::observeEvent(input$create, attempt(function() {
      x <- candidate()
      shiny::req(allowed(), x, input$file)
      if (!isTRUE(input$confirm)) {
        status(tr(lang(), "Bitte das Protokoll ausdr\u00fccklich best\u00e4tigen.", "Explicitly confirm the protocol first."))
        return()
      }
      current <- read_protocol_upload(input$file)
      if (!identical(delphyr::content_hash(current), x$hash)) stop("Upload changed since validation")
      result <- call("create_study", x$protocol, command_id())
      candidate(NULL)
      status(paste(tr(lang(), "Studie angelegt:", "Study created:"), x$protocol$study$code))
      on_created(result$id)
    }))
    list(allowed = allowed, candidate = candidate)
  })
}

study_setup_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

staff_capability_label <- function(capability, lang) {
  labels <- tr(
    lang,
    c(manage = "Studienleitung", analyse = "Auswertung", export = "Export der Forschungsdaten", coordinate = "Koordination", edit = "Redaktion", audit = "Verlauf einsehen (Audit)", contacts_export = "Kontaktexport"),
    c(manage = "Study leadership", analyse = "Analysis", export = "Research data export", coordinate = "Coordination", edit = "Editorial work", audit = "Read the history (audit)", contacts_export = "Contact export")
  )
  unname(ifelse(capability %in% names(labels), labels[capability], capability))
}

# Study information, staff rights and the pseudonymous panel of one study.
study_setup_server <- function(id, study, lang, call, services, touch = function() NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    field <- function(name, default = "") {
      value <- shiny::isolate(input[[name]])
      if (is.null(value)) default else value
    }
    needed <- c("get_capabilities", "get_study_setup", "publish_consent", "list_study_staff", "register_staff_account", "set_capability", "list_panel", "set_panel_group")
    ready <- all(needed %in% names(services))
    allowed <- shiny::reactiveVal(FALSE)
    setup <- shiny::reactiveVal(NULL)
    staff <- shiny::reactiveVal(data.frame())
    panel <- shiny::reactiveVal(data.frame())
    status <- shiny::reactiveVal("")
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    refresh <- function() {
      setup(call("get_study_setup", study()))
      staff(call("list_study_staff", study()))
      panel(call("list_panel", study()))
    }
    shiny::observeEvent(study(), {
      allowed(FALSE)
      setup(NULL)
      staff(data.frame())
      panel(data.frame())
      if (ready) {
        attempt(function() {
          allowed("manage" %in% call("get_capabilities", study()))
          if (allowed()) refresh()
        })
      }
    })
    required <- function(reason, confirm) {
      if (!isTRUE(confirm) || is.null(reason) || !nzchar(trimws(reason))) {
        status(tr(lang(), "Begr\u00fcndung und Best\u00e4tigung sind erforderlich.", "A reason and confirmation are required."))
        return(FALSE)
      }
      TRUE
    }
    output$body <- shiny::renderUI({
      shiny::req(allowed(), setup())
      ns <- session$ns
      l <- lang()
      languages <- unlist(setup()$protocol$study$languages)
      groups <- unlist(setup()$protocol$panel$groups)
      people <- staff()
      members <- panel()
      capabilities <- c("manage", "analyse", "export", "coordinate", "edit", "audit", "contacts_export")
      shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Studieneinrichtung", "Study setup")),
        shiny::tags$h3(tr(l, "Studieninformation", "Study information")),
        shiny::tags$p(tr(l, "Jede ver\u00f6ffentlichte Fassung ist unver\u00e4nderlich. Eine Runde verweist auf genau eine Fassung; ge\u00e4nderter Text ist eine neue Fassung.", "Each published version is immutable. A round refers to exactly one version; changed text is a new version.")),
        shiny::tableOutput(ns("consents")),
        shiny::tags$details(
          shiny::tags$summary(tr(l, "Neue Fassung ver\u00f6ffentlichen", "Publish a new version")),
          shiny::textAreaInput(ns("consent_text"), tr(l, "Text der Studieninformation und Einwilligung", "Study information and consent text"), value = field("consent_text"), width = "100%", rows = 6),
          shiny::selectInput(ns("consent_locale"), tr(l, "Sprache dieses Textes", "Language of this text"), languages, selected = field("consent_locale", languages[1])),
          shiny::checkboxInput(ns("consent_confirm"), tr(l, "Ich habe diesen genauen Text gepr\u00fcft. Er kann nach der Ver\u00f6ffentlichung nicht ge\u00e4ndert werden.", "I reviewed this exact text. It cannot be changed after publication."), FALSE),
          shiny::actionButton(ns("consent_publish"), tr(l, "Studieninformation ver\u00f6ffentlichen", "Publish study information"))
        ),
        shiny::tags$h3(tr(l, "Studienteam und Rechte", "Study team and rights")),
        shiny::tags$p(tr(l, "Rechte gelten f\u00fcr genau ein Konto mit Aussteller und Subject, nie f\u00fcr eine E-Mail-Adresse. Jede \u00c4nderung wirkt ab der n\u00e4chsten gesch\u00fctzten Aktion der Person und wird mit Begr\u00fcndung aufgezeichnet. Das letzte Leitungsrecht einer Studie kann nicht entzogen werden.", "Rights apply to exactly one account with issuer and subject, never to an email address. Each change takes effect at the person\u2019s next protected action and is recorded with its rationale. The last management right of a study cannot be revoked.")),
        shiny::tableOutput(ns("staff")),
        shiny::tags$details(
          shiny::tags$summary(tr(l, "Recht erteilen oder entziehen", "Grant or revoke a right")),
          shiny::selectInput(ns("staff_account"), tr(l, "Konto", "Account"), c(if (nrow(people)) stats::setNames(people$principal_id, people$subject), stats::setNames("new", tr(l, "Weiteres Konto angeben", "Specify another account"))), selected = field("staff_account", if (nrow(people)) people$principal_id[1] else "new")),
          shiny::textInput(ns("staff_issuer"), tr(l, "Aussteller des weiteren Kontos", "Issuer of the other account"), value = field("staff_issuer"), width = "100%"),
          shiny::textInput(ns("staff_subject"), tr(l, "Subject des weiteren Kontos", "Subject of the other account"), value = field("staff_subject"), width = "100%"),
          shiny::selectInput(ns("staff_capability"), tr(l, "Recht", "Right"), stats::setNames(capabilities, staff_capability_label(capabilities, l)), selected = field("staff_capability", "analyse")),
          shiny::selectInput(ns("staff_action"), tr(l, "\u00c4nderung", "Change"), stats::setNames(c("grant", "revoke"), c(tr(l, "Erteilen", "Grant"), tr(l, "Entziehen", "Revoke"))), selected = field("staff_action", "grant")),
          shiny::textAreaInput(ns("staff_reason"), tr(l, "Begr\u00fcndung der Rechte\u00e4nderung", "Rationale for the change of rights"), value = field("staff_reason"), width = "100%"),
          shiny::checkboxInput(ns("staff_confirm"), tr(l, "Ich habe Konto, Recht und \u00c4nderung gepr\u00fcft.", "I reviewed the account, the right and the change."), FALSE),
          shiny::actionButton(ns("staff_apply"), tr(l, "Rechte\u00e4nderung anwenden", "Apply change of rights"))
        ),
        shiny::tags$h3(tr(l, "Panel", "Panel")),
        shiny::tags$p(tr(l, "Das Panel erscheint nur mit Studienpseudonymen. Eine ge\u00e4nderte Interessengruppe gilt f\u00fcr k\u00fcnftig vorbereitete Runden; fr\u00fchere Runden behalten ihre Zuordnung.", "The panel appears by study pseudonym only. A changed stakeholder group applies to rounds prepared in future; earlier rounds keep their assignment.")),
        shiny::tableOutput(ns("panel")),
        shiny::tags$details(
          shiny::tags$summary(tr(l, "Interessengruppe \u00e4ndern", "Change a stakeholder group")),
          shiny::selectInput(ns("group_panelist"), tr(l, "Pseudonym", "Pseudonym"), if (nrow(members)) stats::setNames(members$panelist_id, paste(members$panelist_id, "\u00b7", members$group_code)) else character(), selected = field("group_panelist", NULL)),
          shiny::selectInput(ns("group_code"), tr(l, "Neue Interessengruppe", "New stakeholder group"), groups, selected = field("group_code", groups[1])),
          shiny::textAreaInput(ns("group_reason"), tr(l, "Begr\u00fcndung der Gruppen\u00e4nderung", "Rationale for the group change"), value = field("group_reason"), width = "100%"),
          shiny::checkboxInput(ns("group_confirm"), tr(l, "Ich habe Pseudonym und neue Gruppe gepr\u00fcft.", "I reviewed the pseudonym and the new group."), FALSE),
          shiny::actionButton(ns("group_apply"), tr(l, "Interessengruppe \u00e4ndern", "Change stakeholder group"))
        ),
        status_ui(ns("status"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    output$consents <- shiny::renderTable({
      x <- setup()
      shiny::req(x)
      versions <- x$consent_versions
      if (!nrow(versions)) {
        return(NULL)
      }
      out <- data.frame(seq_len(nrow(versions)), versions$locale, versions$content, stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("Fassung", "Sprache", "Text"), c("Version", "Language", "Text"))
      out
    })
    output$staff <- shiny::renderTable({
      x <- staff()
      shiny::req(nrow(x) > 0)
      rights <- function(v) vapply(strsplit(v, ", ", fixed = TRUE), function(z) paste(staff_capability_label(z, lang()), collapse = "; "), character(1))
      out <- data.frame(x$subject, x$issuer, rights(x$granted), rights(x$revoked), ifelse(x$active, tr(lang(), "aktiv", "active"), tr(lang(), "gesperrt", "disabled")), stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("Subject", "Aussteller", "Erteilte Rechte", "Entzogene Rechte", "Konto"), c("Subject", "Issuer", "Granted rights", "Revoked rights", "Account"))
      out
    })
    output$panel <- shiny::renderTable({
      x <- panel()
      shiny::req(nrow(x) > 0)
      out <- data.frame(x$panelist_id, x$group_code, ifelse(x$withdrawn, tr(lang(), "Teilnahme beendet", "Participation ended"), ifelse(x$active, tr(lang(), "aktiv", "active"), tr(lang(), "inaktiv", "inactive"))), x$rounds_enrolled, x$rounds_submitted, stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("Pseudonym", "Interessengruppe", "Teilnahme", "Runden aufgenommen", "Runden abgegeben"), c("Pseudonym", "Stakeholder group", "Participation", "Rounds enrolled", "Rounds submitted"))
      out
    })
    shiny::observeEvent(input$consent_publish, attempt(function() {
      shiny::req(allowed())
      text <- if (is.null(input$consent_text)) "" else input$consent_text
      if (!isTRUE(input$consent_confirm) || !nzchar(trimws(text))) {
        status(tr(lang(), "Text und Best\u00e4tigung sind erforderlich.", "A text and confirmation are required."))
        return()
      }
      call("publish_consent", study(), text, input$consent_locale, command_id())
      touch()
      shiny::updateCheckboxInput(session, "consent_confirm", value = FALSE)
      shiny::updateTextAreaInput(session, "consent_text", value = "")
      refresh()
      status(tr(lang(), "Studieninformation ver\u00f6ffentlicht.", "Study information published."))
    }))
    shiny::observeEvent(input$staff_apply, attempt(function() {
      shiny::req(allowed(), input$staff_account, input$staff_capability, input$staff_action)
      if (!required(input$staff_reason, input$staff_confirm)) {
        return()
      }
      reason <- trimws(input$staff_reason)
      account <- input$staff_account
      if (identical(account, "new")) account <- call("register_staff_account", study(), trimws(input$staff_issuer), trimws(input$staff_subject), reason, command_id())$id
      call("set_capability", study(), account, input$staff_capability, identical(input$staff_action, "grant"), command_id(), reason = reason)
      touch()
      shiny::updateCheckboxInput(session, "staff_confirm", value = FALSE)
      status(tr(lang(), "Rechte\u00e4nderung best\u00e4tigt.", "Change of rights confirmed."))
      # The actor may just have given up the right to see this section.
      allowed("manage" %in% call("get_capabilities", study()))
      if (allowed()) refresh()
    }))
    shiny::observeEvent(input$group_apply, attempt(function() {
      shiny::req(allowed(), input$group_panelist, input$group_code)
      if (!required(input$group_reason, input$group_confirm)) {
        return()
      }
      call("set_panel_group", study(), input$group_panelist, input$group_code, trimws(input$group_reason), command_id())
      shiny::updateCheckboxInput(session, "group_confirm", value = FALSE)
      refresh()
      status(tr(lang(), "Interessengruppe ge\u00e4ndert. Fr\u00fchere Runden bleiben unver\u00e4ndert.", "Stakeholder group changed. Earlier rounds are unchanged."))
    }))
    list(allowed = allowed, staff = staff, panel = panel)
  })
}
