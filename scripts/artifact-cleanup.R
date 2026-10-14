# Lists the exports whose download period has ended and the export
# directories that no registration covers, left by an interrupted worker or an
# earlier release and unchanged for an hour; with --apply their files are
# removed and the time is recorded. Research data are never touched.
#   Rscript scripts/artifact-cleanup.R                    # dry run
#   Rscript scripts/artifact-cleanup.R --apply
#   Rscript scripts/artifact-cleanup.R --apply --record-missing
# An expired export without a directory here is only reported: its files may
# lie in the export directory of another installation that uses the same
# database. --record-missing records it as removed once that is confirmed.
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
arguments <- commandArgs(trailingOnly = TRUE)
stopifnot(all(arguments %in% c("--apply", "--record-missing")))
apply <- "--apply" %in% arguments
record_missing <- "--record-missing" %in% arguments
r <- delphyr::connect_repository(
  host = Sys.getenv("DELPHYR_DB_HOST", "127.0.0.1"), port = as.integer(Sys.getenv("DELPHYR_DB_PORT", "55439")),
  dbname = Sys.getenv("DELPHYR_DB_NAME", "delphyr"), user = Sys.getenv("DELPHYR_DB_USER", "delphyr_runtime"),
  environment = "development", artifact_root = Sys.getenv("DELPHYR_ARTIFACT_ROOT", file.path(getwd(), ".artifacts"))
)
report <- delphyr::remove_expired_artifacts(r, dry_run = !apply, record_missing = record_missing)
unfinished <- delphyr::remove_unfinished_exports(r, dry_run = !apply)
DBI::dbDisconnect(r$con)
dir.create(".checks", showWarnings = FALSE, mode = "0700")
path <- file.path(".checks", paste0("artifact-cleanup-", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), ".json"))
missing <- sum(!report$present & !report$removed)
jsonlite::write_json(list(
  applied = apply, record_missing = record_missing, expired = nrow(report), with_files = sum(report$present), removed = sum(report$removed),
  without_files_kept = missing, exports = report, unfinished_found = nrow(unfinished), unfinished_removed = sum(unfinished$removed), unfinished = unfinished
), path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf(
  "%s: %d expired exports, %d with files, %d removed, %d without files here kept as not removed; %d unfinished export directories, %d removed. Report: %s\n",
  if (apply) "Applied" else "Dry run", nrow(report), sum(report$present), sum(report$removed), missing, nrow(unfinished), sum(unfinished$removed), path
))
