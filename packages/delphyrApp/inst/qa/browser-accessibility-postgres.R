# Keyboard operation, names of controls, headings, contrast, reflow and
# language attributes in Chromium against PostgreSQL:
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/browser-accessibility-postgres.R
#
# The participant's path is driven by real key events only: Tab, digits,
# Space and Enter. No element is clicked and no value is set by script. This
# is an automated check of the properties a script can establish; it is not a
# test with a screen reader and not a statement of conformance.
source("packages/delphyrApp/inst/qa/browser-helpers.R")
ports <- c(panel = 3891L, manager = 3892L)
admin <- qa_admin()
tag <- substr(uuid::UUIDgenerate(), 1, 8)
code <- paste0("QA-ACCESS-", tag)
manager <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-manager-", code), TRUE))
p <- demo_protocol()
p$study$code <- code
p$study$title <- paste("Synthetic accessibility study", tag)
p$study$languages <- c("en", "de")
p$instrument$dimensions <- list(list(code = "relevance", scale = "relevance_9"), list(code = "clarity", scale = "clarity_9"))
p$instrument$scales$clarity_9 <- list(type = "ordinal_integer", values = 1:9, anchors = list(low = "not clear", high = "entirely clear"), missing_options = c("unable_to_judge", "abstained"))
p$analysis$consensus$min_valid_n <- 2
p$analysis$consensus$group_policy <- "pooled"
study <- create_study(admin, manager, p, "create")$id
consent <- publish_consent(admin, manager, study, "Synthetic demonstration only.", "en", "consent")$id
panel <- lapply(1:3, function(i) {
  actor <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-", code, "-", i)))
  add_panelist(admin, manager, study, actor$principal_id, unlist(p$panel$groups)[1], paste0("panel-", i))
  actor
})
codes <- sprintf("I%03d", 1:6)
items <- do.call(rbind, lapply(c("relevance", "clarity"), function(dimension) do.call(rbind, lapply(c("en", "de"), function(locale) {
  data.frame(item_code = codes, item_version = 1L, locale = locale, text = paste(if (locale == "en") "Synthetic statement" else "Synthetische Aussage", codes), dimension_code = dimension, scale_code = paste0(dimension, "_9"), source_ref = "SRC", required = TRUE, display_order = seq_along(codes))
}))))
deadline <- function() format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
# A first round with released feedback, so that the second shows tables.
first <- prepare_round(admin, manager, study, items, consent, deadline(), "round-1")
for (state in c("review", "approved", "open")) invisible(transition_round(admin, manager, first$id, state, first$hash, "Synthetic qualification", paste("1", state)))
for (i in seq_along(panel)) {
  e <- list_enrollments(admin, panel[[i]], study)$id
  record_consent(admin, panel[[i]], study, consent, TRUE, "consent")
  q <- get_questionnaire(admin, panel[[i]], e)
  revisions <- vapply(seq_len(nrow(q$items)), function(j) save_response(admin, panel[[i]], e, q$items$id[j], list(value = 5L + i, status = "answered"), 0L, paste("r1", j))$revision, integer(1))
  submit_round(admin, panel[[i]], e, setNames(revisions, q$items$id), "submit")
}
invisible(transition_round(admin, manager, first$id, "closed", first$hash, "All submitted", "close"))
analysis <- run_analysis(admin, manager, freeze_round(admin, manager, first$id, "freeze")$id, "analyse")$id
feedback <- create_feedback(admin, manager, analysis, command_id = "feedback")
invisible(release_feedback(admin, manager, feedback$id, feedback$hash, "release"))
second <- prepare_round(admin, manager, study, items, consent, deadline(), "round-2")
invisible(assign_feedback(admin, manager, second$id, feedback$id, "assign"))
for (state in c("review", "approved", "open")) invisible(transition_round(admin, manager, second$id, state, second$hash, "Synthetic qualification", paste("2", state)))
enrollment <- list_enrollments(admin, panel[[1]], study)
enrollment <- enrollment$id[enrollment$number == 2L]

build <- function(repo, data) delphyrApp::run_app(repo, delphyr::demo_actor(repo, data$principal))
hosts <- list(
  qa_host(paste0("accessibility-panel-", tag), ports[["panel"]], build, list(principal = panel[[1]]$principal_id)),
  qa_host(paste0("accessibility-manager-", tag), ports[["manager"]], build, list(principal = manager$principal_id))
)
on.exit(for (h in hosts) if (h$is_alive()) h$kill(), add = TRUE)

