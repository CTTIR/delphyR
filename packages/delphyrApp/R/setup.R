study_create_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

# Languages are named in their own language, as in the language selector.
locale_name <- function(code) {
  known <- c(en = "English", fr = "Fran\u00e7ais", de = "Deutsch")
  code <- as.character(code)
  unname(ifelse(code %in% names(known), known[code], code))
}

# Key facts of a protocol: for review before a study is created from it and
# for the saved versions of a study. Stakeholder groups and dimensions are
# study content; their codes are only made readable.
protocol_summary <- function(p, lang) {
  rule <- p$analysis$consensus
  words <- tr(lang, c(gte = "mindestens", gt = "mehr als", lte = "h\u00f6chstens", lt = "weniger als"), c(gte = "at least", gt = "more than", lte = "at most", lt = "less than"))
  span <- function(values) {
    v <- range(unlist(values))
    if (v[1] == v[2]) as.character(v[1]) else paste0(v[1], "\u2013", v[2])
  }
  # A threshold keeps its decimals; only a share of ratings is rounded.
  share <- function(x) paste0(format_number(100 * x, lang, 2L), if (lang %in% c("fr", "de")) "\u00a0%" else "%")
  agree <- function(b) sprintf(tr(lang, "%s %s Zustimmung (%s)", "%s %s agreement (%s)"), words[[b$operator]], share(b$proportion), span(rule$agree_values))
  disagree <- function(b) sprintf(tr(lang, "%s %s Ablehnung (%s)", "%s %s disagreement (%s)"), words[[b$operator]], share(b$proportion), span(rule$disagree_values))
  consensus <- function(side) paste(agree(side$agree), tr(lang, "und", "and"), disagree(side$disagree))
  designs <- tr(lang, c(modified_round_based_delphi = "Modifiziertes Delphi in Runden", exploratory_round_based_delphi = "Exploratives Delphi in Runden"), c(modified_round_based_delphi = "Modified Delphi in rounds", exploratory_round_based_delphi = "Exploratory Delphi in rounds"))
  design <- if (isTRUE(p$study$design %in% names(designs))) designs[[p$study$design]] else as.character(p$study$design)
  dimensions <- vapply(p$instrument$dimensions, function(d) paste0(humanize_code(d$code), " (", d$scale, ")"), character(1))
  values <- c(
    p$study$code, p$study$title, design, paste(locale_name(unlist(p$study$languages)), collapse = ", "), p$study$timezone,
    paste(humanize_code(unlist(p$panel$groups)), collapse = ", "), paste(dimensions, collapse = ", "),
    consensus(rule$`in`), consensus(rule$out),
    as.character(rule$min_valid_n), if (identical(rule$group_policy, "all_required_groups")) tr(lang, "in jeder erforderlichen Gruppe", "in every required group") else tr(lang, "im Gesamtpanel", "in the pooled panel"),
    as.character(p$stopping$max_rounds), as.character(p$feedback$minimum_display_cell_n)
  )
  out <- data.frame(tr(lang, c("Studiencode", "Titel", "Design", "Sprachen", "Zeitzone", "Interessengruppen", "Dimensionen (Skalen)", "Konsens f\u00fcr Aufnahme", "Konsens f\u00fcr Ausschluss", "G\u00fcltiges Mindest-n", "Gruppenregel", "H\u00f6chstzahl der Runden", "Mindestzellgr\u00f6\u00dfe der Anzeige"), c("Study code", "Title", "Design", "Languages", "Timezone", "Stakeholder groups", "Dimensions (scales)", "Consensus for inclusion", "Consensus for exclusion", "Minimum valid n", "Group rule", "Maximum number of rounds", "Display minimum cell size")), values, stringsAsFactors = FALSE)
  names(out) <- tr(lang, c("Feld", "Wert"), c("Field", "Value"))
  out
}

# The complete protocol as it is shown for review.
protocol_json <- function(p) jsonlite::toJSON(unclass(p), auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)

