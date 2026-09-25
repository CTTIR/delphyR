#' Read the immutable study protocol history
#' @param repo Repository.
#' @param actor Study manager.
#' @param study_id Study UUID.
#' @return Version table with content hashes, configurations and amendment reasons.
#' @export
list_protocol_versions <- function(repo, actor, study_id) {
  authorize(repo, actor, study_id, "manage")
  query(repo, "SELECT p.id,p.version,p.hash,p.config::text,a.previous_protocol_id,a.reason,a.occurred_at FROM research.protocol_versions p LEFT JOIN research.protocol_amendments a ON a.study_id=p.study_id AND a.protocol_id=p.id WHERE p.study_id=$1 ORDER BY p.version", study_id)
}
#' Approve a new protocol version for future rounds
#'
#' Existing rounds and snapshots retain their exact protocol. An amendment never
#' changes the meaning of an existing scale code. Introduce a new scale code for
#' changed scales and a new item version before using it. This service records a
#' synthetic technical approval, not institutional or ethical approval.
#' @param repo Repository.
#' @param actor Study manager.
#' @param study_id Study UUID.
#' @param protocol Validated complete replacement protocol.
#' @param expected_hash Latest protocol hash shown during review.
#' @param reason Nonempty amendment rationale.
#' @param command_id Idempotency key.
#' @return New protocol id, version and hash.
#' @export
amend_protocol <- function(repo, actor, study_id, protocol, expected_hash, reason, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "manage")
    one(query(repo, "SELECT id FROM research.studies WHERE id=$1 AND state IN ('draft','active') FOR UPDATE", study_id))
    protocol <- new_protocol(protocol)
    ensure(scalar_text(expected_hash) && scalar_text(reason) && nchar(reason, type = "bytes") <= 10000L, "protocol.amendment")
    command(repo, actor, study_id, "amend_protocol", command_id, list(protocol, expected_hash, reason), function() {
      old <- one(query(repo, "SELECT id,version,hash,config::text FROM research.protocol_versions WHERE study_id=$1 ORDER BY version DESC LIMIT 1", study_id))
      ensure(identical(old$hash, expected_hash), "protocol.version", "DEL_CONFLICT")
      previous <- new_protocol(from_json(old$config))
      ensure(identical(protocol$study$code, previous$study$code), "protocol.study_code")
      history <- query(repo, "SELECT config::text FROM research.protocol_versions WHERE study_id=$1", study_id)
      for (config in history$config) {
        historical <- new_protocol(from_json(config))
        for (code in intersect(names(historical$instrument$scales), names(protocol$instrument$scales))) {
          ensure(identical(content_hash(historical$instrument$scales[[code]]), content_hash(protocol$instrument$scales[[code]])), "protocol.scale_identity", "DEL_CONFLICT")
        }
      }
      active_groups <- query(repo, "SELECT DISTINCT group_code FROM research.panelists WHERE study_id=$1 AND active", study_id)$group_code
      ensure(all(active_groups %in% unlist(protocol$panel$groups)), "protocol.active_panel_groups", "DEL_CONFLICT")
      max_round <- query(repo, "SELECT COALESCE(MAX(number),0) AS n FROM research.rounds WHERE study_id=$1", study_id)$n
      ensure(protocol$stopping$max_rounds >= max_round, "protocol.existing_rounds")
      hash <- content_hash(protocol)
      ensure(!identical(hash, old$hash), "protocol.unchanged", "DEL_CONFLICT")
      id <- uid()
      version <- old$version + 1L
      execute(repo, "INSERT INTO research.protocol_versions VALUES($1,$2,$3,$4::jsonb,$5)", id, study_id, version, json(protocol), hash)
      execute(repo, "INSERT INTO research.protocol_amendments(id,study_id,previous_protocol_id,protocol_id,actor_id,reason) VALUES($1,$2,$3,$4,$5,$6)", uid(), study_id, old$id, id, actor$principal_id, reason)
      list(id = id, version = version, hash = hash)
    })
  })
}
