job_repo <- function(env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "PostgreSQL opt-in required")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test", artifact_root = tempfile("delphyr-test-"))
  withr::defer(
    {
      DBI::dbDisconnect(r$con)
      unlink(r$artifact_root, recursive = TRUE)
    },
    envir = env
  )
  r
}
job_fixture <- function(r) {
  f <- demo_study(r, n = 2, item_count = 1)
  for (state in c("review", "approved", "open", "closed")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic fixture", state)
  f$snapshot <- freeze_round(r, f$manager, f$round$id, "freeze")$id
  f
}
test_that("leases recover and exhausted crashes become terminal", {
  r <- job_repo()
  f <- job_fixture(r)
  id <- request_analysis(r, f$manager, f$snapshot, "analysis")$id
  j <- claim_job(r, study_id = f$study_id)
  expect_equal(j$id, id)
  expect_equal(nrow(claim_job(r, study_id = f$study_id)), 0L)
  execute(r, "UPDATE ops.jobs SET lease_until=clock_timestamp()-interval '1 second' WHERE id=$1", id)
  newer <- claim_job(r, study_id = f$study_id)
  expect_equal(newer$id, id)
  expect_false(identical(j$lease_token, newer$lease_token))
  expect_equal(newer$attempts, 2L)
  execute(r, "UPDATE ops.jobs SET lease_until=clock_timestamp()-interval '1 second',attempts=3 WHERE id=$1", id)
  expect_equal(nrow(claim_job(r, study_id = f$study_id)), 0L)
  expect_equal(get_operation(r, f$manager, id)$state, "dead_letter")
})
test_that("private exports reproduce and rights are checked again on download", {
  r <- job_repo()
  f <- job_fixture(r)
  id <- request_export(r, f$manager, f$snapshot, "export")$id
  expect_equal(request_export(r, f$manager, f$snapshot, "export")$id, id)
  result <- worker_step(r, study_id = f$study_id)
  expect_equal(result$state, "succeeded")
  path <- download_artifact(r, f$manager, result$result_ref)
  expect_true(file.exists(file.path(path, "report.html")))
  a <- reproduce_export(path)
  expect_true(all(a$results$n_valid == 0))
  files <- list.files(path)
  expect_false(any(grepl("contact|principal|token", files)))
  set_capability(r, f$manager, f$study_id, f$manager$principal_id, "export", FALSE, "revoke")
  expect_error(download_artifact(r, f$manager, result$result_ref), class = "DEL_FORBIDDEN")
  set_capability(r, f$manager, f$study_id, f$manager$principal_id, "export", TRUE, "restore")
  write("tampered", file.path(path, "analysis-results.csv"))
  expect_error(download_artifact(r, f$manager, result$result_ref), class = "DEL_VALIDATION")
})
test_that("revocation after queueing prevents worker export", {
  r <- job_repo()
  f <- job_fixture(r)
  id <- request_export(r, f$manager, f$snapshot, "export")$id
  set_capability(r, f$manager, f$study_id, f$manager$principal_id, "export", FALSE, "revoke")
  expect_equal(worker_step(r, study_id = f$study_id)$error_code, "DEL_FORBIDDEN")
  expect_equal(query(r, "SELECT state FROM ops.jobs WHERE id=$1", id)$state, "dead_letter")
  expect_false(dir.exists(r$artifact_root))
})
# Reads the manifest of an export directory.
job_manifest <- function(path) from_json(paste(readLines(file.path(path, "manifest.json"), warn = FALSE), collapse = "\n"))
# Without the optional report runtime the round export is written at once.
job_without_quarto <- function(env = parent.frame()) {
  local_mocked_bindings(render_study_report = function(...) del_abort("DEL_DEPENDENCY", "report.quarto_runtime"), .package = "delphyr", .env = env)
}

test_that("an export is bound to its purpose, profile, data state and download period", {
  r <- job_repo()
  f <- job_fixture(r)
  job_without_quarto()
  purpose <- "Synthetic secondary analysis of the first round"
  for (bad in list("too short", strrep("x", 501L), NA_character_, 42, c(purpose, purpose), "         x         ")) {
    e <- tryCatch(request_export(r, f$manager, f$snapshot, "bad purpose", purpose = bad), error = function(e) e)
    expect_identical(c(class(e)[1], e$path), c("DEL_VALIDATION", "export.purpose"))
  }
  expect_error(request_study_export(r, f$manager, f$study_id, "study_summary", "bad study purpose", purpose = "short"), class = "DEL_VALIDATION")
  job <- request_export(r, f$manager, f$snapshot, "export", purpose = purpose)
  expect_identical(request_export(r, f$manager, f$snapshot, "export", purpose = purpose), job)
  # The same key with another purpose is another request.
  expect_error(request_export(r, f$manager, f$snapshot, "export", purpose = "Another synthetic purpose"), class = "DEL_CONFLICT")
  # A second request while the first is pending is merged and adds its purpose.
  second <- "Synthetic check of the reproduction script"
  expect_identical(request_export(r, f$manager, f$snapshot, "again", purpose = second)$id, job$id)
  audit <- list_audit_events(r, f$manager, f$study_id, actions = "request_export")
  expect_setequal(audit$reason, c(purpose, second))
  # A download period outside one hour to thirty days is refused before any job is taken.
  for (hours in list(0, 721, NA_real_, "24")) expect_error(worker_step(r, study_id = f$study_id, download_hours = hours), class = "DEL_VALIDATION")
  expect_identical(get_operation(r, f$manager, job$id)$state, "queued")
  result <- worker_step(r, study_id = f$study_id, download_hours = 2)
  expect_identical(result$state, "succeeded")
  period <- query(r, "SELECT extract(epoch FROM expires_at-created_at)::float8/3600 AS hours FROM ops.artifacts WHERE id=$1", result$result_ref)$hours
  expect_equal(period, 2, tolerance = 0.01)
  path <- download_artifact(r, f$manager, result$result_ref)
  manifest <- job_manifest(path)
  expect_identical(unlist(manifest$purposes), c(purpose, second))
  expect_identical(c(manifest$profile, manifest$study_id, manifest$snapshot_id), c("research_round", f$study_id, f$snapshot))
  expect_match(manifest$exported_at, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
  expect_match(manifest$data_as_of, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
  # Every data file names the version of its schema.
  schemas <- vapply(manifest$files, function(x) if (is.null(x$schema_version)) NA_character_ else x$schema_version, character(1))
  names(schemas) <- vapply(manifest$files, `[[`, character(1), "name")
  expect_true(all(!is.na(schemas[grepl("[.](csv|json)$", names(schemas))])))
  expect_true(all(is.na(schemas[c("README.md", "reproduce.R", "report.html")])))
  provenance <- from_json(paste(readLines(file.path(path, "provenance.json"), warn = FALSE), collapse = "\n"))
  expect_identical(provenance$timezone, demo_protocol()$study$timezone)
  expect_identical(provenance$configuration_hash, query(r, "SELECT p.hash FROM research.rounds r JOIN research.protocol_versions p ON p.id=r.protocol_id WHERE r.id=$1", f$round$id)$hash)
  expect_true(all(c("delphyr", "r", "git_commit", "lockfile_sha256", "locale", "quantile_type") %in% names(provenance$software)))
  expect_identical(provenance$analysis$result_hash, manifest$result_hash)
  expect_identical(reproduce_export(path)$provenance$result_hash, manifest$result_hash)
  # A study-level export carries the purpose in its manifest as well.
  study <- request_study_export(r, f$manager, f$study_id, "audit_restricted", "study export", purpose = "Synthetic review of the approvals of the study")
  expect_identical(worker_step(r, study_id = f$study_id)$state, "succeeded")
  study_path <- download_artifact(r, f$manager, get_operation(r, f$manager, study$id)$result_ref)
  expect_identical(unlist(job_manifest(study_path)$purposes), "Synthetic review of the approvals of the study")
  expect_identical(list_audit_events(r, f$manager, f$study_id, actions = "request_export:audit_restricted")$reason, "Synthetic review of the approvals of the study")
  # A request without a purpose leaves the list empty.
  plain <- request_study_export(r, f$manager, f$study_id, "study_summary", "no purpose")
  expect_identical(worker_step(r, study_id = f$study_id)$state, "succeeded")
  expect_length(job_manifest(download_artifact(r, f$manager, get_operation(r, f$manager, plain$id)$result_ref))$purposes, 0L)
})

test_that("the delegated identity of a job lives as long as its reservation and is renewed with it", {
  r <- job_repo()
  f <- job_fixture(r)
  job_without_quarto()
  original <- write_export
  seen <- NULL
  local_mocked_bindings(write_export = function(repo, actor, snapshot_id) {
    seen <<- actor$expires_at
    original(repo, actor, snapshot_id)
  }, .package = "delphyr")
  request_export(r, f$manager, f$snapshot, "long")
  expect_identical(worker_step(r, study_id = f$study_id)$state, "succeeded")
  # Not two minutes: the ten minutes of the reservation.
  expect_gt(as.numeric(difftime(seen, Sys.time(), units = "secs")), 590)
  # A reservation renewed while the job runs keeps job and identity valid
  # beyond the first reservation, also for a rights check during the work.
  second <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(second$con))
  claimed <- NULL
  left <- NULL
  checked <- NULL
  local_mocked_bindings(write_export = function(repo, actor, snapshot_id) {
    expect_true(renew_job_lease(second, claimed$id, claimed$lease_token, 60L))
    left <<- as.numeric(difftime(actor$expires_at, Sys.time(), units = "secs"))
    out <- original(repo, actor, snapshot_id)
    Sys.sleep(6)
    checked <<- authorize(repo, actor, f$study_id, "export")
    out
  }, .package = "delphyr")
  request_export(r, f$manager, f$snapshot, "renewed")
  result <- worker_step(r, study_id = f$study_id, lease_seconds = 5L, on_claim = function(j) claimed <<- j)
  expect_identical(result$state, "succeeded")
  # The identity follows the renewal at once, by the database's measure.
  expect_true(left > 55 && left <= 60)
  expect_false(is.null(checked))
  expect_false(renew_job_lease(second, claimed$id, claimed$lease_token, 60L))
  expect_error(renew_job_lease(second, claimed$id, claimed$lease_token, 7200L), class = "DEL_VALIDATION")
  expect_error(renew_job_lease(second, "not-a-job", claimed$lease_token), class = "DEL_NOT_FOUND")
})

test_that("a job whose reservation ends during its work stops at its next rights check and is taken up again", {
  r <- job_repo()
  f <- job_fixture(r)
  job_without_quarto()
  second <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(second$con))
  original <- write_export
  claimed <- NULL
  end_reservation <- TRUE
  local_mocked_bindings(write_export = function(repo, actor, snapshot_id) {
    # Another process sees the reservation run out, as when nothing renews it.
    if (end_reservation) execute(second, "UPDATE ops.jobs SET lease_until=clock_timestamp()-interval '1 second' WHERE id=$1", claimed$id)
    original(repo, actor, snapshot_id)
  }, .package = "delphyr")
  job <- request_export(r, f$manager, f$snapshot, "lost")
  result <- worker_step(r, study_id = f$study_id, on_claim = function(j) claimed <<- j)
  # A lost reservation, not a refusal of the requester.
  expect_identical(c(result$state, result$error_code), c("failed", "DEL_CONFLICT"))
  state <- query(r, "SELECT state,error_code FROM ops.jobs WHERE id=$1", job$id)
  expect_identical(c(state$state, state$error_code), c("retry_wait", "DEL_CONFLICT"))
  # The export stopped at its first rights check: nothing was written.
  expect_false(dir.exists(r$artifact_root))
  # A requester whose account was closed is refused for good.
  end_reservation <- FALSE
  execute(r, "UPDATE ops.jobs SET available_at=clock_timestamp() WHERE id=$1", job$id)
  execute(r, "UPDATE identity.principals SET active=false WHERE id=$1", f$manager$principal_id)
  expect_identical(worker_step(r, study_id = f$study_id)$error_code, "DEL_UNAUTHORIZED")
  expect_identical(query(r, "SELECT state FROM ops.jobs WHERE id=$1", job$id)$state, "dead_letter")
})

test_that("a registered export that kept its temporary name is delivered from there", {
  r <- job_repo()
  f <- job_fixture(r)
  job_without_quarto()
  request_export(r, f$manager, f$snapshot, "export")
  result <- worker_step(r, study_id = f$study_id)
  expect_identical(result$state, "succeeded")
  # As a worker leaves it when it is stopped between the registration and the
  # renaming.
  final <- file.path(r$artifact_root, result$result_ref)
  expect_true(file.rename(final, paste0(final, ".partial")))
  path <- download_artifact(r, f$manager, result$result_ref)
  expect_identical(basename(path), paste0(result$result_ref, ".partial"))
  expect_identical(reproduce_export(path)$provenance$result_hash, job_manifest(path)$result_hash)
  # It is a registered export, not a leftover for the cleanup.
  Sys.setFileTime(path, Sys.time() - 2 * 3600)
  expect_identical(nrow(remove_unfinished_exports(r, dry_run = FALSE)), 0L)
  expect_true(dir.exists(path))
})

test_that("a job that outlives its reservation is taken up again and leaves no export", {
  r <- job_repo()
  f <- job_fixture(r)
  job_without_quarto()
  original <- write_export
  local_mocked_bindings(write_export = function(repo, actor, snapshot_id) {
    out <- original(repo, actor, snapshot_id)
    Sys.sleep(6)
    out
  }, .package = "delphyr")
  job <- request_export(r, f$manager, f$snapshot, "slow")
  result <- worker_step(r, study_id = f$study_id, lease_seconds = 5L)
  expect_identical(c(result$state, result$error_code), c("failed", "DEL_CONFLICT"))
  state <- query(r, "SELECT state,error_code,attempts FROM ops.jobs WHERE id=$1", job$id)
  expect_identical(c(state$state, state$error_code), c("retry_wait", "DEL_CONFLICT"))
  expect_length(list.files(r$artifact_root, all.files = TRUE, no.. = TRUE), 0L)
  expect_equal(query(r, "SELECT count(*) AS n FROM ops.artifacts WHERE study_id=$1", f$study_id)$n, 0)
})

test_that("an export whose result cannot be recorded leaves no directory, even when recording the failure fails", {
  r <- job_repo()
  f <- job_fixture(r)
  job_without_quarto()
  original <- execute
  local_mocked_bindings(execute = function(repo, sql, ...) {
    if (startsWith(sql, "INSERT INTO ops.artifacts") || startsWith(sql, "UPDATE ops.jobs SET state=CASE")) stop("synthetic lost connection")
    original(repo, sql, ...)
  }, .package = "delphyr")
  for (profile in c("research_round", "study_summary")) {
    job <- if (profile == "research_round") request_export(r, f$manager, f$snapshot, profile) else request_study_export(r, f$manager, f$study_id, profile, profile)
    expect_error(worker_step(r, study_id = f$study_id), "synthetic lost connection")
    expect_true(dir.exists(r$artifact_root))
    expect_length(list.files(r$artifact_root, all.files = TRUE, no.. = TRUE), 0L)
    expect_identical(query(r, "SELECT state FROM ops.jobs WHERE id=$1", job$id)$state, "running")
  }
  expect_equal(query(r, "SELECT count(*) AS n FROM ops.artifacts WHERE study_id=$1", f$study_id)$n, 0)
})

test_that("the worker keeps a long job reserved and reports that it is alive, and stops after its current work when asked", {
  r <- job_repo()
  skip_if_not_installed("callr")
  root <- Sys.getenv("DELPHYR_SOURCE_ROOT")
  skip_if(!nzchar(root), "The worker test needs DELPHYR_SOURCE_ROOT")
  f <- job_fixture(r)
  job <- request_export(r, f$manager, f$snapshot, "export", purpose = "Synthetic check of the worker process")
  work <- tempfile("delphyr-worker-")
  dir.create(work)
  withr::defer(unlink(work, recursive = TRUE))
  stop_file <- file.path(work, "stop")
  worker_id <- paste0("worker-test-", substr(uid(), 1, 8))
  env <- c(DELPHYR_DB_NAME = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), DELPHYR_ARTIFACT_ROOT = file.path(work, "artifacts"), DELPHYR_WORKER_ID = worker_id, DELPHYR_WORKER_STUDY = f$study_id, DELPHYR_WORKER_STOP_FILE = stop_file)
  # The round export reads the submission records after its rights checks;
  # holding that table makes the job as long as the test needs, while the
  # worker's other process works on other tables.
  DBI::dbBegin(r$con)
  withr::defer(suppressWarnings(try(DBI::dbRollback(r$con), silent = TRUE)))
  DBI::dbExecute(r$con, "LOCK TABLE research.snapshot_entries IN ACCESS EXCLUSIVE MODE")
  worker <- callr::rscript_process$new(callr::rscript_process_options(script = file.path(root, "scripts/worker.R"), wd = root, env = env, stdout = file.path(work, "out.log"), stderr = file.path(work, "err.log")))
  withr::defer(if (worker$is_alive()) worker$kill_tree())
  watch <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(watch$con))
  held <- function() query(watch, "SELECT state,lease_until FROM ops.jobs WHERE id=$1", job$id)
  seen <- function() query(watch, "SELECT last_seen_at FROM ops.worker_heartbeats WHERE worker_id=$1", worker_id)$last_seen_at
  wait_for <- function(ok, seconds) {
    deadline <- Sys.time() + seconds
    while (!ok()) {
      if (Sys.time() > deadline || !worker$is_alive()) stop("Worker did not get there: ", paste(readLines(file.path(work, "err.log"), warn = FALSE), collapse = " "))
      Sys.sleep(0.1)
    }
  }
  wait_for(function() identical(held()$state, "running") && length(seen()) == 1L, 90)
  before <- held()$lease_until
  beat <- seen()
  # Still in its job, the worker is reported alive and keeps the job reserved.
  wait_for(function() isTRUE(held()$lease_until > before) && isTRUE(seen() > beat), 45)
  expect_identical(held()$state, "running")
  DBI::dbRollback(r$con)
  wait_for(function() identical(held()$state, "succeeded"), 90)
  file.create(stop_file)
  worker$wait(30000)
  expect_identical(worker$get_exit_status(), 0L)
  # Nothing reports the stopped worker as alive any more.
  last <- seen()
  Sys.sleep(11)
  expect_identical(seen(), last)
  # The export names its purpose and whether the package sources matched the commit.
  r$artifact_root <- file.path(work, "artifacts")
  path <- download_artifact(r, f$manager, get_operation(r, f$manager, job$id)$result_ref)
  expect_identical(unlist(job_manifest(path)$purposes), "Synthetic check of the worker process")
  commit <- from_json(paste(readLines(file.path(path, "provenance.json"), warn = FALSE), collapse = "\n"))$software$git_commit
  expect_true(grepl("^[0-9a-f]{40}( with uncommitted changes in packages/delphyr)?$", commit) || identical(commit, "not recorded"))
  # While the stop file exists the worker does not start.
  again <- callr::rscript(file.path(root, "scripts/worker.R"), wd = root, env = env, fail_on_status = FALSE, show = FALSE, timeout = 60)
  expect_identical(again$status, 0L)
  expect_match(again$stdout, "Worker stopped after its current work")
})
