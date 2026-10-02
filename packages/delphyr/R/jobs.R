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
request_job <- function(repo, actor, snapshot_id, type, key) {
  transaction(repo, function() {
    valid_id(snapshot_id)
    s <- one(query(repo, "SELECT study_id FROM research.snapshots WHERE id=$1", snapshot_id))
    authorize(repo, actor, s$study_id, if (type == "export") "export" else "analyse")
    command(repo, actor, s$study_id, paste0("request_", type), key, list(snapshot_id), function() {
      # One analysis per requester and snapshot; a finished export does not
      # block a later request, while a duplicate pending request is merged.
      job <- if (type == "analysis") {
        query(repo, "INSERT INTO ops.jobs(id,study_id,actor_id,type,input_id,profile) VALUES($1,$2,$3,'analysis',$4,'analysis') ON CONFLICT(study_id,actor_id,input_id) WHERE type='analysis' AND state<>'dead_letter' DO UPDATE SET input_id=EXCLUDED.input_id RETURNING id,state", uid(), s$study_id, actor$principal_id, snapshot_id)
      } else {
        query(repo, "INSERT INTO ops.jobs(id,study_id,actor_id,type,input_id,profile) VALUES($1,$2,$3,'export',$4,'research_round') ON CONFLICT(study_id,actor_id,input_id,profile) WHERE type='export' AND state IN ('queued','running','retry_wait') DO UPDATE SET input_id=EXCLUDED.input_id RETURNING id,state", uid(), s$study_id, actor$principal_id, snapshot_id)
      }
      list(id = job$id, state = job$state)
    })
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
#' @return Operation id. Free-text exports require a separate reviewed profile.
#' @export
request_export <- function(repo, actor, snapshot_id, command_id) request_job(repo, actor, snapshot_id, "export", command_id)
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
#' @return Operation id and state.
#' @export
request_study_export <- function(repo, actor, study_id, profile, command_id) {
  ensure(scalar_text(profile), "export.profile")
  ensure(!identical(profile, "public_release"), "export.public_release_requires_separate_approval", "DEL_FORBIDDEN")
  ensure(profile %in% c("research_pseudonymized", "study_summary", "audit_restricted", "contacts_restricted"), "export.profile")
  transaction(repo, function() {
    admit(repo, actor, study_id, export_capability(profile))
    command(repo, actor, study_id, paste0("request_export:", profile), command_id, list(study_id, profile), function() {
      job <- query(repo, "INSERT INTO ops.jobs(id,study_id,actor_id,type,input_id,profile) VALUES($1,$2,$3,'export',$2,$4) ON CONFLICT(study_id,actor_id,input_id,profile) WHERE type='export' AND state IN ('queued','running','retry_wait') DO UPDATE SET input_id=EXCLUDED.input_id RETURNING id,state", uid(), study_id, actor$principal_id, profile)
      list(id = job$id, state = job$state)
    }, detail = profile)
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
write_export <- function(repo, actor, snapshot_id) {
  x <- one(query(repo, "SELECT study_id,content::text FROM research.snapshots WHERE id=$1", snapshot_id))
  authorize(repo, actor, x$study_id, "export")
  s <- read_snapshot(x$content)
  ensure(!any(vapply(config_scales(s$protocol), function(z) z$type == "free_text", logical(1))), "export.free_text_review_required", "DEL_FORBIDDEN")
  a <- analyse_round(s)
  dir.create(repo$artifact_root, recursive = TRUE, showWarnings = FALSE, mode = "0700")
  root <- normalizePath(repo$artifact_root, mustWork = TRUE)
  key <- uid()
  staging <- file.path(root, paste0(key, ".partial"))
  final <- file.path(root, key)
  dir.create(staging, mode = "0700")
  on.exit(if (dir.exists(staging)) unlink(staging, recursive = TRUE), add = TRUE)
  writeLines(snapshot_json(s), file.path(staging, "snapshot.json"), useBytes = TRUE)
  writeLines(json(s$protocol), file.path(staging, "protocol.json"), useBytes = TRUE)
  utils::write.csv(safe_csv(s$data), file.path(staging, "responses-spreadsheet.csv"), row.names = FALSE, na = "")
  revisions <- query(repo, "SELECT e.panelist_id,se.submission_id,v.round_item_id,v.revision AS response_revision,i.item_code,i.item_version,i.dimension_code FROM research.snapshot_entries se JOIN research.response_revisions v ON v.id=se.response_revision_id JOIN research.enrollments e ON e.id=se.enrollment_id JOIN research.round_items i ON i.id=v.round_item_id WHERE se.study_id=$1 AND se.snapshot_id=$2", x$study_id, snapshot_id)
  utils::write.csv(safe_csv(revisions), file.path(staging, "submission-provenance.csv"), row.names = FALSE, na = "")
  utils::write.csv(safe_csv(a$results), file.path(staging, "analysis-results.csv"), row.names = FALSE, na = "")
  writeLines(c("# Synthetischer Forschungsexport", "Keine Kontakte oder Kontozuordnungen. Pseudonyme sind nicht anonym.", "snapshot.json ist der ma\u00dfgebliche unver\u00e4nderte Datensatz; CSV-Texte sind formelsicher maskiert.", "Ausf\u00fchren: Rscript reproduce.R <Exportverzeichnis>. Freitextprofil nicht freigegeben.", "Schwellen sind synthetische Beispiele, keine methodische Empfehlung."), file.path(staging, "README.md"))
  writeLines(c("args <- commandArgs(trailingOnly=TRUE)", "path <- if(length(args)) args[1] else '.'", "result <- delphyr::reproduce_export(path)", "print(result$results)"), file.path(staging, "reproduce.R"))
  writeLines(json(a$provenance), file.path(staging, "provenance.json"))
  report_data <- prepare_report_data(repo, actor, snapshot_id)
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
    schema_version = "1.0", snapshot_hash = s$content_hash,
    result_hash = a$provenance$result_hash,
    software_version = as.character(utils::packageVersion("delphyr")),
    r_version = R.version.string,
    report = list(renderer = renderer, data_hash = report_data$content_hash)
  )
  manifest$files <- lapply(files, function(f) list(name = basename(f), sha256 = digest::digest(file = f, algo = "sha256"), bytes = file.info(f)$size))
  writeLines(json(manifest), file.path(staging, "manifest.json"))
  hash <- digest::digest(file = file.path(staging, "manifest.json"), algo = "sha256")
  ensure(file.rename(staging, final), "artifact.rename", "DEL_STORAGE")
  list(id = key, study_id = x$study_id, checksum = hash)
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
#' Process one leased job using its requester's current study rights
#' @param repo Trusted development/test worker repository.
#' @param study_id Optional study UUID limiting a worker partition.
#' @param lease_seconds Time the job is reserved for this worker. A job whose
#'   worker stopped is taken up again after that time; a job that needs longer
#'   cannot record its result. The default leaves a wide margin over the
#'   analysis and export of a round of 300 members and 300 rating fields.
#' @return FALSE when idle, otherwise a safe operation state.
#' @export
worker_step <- function(repo, study_id = NULL, lease_seconds = 600L) {
  started <- Sys.time()
  j <- claim_job(repo, lease_seconds = lease_seconds, study_id = study_id)
  if (!nrow(j)) {
    return(FALSE)
  }
  # A delegated actor is restricted to the requesting principal; services recheck rights.
  actor <- structure(list(principal_id = j$actor_id, expires_at = Sys.time() + 120), class = "delphyr_actor")
  out <- NULL
  registered <- FALSE
  result <- tryCatch(
    {
      out <- if (j$type == "analysis") {
        run_analysis(repo, actor, j$input_id, paste0("job-", j$id))
      } else if (j$profile == "research_round") {
        write_export(repo, actor, j$input_id)
      } else {
        write_study_export(repo, actor, j$input_id, j$profile)
      }
      transaction(repo, function() {
        current <- one(query(repo, "SELECT id FROM ops.jobs WHERE id=$1 AND lease_token=$2 AND state='running' AND lease_until>clock_timestamp() FOR UPDATE", j$id, j$lease_token))
        admit(repo, actor, j$study_id, job_capability(j$type, j$profile))
        if (j$type == "export") execute(repo, "INSERT INTO ops.artifacts(id,study_id,actor_id,snapshot_id,storage_key,checksum,expires_at,profile) VALUES($1,$2,$3,$4::uuid,$5,$6,clock_timestamp()+interval '1 day',$7)", out$id, j$study_id, j$actor_id, if (j$profile == "research_round") j$input_id else NA_character_, out$id, out$checksum, j$profile)
        execute(repo, "UPDATE ops.jobs SET state='succeeded',result_ref=$3,lease_until=NULL WHERE id=$1 AND lease_token=$2", current$id, j$lease_token, out$id)
        list(id = j$id, state = "succeeded", result_ref = out$id)
      })
    },
    error = function(e) {
      code <- if (inherits(e, "delphyr_error")) e$code else "DEL_STORAGE"
      permanent <- code %in% c("DEL_FORBIDDEN", "DEL_UNAUTHORIZED", "DEL_NOT_FOUND", "DEL_VALIDATION")
      execute(repo, "UPDATE ops.jobs SET state=CASE WHEN attempts>=3 OR $3 THEN 'dead_letter' ELSE 'retry_wait' END,error_code=$4,available_at=clock_timestamp()+interval '10 seconds',lease_until=NULL WHERE id=$1 AND lease_token=$2 AND state='running'", j$id, j$lease_token, permanent, code)
      list(id = j$id, state = "failed", error_code = code)
    }
  )
  if (j$type == "export" && !is.null(out) && !identical(result$state, "succeeded")) {
    path <- file.path(repo$artifact_root, out$id)
    if (dir.exists(path)) unlink(path, recursive = TRUE)
  }
  log_work(paste0("job.", j$type, if (j$type == "export") paste0(".", j$profile)), started, result$state, j$id, error_class = result$error_code)
  result
}
#' Resolve a private artifact only after a fresh rights check
#' @param repo Repository.
#' @param actor Original requesting actor with current export capability.
#' @param artifact_id Artifact UUID.
#' @return Private directory path for trusted server download code.
#' @export
download_artifact <- function(repo, actor, artifact_id) {
  valid_id(artifact_id)
  x <- one(query(repo, "SELECT * FROM ops.artifacts WHERE id=$1 AND expires_at>clock_timestamp() AND removed_at IS NULL", artifact_id))
  admit(repo, actor, x$study_id, export_capability(x$profile))
  ensure(x$actor_id == actor$principal_id, "artifact", "DEL_NOT_FOUND")
  valid_id(x$storage_key)
  root <- normalizePath(repo$artifact_root, mustWork = TRUE)
  path <- normalizePath(file.path(root, x$storage_key), mustWork = TRUE)
  ensure(startsWith(path, paste0(root, .Platform$file.sep)), "artifact.path", "DEL_STORAGE")
  ensure(identical(digest::digest(file = file.path(path, "manifest.json"), algo = "sha256"), x$checksum), "artifact.checksum", "DEL_STORAGE")
  # Every delivered file is checked; research profiles are also recomputed.
  verify_manifest(path)
  if (x$profile == "research_round") reproduce_export(path) else if (x$profile == "research_pseudonymized") reproduce_study_export(path)
  audit(repo, actor, x$study_id, "artifact_download", artifact_id, detail = x$profile)
  path
}
