# Shared helpers for the self-contained PostgreSQL browser checks. Source from
# the repository root. Every check uses synthetic data, the loopback development
# database and Chromium through chromote; none of them sends a message.
if (!identical(Sys.getenv("DELPHYR_TEST_DB"), "true")) stop("Set DELPHYR_TEST_DB=true to opt in.")
if (dir.exists(".R-library")) .libPaths(c(normalizePath(".R-library"), .libPaths()))
Sys.setenv(CHROMOTE_CHROME = Sys.getenv("CHROMOTE_CHROME", "/usr/bin/chromium"))
pkgload::load_all("packages/delphyr", quiet = TRUE)
qa_root <- normalizePath(".")
dir.create(file.path(qa_root, ".checks"), showWarnings = FALSE, mode = "0700")

qa_connection <- function(user, environment = "development") {
  delphyr::connect_repository(
    host = Sys.getenv("DELPHYR_DB_HOST", "127.0.0.1"), port = as.integer(Sys.getenv("DELPHYR_DB_PORT", "55439")),
    dbname = Sys.getenv("DELPHYR_DB_NAME", "delphyr"), user = user, environment = environment,
    artifact_root = file.path(qa_root, ".artifacts")
  )
}
qa_admin <- function() qa_connection(Sys.getenv("DELPHYR_DB_ADMIN", "postgres"))

# Starts one application host in a separate R process under the restricted
# runtime role. `build` receives the runtime repository, the data and, if it
# takes a third argument, a function that opens a further runtime connection.
qa_host <- function(name, port, build, data = list()) {
  callr::r_bg(
    function(root, libs, port, build, data, runtime_user) {
      .libPaths(libs)
      pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
      pkgload::load_all(file.path(root, "packages/delphyrApp"), quiet = TRUE)
      connect <- function() {
        delphyr::connect_repository(
          host = Sys.getenv("DELPHYR_DB_HOST", "127.0.0.1"), port = as.integer(Sys.getenv("DELPHYR_DB_PORT", "55439")),
          dbname = Sys.getenv("DELPHYR_DB_NAME", "delphyr"), user = runtime_user, environment = "development",
          artifact_root = file.path(root, ".artifacts")
        )
      }
      app <- if (length(formals(build)) >= 3L) build(connect(), data, connect) else build(connect(), data)
      shiny::runApp(app, host = "127.0.0.1", port = port, launch.browser = FALSE)
    },
    list(qa_root, .libPaths(), port, build, data, Sys.getenv("DELPHYR_DB_RUNTIME", "delphyr_runtime")),
    stderr = file.path(qa_root, ".checks", paste0(name, ".log")), stdout = "|"
  )
}

