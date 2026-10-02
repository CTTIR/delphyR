# Coordinator issuance and invitee acceptance in Chromium against PostgreSQL.
# Run from the repository root; starts and stops its own two application hosts.
# The invitee identity uses the gateway adapter with a synthetic trusted request:
# this qualifies the screens and services, not an OIDC gateway deployment.
if (!identical(Sys.getenv("DELPHYR_TEST_DB"), "true")) stop("Set DELPHYR_TEST_DB=true to opt in.")
if (dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"), .libPaths()))
Sys.setenv(CHROMOTE_CHROME = Sys.getenv("CHROMOTE_CHROME", "/usr/bin/chromium"))
pkgload::load_all("packages/delphyr", quiet = TRUE)
root <- normalizePath(".")
ports <- c(coordinator = 3876L, invitee = 3877L)
admin <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "development")
f <- demo_study(admin, n = 2L, item_count = 1L)
csv <- paste("external_ref,email,display_name,locale,stakeholder_group", "QA-INV-1,invitee@example.invalid,Synthetic Invitee,en,public_contributors", sep = "\n")
preview <- preview_panel_import(admin, f$manager, f$study_id, csv)
invisible(import_panel(admin, f$manager, f$study_id, preview, preview$hash, "Synthetic invitation qualification", "import"))
issuer <- "https://synthetic-idp.example.invalid/realms/qa"
subject <- paste0("qa-", uuid::UUIDgenerate())
secret <- paste(format(openssl::rand_bytes(32L)), collapse = "")
host <- function(root, libs, role, port, principal, issuer, subject, secret) {
  .libPaths(libs)
  pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
  pkgload::load_all(file.path(root, "packages/delphyrApp"), quiet = TRUE)
  repo <- delphyr::connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "delphyr_runtime", environment = "development")
  app <- if (role == "coordinator") {
    delphyrApp::run_app(repo, delphyr::demo_actor(repo, principal))
  } else {
    config <- delphyr::new_authentication_config(issuer, secret, "127.0.0.1")
    request <- list(REMOTE_ADDR = "127.0.0.1", HTTP_X_DELPHYR_GATEWAY = secret, HTTP_X_FORWARDED_USER = subject)
    delphyrApp::run_app(repo, actor_factory = function(session, repo) delphyr::authenticated_actor(repo, request, config))
  }
  shiny::runApp(app, host = "127.0.0.1", port = port, launch.browser = FALSE)
}
hosts <- lapply(names(ports), function(role) callr::r_bg(host, list(root, .libPaths(), role, ports[[role]], f$manager$principal_id, issuer, subject, secret), stderr = file.path(root, ".checks", paste0("invitation-", role, ".log")), stdout = "|"))
on.exit(for (h in hosts) if (h$is_alive()) h$kill(), add = TRUE)
session <- function() {
  b <- chromote::ChromoteSession$new()
  js <- function(code) {
    result <- b$Runtime$evaluate(code, awaitPromise = TRUE)
    if (!is.null(result$exceptionDetails)) stop(result$exceptionDetails$text)
    result$result$value
  }
  wait_for <- function(code, tries = 150L) {
    for (attempt in seq_len(tries)) {
      if (isTRUE(tryCatch(js(code), error = function(e) FALSE))) return(invisible(TRUE))
      Sys.sleep(.1)
    }
    stop("Browser condition was not met: ", code)
  }
  type <- function(id, value) js(sprintf("(function(){var x=document.getElementById(%s);x.value=%s;x.dispatchEvent(new Event('input',{bubbles:true}));x.dispatchEvent(new Event('change',{bubbles:true}));return true;})()", jsonlite::toJSON(id, auto_unbox = TRUE), jsonlite::toJSON(value, auto_unbox = TRUE)))
  list(b = b, js = js, wait_for = wait_for, type = type)
}
open_page <- function(s, url) {
  for (attempt in seq_len(100)) {
    ok <- tryCatch({
      s$b$Page$navigate(url)
      Sys.sleep(.3)
      isTRUE(s$js("typeof Shiny !== 'undefined'"))
    }, error = function(e) FALSE)
    if (ok) return(invisible(TRUE))
    Sys.sleep(.3)
  }
  stop("Application did not start: ", url)
}
count <- function(sql, ...) DBI::dbGetQuery(admin$con, sql, params = list(...))$n

