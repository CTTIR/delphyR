# Synthetic service/database load qualification, independent of browser/network latency.
if (Sys.getenv("DELPHYR_TEST_DB") != "true") stop("Set DELPHYR_TEST_DB=true")
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
main <- function() {
  root <- normalizePath(".")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test")
  f <- demo_study(r, n = 30L, item_count = 12L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic load qualification", state)
  for (actor in f$panel) record_consent(r, actor, f$study_id, f$consent_id, TRUE, "consent")
  # A filesystem barrier starts already connected independent processes together.
  barrier <- tempfile("load-barrier-", tmpdir = file.path(root, ".checks"))
  dir.create(barrier, mode = "0700")
  run <- function(root, libs, f, index, barrier) {
    .libPaths(libs)
    pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
    r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "delphyr_runtime", environment = "test")
    on.exit(DBI::dbDisconnect(r$con))
    actor <- f$panel[[index]]
    enrollment <- list_enrollments(r, actor, f$study_id)$id[1]
    q <- get_questionnaire(r, actor, enrollment)
    file.create(file.path(barrier, paste0(index, ".ready")))
    limit <- Sys.time() + 60
    while (!file.exists(file.path(barrier, "start"))) {
      if (Sys.time() > limit) stop("Load barrier timed out")
      Sys.sleep(0.05)
    }
    timing <- numeric(nrow(q$items))
    for (i in seq_len(nrow(q$items))) {
      start <- proc.time()[["elapsed"]]
      receipt <- save_response(r, actor, enrollment, q$items$id[i], list(status = "answered", value = 7L), 0L, paste0("load-", i))
      timing[i] <- proc.time()[["elapsed"]] - start
      stopifnot(receipt$revision == 1L)
    }
    # Read each acknowledged value back through a fresh connection.
    verify <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "delphyr_runtime", environment = "test")
    on.exit(DBI::dbDisconnect(verify$con), add = TRUE)
    saved <- get_questionnaire(verify, actor, enrollment)$responses
    stopifnot(nrow(saved) == nrow(q$items), all(saved$value_int == 7L), all(saved$revision == 1L))
    timing
  }
  children <- list()
  on.exit(for (child in children) if (child$is_alive()) child$kill(), add = TRUE)
  for (i in seq_along(f$panel)) children[[i]] <- callr::r_bg(run, list(root, .libPaths(), f, i, barrier))
  limit <- Sys.time() + 60
  while (length(list.files(barrier, pattern = "ready$")) < length(children)) {
    if (Sys.time() > limit || any(!vapply(children, function(x) x$is_alive(), logical(1)))) stop("Load clients failed to reach barrier")
    Sys.sleep(0.1)
  }
  file.create(file.path(barrier, "start"))
  values <- unlist(lapply(children, function(x) {
    x$wait(timeout = 60000)
    x$get_result()
  }))
  DBI::dbDisconnect(r$con)
  p95 <- unname(stats::quantile(values, 0.95))
  result <- list(status = if (p95 < 2) "PASS" else "FAIL", scope = "local R service and PostgreSQL only; excludes browser and network", clients = length(children), acknowledged_and_reloaded = length(values), p50_seconds = unname(stats::median(values)), p95_seconds = p95, maximum_seconds = max(values), threshold_p95_seconds = 2, study_id = f$study_id, timestamp = format(Sys.time(), tz = "UTC", usetz = TRUE))
  jsonlite::write_json(result, ".checks/load-check.json", auto_unbox = TRUE, pretty = TRUE)
  print(result)
  stopifnot(result$status == "PASS")
}
main()