qa_session <- function() {
  b <- chromote::ChromoteSession$new()
  js <- function(code) {
    result <- b$Runtime$evaluate(code, awaitPromise = TRUE)
    if (!is.null(result$exceptionDetails)) stop(result$exceptionDetails$text)
    result$result$value
  }
  quote_js <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE))
  wait_for <- function(code, tries = 150L) {
    for (attempt in seq_len(tries)) {
      if (isTRUE(tryCatch(js(code), error = function(e) FALSE))) return(invisible(TRUE))
      Sys.sleep(.1)
    }
    stop("Browser condition was not met: ", code)
  }
  list(
    b = b, js = js, wait_for = wait_for,
    # Text inputs: set the value and raise the events Shiny listens for.
    type = function(id, value) invisible(js(sprintf("(function(){var x=document.getElementById(%s);x.value=%s;x.dispatchEvent(new Event('input',{bubbles:true}));x.dispatchEvent(new Event('change',{bubbles:true}));return true;})()", quote_js(id), quote_js(value)))),
    select = function(id, value) invisible(js(sprintf("(function(){document.getElementById(%s).selectize.setValue(%s);return true;})()", quote_js(id), quote_js(value)))),
    click = function(id) invisible(js(sprintf("(function(){document.getElementById(%s).click();return true;})()", quote_js(id)))),
    value = function(id) js(sprintf("document.getElementById(%s).value", quote_js(id))),
    text = function(id) js(sprintf("(function(){var x=document.getElementById(%s);return x?x.innerText:'';})()", quote_js(id))),
    # Waits for text in an element and reports what was shown instead on failure.
    wait_text = function(id, text, tries = 150L) {
      found <- tryCatch(wait_for(sprintf("(function(){var x=document.getElementById(%s);return !!x && x.innerText.includes(%s);})()", quote_js(id), quote_js(text)), tries), error = function(e) FALSE)
      if (identical(found, FALSE)) {
        shown <- tryCatch(js(sprintf("(function(){var x=document.getElementById(%s);return x?x.innerText:'<element absent>';})()", quote_js(id))), error = function(e) "<unreadable>")
        stop("Expected '", text, "' in #", id, " but it shows: '", shown, "'")
      }
      invisible(TRUE)
    },
    exists = function(id) isTRUE(js(sprintf("document.getElementById(%s) !== null", quote_js(id)))),
    # A section is rendered again after a confirmed change. `mark` tags the
    # current element; `replaced` waits until the new rendering has arrived.
    mark = function(id) invisible(js(sprintf("(function(){var x=document.getElementById(%s);if(x){x.setAttribute('data-qa-stale','1');}return true;})()", quote_js(id)))),
    replaced = function(id) wait_for(sprintf("(function(){var x=document.getElementById(%s);return !!x && !x.hasAttribute('data-qa-stale');})()", quote_js(id))),
    # Opens the collapsible section that contains a control, as a person would.
    expand = function(id) invisible(js(sprintf("(function(){var d=document.getElementById(%s).closest('details');if(d){d.open=true;}return true;})()", quote_js(id)))),
    viewport = function(mobile) invisible(b$Emulation$setDeviceMetricsOverride(width = if (mobile) 390 else 1280, height = if (mobile) 844 else 900, deviceScaleFactor = 1, mobile = mobile)),
    no_overflow = function() isTRUE(js("document.documentElement.scrollWidth <= innerWidth")),
    # Visible output errors; a silently empty output is not an error.
    output_errors = function() js("Array.from(document.querySelectorAll('.shiny-output-error')).filter(function(x){return !x.classList.contains('shiny-output-error-shiny.silent.error') && x.innerText.trim().length>0;}).length"),
    output_error_ids = function() js("Array.from(document.querySelectorAll('.shiny-output-error')).map(function(x){return x.id+' ['+x.className+'] '+x.innerText.slice(0,80);}).join(' | ')"),
    # Chooses a local file in a Shiny file input and waits for the upload.
    upload = function(id, path) {
      document <- b$DOM$getDocument()
      node <- b$DOM$querySelector(nodeId = document$root$nodeId, selector = paste0("#", id))$nodeId
      b$DOM$setFileInputFiles(files = list(normalizePath(path)), nodeId = node)
      wait_for(sprintf("(function(){var p=document.querySelector('#%s_progress .progress-bar');return !!p && p.innerText.toLowerCase().includes('complete');})()", id))
      invisible(TRUE)
    },
    # Sends the identity headers that a qualified gateway would set for this
    # browser session. The script stands in for the gateway; this is not OIDC.
    identity = function(headers) {
      b$Network$enable()
      invisible(b$Network$setExtraHTTPHeaders(headers = headers))
    },
    # Fetches a Shiny download link inside the page and returns its bytes.
    download = function(id) {
      wait_for(sprintf("(function(){var a=document.getElementById(%s);return !!a && !!a.getAttribute('href') && a.getAttribute('href').length>0;})()", quote_js(id)))
      encoded <- js(sprintf("(async function(){var a=document.getElementById(%s);var r=await fetch(a.href);if(!r.ok) return 'HTTP '+r.status;var b=new Uint8Array(await r.arrayBuffer());var s='';for(var i=0;i<b.length;i+=8192){s+=String.fromCharCode.apply(null,b.subarray(i,i+8192));}return btoa(s);})()", quote_js(id)))
      if (startsWith(encoded, "HTTP ")) stop("Download failed: ", encoded)
      jsonlite::base64_dec(encoded)
    },
    offline = function(value) {
      b$Network$enable()
      invisible(b$Network$emulateNetworkConditions(offline = value, latency = 0, downloadThroughput = if (value) 0 else -1, uploadThroughput = if (value) 0 else -1))
    },
    close = function() invisible(b$close())
  )
}

qa_open <- function(s, url) {
  for (attempt in seq_len(100)) {
    ok <- tryCatch(
      {
        s$b$Page$navigate(url)
        Sys.sleep(.3)
        isTRUE(s$js("typeof Shiny !== 'undefined'"))
      },
      error = function(e) FALSE
    )
    if (ok) return(invisible(TRUE))
    Sys.sleep(.3)
  }
  stop("Application did not start: ", url)
}

qa_count <- function(repo, sql, ...) as.integer(DBI::dbGetQuery(repo$con, sql, params = list(...))[[1]])

# Unpacks downloaded zip bytes into a fresh private directory.
qa_unzip <- function(bytes) {
  directory <- tempfile("delphyr-qa-download-")
  dir.create(directory, mode = "0700")
  archive <- file.path(directory, "download.zip")
  writeBin(bytes, archive)
  utils::unzip(archive, exdir = directory)
  unlink(archive)
  directory
}

