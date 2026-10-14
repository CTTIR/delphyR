# Capability that admits each export profile. The contact export is a separate
# right; the audit export is open to the audit role and to study management.
export_capability <- function(profile) {
  capabilities <- list(
    research_round = "export", research_pseudonymized = "export", study_summary = c("analyse", "manage"),
    audit_restricted = c("audit", "manage"), contacts_restricted = "contacts_export"
  )
  ensure(is.character(profile) && length(profile) == 1L && profile %in% names(capabilities), "export.profile")
  capabilities[[profile]]
}
job_capability <- function(type, profile) if (identical(type, "analysis")) "analyse" else export_capability(profile)
admit <- function(repo, actor, study_id, capability) {
  if (length(capability) > 1L) authorize_any(repo, actor, study_id, capability) else authorize(repo, actor, study_id, capability)
}
# An export is bound to what it is for: one text of 10 to 500 characters,
# recorded as the rationale of the request and written into the manifest.
valid_purpose <- function(purpose) {
  ensure(is.null(purpose) || isTRUE(tryCatch(scalar_text(purpose) && nchar(trimws(purpose)) >= 10L && nchar(purpose) <= 500L, error = function(e) FALSE)), "export.purpose")
}
# A purpose is part of the request: the same key with another purpose is a
# conflict. Requests without one keep their earlier payload.
export_payload <- function(payload, purpose) if (is.null(purpose)) payload else c(payload, list(purpose))
request_job <- function(repo, actor, snapshot_id, type, key, purpose = NULL) {
  transaction(repo, function() {
    valid_id(snapshot_id)
    s <- one(query(repo, "SELECT study_id FROM research.snapshots WHERE id=$1", snapshot_id))
    authorize(repo, actor, s$study_id, if (type == "export") "export" else "analyse")
    command(repo, actor, s$study_id, paste0("request_", type), key, export_payload(list(snapshot_id), purpose), function() {
      # One analysis per requester and snapshot; a finished export does not
      # block a later request, while a duplicate pending request is merged.
      job <- if (type == "analysis") {
        query(repo, "INSERT INTO ops.jobs(id,study_id,actor_id,type,input_id,profile) VALUES($1,$2,$3,'analysis',$4,'analysis') ON CONFLICT(study_id,actor_id,input_id) WHERE type='analysis' AND state<>'dead_letter' DO UPDATE SET input_id=EXCLUDED.input_id RETURNING id,state", uid(), s$study_id, actor$principal_id, snapshot_id)
      } else {
        query(repo, "INSERT INTO ops.jobs(id,study_id,actor_id,type,input_id,profile) VALUES($1,$2,$3,'export',$4,'research_round') ON CONFLICT(study_id,actor_id,input_id,profile) WHERE type='export' AND state IN ('queued','running','retry_wait') DO UPDATE SET input_id=EXCLUDED.input_id RETURNING id,state", uid(), s$study_id, actor$principal_id, snapshot_id)
      }
      list(id = job$id, state = job$state)
    }, reason = purpose)
  })
}
#' Queue a durable analysis operation
#' @param repo Repository.
#' @param actor Actor with analyse capability.
#' @param snapshot_id Immutable snapshot UUID.
#' @param command_id Idempotency key.
#' @return Operation id.
#' @export
request_analysis <- function(repo, actor, snapshot_id, command_id) request_job(repo, actor, snapshot_id, "analysis", command_id)
#' Queue a private pseudonymized numeric research export
#' @param repo Repository.
#' @param actor Actor with export capability.
#' @param snapshot_id Immutable snapshot UUID.
#' @param command_id Idempotency key.
#' @param purpose What the export is for, 10 to 500 characters. It is
#'   recorded as the rationale of the request in the audit trail and written
#'   into the manifest of the export, under `purposes`. A request merged into
#'   a pending export of the same snapshot adds its purpose there.
#' @return Operation id. Free-text exports require a separate reviewed profile.
#' @export
request_export <- function(repo, actor, snapshot_id, command_id, purpose = NULL) {
  valid_purpose(purpose)
  request_job(repo, actor, snapshot_id, "export", command_id, purpose)
}
#' Queue a private study-level export for one profile
#'
#' Profiles separate what leaves the system and who may request it:
#' research_pseudonymized (export capability) holds every frozen round with
#' pseudonyms, decisions, lineage and reviewed qualitative records;
#' study_summary (analyse or manage) holds aggregates only;
#' audit_restricted (audit or manage) holds events and approvals without
#' response content; contacts_restricted (contacts_export) holds contact
#' fields without pseudonyms. A public release is not produced by the software.
#' @param repo Repository.
#' @param actor Actor holding the capability of the requested profile.
#' @param study_id Study UUID.
#' @param profile research_pseudonymized, study_summary, audit_restricted or
#'   contacts_restricted.
#' @param command_id Idempotency key.
#' @param purpose What the export is for, 10 to 500 characters; see
#'   request_export().
#' @return Operation id and state.
#' @export
request_study_export <- function(repo, actor, study_id, profile, command_id, purpose = NULL) {
  ensure(scalar_text(profile), "export.profile")
  ensure(!identical(profile, "public_release"), "export.public_release_requires_separate_approval", "DEL_FORBIDDEN")
  ensure(profile %in% c("research_pseudonymized", "study_summary", "audit_restricted", "contacts_restricted"), "export.profile")
  valid_purpose(purpose)
  transaction(repo, function() {
    admit(repo, actor, study_id, export_capability(profile))
    command(repo, actor, study_id, paste0("request_export:", profile), command_id, export_payload(list(study_id, profile), purpose), function() {
      job <- query(repo, "INSERT INTO ops.jobs(id,study_id,actor_id,type,input_id,profile) VALUES($1,$2,$3,'export',$2,$4) ON CONFLICT(study_id,actor_id,input_id,profile) WHERE type='export' AND state IN ('queued','running','retry_wait') DO UPDATE SET input_id=EXCLUDED.input_id RETURNING id,state", uid(), study_id, actor$principal_id, profile)
      list(id = job$id, state = job$state)
    }, reason = purpose, detail = profile)
  })
}
#' Retrieve an authorized operation state
#' @param repo Repository.
#' @param actor Requesting actor.
#' @param operation_id Operation UUID.
#' @return State, result reference and safe error code.
#' @export
get_operation <- function(repo, actor, operation_id) {
  valid_id(operation_id)
  x <- one(query(repo, "SELECT id,study_id,actor_id,type,profile,state,result_ref,error_code FROM ops.jobs WHERE id=$1", operation_id))
  admit(repo, actor, x$study_id, job_capability(x$type, x$profile))
  ensure(x$actor_id == actor$principal_id, "operation", "DEL_NOT_FOUND")
  x[, c("id", "state", "result_ref", "error_code"), drop = FALSE]
}
#' Claim one available durable job with an exclusive lease
#' @param repo Trusted worker repository.
#' @param study_id Optional study UUID limiting a worker partition.
#' @param lease_seconds Lease duration, between 1 and 3600 seconds.
#' @return Claimed row or empty data frame. Worker infrastructure API.
#' @export
claim_job <- function(repo, lease_seconds = 120, study_id = NULL) {
  transaction(repo, function() {
    ensure(whole(lease_seconds) && length(lease_seconds) == 1 && lease_seconds > 0 && lease_seconds <= 3600, "lease")
    if (!is.null(study_id)) valid_id(study_id)
    study_param <- if (is.null(study_id)) NA_character_ else study_id
    execute(repo, "UPDATE ops.jobs SET state='dead_letter',error_code='DEL_LEASE_EXHAUSTED',lease_until=NULL WHERE state='running' AND attempts>=3 AND lease_until<clock_timestamp() AND ($1::uuid IS NULL OR study_id=$1)", study_param)
    query(repo, "WITH candidate AS (SELECT id FROM ops.jobs WHERE ($3::uuid IS NULL OR study_id=$3) AND attempts<3 AND ((state IN ('queued','retry_wait') AND available_at<=clock_timestamp()) OR (state='running' AND lease_until<clock_timestamp())) ORDER BY available_at,id FOR UPDATE SKIP LOCKED LIMIT 1) UPDATE ops.jobs j SET state='running',attempts=attempts+1,lease_token=$1,lease_until=clock_timestamp()+$2*interval '1 second' FROM candidate c WHERE j.id=c.id RETURNING j.*", uid(), lease_seconds, study_param)
  })
}
safe_csv <- function(x) {
  for (n in names(x)) {
    if (is.character(x[[n]])) {
      bad <- grepl("^[[:space:]]*[=+@-]", x[[n]])
      x[[n]][bad & !is.na(bad)] <- paste0("'", x[[n]][bad & !is.na(bad)])
    }
  }
  x
}
# Writes a round export under a temporary name, `<id>.partial`. The worker
# gives it its final name only after the export is registered.
write_export <- function(repo, actor, snapshot_id) {
  x <- one(query(repo, "SELECT s.study_id,s.content::text,st.code AS study_code,to_char(r.closed_at AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS closed_at,p.hash AS configuration_hash FROM research.snapshots s JOIN research.studies st ON st.id=s.study_id JOIN research.rounds r ON r.id=s.round_id JOIN research.protocol_versions p ON p.id=r.protocol_id WHERE s.id=$1", snapshot_id))
  authorize(repo, actor, x$study_id, "export")
  s <- read_snapshot(x$content)
  ensure(!any(vapply(config_scales(s$protocol), function(z) z$type == "free_text", logical(1))), "export.free_text_review_required", "DEL_FORBIDDEN")
  # Every right is checked before the long work; the worker checks it again
  # when it records the result.
  report_data <- prepare_report_data(repo, actor, snapshot_id)
  revisions <- query(repo, "SELECT e.panelist_id,se.submission_id,v.round_item_id,v.revision AS response_revision,i.item_code,i.item_version,i.dimension_code FROM research.snapshot_entries se JOIN research.response_revisions v ON v.id=se.response_revision_id JOIN research.enrollments e ON e.id=se.enrollment_id JOIN research.round_items i ON i.id=v.round_item_id WHERE se.study_id=$1 AND se.snapshot_id=$2", x$study_id, snapshot_id)
  a <- analyse_round(s)
  dir.create(repo$artifact_root, recursive = TRUE, showWarnings = FALSE, mode = "0700")
  root <- normalizePath(repo$artifact_root, mustWork = TRUE)
  key <- uid()
  staging <- file.path(root, paste0(key, ".partial"))
  dir.create(staging, mode = "0700")
  written <- FALSE
  on.exit(if (!written && dir.exists(staging)) unlink(staging, recursive = TRUE), add = TRUE)
  writeLines(snapshot_json(s), file.path(staging, "snapshot.json"), useBytes = TRUE)
  writeLines(json(s$protocol), file.path(staging, "protocol.json"), useBytes = TRUE)
  utils::write.csv(safe_csv(s$data), file.path(staging, "responses-spreadsheet.csv"), row.names = FALSE, na = "")
  utils::write.csv(safe_csv(revisions), file.path(staging, "submission-provenance.csv"), row.names = FALSE, na = "")
  utils::write.csv(safe_csv(a$results), file.path(staging, "analysis-results.csv"), row.names = FALSE, na = "")
  writeLines(c("# Synthetischer Forschungsexport", "Keine Kontakte oder Kontozuordnungen. Pseudonyme sind nicht anonym.", "snapshot.json ist der ma\u00dfgebliche unver\u00e4nderte Datensatz; CSV-Texte sind formelsicher maskiert.", "Ausf\u00fchren: Rscript reproduce.R <Exportverzeichnis>. Freitextprofil nicht freigegeben.", "Schwellen sind synthetische Beispiele, keine methodische Empfehlung."), file.path(staging, "README.md"))
  writeLines(c("args <- commandArgs(trailingOnly=TRUE)", "path <- if(length(args)) args[1] else '.'", "result <- delphyr::reproduce_export(path)", "print(result$results)"), file.path(staging, "reproduce.R"))
  # The time of the export is kept apart from the time of its data: the
  # frozen round's close.
  exported_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  provenance <- list(
    export_schema_version = "1.0", profile = "research_round", study_id = x$study_id, study_code = x$study_code,
    snapshot_id = snapshot_id, round_number = s$round_number, exported_at = exported_at, data_as_of = x$closed_at,
    timezone = s$protocol$study$timezone, configuration_hash = x$configuration_hash, software = study_software(),
    analysis = a$provenance
  )
  writeLines(json(provenance), file.path(staging, "provenance.json"), useBytes = TRUE)
  write_report_data(report_data, staging)
  # Only a missing optional runtime permits the basic report fallback.
  rendered <- tryCatch(
    {
      render_study_report(report_data, staging)
      TRUE
    },
    DEL_DEPENDENCY = function(e) FALSE
  )
  renderer <- if (rendered) "quarto_html" else "basic_html_missing_quarto_runtime"
  if (!rendered) {
    # A portable HTML report escapes every data value; interpretation is never invented.
    esc <- function(x) {
      x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
      x <- gsub("<", "&lt;", x, fixed = TRUE)
      gsub(">", "&gt;", x, fixed = TRUE)
    }
    rows <- apply(a$results[, c("item_code", "dimension_code", "stratum", "n_valid", "classification")], 1, function(v) paste0("<tr>", paste0("<td>", esc(v), "</td>", collapse = ""), "</tr>"))
    writeLines(c('<!doctype html><html lang="en"><meta charset="utf-8"><title>delphyR - synthetic report</title><main><h1>Synthetic study report</h1><p>Basic HTML fallback: optional Quarto runtime unavailable. Development evidence only. Scientific interpretation and institutional information: not documented.</p><table><caption>Immutable analysis results</caption><thead><tr><th>Item</th><th>Dimension</th><th>Group</th><th>Valid n</th><th>Classification</th></tr></thead><tbody>', rows, "</tbody></table></main></html>"), file.path(staging, "report.html"))
  }
  files <- list.files(staging, full.names = TRUE)
  manifest <- list(
    schema_version = "1.0", profile = "research_round", study_id = x$study_id, snapshot_id = snapshot_id, round_number = s$round_number,
    exported_at = exported_at, data_as_of = x$closed_at, snapshot_hash = s$content_hash,
    result_hash = a$provenance$result_hash,
    software_version = as.character(utils::packageVersion("delphyr")),
    r_version = R.version.string,
    report = list(renderer = renderer, data_hash = report_data$content_hash)
  )
  # Each data file names the version of its own schema; documents for
  # people have none.
  schemas <- c(snapshot.json = s$schema_version, protocol.json = s$protocol$schema_version, "report-data.json" = report_data$schema_version)
  manifest$files <- lapply(files, function(f) {
    name <- basename(f)
    schema <- if (name %in% names(schemas)) schemas[[name]] else if (grepl("[.](csv|json)$", name)) "1.0"
    c(list(name = name, sha256 = digest::digest(file = f, algo = "sha256"), bytes = file.info(f)$size), if (!is.null(schema)) list(schema_version = schema))
  })
  writeLines(json(manifest), file.path(staging, "manifest.json"))
  hash <- digest::digest(file = file.path(staging, "manifest.json"), algo = "sha256")
  written <- TRUE
  list(id = key, study_id = x$study_id, checksum = hash)
}
# The directory of an export: its final name, or its temporary one until it
# is registered and renamed. A worker stopped between the registration and the
# renaming leaves a registered export under the temporary name.
export_directory <- function(repo, key) {
  final <- file.path(repo$artifact_root, key)
  if (dir.exists(final)) final else paste0(final, ".partial")
}
# Binds an export to its request: the stated purposes of the requests it
# answers join the manifest, whose checksum is registered.
bind_export_manifest <- function(path, purposes) {
  file <- file.path(path, "manifest.json")
  manifest <- from_json(paste(readLines(file, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
  manifest$purposes <- as.list(purposes)
  writeLines(json(manifest), file, useBytes = TRUE)
  digest::digest(file = file, algo = "sha256")
}
# The stated purposes of the requests merged into a job, in request order.
export_purposes <- function(repo, j) {
  x <- query(repo, "SELECT reason FROM ops.audit WHERE study_id=$1 AND object_ref=$2 AND action IN ('request_export',$3) AND reason IS NOT NULL ORDER BY occurred_at,id", j$study_id, j$id, paste0("request_export:", j$profile))
  unique(x$reason)
}
# Checks every listed file of an export against its recorded SHA-256. On the
# server the directory must hold exactly the listed files.
verify_manifest <- function(path, exact = TRUE) {
  ensure(scalar_text(path) && file.exists(file.path(path, "manifest.json")), "manifest.missing")
  manifest <- from_json(paste(readLines(file.path(path, "manifest.json"), warn = FALSE), collapse = "\n"))
  ensure(is.list(manifest$files) && length(manifest$files) > 0L, "manifest.files")
  for (f in manifest$files) {
    ensure(scalar_text(f$name) && identical(basename(f$name), f$name) && !f$name %in% c(".", ".."), "manifest.path")
    ensure(file.exists(file.path(path, f$name)) && identical(digest::digest(file = file.path(path, f$name), algo = "sha256"), f$sha256), "manifest.checksum")
  }
  listed <- vapply(manifest$files, function(f) f$name, character(1))
  if (exact) ensure(setequal(c(listed, "manifest.json"), list.files(path)), "manifest.unlisted_file")
  manifest
}
#' Verify and reproduce a portable research export without a database
#' @param path Export directory under the user's control.
#' @return Recomputed delphyr_analysis after all listed checksums match.
#' @export
reproduce_export <- function(path) {
  manifest <- verify_manifest(path, exact = FALSE)
  s <- read_snapshot(paste(readLines(file.path(path, "snapshot.json"), warn = FALSE), collapse = "\n"))
  a <- analyse_round(s)
  ensure(identical(s$content_hash, manifest$snapshot_hash) && identical(a$provenance$result_hash, manifest$result_hash), "reproduction")
  a
}
#' Renew the reservation of a running job
#'
#' A worker process that is still working on a job keeps it reserved: the
#' reservation is extended to `lease_seconds` from now, as long as it has not
#' ended yet. The requester's rights are checked again when the result is
#' recorded, with an identity that lasts as long as the reservation.
#' @param repo Trusted worker repository.
#' @param job_id Job UUID of a claim, see the `on_claim` hook of worker_step().
#' @param lease_token Lease token of that claim.
#' @param lease_seconds New reservation from now, between 1 and 3600 seconds.
#' @return TRUE when the reservation was renewed; FALSE when it had ended or
#'   the job is no longer held by that claim. Worker infrastructure API.
#' @export
renew_job_lease <- function(repo, job_id, lease_token, lease_seconds = 600L) {
  ensure(whole(lease_seconds) && length(lease_seconds) == 1L && lease_seconds > 0 && lease_seconds <= 3600, "lease")
  valid_id(job_id)
  valid_id(lease_token)
  identical(execute(repo, "UPDATE ops.jobs SET lease_until=clock_timestamp()+$3*interval '1 second' WHERE id=$1 AND lease_token=$2 AND state='running' AND lease_until>clock_timestamp()", job_id, lease_token, lease_seconds), 1L)
}
# The requester's identity, delegated to one claim of a job. Services read
# `expires_at` when they check rights; it is taken from the reservation in
# the database each time, so a renewal extends it, a lost reservation ends it,
# and the worker's clock is never compared with the database's.
delegated_actor <- function(repo, j) {
  actor <- new.env(parent = emptyenv())
  actor$principal_id <- j$actor_id
  makeActiveBinding("expires_at", function() {
    left <- query(repo, "SELECT extract(epoch FROM lease_until-clock_timestamp())::float8 AS s FROM ops.jobs WHERE id=$1 AND lease_token=$2 AND state='running'", j$id, j$lease_token)$s
    Sys.time() + if (length(left) == 1L && !is.na(left)) left else -1
  }, actor)
  class(actor) <- "delphyr_actor"
  actor
}
#' Process one leased job using its requester's current study rights
#'
#' The requester's identity is delegated for exactly as long as this worker
#' holds the job's reservation, as the database measures it: renewing the
#' reservation (renew_job_lease()) extends it, and it ends when the
#' reservation ends or another worker takes the job up. A refusal that a retry
#' cannot change (`DEL_FORBIDDEN`, `DEL_UNAUTHORIZED`, `DEL_NOT_FOUND`,
#' `DEL_VALIDATION`) ends the job; any other failure, including a report that
#' could not be rendered (`DEL_RENDER`) and a reservation that ended before
#' the result was recorded (`DEL_CONFLICT` with path `job.lease`), is retried
#' after ten seconds, up to three attempts. A rights check refused because
#' the reservation had ended counts as such a lost reservation (`DEL_CONFLICT`),
#' not as a refusal of the requester. An export is written under a temporary
#' name and gets its final name only after it is registered; one that cannot
#' be registered is removed, whatever failed.
#' @param repo Trusted development/test worker repository.
#' @param study_id Optional study UUID limiting a worker partition.
#' @param lease_seconds Time the job is reserved for this worker. A job whose
#'   worker stopped is taken up again after that time; a job that needs longer
#'   cannot record its result unless its reservation is renewed. The default
#'   leaves a wide margin over the analysis and export of a round of 300
#'   members and 300 rating fields.
#' @param download_hours Hours an export can be downloaded after it was
#'   registered, from 1 to 720; one day by default. The period is the
#'   decision of the responsible organisation.
#' @param on_claim Optional function called with the claimed job (a one-row
#'   data frame with `id` and `lease_token`) before it runs, for example to
#'   renew its reservation from another process.
#' @return FALSE when idle, otherwise a safe operation state.
#' @export
worker_step <- function(repo, study_id = NULL, lease_seconds = 600L, download_hours = 24, on_claim = NULL) {
  ensure(is.numeric(download_hours) && length(download_hours) == 1L && is.finite(download_hours) && download_hours >= 1 && download_hours <= 720, "export.download_hours")
  ensure(is.null(on_claim) || is.function(on_claim), "worker.on_claim")
  started <- Sys.time()
  j <- claim_job(repo, lease_seconds = lease_seconds, study_id = study_id)
  if (!nrow(j)) {
    return(FALSE)
  }
  if (!is.null(on_claim)) on_claim(j)
  # A delegated actor is restricted to the requesting principal and to this
  # claim of the job; services recheck rights.
  actor <- delegated_actor(repo, j)
  out <- NULL
  registered <- FALSE
  # An export leaves this function registered or not at all, also when the
  # recording of a failure fails.
  on.exit(if (j$type == "export" && !is.null(out) && !registered) unlink(file.path(repo$artifact_root, paste0(out$id, c(".partial", ""))), recursive = TRUE), add = TRUE)
  result <- tryCatch(
    {
      out <- if (j$type == "analysis") {
        run_analysis(repo, actor, j$input_id, paste0("job-", j$id))
      } else if (j$profile == "research_round") {
        write_export(repo, actor, j$input_id)
      } else {
        write_study_export(repo, actor, j$input_id, j$profile)
      }
      recorded <- transaction(repo, function() {
        current <- query(repo, "SELECT id FROM ops.jobs WHERE id=$1 AND lease_token=$2 AND state='running' AND lease_until>clock_timestamp() FOR UPDATE", j$id, j$lease_token)
        # A job that outlived its reservation records nothing; another worker
        # may have taken it up.
        ensure(nrow(current) == 1L, "job.lease", "DEL_CONFLICT")
        admit(repo, actor, j$study_id, job_capability(j$type, j$profile))
        if (j$type == "export") {
          checksum <- bind_export_manifest(export_directory(repo, out$id), export_purposes(repo, j))
          execute(repo, "INSERT INTO ops.artifacts(id,study_id,actor_id,snapshot_id,storage_key,checksum,expires_at,profile) VALUES($1,$2,$3,$4::uuid,$5,$6,clock_timestamp()+$8*interval '1 hour',$7)", out$id, j$study_id, j$actor_id, if (j$profile == "research_round") j$input_id else NA_character_, out$id, checksum, j$profile, download_hours)
        }
        execute(repo, "UPDATE ops.jobs SET state='succeeded',result_ref=$3,lease_until=NULL WHERE id=$1 AND lease_token=$2", current$id, j$lease_token, out$id)
        list(id = j$id, state = "succeeded", result_ref = out$id)
      })
      registered <- TRUE
      recorded
    },
    error = function(e) {
      code <- if (inherits(e, "delphyr_error")) e$code else "DEL_STORAGE"
      # An identity that ended with the reservation is a lost reservation,
      # not a refusal of the requester.
      if (identical(code, "DEL_UNAUTHORIZED") && !isTRUE(Sys.time() < actor$expires_at)) code <- "DEL_CONFLICT"
      permanent <- code %in% c("DEL_FORBIDDEN", "DEL_UNAUTHORIZED", "DEL_NOT_FOUND", "DEL_VALIDATION")
      execute(repo, "UPDATE ops.jobs SET state=CASE WHEN attempts>=3 OR $3 THEN 'dead_letter' ELSE 'retry_wait' END,error_code=$4,available_at=clock_timestamp()+interval '10 seconds',lease_until=NULL WHERE id=$1 AND lease_token=$2 AND state='running'", j$id, j$lease_token, permanent, code)
      list(id = j$id, state = "failed", error_code = code)
    }
  )
  # A registered export gets its final name now. A worker stopped before the
  # registration leaves an unregistered temporary directory, which the cleanup
  # removes; one stopped after it leaves a registered export that is
  # delivered from its temporary name.
  staging <- if (registered && j$type == "export") file.path(repo$artifact_root, paste0(out$id, ".partial")) else ""
  if (dir.exists(staging) && !file.rename(staging, file.path(repo$artifact_root, out$id))) log_work("job.export.publish", started, "failed", out$id, error_class = "DEL_STORAGE")
  log_work(paste0("job.", j$type, if (j$type == "export") paste0(".", j$profile)), started, result$state, j$id, error_class = result$error_code)
  result
}
#' Resolve a private artifact only after a fresh rights check
#' @param repo Repository.
#' @param actor Original requesting actor with current export capability.
#' @param artifact_id Artifact UUID.
#' @return Private directory path for trusted server download code. An export
#'   whose worker stopped after registering it but before giving it its final
#'   name is delivered from its temporary name, `<id>.partial`.
#' @export
download_artifact <- function(repo, actor, artifact_id) {
  valid_id(artifact_id)
  x <- one(query(repo, "SELECT * FROM ops.artifacts WHERE id=$1 AND expires_at>clock_timestamp() AND removed_at IS NULL", artifact_id))
  admit(repo, actor, x$study_id, export_capability(x$profile))
  ensure(x$actor_id == actor$principal_id, "artifact", "DEL_NOT_FOUND")
  valid_id(x$storage_key)
  directory <- export_directory(repo, x$storage_key)
  ensure(dir.exists(directory), "artifact", "DEL_NOT_FOUND")
  root <- normalizePath(repo$artifact_root, mustWork = TRUE)
  path <- normalizePath(directory, mustWork = TRUE)
  ensure(startsWith(path, paste0(root, .Platform$file.sep)), "artifact.path", "DEL_STORAGE")
  ensure(identical(digest::digest(file = file.path(path, "manifest.json"), algo = "sha256"), x$checksum), "artifact.checksum", "DEL_STORAGE")
  # Every delivered file is checked; research profiles are also recomputed.
  verify_manifest(path)
  if (x$profile == "research_round") reproduce_export(path) else if (x$profile == "research_pseudonymized") reproduce_study_export(path)
  audit(repo, actor, x$study_id, "artifact_download", artifact_id, detail = x$profile)
  path
}
