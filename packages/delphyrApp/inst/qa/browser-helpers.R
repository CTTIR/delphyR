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
# runtime role. `build` receives the runtime repository and returns the app.
qa_host <- function(name, port, build, data = list()) {
  callr::r_bg(
    function(root, libs, port, build, data, runtime_user) {
      .libPaths(libs)
      pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
      pkgload::load_all(file.path(root, "packages/delphyrApp"), quiet = TRUE)
      repo <- delphyr::connect_repository(
        host = Sys.getenv("DELPHYR_DB_HOST", "127.0.0.1"), port = as.integer(Sys.getenv("DELPHYR_DB_PORT", "55439")),
        dbname = Sys.getenv("DELPHYR_DB_NAME", "delphyr"), user = runtime_user, environment = "development",
        artifact_root = file.path(root, ".artifacts")
      )
      shiny::runApp(build(repo, data), host = "127.0.0.1", port = port, launch.browser = FALSE)
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
    wait_text = function(id, text, tries = 150L) wait_for(sprintf("(function(){var x=document.getElementById(%s);return !!x && x.innerText.includes(%s);})()", quote_js(id), quote_js(text)), tries),
    exists = function(id) isTRUE(js(sprintf("document.getElementById(%s) !== null", quote_js(id)))),
    viewport = function(mobile) invisible(b$Emulation$setDeviceMetricsOverride(width = if (mobile) 390 else 1280, height = if (mobile) 844 else 900, deviceScaleFactor = 1, mobile = mobile)),
    no_overflow = function() isTRUE(js("document.documentElement.scrollWidth <= innerWidth")),
    output_errors = function() js("document.querySelectorAll('.shiny-output-error').length"),
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
