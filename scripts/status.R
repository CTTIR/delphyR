# Operational state of the local installation as JSON, for monitoring and the
# first look at an incident. Exit status 0: ready; 1: the database answers but
# is not ready, for example because its schema is behind this software or the
# status could not be read (attention status_failed); 2: no answer.
#   Rscript scripts/status.R
# The output holds counts and ages only.
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
r <- tryCatch(
  delphyr::connect_repository(
    host = Sys.getenv("DELPHYR_DB_HOST", "127.0.0.1"), port = as.integer(Sys.getenv("DELPHYR_DB_PORT", "55439")),
    dbname = Sys.getenv("DELPHYR_DB_NAME", "delphyr"), user = Sys.getenv("DELPHYR_DB_USER", "delphyr_runtime"),
    environment = "development", artifact_root = Sys.getenv("DELPHYR_ARTIFACT_ROOT", file.path(getwd(), ".artifacts")), connect_timeout = 5L
  ),
  error = function(e) NULL
)
status <- if (is.null(r)) {
  list(ready = FALSE, schema = list(state = "unreachable"), attention = "database_unreachable")
} else {
  # A database that answers is never reported as unreachable; a failure to
  # read its state is named by its condition class only.
  x <- tryCatch(delphyr::get_system_status(r), error = function(e) {
    list(ready = FALSE, schema = list(state = "unknown"), attention = "status_failed", error_class = if (inherits(e, "delphyr_error")) e$code else class(e)[1])
  })
  # Free space of the private export directory, where it exists.
  x$artifact_storage <- if (dir.exists(r$artifact_root)) {
    free <- suppressWarnings(as.numeric(system2("df", c("-Pk", shQuote(r$artifact_root)), stdout = TRUE)[2] |> strsplit(" +") |> unlist())[4])
    list(present = TRUE, free_mb = round(free / 1024))
  } else {
    list(present = FALSE)
  }
  DBI::dbDisconnect(r$con)
  x
}
cat(jsonlite::toJSON(status, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), "\n")
quit(save = "no", status = if (isTRUE(status$ready)) 0L else if (identical(status$schema$state, "unreachable")) 2L else 1L)
