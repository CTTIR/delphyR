# Scientific forms follow the suite's teal/slate palette and system typography.
app_css <- function() '
body {color:#22303c;background:#eceff2;font-family:system-ui,-apple-system,"Segoe UI",sans-serif;}
.del-wrap {max-width:1040px;margin:auto;padding:24px 20px 60px;}
.del-header {display:flex;justify-content:space-between;align-items:center;gap:24px;flex-wrap:wrap;}
.del-header h1 {font-size:2.1rem;font-weight:750;color:#0e6e78;margin:0;}
.del-banner {background:#fff5d8;border-left:5px solid #8a5900;padding:12px 16px;margin:20px 0;color:#533800;}
.del-sheet {background:white;border:1px solid #dce3e7;border-radius:10px;padding:24px;margin:18px 0;}
.del-item {border-top:1px solid #dce3e7;padding:22px 0;max-width:75ch;}
.del-item h3 {font-size:1.25rem;line-height:1.5;}
h2 {font-size:1.55rem;} p {max-width:75ch;line-height:1.6;}
.btn {min-height:44px;border-radius:7px;white-space:normal;}
a:focus-visible,button:focus-visible,input:focus-visible,textarea:focus-visible,select:focus-visible {outline:3px solid #9b5100!important;outline-offset:3px;}
.del-status {border-left:3px solid #0e6e78;padding:8px 12px;margin:12px 0;overflow-wrap:anywhere;}
.del-status:has(.shiny-text-output:empty) {border:0;padding:0;margin:0;}
.del-management:has(> .shiny-html-output:first-child:empty):has(> .del-status .shiny-text-output:empty) {border:0;padding:0;margin:0;background:transparent;}
.shiny-input-container:has(input[type="checkbox"]) {width:100%;}
.del-note {color:#506273;font-size:.95rem;}
.del-actions {display:flex;gap:12px;flex-wrap:wrap;margin:16px 0;}
.del-consent {white-space:pre-wrap;max-width:75ch;}
.table {display:block;overflow-x:auto;}
@media(max-width:600px) {.del-wrap{padding:16px 12px}.del-sheet{padding:16px}.shiny-input-container{max-width:100%}h1{font-size:1.7rem}}
@media(prefers-reduced-motion:reduce) {*{animation:none!important;transition:none!important}}
'
tr <- function(lang, de, en) if (identical(lang, "en")) en else de
status_ui <- function(id) shiny::tags$div(class = "del-status", role = "status", `aria-live` = "polite", shiny::textOutput(id))
command_id <- function() uuid::UUIDgenerate()
safe_error <- function(e, lang) {
  if (inherits(e, "DEL_CONFLICT")) {
    return(tr(lang, "Konflikt: Bitte Seite neu laden und den gespeicherten Stand pr\u00fcfen. Ihre Eingabe ist noch sichtbar.", "Conflict: reload and review the saved version. Your input remains visible."))
  }
  if (inherits(e, "DEL_ROUND_CLOSED")) {
    return(tr(lang, "Die Runde ist geschlossen oder die Frist abgelaufen. Speichern ist nicht m\u00f6glich.", "The round is closed or its deadline has passed. Saving is unavailable."))
  }
  tr(lang, "Aktion fehlgeschlagen. Bitte Angaben, Berechtigung und Rundenstatus pr\u00fcfen. Es wurde kein Erfolg best\u00e4tigt.", "Action failed. Check your entries, permissions and round state. No success was confirmed.")
}
state_label <- function(state, lang) {
  en <- c(draft = "Draft", review = "In review", approved = "Approved", open = "Open", closed = "Closed", frozen = "Frozen", analysed = "Analysed", released = "Feedback released", finalized = "Finalized", eligible = "Eligible", in_progress = "In progress", submitted = "Submitted")
  de <- c(draft = "Entwurf", review = "In Pr\u00fcfung", approved = "Freigegeben", open = "Offen", closed = "Geschlossen", frozen = "Eingefroren", analysed = "Ausgewertet", released = "Feedback freigegeben", finalized = "Abgeschlossen", eligible = "Teilnahme m\u00f6glich", in_progress = "In Bearbeitung", submitted = "Abgegeben")
  labels <- if (identical(lang, "en")) en else de
  unname(ifelse(state %in% names(labels), labels[state], state))
}

round_display <- function(rounds, language, timezone = "UTC") {
  if (is.null(timezone) || !nzchar(timezone)) timezone <- "UTC"
  deadline <- rounds$deadline
  if (is.numeric(deadline) && !inherits(deadline, "POSIXt")) {
    deadline <- as.POSIXct(deadline, origin = "1970-01-01", tz = "UTC")
  } else {
    deadline <- as.POSIXct(deadline, tz = "UTC")
  }
  out <- data.frame(
    round = rounds$number,
    state = state_label(rounds$state, language),
    deadline = paste(format(deadline, "%Y-%m-%d %H:%M %z", tz = timezone), timezone),
    stringsAsFactors = FALSE
  )
  names(out) <- c(tr(language, "Runde", "Round"), tr(language, "Status", "State"), tr(language, "Abgabefrist", "Deadline"))
  out
}
