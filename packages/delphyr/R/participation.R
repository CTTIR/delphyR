#' Withdraw the current participant from future synthetic study activity
#'
#' Stops further collection and delivery eligibility while retaining previously
#' committed research data. This explicit synthetic policy is not a deletion
#' workflow or a policy for use with real participants.
#' @param repo Repository.
#' @param actor Participant's own current server identity.
#' @param study_id Study UUID.
#' @param retention_policy Must explicitly be synthetic_retain_prior_data.
#' @param command_id Idempotency key.
#' @return Withdrawal event id and policy receipt.
#' @export
withdraw_participation <- function(repo, actor, study_id, retention_policy, command_id) {
  transaction(repo, function() {
    member <- authorize(repo, actor, study_id, "panel")
    ensure(identical(retention_policy, "synthetic_retain_prior_data"), "withdrawal.policy")
    one(query(repo, "SELECT id FROM research.studies WHERE id=$1 FOR NO KEY UPDATE", study_id))
    member <- authorize(repo, actor, study_id, "panel")
    panel <- one(query(repo, "SELECT panelist_id FROM identity.panelist_links WHERE study_id=$1 AND membership_id=$2", study_id, member))$panelist_id
    command(repo, actor, study_id, "withdraw_participation", command_id, list(retention_policy), function() {
      existing <- query(repo, "SELECT id,retention_policy FROM research.participation_withdrawals WHERE study_id=$1 AND panelist_id=$2", study_id, panel)
      if (nrow(existing)) {
        return(as.list(existing[1, ]))
      }
      # The study lock serializes round preparation; enrollment locks serialize
      # with save/submit, so an acknowledged save either precedes withdrawal
      # or observes the withdrawn state. Historical submissions are retained.
      query(repo, "SELECT id FROM research.enrollments WHERE study_id=$1 AND panelist_id=$2 ORDER BY id FOR UPDATE", study_id, panel)
      authorize(repo, actor, study_id, "panel")
      execute(repo, "UPDATE research.panelists SET active=false WHERE study_id=$1 AND id=$2", study_id, panel)
      execute(repo, "UPDATE research.enrollments SET state='withdrawn' WHERE study_id=$1 AND panelist_id=$2 AND state IN ('eligible','in_progress')", study_id, panel)
      id <- uid()
      execute(repo, "INSERT INTO research.participation_withdrawals(id,study_id,panelist_id,actor_id,retention_policy) VALUES($1,$2,$3,$4,$5)", id, study_id, panel, actor$principal_id, retention_policy)
      list(id = id, retention_policy = retention_policy)
    })
  })
}
#' Change stakeholder group only for future round preparation
#' @param repo Repository.
#' @param actor Study manager.
#' @param study_id Study UUID.
#' @param panelist_id Study-specific pseudonym UUID.
#' @param group_code Group declared by the current protocol.
#' @param reason Nonempty rationale.
#' @param command_id Idempotency key.
#' @return Immutable group-change receipt; existing enrollments stay unchanged.
#' @export
set_panel_group <- function(repo, actor, study_id, panelist_id, group_code, reason, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "manage")
    valid_id(panelist_id)
    one(query(repo, "SELECT id FROM research.studies WHERE id=$1 AND state IN ('draft','active') FOR NO KEY UPDATE", study_id))
    p <- protocol_for(repo, study_id)$config
    ensure(scalar_text(group_code) && group_code %in% unlist(p$panel$groups) && scalar_text(reason) && nchar(reason, type = "bytes") <= 10000L, "panel.group")
    command(repo, actor, study_id, "panel_group", command_id, list(panelist_id, group_code, reason), function() {
      previous <- one(query(repo, "SELECT group_code FROM research.panelists WHERE study_id=$1 AND id=$2 AND active FOR UPDATE", study_id, panelist_id))$group_code
      ensure(!identical(previous, group_code), "panel.group_unchanged", "DEL_CONFLICT")
      id <- uid()
      execute(repo, "UPDATE research.panelists SET group_code=$3 WHERE study_id=$1 AND id=$2", study_id, panelist_id, group_code)
      execute(repo, "INSERT INTO research.panel_group_events(id,study_id,panelist_id,actor_id,previous_group,group_code,reason) VALUES($1,$2,$3,$4,$5,$6,$7)", id, study_id, panelist_id, actor$principal_id, previous, group_code, reason)
      list(id = id, group_code = group_code)
    })
  })
}