# 1. An unregistered identity is told so and receives no session.
invitee <- session()
open_page(invitee, sprintf("http://127.0.0.1:%d", ports[["invitee"]]))
invitee$wait_for("document.getElementById('unregistered').hidden === false")
stopifnot(grepl("not registered", invitee$js("document.getElementById('unregistered').textContent"), fixed = TRUE))
stopifnot(identical(count("SELECT count(*)::int AS n FROM identity.principals WHERE issuer=$1 AND subject=$2", issuer, subject), 0L))

# 2. The coordinator registers the stable account and issues the invitation.
coordinator <- session()
open_page(coordinator, sprintf("http://127.0.0.1:%d", ports[["coordinator"]]))
coordinator$wait_for("document.getElementById('invitations-issue') !== null && document.getElementById('invitations-draft').value !== ''")
coordinator$wait_for("document.getElementById('invitations-drafts').innerText.includes('Not yet issued')")
coordinator$type("invitations-issuer", issuer)
coordinator$type("invitations-subject", subject)
coordinator$js("document.getElementById('invitations-issue').click()")
coordinator$wait_for("document.getElementById('invitations-status').textContent.includes('reason and confirmation')")
stopifnot(identical(count("SELECT count(*)::int AS n FROM identity.panel_invitations WHERE study_id=$1", f$study_id), 0L))
coordinator$type("invitations-reason", "Stable synthetic account reviewed for this exact draft.")
Sys.sleep(.5)
coordinator$js("document.getElementById('invitations-confirm').click();document.getElementById('invitations-issue').click()")
coordinator$wait_for("document.getElementById('invitations-code') !== null")
code <- coordinator$js("document.getElementById('invitations-code').value")
stopifnot(grepl("^dlp1[.]", code))
coordinator$wait_for("document.getElementById('invitations-drafts').innerText.includes('Awaiting acceptance')")
parsed <- parse_invitation_code(code)
coordinator$js("document.getElementById('invitations-hide').click()")
coordinator$wait_for("document.getElementById('invitations-code') === null")
stopifnot(!grepl(as.character(parsed$token), coordinator$js("document.documentElement.outerHTML"), fixed = TRUE))

# 3. The invitee signs in again; the code arrives in the URL fragment only.
invitee$b$close()
invitee <- session()
open_page(invitee, sprintf("http://127.0.0.1:%d/#invitation=%s", ports[["invitee"]], code))
invitee$wait_for("document.getElementById('invitation_accept-code') !== null && document.getElementById('invitation_accept-code').value.length > 0")
invitee$wait_for("location.hash === ''")
stopifnot(identical(invitee$js("document.getElementById('invitation_accept-code').type"), "password"))
stopifnot(identical(invitee$js("document.getElementById('unregistered').hidden"), TRUE))
stopifnot(grepl("No accessible study", invitee$js("document.getElementById('status').textContent"), fixed = TRUE))
# A changed code is refused without disclosing the reason.
broken <- sub(".$", if (endsWith(code, "0")) "1" else "0", code)
invitee$type("invitation_accept-code", broken)
Sys.sleep(.5)
invitee$js("document.getElementById('invitation_accept-check').click()")
invitee$wait_for("document.getElementById('invitation_accept-status').textContent.includes('not available for your account')")
invitee$type("invitation_accept-code", code)
Sys.sleep(.5)
invitee$js("document.getElementById('invitation_accept-check').click()")
invitee$wait_for("document.getElementById('invitation_accept-accept') !== null")
stopifnot(grepl("Synthetic Delphi study", invitee$js("document.getElementById('invitation_accept-preview').innerText"), fixed = TRUE))
stopifnot(identical(count("SELECT count(*)::int AS n FROM identity.memberships m JOIN identity.principals p ON p.id=m.principal_id WHERE p.subject=$1", subject), 0L))
invitee$js("document.getElementById('invitation_accept-accept').click()")
invitee$wait_for("document.getElementById('invitation_accept-status').textContent.includes('confirm acceptance')")
stopifnot(identical(count("SELECT count(*)::int AS n FROM identity.panel_invitation_acceptances WHERE study_id=$1", f$study_id), 0L))
invitee$js("document.getElementById('invitation_accept-confirm').click();document.getElementById('invitation_accept-accept').click()")
invitee$wait_for("document.getElementById('invitation_accept-preview').innerText.includes('Invitation accepted.')")
invitee$wait_for(sprintf("document.getElementById('study').value === '%s'", f$study_id))
invitee$wait_for("document.querySelector('nav.del-nav') !== null && document.querySelector('nav.del-nav').innerText.includes('My participation')")
stopifnot(identical(invitee$js("document.getElementById('invitation_accept-code').value"), ""))
for (s in list(invitee, coordinator)) {
  stopifnot(identical(s$js("document.querySelectorAll('.shiny-output-error').length"), 0L))
  for (mobile in c(TRUE, FALSE)) {
    s$b$Emulation$setDeviceMetricsOverride(width = if (mobile) 390 else 1280, height = if (mobile) 844 else 900, deviceScaleFactor = 1, mobile = mobile)
    Sys.sleep(.3)
    stopifnot(isTRUE(s$js("document.documentElement.scrollWidth <= innerWidth")))
  }
}

