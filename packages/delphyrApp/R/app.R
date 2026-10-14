#' Build a synthetic study application with a trusted server identity
#'
#' The hosting application must resolve the actor on the server. Never derive
#' the actor from an input, URL parameter or a browser-supplied role. Responses
#' are saved automatically after a short pause; only a committed revision is
#' shown as saved. Production authentication, external mail and deployment
#' qualification are outside this interface's acceptance scope.
#'
#' @param repo A connected delphyr repository; lifetime is managed by the caller.
#' @param actor Trusted actor supplied by server-side session setup. An actor
#'   made by delphyr::demo_actor() is made anew for every session, for the same
#'   synthetic account, so that a demonstration outlives the actor's hour.
#' @param actor_factory Optional trusted function(session, repo) resolving each
#'   session identity independently. Mutually exclusive with actor.
#' @param repo_factory Optional function creating a repository for each session;
#'   its DBI connection is closed when the session ends.
#' @param language Initial interface language: en (default), fr or de.
#' @param services Named list of service functions, each accepting repo and actor
#'   as their first two arguments. NULL uses exported delphyr services.
#' @param autosave_ms Pause in milliseconds after which a settled, complete
#'   response is saved automatically. 0 leaves only the explicit save button.
#' @param block_fields Largest number of response fields shown at once. A
#'   longer round is presented in blocks; the fields of one item stay together.
#' @param sign_out_url Address of the gateway that ends the sign-in, as a path
#'   on this host or an http(s) address. NULL (default) shows no sign-out link.
#'   Signing out ends every session of the account in this process and leaves
#'   the page; ending the session of the gateway and the identity provider is
#'   the task of that address.
#' @return A shiny.appobj, runnable with shiny::runApp().
#' @export
#' @examples
#' if (interactive() && FALSE) {
#'   # Resolve repo and actor on the server before constructing the application.
#'   shiny::runApp(run_app(repo, actor))
#' }
run_app <- function(repo = NULL, actor = NULL, language = c("en", "fr", "de"), services = NULL,
                    actor_factory = NULL, repo_factory = NULL, autosave_ms = 1500, block_fields = 10L, sign_out_url = NULL) {
  language <- match.arg(language)
  if (!is.null(sign_out_url) && !(is.character(sign_out_url) && length(sign_out_url) == 1L && !is.na(sign_out_url) && nchar(sign_out_url, type = "bytes") <= 2000L && grepl("^(/|https?://)[^[:space:][:cntrl:]\"'<>]*$", sign_out_url) && !startsWith(sign_out_url, "//"))) stop("Invalid sign-out address.", call. = FALSE)
  if (!is.numeric(autosave_ms) || length(autosave_ms) != 1L || is.na(autosave_ms) || autosave_ms < 0 || autosave_ms > 60000) stop("Invalid autosave delay.", call. = FALSE)
  if (!is.numeric(block_fields) || length(block_fields) != 1L || is.na(block_fields) || block_fields < 1 || block_fields > 200 || block_fields != floor(block_fields)) stop("Invalid block size.", call. = FALSE)
  if (is.null(actor_factory)) {
    if (is.null(actor) || !is.list(actor)) stop("A trusted server actor is required.", call. = FALSE)
  } else if (!is.function(actor_factory) || !is.null(actor)) {
    stop("Use one trusted server identity factory or one fixed demo actor.", call. = FALSE)
  }
  # A demonstration identity lives for one hour at most. Every session of a
  # demonstration receives a new one for the same synthetic account, as every
  # page load behind a gateway passes the gateway again; demo_actor() checks
  # the repository and the account each time.
  if (is.null(actor_factory) && demo_identity(actor)) {
    principal <- actor$principal_id
    actor_factory <- function(session, repo) delphyr::demo_actor(repo, principal)
    actor <- NULL
  }
  if (!is.null(repo_factory) && !is.function(repo_factory)) stop("Invalid repository factory.", call. = FALSE)
  if (is.null(services)) {
    n <- c(
      "list_studies", "list_enrollments", "get_questionnaire", "record_consent",
      "save_response", "submit_round", "list_rounds", "transition_round", "get_capabilities", "freeze_round", "request_analysis", "get_operation", "get_analysis",
      "create_feedback", "get_feedback_candidate", "release_feedback", "assign_feedback", "request_export",
      "download_artifact", "get_study_setup", "prepare_round", "get_feedback", "complete_study",
      "get_qualitative_provenance", "list_qualitative_reviews", "record_qualitative_source",
      "redact_qualitative_source", "release_qualitative_edit", "create_qualitative_theme",
      "code_qualitative_source", "link_item_source", "record_item_lineage",
      "list_campaign_rounds", "list_campaign_enrollments", "prepare_campaign",
      "preview_campaign", "release_campaign", "cancel_campaign", "list_protocol_versions", "amend_protocol", "withdraw_participation", "preview_panel_import", "import_panel", "get_panel_import_receipt",
      "list_panel_invitations", "register_invited_account", "issue_panel_invitation", "revoke_panel_invitation",
      "preview_panel_invitation", "accept_panel_invitation", "get_round_instrument", "get_round_readiness", "enroll_panel",
      "list_audit_events", "get_study_documentation", "record_study_documentation", "record_item_comparability", "get_item_comparability",
      "request_study_export", "write_participant_feedback", "get_account_rights", "create_study", "publish_consent", "list_study_staff",
      "register_staff_account", "set_capability", "list_panel", "set_panel_group", "record_item_decision", "list_item_decisions",
      "list_contribution_rounds", "import_round_contributions", "list_released_edits", "list_released_feedback", "release_feedback_correction",
      "list_uncertain_deliveries", "resolve_delivery", "get_operations_status", "change_round_deadline"
    )
    services <- stats::setNames(lapply(n, function(x) getExportedValue("delphyr", x)), n)
  }
  required <- c("list_studies", "list_enrollments", "get_questionnaire", "record_consent", "save_response", "submit_round")
  if (!all(required %in% names(services)) || !all(vapply(services, is.function, logical(1)))) stop("Incomplete service adapter.", call. = FALSE)
  shiny::addResourcePath("delphyr-brand", system.file("www", package = "delphyrApp"))
  open_sessions <- session_registry()
  ui <- shiny::fluidPage(
    theme = bslib::bs_theme(version = 5, bg = "#eceff2", fg = "#22303c", primary = "#0e6e78", success = "#0e6e78", danger = "#b3372b", base_font = "system-ui"),
    shiny::tags$head(
      shiny::tags$script(shiny::HTML(page_script(language))), shiny::tags$style(shiny::HTML(app_css())),
      shiny::tags$link(rel = "icon", type = "image/png", href = "delphyr-brand/delphyR-mark.png"),
      shiny::tags$link(rel = "icon", type = "image/svg+xml", href = "delphyr-brand/delphyR-mark.svg")
    ),
    shiny::tags$div(
      class = "del-wrap",
      shiny::tags$header(
        class = "del-header", shiny::tags$div(
          class = "del-brand",
          shiny::tags$img(class = "del-logo", src = "delphyr-brand/delphyR-mark.svg", alt = "", width = 64, height = 72),
          shiny::tags$h1("delphyR")
        ),
        shiny::tags$div(
          class = "del-account",
          shiny::selectInput("language", tr(language, "Sprache", "Language"), c("English" = "en", "Fran\u00e7ais" = "fr", "Deutsch" = "de"), selected = language, width = "190px", selectize = FALSE),
          # Nothing else stands beside the language unless the sign-in can end here.
          if (!is.null(sign_out_url)) shiny::uiOutput("account", inline = TRUE)
        )
      ),
      shiny::uiOutput("banner"),
      closed_notices(language, sign_out_url),
      shiny::tags$main(
        id = "main", invitation_accept_ui("invitation_accept"),
        shiny::tags$section(
          class = "del-sheet",
          shiny::uiOutput("intro"),
          # The list of studies appears once there is a study to choose.
          shiny::tags$div(hidden = "hidden", shiny::textOutput("has_studies")),
          shiny::conditionalPanel("output.has_studies === 'yes'", shiny::selectInput("study", tr(language, "Studie", "Study"), character(), width = "100%", selectize = FALSE)),
          status_ui("status")
        ),
        study_create_ui("study_create"),
        shiny::uiOutput("navigation"),
        shiny::tags$div(id = "section-panel", panel_ui("panel")),
        shiny::tags$div(id = "section-setup", study_setup_ui("study_setup")),
        shiny::tags$div(id = "section-protocols", protocols_ui("protocols")),
        shiny::tags$div(id = "section-management", management_ui("management")),
        shiny::tags$div(id = "section-editorial", editorial_ui("editorial")),
        shiny::tags$div(id = "section-panel-import", panel_import_ui("panel_import")),
        shiny::tags$div(id = "section-invitations", invitations_ui("invitations")),
        shiny::tags$div(id = "section-communications", communications_ui("communications")),
        shiny::tags$div(id = "section-documentation", documentation_ui("documentation")),
        shiny::tags$div(id = "section-exports", exports_ui("exports")),
        shiny::tags$div(id = "section-audit", audit_ui("audit"))
      ),
      shiny::tags$footer(class = "del-note", "CTTIR \u00b7 delphyR \u00b7 0.0.1")
    )
  )
  server <- function(input, output, session) {
    # The repository and the identity of this session. If either cannot be
    # had, the session ends before any service is reached, and the page says
    # whether the account was refused or the service could not start it.
    session_repo <- if (is.null(repo_factory)) repo else tryCatch(delphyr::log_operation("session_repository", repo_factory, component = "app"), error = function(e) e)
    if (!is.null(repo_factory) && !inherits(session_repo, "error") && inherits(session_repo$con, "DBIConnection")) {
      session$onSessionEnded(function() DBI::dbDisconnect(session_repo$con))
    }
    session_actor <- if (inherits(session_repo, "error")) {
      session_repo
    } else if (is.null(actor_factory)) {
      actor
    } else {
      # A refused identity is recorded by its class only, never by its headers.
      tryCatch(delphyr::log_operation("session_identity", function() actor_factory(session, session_repo), component = "app"), error = function(e) e)
    }
    refusal <- if (inherits(session_repo, "error")) session_unavailable(session_repo) else session_refusal(session_actor)
    if (!is.null(refusal)) {
      # No account is created on login; the page explains the closed session.
      session$sendCustomMessage("delphyr-closed", refusal)
      session$close()
      return(invisible(NULL))
    }
    # Every service call leaves one entry in the technical log; a refusal or
    # failure carries its correlation ID into the message shown to the person.
    # Arguments are evaluated first, so that a pending input is not a failure.
    call <- function(name, ...) {
      arguments <- list(...)
      tryCatch(
        delphyr::log_operation(name, function() do.call(services[[name]], c(list(session_repo, session_actor), arguments)), component = "app"),
        error = function(e) {
          if (inherits(e, "delphyr_error")) stop(e)
          # The message of any other condition may quote a value. Only its
          # reference leaves the service boundary, also when nothing catches it.
          stop(structure(list(message = "DEL_STORAGE service", call = NULL, code = "DEL_STORAGE", path = "service", correlation_id = e$correlation_id), class = c("DEL_STORAGE", "delphyr_error", "error", "condition")))
        }
      )
    }
    lang <- shiny::reactive(if (is.null(input$language)) language else input$language)
    shiny::observeEvent(lang(), {
      session$sendCustomMessage("delphyr-language", lang())
      shiny::updateSelectInput(session, "language", label = tr(lang(), "Sprache", "Language"))
      shiny::updateSelectInput(session, "study", label = tr(lang(), "Studie", "Study"))
    })
    capabilities <- shiny::reactiveVal(character())
    studies <- shiny::reactiveVal(NULL)
    # Sections of one session share a signal: a confirmed change in one
    # section lets the others read their lists again instead of showing
    # stale rounds, drafts or rights. Services check every action regardless.
    changed <- shiny::reactiveVal(0L)
    touch <- function() changed(shiny::isolate(changed()) + 1L)
    # Every confirmed change made through a staff section is that signal,
    # whether or not the section sends it itself; a read is no change. The
    # changes made outside Setup are also counted on their own (setup_study).
    changed_outside_setup <- shiny::reactiveVal(0L)
    signalling <- function(section) {
      function(name, ...) {
        result <- call(name, ...)
        if (!grepl("^(get|list|preview|download)_", name)) {
          touch()
          if (!identical(section, "study_setup")) changed_outside_setup(shiny::isolate(changed_outside_setup()) + 1L)
        }
        result
      }
    }
    status <- shiny::reactiveVal("")
    output$banner <- shiny::renderUI(shiny::tags$aside(class = "del-banner", tr(
      lang(),
      "Synthetische Entwicklungsumgebung. Keine realen Teilnehmendendaten eingeben. E-Mails werden nicht versendet.",
      "Synthetic development environment. Do not enter real participant data. No email is sent."
    )))
    output$intro <- shiny::renderUI({
      l <- lang()
      s <- studies()
      shiny::tagList(
        shiny::tags$h2(tr(l, "Ihre Studien", "Your studies")),
        if (length(s) && nrow(s)) shiny::tags$p(workspace_intro(capabilities(), l))
      )
    })
    output$has_studies <- shiny::renderText(if (length(studies()) && nrow(studies())) "yes" else "no")
    shiny::outputOptions(output, "has_studies", suspendWhenHidden = FALSE)
    output$status <- shiny::renderText(localize_status(status(), lang()))
    shiny::outputOptions(output, "status", suspendWhenHidden = FALSE)
    # Signing out ends the other sessions of the same account in this process,
    # for example a second tab, and then leaves the page, which ends this
    # session and closes its database connection. The address ends the sign-in
    # at the gateway. Without a connection the link is followed directly.
    output$account <- shiny::renderUI(if (!is.null(sign_out_url)) shiny::tags$a(id = "sign_out", class = "btn btn-default del-signout", href = sign_out_url, tr(lang(), "Abmelden", "Sign out")))
    if (!is.null(sign_out_url)) {
      account <- paste(session_actor$principal_id, collapse = " ")
      own <- open_sessions$add(account, session)
      session$onSessionEnded(function() open_sessions$remove(account, own))
      shiny::observeEvent(input$sign_out, {
        for (other in open_sessions$others(account, own)) try(other$close(), silent = TRUE)
        session$sendCustomMessage("delphyr-leave", sign_out_url)
      })
    }
    verified <- is.character(session_actor$issuer) && length(session_actor$issuer) == 1L && grepl("^https?://", session_actor$issuer)
    accepting <- verified && all(c("preview_panel_invitation", "accept_panel_invitation") %in% names(services))
    # The account's right to create a study, as the section that creates one read it.
    can_create <- function() {
      allowed <- creation$allowed
      is.function(allowed) && isTRUE(shiny::isolate(allowed()))
    }
    load_studies <- function(selected = NULL) {
      tryCatch(
        {
          s <- call("list_studies")
          studies(s)
          shiny::updateSelectInput(session, "study", choices = stats::setNames(s$id, s$title), selected = if (length(selected) == 1L && selected %in% s$id) selected else NULL)
          status(if (!nrow(s)) empty_state(lang(), can_create(), accepting) else "")
        },
        error = function(e) status(safe_error(e, lang()))
      )
    }
    shiny::observeEvent(TRUE, load_studies(), once = TRUE)
    study <- shiny::reactive({
      shiny::req(input$study)
      input$study
    })
    # A staff section reads its rights and lists when a study is selected.
    # When this session's own rights change, a section whose rights changed
    # reads the study again as on a new selection; the others keep what they
    # show, such as a hand-over code, a requested operation or a status.
    # Exports follow the change signal themselves, and the participant section
    # keeps answers that are not saved yet. A section that starts to read
    # another right needs it listed here.
    section_rights <- list(
      management = c("manage", "analyse", "export"), editorial = c("edit", "manage"), communications = "coordinate",
      protocols = "manage", panel_import = c("coordinate", "manage"), study_setup = "manage",
      documentation = "manage", audit = c("audit", "manage"), invitations = "coordinate"
    )
    reselected <- lapply(section_rights, function(x) shiny::reactiveVal(0L))
    section_study <- lapply(stats::setNames(nm = names(section_rights)), function(section) {
      shiny::reactive({
        reselected[[section]]()
        study()
      })
    })
    # Setup shows the team, the panel and the current protocol's languages
    # and groups, which other sections change as well. A confirmed change
    # made elsewhere counts as a new selection for Setup; after a change of
    # its own Setup reads them itself and keeps its confirmation.
    setup_study <- shiny::reactive({
      changed_outside_setup()
      section_study$study_setup()
    })
    shiny::observeEvent(study(), {
      capabilities(character())
      if ("get_capabilities" %in% names(services)) {
        tryCatch(capabilities(call("get_capabilities", study())), error = function(e) status(safe_error(e, lang())))
      }
    })
    shiny::observeEvent(changed(),
      {
        if ("get_capabilities" %in% names(services) && length(input$study) == 1L && nzchar(input$study)) {
          before <- capabilities()
          tryCatch(
            {
              now <- call("get_capabilities", input$study)
              capabilities(now)
              for (section in names(section_rights)) {
                rights <- section_rights[[section]]
                if (!setequal(intersect(before, rights), intersect(now, rights))) reselected[[section]](reselected[[section]]() + 1L)
              }
            },
            error = function(e) capabilities(character())
          )
        }
      },
      ignoreInit = TRUE
    )
    output$navigation <- shiny::renderUI({
      links <- workspace_sections(capabilities(), lang())
      # A single section needs no navigation: its own heading follows.
      if (nrow(links) < 2L) {
        return(NULL)
      }
      shiny::tags$nav(
        class = "del-nav", `aria-label` = tr(lang(), "Bereiche dieser Studie", "Study sections"),
        shiny::tags$ul(lapply(seq_len(nrow(links)), function(i) shiny::tags$li(shiny::tags$a(href = paste0("#", links$id[i]), links$label[i]))))
      )
    })
    panel_server("panel", study, lang, call, feedback_available = "get_feedback" %in% names(services), capabilities_available = "get_capabilities" %in% names(services), withdrawal_available = "withdraw_participation" %in% names(services), autosave_ms = autosave_ms, feedback_download_available = "write_participant_feedback" %in% names(services), block_fields = as.integer(block_fields))
    management_server("management", section_study$management, lang, signalling("management"), services, changed = changed, touch = touch)
    editorial_server("editorial", section_study$editorial, lang, signalling("editorial"), services, changed = changed)
    communications_server("communications", section_study$communications, lang, signalling("communications"), services, changed = changed)
    protocols_server("protocols", section_study$protocols, lang, signalling("protocols"), services)
    panel_import_server("panel_import", section_study$panel_import, lang, signalling("panel_import"), services, touch = touch)
    creation <- study_create_server("study_create", lang, call, services, on_created = load_studies)
    study_setup_server("study_setup", setup_study, lang, signalling("study_setup"), services, touch = touch)
    documentation_server("documentation", section_study$documentation, lang, signalling("documentation"), services)
    exports_server("exports", study, lang, signalling("exports"), services, changed = changed)
    audit_server("audit", section_study$audit, lang, signalling("audit"), services)
    invitations_server("invitations", section_study$invitations, lang, signalling("invitations"), services, default_issuer = if (verified) session_actor$issuer else "", changed = changed)
    invitation_accept_server("invitation_accept", lang, call, services, verified, on_accepted = load_studies)
  }
  # An output that fails unexpectedly shows a generic notice, not its message.
  app <- shiny::shinyApp(ui, server, onStart = function() {
    previous <- options(shiny.sanitize.errors = TRUE)
    shiny::onStop(function() options(previous))
    register_page_assets(app)
  })
  app
}

