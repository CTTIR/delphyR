# Operation of an installation: heartbeat, status, the removal of expired
# exports and an inventory for retention decisions. None of these functions
# returns study content, a contact or an account reference.

#' Record that a worker process is alive
#' @param repo Trusted worker repository.
#' @param worker_id Stable name of the worker slot, for example "worker-1".
#' @param started TRUE when the process has just started.
#' @return Invisibly TRUE.
#' @export
record_worker_heartbeat <- function(repo, worker_id, started = FALSE) {
  ensure(scalar_text(worker_id) && grepl("^[A-Za-z0-9_.:-]{1,100}$", worker_id), "worker.id")
  ensure(is.logical(started) && length(started) == 1L && !is.na(started), "worker.started")
  execute(repo, "INSERT INTO ops.worker_heartbeats(worker_id,software_version) VALUES($1,$2) ON CONFLICT(worker_id) DO UPDATE SET last_seen_at=clock_timestamp(),software_version=EXCLUDED.software_version,started_at=CASE WHEN $3 THEN clock_timestamp() ELSE ops.worker_heartbeats.started_at END", worker_id, as.character(utils::packageVersion("delphyr")), started)
  invisible(TRUE)
}
#' Read the operational state of an installation
#'
#' For monitoring and the first look at an incident. The result holds counts
#' and ages only: no study content, contact, account or study identifier.
#' `ready` is TRUE when the database answers and its schema is exactly the
#' one this software version ships. `attention` lists what a person should
#' look at; it does not make the application unready.
#' @param repo Repository of the application or worker role.
#' @param path Directory of the packaged migrations.
#' @param heartbeat_seconds Age after which a worker counts as silent.
#' @return A list with `ready`, `schema`, `workers`, `jobs`, `messages`,
#'   `artifacts` and `attention`.
#' @export
get_system_status <- function(repo, path = system.file("sql", package = "delphyr"), heartbeat_seconds = 60L) {
  ensure(whole(heartbeat_seconds) && length(heartbeat_seconds) == 1L && heartbeat_seconds > 0, "status.heartbeat")
  files <- sort(list.files(path, pattern = "^[0-9]+.*[.]sql$", full.names = TRUE))
  packaged <- stats::setNames(vapply(files, function(f) digest::digest(file = f, algo = "sha256"), character(1)), basename(files))
  applied <- tryCatch(query(repo, "SELECT version,checksum FROM ops.schema_migrations ORDER BY version"), error = function(e) NULL)
  if (is.null(applied)) {
    return(list(ready = FALSE, schema = list(state = "unreachable", applied = 0L, packaged = length(packaged)), attention = "database_unreachable"))
  }
  known <- applied$version %in% names(packaged)
  state <- if (any(!known)) {
    "ahead"
  } else if (!all(applied$checksum == packaged[applied$version])) {
    "changed"
  } else if (nrow(applied) < length(packaged)) {
    "behind"
  } else {
    "current"
  }
  workers <- query(repo, "SELECT worker_id,software_version,round(extract(epoch FROM clock_timestamp()-last_seen_at))::int AS seconds_since_seen,round(extract(epoch FROM clock_timestamp()-started_at))::int AS seconds_since_start FROM ops.worker_heartbeats ORDER BY worker_id")
  jobs <- query(repo, "SELECT type,state,count(*)::int AS n,round(extract(epoch FROM clock_timestamp()-min(available_at)))::int AS oldest_seconds FROM ops.jobs WHERE state<>'succeeded' GROUP BY type,state ORDER BY type,state")
  messages <- query(repo, "SELECT state,count(*)::int AS n,round(extract(epoch FROM clock_timestamp()-min(updated_at)))::int AS oldest_seconds FROM ops.message_delivery WHERE state IN ('queued','running','delivery_unknown','failed') GROUP BY state ORDER BY state")
  artifacts <- query(repo, "SELECT count(*) FILTER (WHERE expires_at>clock_timestamp())::int AS available,count(*) FILTER (WHERE expires_at<=clock_timestamp() AND removed_at IS NULL)::int AS expired_not_removed,count(*) FILTER (WHERE removed_at IS NOT NULL)::int AS removed FROM ops.artifacts")
  waiting <- jobs[jobs$state %in% c("queued", "retry_wait"), , drop = FALSE]
  attention <- c(
    if (state != "current") paste0("schema_", state),
    if (!nrow(workers)) "no_worker_registered" else if (all(workers$seconds_since_seen > heartbeat_seconds)) "no_worker_alive",
    if (any(jobs$state == "dead_letter")) "dead_letter_jobs",
    if (nrow(waiting) && max(waiting$oldest_seconds) > 600) "jobs_waiting_long",
    if (any(messages$state == "delivery_unknown")) "uncertain_deliveries",
    if (artifacts$expired_not_removed > 0L) "expired_exports_not_removed"
  )
  list(
    ready = identical(state, "current"), schema = list(state = state, applied = nrow(applied), packaged = length(packaged)),
    workers = workers, jobs = jobs, messages = messages, artifacts = as.list(artifacts), attention = if (length(attention)) attention else character()
  )
}
#' Remove the files of exports whose download period has ended
#'
#' An export is a temporary private copy of data that stays in the database.
#' After `expires_at` it can no longer be downloaded; this function removes its
#' directory and records the time. It never touches research data, and without
#' `dry_run = FALSE` it removes nothing. An export whose files are already
#' absent from the private directory is recorded as removed as well.
#' @param repo Trusted worker repository with the artifact root of the worker.
#' @param dry_run TRUE lists what would be removed.
#' @param study_id Optional study UUID; otherwise every study.
#' @return A table of the expired exports: identifier, profile, expiry, whether
#'   files are present and whether the removal was recorded.
#' @export
remove_expired_artifacts <- function(repo, dry_run = TRUE, study_id = NULL) {
  ensure(is.logical(dry_run) && length(dry_run) == 1L && !is.na(dry_run), "artifacts.dry_run")
  if (!is.null(study_id)) valid_id(study_id)
  x <- query(repo, "SELECT id,storage_key,profile,expires_at::text AS expires_at FROM ops.artifacts WHERE expires_at<=clock_timestamp() AND removed_at IS NULL AND ($1::uuid IS NULL OR study_id=$1) ORDER BY expires_at,id", if (is.null(study_id)) NA_character_ else study_id)
  x$present <- logical(nrow(x))
  x$removed <- logical(nrow(x))
  columns <- c("id", "profile", "expires_at", "present", "removed")
  if (!nrow(x)) {
    return(x[, columns])
  }
  # A missing private directory is a wrong configuration, not removed files.
  ensure(dry_run || dir.exists(repo$artifact_root), "artifact.root", "DEL_STORAGE")
  root <- if (dir.exists(repo$artifact_root)) normalizePath(repo$artifact_root, mustWork = TRUE) else NA_character_
  for (i in seq_len(nrow(x))) {
    valid_id(x$storage_key[i])
    path <- if (is.na(root)) NA_character_ else file.path(root, x$storage_key[i])
    x$present[i] <- !is.na(path) && dir.exists(path)
    if (dry_run) next
    # The files go first: a registration marked removed never has files left.
    if (x$present[i]) {
      ensure(startsWith(normalizePath(path, mustWork = TRUE), paste0(root, .Platform$file.sep)), "artifact.path", "DEL_STORAGE")
      unlink(path, recursive = TRUE)
      ensure(!dir.exists(path), "artifact.remove", "DEL_STORAGE")
    }
    execute(repo, "UPDATE ops.artifacts SET removed_at=clock_timestamp() WHERE id=$1 AND removed_at IS NULL AND expires_at<=clock_timestamp()", x$id[i])
    x$removed[i] <- TRUE
  }
  rownames(x) <- NULL
  x[, columns]
}
#' Put messages that wait for delivery on hold for a human decision
#'
#' After a database was restored from a backup, a message that was waiting
#' when the backup was taken may have been delivered before the loss. This
#' function turns every message that is queued or in flight into an uncertain
#' delivery with the cause `restored_from_backup`. The worker then sends none
#' of them, and a coordinator decides for each one in the interface: delivery
#' confirmed, send again, or abandon. Run it before the worker is started on a
#' restored database. Without `dry_run = FALSE` it changes nothing.
#' @param repo Trusted worker repository.
#' @param dry_run TRUE counts what would be put on hold.
#' @param study_id Optional study UUID; otherwise every study.
#' @return A list with the numbers of messages `queued` and `in_flight` that
#'   were found and the number `held`, which is zero for a dry run.
#' @export
hold_pending_messages <- function(repo, dry_run = TRUE, study_id = NULL) {
  ensure(is.logical(dry_run) && length(dry_run) == 1L && !is.na(dry_run), "messages.dry_run")
  if (!is.null(study_id)) valid_id(study_id)
  study <- if (is.null(study_id)) NA_character_ else study_id
  transaction(repo, function() {
    found <- query(repo, "SELECT d.message_id,d.state FROM ops.message_delivery d JOIN ops.message_outbox o ON o.id=d.message_id WHERE d.state IN ('queued','running') AND ($1::uuid IS NULL OR o.study_id=$1) ORDER BY d.message_id FOR UPDATE OF d", study)
    held <- 0L
    if (!dry_run && nrow(found)) {
      held <- execute(repo, "UPDATE ops.message_delivery d SET state='delivery_unknown',reason='restored_from_backup',lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp() FROM ops.message_outbox o WHERE d.message_id=o.id AND d.state IN ('queued','running') AND ($1::uuid IS NULL OR o.study_id=$1)", study)
    }
    list(queued = sum(found$state == "queued"), in_flight = sum(found$state == "running"), held = as.integer(held))
  })
}
#' Inventory of a study's data for retention decisions
#'
#' Lists each class of stored data with its count and the age of its oldest
#' and newest record. With `periods`, a proposed number of days per class, it
#' also states how many records would be older than that period. It is a dry
#' run: nothing is deleted, and the software ships no retention periods. A
#' period is the decision of the responsible organisation.
#' @param repo Repository.
#' @param actor Actor with manage capability.
#' @param study_id Study UUID.
#' @param periods Optional named numeric vector of days per data class.
#' @return A table with data_class, records, oldest, newest, period_days and
#'   older_than_period.
#' @export
get_retention_report <- function(repo, actor, study_id, periods = NULL) {
  authorize(repo, actor, study_id, "manage")
  classes <- c(
    contacts = "SELECT r.imported_at AS at FROM identity.panel_contacts c JOIN identity.panel_import_receipts r ON r.study_id=c.study_id AND r.id=c.import_id WHERE c.study_id=$1",
    contacts_without_accepted_invitation = "SELECT r.imported_at AS at FROM identity.panel_contacts c JOIN identity.panel_import_receipts r ON r.study_id=c.study_id AND r.id=c.import_id JOIN identity.panel_invitation_drafts d ON d.study_id=c.study_id AND d.contact_id=c.id WHERE c.study_id=$1 AND NOT EXISTS(SELECT 1 FROM identity.panel_invitation_acceptances a WHERE a.study_id=d.study_id AND a.draft_id=d.id)",
    invitations = "SELECT created_at AS at FROM identity.panel_invitations WHERE study_id=$1",
    consent_records = "SELECT recorded_at AS at FROM identity.consents WHERE study_id=$1",
    response_revisions = "SELECT created_at AS at FROM research.response_revisions WHERE study_id=$1",
    free_text_originals = "SELECT created_at AS at FROM research.qualitative_sources WHERE study_id=$1",
    frozen_snapshots = "SELECT r.closed_at AS at FROM research.snapshots s JOIN research.rounds r ON r.id=s.round_id WHERE s.study_id=$1",
    campaign_messages = "SELECT created_at AS at FROM ops.message_outbox WHERE study_id=$1",
    audit_events = "SELECT occurred_at AS at FROM ops.audit WHERE study_id=$1",
    exports_with_files = "SELECT expires_at AS at FROM ops.artifacts WHERE study_id=$1 AND removed_at IS NULL"
  )
  ensure(is.null(periods) || (is.numeric(periods) && !is.null(names(periods)) && !anyDuplicated(names(periods)) && all(names(periods) %in% names(classes)) && all(is.finite(periods) & periods >= 0)), "retention.periods")
  rows <- lapply(names(classes), function(name) {
    days <- if (is.null(periods) || !name %in% names(periods)) NA_real_ else periods[[name]]
    x <- query(repo, paste0("SELECT count(*)::int AS records,min(at)::text AS oldest,max(at)::text AS newest,count(*) FILTER (WHERE $2::float8 IS NOT NULL AND at<clock_timestamp()-$2::float8*interval '1 day')::int AS older FROM (", classes[[name]], ") x"), study_id, days)
    data.frame(data_class = name, records = x$records, oldest = x$oldest, newest = x$newest, period_days = days, older_than_period = if (is.na(days)) NA_integer_ else x$older, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}
