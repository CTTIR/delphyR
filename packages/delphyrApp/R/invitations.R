invitations_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

invitations_server <- function(id, study, lang, call, services, default_issuer = "") {
  shiny::moduleServer(id, function(input, output, session) {
    field <- function(name, default = "") {
      value <- shiny::isolate(input[[name]])
      if (is.null(value)) default else value
    }
    allowed <- shiny::reactiveVal(FALSE)
    drafts <- shiny::reactiveVal(data.frame())
    issued <- shiny::reactiveVal(NULL)
    status <- shiny::reactiveVal("")
    ready <- all(c("get_capabilities", "list_panel_invitations", "register_invited_account", "issue_panel_invitation", "revoke_panel_invitation") %in% names(services))
    attempt <- function(f) tryCatch(f(), error = function(e) status(safe_error(e, lang())))
    refresh <- function() drafts(call("list_panel_invitations", study()))
    shiny::observeEvent(study(), {
      allowed(FALSE)
      drafts(data.frame())
      # A hand-over code never survives a change of study.
      issued(NULL)
      if (ready) {
        attempt(function() {
          allowed("coordinate" %in% call("get_capabilities", study()))
          if (allowed()) refresh()
        })
      }
    })
    output$body <- shiny::renderUI({
      shiny::req(allowed())
      ns <- session$ns
      l <- lang()
      d <- drafts()
      open <- if (nrow(d)) d[d$state %in% c("unbound", "expired", "revoked"), , drop = FALSE] else d
      pending <- if (nrow(d)) d[d$state == "outstanding", , drop = FALSE] else d
      shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Einladungen und Kontobindung", "Invitations and account binding")),
        shiny::tags$p(class = "del-banner", tr(l, "Jede Einladung ist an genau ein verifiziertes Konto gebunden (Aussteller und Subject des Identitätsanbieters). Eine E-Mail-Adresse wählt kein Konto aus. Es wird keine E-Mail versendet.", "Each invitation is bound to exactly one verified account (identity-provider issuer and subject). An email address never selects an account. No email is sent.")),
        shiny::tableOutput(ns("drafts")),
        shiny::selectInput(ns("draft"), tr(l, "Einladungsentwurf", "Invitation draft"), if (nrow(open)) stats::setNames(open$draft_id, paste(open$external_ref, "·", open$display_name)) else character(), selected = field("draft", NULL)),
        shiny::textInput(ns("issuer"), tr(l, "Aussteller (Issuer-URL des Identitätsanbieters)", "Issuer (identity-provider issuer URL)"), value = field("issuer", default_issuer), width = "100%"),
        shiny::textInput(ns("subject"), tr(l, "Stabiles Subject des eingeladenen Kontos", "Stable subject of the invited account"), value = field("subject"), width = "100%"),
        shiny::numericInput(ns("ttl"), tr(l, "Gültigkeit in Minuten (1 bis 1440)", "Validity in minutes (1 to 1440)"), value = field("ttl", 15), min = 1, max = 1440, step = 1),
        shiny::textAreaInput(ns("reason"), tr(l, "Begründung der Kontobindung", "Account-binding rationale"), value = field("reason"), width = "100%"),
        shiny::checkboxInput(ns("confirm"), tr(l, "Ich habe geprüft, dass dieses stabile Konto zur eingeladenen Person gehört.", "I verified that this stable account belongs to the invited person."), FALSE),
        shiny::actionButton(ns("issue"), tr(l, "Konto registrieren und Einladung ausstellen", "Register account and issue invitation"), class = "btn-primary"),
        shiny::uiOutput(ns("issued")),
        shiny::tags$details(
          shiny::tags$summary(tr(l, "Ausstehende Einladung widerrufen", "Revoke an outstanding invitation")),
          shiny::selectInput(ns("outstanding"), tr(l, "Ausstehende Einladung", "Outstanding invitation"), if (nrow(pending)) stats::setNames(pending$invitation_id, paste(pending$external_ref, "·", pending$display_name)) else character(), selected = field("outstanding", NULL)),
          shiny::textAreaInput(ns("revoke_reason"), tr(l, "Widerrufsbegründung", "Revocation rationale"), value = field("revoke_reason"), width = "100%"),
          shiny::checkboxInput(ns("revoke_confirm"), tr(l, "Ich möchte diese Einladung widerrufen.", "I want to revoke this invitation."), FALSE),
          shiny::actionButton(ns("revoke"), tr(l, "Einladung widerrufen", "Revoke invitation"), class = "btn-outline-danger")
        ),
        shiny::actionButton(ns("refresh"), tr(l, "Einladungsstand aktualisieren", "Refresh invitation states")),
        status_ui(ns("status"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    output$drafts <- shiny::renderTable(
      {
        d <- drafts()
        if (!nrow(d)) {
          return(NULL)
        }
        x <- data.frame(d$external_ref, d$display_name, d$stakeholder_group, invitation_state_label(d$state, lang()), ifelse(is.na(d$expires_at) | d$state != "outstanding", "", d$expires_at), stringsAsFactors = FALSE)
        names(x) <- tr(lang(), c("Quellenreferenz", "Anzeigename", "Interessengruppe", "Einladungsstatus", "Gültig bis (UTC)"), c("Source reference", "Display name", "Stakeholder group", "Invitation state", "Valid until (UTC)"))
        x
      },
      striped = TRUE
    )
    shiny::observeEvent(input$issue, attempt(function() {
      shiny::req(allowed(), input$draft)
      issued(NULL)
      reason <- if (is.null(input$reason)) "" else trimws(input$reason)
      ttl <- suppressWarnings(as.numeric(input$ttl))
      if (!isTRUE(input$confirm) || !nzchar(reason)) {
        status(tr(lang(), "Begründung und Bestätigung sind erforderlich.", "A reason and confirmation are required."))
        return()
      }
      if (length(ttl) != 1L || is.na(ttl) || ttl != floor(ttl) || ttl < 1 || ttl > 1440) stop("Invalid validity")
      draft <- input$draft
      target <- study()
      token <- delphyr::new_invitation_token()
      account <- call("register_invited_account", target, trimws(input$issuer), trimws(input$subject), reason, command_id())
      invitation <- call("issue_panel_invitation", target, draft, account$id, token, ttl * 60, reason, command_id())
      issued(list(code = as.character(delphyr::invitation_code(target, invitation$id, token)), expires_at = invitation$expires_at))
      shiny::updateCheckboxInput(session, "confirm", value = FALSE)
      shiny::updateTextInput(session, "subject", value = "")
      refresh()
      status(tr(lang(), "Einladung ausgestellt. Der Übergabecode wird nur jetzt angezeigt.", "Invitation issued. The hand-over code is shown only now."))
    }))
    output$issued <- shiny::renderUI({
      x <- issued()
      shiny::req(x)
      shiny::tags$div(
        class = "del-handover",
        shiny::tags$h3(tr(lang(), "Übergabecode", "Hand-over code")),
        shiny::tags$p(tr(lang(), "Geben Sie diesen Code über einen genehmigten privaten Kanal weiter. Er wird nicht gespeichert und kann nicht erneut angezeigt werden.", "Pass this code on through an approved private channel. It is not stored and cannot be displayed again.")),
        shiny::tags$textarea(id = session$ns("code"), class = "form-control del-code", readonly = "readonly", rows = 3, `aria-label` = tr(lang(), "Übergabecode", "Hand-over code"), x$code),
        shiny::tags$p(paste(tr(lang(), "Gültig bis (UTC):", "Valid until (UTC):"), x$expires_at)),
        shiny::actionButton(session$ns("hide"), tr(lang(), "Code ausblenden", "Hide code"))
      )
    })
    shiny::observeEvent(input$hide, issued(NULL))
    shiny::observeEvent(input$revoke, attempt(function() {
      shiny::req(allowed(), input$outstanding)
      reason <- if (is.null(input$revoke_reason)) "" else trimws(input$revoke_reason)
      if (!isTRUE(input$revoke_confirm) || !nzchar(reason)) {
        status(tr(lang(), "Begründung und Bestätigung sind erforderlich.", "A reason and confirmation are required."))
        return()
      }
      call("revoke_panel_invitation", study(), input$outstanding, reason, command_id())
      issued(NULL)
      shiny::updateCheckboxInput(session, "revoke_confirm", value = FALSE)
      refresh()
      status(tr(lang(), "Einladung widerrufen.", "Invitation revoked."))
    }))
    shiny::observeEvent(input$refresh, attempt(function() {
      shiny::req(allowed())
      refresh()
    }))
  })
}

invitation_state_label <- function(state, lang) {
  labels <- tr(
    lang, c(unbound = "Noch nicht ausgestellt", outstanding = "Annahme ausstehend", expired = "Abgelaufen", revoked = "Widerrufen", accepted = "Angenommen"),
    c(unbound = "Not yet issued", outstanding = "Awaiting acceptance", expired = "Expired", revoked = "Revoked", accepted = "Accepted")
  )
  unname(ifelse(state %in% names(labels), labels[state], state))
}

invitation_accept_ui <- function(id) shiny::uiOutput(shiny::NS(id)("body"))

# Acceptance is offered only to sessions whose identity came from the verified
# gateway. Preview is read-only; joining requires a separate confirmed action.
invitation_accept_server <- function(id, lang, call, services, verified, on_accepted = function(study_id) NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ready <- isTRUE(verified) && all(c("preview_panel_invitation", "accept_panel_invitation") %in% names(services))
    previewed <- shiny::reactiveVal(NULL)
    receipt <- shiny::reactiveVal(NULL)
    status <- shiny::reactiveVal("")
    unavailable <- function() status(tr(lang(), "Diese Einladung ist für Ihr Konto nicht verfügbar. Sie kann abgelaufen, widerrufen, bereits verwendet oder für ein anderes Konto ausgestellt sein. Wenden Sie sich an die Studienleitung.", "This invitation is not available for your account. It may be expired, revoked, already used or issued for another account. Contact the study team."))
    output$body <- shiny::renderUI({
      shiny::req(ready)
      ns <- session$ns
      l <- lang()
      shiny::tags$section(
        class = "del-sheet",
        shiny::tags$h2(tr(l, "Einladung annehmen", "Accept an invitation")),
        shiny::tags$p(tr(l, "Geben Sie den Übergabecode ein, den Sie von der Studienkoordination erhalten haben. Die Prüfung ändert nichts. Erst Ihre ausdrückliche Bestätigung nimmt Sie in das Panel auf; Einwilligung und Antworten bleiben eigene Schritte.", "Enter the hand-over code you received from the study coordinators. Checking changes nothing. Only your explicit confirmation adds you to the panel; consent and responses remain separate steps.")),
        shiny::passwordInput(ns("code"), tr(l, "Übergabecode", "Hand-over code"), value = shiny::isolate(if (is.null(input$code)) "" else input$code), width = "100%"),
        shiny::actionButton(ns("check"), tr(l, "Einladung prüfen", "Check invitation")),
        shiny::uiOutput(ns("preview")),
        status_ui(ns("status"))
      )
    })
    shiny::outputOptions(output, "body", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    # A code in the URL fragment is never sent to the server by the browser's
    # page request, so it does not reach proxy access logs.
    if (ready) {
      shiny::observeEvent(session$clientData$url_hash,
        {
          hash <- session$clientData$url_hash
          if (is.character(hash) && length(hash) == 1L && startsWith(hash, "#invitation=")) {
            shiny::updateTextInput(session, "code", value = substring(hash, nchar("#invitation=") + 1L))
            session$sendCustomMessage("delphyr-clear-hash", TRUE)
          }
        },
        once = TRUE
      )
    }
    shiny::observeEvent(input$code, {
      previewed(NULL)
    })
    shiny::observeEvent(input$check, {
      shiny::req(ready)
      previewed(NULL)
      receipt(NULL)
      tryCatch(
        {
          x <- delphyr::parse_invitation_code(input$code)
          p <- call("preview_panel_invitation", x$study_id, x$invitation_id, x$token)
          # One idempotency key per previewed invitation makes a lost reply retryable.
          previewed(list(code = x, preview = p, key = command_id()))
          status(tr(lang(), "Einladung geprüft. Noch keine Teilnahme angelegt.", "Invitation checked. No participation has been created yet."))
        },
        error = function(e) unavailable()
      )
    })
    output$preview <- shiny::renderUI({
      r <- receipt()
      if (!is.null(r)) {
        return(shiny::tags$p(paste(tr(lang(), "Einladung angenommen. Beleg:", "Invitation accepted. Receipt:"), r$id)))
      }
      x <- previewed()
      shiny::req(x)
      ns <- session$ns
      shiny::tagList(
        shiny::tags$h3(x$preview$study_title),
        shiny::tags$p(paste(tr(lang(), "Gültig bis (UTC):", "Valid until (UTC):"), x$preview$expires_at)),
        shiny::checkboxInput(ns("confirm"), tr(lang(), "Ich möchte mit meinem angemeldeten Konto dem Panel dieser Studie beitreten.", "I want to join this study's panel with my signed-in account."), FALSE),
        shiny::actionButton(ns("accept"), tr(lang(), "Einladung verbindlich annehmen", "Accept invitation"), class = "btn-primary")
      )
    })
    shiny::observeEvent(input$accept, {
      x <- previewed()
      shiny::req(ready, x)
      if (!isTRUE(input$confirm)) {
        status(tr(lang(), "Bitte die Annahme ausdrücklich bestätigen.", "Explicitly confirm acceptance first."))
        return()
      }
      tryCatch(
        {
          result <- call("accept_panel_invitation", x$code$study_id, x$code$invitation_id, x$code$token, TRUE, x$key)
          receipt(result)
          previewed(NULL)
          shiny::updateTextInput(session, "code", value = "")
          status(tr(lang(), "Sie sind dem Panel beigetreten. Wählen Sie die Studie aus, um fortzufahren.", "You joined the panel. Select the study to continue."))
          on_accepted(x$code$study_id)
        },
        error = function(e) unavailable()
      )
    })
    list(receipt = receipt, previewed = previewed)
  })
}
