security_log <- function(level = "info", env = parent.frame()) {
  lines <- character()
  withr::local_options(list(delphyr.log_level = level, delphyr.log_sink = function(line) lines <<- c(lines, line)), .local_envir = env)
  function() lapply(lines, jsonlite::fromJSON)
}
security_services <- function(...) {
  utils::modifyList(list(
    list_studies = function(...) data.frame(id = "study", title = "Synthetic"),
    list_enrollments = function(...) data.frame(id = character(), number = integer(), round_state = character()),
    get_questionnaire = function(...) stop("unused"), record_consent = function(...) stop("unused"),
    save_response = function(...) stop("unused"), submit_round = function(...) stop("unused")
  ), list(...))
}

test_that("a failed service call shows a reference that names one entry of the technical log", {
  entries <- security_log()
  secret <- "CANARY duplicate key (email)=(canary@example.invalid)"
  app <- run_app(actor = list(principal_id = "CANARY-PRINCIPAL"), services = security_services(
    get_capabilities = function(...) stop(secret),
    list_enrollments = function(...) delphyr::del_abort("DEL_FORBIDDEN", "capability")
  ))
  shiny::testServer(app, {
    session$setInputs(language = "en", study = "study")
    session$flushReact()
    shown <- status()
    expect_match(shown, "^Action failed[.] .* No success was confirmed[.] Reference: [0-9a-f]{12}$")
    reference <- sub("^.* ", "", shown)
    failed <- Filter(function(entry) identical(entry$correlation_id, reference), entries())
    expect_length(failed, 1L)
    expect_identical(failed[[1]][c("component", "operation", "outcome", "error_class")], list(component = "app", operation = "get_capabilities", outcome = "failed", error_class = "simpleError"))
    expect_true(any(vapply(entries(), function(entry) identical(entry$operation, "list_studies") && identical(entry$outcome, "ok"), logical(1))))
    # The condition that leaves a failed service call carries no message of
    # its cause; the log keeps the class of the cause.
    failure <- tryCatch(call("get_capabilities", "study"), error = function(e) e)
    expect_s3_class(failure, "DEL_STORAGE")
    expect_identical(conditionMessage(failure), "DEL_STORAGE service")
    expect_identical(Filter(function(entry) identical(entry$correlation_id, failure$correlation_id), entries())[[1]]$error_class, "simpleError")
    refusal <- tryCatch(call("list_enrollments", "study"), error = function(e) e)
    expect_s3_class(refusal, "DEL_FORBIDDEN")
    x <- entries()
    refused <- Filter(function(entry) identical(entry$correlation_id, refusal$correlation_id), x)
    expect_identical(refused[[1]][c("level", "operation", "outcome", "error_class", "error_path")], list(level = "warning", operation = "list_enrollments", outcome = "refused", error_class = "DEL_FORBIDDEN", error_path = "capability"))
    # Neither the message nor the log repeats what the server refused.
    expect_false(grepl("CANARY|canary", shown))
    expect_false(any(grepl("CANARY|canary", unlist(x))))
    # The reference keeps its value when the language changes.
    session$setInputs(language = "fr")
    expect_match(output$status, paste0("R\u00e9f\u00e9rence : ", reference, "$"))
    session$setInputs(language = "de")
    expect_match(output$status, paste0("Referenz: ", reference, "$"))
  })
})

test_that("a pending input is not logged as a failure and a refused identity is", {
  entries <- security_log()
  app <- run_app(actor = list(principal_id = "trusted"), services = security_services(get_capabilities = function(repo, actor, study) "panel"))
  shiny::testServer(app, {
    # No study is selected yet: the call is never started.
    expect_error(call("get_capabilities", shiny::req(NULL)), class = "shiny.silent.error")
    expect_identical(call("get_capabilities", "study"), "panel")
  })
  x <- entries()
  expect_false(any(vapply(x, function(entry) !identical(entry$outcome, "ok"), logical(1))))
  denied <- run_app(repo = list(), actor_factory = function(session, repo) delphyr::del_abort("DEL_UNAUTHORIZED", "authentication.gateway"), services = security_services())
  shiny::testServer(denied, expect_true(session$isClosed()))
  last <- entries()[[length(entries())]]
  expect_identical(last[c("level", "component", "operation", "outcome", "error_class", "error_path")], list(level = "warning", component = "app", operation = "session_identity", outcome = "refused", error_class = "DEL_UNAUTHORIZED", error_path = "authentication.gateway"))
})

test_that("failure messages outside a service call and failed background work quote a reference", {
  entries <- security_log("warning")
  shown <- safe_error(simpleError("CANARY file too large"), "en")
  expect_match(shown, "^Action failed[.] .* Reference: [0-9a-f]{12}$")
  x <- entries()
  expect_length(x, 1L)
  expect_identical(x[[1]][c("component", "operation", "outcome", "correlation_id")], list(component = "app", operation = "interface", outcome = "failed", correlation_id = sub("^.* ", "", shown)))
  expect_false(any(grepl("CANARY", c(shown, unlist(x)), fixed = TRUE)))
  conflict <- tryCatch(delphyr::log_operation("save_response", function() delphyr::del_abort("DEL_CONFLICT", "response.revision")), error = function(e) e)
  expect_identical(safe_error(conflict, "de"), paste("Konflikt: Bitte Seite neu laden und den gespeicherten Stand pr\u00fcfen. Ihre Eingabe ist noch sichtbar. Referenz:", conflict$correlation_id))
  closed <- tryCatch(delphyr::log_operation("save_response", function() delphyr::del_abort("DEL_ROUND_CLOSED", "round")), error = function(e) e)
  expect_match(safe_error(closed, "en"), paste0("Saving is unavailable[.] Reference: ", closed$correlation_id, "$"))
  expect_length(entries(), 3L)
  id <- "0f8fad5b-d9cb-469f-a165-70867728950e"
  expect_identical(operation_status(list(id = id, state = "succeeded"), "en"), "Operation: Succeeded")
  expect_identical(operation_status(list(id = id, state = "queued"), "en"), "Operation: Queued")
  expect_identical(operation_status(list(id = id, state = "dead_letter"), "en"), paste("Operation: Permanently failed Reference:", id))
  expect_identical(operation_status(list(id = id, state = "retry_wait"), "de"), paste("Auftrag: Wartet auf Wiederholung Referenz:", id))
  expect_identical(localize_status(paste("Operation: Permanently failed Reference:", id), "fr"), paste("Op\u00e9ration : Permanently failed R\u00e9f\u00e9rence :", id))
  # Only a reference of the known shape is treated as one.
  expect_identical(localize_status("Synthetic study Reference: not-a-reference", "de"), "Synthetic study Reference: not-a-reference")
})

test_that("oversized uploads are refused before their content is read", {
  path <- tempfile(fileext = ".csv")
  withr::defer(unlink(path))
  writeLines(c("external_ref,email,display_name,locale,stakeholder_group", "C-1,c-1@example.invalid,Synthetic,en,professionals"), path)
  expect_true(is.raw(panel_upload_bytes(list(datapath = path, size = file.info(path)$size))))
  # The size announced by the browser and the size on disk are both checked.
  expect_error(panel_upload_bytes(list(datapath = path, size = 1024 * 1024 + 1)), "1 MiB")
  writeBin(as.raw(rep(65L, 1024L * 1024L + 1L)), path)
  expect_error(panel_upload_bytes(list(datapath = path, size = 10)), "1 MiB")
  expect_error(panel_upload_bytes(list(datapath = path, size = NA_real_)), "1 MiB")
  expect_error(read_protocol_upload(list(datapath = path, size = 10)), "1 MB")
})
