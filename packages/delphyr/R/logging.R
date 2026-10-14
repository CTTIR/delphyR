# Technical log. One JSON line per event names the operation, its duration
# and, for a refusal or failure, the class and field path of the condition.
# Arguments, results, condition messages, account references and request
# headers are never written: the log can be kept with ordinary operational
# access and still links a message shown to a person to what happened.
log_levels <- c(off = 0L, error = 1L, warning = 2L, info = 3L)
log_threshold <- function() {
  level <- getOption("delphyr.log_level", Sys.getenv("DELPHYR_LOG_LEVEL", "warning"))
  if (is.character(level) && length(level) == 1L && !is.na(level) && level %in% names(log_levels)) log_levels[[level]] else log_levels[["warning"]]
}
# Only values of a fixed shape reach the log; anything else is replaced.
log_token <- function(x, pattern, fallback) {
  if (is.character(x) && length(x) == 1L && !is.na(x) && grepl(pattern, x)) x else fallback
}
log_refusals <- c("DEL_VALIDATION", "DEL_FORBIDDEN", "DEL_NOT_FOUND", "DEL_CONFLICT", "DEL_ROUND_CLOSED", "DEL_UNAUTHORIZED")
log_condition <- function(e) {
  if (!inherits(e, "delphyr_error")) {
    return(list(level = "error", outcome = "failed", error_class = log_token(class(e)[1], "^[A-Za-z][A-Za-z0-9_.:]{0,79}$", "condition")))
  }
  refused <- is.character(e$code) && length(e$code) == 1L && e$code %in% log_refusals
  out <- list(
    level = if (refused) "warning" else "error", outcome = if (refused) "refused" else "failed",
    error_class = log_token(e$code, "^DEL_[A-Z_]{1,40}$", "DEL_UNKNOWN")
  )
  if (!identical(e$path, "")) out$error_path <- log_token(e$path, "^[A-Za-z0-9_.:,-]{1,200}$", "withheld")
  out
}
write_log <- function(level, fields) {
  if (log_levels[[level]] > log_threshold()) {
    return(invisible(FALSE))
  }
  line <- json(c(list(time = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"), level = level), fields))
  sink <- getOption("delphyr.log_sink")
  # A failing log destination never changes the outcome of an operation.
  tryCatch(if (is.function(sink)) sink(line) else cat(line, "\n", sep = "", file = stderr()), error = function(e) NULL)
  invisible(TRUE)
}
# Entry for one unit of background work. State, code and reason are fixed
# tokens of the queue, never provider or database text.
log_work <- function(operation, started, state, reference, error_class = NULL, reason = NULL) {
  level <- if (state %in% c("succeeded", "sink_recorded", "accepted", "suppressed")) {
    "info"
  } else if (identical(state, "delivery_unknown") || (!is.null(error_class) && !error_class %in% log_refusals)) {
    "error"
  } else {
    "warning"
  }
  fields <- list(
    correlation_id = new_correlation_id(), component = "worker", operation = operation,
    duration_ms = as.integer(round(as.numeric(difftime(Sys.time(), started, units = "secs")) * 1000)),
    reference = log_token(reference, "^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", "withheld"),
    outcome = log_token(state, "^[a-z_]{1,40}$", "unknown")
  )
  if (!is.null(error_class)) fields$error_class <- log_token(error_class, "^DEL_[A-Z_]{1,40}$", "DEL_UNKNOWN")
  if (!is.null(reason) && !is.na(reason)) fields$reason <- log_token(reason, "^[a-z0-9_]{1,60}$", "withheld")
  write_log(level, fields)
}
#' Create a correlation ID for the technical log
#'
#' The ID is random. It is derived from no account, study or content and can
#' be shown to a person and quoted in a support request.
#' @return Twelve lowercase hexadecimal characters.
#' @export
#' @examples
#' new_correlation_id()
new_correlation_id <- function() paste(format(openssl::rand_bytes(6L)), collapse = "")
#' Write one entry of the technical log
#'
#' An entry holds the time, a correlation ID, the component, the operation, its
#' duration and, for a refused or failed operation, the condition class and
#' field path. Arguments, results, condition messages, account references and
#' request headers are never written.
#'
#' Entries are written to standard error as one JSON object per line. Set
#' `options(delphyr.log_sink = function(line) ...)` to route them elsewhere.
#' `options(delphyr.log_level = )` or the environment variable
#' `DELPHYR_LOG_LEVEL` selects `off`, `error` (failures), `warning` (refusals
#' and failures; the default) or `info` (every operation).
#' @param operation Stable operation name, for example "save_response".
#' @param error Condition of a refused or failed operation; NULL for success.
#' @param correlation_id Output of new_correlation_id().
#' @param component Part of the system writing the entry, for example "app".
#' @param duration_ms Duration in milliseconds, if measured.
#' @param reference UUID of the job or message concerned, if any.
#' @return The correlation ID, invisibly.
#' @export
#' @examples
#' options(delphyr.log_sink = function(line) NULL)
#' log_event("example", error = simpleError("not written"))
#' options(delphyr.log_sink = NULL)
log_event <- function(operation, error = NULL, correlation_id = new_correlation_id(), component = "service", duration_ms = NULL, reference = NULL) {
  correlation_id <- log_token(correlation_id, "^[0-9a-f]{12}$", new_correlation_id())
  fields <- list(
    correlation_id = correlation_id, component = log_token(component, "^[a-z][a-z0-9_]{0,31}$", "service"),
    operation = log_token(operation, "^[A-Za-z][A-Za-z0-9_.:-]{0,79}$", "unnamed")
  )
  if (is.numeric(duration_ms) && length(duration_ms) == 1L && is.finite(duration_ms) && duration_ms >= 0) fields$duration_ms <- as.integer(round(duration_ms))
  if (!is.null(reference)) fields$reference <- log_token(reference, "^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", "withheld")
  detail <- if (is.null(error)) list(level = "info", outcome = "ok") else log_condition(error)
  write_log(detail$level, c(fields, detail[setdiff(names(detail), "level")]))
  invisible(correlation_id)
}
#' Run one operation with an entry in the technical log
#'
#' Measures the operation and writes one entry, see log_event(). A refused or
#' failed operation signals its original condition again, extended by the field
#' `correlation_id`, so that the message shown to a person can quote it.
#' @param operation Stable operation name, for example "save_response".
#' @param code Function without arguments performing the operation.
#' @param correlation_id Output of new_correlation_id().
#' @param component Part of the system writing the entry, for example "app".
#' @return The value of code().
#' @export
#' @examples
#' options(delphyr.log_sink = function(line) NULL)
#' log_operation("example", function() 1 + 1)
#' options(delphyr.log_sink = NULL)
log_operation <- function(operation, code, correlation_id = new_correlation_id(), component = "service") {
  ensure(is.function(code), "log.code")
  started <- Sys.time()
  elapsed <- function() as.numeric(difftime(Sys.time(), started, units = "secs")) * 1000
  value <- tryCatch(code(), error = function(e) {
    id <- log_event(operation, error = e, correlation_id = correlation_id, component = component, duration_ms = elapsed())
    if (is.list(e)) e$correlation_id <- id
    stop(e)
  })
  log_event(operation, correlation_id = correlation_id, component = component, duration_ms = elapsed())
  value
}
# Printing a frozen snapshot shows what it is, never its content: a console or
# a log that captures it receives no answer and no free text.
#' @export
print.delphyr_snapshot <- function(x, ...) {
  d <- x$data
  texts <- sum(d$answer_status == "answered" & !is.na(d$value_text))
  cat(
    "<frozen snapshot>\n",
    "  id: ", x$snapshot_id, "\n",
    "  content hash: ", x$content_hash, "\n",
    "  study ", x$protocol$study$code, ", round ", x$round_number, "\n",
    "  panel: ", length(unique(d$panelist_id)), " assigned, ", length(unique(d$panelist_id[d$submitted])), " submitted\n",
    "  fields: ", nrow(x$items), " item dimensions, ", nrow(d), " response fields, ", texts, " free-text answers\n",
    "  Answers and free texts are not printed.\n",
    sep = ""
  )
  invisible(x)
}
# A feedback draft and the data of a report are printed the same way: what
# they are and how much they hold, never a table or a reviewed text.
#' @export
print.delphyr_feedback_draft <- function(x, ...) {
  r <- x$results
  suppressed <- if (is.null(r$suppressed)) 0L else sum(r$suppressed %in% TRUE)
  cat(
    "<feedback draft>\n",
    "  hash: ", x$hash, "\n",
    "  analysis hash: ", x$analysis_hash, "\n",
    "  results: ", NROW(r), " rows, ", suppressed, " suppressed; distributions: ", NROW(x$distributions), " rows\n",
    "  qualitative texts: ", length(x$qualitative), "\n",
    "  Results and texts are not printed.\n",
    sep = ""
  )
  invisible(x)
}
#' @export
print.delphyr_report_data <- function(x, ...) {
  value <- unclass(x)
  rows <- vapply(Filter(is.data.frame, value), nrow, integer(1))
  m <- value$metadata
  cat(
    "<report data>\n",
    "  profile: ", value$profile, ", schema version ", value$schema_version, "\n",
    "  content hash: ", value$content_hash, "\n",
    "  study ", if (!is.null(m$study_code)) m$study_code else m$study_id, if (!is.null(m$round_number)) paste0(", round ", m$round_number), "\n",
    "  tables: ", if (length(rows)) paste0(names(rows), " (", rows, ")", collapse = ", ") else "none", "\n",
    "  Tables and texts are not printed.\n",
    sep = ""
  )
  invisible(x)
}