# A synthetic study with two frozen rounds built through the services: four
# panel members in two groups, one revised item, attrition in round two,
# decisions and released feedback. Returns actors and identifiers.
qa_two_round_study <- function(admin) {
  code <- paste0("QA-", substr(uuid::UUIDgenerate(), 1, 8))
  manager <- delphyr::demo_actor(admin, delphyr::provision_demo_principal(admin, paste0("demo-manager-", code), TRUE))
  p <- delphyr::demo_protocol()
  p$study$code <- code
  p$study$title <- paste("Synthetic two-round study", code)
  p$study$languages <- "en"
  p$analysis$consensus$min_valid_n <- 2
  p$analysis$consensus$group_policy <- "pooled"
  p$feedback$minimum_display_cell_n <- 3
  study <- delphyr::create_study(admin, manager, p, "create")$id
  consent <- delphyr::publish_consent(admin, manager, study, "Synthetic demonstration only.", "en", "consent")$id
  panel <- lapply(1:4, function(i) {
    actor <- delphyr::demo_actor(admin, delphyr::provision_demo_principal(admin, paste0("demo-", code, "-", i)))
    delphyr::add_panelist(admin, manager, study, actor$principal_id, unlist(p$panel$groups)[1 + (i > 2)], paste0("panel-", i))
    actor
  })
  items <- data.frame(item_code = c("I001", "I002"), item_version = 1L, locale = "en", text = c("Synthetic item one", "Synthetic item two"), dimension_code = "relevance", scale_code = "relevance_9", source_ref = "SRC-1", required = TRUE, display_order = 1:2)
  deadline <- function() format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  conduct <- function(round, number, values, submit) {
    for (state in c("review", "approved", "open")) delphyr::transition_round(admin, manager, round$id, state, round$hash, "Synthetic qualification", paste(number, state))
    for (i in seq_along(panel)) {
      enrollment <- utils::tail(delphyr::list_enrollments(admin, panel[[i]], study)$id, 1)
      if (number == 1L) delphyr::record_consent(admin, panel[[i]], study, consent, TRUE, "consent")
      q <- delphyr::get_questionnaire(admin, panel[[i]], enrollment)
      for (j in seq_len(nrow(q$items))) delphyr::save_response(admin, panel[[i]], enrollment, q$items$id[j], list(value = values[[i]][j], status = "answered"), 0L, paste(number, j))
      if (submit[i]) {
        q <- delphyr::get_questionnaire(admin, panel[[i]], enrollment)
        delphyr::submit_round(admin, panel[[i]], enrollment, stats::setNames(q$responses$revision, q$responses$round_item_id), paste("submit", number))
      }
    }
    delphyr::transition_round(admin, manager, round$id, "closed", round$hash, "All expected submissions received", paste(number, "close"))
    snapshot <- delphyr::freeze_round(admin, manager, round$id, paste(number, "freeze"))$id
    list(snapshot = snapshot, analysis = delphyr::run_analysis(admin, manager, snapshot, paste(number, "analyse"))$id)
  }
  first <- delphyr::prepare_round(admin, manager, study, items, consent, deadline(), "round-1")
  one <- conduct(first, 1L, list(c(8L, 7L), c(7L, 3L), c(9L, 8L), c(2L, 9L)), rep(TRUE, 4))
  delphyr::record_item_decision(admin, manager, one$analysis, "I001", "revise", "Wording was unclear", "decide-1")
  delphyr::record_item_decision(admin, manager, one$analysis, "I002", "rerate", "No consensus yet", "decide-2")
  feedback <- delphyr::create_feedback(admin, manager, one$analysis, command_id = "feedback")
  delphyr::release_feedback(admin, manager, feedback$id, feedback$hash, "release")
  revised <- items
  revised$item_version[1] <- 2L
  revised$text[1] <- "Synthetic item one, revised"
  second <- delphyr::prepare_round(admin, manager, study, revised, consent, deadline(), "round-2")
  delphyr::assign_feedback(admin, manager, second$id, feedback$id, "assign")
  two <- conduct(second, 2L, list(c(8L, 7L), c(8L, 4L), c(9L, 8L), c(5L, 5L)), c(TRUE, TRUE, TRUE, FALSE))
  for (item in c("I001", "I002")) delphyr::record_item_decision(admin, manager, two$analysis, item, "finalize", "Final synthetic decision", paste("final", item))
  delphyr::transition_round(admin, manager, second$id, "finalized", second$hash, "Final round", "finalize")
  list(code = code, study_id = study, manager = manager, panel = panel, rounds = list(first, second), snapshots = c(one$snapshot, two$snapshot), analyses = c(one$analysis, two$analysis), feedback = feedback$id)
}