# An actor made by delphyr::demo_actor(): a server identity with a lifetime
# but without the issuer that a sign-in through a gateway carries.
demo_identity <- function(actor) inherits(actor, "delphyr_actor") && is.null(actor$issuer) && length(actor$expires_at) == 1L

# Why a session cannot start, as told to the page; NULL when it can. An
# identity that the gateway or the register of accounts refuses is
# "refused". Any other failure, of the database, its connection or the
# identity lookup, says nothing about the account: the service is
# "unavailable", and the reference names the entry of the technical log.
session_refusal <- function(actor) {
  if (is.null(actor) || inherits(actor, c("DEL_UNAUTHORIZED", "DEL_FORBIDDEN", "DEL_NOT_FOUND"))) {
    return(list(reason = "refused"))
  }
  if (inherits(actor, "error")) {
    return(session_unavailable(actor))
  }
  NULL
}
session_unavailable <- function(e) list(reason = "unavailable", reference = error_reference(e))

# What a person without any study can do next: create one, enter the code of
# an invitation, or turn to the study team.
empty_state <- function(lang, can_create, can_accept) {
  if (can_create && can_accept) {
    tr(lang, "Noch keine berechtigte Studie. Sie k\u00f6nnen unten eine Studie anlegen oder oben den \u00dcbergabecode einer Einladung eingeben.", "No accessible study yet. You can create a study below or enter the hand-over code of an invitation above.")
  } else if (can_create) {
    tr(lang, "Noch keine berechtigte Studie. Sie k\u00f6nnen unten eine Studie anlegen.", "No accessible study yet. You can create a study below.")
  } else if (can_accept) {
    tr(lang, "Noch keine berechtigte Studie. Geben Sie oben den \u00dcbergabecode Ihrer Einladung ein oder wenden Sie sich an die Studienleitung.", "No accessible study yet. Enter the hand-over code of your invitation above, or contact the study team.")
  } else {
    tr(lang, "Noch keine berechtigte Studie. Wenden Sie sich an die Studienleitung.", "No accessible study yet. Contact the study team.")
  }
}