# Creating a study is an account right granted by the operator. The exact
# uploaded protocol is validated, shown and confirmed before anything is stored.
study_create_server <- function(id, lang, call, services, on_created = function(study_id) NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ready <- all(c("get_account_rights", "create_study") %in% names(services))
    allowed <- shiny::reactiveVal(FALSE)
    # An account that already has studies sees the steps behind a summary line.
    has_studies <- shiny::reactiveVal(FALSE)
    candidate <- shiny::reactiveVal(NULL)
    file_ready <- shiny::reactiveVal(FALSE)
    status <- shiny::reactiveVal("")
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    if (ready) {
      attempt(function() {
        can <- isTRUE(call("get_account_rights")$can_create_study)
        allowed(can)
        if (can && "list_studies" %in% names(services)) has_studies(NROW(call("list_studies")) > 0L)
      })
    }
    output$body <- shiny::renderUI({
      shiny::req(allowed())
      ns <- session$ns
      l <- lang()
      steps <- shiny::tagList(
        shiny::tags$p(tr(l, "Eine Studie entsteht aus einem vollst\u00e4ndigen Studienprotokoll im JSON-Format. Es wird gepr\u00fcft und angezeigt; erst Ihre Best\u00e4tigung legt die Studie mit Protokollversion 1 an.", "A study is created from a complete study protocol in JSON format. It is checked and shown to you; only your confirmation creates the study with protocol version 1.")),
        shiny::tags$ol(
          shiny::tags$li(
            shiny::downloadLink(ns("example"), tr(l, "Beispielprotokoll (JSON) herunterladen", "Download the example protocol (JSON)")), " ",
            tr(l, "und anpassen: Code und Titel der Studie, Sprachen, Interessengruppen, Bewertungsdimensionen und Skalen, Konsensregel und Rundenzahl.", "and adapt it: study code and title, languages, stakeholder groups, rating dimensions and scales, consensus rule and number of rounds.")
          ),
          shiny::tags$li(tr(l, "Die Datei ausw\u00e4hlen und pr\u00fcfen lassen.", "Choose the file and validate it.")),
          shiny::tags$li(tr(l, "Zusammenfassung und vollst\u00e4ndiges Protokoll pr\u00fcfen, dann best\u00e4tigen.", "Review the summary and the complete protocol, then confirm."))
        ),
        shiny::tags$p(class = "del-note", tr(l, "Das Beispiel ist ein vollst\u00e4ndiges, g\u00fcltiges Protokoll mit Beispielwerten: Ersetzen Sie diese durch die Werte Ihrer Studie und behalten Sie den Aufbau bei. Ist ein Wert nicht zul\u00e4ssig, nennt die Pr\u00fcfung das beanstandete Feld. Mehr dazu im Benutzerhandbuch von delphyR (englisch), Abschnitt \u201eCreate and set up a study\u201c.", "The example is a complete, valid protocol with example values: replace them with those of your study and keep its structure. If a value is not allowed, the validation names the field in question. More in the delphyR user guide, section \u201cCreate and set up a study\u201d.")),
        file_input(ns("file"), tr(l, "Studienprotokoll (JSON, h\u00f6chstens 1 MB)", "Study protocol (JSON, maximum 1 MB)"), accept = ".json", buttonLabel = tr(l, "Durchsuchen\u2026", "Browse\u2026"), placeholder = tr(l, "Keine Datei ausgew\u00e4hlt", "No file selected")),
        shiny::uiOutput(ns("validate_action")),
        shiny::tableOutput(ns("summary")),
        shiny::uiOutput(ns("confirmation"))
      )
      shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Neue Studie anlegen", "Create a new study")),
        if (has_studies()) shiny::tags$details(shiny::tags$summary(tr(l, "Schritte und Formular anzeigen", "Show the steps and the form")), steps) else steps,
        status_ui(ns("status"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    output$example <- shiny::downloadHandler(
      filename = function() "delphyr-example-protocol.json",
      content = function(file) writeLines(protocol_json(delphyr::demo_protocol()), file, useBytes = TRUE),
      contentType = "application/json"
    )
    output$validate_action <- shiny::renderUI({
      l <- lang()
      chosen <- file_ready()
      shiny::tagList(
        shiny::tags$div(class = "del-actions", shiny::actionButton(session$ns("validate"), tr(l, "Protokoll pr\u00fcfen", "Validate protocol"), disabled = !chosen)),
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
    shiny::observeEvent(input$validate, {
      shiny::req(allowed())
      if (!file_ready()) {
        status(tr(lang(), "Zuerst eine Protokolldatei ausw\u00e4hlen.", "Choose a protocol file first."))
        return()
      }
      candidate(NULL)
      tryCatch(
        {
          p <- read_protocol_upload(input$file)
          candidate(list(protocol = p, hash = delphyr::content_hash(p)))
          status(tr(lang(), "Protokoll g\u00fcltig. Noch keine Studie angelegt.", "Protocol is valid. No study has been created yet."))
        },
        error = function(e) status(protocol_upload_error(e, lang()))
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
        shiny::tags$p(class = "del-note", tr(lang(), "Schwellenwerte wie die Konsensregel und das g\u00fcltige Mindest-n sind methodische Entscheidungen des Studienteams.", "Thresholds such as the consensus rule and the minimum valid n are methodological decisions of the study team.")),
        shiny::tags$details(shiny::tags$summary(tr(lang(), "Vollst\u00e4ndiges Protokoll", "Complete protocol")), shiny::tags$pre(protocol_json(x$protocol))),
        shiny::checkboxInput(ns("confirm"), tr(lang(), "Ich habe dieses genaue Protokoll gepr\u00fcft und lege die Studie damit an.", "I reviewed this exact protocol and create the study with it."), FALSE),
        shiny::tags$div(class = "del-actions", shiny::actionButton(ns("create"), tr(lang(), "Studie anlegen", "Create study"), class = "btn-primary"))
      )
    })
    shiny::observeEvent(input$create, attempt(function() {
      x <- candidate()
      shiny::req(allowed(), x, file_ready())
      if (!isTRUE(input$confirm)) {
        status(tr(lang(), "Bitte das Protokoll ausdr\u00fccklich best\u00e4tigen.", "Explicitly confirm the protocol first."))
        return()
      }
      current <- tryCatch(delphyr::content_hash(read_protocol_upload(input$file)), error = function(e) NA_character_)
      if (!identical(current, x$hash)) {
        status(tr(lang(), "Die Datei wurde nach der Pr\u00fcfung ge\u00e4ndert. Bitte erneut pr\u00fcfen.", "The file changed after it was validated. Validate it again."))
        return()
      }
      result <- call("create_study", x$protocol, command_id())
      candidate(NULL)
      has_studies(TRUE)
      file_ready(FALSE)
      status(paste(tr(lang(), "Studie angelegt:", "Study created:"), x$protocol$study$code))
      on_created(result$id)
    }))
    list(allowed = allowed, candidate = candidate, file_ready = file_ready)
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

# What a change of rights does, before it is confirmed.
staff_change_text <- function(account, issuer, subject, capability, action, people, lang) {
  if (is.null(account) || !nzchar(account)) {
    return(tr(lang, "Noch kein Konto gew\u00e4hlt.", "No account chosen yet."))
  }
  issuer <- if (is.null(issuer)) "" else trimws(issuer)
  subject <- if (is.null(subject)) "" else trimws(subject)
  who <- if (identical(account, "new")) {
    if (!nzchar(issuer) || !nzchar(subject)) {
      return(tr(lang, "Identit\u00e4tsanbieter und Kontokennung des weiteren Kontos fehlen noch.", "The identity provider and the account identifier of the other account are still missing."))
    }
    sprintf(tr(lang, "das Konto %s von %s", "the account %s of %s"), subject, issuer)
  } else {
    name <- if (NROW(people)) as.character(people$subject[match(account, people$principal_id)]) else NA_character_
    if (is.na(name)) short_ref(account) else name
  }
  right <- staff_capability_label(if (is.null(capability)) "" else capability, lang)
  template <- if (identical(action, "revoke")) {
    tr(lang, "Diese \u00c4nderung entzieht %2$s das Recht \u201e%1$s\u201c.", "This change revokes the right \u201c%1$s\u201d from %2$s.")
  } else {
    tr(lang, "Diese \u00c4nderung erteilt %2$s das Recht \u201e%1$s\u201c.", "This change grants the right \u201c%1$s\u201d to %2$s.")
  }
  sprintf(template, right, who)
}

# Study information, staff rights and the pseudonymous panel of one study.
study_setup_server <- function(id, study, lang, call, services, touch = function() NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    # Values typed into a form belong to the study they were typed for; the
    # forms of another study start empty.
    form_study <- NULL
    field <- function(name, default = "") {
      if (!identical(form_study, shiny::isolate(study()))) {
        return(default)
      }
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
      status("")
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
      accounts <- c(stats::setNames("", tr(l, "Konto w\u00e4hlen", "Choose an account")), if (nrow(people)) stats::setNames(people$principal_id, people$subject), stats::setNames("new", tr(l, "Weiteres Konto angeben", "Specify another account")))
      pseudonyms <- c(stats::setNames("", tr(l, "Pseudonym w\u00e4hlen", "Choose a pseudonym")), if (nrow(members)) stats::setNames(members$panelist_id, paste(short_ref(members$panelist_id), "\u00b7", humanize_code(members$group_code))))
      ui <- shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Studieneinrichtung", "Study setup")),
        shiny::tags$h3(tr(l, "Studieninformation", "Study information")),
        shiny::tags$p(tr(l, "Jede ver\u00f6ffentlichte Fassung ist unver\u00e4nderlich. Eine Runde verweist auf genau eine Fassung; ge\u00e4nderter Text ist eine neue Fassung.", "Each published version is immutable. A round refers to exactly one version; changed text is a new version.")),
        shiny::tableOutput(ns("consents")),
        shiny::tags$details(
          shiny::tags$summary(tr(l, "Neue Fassung ver\u00f6ffentlichen", "Publish a new version")),
          shiny::textAreaInput(ns("consent_text"), tr(l, "Text der Studieninformation und Einwilligung", "Study information and consent text"), value = field("consent_text"), width = "100%", rows = 6),
          shiny::selectInput(ns("consent_locale"), tr(l, "Sprache dieses Textes", "Language of this text"), stats::setNames(languages, locale_name(languages)), selected = field("consent_locale", languages[1])),
          shiny::checkboxInput(ns("consent_confirm"), tr(l, "Ich habe diesen genauen Text gepr\u00fcft. Er kann nach der Ver\u00f6ffentlichung nicht ge\u00e4ndert werden.", "I reviewed this exact text. It cannot be changed after publication."), FALSE),
          shiny::tags$div(class = "del-actions", shiny::actionButton(ns("consent_publish"), tr(l, "Studieninformation ver\u00f6ffentlichen", "Publish study information")))
        ),
        shiny::tags$h3(tr(l, "Studienteam und Rechte", "Study team and rights")),
        shiny::tags$p(tr(l, "Ein Recht gilt f\u00fcr genau ein Konto, bestimmt durch seinen Identit\u00e4tsanbieter (Issuer) und seine Kontokennung bei diesem Anbieter (Subject), nie durch eine E-Mail-Adresse. Jede \u00c4nderung gilt ab der n\u00e4chsten Aktion der Person in der Anwendung und wird mit ihrer Begr\u00fcndung aufgezeichnet. Das letzte Leitungsrecht einer Studie kann nicht entzogen werden.", "A right applies to exactly one account, identified by its identity provider (issuer) and its account identifier at that provider (subject), never by an email address. Each change applies from the person\u2019s next action in the application and is recorded with its rationale. The last management right of a study cannot be revoked.")),
        shiny::tableOutput(ns("staff")),
        shiny::tags$details(
          shiny::tags$summary(tr(l, "Recht erteilen oder entziehen", "Grant or revoke a right")),
          shiny::selectInput(ns("staff_account"), tr(l, "Konto", "Account"), accounts, selected = field("staff_account", ""), width = "100%"),
          shiny::conditionalPanel(
            "input.staff_account == 'new'",
            ns = ns,
            shiny::textInput(ns("staff_issuer"), tr(l, "Identit\u00e4tsanbieter des weiteren Kontos (Issuer)", "Identity provider of the other account (issuer)"), value = field("staff_issuer"), width = "100%"),
            shiny::textInput(ns("staff_subject"), tr(l, "Kontokennung beim Identit\u00e4tsanbieter (Subject)", "Account identifier at that provider (subject)"), value = field("staff_subject"), width = "100%")
          ),
          shiny::selectInput(ns("staff_capability"), tr(l, "Recht", "Right"), stats::setNames(capabilities, staff_capability_label(capabilities, l)), selected = field("staff_capability", "analyse")),
          shiny::selectInput(ns("staff_action"), tr(l, "\u00c4nderung", "Change"), stats::setNames(c("grant", "revoke"), c(tr(l, "Erteilen", "Grant"), tr(l, "Entziehen", "Revoke"))), selected = field("staff_action", "grant")),
          shiny::textAreaInput(ns("staff_reason"), tr(l, "Begr\u00fcndung der Rechte\u00e4nderung", "Rationale for the change of rights"), value = field("staff_reason"), width = "100%"),
          shiny::textOutput(ns("staff_change"), container = shiny::tags$p),
          shiny::checkboxInput(ns("staff_confirm"), tr(l, "Ich habe Konto, Recht und \u00c4nderung gepr\u00fcft.", "I reviewed the account, the right and the change."), FALSE),
          shiny::tags$div(class = "del-actions", shiny::actionButton(ns("staff_apply"), tr(l, "Rechte\u00e4nderung anwenden", "Apply change of rights")))
        ),
        shiny::tags$h3(tr(l, "Panel", "Panel")),
        shiny::tags$p(tr(l, "Das Panel erscheint nur mit Studienpseudonymen. Eine ge\u00e4nderte Interessengruppe gilt f\u00fcr k\u00fcnftig vorbereitete Runden; fr\u00fchere Runden behalten ihre Zuordnung.", "The panel appears by study pseudonym only. A changed stakeholder group applies to rounds prepared in future; earlier rounds keep their assignment.")),
        shiny::uiOutput(ns("panel")),
        shiny::tags$details(
          shiny::tags$summary(tr(l, "Interessengruppe \u00e4ndern", "Change a stakeholder group")),
          shiny::selectInput(ns("group_panelist"), tr(l, "Pseudonym", "Pseudonym"), pseudonyms, selected = field("group_panelist", ""), width = "100%"),
          shiny::selectInput(ns("group_code"), tr(l, "Neue Interessengruppe", "New stakeholder group"), c(stats::setNames("", tr(l, "Gruppe w\u00e4hlen", "Choose a group")), stats::setNames(groups, humanize_code(groups))), selected = field("group_code", "")),
          shiny::textAreaInput(ns("group_reason"), tr(l, "Begr\u00fcndung der Gruppen\u00e4nderung", "Rationale for the group change"), value = field("group_reason"), width = "100%"),
          shiny::checkboxInput(ns("group_confirm"), tr(l, "Ich habe Pseudonym und neue Gruppe gepr\u00fcft.", "I reviewed the pseudonym and the new group."), FALSE),
          shiny::tags$div(class = "del-actions", shiny::actionButton(ns("group_apply"), tr(l, "Interessengruppe \u00e4ndern", "Change stakeholder group")))
        ),
        status_ui(ns("status"))
      )
      form_study <<- shiny::isolate(study())
      ui
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    output$staff_change <- shiny::renderText(staff_change_text(input$staff_account, input$staff_issuer, input$staff_subject, input$staff_capability, input$staff_action, staff(), lang()))
    output$consents <- shiny::renderTable({
      x <- setup()
      shiny::req(x)
      versions <- x$consent_versions
      if (!nrow(versions)) {
        return(NULL)
      }
      out <- data.frame(seq_len(nrow(versions)), locale_name(versions$locale), versions$content, stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("Fassung", "Sprache", "Text"), c("Version", "Language", "Text"))
      out
    })
    output$staff <- shiny::renderTable({
      x <- staff()
      shiny::req(nrow(x) > 0)
      rights <- function(v) {
        vapply(strsplit(ifelse(is.na(v), "", v), ", ", fixed = TRUE), function(z) {
          z <- z[nzchar(z)]
          if (length(z)) paste(staff_capability_label(z, lang()), collapse = "; ") else no_value
        }, character(1))
      }
      out <- data.frame(x$subject, x$issuer, rights(x$granted), rights(x$revoked), ifelse(x$active, tr(lang(), "Aktiv", "Active"), tr(lang(), "Gesperrt", "Disabled")), stringsAsFactors = FALSE)
      names(out) <- tr(lang(), c("Kontokennung", "Identit\u00e4tsanbieter", "Erteilte Rechte", "Entzogene Rechte", "Kontostatus"), c("Account identifier", "Identity provider", "Granted rights", "Revoked rights", "Account status"))
      out
    })
    output$panel <- shiny::renderUI({
      x <- panel()
      shiny::req(nrow(x) > 0)
      l <- lang()
      state <- ifelse(x$withdrawn, tr(l, "Teilnahme beendet", "Participation ended"), ifelse(x$active, tr(l, "Aktiv", "Active"), tr(l, "Inaktiv", "Inactive")))
      rows <- lapply(seq_len(nrow(x)), function(i) list(ref_tag(x$panelist_id[i]), humanize_code(x$group_code[i]), state[i], x$rounds_enrolled[i], x$rounds_submitted[i]))
      markup_table(tr(l, c("Pseudonym", "Interessengruppe", "Teilnahme", "Runden aufgenommen", "Runden abgegeben"), c("Pseudonym", "Stakeholder group", "Participation", "Rounds enrolled", "Rounds submitted")), rows)
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
      shiny::req(allowed(), input$staff_capability, input$staff_action)
      account <- if (is.null(input$staff_account)) "" else input$staff_account
      if (!nzchar(account)) {
        status(tr(lang(), "Zuerst ein Konto w\u00e4hlen.", "Choose an account first."))
        return()
      }
      issuer <- if (is.null(input$staff_issuer)) "" else trimws(input$staff_issuer)
      subject <- if (is.null(input$staff_subject)) "" else trimws(input$staff_subject)
      if (identical(account, "new") && (!nzchar(issuer) || !nzchar(subject))) {
        status(tr(lang(), "Identit\u00e4tsanbieter und Kontokennung des weiteren Kontos angeben.", "Enter the identity provider and the account identifier of the other account."))
        return()
      }
      if (!required(input$staff_reason, input$staff_confirm)) {
        return()
      }
      reason <- trimws(input$staff_reason)
      name <- if (identical(account, "new")) subject else as.character(staff()$subject[match(account, staff()$principal_id)])
      if (identical(account, "new")) account <- call("register_staff_account", study(), issuer, subject, reason, command_id())$id
      call("set_capability", study(), account, input$staff_capability, identical(input$staff_action, "grant"), command_id(), reason = reason)
      touch()
      shiny::updateCheckboxInput(session, "staff_confirm", value = FALSE)
      status(paste(tr(lang(), "Rechte\u00e4nderung best\u00e4tigt. Konto:", "Change of rights confirmed. Account:"), name))
      # The actor may just have given up the right to see this section.
      allowed("manage" %in% call("get_capabilities", study()))
      if (allowed()) refresh()
    }))
    shiny::observeEvent(input$group_apply, attempt(function() {
      shiny::req(allowed())
      member <- if (is.null(input$group_panelist)) "" else input$group_panelist
      group <- if (is.null(input$group_code)) "" else input$group_code
      if (!nzchar(member) || !nzchar(group)) {
        status(tr(lang(), "Zuerst ein Pseudonym und eine neue Gruppe w\u00e4hlen.", "Choose a pseudonym and a new group first."))
        return()
      }
      if (identical(panel()$group_code[match(member, panel()$panelist_id)], group)) {
        status(tr(lang(), "Dieses Panelmitglied ist bereits in dieser Gruppe.", "This panel member is already in that group."))
        return()
      }
      if (!required(input$group_reason, input$group_confirm)) {
        return()
      }
      call("set_panel_group", study(), member, group, trimws(input$group_reason), command_id())
      shiny::updateCheckboxInput(session, "group_confirm", value = FALSE)
      refresh()
      status(tr(lang(), "Interessengruppe ge\u00e4ndert. Fr\u00fchere Runden bleiben unver\u00e4ndert.", "Stakeholder group changed. Earlier rounds are unchanged."))
    }))
    list(allowed = allowed, staff = staff, panel = panel)
  })
}
