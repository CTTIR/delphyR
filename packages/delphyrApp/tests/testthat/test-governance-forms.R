forms_services <- function(names) stats::setNames(rep(list(function(...) NULL), length(names)), names)
forms_refusal <- function(code) structure(class = c(code, "delphyr_error", "error", "condition"), list(message = paste(code, "artifact"), call = NULL, code = code, path = "artifact", correlation_id = "0123456789ab"))

test_that("the documentation form belongs to the selected study and its loaded version", {
  stored <- list(
    A = list(version = 3L, hash = "a", fields = list(funding = "Funded by agency ALPHA")),
    B = list(version = 1L, hash = "b", fields = list(funding = "Funded by foundation BETA"))
  )
  saved <- list()
  call <- function(name, ...) {
    args <- list(...)
    switch(name,
      get_capabilities = "manage",
      get_study_documentation = c(stored[[args[[1]]]], list(history = data.frame(version = integer(), hash = character(), reason = character(), recorded_at = character()))),
      record_study_documentation = {
        saved[[length(saved) + 1L]] <<- args
        list(id = "doc", hash = "h", version = stored[[args[[1]]]]$version + 1L)
      },
      stop("Unexpected service")
    )
  }
  selected <- shiny::reactiveVal("A")
  language <- shiny::reactiveVal("en")
  services <- forms_services(c("get_capabilities", "get_study_documentation", "record_study_documentation"))
  shiny::testServer(delphyrApp:::documentation_server, args = list(study = function() selected(), lang = function() language(), call = call, services = services), {
    type <- function(...) {
      values <- list(...)
      names(values) <- paste0(names(values), "_", form())
      do.call(session$setInputs, values)
    }
    session$flushReact()
    first <- form()
    # The browser holds A's statements and A's confirmation.
    type(funding = "Funded by agency ALPHA", reason = "Typed for A", confirm = TRUE)
    selected("B")
    session$flushReact()
    expect_false(identical(form(), first))
    html <- output$body$html
    expect_match(html, "Funded by foundation BETA", fixed = TRUE)
    expect_false(grepl("ALPHA", html, fixed = TRUE))
    expect_false(grepl("Typed for A", html, fixed = TRUE))
    # A confirmation given for A's form does not save B's.
    session$setInputs(save = 1)
    expect_length(saved, 0L)
    expect_match(output$status, "A reason and confirmation are required.", fixed = TRUE)
    # B's fields as the browser sends them when it shows them.
    type(funding = "Funded by foundation BETA", reason = "Checked for B", confirm = TRUE)
    session$setInputs(save = 2)
    expect_length(saved, 1L)
    expect_identical(saved[[1]][[1]], "B")
    expect_identical(saved[[1]][[2]], list(funding = "Funded by foundation BETA"))
    expect_identical(saved[[1]][[3]], 1L)
    # Text typed into a field survives a change of language.
    type(funding = "Revised by the team")
    language("de")
    session$flushReact()
    expect_match(output$body$html, "Revised by the team", fixed = TRUE)
  })
})