# The notices of a session that the server ended before accepting it. The
# session is gone, so they are part of the page, in every interface language
# with the configured one first; the page script shows the one that applies.
closed_notices <- function(language, sign_out_url = NULL) {
  order <- c(language, setdiff(c("en", "fr", "de"), language))
  notice <- function(id, content) {
    shiny::tags$div(id = id, class = "del-closed-notice", role = "alert", hidden = "hidden", lapply(order, function(l) shiny::tags$section(lang = l, content(l))))
  }
  shiny::tagList(
    notice("unregistered", function(l) {
      shiny::tagList(
        shiny::tags$h2(tr(l, "Kein Zugang zu dieser Anwendung", "No access to this application")),
        shiny::tags$p(tr(l, "Ihr Konto ist f\u00fcr diese Anwendung nicht registriert. Wenden Sie sich an die Studienkoordination.", "Your account is not registered for this application. Contact the study coordinators.")),
        if (!is.null(sign_out_url)) shiny::tags$p(shiny::tags$a(href = sign_out_url, tr(l, "Abmelden, um ein anderes Konto zu verwenden", "Sign out to use another account")))
      )
    }),
    notice("unavailable", function(l) {
      shiny::tagList(
        shiny::tags$h2(tr(l, "Die Anwendung ist gerade nicht erreichbar", "The application is not available right now")),
        shiny::tags$p(tr(l, "Es wurde nichts ge\u00e4ndert. Laden Sie die Seite in einigen Minuten neu.", "Nothing was changed. Reload the page in a few minutes.")),
        shiny::tags$p(`data-reference` = NA, hidden = "hidden", tr(l, "Wenn das Problem bleibt, nennen Sie der Studienleitung diese Referenz:", "If the problem persists, give the study team this reference:"), " ", shiny::tags$code(class = "del-reference"))
      )
    })
  )
}

