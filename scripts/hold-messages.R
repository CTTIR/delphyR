# After a restore from a backup: put every message that waits for delivery on
# hold, so that the worker sends none of them before a coordinator decided.
#   Rscript scripts/hold-messages.R           counts only
#   Rscript scripts/hold-messages.R --apply   puts them on hold
# Run it before the worker is started on the restored database.
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
r <- delphyr::connect_repository(
  host = Sys.getenv("DELPHYR_DB_HOST", "127.0.0.1"), port = as.integer(Sys.getenv("DELPHYR_DB_PORT", "55439")),
  dbname = Sys.getenv("DELPHYR_DB_NAME", "delphyr"), user = Sys.getenv("DELPHYR_DB_USER", "delphyr_runtime"), environment = "development"
)
x <- delphyr::hold_pending_messages(r, dry_run = !identical(commandArgs(TRUE), "--apply"))
DBI::dbDisconnect(r$con)
cat(jsonlite::toJSON(x, auto_unbox = TRUE), "\n")
