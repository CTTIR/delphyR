#' Connect to an explicitly configured PostgreSQL database
#' @param ... Arguments passed to DBI::dbConnect(RPostgres::Postgres()).
#' @param environment Development or test; production is not qualified.
#' @param artifact_root Private directory for generated artifacts.
#' @return A delphyr repository. Close its connection with DBI::dbDisconnect(repo$con).
#' @export
connect_repository <- function(..., environment = c("development", "test"), artifact_root = tempfile("delphyr-artifacts-")) {
  environment <- match.arg(environment)
  ensure(requireNamespace("RPostgres", quietly = TRUE), "RPostgres", "DEL_DEPENDENCY")
  con <- DBI::dbConnect(RPostgres::Postgres(), ...)
  structure(list(con = con, environment = environment, artifact_root = artifact_root), class = "delphyr_repository")
}
query <- function(repo, sql, ...) {
  result <- DBI::dbSendQuery(repo$con, sql)
  on.exit(DBI::dbClearResult(result))
  params <- list(...)
  if (length(params)) DBI::dbBind(result, params)
  DBI::dbFetch(result)
}
execute <- function(repo, sql, ...) {
  result <- DBI::dbSendStatement(repo$con, sql)
  on.exit(DBI::dbClearResult(result))
  params <- list(...)
  if (length(params)) DBI::dbBind(result, params)
  DBI::dbGetRowsAffected(result)
}
one <- function(x) {
  ensure(nrow(x) == 1, "object", "DEL_NOT_FOUND")
  x
}
uid <- function() uuid::UUIDgenerate()
valid_id <- function(x) ensure(scalar_text(x) && grepl("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", x), "object", "DEL_NOT_FOUND")
transaction <- function(repo, code) {
  tryCatch(DBI::dbWithTransaction(repo$con, code()), error = function(e) {
    if (inherits(e, "delphyr_error")) stop(e)
    del_abort("DEL_STORAGE", "transaction")
  })
}
#' Apply checksummed forward migrations
#' @param repo Repository connected as migration owner.
#' @param path Directory of SQL migrations, normally installed package resources.
#' @return Invisibly TRUE. Changed historical migration files are rejected.
#' @export
migrate_repository <- function(repo, path = system.file("sql", package = "delphyr")) {
  files <- sort(list.files(path, pattern = "^[0-9]+.*[.]sql$", full.names = TRUE))
  ensure(length(files) > 0, "migrations")
  DBI::dbWithTransaction(repo$con, {
    DBI::dbExecute(repo$con, "SELECT pg_advisory_xact_lock(492103881)")
    exists <- !is.na(DBI::dbGetQuery(repo$con, "SELECT to_regclass('ops.schema_migrations')::text AS x")$x)
    applied <- if (exists) DBI::dbGetQuery(repo$con, "SELECT * FROM ops.schema_migrations") else data.frame(version = character(), checksum = character())
    for (f in files) {
      h <- digest::digest(file = f, algo = "sha256")
      v <- basename(f)
      old <- applied[applied$version == v, , drop = FALSE]
      if (nrow(old)) {
        ensure(identical(old$checksum, h), "migration.checksum", "DEL_CONFLICT")
      } else {
        DBI::dbExecute(repo$con, paste(readLines(f, warn = FALSE), collapse = "\n"), immediate = TRUE)
        execute(repo, "INSERT INTO ops.schema_migrations(version,checksum) VALUES($1,$2)", v, h)
      }
    }
  })
  invisible(TRUE)
}
#' Provision a synthetic development principal
#' @param repo Development/test repository, using a provisioning connection.
#' @param subject Synthetic account name, prefixed demo-.
#' @param can_create Allow creating demo studies.
#' @return Principal UUID. This is not a production authentication adapter.
#' @export
provision_demo_principal <- function(repo, subject, can_create = FALSE) {
  ensure(repo$environment %in% c("development", "test") && scalar_text(subject) && grepl("^demo-", subject), "demo.identity", "DEL_FORBIDDEN")
  x <- query(repo, "INSERT INTO identity.principals(id,issuer,subject,can_create) VALUES($1,'urn:delphyr:demo',$2,$3) ON CONFLICT(issuer,subject) DO UPDATE SET subject=EXCLUDED.subject RETURNING id", uid(), subject, can_create)
  x$id
}
#' Create a short-lived, server-side demo actor
#' @param repo Development/test repository.
#' @param principal_id Provisioned synthetic principal UUID.
#' @param lifetime_seconds Positive session duration, at most one hour.
#' @return Actor context for trusted server code, never accepted from browser payloads.
#' @export
demo_actor <- function(repo, principal_id, lifetime_seconds = 3600) {
  ensure(repo$environment %in% c("development", "test"), "demo.actor", "DEL_FORBIDDEN")
  valid_id(principal_id)
  ensure(is.numeric(lifetime_seconds) && length(lifetime_seconds) == 1 && is.finite(lifetime_seconds) && lifetime_seconds > 0 && lifetime_seconds <= 3600, "session.duration")
  p <- one(query(repo, "SELECT id FROM identity.principals WHERE id=$1 AND issuer='urn:delphyr:demo' AND active", principal_id))
  structure(list(principal_id = p$id, expires_at = Sys.time() + lifetime_seconds), class = "delphyr_actor")
}
identity_check <- function(repo, actor) {
  ensure(inherits(actor, "delphyr_actor") && length(actor$expires_at) == 1 && isTRUE(Sys.time() < actor$expires_at), "session", "DEL_UNAUTHORIZED")
  valid_id(actor$principal_id)
  p <- query(repo, "SELECT * FROM identity.principals WHERE id=$1 AND active", actor$principal_id)
  ensure(nrow(p) == 1, "session", "DEL_UNAUTHORIZED")
  p
}
authorize <- function(repo, actor, study_id, capability = NULL) {
  identity_check(repo, actor)
  valid_id(study_id)
  m <- query(repo, "SELECT id FROM identity.memberships WHERE study_id=$1 AND principal_id=$2 AND active", study_id, actor$principal_id)
  ensure(nrow(m) == 1, "study", "DEL_NOT_FOUND")
  if (!is.null(capability)) {
    c <- query(repo, "SELECT capability FROM identity.capabilities WHERE study_id=$1 AND membership_id=$2 AND revoked_at IS NULL", study_id, m$id)
    ensure(capability %in% c$capability, "capability", "DEL_FORBIDDEN")
  }
  m$id
}
audit <- function(repo, actor, study, action, object) execute(repo, "INSERT INTO ops.audit(id,study_id,actor_id,action,object_ref) VALUES($1,$2,$3,$4,$5)", uid(), study, actor$principal_id, action, as.character(object))
command <- function(repo, actor, study, type, key, payload, fun) {
  ensure(scalar_text(key) && nchar(key) <= 200, "command_id")
  # Serialize retries of one command without blocking independent participants.
  lock <- paste(study, actor$principal_id, type, key, sep = ":")
  query(repo, "SELECT pg_advisory_xact_lock(hashtextextended($1,0))", lock)
  # Admission follows every potentially blocking service lock. A revocation
  # committed before this check wins; already admitted transactions may finish.
  capability <- c(
    create_study = "manage", amend_protocol = "manage", capability = "manage", publish_consent = "manage",
    consent = "panel", add_panelist = "manage", prepare_round = "manage", transition_round = "manage",
    save = "panel", submit = "panel", freeze = "manage", analyse = "analyse", feedback_draft = "analyse",
    release_feedback = "manage", assign_feedback = "manage", decision = "manage",
    request_analysis = "analyse", request_export = "export", complete_study = "manage",
    qualitative_source = "edit", qualitative_edit = "edit", qualitative_release = "manage",
    qualitative_theme = "edit", qualitative_code = "edit", qualitative_item_source = "edit",
    qualitative_lineage = "manage", campaign_prepare = "coordinate",
    campaign_release = "coordinate", campaign_cancel = "coordinate", panel_import = "coordinate", invitation_issue = "coordinate", invitation_revoke = "coordinate", withdraw_participation = "panel", panel_group = "manage"
  )[[type]]
  authorize(repo, actor, study, capability)
  h <- content_hash(payload)
  old <- query(repo, "SELECT payload_hash,outcome::text FROM ops.commands WHERE study_id=$1 AND actor_id=$2 AND command_type=$3 AND command_key=$4", study, actor$principal_id, type, key)
  if (nrow(old)) {
    ensure(identical(old$payload_hash, h), "command.payload", "DEL_CONFLICT")
    return(jsonlite::fromJSON(old$outcome, simplifyVector = TRUE))
  }
  result <- fun()
  execute(repo, "INSERT INTO ops.commands VALUES($1,$2,$3,$4,$5,$6::jsonb)", study, actor$principal_id, type, key, h, json(result))
  audit(repo, actor, study, type, if (!is.null(result$id)) result$id else study)
  result
}
#' Create an isolated synthetic study and its first immutable protocol
#' @param repo Repository.
#' @param actor Authorized server actor.
#' @param protocol Validated demo protocol.
#' @param command_id Idempotency key.
#' @return Study id and protocol id.
#' @export
create_study <- function(repo, actor, protocol, command_id) {
  transaction(repo, function() {
    p <- identity_check(repo, actor)
    ensure(isTRUE(p$can_create), "create", "DEL_FORBIDDEN")
    protocol <- new_protocol(protocol)
    query(repo, "SELECT pg_advisory_xact_lock(hashtextextended($1,0))", paste0("study:", protocol$study$code))
    old <- query(repo, "SELECT id FROM research.studies WHERE code=$1", protocol$study$code)
    if (nrow(old)) {
      study <- old$id
      authorize(repo, actor, study, "manage")
    } else {
      study <- uid()
      member <- uid()
      execute(repo, "INSERT INTO research.studies(id,code,title) VALUES($1,$2,$3)", study, protocol$study$code, protocol$study$title)
      execute(repo, "INSERT INTO identity.memberships(id,study_id,principal_id) VALUES($1,$2,$3)", member, study, actor$principal_id)
      for (cap in c("manage", "analyse", "export", "coordinate", "edit")) execute(repo, "INSERT INTO identity.capabilities(study_id,membership_id,capability) VALUES($1,$2,$3)", study, member, cap)
    }
    command(repo, actor, study, "create_study", command_id, protocol, function() {
      ensure(!nrow(old), "study.exists", "DEL_CONFLICT")
      id <- uid()
      execute(repo, "INSERT INTO research.protocol_versions VALUES($1,$2,1,$3::jsonb,$4)", id, study, json(protocol), content_hash(protocol))
      list(id = study, protocol_id = id)
    })
  })
}
#' Assign or revoke a study capability
#' @param repo Repository.
#' @param actor Study manager.
#' @param study_id Study UUID.
#' @param principal_id Principal UUID.
#' @param capability One of manage, analyse, export, coordinate, edit, panel, audit.
#' @param enabled Grant if TRUE; revoke otherwise.
#' @param command_id Idempotency key.
#' @return Membership id.
#' @export
set_capability <- function(repo, actor, study_id, principal_id, capability, enabled, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "manage")
    valid_id(principal_id)
    ensure(capability %in% c("manage", "analyse", "export", "coordinate", "edit", "panel", "audit") && is.logical(enabled) && length(enabled) == 1 && !is.na(enabled), "capability")
    command(repo, actor, study_id, "capability", command_id, list(principal_id, capability, enabled), function() {
      m <- query(repo, "INSERT INTO identity.memberships(id,study_id,principal_id) VALUES($1,$2,$3) ON CONFLICT(study_id,principal_id) DO UPDATE SET principal_id=EXCLUDED.principal_id RETURNING id", uid(), study_id, principal_id)$id
      execute(repo, "INSERT INTO identity.capabilities(study_id,membership_id,capability,revoked_at) VALUES($1,$2,$3,CASE WHEN $4 THEN NULL ELSE clock_timestamp() END) ON CONFLICT(study_id,membership_id,capability) DO UPDATE SET revoked_at=EXCLUDED.revoked_at", study_id, m, capability, enabled)
      list(id = m)
    })
  })
}
#' List studies available to the current actor
#' @param repo Repository.
#' @param actor Server actor.
#' @return Study table without contacts or response data.
#' @export
list_studies <- function(repo, actor) {
  identity_check(repo, actor)
  query(repo, "SELECT s.id,s.code,s.title,s.state FROM research.studies s JOIN identity.memberships m ON m.study_id=s.id WHERE m.principal_id=$1 AND m.active ORDER BY s.code", actor$principal_id)
}
#' Read current study capabilities
#' @param repo Repository.
#' @param actor Server actor.
#' @param study_id Study UUID.
#' @return Character vector; this UI hint does not replace service authorization.
#' @export
get_capabilities <- function(repo, actor, study_id) {
  m <- authorize(repo, actor, study_id)
  query(repo, "SELECT capability FROM identity.capabilities WHERE study_id=$1 AND membership_id=$2 AND revoked_at IS NULL", study_id, m)$capability
}