# The script of the page: its language, the messages of the server, the
# sign-out link, the notice of a session the server never accepted, and the
# open state of collapsible groups across a new rendering.
page_script <- function(language) {
  sprintf("document.documentElement.lang=%s;
$(document).on('shiny:connected',function(){
Shiny.addCustomMessageHandler('delphyr-language',function(lang){window.delphyrAccepted=true;document.documentElement.lang=lang;});
Shiny.addCustomMessageHandler('delphyr-closed',function(x){delphyrClosed(x);});
Shiny.addCustomMessageHandler('delphyr-clear-hash',function(x){history.replaceState(null,'',location.pathname+location.search);});
Shiny.addCustomMessageHandler('delphyr-focus',function(id){var x=document.getElementById(id);if(x){x.scrollIntoView({block:'start'});x.focus({preventScroll:true});}});
Shiny.addCustomMessageHandler('delphyr-leave',function(url){window.location.assign(url);});
});
$(document).on('click','#sign_out',function(e){var url=this.getAttribute('href');if(window.Shiny&&Shiny.shinyapp&&Shiny.shinyapp.isConnected()){e.preventDefault();Shiny.setInputValue('sign_out',Date.now(),{priority:'event'});setTimeout(function(){window.location.assign(url);},2000);}});
/* A session the server never accepted ends with one notice and nothing else:
   a refused account, or a service that could not start the session. A close
   without word from the server is taken as the service being unavailable;
   the word may arrive after the close. */
var delphyrClosed=(function(){var reason=null;return function(x){
if(window.delphyrAccepted)return;
if(x){reason=x;}else if(!reason){reason={reason:'unavailable'};}
var refused=reason.reason==='refused';
var shown=document.getElementById(refused?'unregistered':'unavailable');
var other=document.getElementById(refused?'unavailable':'unregistered');
if(other)other.hidden=true;
if(!shown)return;
if(reason.reference){shown.querySelectorAll('[data-reference]').forEach(function(p){p.querySelector('.del-reference').textContent=reason.reference;p.hidden=false;});}
shown.hidden=false;
document.body.classList.add('del-closed');
};})();
$(document).on('shiny:disconnected',function(){delphyrClosed(null);});
(function(){var open={};function key(d){var host=d.closest('.shiny-html-output');var s=d.querySelector('summary');return (host?host.id:'')+'|'+(s?s.textContent:'');}document.addEventListener('toggle',function(e){var d=e.target;if(d&&d.tagName==='DETAILS'){open[key(d)]=d.open;}},true);function restore(node){if(!node||node.nodeType!==1)return;var list=node.tagName==='DETAILS'?[node]:node.querySelectorAll('details');Array.prototype.forEach.call(list,function(d){if(open[key(d)]&&!d.open){d.open=true;}});}document.addEventListener('DOMContentLoaded',function(){new MutationObserver(function(changes){changes.forEach(function(c){Array.prototype.forEach.call(c.addedNodes,restore);});}).observe(document.body,{childList:true,subtree:true});});})();", jsonlite::toJSON(language, auto_unbox = TRUE))
}

# The open sessions of one process by account. A gateway that sends every
# request of an account to the same process keeps them together.
session_registry <- function() {
  sessions <- new.env(parent = emptyenv())
  list(
    add = function(account, session) {
      key <- uuid::UUIDgenerate()
      assign(account, c(get0(account, envir = sessions, inherits = FALSE, ifnotfound = list()), stats::setNames(list(session), key)), envir = sessions)
      key
    },
    remove = function(account, key) {
      rest <- get0(account, envir = sessions, inherits = FALSE, ifnotfound = list())
      rest[[key]] <- NULL
      if (length(rest)) assign(account, rest, envir = sessions) else if (exists(account, envir = sessions, inherits = FALSE)) rm(list = account, envir = sessions)
      invisible(NULL)
    },
    others = function(account, key) {
      all <- get0(account, envir = sessions, inherits = FALSE, ifnotfound = list())
      unname(all[setdiff(names(all), key)])
    },
    accounts = function() length(ls(sessions, all.names = TRUE))
  )
}
# A process serves the scripts and styles of its page only after it has
# rendered that page once. Behind a gateway with several processes a page can
# come from one process and its files be asked of another that has just been
# started; rendering the page once at start makes every process answer.
register_page_assets <- function(app) {
  request <- list(REQUEST_METHOD = "GET", PATH_INFO = "/", QUERY_STRING = "")
  invisible(tryCatch(!is.null(app$httpHandler(request)), error = function(e) FALSE))
}
