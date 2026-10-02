operations_repo <- function(user = "postgres", env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "PostgreSQL opt-in required")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = user, environment = "test", artifact_root = tempfile("delphyr-operations-"))
  withr::defer({
    DBI::dbDisconnect(r$con)
    unlink(r$artifact_root, recursive = TRUE)
  }, envir = env)
  r
}
operations_stamp <- function(seconds) format(Sys.time() + seconds, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
# A study with two members and one round in the requested state.
operations_fixture <- function(r, state = "open") {
  code <- paste0("OPERATIONS-", substr(uid(), 1, 8))
  manager <- demo_actor(r, provision_demo_principal(r, paste0("demo-manager-", code), TRUE))
  p <- demo_protocol()
  p$study$code <- code
  p$study$languages <- "en"
  study <- create_study(r, manager, p, "create")$id
  consent <- publish_consent(r, manager, study, "Synthetic information.", "en", "consent")$id
  panel <- lapply(1:2, function(i) {
    actor <- demo_actor(r, provision_demo_principal(r, paste0("demo-", code, "-", i)))
    add_panelist(r, manager, study, actor$principal_id, unlist(p$panel$groups)[i], paste0("panel-", i))
    actor
  })
  items <- data.frame(item_code = "I001", item_version = 1L, locale = "en", text = "Synthetic item", dimension_code = "relevance", scale_code = "relevance_9", source_ref = "SRC", required = TRUE, display_order = 1L)
  round <- prepare_round(r, manager, study, items, consent, operations_stamp(86400), "round")
  for (target in c("review", "approved", "open", "closed")) {
    if (identical(state, "draft")) break
    transition_round(r, manager, round$id, target, round$hash, "Synthetic", target)
    if (target == "open") for (actor in panel) record_consent(r, actor, study, consent, TRUE, "consent")
    if (identical(target, state)) break
  }
  list(code = code, manager = manager, panel = panel, study_id = study, consent = consent, items = items, round = round)
}
round_deadline <- function(r, id) query(r, "SELECT to_char(deadline AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS deadline,state FROM research.rounds WHERE id=$1", id)

test_that("a deadline is a complete time with an offset and is refused before any statement", {
  r <- operations_repo()
  f <- operations_fixture(r, "draft")
  consent <- f$consent
  for (bad in c("tomorrow Z", "2026-12-01 18:00:00+01:00", "2026-02-31T10:00:00Z", "2026-13-01T10:00:00Z", "2026-12-01T25:00:00Z", "2026-12-01T10:00:00+25:00", "2026-12-01T10:00Zebra Z")) {
    e <- tryCatch(change_round_deadline(r, f$manager, f$round$id, bad, f$round$hash, "Synthetic", uid()), error = function(e) e)
    expect_s3_class(e, "DEL_VALIDATION")
    expect_identical(e$path, "deadline.format")
  }
  expect_identical(tryCatch(change_round_deadline(r, f$manager, f$round$id, "2026-12-01T10:00:00", f$round$hash, "Synthetic", uid()), error = function(e) e$path), "deadline.offset")
  expect_identical(tryCatch(change_round_deadline(r, f$manager, f$round$id, "2020-01-01T10:00:00Z", f$round$hash, "Synthetic", uid()), error = function(e) e$path), "deadline.past")
  # Preparing a round applies the same rule instead of leaving it to the database.
  transition_round(r, f$manager, f$round$id, "cancelled", f$round$hash, "Synthetic", "cancel")
  e <- tryCatch(prepare_round(r, f$manager, f$study_id, f$items, consent, "next Friday Z", "malformed"), error = function(e) e)
  expect_s3_class(e, "DEL_VALIDATION")
  expect_identical(e$path, "deadline.format")
  expect_identical(prepare_round(r, f$manager, f$study_id, f$items, consent, "2099-12-01T18:00:00.5+01:00", "fraction")$hash, f$round$hash)
})

test_that("the deadline of an unopened round may change freely and is recorded with its rationale", {
  r <- operations_repo()
  f <- operations_fixture(r, "draft")
  other <- operations_fixture(r, "draft")
  expect_error(change_round_deadline(r, f$panel[[1]], f$round$id, operations_stamp(3600), f$round$hash, "Synthetic", "member"), class = "DEL_FORBIDDEN")
  expect_error(change_round_deadline(r, other$manager, f$round$id, operations_stamp(3600), f$round$hash, "Synthetic", "foreign"), class = "DEL_NOT_FOUND")
  expect_identical(tryCatch(change_round_deadline(r, f$manager, f$round$id, operations_stamp(3600), strrep("0", 64), "Synthetic", "hash"), error = function(e) e$path), "round.hash")
  expect_error(change_round_deadline(r, f$manager, f$round$id, operations_stamp(3600), f$round$hash, " ", "blank"), class = "DEL_VALIDATION")
  # Earlier than before is allowed while nobody has been told a deadline.
  earlier <- operations_stamp(3600)
  receipt <- change_round_deadline(r, f$manager, f$round$id, earlier, f$round$hash, "Recruitment finished early", "change")
  expect_identical(receipt, list(id = f$round$id, deadline = earlier))
  expect_identical(round_deadline(r, f$round$id)$deadline, earlier)
  # A retry returns the same receipt; a different request under the key is refused.
  expect_identical(change_round_deadline(r, f$manager, f$round$id, earlier, f$round$hash, "Recruitment finished early", "change"), receipt)
  expect_error(change_round_deadline(r, f$manager, f$round$id, operations_stamp(7200), f$round$hash, "Recruitment finished early", "change"), class = "DEL_CONFLICT")
  events <- get_round_instrument(r, f$manager, f$round$id)$events
  expect_identical(events$target_state, "deadline_changed")
  expect_identical(events$reason, "Recruitment finished early")
  audit <- list_audit_events(r, f$manager, f$study_id, actions = "round_deadline")
  expect_identical(nrow(audit), 1L)
  expect_identical(audit$reason, "Recruitment finished early")
  expect_identical(audit$detail, earlier)
  # The approval of the instrument is untouched.
  expect_identical(get_round_instrument(r, f$manager, f$round$id)$round$instrument_hash, f$round$hash)
  expect_identical(round_deadline(r, f$round$id)$state, "draft")
})

test_that("an open round can only be extended and accepts answers again; a closed round stays closed", {
  r <- operations_repo()
  f <- operations_fixture(r, "open")
  current <- round_deadline(r, f$round$id)$deadline
  expect_identical(tryCatch(change_round_deadline(r, f$manager, f$round$id, operations_stamp(3600), f$round$hash, "Synthetic", "earlier"), error = function(e) e$path), "deadline.earlier")
  expect_identical(round_deadline(r, f$round$id)$deadline, current)
  # The deadline passes while the round is still open: answers are refused.
  execute(r, "UPDATE research.rounds SET deadline=clock_timestamp()-interval '1 minute' WHERE id=$1", f$round$id)
  actor <- f$panel[[1]]
  enrollment <- list_enrollments(r, actor, f$study_id)$id
  item <- get_questionnaire(r, actor, enrollment)$items$id
  expect_error(save_response(r, actor, enrollment, item, list(value = 7L, status = "answered"), 0L, "late"), class = "DEL_ROUND_CLOSED")
  later <- operations_stamp(2 * 86400)
  expect_identical(change_round_deadline(r, f$manager, f$round$id, later, f$round$hash, "Service was interrupted before the deadline", "extend")$deadline, later)
  expect_identical(save_response(r, actor, enrollment, item, list(value = 7L, status = "answered"), 0L, "after extension")$revision, 1L)
  expect_identical(round_deadline(r, f$round$id)$state, "open")
  transition_round(r, f$manager, f$round$id, "closed", f$round$hash, "Close", "close")
  e <- tryCatch(change_round_deadline(r, f$manager, f$round$id, operations_stamp(3 * 86400), f$round$hash, "Synthetic", "closed"), error = function(e) e)
  expect_s3_class(e, "DEL_CONFLICT")
  expect_identical(e$path, "round.state")
  expect_error(save_response(r, actor, enrollment, item, list(value = 8L, status = "answered"), 1L, "closed"), class = "DEL_ROUND_CLOSED")
  expect_identical(round_deadline(r, f$round$id)$deadline, later)
})

test_that("the system status holds counts and ages only and names what needs attention", {
  r <- operations_repo()
  f <- operations_fixture(r, "closed")
  runtime <- operations_repo("delphyr_runtime")
  worker <- paste0("worker-test-", substr(uid(), 1, 8))
  expect_error(record_worker_heartbeat(runtime, "not a valid id"), class = "DEL_VALIDATION")
  record_worker_heartbeat(runtime, worker, started = TRUE)
  record_worker_heartbeat(runtime, worker)
  s <- get_system_status(runtime)
  expect_true(s$ready)
  expect_identical(s$schema$state, "current")
  expect_identical(s$schema$applied, s$schema$packaged)
  seen <- s$workers[s$workers$worker_id == worker, ]
  expect_identical(nrow(seen), 1L)
  expect_true(seen$seconds_since_seen <= 5L && seen$seconds_since_start <= 5L)
  expect_identical(seen$software_version, as.character(utils::packageVersion("delphyr")))
  expect_false("no_worker_alive" %in% s$attention)
  # A job that cannot succeed ends as a dead letter and is named.
  snapshot <- freeze_round(r, f$manager, f$round$id, "freeze")$id
  job <- request_export(r, f$manager, snapshot, "export")
  set_capability(r, f$manager, f$study_id, f$manager$principal_id, "export", FALSE, "revoke")
  expect_identical(worker_step(r, study_id = f$study_id)$error_code, "DEL_FORBIDDEN")
  s <- get_system_status(runtime)
  expect_true("dead_letter_jobs" %in% s$attention)
  expect_true(any(s$jobs$state == "dead_letter" & s$jobs$type == "export"))
  expect_true(all(c("type", "state", "n", "oldest_seconds") %in% names(s$jobs)))
  text <- as.character(jsonlite::toJSON(s, auto_unbox = TRUE))
  expect_false(any(vapply(c(f$study_id, f$code, job$id, f$manager$principal_id, snapshot), function(x) grepl(x, text, fixed = TRUE), logical(1))))
  # Database and software that do not match are not ready.
  packaged <- system.file("sql", package = "delphyr")
  directory <- tempfile("delphyr-migrations-")
  dir.create(directory)
  withr::defer(unlink(directory, recursive = TRUE))
  file.copy(list.files(packaged, full.names = TRUE), directory)
  writeLines("SELECT 1;", file.path(directory, "999_later.sql"))
  behind <- get_system_status(runtime, directory)
  expect_false(behind$ready)
  expect_identical(behind$schema$state, "behind")
  expect_true("schema_behind" %in% behind$attention)
  unlink(file.path(directory, "999_later.sql"))
  write("-- edited after it was applied", file.path(directory, "001_core.sql"), append = TRUE)
  expect_identical(get_system_status(runtime, directory)$schema$state, "changed")
  unlink(file.path(directory, list.files(directory)[-1]))
  ahead <- get_system_status(runtime, directory)
  expect_identical(ahead$schema$state, "ahead")
  expect_false(ahead$ready)
  # No answer from the database is reported, not raised.
  broken <- structure(list(con = NULL, environment = "test", artifact_root = tempdir()), class = "delphyr_repository")
  expect_identical(get_system_status(broken)[c("ready", "attention")], list(ready = FALSE, attention = "database_unreachable"))
  # A worker that was last seen long ago counts as silent.
  expect_true("no_worker_alive" %in% get_system_status(runtime, heartbeat_seconds = 1L)$attention || any(get_system_status(runtime, heartbeat_seconds = 1L)$workers$seconds_since_seen <= 1L))
})

test_that("only the files of expired exports are removed and the time is recorded", {
  r <- operations_repo()
  f <- operations_fixture(r, "closed")
  snapshot <- freeze_round(r, f$manager, f$round$id, "freeze")$id
  export <- function(key) {
    job <- request_export(r, f$manager, snapshot, key)
    result <- worker_step(r, study_id = f$study_id)
    stopifnot(identical(result$state, "succeeded"))
    result$result_ref
  }
  current <- export("current")
  expect_true(dir.exists(file.path(r$artifact_root, current)))
  expect_identical(nrow(remove_expired_artifacts(r, dry_run = FALSE, study_id = f$study_id)), 0L)
  expect_true(dir.exists(file.path(r$artifact_root, current)))
  # An export past its download period, registered with its files.
  expired <- uid()
  dir.create(file.path(r$artifact_root, expired))
  writeLines("synthetic export", file.path(r$artifact_root, expired, "manifest.json"))
  execute(r, "INSERT INTO ops.artifacts(id,study_id,actor_id,snapshot_id,storage_key,checksum,expires_at,profile) VALUES($1,$2,$3,$4,$1,'synthetic',clock_timestamp()-interval '1 hour','research_round')", expired, f$study_id, f$manager$principal_id, snapshot)
  lost <- uid()
  execute(r, "INSERT INTO ops.artifacts(id,study_id,actor_id,snapshot_id,storage_key,checksum,expires_at,profile) VALUES($1,$2,$3,$4,$1,'synthetic',clock_timestamp()-interval '2 hours','research_round')", lost, f$study_id, f$manager$principal_id, snapshot)
  expect_error(download_artifact(r, f$manager, expired), class = "DEL_NOT_FOUND")
  # The dry run reports and changes nothing.
  report <- remove_expired_artifacts(r, study_id = f$study_id)
  expect_identical(report$id, c(lost, expired))
  expect_identical(report$present, c(FALSE, TRUE))
  expect_identical(report$removed, c(FALSE, FALSE))
  expect_true(file.exists(file.path(r$artifact_root, expired, "manifest.json")))
  expect_identical(query(r, "SELECT count(*)::int AS n FROM ops.artifacts WHERE study_id=$1 AND removed_at IS NOT NULL", f$study_id)$n, 0L)
  expect_true(get_system_status(r)$artifacts$expired_not_removed >= 2L)
  applied <- remove_expired_artifacts(r, dry_run = FALSE, study_id = f$study_id)
  expect_identical(applied$removed, c(TRUE, TRUE))
  expect_false(dir.exists(file.path(r$artifact_root, expired)))
  expect_true(dir.exists(file.path(r$artifact_root, current)))
  expect_identical(query(r, "SELECT count(*)::int AS n FROM ops.artifacts WHERE study_id=$1 AND removed_at IS NOT NULL", f$study_id)$n, 2L)
  expect_identical(nrow(remove_expired_artifacts(r, dry_run = FALSE, study_id = f$study_id)), 0L)
  expect_true(file.exists(file.path(download_artifact(r, f$manager, current), "manifest.json")))
  # The registration is immutable apart from that one mark.
  expect_error(execute(r, "UPDATE ops.artifacts SET removed_at=NULL WHERE id=$1", expired))
  expect_error(execute(r, "UPDATE ops.artifacts SET checksum='changed' WHERE id=$1", current))
  expect_error(execute(r, "UPDATE ops.artifacts SET removed_at=clock_timestamp() WHERE id=$1", current))
  expect_error(execute(r, "DELETE FROM ops.artifacts WHERE id=$1", expired))
  # Without the private directory nothing is marked as removed.
  another <- uid()
  execute(r, "INSERT INTO ops.artifacts(id,study_id,actor_id,snapshot_id,storage_key,checksum,expires_at,profile) VALUES($1,$2,$3,$4,$1,'synthetic',clock_timestamp()-interval '1 hour','research_round')", another, f$study_id, f$manager$principal_id, snapshot)
  elsewhere <- r
  elsewhere$artifact_root <- file.path(tempdir(), paste0("absent-", uid()))
  expect_error(remove_expired_artifacts(elsewhere, dry_run = FALSE, study_id = f$study_id), class = "DEL_STORAGE")
  expect_identical(query(r, "SELECT removed_at IS NULL AS kept FROM ops.artifacts WHERE id=$1", another)$kept, TRUE)
  expect_error(remove_expired_artifacts(r, dry_run = NA), class = "DEL_VALIDATION")
  expect_error(remove_expired_artifacts(r, study_id = "not an id"), class = "DEL_NOT_FOUND")
})

test_that("the retention inventory counts and proposes; it deletes nothing", {
  r <- operations_repo()
  f <- operations_fixture(r, "open")
  csv <- paste("external_ref,email,display_name,locale,stakeholder_group", "R-1,retention-1@example.invalid,Synthetic One,en,professionals", "R-2,retention-2@example.invalid,Synthetic Two,en,professionals", sep = "\n")
  preview <- preview_panel_import(r, f$manager, f$study_id, csv)
  import_panel(r, f$manager, f$study_id, preview, preview$hash, "Synthetic contacts", "import")
  actor <- f$panel[[1]]
  enrollment <- list_enrollments(r, actor, f$study_id)$id
  item <- get_questionnaire(r, actor, enrollment)$items$id
  save_response(r, actor, enrollment, item, list(value = 7L, status = "answered"), 0L, "save")
  save_response(r, actor, enrollment, item, list(value = 8L, status = "answered"), 1L, "save again")
  count <- function() query(r, "SELECT (SELECT count(*) FROM identity.panel_contacts WHERE study_id=$1)::int AS contacts,(SELECT count(*) FROM research.response_revisions WHERE study_id=$1)::int AS revisions,(SELECT count(*) FROM ops.audit WHERE study_id=$1)::int AS audit", f$study_id)
  before <- count()
  x <- get_retention_report(r, f$manager, f$study_id)
  expect_identical(names(x), c("data_class", "records", "oldest", "newest", "period_days", "older_than_period"))
  n <- stats::setNames(x$records, x$data_class)
  expect_identical(n[["contacts"]], 2L)
  expect_identical(n[["contacts_without_accepted_invitation"]], 2L)
  expect_identical(n[["consent_records"]], 2L)
  expect_identical(n[["response_revisions"]], 2L)
  expect_identical(n[["frozen_snapshots"]], 0L)
  expect_identical(n[["audit_events"]], before$audit)
  expect_true(all(is.na(x$period_days)) && all(is.na(x$older_than_period)))
  expect_true(is.na(x$oldest[x$data_class == "frozen_snapshots"]))
  # A proposed period states what would be older; nothing is removed.
  proposed <- get_retention_report(r, f$manager, f$study_id, periods = c(contacts_without_accepted_invitation = 0, audit_events = 3650, response_revisions = 0))
  older <- stats::setNames(proposed$older_than_period, proposed$data_class)
  expect_identical(older[["contacts_without_accepted_invitation"]], 2L)
  expect_identical(older[["response_revisions"]], 2L)
  expect_identical(older[["audit_events"]], 0L)
  expect_true(is.na(older[["contacts"]]))
  expect_identical(count(), before)
  expect_error(get_retention_report(r, f$manager, f$study_id, periods = c(everything = 1)), class = "DEL_VALIDATION")
  expect_error(get_retention_report(r, f$manager, f$study_id, periods = c(contacts = -1)), class = "DEL_VALIDATION")
  expect_error(get_retention_report(r, f$panel[[1]], f$study_id), class = "DEL_FORBIDDEN")
  expect_error(get_retention_report(r, operations_fixture(r, "draft")$manager, f$study_id), class = "DEL_NOT_FOUND")
  # No contact, account or answer is part of the inventory.
  text <- paste(unlist(x), collapse = " ")
  expect_false(grepl("retention-1@example.invalid|Synthetic One", text))
})
