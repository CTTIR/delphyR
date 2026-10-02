# Operational state of the local installation as JSON, for monitoring and the
# first look at an incident. Exit status 0: ready; 1: not ready; 2: no answer.
#   Rscript scripts/status.R
# The output holds counts and ages only.
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
status <- tryCatch(
  {
    r <- delphyr::connect_repository(
      host = Sys.getenv("DELPHYR_DB_HOST", "127.0.0.1"), port = as.integer(Sys.getenv("DELPHYR_DB_PORT", "55439")),
      dbname = Sys.getenv("DELPHYR_DB_NAME", "delphyr"), user = Sys.getenv("DELPHYR_DB_USER", "delphyr_runtime"),
      environment = "development", artifact_root = Sys.getenv("DELPHYR_ARTIFACT_ROOT", file.path(getwd(), ".artifacts")), connect_timeout = 5L
    )
    on.exit(DBI::dbDisconnect(r$con))
    x <- delphyr::get_system_status(r)
    # Free space of the private export directory, where it exists.
    x$artifact_storage <- if (dir.exists(r$artifact_root)) {
      free <- suppressWarnings(as.numeric(system2("df", c("-Pk", shQuote(r$artifact_root)), stdout = TRUE)[2] |> strsplit(" +") |> unlist())[4])
      list(present = TRUE, free_mb = round(free / 1024))
    } else {
      list(present = FALSE)
    }
    x
  },
  error = function(e) list(ready = FALSE, schema = list(state = "unreachable"), attention = "database_unreachable")
)
cat(jsonlite::toJSON(status, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), "\n")
quit(save = "no", status = if (isTRUE(status$ready)) 0L else if (identical(status$schema$state, "unreachable")) 2L else 1L)