test_that("an export needs a purpose, and status and download appear only once something is requested", {
  requests <- list()
  states <- c(`job-1` = "queued", `job-2` = "queued")
  call <- function(name, ...) {
    args <- list(...)
    switch(name,
      get_capabilities = c("analyse", "audit"),
      request_study_export = {
        requests[[length(requests) + 1L]] <<- args
        list(id = paste0("job-", length(requests)), state = "queued")
      },
      get_operation = data.frame(id = args[[1]], state = states[[args[[1]]]], result_ref = if (states[[args[[1]]]] == "succeeded") paste0("artifact-", args[[1]]) else NA_character_),
      stop("Unexpected service")
    )
  }
  services <- forms_services(c("get_capabilities", "request_study_export", "get_operation", "download_artifact"))
  shiny::testServer(delphyrApp:::exports_server, args = list(study = function() "study", lang = function() "en", call = call, services = services), {
    session$flushReact()
    html <- output$body$html
    # Nothing requested yet: no status check, no download, no list.
    expect_false(grepl("Check status", html, fixed = TRUE))
    expect_false(grepl("Download", html, fixed = TRUE))
    expect_error(output$requested)
    # The description is a paragraph and keeps the paragraph width.
    expect_match(html, "<p id=\"[^\"]*description\" class=\"shiny-text-output\"></p>")
    session$setInputs(profile = "study_summary", purpose = " too short ", confirm = TRUE, request = 1)
    expect_length(requests, 0L)
    expect_match(output$status, "Describe the purpose of the export in 10 to 500 characters.", fixed = TRUE)
    session$setInputs(purpose = strrep("x", 501), request = 2)
    expect_length(requests, 0L)
    session$setInputs(purpose = "  Annual summary for the steering group  ", request = 3)
    expect_length(requests, 1L)
    expect_identical(requests[[1]][[2]], "study_summary")
    expect_identical(requests[[1]]$purpose, "Annual summary for the steering group")
    listed <- output$requested$html
    expect_match(listed, "Requested exports", fixed = TRUE)
    expect_match(listed, "Aggregated study summary", fixed = TRUE)
    expect_match(listed, "Annual summary for the steering group", fixed = TRUE)
    expect_match(listed, "Queued", fixed = TRUE)
    expect_match(listed, "Check status", fixed = TRUE)
    expect_false(grepl("download_job-1", listed, fixed = TRUE))
    states[["job-1"]] <<- "succeeded"
    session$setInputs(poll = 1)
    listed <- output$requested$html
    expect_match(listed, "download_job-1", fixed = TRUE)
    expect_false(grepl("Check status", listed, fixed = TRUE))
    expect_match(output$status, "State of the latest export: Succeeded", fixed = TRUE)
    # An earlier export stays listed when another one is requested.
    session$setInputs(profile = "audit_restricted", purpose = "Review of approvals for the board", confirm = TRUE, request = 4)
    expect_identical(requested()$id, c("job-2", "job-1"))
    listed <- output$requested$html
    expect_match(listed, "History and approvals", fixed = TRUE)
    expect_match(listed, "download_job-1", fixed = TRUE)
  })
})

test_that("a purpose typed for one study is not offered in another study's export form", {
  call <- function(name, ...) if (name == "get_capabilities") "analyse" else stop("Unexpected service")
  services <- forms_services(c("get_capabilities", "request_study_export", "get_operation", "download_artifact"))
  selected <- shiny::reactiveVal("A")
  language <- shiny::reactiveVal("en")
  shiny::testServer(delphyrApp:::exports_server, args = list(study = function() selected(), lang = function() language(), call = call, services = services), {
    session$flushReact()
    session$setInputs(purpose = "Board report on study A results")
    # Within one study the purpose survives a new drawing of the form.
    language("de")
    session$flushReact()
    expect_match(output$body$html, "Board report on study A results", fixed = TRUE)
    selected("B")
    session$flushReact()
    html <- output$body$html
    expect_match(html, "Zweck dieses Exports", fixed = TRUE)
    expect_false(grepl("study A results", html, fixed = TRUE))
    expect_match(html, "<textarea[^>]*purpose[^>]*></textarea>")
  })
})

test_that("a refused download names its reason and the export is no longer offered", {
  refusal <- "DEL_NOT_FOUND"
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "analyse",
      request_study_export = list(id = "job-1", state = "queued"),
      get_operation = data.frame(id = "job-1", state = "succeeded", result_ref = "artifact-1"),
      download_artifact = stop(forms_refusal(refusal)),
      stop("Unexpected service")
    )
  }
  services <- forms_services(c("get_capabilities", "request_study_export", "get_operation", "download_artifact"))
  shiny::testServer(delphyrApp:::exports_server, args = list(study = function() "study", lang = function() "en", call = call, services = services), {
    session$flushReact()
    session$setInputs(profile = "study_summary", purpose = "Annual summary for the steering group", confirm = TRUE, request = 1)
    session$setInputs(poll = 1)
    expect_match(output$status, "Succeeded", fixed = TRUE)
    expect_error(output[["download_job-1"]])
    session$flushReact()
    expect_identical(requested()$state, "refused")
    expect_true(is.na(requested()$artifact))
    expect_match(output$status, "The export is no longer available", fixed = TRUE)
    expect_match(output$status, "Reference: 0123456789ab", fixed = TRUE)
    expect_false(grepl("Succeeded", output$status, fixed = TRUE))
    listed <- output$requested$html
    expect_match(listed, "Download refused", fixed = TRUE)
    expect_false(grepl("download_job-1\"", listed, fixed = TRUE))
  })
  expect_match(download_error_text(forms_refusal("DEL_FORBIDDEN"), "en"), "Your current rights do not permit this download. Reference: 0123456789ab", fixed = TRUE)
  expect_match(download_error_text(forms_refusal("DEL_UNAUTHORIZED"), "en"), "Your sign-in has expired", fixed = TRUE)
  expect_match(download_error_text(forms_refusal("DEL_STORAGE"), "fr"), "Le t\u00e9l\u00e9chargement a \u00e9chou\u00e9", fixed = TRUE)
})