# 4. The coordinator sees the accepted state; the consumed code is useless.
coordinator$js("document.getElementById('invitations-refresh').click()")
coordinator$wait_for("document.getElementById('invitations-drafts').innerText.includes('Accepted')")
replay <- session()
open_page(replay, sprintf("http://127.0.0.1:%d/#invitation=%s", ports[["invitee"]], code))
replay$wait_for("document.getElementById('invitation_accept-code') !== null && document.getElementById('invitation_accept-code').value.length > 0")
replay$js("document.getElementById('invitation_accept-check').click()")
replay$wait_for("document.getElementById('invitation_accept-status').textContent.includes('not available for your account')")

# 5. Independent database verification.
acceptance <- DBI::dbGetQuery(admin$con, "SELECT a.*,p.group_code FROM identity.panel_invitation_acceptances a JOIN research.panelists p ON p.id=a.panelist_id WHERE a.study_id=$1", params = list(f$study_id))
stopifnot(
  nrow(acceptance) == 1L, identical(acceptance$invitation_id, parsed$invitation_id), identical(acceptance$group_code, "public_contributors"),
  identical(count("SELECT count(*)::int AS n FROM identity.consents WHERE study_id=$1 AND membership_id=$2", f$study_id, acceptance$membership_id), 0L),
  identical(count("SELECT count(*)::int AS n FROM research.enrollments WHERE study_id=$1 AND panelist_id=$2", f$study_id, acceptance$panelist_id), 0L),
  identical(count("SELECT count(*)::int AS n FROM identity.panel_invitations WHERE study_id=$1 AND token_hash=$2", f$study_id, as.character(parsed$token)), 0L),
  identical(count("SELECT count(*)::int AS n FROM ops.commands WHERE study_id=$1 AND outcome::text LIKE '%' || $2 || '%'", f$study_id, as.character(parsed$token)), 0L),
  identical(count("SELECT count(*)::int AS n FROM ops.audit WHERE study_id=$1 AND object_ref LIKE '%' || $2 || '%'", f$study_id, as.character(parsed$token)), 0L)
)
logs <- unlist(lapply(file.path(".checks", paste0("invitation-", names(ports), ".log")), readLines, warn = FALSE))
stopifnot(!any(grepl(as.character(parsed$token), logs, fixed = TRUE)), !any(grepl(secret, logs, fixed = TRUE)))
for (s in list(invitee, coordinator, replay)) s$b$close()
DBI::dbDisconnect(admin$con)
print(list(
  unregistered_notice = TRUE, issued_through_ui = TRUE, fragment_prefill_cleared = TRUE, changed_code_refused = TRUE,
  explicit_confirmation_required = TRUE, accepted = acceptance$invitation_id, replay_refused = TRUE,
  no_consent_or_enrollment_created = TRUE, token_absent_from_database_and_logs = TRUE, mobile_overflow = FALSE
))
