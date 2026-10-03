# Scientific forms follow the suite's teal/slate palette and system typography.
app_css <- function() '
:root {--del-accent:#0e6e78;--del-accent-soft:#eef6f6;--del-warn:#b3372b;--del-warn-soft:#fbefed;--del-line:#dce3e7;}
body {color:#22303c;background:#eceff2;font-family:system-ui,-apple-system,"Segoe UI",sans-serif;}
.del-wrap {max-width:1040px;margin:auto;padding:24px 20px 60px;overflow-wrap:break-word;}
.del-header {display:flex;justify-content:space-between;align-items:center;gap:24px;flex-wrap:wrap;}
.del-brand {display:flex;align-items:center;gap:16px;}
.del-account {display:flex;align-items:flex-end;gap:16px;flex-wrap:wrap;}
.del-account .form-group {margin-bottom:0;}
.del-logo {width:72px;height:84px;object-fit:contain;}
.del-header h1 {font-size:2.1rem;font-weight:750;color:#0e6e78;margin:0;}
.del-banner {background:var(--del-warn-soft);border-left:3px solid var(--del-warn);padding:12px 16px;margin:20px 0;color:var(--del-warn);border-radius:0 8px 8px 0;}
.del-nav {background:white;border:1px solid #dce3e7;border-radius:14px;padding:8px 16px;}
.del-nav ul {list-style:none;display:flex;flex-wrap:wrap;gap:4px 20px;margin:0;padding:0;}
.del-nav a {display:inline-flex;align-items:center;min-height:44px;color:#0e6e78;font-weight:600;text-decoration:underline;text-underline-offset:3px;}
[id^="section-"] {scroll-margin-top:16px;}
.del-sheet {background:white;border:1px solid #dce3e7;border-radius:14px;padding:24px;margin:18px 0;box-shadow:0 1px 2px rgba(34,48,60,.10);}
.del-item {border-top:1px solid #dce3e7;padding:22px 0;max-width:75ch;}
.del-item h3 {line-height:1.5;}
h1,h2,h3,h4 {letter-spacing:-.01em;overflow-wrap:anywhere;}
h2 {font-size:1.5rem;} h3 {font-size:1.2rem;} h4 {font-size:1.05rem;} h3,h4 {margin-top:20px;} p {max-width:75ch;line-height:1.6;}
.btn {min-height:44px;border-radius:8px;font-weight:600;white-space:normal;}
.btn + .btn {margin-left:12px;}
.del-actions .btn + .btn,.del-blocknav .btn + .btn,.del-account .btn + .btn {margin-left:0;}
.btn + h2,.btn + h3,.btn + h4,.btn + p,.btn + .form-group,.btn + .shiny-input-container,.btn + .table {margin-top:16px;}
.btn-sm {min-height:36px;font-weight:500;}
a:focus-visible,button:focus-visible,input:focus-visible,textarea:focus-visible,select:focus-visible {outline:3px solid var(--del-accent)!important;outline-offset:3px;}
.form-control,.form-select,.selectize-input {min-height:44px;border-color:#6b7c8a;background-color:#fff;}
.form-control:disabled,.form-select:disabled,.form-control[readonly] {background-color:#eef1f4;color:#4a5865;}
.form-control::placeholder {color:#5b6b7a;font-style:italic;opacity:1;}
.checkbox label,.radio label {display:flex;gap:10px;align-items:flex-start;}
.checkbox input,.radio input {flex:none;margin-top:.3em;}
details {border:1px solid var(--del-line);border-radius:10px;padding:0 14px;margin:12px 0;background:#fff;}
details > summary {font-weight:600;padding:10px 0;min-height:44px;cursor:pointer;}
details[open] > summary {border-bottom:1px solid var(--del-line);margin-bottom:12px;}
.del-status {border-left:3px solid #9cabb7;padding:8px 12px;margin:12px 0;overflow-wrap:anywhere;}
.del-status--saved {border-color:var(--del-accent);background:var(--del-accent-soft);color:var(--del-accent);}
.del-status--attention,.shiny-output-error {border-color:var(--del-warn);color:var(--del-warn);}
.del-status--attention {background:var(--del-warn-soft);}
.del-status:has(.shiny-text-output:empty) {border:0;padding:0;margin:0;}
.del-management:has(> .shiny-html-output:first-child:empty):has(> .del-status .shiny-text-output:empty) {border:0;padding:0;margin:0;background:transparent;}
.shiny-input-container:has(input[type="checkbox"]) {width:100%;}
.del-note {color:#5b6b7a;font-size:.95rem;}
.del-actions {display:flex;gap:12px;flex-wrap:wrap;margin:16px 0;}
.del-blocknav {display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end;margin:16px 0;}
.del-blocknav .form-group {margin-bottom:0;}
.del-consent {white-space:pre-wrap;max-width:75ch;}
.del-qualitative {padding-left:1.2rem;max-width:75ch;}
.del-qualitative li {margin:6px 0;line-height:1.5;}
.del-review {border-top:1px solid var(--del-line);border-bottom:1px solid var(--del-line);padding:8px 0 16px;margin:16px 0;}
.del-review h4 {font-size:1.05rem;margin-top:18px;}
.del-ref {font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.9em;text-decoration:underline dotted;text-underline-offset:3px;cursor:help;}
.del-statement {border:1px solid var(--del-line);border-radius:12px;padding:18px 20px;margin:18px 0;max-width:75ch;background:#fff;}
.del-statement > h3:first-child {margin-top:0;}
.del-feedback {background:var(--del-accent-soft);border-left:3px solid var(--del-accent);border-radius:0 8px 8px 0;padding:10px 14px;margin:12px 0;}
.del-feedback p {margin:4px 0;}
.del-feedback blockquote {margin:8px 0 4px;padding-left:12px;border-left:2px solid #9cabb7;font-style:italic;}
.del-revision {border-left:3px solid #8a6d1d;background:#fbf6e7;border-radius:0 8px 8px 0;padding:10px 14px;margin:12px 0;}
.del-anchors {color:#4a5865;font-size:.95rem;margin:4px 0 8px;}
.del-code {font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.9rem;overflow-wrap:anywhere;resize:none;}
footer.del-note {text-align:center;font-size:.8rem;padding:12px 0;}
.table {display:block;overflow-x:auto;}
.table caption {caption-side:top;color:#22303c;font-weight:600;padding-top:0;}
.table th:first-child,.table td:first-child {position:sticky;left:0;background-color:#fff;z-index:1;}
@media(max-width:600px) {.del-wrap{padding:16px 12px}.del-sheet{padding:16px}.del-statement{padding:14px}.shiny-input-container{max-width:100%}h1{font-size:1.7rem}h2{font-size:1.35rem}.btn + .btn{margin-left:0;margin-top:8px}}
@media(prefers-reduced-motion:reduce) {*{animation:none!important;transition:none!important}}
'
status_ui <- function(id) shiny::tags$div(class = "del-status", role = "status", `aria-live` = "polite", shiny::textOutput(id))
command_id <- function() uuid::UUIDgenerate()
# The choices of a list: identifiers with their labels. An empty list stays
# empty; a label built with fixed text would otherwise have length one.
list_choices <- function(ids, labels) if (length(ids)) stats::setNames(ids, labels) else character()
# A file input shows the chosen file in a read-only text field that the
# framework leaves without a name; it takes the label of the input.
file_input <- function(id, label, ...) {
  x <- shiny::fileInput(id, label, ...)
  htmltools::tagQuery(x)$find("input.form-control")$addAttrs(`aria-labelledby` = paste0(id, "-label"))$allTags()
}
# The message never repeats what the server refused; the reference links it to
# one entry of the technical log, which holds no content either.
safe_error <- function(e, lang) {
  # An input that is not ready yet cancels the step silently; that is not a
  # failure, so nothing is shown or logged and the cancellation stays one.
  if (inherits(e, "shiny.silent.error")) stop(e)
  text <- if (inherits(e, "DEL_CONFLICT")) {
    tr(lang, "Konflikt: Bitte Seite neu laden und den gespeicherten Stand pr\u00fcfen. Ihre Eingabe ist noch sichtbar.", "Conflict: reload and review the saved version. Your input remains visible.")
  } else if (inherits(e, "DEL_ROUND_CLOSED")) {
    tr(lang, "Die Runde ist geschlossen oder die Frist abgelaufen. Speichern ist nicht m\u00f6glich.", "The round is closed or its deadline has passed. Saving is unavailable.")
  } else if (inherits(e, "DEL_UNAUTHORIZED")) {
    # The identity of a session is valid for a limited time; only a new page
    # load passes the gateway again.
    tr(lang, "Ihre Anmeldung ist abgelaufen. Bitte die Seite neu laden und erneut anmelden. Best\u00e4tigt gespeicherte Eingaben bleiben erhalten; diese Aktion wurde nicht ausgef\u00fchrt.", "Your sign-in has expired. Reload the page and sign in again. Entries confirmed as saved are kept; this action was not carried out.")
  } else {
    tr(lang, "Aktion fehlgeschlagen. Bitte Angaben, Berechtigung und Rundenstatus pr\u00fcfen. Es wurde kein Erfolg best\u00e4tigt.", "Action failed. Check your entries, permissions and round state. No success was confirmed.")
  }
  paste(text, reference_text(error_reference(e), lang))
}
# A failure outside a service call gets its own entry, so that every failure
# message quotes a reference.
error_reference <- function(e) {
  id <- if (is.list(e)) e$correlation_id else NULL
  if (is.character(id) && length(id) == 1L && grepl("^[0-9a-f]{12}$", id)) id else delphyr::log_event("interface", error = e, component = "app")
}
reference_text <- function(id, lang) paste(tr(lang, "Referenz:", "Reference:"), id)
state_label <- function(state, lang) {
  en <- c(draft = "Draft", review = "In review", approved = "Approved", open = "Open", closed = "Closed", frozen = "Frozen", analysed = "Analysed", released = "Feedback released", finalized = "Finalized", eligible = "Eligible", in_progress = "In progress", submitted = "Submitted")
  de <- c(draft = "Entwurf", review = "In Pr\u00fcfung", approved = "Freigegeben", open = "Offen", closed = "Geschlossen", frozen = "Eingefroren", analysed = "Ausgewertet", released = "Feedback freigegeben", finalized = "Abgeschlossen", eligible = "Teilnahme m\u00f6glich", in_progress = "In Bearbeitung", submitted = "Abgegeben")
  en <- c(en, pending = "Pending", running = "Running", succeeded = "Succeeded", failed = "Failed", cancelled = "Cancelled")
  de <- c(de, pending = "Ausstehend", running = "In Bearbeitung", succeeded = "Erfolgreich", failed = "Fehlgeschlagen", cancelled = "Abgebrochen")
  labels <- tr(lang, de, en)
  unname(ifelse(state %in% names(labels), labels[state], state))
}

round_display <- function(rounds, language, timezone = "UTC") {
  out <- data.frame(
    round = rounds$number,
    state = round_state_label(rounds$state, language),
    deadline = format_moment(rounds$deadline, timezone, language),
    stringsAsFactors = FALSE
  )
  names(out) <- c(tr(language, "Runde", "Round"), tr(language, "Status", "State"), tr(language, "Abgabefrist", "Deadline"))
  out
}

connection_script <- function(banner_id, workspace_id) {
  messages <- lapply(c("en", "fr", "de"), function(lang) list(
    restored = tr(lang, "Verbindung wiederhergestellt. Pr\u00fcfen Sie vor dem Fortsetzen den zuletzt gespeicherten Stand. Offene \u00c4nderungen sind nicht als gespeichert best\u00e4tigt.", "Connection restored. Review the last saved responses before continuing. Pending edits have not been confirmed saved."),
    lost = tr(lang, "Verbindung unterbrochen. \u00c4nderungen werden nicht gespeichert. Sichern Sie offene Texte vor dem Neuladen; danach sind nur best\u00e4tigte Antworten wiederhergestellt.", "Connection lost. Changes are not being saved. Keep a copy of pending text before reloading; a reload restores only confirmed responses.")
  ))
  names(messages) <- c("en", "fr", "de")
  sprintf(
    "(function(){
      var lost=false, restored=false;
      var boxId=%s, workspaceId=%s, messages=%s;
      function show(){
        var box=document.getElementById(boxId);
        if(!box || !lost) return;
        var language=document.getElementById('language');
        var lang=language && language.value || 'en';
        box.hidden=false;
        box.textContent=messages[lang][restored ? 'restored' : 'lost'];
        var workspace=document.getElementById(workspaceId);
        if(workspace) workspace.querySelectorAll('.del-status, .del-progress').forEach(function(x){x.hidden=!restored;});
      }
      $(document).on('shiny:disconnected',function(){lost=true;restored=false;show();});
      $(document).on('shiny:connected',function(){if(lost){restored=true;show();}});
      $(document).on('change','#language',show);
      window.addEventListener('offline',function(){lost=true;restored=false;show();});
    })();",
    jsonlite::toJSON(banner_id, auto_unbox = TRUE),
    jsonlite::toJSON(workspace_id, auto_unbox = TRUE),
    jsonlite::toJSON(messages, auto_unbox = TRUE)
  )
}

workspace_sections <- function(capabilities, lang) {
  has <- function(...) any(c(...) %in% capabilities)
  ids <- c("section-panel", "section-setup", "section-protocols", "section-management", "section-editorial", "section-panel-import", "section-invitations", "section-communications", "section-documentation", "section-exports", "section-audit")
  labels <- tr(
    lang, c("Meine Teilnahme", "Einrichtung", "Protokoll", "Runden und Auswertung", "Redaktion", "Panelimport", "Einladungen", "Kommunikation", "Dokumentation", "Exporte", "Verlauf"),
    c("My participation", "Setup", "Protocol", "Rounds and analysis", "Editorial review", "Panel import", "Invitations", "Communications", "Documentation", "Exports", "History")
  )
  show <- c(has("panel"), has("manage"), has("manage"), has("manage"), has("edit", "manage"), has("coordinate"), has("coordinate"), has("coordinate"), has("manage"), has("export", "analyse", "manage", "audit", "contacts_export"), has("audit", "manage"))
  data.frame(id = ids[show], label = labels[show], stringsAsFactors = FALSE)
}

workspace_intro <- function(capabilities, lang) {
  if ("manage" %in% capabilities) {
    return(tr(lang, "Verwalten Sie Protokoll, Runden und unabh\u00e4ngige Pr\u00fcfungen. W\u00e4hlen Sie einen Studienbereich, um den n\u00e4chsten Schritt vorzubereiten.", "Manage the protocol, rounds and independent reviews. Choose a study section to prepare the next step."))
  }
  if ("coordinate" %in% capabilities) {
    return(tr(lang, "Pr\u00fcfen Sie synthetische Kontakte und genaue Empf\u00e4ngerlisten, bevor Sie Importe oder lokale Testbelege freigeben.", "Review synthetic contacts and exact recipient lists before approving imports or local test receipts."))
  }
  if ("edit" %in% capabilities) {
    return(tr(lang, "Bewahren Sie Originalquellen und begr\u00fcnden Sie getrennte redaktionelle Fassungen, Codierungen und Itembez\u00fcge.", "Preserve original sources and document separate editorial versions, coding decisions and item provenance."))
  }
  if ("panel" %in% capabilities) {
    return(tr(lang, "Speichern Sie jede Antwort und pr\u00fcfen Sie den best\u00e4tigten Stand vor Ihrer ausdr\u00fccklichen Abgabe.", "Save each response and review the confirmed answers before explicitly submitting your round."))
  }
  if ("audit" %in% capabilities) {
    return(tr(lang, "Pr\u00fcfen Sie den aufgezeichneten Verlauf dieser Studie. Antwortinhalte und Kontakte geh\u00f6ren nicht zu dieser Ansicht.", "Review the recorded history of this study. Response content and contacts are not part of this view."))
  }
  if (any(c("analyse", "export", "contacts_export") %in% capabilities)) {
    return(tr(lang, "Fordern Sie die Exporte an, die Ihre Rolle erlaubt. Jeder Abruf wird gepr\u00fcft und aufgezeichnet.", "Request the exports your role permits. Every retrieval is checked and recorded."))
  }
  tr(lang, "W\u00e4hlen Sie eine Studie, um Ihre verf\u00fcgbaren Arbeitsbereiche zu sehen.", "Choose a study to see your available work areas.")
}