# Real key events through the browser's input pipeline.
keys <- list(
  Tab = list(key = "Tab", code = "Tab", vk = 9L, text = NULL), Enter = list(key = "Enter", code = "Enter", vk = 13L, text = "\r"),
  Space = list(key = " ", code = "Space", vk = 32L, text = " "), ArrowDown = list(key = "ArrowDown", code = "ArrowDown", vk = 40L, text = NULL)
)
press <- function(s, name, shift = FALSE) {
  k <- if (name %in% names(keys)) keys[[name]] else list(key = name, code = paste0("Digit", name), vk = utf8ToInt(name), text = name)
  modifiers <- if (shift) 8L else 0L
  arguments <- list(type = if (is.null(k$text)) "rawKeyDown" else "keyDown", key = k$key, code = k$code, windowsVirtualKeyCode = k$vk, nativeVirtualKeyCode = k$vk, modifiers = modifiers)
  if (!is.null(k$text)) arguments$text <- k$text
  do.call(s$b$Input$dispatchKeyEvent, arguments)
  s$b$Input$dispatchKeyEvent(type = "keyUp", key = k$key, code = k$code, windowsVirtualKeyCode = k$vk, nativeVirtualKeyCode = k$vk, modifiers = modifiers)
  invisible(TRUE)
}
focused <- function(s) s$js("(function(){var e=document.activeElement;return e ? (e.id || e.tagName.toLowerCase()) : '';})()")
path <- character()
# Presses Tab until the element has the focus; every stop must be visible.
tab_to <- function(s, id, limit = 80L) {
  for (step in seq_len(limit)) {
    if (identical(focused(s), id)) return(invisible(step - 1L))
    press(s, "Tab")
    Sys.sleep(.03)
    now <- focused(s)
    path <<- c(path, now)
    visible <- s$js("(function(){var e=document.activeElement;if(!e||e===document.body)return true;var r=e.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(e).visibility!=='hidden';})()")
    if (!isTRUE(visible)) stop("Focus reached an element that is not visible: ", now)
  }
  stop("Focus did not reach ", id, " within ", limit, " Tab presses; last: ", paste(utils::tail(path, 6), collapse = " > "))
}
wait_saved <- function(s, slot) s$wait_for(sprintf("(function(){var x=document.querySelector('#panel-slot_%d-save_status .del-status--saved');return !!x && x.innerText.includes('Saved:');})()", slot))

# 1. A panel member answers both blocks and submits with the keyboard alone.
s <- qa_session()
qa_open(s, sprintf("http://127.0.0.1:%d", ports[["panel"]]))
s$wait_for(sprintf("document.getElementById('study') !== null && document.getElementById('study').value === '%s'", study))
s$wait_for("document.getElementById('panel-load') !== null && document.getElementById('panel-enrollment').selectize !== undefined && Object.keys(document.getElementById('panel-enrollment').selectize.options).length === 2")
stopifnot(identical(s$value("panel-enrollment"), enrollment))
tab_to(s, "panel-load")
press(s, "Enter")
s$wait_for("document.querySelectorAll('#panel-block section.del-item').length === 10")
q <- get_questionnaire(admin, panel[[1]], enrollment)
field <- function(row) sprintf("panel-item_%d_%d-value", generation, row)
generation <- 1L
rate <- function(rows, digit) {
  for (slot in seq_along(rows)) {
    tab_to(s, field(rows[slot]))
    press(s, digit)
    wait_saved(s, slot)
    stopifnot(identical(s$value(field(rows[slot])), digit), identical(s$value(sub("-value$", "-kind", field(rows[slot]))), "answered"))
  }
}
rate(1:10, "7")
live <- s$js("(function(){var x=document.querySelector('#panel-slot_1-save_status .del-status');return x.getAttribute('role')+' '+x.getAttribute('aria-live');})()")
stopifnot(identical(live, "status polite"))
# The next block is opened with the keyboard; the focus moves to its heading.
tab_to(s, "panel-block_next")
press(s, "Enter")
s$wait_for("document.querySelectorAll('#panel-block section.del-item').length === 2")
s$wait_for("document.activeElement && document.activeElement.id === 'panel-block_heading'")
stopifnot(grepl("Block 2 of 2", s$text("panel-block_heading"), fixed = TRUE))
generation <- 2L
rate(11:12, "8")
tab_to(s, "panel-confirm")
press(s, "Space")
s$wait_for("document.getElementById('panel-confirm').checked === true")
tab_to(s, "panel-submit")
press(s, "Enter")
s$wait_text("panel-receipt", "Submission confirmed:")
stored <- get_questionnaire(admin, panel[[1]], enrollment)
stopifnot(
  nrow(stored$receipt) == 1L, nrow(stored$responses) == 12L,
  identical(sort(stored$responses$value_int), c(rep(7L, 10), rep(8L, 2))), all(stored$responses$status == "answered")
)
# No stop of the path lacked a name or was reached twice in a row.
stopifnot(!any(path == ""), !any(path[-1] == path[-length(path)]))

