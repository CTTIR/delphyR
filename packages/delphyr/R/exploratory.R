#' List frozen rounds with free-text contributions
#' @param repo Repository.
#' @param actor Actor with edit capability.
#' @param study_id Study UUID.
#' @return Round number, snapshot UUID and the number of submitted free-text
#'   answers, with how many are already preserved as qualitative sources.
#' @export
list_contribution_rounds <- function(repo, actor, study_id) {
  authorize(repo, actor, study_id, "edit")
  query(repo, "SELECT r.number AS round_number,s.id AS snapshot_id,
      count(v.id)::int AS contributions,
      count(q.id)::int AS imported
    FROM research.snapshots s JOIN research.rounds r ON r.study_id=s.study_id AND r.id=s.round_id
    LEFT JOIN research.snapshot_entries se ON se.study_id=s.study_id AND se.snapshot_id=s.id
    LEFT JOIN research.response_revisions v ON v.id=se.response_revision_id AND v.status='answered' AND v.value_text IS NOT NULL
    LEFT JOIN research.qualitative_sources q ON q.study_id=v.study_id AND q.response_revision_id=v.id
    WHERE s.study_id=$1 GROUP BY r.number,s.id ORDER BY r.number", study_id)
}
#' Preserve the free-text answers of a frozen round as qualitative sources
#'
#' Every submitted free-text answer of the snapshot becomes one immutable
#' original source, referenced by round, item and an opaque suffix. The
#' sources carry no pseudonym; editorial work, redaction and independent
#' release follow as for any other source. Answers that already have a source
#' are skipped, so the import can be repeated.
#' @inheritParams list_contribution_rounds
#' @param snapshot_id Snapshot UUID of a frozen round.
#' @param command_id Idempotency key.
#' @return Snapshot UUID and the number of sources created.
#' @export
import_round_contributions <- function(repo, actor, snapshot_id, command_id) {
  transaction(repo, function() {
    valid_id(snapshot_id)
    x <- one(query(repo, "SELECT study_id FROM research.snapshots WHERE id=$1", snapshot_id))
    authorize(repo, actor, x$study_id, "edit")
    command(repo, actor, x$study_id, "qualitative_import", command_id, list(snapshot_id), function() {
      rows <- query(repo, "SELECT v.id AS revision_id,v.value_text,r.number,i.item_code,i.dimension_code FROM research.snapshot_entries se JOIN research.response_revisions v ON v.id=se.response_revision_id JOIN research.round_items i ON i.id=v.round_item_id JOIN research.rounds r ON r.id=se.round_id WHERE se.study_id=$1 AND se.snapshot_id=$2 AND v.status='answered' AND v.value_text IS NOT NULL AND NOT EXISTS(SELECT 1 FROM research.qualitative_sources q WHERE q.study_id=v.study_id AND q.response_revision_id=v.id) ORDER BY i.item_code,i.dimension_code,v.id", x$study_id, snapshot_id)
      for (i in seq_len(nrow(rows))) {
        reference <- paste0("R", rows$number[i], "-", rows$item_code[i], "-", rows$dimension_code[i], "-", substr(rows$revision_id[i], 1L, 8L))
        payload <- list(text = rows$value_text[i], source_ref = reference, response_revision_id = rows$revision_id[i])
        execute(repo, "INSERT INTO research.qualitative_sources(id,study_id,original_text,source_ref,response_revision_id,created_by,hash) VALUES($1,$2,$3,$4,$5,$6,$7)", uid(), x$study_id, rows$value_text[i], reference, rows$revision_id[i], actor$principal_id, content_hash(payload))
      }
      list(id = snapshot_id, imported = nrow(rows))
    })
  })
}
#' List released editorial versions available for participant feedback
#' @inheritParams list_contribution_rounds
#' @param actor Actor with analyse or manage capability.
#' @return Edit UUID, source reference, kind, released text, release time and
#'   the item codes linked to the source. Originals are not included.
#' @export
list_released_edits <- function(repo, actor, study_id) {
  authorize_any(repo, actor, study_id, c("analyse", "manage"))
  x <- query(repo, "SELECT e.id AS edit_id,q.source_ref,e.kind,e.redacted_text AS text,r.released_at::text AS released_at,
      COALESCE((SELECT string_agg(DISTINCT v.item_code, ', ' ORDER BY v.item_code) FROM research.qualitative_item_sources s JOIN research.item_provenance_versions v ON v.study_id=s.study_id AND v.id=s.item_id WHERE s.study_id=e.study_id AND s.source_id=e.source_id), '') AS item_codes
    FROM research.qualitative_edits e JOIN research.qualitative_releases r ON r.study_id=e.study_id AND r.edit_id=e.id JOIN research.qualitative_sources q ON q.study_id=e.study_id AND q.id=e.source_id
    WHERE e.study_id=$1 ORDER BY r.released_at,e.id", study_id)
  x
}
#' Replace released feedback by a corrected version
#'
#' Released feedback is never edited. A correction releases a second feedback
#' candidate of the same analysis and records that it replaces the first:
#' later views show the corrected version with the note for participants,
#' while earlier display events keep referring to the version that was shown.
#' @param repo Repository.
#' @param actor Study manager.
#' @param feedback_id Released feedback that contains the error.
#' @param replacement_id Reviewed candidate of the same analysis.
#' @param expected_hash Exact hash of the replacement shown during review.
#' @param reason Internal rationale for the correction.
#' @param impact_note Internal assessment of the effect on ratings already
#'   given under the earlier version.
#' @param participant_note Text shown to participants with the corrected feedback.
#' @param command_id Idempotency key.
#' @return The replacement feedback UUID and the feedback it replaces.
#' @export
release_feedback_correction <- function(repo, actor, feedback_id, replacement_id, expected_hash, reason, impact_note, participant_note, command_id) {
  transaction(repo, function() {
    valid_id(feedback_id)
    valid_id(replacement_id)
    old <- one(query(repo, "SELECT f.*,s.round_id FROM research.feedback f JOIN research.analyses a ON a.id=f.analysis_id JOIN research.snapshots s ON s.id=a.snapshot_id WHERE f.id=$1", feedback_id))
    r <- round_get(repo, actor, old$round_id, "manage", " FOR UPDATE")
    for (text in list(reason, impact_note, participant_note)) ensure(scalar_text(text) && nchar(text, type = "bytes") <= 10000L, "correction.text")
    ensure(scalar_text(expected_hash), "correction.hash")
    command(repo, actor, old$study_id, "correct_feedback", command_id, list(feedback_id, replacement_id, expected_hash, reason, impact_note, participant_note), function() {
      new <- one(query(repo, "SELECT * FROM research.feedback WHERE study_id=$1 AND id=$2 FOR UPDATE", old$study_id, replacement_id))
      ensure(old$state == "released" && new$state == "reviewed" && identical(new$analysis_id, old$analysis_id) && identical(new$hash, expected_hash) && !identical(new$hash, old$hash), "feedback.correction", "DEL_CONFLICT")
      ensure(!nrow(query(repo, "SELECT id FROM research.feedback_corrections WHERE study_id=$1 AND feedback_id=$2", old$study_id, feedback_id)), "feedback.already_corrected", "DEL_CONFLICT")
      execute(repo, "UPDATE research.feedback SET state='released' WHERE id=$1", replacement_id)
      execute(repo, "INSERT INTO research.feedback_corrections(id,study_id,feedback_id,replacement_id,reason,impact_note,participant_note,actor_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8)", uid(), old$study_id, feedback_id, replacement_id, reason, impact_note, participant_note, actor$principal_id)
      list(id = replacement_id, replaces = feedback_id)
    }, reason = reason, detail = paste("replaces", feedback_id))
  })
}
#' Read the released feedback of a round and its corrections
#' @param repo Repository.
#' @param actor Study manager or analyst.
#' @param study_id Study UUID.
#' @return One row per released feedback: round, UUID, hash, the round it is
#'   assigned to and, where it was corrected, its replacement with rationale.
#' @export
list_released_feedback <- function(repo, actor, study_id) {
  authorize_any(repo, actor, study_id, c("analyse", "manage"))
  query(repo, "SELECT r.number AS round_number,f.id AS feedback_id,f.hash,
      (SELECT min(r2.number) FROM research.feedback_assignments fa JOIN research.rounds r2 ON r2.id=fa.round_id WHERE fa.study_id=f.study_id AND fa.feedback_id=f.id)::int AS assigned_round,
      c.replacement_id,c.reason,c.impact_note,c.participant_note,c.recorded_at::text AS corrected_at,
      EXISTS(SELECT 1 FROM research.feedback_corrections p WHERE p.study_id=f.study_id AND p.replacement_id=f.id) AS is_correction
    FROM research.feedback f JOIN research.analyses a ON a.id=f.analysis_id JOIN research.snapshots s ON s.id=a.snapshot_id JOIN research.rounds r ON r.id=s.round_id
    LEFT JOIN research.feedback_corrections c ON c.study_id=f.study_id AND c.feedback_id=f.id
    WHERE f.study_id=$1 AND f.state='released' ORDER BY r.number,f.id", study_id)
}
