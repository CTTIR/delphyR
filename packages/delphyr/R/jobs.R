request_job <- function(repo, actor, snapshot_id, type, key) {
  transaction(repo, function() {
    valid_id(snapshot_id)
    s <- one(query(repo, "SELECT study_id FROM research.snapshots WHERE id=$1", snapshot_id))
    authorize(repo, actor, s$study_id, if (type == "export") "export" else "analyse")
    command(repo, actor, s$study_id, paste0("request_", type), key, list(snapshot_id), function() {
      job <- query(repo, "INSERT INTO ops.jobs(id,study_id,actor_id,type,input_id) VALUES($1,$2,$3,$4,$5) ON CONFLICT(study_id,actor_id,type,input_id) DO UPDATE SET input_id=EXCLUDED.input_id RETURNING id,state", uid(), s$study_id, actor$principal_id, type, snapshot_id)
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
#' Retrieve an authorized operation state
#' @param repo Repository.
#' @param actor Requesting actor.
#' @param operation_id Operation UUID.
#' @return State, result reference and safe error code.
#' @export
get_operation <- function(repo, actor, operation_id) {
  valid_id(operation_id)
  x <- one(query(repo, "SELECT id,study_id,actor_id,type,state,result_ref,error_code FROM ops.jobs WHERE id=$1", operation_id))
  authorize(repo, actor, x$study_id, if (x$type == "export") "export" else "analyse")
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
  files <- list.files(staging, full.names = TRUE)
  manifest <- list(schema_version = "1.0", snapshot_hash = s$content_hash, result_hash = a$provenance$result_hash, software_version = as.character(utils::packageVersion("delphyr")), r_version = R.version.string, files = lapply(files, function(f) list(name = basename(f), sha256 = digest::digest(file = f, algo = "sha256"), bytes = file.info(f)$size)))
  writeLines(json(manifest), file.path(staging, "manifest.json"))
  # A portable HTML report escapes every data value; interpretation is never invented.
  esc <- function(x) {
    x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    gsub(">", "&gt;", x, fixed = TRUE)
  }
  rows <- apply(a$results[, c("item_code", "dimension_code", "stratum", "n_valid", "classification")], 1, function(v) paste0("<tr>", paste0("<td>", esc(v), "</td>", collapse = ""), "</tr>"))
  writeLines(c('<!doctype html><html lang="de"><meta charset="utf-8"><title>delphyR \u2013 synthetischer Bericht</title><main><h1>Synthetischer Studienbericht</h1><p>Entwicklungsnachweis. Fachliche Interpretation und institutionelle Angaben: nicht dokumentiert.</p><table><caption>Unver\u00e4nderlicher Analysestand</caption><thead><tr><th>Item</th><th>Dimension</th><th>Gruppe</th><th>G\u00fcltiges n</th><th>Klassifikation</th></tr></thead><tbody>', rows, "</tbody></table></main></html>"), file.path(staging, "report.html"))
  files <- list.files(staging, full.names = TRUE)
  files <- files[basename(files) != "manifest.json"]
  manifest$files <- lapply(files, function(f) list(name = basename(f), sha256 = digest::digest(file = f, algo = "sha256"), bytes = file.info(f)$size))
  writeLines(json(manifest), file.path(staging, "manifest.json"))
  hash <- digest::digest(file = file.path(staging, "manifest.json"), algo = "sha256")
  ensure(file.rename(staging, final), "artifact.rename", "DEL_STORAGE")
  list(id = key, study_id = x$study_id, checksum = hash)
}
#' Verify and reproduce a portable research export without a database
#' @param path Export directory under the user's control.
#' @return Recomputed delphyr_analysis after all listed checksums match.
#' @export
reproduce_export <- function(path) {
  manifest <- from_json(paste(readLines(file.path(path, "manifest.json"), warn = FALSE), collapse = "\n"))
  for (f in manifest$files) {
    ensure(scalar_text(f$name) && identical(basename(f$name), f$name) && !f$name %in% c(".", ".."), "manifest.path")
    ensure(identical(digest::digest(file = file.path(path, f$name), algo = "sha256"), f$sha256), "manifest.checksum")
  }
  s <- read_snapshot(paste(readLines(file.path(path, "snapshot.json"), warn = FALSE), collapse = "\n"))
  a <- analyse_round(s)
  ensure(identical(s$content_hash, manifest$snapshot_hash) && identical(a$provenance$result_hash, manifest$result_hash), "reproduction")
  a
}
#' Process one leased job using its requester's current study rights
#' @param repo Trusted development/test worker repository.
#' @param study_id Optional study UUID limiting a worker partition.
#' @return FALSE when idle, otherwise a safe operation state.
#' @export
worker_step <- function(repo, study_id = NULL) {
  j <- claim_job(repo, study_id = study_id)
  if (!nrow(j)) {
    return(FALSE)
  }
  # A delegated actor is restricted to the requesting principal; services recheck rights.
  actor <- structure(list(principal_id = j$actor_id, expires_at = Sys.time() + 120), class = "delphyr_actor")
  out <- NULL
  registered <- FALSE
  result <- tryCatch(
    {
      if (j$type == "analysis") out <- run_analysis(repo, actor, j$input_id, paste0("job-", j$id)) else out <- write_export(repo, actor, j$input_id)
      transaction(repo, function() {
        current <- one(query(repo, "SELECT id FROM ops.jobs WHERE id=$1 AND lease_token=$2 AND state='running' AND lease_until>clock_timestamp() FOR UPDATE", j$id, j$lease_token))
        authorize(repo, actor, j$study_id, if (j$type == "export") "export" else "analyse")
        if (j$type == "export") execute(repo, "INSERT INTO ops.artifacts VALUES($1,$2,$3,$4,$5,$6,clock_timestamp()+interval '1 day')", out$id, j$study_id, j$actor_id, j$input_id, out$id, out$checksum)
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
  x <- one(query(repo, "SELECT * FROM ops.artifacts WHERE id=$1 AND expires_at>clock_timestamp()", artifact_id))
  authorize(repo, actor, x$study_id, "export")
  ensure(x$actor_id == actor$principal_id, "artifact", "DEL_NOT_FOUND")
  valid_id(x$storage_key)
  root <- normalizePath(repo$artifact_root, mustWork = TRUE)
  path <- normalizePath(file.path(root, x$storage_key), mustWork = TRUE)
  ensure(startsWith(path, paste0(root, .Platform$file.sep)), "artifact.path", "DEL_STORAGE")
  ensure(identical(digest::digest(file = file.path(path, "manifest.json"), algo = "sha256"), x$checksum), "artifact.checksum", "DEL_STORAGE")
  reproduce_export(path)
  audit(repo, actor, x$study_id, "artifact_download", artifact_id)
  path
}
