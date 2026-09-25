# Portable JSON retains tables, explicit nulls and the declarative protocol.
snapshot_json <- function(s) json(list(responses = s$data[s$data$submitted, c("panelist_id", "item_code", "item_version", "dimension_code", "answer_status", "value_integer", "value_text"), drop = FALSE], assignments = unique(s$data[, c("panelist_id", "group_code", "submitted"), drop = FALSE]), items = s$items, protocol = s$protocol, round_number = s$round_number, snapshot_id = s$snapshot_id, content_hash = s$content_hash))
read_snapshot <- function(value) {
  x <- jsonlite::fromJSON(value, simplifyVector = TRUE)
  p <- from_json(value)$protocol
  r <- x$responses
  if (!is.data.frame(r)) r <- data.frame(panelist_id = character(), item_code = character(), item_version = integer(), dimension_code = character(), answer_status = character(), value_integer = integer(), value_text = character())
  r$value_text <- as.character(r$value_text)
  r$value_integer <- as.integer(r$value_integer)
  x$items$item_version <- as.integer(x$items$item_version)
  s <- new_snapshot(r, x$assignments, x$items, p, x$round_number, x$snapshot_id)
  ensure(identical(s$content_hash, x$content_hash), "snapshot.hash")
  s
}
#' Freeze the exact submitted revision set of a closed round
#' @param repo Repository.
#' @param actor Study manager.
#' @param round_id Closed round UUID.
#' @param command_id Idempotency key.
#' @return Immutable snapshot UUID and content hash.
#' @export
freeze_round <- function(repo, actor, round_id, command_id) {
  transaction(repo, function() {
    r <- round_get(repo, actor, round_id, "manage", " FOR UPDATE")
    command(repo, actor, r$study_id, "freeze", command_id, list(round_id), function() {
      ensure(r$state == "closed", "round.state", "DEL_CONFLICT")
      assignments <- query(repo, "SELECT e.panelist_id,e.group_code,(s.id IS NOT NULL) AS submitted FROM research.enrollments e LEFT JOIN research.submissions s ON s.study_id=e.study_id AND s.enrollment_id=e.id WHERE e.study_id=$1 AND e.round_id=$2 ORDER BY e.panelist_id", r$study_id, r$id)
      items <- query(repo, "SELECT item_code,item_version,dimension_code,scale_code FROM research.round_items WHERE study_id=$1 AND round_id=$2 ORDER BY item_code,dimension_code", r$study_id, r$id)
      responses <- query(repo, "SELECT e.panelist_id,i.item_code,i.item_version,i.dimension_code,v.status AS answer_status,v.value_int AS value_integer,v.value_text FROM research.submission_entries se JOIN research.response_revisions v ON v.id=se.response_revision_id JOIN research.enrollments e ON e.id=se.enrollment_id JOIN research.round_items i ON i.id=v.round_item_id WHERE se.study_id=$1 AND se.round_id=$2", r$study_id, r$id)
      p <- from_json(one(query(repo, "SELECT config::text FROM research.protocol_versions WHERE id=$1", r$protocol_id))$config)
      id <- uid()
      s <- new_snapshot(responses, assignments, items, p, r$number, id)
      execute(repo, "INSERT INTO research.snapshots VALUES($1,$2,$3,$4::jsonb,$5)", id, r$study_id, r$id, snapshot_json(s), s$content_hash)
      execute(repo, "INSERT INTO research.snapshot_entries SELECT study_id,round_id,$3,enrollment_id,submission_id,response_revision_id FROM research.submission_entries WHERE study_id=$1 AND round_id=$2", r$study_id, r$id, id)
      execute(repo, "UPDATE research.rounds SET state='frozen' WHERE id=$1", r$id)
      list(id = id, hash = s$content_hash)
    })
  })
}
#' Retrieve a frozen snapshot through current study authorization
#' @param repo Repository.
#' @param actor Actor with analyse capability.
#' @param snapshot_id Snapshot UUID.
#' @return Validated delphyr_snapshot.
#' @export
get_snapshot <- function(repo, actor, snapshot_id) {
  valid_id(snapshot_id)
  x <- one(query(repo, "SELECT study_id,content::text FROM research.snapshots WHERE id=$1", snapshot_id))
  authorize(repo, actor, x$study_id, "analyse")
  read_snapshot(x$content)
}
#' Analyse and persist a frozen snapshot
#' @param repo Repository.
#' @param actor Actor with analyse capability.
#' @param snapshot_id Snapshot UUID.
#' @param command_id Idempotency key.
#' @return Analysis UUID and scientific result hash.
#' @export
run_analysis <- function(repo, actor, snapshot_id, command_id) {
  transaction(repo, function() {
    valid_id(snapshot_id)
    x <- one(query(repo, "SELECT study_id,round_id,content::text FROM research.snapshots WHERE id=$1", snapshot_id))
    r <- round_get(repo, actor, x$round_id, "analyse", " FOR UPDATE")
    command(repo, actor, x$study_id, "analyse", command_id, list(snapshot_id), function() {
      ensure(r$state %in% c("frozen", "analysed", "released", "finalized"), "round.state", "DEL_CONFLICT")
      a <- analyse_round(read_snapshot(x$content))
      id <- uid()
      execute(repo, "INSERT INTO research.analyses VALUES($1,$2,$3,$4::jsonb,$5)", id, x$study_id, snapshot_id, json(a), a$provenance$result_hash)
      execute(repo, "UPDATE research.rounds SET state='analysed' WHERE id=$1 AND state='frozen'", r$id)
      list(id = id, hash = a$provenance$result_hash)
    })
  })
}
#' Read a persisted aggregate analysis
#' @param repo Repository.
#' @param actor Actor with analyse capability.
#' @param analysis_id Analysis UUID.
#' @return delphyr_analysis.
#' @export
get_analysis <- function(repo, actor, analysis_id) {
  valid_id(analysis_id)
  x <- one(query(repo, "SELECT study_id,content::text FROM research.analyses WHERE id=$1", analysis_id))
  authorize(repo, actor, x$study_id, "analyse")
  structure(jsonlite::fromJSON(x$content), class = "delphyr_analysis")
}
#' Create a reviewed feedback candidate from a frozen analysis
#' @param repo Repository.
#' @param actor Actor with analyse capability.
#' @param analysis_id Analysis UUID.
#' @param qualitative Reviewed summaries.
#' @param command_id Idempotency key.
#' @return Feedback UUID and hash, requiring separate release.
#' @export
create_feedback <- function(repo, actor, analysis_id, qualitative = list(), command_id) {
  transaction(repo, function() {
    a <- get_analysis(repo, actor, analysis_id)
    x <- one(query(repo, "SELECT study_id,snapshot_id FROM research.analyses WHERE id=$1", analysis_id))
    s <- get_snapshot(repo, actor, x$snapshot_id)
    policy <- s$protocol$feedback[c("group_statistics", "minimum_display_cell_n", "complementary_suppression")]
    f <- prepare_feedback(a, qualitative, policy)
    command(repo, actor, x$study_id, "feedback_draft", command_id, list(analysis_id, qualitative), function() {
      id <- uid()
      execute(repo, "INSERT INTO research.feedback(id,study_id,analysis_id,content,hash) VALUES($1,$2,$3,$4::jsonb,$5)", id, x$study_id, analysis_id, json(f), f$hash)
      list(id = id, hash = f$hash)
    })
  })
}
#' Release an exact reviewed feedback candidate
#' @param repo Repository.
#' @param actor Study manager.
#' @param feedback_id Feedback UUID.
#' @param expected_hash Exact reviewed content hash.
#' @param command_id Idempotency key.
#' @return Feedback UUID.
#' @export
release_feedback <- function(repo, actor, feedback_id, expected_hash, command_id) {
  transaction(repo, function() {
    valid_id(feedback_id)
    f <- one(query(repo, "SELECT f.*,s.round_id FROM research.feedback f JOIN research.analyses a ON a.id=f.analysis_id JOIN research.snapshots s ON s.id=a.snapshot_id WHERE f.id=$1", feedback_id))
    r <- round_get(repo, actor, f$round_id, "manage", " FOR UPDATE")
    command(repo, actor, f$study_id, "release_feedback", command_id, list(feedback_id, expected_hash), function() {
      ensure(f$hash == expected_hash && f$state == "reviewed" && r$state == "analysed", "feedback.release", "DEL_CONFLICT")
      execute(repo, "UPDATE research.feedback SET state='released' WHERE id=$1", f$id)
      execute(repo, "UPDATE research.rounds SET state='released' WHERE id=$1", r$id)
      list(id = f$id)
    })
  })
}
#' Assign released feedback to an unopened subsequent round
#' @param repo Repository.
#' @param actor Study manager.
#' @param round_id Target round.
#' @param feedback_id Released feedback in the same study.
#' @param command_id Idempotency key.
#' @return Target round UUID.
#' @export
assign_feedback <- function(repo, actor, round_id, feedback_id, command_id) {
  transaction(repo, function() {
    r <- round_get(repo, actor, round_id, "manage", " FOR UPDATE")
    valid_id(feedback_id)
    command(repo, actor, r$study_id, "assign_feedback", command_id, list(round_id, feedback_id), function() {
      ensure(r$state %in% c("draft", "review", "approved"), "round.state", "DEL_CONFLICT")
      f <- one(query(repo, "SELECT f.id,pr.number FROM research.feedback f JOIN research.analyses a ON a.id=f.analysis_id JOIN research.snapshots s ON s.id=a.snapshot_id JOIN research.rounds pr ON pr.id=s.round_id WHERE f.id=$1 AND f.study_id=$2 AND f.state='released'", feedback_id, r$study_id))
      ensure(f$number < r$number, "feedback.source_round")
      execute(repo, "INSERT INTO research.feedback_assignments SELECT study_id,round_id,id,$3 FROM research.enrollments WHERE study_id=$1 AND round_id=$2", r$study_id, r$id, feedback_id)
      list(id = r$id)
    })
  })
}
#' Read released aggregate feedback plus only the actor's prior answers
#' @param repo Repository.
#' @param actor Panel actor.
#' @param enrollment_id Own target enrollment.
#' @return Aggregate feedback and own prior response table, or NULL.
#' @export
get_feedback <- function(repo, actor, enrollment_id) {
  transaction(repo, function() {
    z <- enrollment_get(repo, actor, enrollment_id, FALSE)
    e <- z$enrollment
    f <- query(repo, "SELECT f.id,f.content::text,s.content::text AS snapshot FROM research.feedback_assignments fa JOIN research.feedback f ON f.study_id=fa.study_id AND f.id=fa.feedback_id JOIN research.analyses a ON a.id=f.analysis_id JOIN research.snapshots s ON s.id=a.snapshot_id WHERE fa.study_id=$1 AND fa.enrollment_id=$2 AND f.state='released'", e$study_id, e$id)
    if (!nrow(f)) {
      return(NULL)
    }
    s <- read_snapshot(f$snapshot)
    own <- s$data[s$data$panelist_id == e$panelist_id, c("item_code", "item_version", "dimension_code", "answer_status", "value_integer", "value_text"), drop = FALSE]
    if (!isTRUE(s$protocol$feedback$own_previous_rating)) own <- own[FALSE, , drop = FALSE]
    audit(repo, actor, e$study_id, "feedback_displayed", f$id)
    list(id = f$id, aggregate = jsonlite::fromJSON(f$content), own = own)
  })
}
#' List study round states and frozen result references
#' @param repo Repository.
#' @param actor Study manager or analyst.
#' @param study_id Study UUID.
#' @return Round table.
#' @export
list_rounds <- function(repo, actor, study_id) {
  authorize(repo, actor, study_id, "manage")
  query(repo, "SELECT r.id,r.number,r.state,r.instrument_hash,r.deadline,s.id AS snapshot_id,(SELECT a.id FROM research.analyses a WHERE a.snapshot_id=s.id ORDER BY a.id LIMIT 1) AS analysis_id FROM research.rounds r LEFT JOIN research.snapshots s ON s.round_id=r.id WHERE r.study_id=$1 ORDER BY r.number", study_id)
}
#' Record a human decision separately from analytic classification
#' @param repo Repository.
#' @param actor Study manager.
#' @param analysis_id Evidence reference.
#' @param item_code Item being decided.
#' @param disposition retain, revise, remove, split, merge, rerate or finalize.
#' @param reason Human rationale.
#' @param command_id Idempotency key.
#' @return Decision UUID.
#' @export
record_item_decision <- function(repo, actor, analysis_id, item_code, disposition, reason, command_id) {
  transaction(repo, function() {
    valid_id(analysis_id)
    x <- one(query(repo, "SELECT study_id,content::text FROM research.analyses WHERE id=$1", analysis_id))
    authorize(repo, actor, x$study_id, "manage")
    a <- jsonlite::fromJSON(x$content)
    ensure(item_code %in% a$results$item_code && disposition %in% c("retain", "revise", "remove", "split", "merge", "rerate", "finalize") && scalar_text(reason), "decision")
    command(repo, actor, x$study_id, "decision", command_id, list(analysis_id, item_code, disposition, reason), function() {
      id <- uid()
      execute(repo, "INSERT INTO research.decisions VALUES($1,$2,$3,$4,$5,$6,$7)", id, x$study_id, analysis_id, item_code, disposition, reason, actor$principal_id)
      list(id = id)
    })
  })
}
#' Read authorized setup information for the round editor
#' @param repo Repository.
#' @param actor Study manager.
#' @param study_id Study UUID.
#' @return Protocol and published information versions, without panel identities.
#' @export
get_study_setup <- function(repo, actor, study_id) {
  authorize(repo, actor, study_id, "manage")
  list(protocol = protocol_for(repo, study_id)$config, consent_versions = query(repo, "SELECT id,locale,content,hash FROM identity.consent_versions WHERE study_id=$1 ORDER BY created_at", study_id))
}
#' Preview the exact reviewed feedback artifact before release
#' @param repo Repository.
#' @param actor Study manager.
#' @param feedback_id Feedback UUID.
#' @return Content, hash and state of the candidate.
#' @export
get_feedback_candidate <- function(repo, actor, feedback_id) {
  valid_id(feedback_id)
  x <- one(query(repo, "SELECT study_id,content::text,hash,state FROM research.feedback WHERE id=$1", feedback_id))
  authorize(repo, actor, x$study_id, "manage")
  list(content = jsonlite::fromJSON(x$content), hash = x$hash, state = x$state)
}
#' Complete a study after finalization and explicit item decisions
#' @param repo Repository.
#' @param actor Study manager.
#' @param study_id Study UUID.
#' @param reason Human completion rationale, including persistent dissent.
#' @param command_id Idempotency key.
#' @return Completed study UUID.
#' @export
complete_study <- function(repo, actor, study_id, reason, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "manage")
    s <- one(query(repo, "SELECT state FROM research.studies WHERE id=$1 FOR UPDATE", study_id))
    ensure(scalar_text(reason), "completion.reason")
    command(repo, actor, study_id, "complete_study", command_id, list(reason), function() {
      ensure(s$state == "active", "study.state", "DEL_CONFLICT")
      r <- one(query(repo, "SELECT id,state FROM research.rounds WHERE study_id=$1 ORDER BY number DESC LIMIT 1", study_id))
      ensure(r$state == "finalized", "completion.round", "DEL_CONFLICT")
      unresolved <- query(repo, "SELECT DISTINCT i.item_code FROM research.round_items i WHERE i.round_id=$1 AND NOT EXISTS (SELECT 1 FROM research.decisions d JOIN research.analyses a ON a.id=d.analysis_id JOIN research.snapshots sn ON sn.id=a.snapshot_id WHERE d.study_id=i.study_id AND d.item_code=i.item_code AND sn.round_id=i.round_id)", r$id)
      ensure(nrow(unresolved) == 0, "completion.decisions")
      execute(repo, "UPDATE research.studies SET state='completed' WHERE id=$1", study_id)
      list(id = study_id, state = "completed")
    })
  })
}
