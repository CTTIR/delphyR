log_capture <- function(level = "info", env = parent.frame()) {
  lines <- character()
  withr::local_options(list(delphyr.log_level = level, delphyr.log_sink = function(line) lines <<- c(lines, line)), .local_envir = env)
  function() lapply(lines, jsonlite::fromJSON)
}
log_fields <- c("time", "level", "correlation_id", "component", "operation", "duration_ms", "reference", "outcome", "error_class", "error_path", "reason")

test_that("an operation leaves one entry with its duration and nothing of its content", {
  entries <- log_capture()
  value <- log_operation("save_response", function() list(answer = "CANARY-ANSWER"), component = "app")
  expect_identical(value$answer, "CANARY-ANSWER")
  x <- entries()
  expect_length(x, 1L)
  expect_true(all(names(x[[1]]) %in% log_fields))
  expect_identical(x[[1]][c("level", "component", "operation", "outcome")], list(level = "info", component = "app", operation = "save_response", outcome = "ok"))
  expect_match(x[[1]]$correlation_id, "^[0-9a-f]{12}$")
  expect_match(x[[1]]$time, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{3}Z$")
  expect_true(is.numeric(x[[1]]$duration_ms) && x[[1]]$duration_ms >= 0)
  expect_false(any(grepl("CANARY", unlist(x), fixed = TRUE)))
})

test_that("a refusal is logged by class and path and signalled again with its reference", {
  entries <- log_capture()
  e <- tryCatch(log_operation("submit_round", function() del_abort("DEL_CONFLICT", "response.revision")), error = function(e) e)
  expect_s3_class(e, "DEL_CONFLICT")
  expect_identical(e$path, "response.revision")
  x <- entries()[[1]]
  expect_identical(x[c("level", "outcome", "error_class", "error_path")], list(level = "warning", outcome = "refused", error_class = "DEL_CONFLICT", error_path = "response.revision"))
  expect_identical(e$correlation_id, x$correlation_id)
  # A storage failure is a failure of the system, not a refusal.
  e <- tryCatch(log_operation("save_response", function() del_abort("DEL_STORAGE", "transaction")), error = function(e) e)
  expect_identical(entries()[[2]][c("level", "outcome", "error_class")], list(level = "error", outcome = "failed", error_class = "DEL_STORAGE"))
})

test_that("condition messages, unsafe paths and unsafe names never reach an entry", {
  entries <- log_capture()
  secret <- "CANARY duplicate key (email)=(canary@example.invalid)"
  e <- tryCatch(log_operation("import_panel", function() stop(secret)), error = function(e) e)
  expect_identical(conditionMessage(e), secret)
  expect_match(e$correlation_id, "^[0-9a-f]{12}$")
  e <- tryCatch(log_operation("save_response", function() del_abort("DEL_VALIDATION", "value CANARY-ANSWER rejected")), error = function(e) e)
  log_event("CANARY operation name", component = "CANARY component", correlation_id = "CANARY-ID", reference = "CANARY-REFERENCE", duration_ms = "CANARY")
  log_event("download_artifact", error = structure(list(message = "CANARY", call = NULL), class = c("CANARY class", "error", "condition")))
  log_event("download_artifact", error = structure(list(message = "x", call = NULL, code = "CANARY", path = ""), class = c("delphyr_error", "error", "condition")))
  x <- entries()
  expect_length(x, 5L)
  expect_false(any(grepl("CANARY|canary", unlist(x))))
  expect_identical(x[[1]][c("outcome", "error_class")], list(outcome = "failed", error_class = "simpleError"))
  expect_identical(x[[2]]$error_path, "withheld")
  expect_identical(x[[3]][c("component", "operation", "reference")], list(component = "service", operation = "unnamed", reference = "withheld"))
  expect_match(x[[3]]$correlation_id, "^[0-9a-f]{12}$")
  expect_null(x[[3]]$duration_ms)
  expect_identical(x[[4]]$error_class, "condition")
  expect_identical(x[[5]]$error_class, "DEL_UNKNOWN")
  expect_null(x[[5]]$error_path)
  expect_true(all(vapply(x, function(entry) all(names(entry) %in% log_fields), logical(1))))
})

test_that("the level selects what is written and a failing destination changes nothing", {
  run <- function(level) {
    entries <- log_capture(level)
    log_operation("list_studies", function() TRUE)
    try(log_operation("save_response", function() del_abort("DEL_VALIDATION", "response.value")), silent = TRUE)
    try(log_operation("save_response", function() del_abort("DEL_STORAGE", "transaction")), silent = TRUE)
    vapply(entries(), function(x) x$level, character(1))
  }
  expect_identical(run("info"), c("info", "warning", "error"))
  expect_identical(run("warning"), c("warning", "error"))
  expect_identical(run("error"), "error")
  expect_identical(run("off"), character())
  # An unknown level falls back to the default.
  expect_identical(run("CANARY"), c("warning", "error"))
  withr::local_options(list(delphyr.log_level = "info", delphyr.log_sink = function(line) stop("disk full")))
  expect_identical(log_operation("list_studies", function() 42L), 42L)
  expect_s3_class(tryCatch(log_operation("save_response", function() del_abort("DEL_CONFLICT", "response.revision")), error = function(e) e), "DEL_CONFLICT")
  expect_error(log_operation("list_studies", "not a function"), class = "DEL_VALIDATION")
})

test_that("background work is logged by fixed tokens with the job or message as reference", {
  entries <- log_capture()
  id <- uid()
  started <- Sys.time()
  log_work("job.export.study_summary", started, "succeeded", id)
  log_work("job.analysis", started, "failed", id, error_class = "DEL_FORBIDDEN")
  log_work("job.analysis", started, "failed", id, error_class = "DEL_STORAGE")
  log_work("message.deliver", started, "delivery_unknown", id, reason = "adapter_outcome_unknown")
  log_work("message.deliver", started, "failed", id, reason = "Mailbox of canary@example.invalid is full")
  log_work("message.deliver", started, "suppressed", "CANARY", reason = "consent_withdrawn")
  x <- entries()
  expect_identical(vapply(x, function(entry) entry$level, character(1)), c("info", "warning", "error", "error", "warning", "info"))
  expect_true(all(vapply(x, function(entry) identical(entry$component, "worker") && all(names(entry) %in% log_fields), logical(1))))
  expect_identical(x[[1]]$reference, id)
  expect_identical(x[[4]]$reason, "adapter_outcome_unknown")
  expect_identical(x[[5]]$reason, "withheld")
  expect_identical(x[[6]]$reference, "withheld")
  expect_false(any(grepl("CANARY|canary", unlist(x))))
})

test_that("correlation IDs are random and carry no content", {
  ids <- replicate(200, new_correlation_id())
  expect_true(all(grepl("^[0-9a-f]{12}$", ids)))
  expect_identical(anyDuplicated(ids), 0L)
})
