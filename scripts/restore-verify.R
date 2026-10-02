# Function check of a restored database, called by scripts/restore-check.sh:
#   Rscript scripts/restore-verify.R <socket directory> [study id]
# The restored instance has no network; the connection uses its local socket.
# Prints one JSON object and exits with status 0 only if every check passed.
# The steps are those of docs/runbooks/backup-and-restore.md.
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
options(delphyr.log_level = "off")
arguments <- commandArgs(TRUE)
socket <- normalizePath(arguments[1], mustWork = TRUE)
connect <- function(user) connect_repository(host = socket, port = 5432L, dbname = "delphyr", user = user, environment = "test", artifact_root = tempfile("delphyr-restore-"))
owner <- connect("postgres")
checks <- list()

# The software finds its own schema: no migration is pending and none differs.
before <- query(owner, "SELECT count(*)::int AS n FROM ops.schema_migrations")$n
migrate_repository(owner)
checks$no_migration_pending <- identical(query(owner, "SELECT count(*)::int AS n FROM ops.schema_migrations")$n, before)

# Roles are not part of a dump: the restricted application role is set up anew.
configured <- system2("Rscript", "scripts/configure-dev-role.R", env = c(paste0("DELPHYR_DB_HOST=", socket), "DELPHYR_DB_PORT=5432"), stdout = FALSE, stderr = FALSE)
runtime <- if (identical(configured, 0L)) tryCatch(connect("delphyr_runtime"), error = function(e) NULL)
checks$application_role_configured <- !is.null(runtime)
if (is.null(runtime)) runtime <- owner
status <- get_system_status(runtime)
checks$status_ready_and_schema_current <- isTRUE(status$ready) && identical(status$schema$state, "current")

# Before any worker starts: what waited for delivery is held for a decision.
sink_receipts <- function() query(owner, "SELECT count(*)::int AS n FROM ops.message_sink")$n
receipts <- sink_receipts()
waiting <- hold_pending_messages(runtime)
held <- hold_pending_messages(runtime, dry_run = FALSE)
left <- hold_pending_messages(runtime)
checks$waiting_messages_held <- identical(held$held, waiting$queued + waiting$in_flight) && identical(left$queued + left$in_flight, 0L)
checks$worker_sends_nothing_unchecked <- identical(process_campaign_sink(runtime), FALSE) && identical(sink_receipts(), receipts)

# One study: a synthetic member signs in and reads the own round, staff read
# the rounds, and every frozen snapshot is verified and analysed again.
study <- if (length(arguments) > 1L && nzchar(arguments[2])) arguments[2] else NA_character_
if (is.na(study)) {
  study <- query(owner, "SELECT s.study_id FROM research.snapshots s JOIN research.analyses a ON a.study_id=s.study_id AND a.snapshot_id=s.id JOIN research.rounds r ON r.id=s.round_id
    WHERE EXISTS(SELECT 1 FROM identity.memberships m JOIN identity.principals p ON p.id=m.principal_id JOIN identity.capabilities c ON c.study_id=m.study_id AND c.membership_id=m.id
                 WHERE m.study_id=s.study_id AND m.active AND p.active AND p.issuer='urn:delphyr:demo' AND c.capability='analyse' AND c.revoked_at IS NULL)
    ORDER BY r.closed_at DESC NULLS LAST,s.id LIMIT 1")$study_id
}
checks$study_with_frozen_round_found <- length(study) == 1L && !is.na(study)
if (checks$study_with_frozen_round_found) {
  valid_id(study)
  account <- function(capability) query(owner, "SELECT p.id FROM identity.principals p JOIN identity.memberships m ON m.principal_id=p.id JOIN identity.capabilities c ON c.study_id=m.study_id AND c.membership_id=m.id WHERE m.study_id=$1 AND m.active AND p.active AND p.issuer='urn:delphyr:demo' AND c.capability=$2 AND c.revoked_at IS NULL ORDER BY p.id LIMIT 1", study, capability)$id
  member <- account("panel")
  staff <- account("analyse")
  checks$member_reads_own_round <- FALSE
  if (length(member)) {
    actor <- demo_actor(runtime, member)
    enrollments <- list_enrollments(runtime, actor, study)
    if (nrow(enrollments)) {
      own <- get_questionnaire(runtime, actor, enrollments$id[1])
      stored <- query(owner, "SELECT count(*)::int AS n FROM research.response_current WHERE enrollment_id=$1", enrollments$id[1])$n
      items <- query(owner, "SELECT count(*)::int AS n FROM research.round_items i JOIN research.enrollments e ON e.round_id=i.round_id WHERE e.id=$1", enrollments$id[1])$n
      checks$member_reads_own_round <- identical(nrow(own$responses), stored) && identical(nrow(own$items), items) && items > 0L
    }
  }
  checks$staff_read_rounds <- FALSE
  checks$snapshots_verified_and_reanalysed <- FALSE
  snapshots <- 0L
  if (length(staff)) {
    actor <- demo_actor(runtime, staff)
    rounds <- query(owner, "SELECT count(*)::int AS n FROM research.rounds WHERE study_id=$1", study)$n
    checks$staff_read_rounds <- tryCatch(identical(nrow(list_rounds(runtime, actor, study)), rounds) && rounds > 0L, error = function(e) FALSE)
    frozen <- query(owner, "SELECT id FROM research.snapshots WHERE study_id=$1 ORDER BY id", study)$id
    same <- vapply(frozen, function(id) {
      # Reading rebuilds the snapshot and compares its content hash.
      snapshot <- get_snapshot(runtime, actor, id)
      recorded <- query(owner, "SELECT hash FROM research.analyses WHERE study_id=$1 AND snapshot_id=$2", study, id)$hash
      length(recorded) > 0L && all(recorded == analyse_round(snapshot)$provenance$result_hash)
    }, logical(1))
    snapshots <- length(frozen)
    checks$snapshots_verified_and_reanalysed <- snapshots > 0L && all(same)
  }
}
passed <- all(vapply(checks, isTRUE, logical(1)))
cat(jsonlite::toJSON(list(
  passed = passed, checks = checks, messages_found_waiting = waiting$queued + waiting$in_flight, messages_held = held$held,
  study = if (isTRUE(checks$study_with_frozen_round_found)) study else NULL, snapshots_reanalysed = if (exists("snapshots")) snapshots else 0L
), auto_unbox = TRUE, null = "null"), "\n")
if (!identical(runtime, owner)) DBI::dbDisconnect(runtime$con)
DBI::dbDisconnect(owner$con)
quit(save = "no", status = if (passed) 0L else 1L)
