# Background worker of the development installation: analyses, exports and
# approved synthetic messages, one at a time.
#   Rscript scripts/worker.R
# Environment: DELPHYR_DB_HOST, DELPHYR_DB_PORT, DELPHYR_DB_NAME,
# DELPHYR_DB_USER, DELPHYR_ARTIFACT_ROOT (default .artifacts),
# DELPHYR_WORKER_ID (default worker-1), DELPHYR_WORKER_STUDY (optional study
# UUID), DELPHYR_EXPORT_DOWNLOAD_HOURS (default 24) and
# DELPHYR_WORKER_STOP_FILE (default .local/worker.stop).
# To stop the worker after its current job or message, create the stop file.
# The worker then ends with status 0, and it does not start while the file
# exists; remove it to run the worker again.
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
# Exports record the software state they were built with, when it is known:
# the commit, and whether the package sources differ from it.
if (!nzchar(Sys.getenv("DELPHYR_GIT_COMMIT"))) {
  git <- function(...) {
    out <- tryCatch(suppressWarnings(system2("git", c(...), stdout = TRUE, stderr = FALSE)), error = function(e) NA_character_)
    if (is.null(attr(out, "status"))) out else NA_character_
  }
  commit <- git("rev-parse", "HEAD")
  changes <- git("status", "--porcelain", "--", "packages/delphyr")
  if (length(commit) == 1L && grepl("^[0-9a-f]{40}$", commit) && !anyNA(changes)) {
    Sys.setenv(DELPHYR_GIT_COMMIT = if (length(changes)) paste(commit, "with uncommitted changes in packages/delphyr") else commit)
  }
}
if (!nzchar(Sys.getenv("DELPHYR_LOCKFILE_SHA256")) && file.exists("renv.lock")) Sys.setenv(DELPHYR_LOCKFILE_SHA256 = digest::digest(file = "renv.lock", algo = "sha256"))
settings <- list(
  host = Sys.getenv("DELPHYR_DB_HOST", "127.0.0.1"), port = as.integer(Sys.getenv("DELPHYR_DB_PORT", "55439")),
  dbname = Sys.getenv("DELPHYR_DB_NAME", "delphyr"), user = Sys.getenv("DELPHYR_DB_USER", "delphyr_runtime"),
  environment = "development", artifact_root = Sys.getenv("DELPHYR_ARTIFACT_ROOT", file.path(getwd(), ".artifacts"))
)
worker_id <- Sys.getenv("DELPHYR_WORKER_ID", "worker-1")
study <- if (nzchar(Sys.getenv("DELPHYR_WORKER_STUDY"))) Sys.getenv("DELPHYR_WORKER_STUDY") else NULL
download_hours <- as.numeric(Sys.getenv("DELPHYR_EXPORT_DOWNLOAD_HOURS", "24"))
stop_file <- Sys.getenv("DELPHYR_WORKER_STOP_FILE", file.path(".local", "worker.stop"))
lease <- 600L
keeper <- NULL
drain <- function() {
  if (!is.null(keeper)) keeper$kill()
  cat("Worker stopped after its current work: ", stop_file, " exists.\n", sep = "")
  quit(save = "no", status = 0L)
}
if (file.exists(stop_file)) drain()
r <- do.call(delphyr::connect_repository, settings)
delphyr::record_worker_heartbeat(r, worker_id, started = TRUE)
# A second process reports every ten seconds that the worker is alive, also
# while a long job runs, and renews the reservation of that job while this
# process lives, for at most an hour from the claim.
held <- tempfile("delphyr-worker-job-")
keeper <- callr::r_bg(function(root, libs, settings, worker_id, parent, held, lease) {
  .libPaths(libs)
  pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
  r <- do.call(connect_repository, settings)
  parent <- ps::ps_handle(parent)
  repeat {
    if (!ps::ps_is_running(parent)) quit(save = "no")
    record_worker_heartbeat(r, worker_id)
    job <- tryCatch(readLines(held, warn = FALSE), error = function(e) character())
    if (length(job) == 3L && Sys.time() - as.POSIXct(as.numeric(job[3]), origin = "1970-01-01") < as.difftime(1, units = "hours")) renew_job_lease(r, job[1], job[2], lease)
    Sys.sleep(10)
  }
}, args = list(getwd(), .libPaths(), settings, worker_id, Sys.getpid(), held, lease), supervise = TRUE)
claimed <- function(job) writeLines(c(job$id, job$lease_token, format(as.numeric(Sys.time()), nsmall = 3)), held)
# Each job and message leaves one entry in the technical log. An unexpected
# failure is recorded by its class only and ends the process, so that the
# supervisor restarts it with a fresh connection.
repeat {
  idle <- tryCatch(
    {
      if (!keeper$is_alive()) stop("The process that reports the worker as alive ended.")
      if (file.exists(stop_file)) drain()
      result <- delphyr::worker_step(r, study_id = study, lease_seconds = lease, download_hours = download_hours, on_claim = claimed)
      unlink(held)
      if (file.exists(stop_file)) drain()
      message_result <- delphyr::process_campaign_sink(r, study_id = study)
      identical(result, FALSE) && identical(message_result, FALSE)
    },
    error = function(e) {
      delphyr::log_event("worker.loop", error = e, component = "worker")
      keeper$kill()
      quit(save = "no", status = 1L)
    }
  )
  if (idle) Sys.sleep(1)
}
