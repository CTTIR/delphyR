# Lists the exports whose download period has ended; with --apply their files
# are removed and the time is recorded. Research data are never touched.
#   Rscript scripts/artifact-cleanup.R            # dry run
#   Rscript scripts/artifact-cleanup.R --apply
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
apply <- identical(commandArgs(trailingOnly = TRUE), "--apply")
r <- delphyr::connect_repository(
  host = Sys.getenv("DELPHYR_DB_HOST", "127.0.0.1"), port = as.integer(Sys.getenv("DELPHYR_DB_PORT", "55439")),
  dbname = Sys.getenv("DELPHYR_DB_NAME", "delphyr"), user = Sys.getenv("DELPHYR_DB_USER", "delphyr_runtime"),
  environment = "development", artifact_root = Sys.getenv("DELPHYR_ARTIFACT_ROOT", file.path(getwd(), ".artifacts"))
)
report <- delphyr::remove_expired_artifacts(r, dry_run = !apply)
DBI::dbDisconnect(r$con)
dir.create(".checks", showWarnings = FALSE, mode = "0700")
path <- file.path(".checks", paste0("artifact-cleanup-", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), ".json"))
jsonlite::write_json(list(applied = apply, expired = nrow(report), with_files = sum(report$present), removed = sum(report$removed), exports = report), path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("%s: %d expired exports, %d with files, %d removed. Report: %s\n", if (apply) "Applied" else "Dry run", nrow(report), sum(report$present), sum(report$removed), path))