# 2. Every control has a name; headings do not skip a level; text has contrast.
names_missing <- "(function(){
  function name(e){
    if (e.getAttribute('aria-label')) return e.getAttribute('aria-label');
    var by=e.getAttribute('aria-labelledby'); if (by) return by.split(' ').map(function(i){var x=document.getElementById(i);return x?x.innerText:'';}).join(' ');
    if (e.id) { var l=document.querySelector('label[for=\"'+e.id+'\"]'); if (l) return l.innerText; }
    var p=e.closest('label'); if (p) return p.innerText;
    if (e.tagName==='BUTTON' || e.tagName==='A' || e.tagName==='SUMMARY') return e.innerText;
    return e.getAttribute('title') || '';
  }
  var bad=[];
  document.querySelectorAll('input:not([type=hidden]), select, textarea, button, a[href], summary').forEach(function(e){
    var r=e.getBoundingClientRect();
    if (r.width===0 || r.height===0 || getComputedStyle(e).visibility==='hidden') return;
    if (!name(e).trim()) bad.push(e.tagName.toLowerCase()+'#'+e.id);
  });
  return bad.join(', ');
})()"
heading_skips <- "(function(){
  var last=0, bad=[];
  document.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(function(h){
    var r=h.getBoundingClientRect(); if (r.width===0 || r.height===0) return;
    var level=parseInt(h.tagName.substring(1),10);
    if (last && level>last+1) bad.push(h.tagName+' after H'+last+': '+h.innerText.slice(0,40));
    last=level;
  });
  return bad.join(' | ');
})()"
# Lowest contrast between a text and the background behind it.
lowest_contrast <- "(function(){
  function parse(c){var m=c.match(/rgba?\\(([^)]+)\\)/);if(!m)return null;var p=m[1].split(',').map(parseFloat);return {r:p[0],g:p[1],b:p[2],a:p.length>3?p[3]:1};}
  function lum(c){var v=[c.r,c.g,c.b].map(function(x){x/=255;return x<=0.03928?x/12.92:Math.pow((x+0.055)/1.055,2.4);});return 0.2126*v[0]+0.7152*v[1]+0.0722*v[2];}
  function background(e){while(e){var c=parse(getComputedStyle(e).backgroundColor);if(c&&c.a>0.99)return c;e=e.parentElement;}return {r:255,g:255,b:255,a:1};}
  var worst={ratio:99,text:''};
  var walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,null);
  while(walker.nextNode()){
    var node=walker.currentNode, e=node.parentElement;
    if(!node.nodeValue.trim()||!e) continue;
    var r=e.getBoundingClientRect(), style=getComputedStyle(e);
    if(r.width===0||r.height===0||style.visibility==='hidden'||style.display==='none') continue;
    if(e.closest('option,script,style,[hidden]')) continue;
    var fg=parse(style.color); if(!fg||fg.a<0.99) continue;
    var a=lum(fg), b=lum(background(e)), ratio=(Math.max(a,b)+0.05)/(Math.min(a,b)+0.05);
    if(ratio<worst.ratio) worst={ratio:ratio,text:e.tagName+' '+node.nodeValue.trim().slice(0,40)};
  }
  return JSON.stringify(worst);
})()"
inspect <- function(session, label) {
  # Collapsed sections are opened, so that their controls are inspected too.
  invisible(session$js("(function(){document.querySelectorAll('details').forEach(function(d){d.open=true;});return true;})()"))
  Sys.sleep(.3)
  missing <- session$js(names_missing)
  if (nzchar(missing)) stop(label, ": controls without a name: ", missing)
  skips <- session$js(heading_skips)
  if (nzchar(skips)) stop(label, ": heading levels skipped: ", skips)
  contrast <- jsonlite::fromJSON(session$js(lowest_contrast))
  if (contrast$ratio < 4.5) stop(label, ": text contrast ", round(contrast$ratio, 2), " at ", contrast$text)
  tables <- session$js("Array.from(document.querySelectorAll('table')).filter(function(t){return t.getBoundingClientRect().height>0 && t.querySelectorAll('th').length===0;}).length")
  if (!identical(tables, 0L)) stop(label, ": a table has no header cells")
  round(contrast$ratio, 2)
}
contrast <- c(panel = inspect(s, "Participant view"))
stopifnot(identical(s$js("document.documentElement.lang"), "en"), isTRUE(s$js("document.querySelector('#panel-slot_1-title span[lang]').getAttribute('lang') === 'en'")))
# The interface language changes without touching what was entered.
s$select("language", "de")
s$wait_for("document.documentElement.lang === 'de'")
s$wait_text("panel-slot_1-title", "Synthetische Aussage")
stopifnot(isTRUE(s$js("document.querySelector('#panel-slot_1-title span[lang]').getAttribute('lang') === 'de'")), identical(s$value(field(11L)), "8"))
contrast <- c(contrast, panel_german = inspect(s, "Participant view, German"))
# A focused control is marked visibly.
tab_to(s, field(11L), limit = 120L)
ring <- s$js("(function(){var c=getComputedStyle(document.activeElement);return c.outlineStyle+'|'+c.outlineWidth+'|'+c.boxShadow;})()")
stopifnot(!grepl("^none\\|[^|]*\\|none$", ring))

