#' Generate a private synthetic invitation token
#' @return A 256-bit secret with redacted printing. Retain privately; only its hash
#'   is persisted. Never put the token in logs, audit records or research exports.
#' @export
new_invitation_token <- function() structure(paste(format(openssl::rand_bytes(32L)), collapse = ""), class = "delphyr_invitation_token")
#' @export
print.delphyr_invitation_token <- function(x, ...) {
  cat("<private invitation token>\n")
  invisible(x)
}
invitation_hash <- function(token) {
  ensure(is.character(token) && length(token) == 1L && !is.na(token) && grepl("^[0-9a-f]{64}$", token), "invitation.token", "DEL_UNAUTHORIZED")
  digest::digest(as.character(token), algo = "sha256", serialize = FALSE)
}
invitation_identity <- function(repo, actor) {
  p <- identity_check(repo, actor)
  ensure(scalar_text(actor$issuer) && identical(actor$issuer, p$issuer) && grepl("^https?://", p$issuer), "invitation.identity", "DEL_UNAUTHORIZED")
  p
}
invitation_match <- function(repo, actor, inv, token_hash) {
  p <- invitation_identity(repo, actor)
  ensure(identical(inv$token_hash, token_hash) && identical(inv$expected_principal_id, p$id) &&
    identical(inv$expected_issuer, p$issuer) && identical(inv$expected_subject, p$subject), "invitation.identity", "DEL_UNAUTHORIZED")
  invisible(p)
}
#' Issue a synthetic invitation for an explicitly approved existing account
#' @param repo Repository.
#' @param actor Study coordinator.
#' @param study_id Study UUID.
#' @param draft_id Imported invitation draft UUID.
#' @param principal_id Existing provisioned principal approved by stable issuer/subject.
#' @param token Private output of new_invitation_token(). Never persisted in plaintext.
#' @param ttl_seconds Lifetime in seconds, between one second and 24 hours.
#' @param reason Documented account-binding approval; do not include credentials.
#' @param command_id Idempotency key.
#' @return Invitation UUID and expiry, without the token or contact fields.
#' @export
issue_panel_invitation <- function(repo, actor, study_id, draft_id, principal_id, token, ttl_seconds = 900L, reason, command_id) {
  h <- invitation_hash(token)
  ensure(whole(ttl_seconds) && length(ttl_seconds) == 1L && ttl_seconds >= 1L && ttl_seconds <= 86400L, "invitation.ttl")
  ensure(scalar_text(reason), "invitation.reason")
  valid_id(draft_id)
  valid_id(principal_id)
  transaction(repo, function() {
    authorize(repo, actor, study_id, "coordinate")
    one(query(repo, "SELECT id FROM research.studies WHERE id=$1 AND state IN ('draft','active') FOR NO KEY UPDATE", study_id))
    command(repo, actor, study_id, "invitation_issue", command_id, list(draft_id, principal_id, h, ttl_seconds, reason), function() {
      one(query(repo, "SELECT id FROM identity.panel_invitation_drafts WHERE study_id=$1 AND id=$2", study_id, draft_id))
      p <- one(query(repo, "SELECT * FROM identity.principals WHERE id=$1 AND active", principal_id))
      ensure(grepl("^https?://", p$issuer), "invitation.verified_account", "DEL_FORBIDDEN")
      ensure(!nrow(query(repo, "SELECT invitation_id FROM identity.panel_invitation_acceptances WHERE study_id=$1 AND draft_id=$2", study_id, draft_id)), "invitation.accepted", "DEL_CONFLICT")
      ensure(!nrow(query(repo, "SELECT i.id FROM identity.panel_invitations i WHERE i.study_id=$1 AND i.draft_id=$2 AND i.expires_at>clock_timestamp() AND NOT EXISTS(SELECT 1 FROM identity.panel_invitation_revocations r WHERE r.invitation_id=i.id)", study_id, draft_id)), "invitation.outstanding", "DEL_CONFLICT")
      id <- uid()
      x <- query(repo, "INSERT INTO identity.panel_invitations(id,study_id,draft_id,expected_principal_id,expected_issuer,expected_subject,token_hash,expires_at,actor_id,reason) VALUES($1,$2,$3,$4,$5,$6,$7,clock_timestamp()+$8*interval '1 second',$9,$10) RETURNING expires_at::text", id, study_id, draft_id, principal_id, p$issuer, p$subject, h, ttl_seconds, actor$principal_id, reason)
      list(id = id, expires_at = x$expires_at)
    })
  })
}
#' Revoke an unconsumed synthetic invitation
#' @inheritParams issue_panel_invitation
#' @param invitation_id Invitation UUID.
#' @return Invitation UUID.
#' @export
revoke_panel_invitation <- function(repo, actor, study_id, invitation_id, reason, command_id) {
  valid_id(invitation_id)
  ensure(scalar_text(reason), "invitation.reason")
  transaction(repo, function() {
    authorize(repo, actor, study_id, "coordinate")
    one(query(repo, "SELECT id FROM research.studies WHERE id=$1 FOR NO KEY UPDATE", study_id))
    command(repo, actor, study_id, "invitation_revoke", command_id, list(invitation_id, reason), function() {
      one(query(repo, "SELECT id FROM identity.panel_invitations WHERE study_id=$1 AND id=$2 FOR UPDATE", study_id, invitation_id))
      authorize(repo, actor, study_id, "coordinate")
      ensure(!nrow(query(repo, "SELECT invitation_id FROM identity.panel_invitation_acceptances WHERE invitation_id=$1", invitation_id)), "invitation.accepted", "DEL_CONFLICT")
      execute(repo, "INSERT INTO identity.panel_invitation_revocations(invitation_id,study_id,actor_id,reason) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING", invitation_id, study_id, actor$principal_id, reason)
      list(id = invitation_id)
    })
  })
}
#' Accept an invitation after verified login and an explicit confirmed action
#' @inheritParams issue_panel_invitation
#' @param invitation_id Invitation UUID, not a panelist identifier.
#' @param confirmed Explicit TRUE from the confirmation action; never call on GET.
#' @return Invitation, membership and pseudonym receipt. No consent or round
#'   enrollment is created. Existing provisioned accounts are required.
#' @export
accept_panel_invitation <- function(repo, actor, study_id, invitation_id, token, confirmed, command_id) {
  ensure(isTRUE(confirmed), "invitation.confirmed")
  valid_id(study_id)
  valid_id(invitation_id)
  h <- invitation_hash(token)
  ensure(scalar_text(command_id) && nchar(command_id) <= 200L, "command_id")
  payload <- content_hash(list(invitation_id, h, confirmed))
  transaction(repo, function() {
    invitation_identity(repo, actor)
    one(query(repo, "SELECT id FROM research.studies WHERE id=$1 AND state IN ('draft','active') FOR NO KEY UPDATE", study_id))
    inv <- one(query(repo, "SELECT * FROM identity.panel_invitations WHERE study_id=$1 AND id=$2 FOR UPDATE", study_id, invitation_id))
    invitation_match(repo, actor, inv, h)
    old <- query(repo, "SELECT invitation_id,membership_id,panelist_id,payload_hash FROM identity.panel_invitation_acceptances WHERE study_id=$1 AND principal_id=$2 AND command_key=$3", study_id, actor$principal_id, command_id)
    receipt <- function(x) list(id = x$invitation_id, membership_id = x$membership_id, panelist_id = x$panelist_id)
    if (nrow(old)) {
      ensure(identical(old$payload_hash, payload), "command.payload", "DEL_CONFLICT")
      return(receipt(old))
    }
    ensure(isTRUE(query(repo, "SELECT expires_at>clock_timestamp() AS valid FROM identity.panel_invitations WHERE id=$1", invitation_id)$valid) &&
      !nrow(query(repo, "SELECT invitation_id FROM identity.panel_invitation_revocations WHERE invitation_id=$1", invitation_id)), "invitation.expired_or_revoked", "DEL_UNAUTHORIZED")
    ensure(!nrow(query(repo, "SELECT invitation_id FROM identity.panel_invitation_acceptances WHERE invitation_id=$1 OR (study_id=$2 AND (draft_id=$3 OR principal_id=$4))", invitation_id, study_id, inv$draft_id, actor$principal_id)), "invitation.consumed", "DEL_CONFLICT")
    contact <- one(query(repo, "SELECT c.stakeholder_group FROM identity.panel_contacts c JOIN identity.panel_invitation_drafts d ON d.study_id=c.study_id AND d.contact_id=c.id WHERE d.study_id=$1 AND d.id=$2", study_id, inv$draft_id))
    ensure(contact$stakeholder_group %in% unlist(protocol_for(repo, study_id)$config$panel$groups), "panel.group")
    m <- query(repo, "SELECT id,active FROM identity.memberships WHERE study_id=$1 AND principal_id=$2 FOR UPDATE", study_id, actor$principal_id)
    invitation_match(repo, actor, inv, h)
    if (nrow(m)) {
      ensure(isTRUE(m$active), "invitation.membership", "DEL_FORBIDDEN")
      ensure(!nrow(query(repo, "SELECT panelist_id FROM identity.panelist_links WHERE study_id=$1 AND membership_id=$2", study_id, m$id)), "panel.duplicate", "DEL_CONFLICT")
      ensure(!nrow(query(repo, "SELECT capability FROM identity.capabilities WHERE study_id=$1 AND membership_id=$2 AND capability='panel' AND revoked_at IS NOT NULL", study_id, m$id)), "invitation.revoked_right", "DEL_FORBIDDEN")
    } else {
      m <- data.frame(id = uid())
      execute(repo, "INSERT INTO identity.memberships(id,study_id,principal_id) VALUES($1,$2,$3)", m$id, study_id, actor$principal_id)
    }
    id <- uid()
    execute(repo, "INSERT INTO research.panelists(id,study_id,group_code) VALUES($1,$2,$3)", id, study_id, contact$stakeholder_group)
    execute(repo, "INSERT INTO identity.panelist_links VALUES($1,$2,$3)", study_id, m$id, id)
    execute(repo, "INSERT INTO identity.capabilities(study_id,membership_id,capability) VALUES($1,$2,'panel') ON CONFLICT DO NOTHING", study_id, m$id)
    execute(repo, "INSERT INTO identity.panel_invitation_acceptances(invitation_id,study_id,draft_id,principal_id,membership_id,panelist_id,command_key,payload_hash) VALUES($1,$2,$3,$4,$5,$6,$7,$8)", invitation_id, study_id, inv$draft_id, actor$principal_id, m$id, id, command_id, payload)
    audit(repo, actor, study_id, "invitation_accept", invitation_id)
    list(id = invitation_id, membership_id = m$id, panelist_id = id)
  })
}
#' Preview an invitation without creating membership or consuming its token
#' @inheritParams accept_panel_invitation
#' @return Study title and invitation expiry only, for the exact approved account.
#' @export
preview_panel_invitation <- function(repo, actor, study_id, invitation_id, token) {
  valid_id(study_id)
  valid_id(invitation_id)
  h <- invitation_hash(token)
  invitation_identity(repo, actor)
  inv <- one(query(repo, "SELECT i.*,s.title FROM identity.panel_invitations i JOIN research.studies s ON s.id=i.study_id WHERE i.study_id=$1 AND i.id=$2 AND s.state IN ('draft','active') AND i.expires_at>clock_timestamp() AND NOT EXISTS(SELECT 1 FROM identity.panel_invitation_revocations r WHERE r.invitation_id=i.id) AND NOT EXISTS(SELECT 1 FROM identity.panel_invitation_acceptances a WHERE a.invitation_id=i.id)", study_id, invitation_id))
  invitation_match(repo, actor, inv, h)
  list(id = inv$id, study_title = inv$title, expires_at = as.character(inv$expires_at))
}
#' Register a verified external account before issuing its invitation
#'
#' Account onboarding is an explicit coordinator decision. The stable issuer and
#' subject come from the institution's identity provider, never from an email
#' address. The registered principal has no study rights until its own
#' invitation is accepted. Existing disabled accounts are not reactivated.
#' @inheritParams issue_panel_invitation
#' @param issuer Exact OIDC issuer URL of the qualified authentication gateway.
#' @param subject Stable provider subject of the invited person.
#' @return Principal UUID for issue_panel_invitation(); no rights are granted.
#' @export
register_invited_account <- function(repo, actor, study_id, issuer, subject, reason, command_id) {
  ensure(scalar_text(issuer) && nchar(issuer, type = "bytes") <= 512L && grepl("^https?://[^[:space:]?#@]+$", issuer), "invitation.issuer")
  ensure(scalar_text(subject) && nchar(subject, type = "bytes") <= 1024L && !grepl("[[:space:],[:cntrl:]]", subject), "invitation.subject")
  ensure(scalar_text(reason) && nchar(reason, type = "bytes") <= 10000L, "invitation.reason")
  transaction(repo, function() {
    authorize(repo, actor, study_id, "coordinate")
    one(query(repo, "SELECT id FROM research.studies WHERE id=$1 AND state IN ('draft','active') FOR NO KEY UPDATE", study_id))
    command(repo, actor, study_id, "invitation_account", command_id, list(issuer, subject, reason), function() {
      p <- query(repo, "INSERT INTO identity.principals(id,issuer,subject) VALUES($1,$2,$3) ON CONFLICT(issuer,subject) DO UPDATE SET subject=EXCLUDED.subject RETURNING id,active", uid(), issuer, subject)
      ensure(isTRUE(p$active), "invitation.account_disabled", "DEL_FORBIDDEN")
      list(id = p$id)
    })
  })
}
#' List imported invitation drafts and their current invitation state
#' @inheritParams issue_panel_invitation
#' @return One row per draft: source reference, display name, group, locale,
#'   latest invitation id, expiry and state (unbound, outstanding, expired,
#'   revoked or accepted). Never contains tokens, hashes, emails or pseudonyms.
#' @export
list_panel_invitations <- function(repo, actor, study_id) {
  authorize(repo, actor, study_id, "coordinate")
  query(repo, "SELECT d.id AS draft_id,c.external_ref,c.display_name,c.stakeholder_group,c.locale,i.id AS invitation_id,i.expires_at::text AS expires_at,
    CASE WHEN EXISTS(SELECT 1 FROM identity.panel_invitation_acceptances a WHERE a.study_id=d.study_id AND a.draft_id=d.id) THEN 'accepted'
         WHEN i.id IS NULL THEN 'unbound'
         WHEN EXISTS(SELECT 1 FROM identity.panel_invitation_revocations r WHERE r.invitation_id=i.id) THEN 'revoked'
         WHEN i.expires_at<=clock_timestamp() THEN 'expired' ELSE 'outstanding' END AS state
    FROM identity.panel_invitation_drafts d JOIN identity.panel_contacts c ON c.study_id=d.study_id AND c.id=d.contact_id
    LEFT JOIN LATERAL (SELECT x.id,x.expires_at FROM identity.panel_invitations x WHERE x.study_id=d.study_id AND x.draft_id=d.id ORDER BY x.created_at DESC,x.id LIMIT 1) i ON true
    WHERE d.study_id=$1 ORDER BY c.external_ref", study_id)
}
#' Encode an invitation hand-over code
#'
#' The code combines the study, invitation and private token so that the invited
#' person enters one value after verified login. Treat the whole code as secret.
#' @param study_id,invitation_id UUIDs returned by the issuing services.
#' @param token Private output of new_invitation_token().
#' @return A single private string with redacted printing; as.character() reveals it.
#' @export
invitation_code <- function(study_id, invitation_id, token) {
  valid_id(study_id)
  valid_id(invitation_id)
  invitation_hash(token)
  structure(paste("dlp1", study_id, invitation_id, as.character(token), sep = "."), class = "delphyr_invitation_token")
}
#' Decode an invitation hand-over code
#' @param code Value produced by invitation_code(); surrounding space is ignored.
#' @return List study_id, invitation_id and token; DEL_UNAUTHORIZED when malformed.
#' @export
parse_invitation_code <- function(code) {
  ensure(is.character(code) && length(code) == 1L && !is.na(code) && nchar(code, type = "bytes") <= 200L, "invitation.code", "DEL_UNAUTHORIZED")
  parts <- strsplit(trimws(code), ".", fixed = TRUE)[[1]]
  uuid <- "^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$"
  ensure(length(parts) == 4L && identical(parts[1], "dlp1") && grepl(uuid, parts[2]) && grepl(uuid, parts[3]) && grepl("^[0-9a-f]{64}$", parts[4]), "invitation.code", "DEL_UNAUTHORIZED")
  list(study_id = parts[2], invitation_id = parts[3], token = structure(parts[4], class = "delphyr_invitation_token"))
}
