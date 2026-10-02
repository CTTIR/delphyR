.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
# Exports record the software state they were built with, when it is known.
if (!nzchar(Sys.getenv("DELPHYR_GIT_COMMIT"))) {
  commit <- tryCatch(suppressWarnings(system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)), error = function(e) character())
  if (length(commit) == 1L && grepl("^[0-9a-f]{40}$", commit)) Sys.setenv(DELPHYR_GIT_COMMIT = commit)
}
if (!nzchar(Sys.getenv("DELPHYR_LOCKFILE_SHA256")) && file.exists("renv.lock")) Sys.setenv(DELPHYR_LOCKFILE_SHA256 = digest::digest(file = "renv.lock", algo = "sha256"))
r <- delphyr::connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "delphyr_runtime", environment = "development", artifact_root = file.path(getwd(), ".artifacts"))
# The worker reports that it is alive, at most every ten seconds.
worker_id <- Sys.getenv("DELPHYR_WORKER_ID", "worker-1")
delphyr::record_worker_heartbeat(r, worker_id, started = TRUE)
seen <- Sys.time()
# Each job and message leaves one entry in the technical log. An unexpected
# failure is recorded by its class only and ends the process, so that the
# supervisor restarts it with a fresh connection.
repeat {
  idle <- tryCatch(
    {
      if (difftime(Sys.time(), seen, units = "secs") >= 10) {
        delphyr::record_worker_heartbeat(r, worker_id)
        seen <- Sys.time()
      }
      result <- delphyr::worker_step(r)
      message_result <- delphyr::process_campaign_sink(r)
      identical(result, FALSE) && identical(message_result, FALSE)
    },
    error = function(e) {
      delphyr::log_event("worker.loop", error = e, component = "worker")
      quit(save = "no", status = 1L)
    }
  )
  if (idle) Sys.sleep(1)
}