# 3. Study management: names, headings, contrast with every section open.
m <- qa_session()
qa_open(m, sprintf("http://127.0.0.1:%d", ports[["manager"]]))
m$wait_for(sprintf("document.getElementById('study') !== null && document.getElementById('study').value === '%s'", study))
m$wait_for("document.getElementById('management-round') !== null && document.getElementById('audit-load') !== null")
invisible(m$js("(function(){document.querySelectorAll('details').forEach(function(d){d.open=true;});return true;})()"))
m$click("management-review")
m$wait_text("management-review_items", "Synthetic statement I001")
invisible(m$js("(function(){document.querySelectorAll('details').forEach(function(d){d.open=true;});return true;})()"))
m$click("audit-load")
m$wait_text("audit-events", "Round state changed")
Sys.sleep(1)
contrast <- c(contrast, manager = inspect(m, "Study management"))

# 4. Reflow: at 320 CSS pixels and at 200 percent nothing needs sideways scrolling.
reflow <- function(session, width, scale, label) {
  invisible(session$b$Emulation$setDeviceMetricsOverride(width = width, height = 800, deviceScaleFactor = scale, mobile = FALSE))
  Sys.sleep(.4)
  if (!isTRUE(session$js("document.documentElement.scrollWidth <= window.innerWidth"))) {
    wide <- session$js("(function(){var w=window.innerWidth,out=[];function clipped(e){for(var a=e.parentElement;a&&a!==document.body;a=a.parentElement){var o=getComputedStyle(a).overflowX;if(o==='auto'||o==='scroll'||o==='hidden')return true;}return false;}document.querySelectorAll('body *').forEach(function(e){var r=e.getBoundingClientRect();if(r.width>0&&r.right>w+1&&!clipped(e)){out.push(e.tagName.toLowerCase()+(e.id?'#'+e.id:'')+(typeof e.className==='string'&&e.className?'.'+e.className.split(' ')[0]:'')+' '+Math.round(r.right));}});return out.slice(0,15).join(' | ');})()")
    stop(label, " needs sideways scrolling at ", width, " CSS pixels: ", wide)
  }
  TRUE
}
stopifnot(reflow(s, 320, 1, "Participant view"), reflow(s, 640, 2, "Participant view"), reflow(m, 320, 1, "Study management"), reflow(m, 640, 2, "Study management"))
for (session in list(s, m)) {
  if (!identical(session$output_errors(), 0L)) stop("Output errors: ", session$output_error_ids())
  session$close()
}
DBI::dbDisconnect(admin$con)
print(list(
  keyboard_only_rating_and_submission = TRUE, tab_stops_on_the_way = length(path), focus_moves_to_block_heading = TRUE, save_status_is_live_region = TRUE,
  all_controls_named = TRUE, heading_levels_not_skipped = TRUE, lowest_text_contrast = contrast, tables_have_headers = TRUE,
  language_attribute_follows_content = TRUE, focus_visibly_marked = TRUE, reflow_at_320px_and_200_percent = TRUE
))
