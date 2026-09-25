#' Prepare an exact synthetic communication campaign
#' @param repo Development/test repository.
#' @param actor Actor with coordinate capability.
#' @param round_id Study round UUID.
#' @param enrollment_ids Exact recipient enrollment UUIDs; no addresses accepted.
#' @param kind invitation, round_start, reminder, deadline_change or completion.
#' @param subject,body Final plain text without unresolved template placeholders.
#' @param locale de or en.
#' @param template_version Positive immutable template version.
#' @param command_id Idempotency key.
#' @return Campaign id, exact content/recipient hash and recipient count.
#' @export
prepare_campaign <- function(repo, actor, round_id, enrollment_ids, kind, subject, body,
                             locale = "de", template_version = 1L, command_id) {
  transaction(repo, function() {
    ensure(repo$environment %in% c("development", "test"), "communications.sink_only", "DEL_FORBIDDEN")
    r <- round_get(repo, actor, round_id, "coordinate", " FOR SHARE")
    ensure(is.character(enrollment_ids) && length(enrollment_ids) > 0 && length(enrollment_ids) <= 10000 && !anyDuplicated(enrollment_ids), "campaign.recipients")
    for (id in enrollment_ids) valid_id(id)
    ensure(length(kind) == 1 && kind %in% c("invitation", "round_start", "reminder", "deadline_change", "completion"), "campaign.kind")
    ensure(scalar_text(subject) && nchar(subject, type = "bytes") <= 200 && scalar_text(body) && nchar(body, type = "bytes") <= 20000 &&
      !grepl("[\r\n]", subject) && !grepl("{{", paste(subject, body), fixed = TRUE) && !grepl("}}", paste(subject, body), fixed = TRUE), "campaign.text")
    ensure(length(locale) == 1 && locale %in% c("de", "en") && whole(template_version) && length(template_version) == 1 && template_version > 0, "campaign.template")
    recipients <- sort(enrollment_ids)
    payload <- list(round_id = round_id, enrollment_ids = recipients, kind = kind, subject = subject, body = body, locale = locale, template_version = template_version)
    command(repo, actor, r$study_id, "campaign_prepare", command_id, payload, function() {
      for (e in recipients) one(query(repo, "SELECT id FROM research.enrollments WHERE study_id=$1 AND round_id=$2 AND id=$3", r$study_id, round_id, e))
      id <- uid()
      h <- content_hash(payload)
      execute(repo, "INSERT INTO ops.campaigns(id,study_id,round_id,kind,locale,template_version,subject,body,hash,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)", id, r$study_id, round_id, kind, locale, template_version, subject, body, h, actor$principal_id)
      for (e in recipients) execute(repo, "INSERT INTO ops.campaign_recipients VALUES($1,$2,$3,$4)", r$study_id, round_id, id, e)
      list(id = id, hash = h, n_recipients = length(recipients))
    })
  })
}
campaign_get <- function(repo, actor, id, lock = FALSE) {
  valid_id(id)
  x <- one(query(repo, "SELECT study_id FROM ops.campaigns WHERE id=$1", id))
  authorize(repo, actor, x$study_id, "coordinate")
  one(query(repo, paste0("SELECT * FROM ops.campaigns WHERE id=$1", if (lock) " FOR UPDATE" else ""), id))
}
campaign_hash <- function(repo, c) {
  ids <- query(repo, "SELECT enrollment_id FROM ops.campaign_recipients WHERE campaign_id=$1 ORDER BY enrollment_id", c$id)$enrollment_id
  content_hash(list(round_id = c$round_id, enrollment_ids = sort(ids), kind = c$kind, subject = c$subject, body = c$body, locale = c$locale, template_version = c$template_version))
}
#' Preview exact campaign text and pseudonymous recipients
#' @param repo Repository.
#' @param actor Actor with coordinate capability.
#' @param campaign_id Campaign UUID.
#' @return Plain text, hash, pseudonyms and delivery states; no contacts or answers.
#' @export
preview_campaign <- function(repo, actor, campaign_id) {
  c <- campaign_get(repo, actor, campaign_id)
  list(
    id = c$id, kind = c$kind, subject = c$subject, body = c$body, locale = c$locale, hash = c$hash,
    released = nrow(query(repo, "SELECT id FROM ops.campaign_releases WHERE campaign_id=$1", c$id)) == 1L,
    cancelled = nrow(query(repo, "SELECT id FROM ops.campaign_cancellations WHERE campaign_id=$1", c$id)) == 1L,
    recipients = query(repo, "SELECT e.id AS enrollment_id,e.panelist_id AS pseudonym,coalesce(d.state,'draft') AS delivery_state,d.reason FROM ops.campaign_recipients cr JOIN research.enrollments e ON e.id=cr.enrollment_id LEFT JOIN ops.message_outbox o ON o.campaign_id=cr.campaign_id AND o.enrollment_id=cr.enrollment_id LEFT JOIN ops.message_delivery d ON d.message_id=o.id WHERE cr.campaign_id=$1 ORDER BY e.id", c$id)
  )
}
#' Release an exact synthetic campaign and atomically create its outbox
#' @param repo Repository.
#' @param actor Actor with coordinate capability.
#' @param campaign_id Campaign UUID.
#' @param expected_hash Hash reviewed in preview.
#' @param reason Human approval rationale.
#' @param command_id Idempotency key.
#' @return Campaign id and approved recipient count. No message is sent.
#' @export
release_campaign <- function(repo, actor, campaign_id, expected_hash, reason, command_id) {
  transaction(repo, function() {
    c <- campaign_get(repo, actor, campaign_id, TRUE)
    ensure(scalar_text(reason), "campaign.reason")
    command(repo, actor, c$study_id, "campaign_release", command_id, list(campaign_id, expected_hash, reason), function() {
      ensure(identical(c$hash, expected_hash) && identical(c$hash, campaign_hash(repo, c)), "campaign.hash", "DEL_CONFLICT")
      ensure(!nrow(query(repo, "SELECT id FROM ops.campaign_cancellations WHERE campaign_id=$1", c$id)) &&
        !nrow(query(repo, "SELECT id FROM ops.campaign_releases WHERE campaign_id=$1", c$id)), "campaign.state", "DEL_CONFLICT")
      recipients <- query(repo, "SELECT enrollment_id FROM ops.campaign_recipients WHERE campaign_id=$1 ORDER BY enrollment_id", c$id)$enrollment_id
      execute(repo, "INSERT INTO ops.campaign_releases(id,study_id,campaign_id,approved_hash,reason,approved_by) VALUES($1,$2,$3,$4,$5,$6)", uid(), c$study_id, c$id, c$hash, reason, actor$principal_id)
      for (e in recipients) {
        id <- uid()
        execute(repo, "INSERT INTO ops.message_outbox(id,study_id,campaign_id,enrollment_id,dedupe_key) VALUES($1,$2,$3,$4,$5)", id, c$study_id, c$id, e, content_hash(list(c$id, e, c$hash)))
        execute(repo, "INSERT INTO ops.message_delivery(message_id) VALUES($1)", id)
      }
      list(id = c$id, n_recipients = length(recipients))
    })
  })
}
#' Cancel remaining synthetic campaign delivery
#' @param repo Repository.
#' @param actor Actor with coordinate capability.
#' @param campaign_id Campaign UUID.
#' @param reason Human cancellation rationale.
#' @param command_id Idempotency key.
#' @return Campaign UUID; already recorded sink receipts remain immutable.
#' @export
cancel_campaign <- function(repo, actor, campaign_id, reason, command_id) {
  transaction(repo, function() {
    c <- campaign_get(repo, actor, campaign_id, TRUE)
    ensure(scalar_text(reason), "campaign.reason")
    command(repo, actor, c$study_id, "campaign_cancel", command_id, list(campaign_id, reason), function() {
      execute(repo, "INSERT INTO ops.campaign_cancellations(id,study_id,campaign_id,reason,cancelled_by) VALUES($1,$2,$3,$4,$5)", uid(), c$study_id, c$id, reason, actor$principal_id)
      list(id = c$id)
    })
  })
}
claim_campaign_message <- function(repo, study_id = NULL, lease_seconds = 30L) {
  transaction(repo, function() {
    ensure(repo$environment %in% c("development", "test"), "communications.sink_only", "DEL_FORBIDDEN")
    if (!is.null(study_id)) valid_id(study_id) else study_id <- NA_character_
    ensure(whole(lease_seconds) && length(lease_seconds) == 1 && lease_seconds > 0 && lease_seconds <= 300, "message.lease")
    execute(repo, "UPDATE ops.message_delivery d SET state='delivery_unknown',reason='expired_in_flight_lease',lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp() FROM ops.message_outbox o WHERE d.message_id=o.id AND d.state='running' AND d.lease_until<=clock_timestamp() AND ($1::uuid IS NULL OR o.study_id=$1)", study_id)
    j <- query(repo, "SELECT o.* FROM ops.message_outbox o JOIN ops.message_delivery d ON d.message_id=o.id WHERE d.state='queued' AND ($1::uuid IS NULL OR o.study_id=$1) ORDER BY o.created_at,o.id LIMIT 1 FOR UPDATE OF d SKIP LOCKED", study_id)
    if (!nrow(j)) {
      return(j)
    }
    token <- uid()
    execute(repo, "UPDATE ops.message_delivery SET state='running',lease_token=$2,lease_until=clock_timestamp()+$3*interval '1 second',attempts=attempts+1,updated_at=clock_timestamp() WHERE message_id=$1", j$id, token, lease_seconds)
    j$lease_token <- token
    j
  })
}
campaign_recipient_reason <- function(repo, c, enrollment_id) {
  if (nrow(query(repo, "SELECT id FROM ops.campaign_cancellations WHERE campaign_id=$1", c$id))) {
    return("campaign_cancelled")
  }
  release <- one(query(repo, "SELECT approved_by FROM ops.campaign_releases WHERE campaign_id=$1", c$id))
  approved <- query(repo, "SELECT p.id FROM identity.principals p JOIN identity.memberships m ON m.principal_id=p.id JOIN identity.capabilities cap ON cap.study_id=m.study_id AND cap.membership_id=m.id WHERE p.id=$1 AND p.active AND m.active AND m.study_id=$2 AND cap.capability='coordinate' AND cap.revoked_at IS NULL", release$approved_by, c$study_id)
  if (!nrow(approved)) {
    return("approval_authority_revoked")
  }
  e <- query(repo, "SELECT e.state,p.active AS panel_active,m.active AS member_active,pr.active AS principal_active,m.id AS membership_id,r.state AS round_state,r.deadline>clock_timestamp() AS in_time,r.consent_version_id,s.state AS study_state FROM research.enrollments e JOIN research.panelists p ON p.id=e.panelist_id JOIN identity.panelist_links l ON l.study_id=e.study_id AND l.panelist_id=e.panelist_id JOIN identity.memberships m ON m.id=l.membership_id JOIN identity.principals pr ON pr.id=m.principal_id JOIN research.rounds r ON r.id=e.round_id JOIN research.studies s ON s.id=e.study_id WHERE e.id=$1 AND e.study_id=$2", enrollment_id, c$study_id)
  if (nrow(e) != 1 || !isTRUE(e$panel_active) || !isTRUE(e$member_active) || !isTRUE(e$principal_active) || e$state == "withdrawn") {
    return("participation_inactive")
  }
  if (!e$study_state %in% c("draft", "active", "completed")) {
    return("study_inactive")
  }
  cap <- query(repo, "SELECT capability FROM identity.capabilities WHERE study_id=$1 AND membership_id=$2 AND capability='panel' AND revoked_at IS NULL", c$study_id, e$membership_id)
  if (!nrow(cap)) {
    return("panel_right_revoked")
  }
  latest <- query(repo, "SELECT decision FROM identity.consents WHERE study_id=$1 AND membership_id=$2 ORDER BY recorded_at DESC,id DESC LIMIT 1", c$study_id, e$membership_id)
  if (nrow(latest) && !isTRUE(latest$decision)) {
    return("consent_withdrawn")
  }
  consent <- query(repo, "SELECT decision FROM identity.consents WHERE study_id=$1 AND membership_id=$2 AND consent_version_id=$3 ORDER BY recorded_at DESC,id DESC LIMIT 1", c$study_id, e$membership_id, e$consent_version_id)
  if (nrow(consent) && !isTRUE(consent$decision)) {
    return("consent_withdrawn")
  }
  if (!c$kind %in% c("invitation", "round_start") && !nrow(consent)) {
    return("consent_missing")
  }
  if (c$kind == "reminder" && e$state == "submitted") {
    return("already_submitted")
  }
  if (c$kind %in% c("round_start", "reminder", "deadline_change") && (!identical(e$round_state, "open") || !isTRUE(e$in_time))) {
    return("round_not_open")
  }
  NULL
}
complete_campaign_sink <- function(repo, j) {
  transaction(repo, function() {
    c <- one(query(repo, "SELECT * FROM ops.campaigns WHERE id=$1 FOR SHARE", j$campaign_id))
    # Use round/enrollment ordering shared with Save/Submit/Close before checking eligibility.
    query(repo, "SELECT id FROM research.rounds WHERE id=$1 FOR SHARE", c$round_id)
    query(repo, "SELECT id FROM research.enrollments WHERE id=$1 FOR UPDATE", j$enrollment_id)
    one(query(repo, "SELECT message_id FROM ops.message_delivery WHERE message_id=$1 AND state='running' AND lease_token=$2 AND lease_until>clock_timestamp() FOR UPDATE", j$id, j$lease_token))
    reason <- campaign_recipient_reason(repo, c, j$enrollment_id)
    state <- if (is.null(reason)) "sink_recorded" else "suppressed"
    if (is.null(reason)) execute(repo, "INSERT INTO ops.message_sink(message_id,campaign_hash) VALUES($1,$2) ON CONFLICT(message_id) DO NOTHING", j$id, c$hash)
    execute(repo, "UPDATE ops.message_delivery SET state=$2,reason=$3,lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp() WHERE message_id=$1", j$id, state, if (is.null(reason)) NA_character_ else reason)
    approver <- one(query(repo, "SELECT approved_by FROM ops.campaign_releases WHERE campaign_id=$1", c$id))$approved_by
    audit(repo, list(principal_id = approver), j$study_id, paste0("message_", state), j$id)
    list(id = j$id, state = state, reason = reason)
  })
}
#' Process one approved message into a local database sink
#' @param repo Trusted separate development/test worker repository.
#' @param study_id Optional study UUID restricting the worker partition.
#' @param lease_seconds Claim duration from 1 to 300 seconds.
#' @return FALSE when idle or a message id/state/reason. Never sends external mail.
#' @export
process_campaign_sink <- function(repo, study_id = NULL, lease_seconds = 30L) {
  j <- claim_campaign_message(repo, study_id, lease_seconds)
  if (!nrow(j)) {
    return(FALSE)
  }
  complete_campaign_sink(repo, j)
}

#' List rounds available to a campaign coordinator
#' @param repo Repository.
#' @param actor Actor with coordinate capability.
#' @param study_id Study UUID.
#' @return Minimal round identifiers, numbers and states.
#' @export
list_campaign_rounds <- function(repo, actor, study_id) {
  authorize(repo, actor, study_id, "coordinate")
  query(repo, "SELECT id,number,state FROM research.rounds WHERE study_id=$1 ORDER BY number", study_id)
}

#' Preview eligible campaign selection fields without contacts or answers
#' @param repo Repository.
#' @param actor Actor with coordinate capability.
#' @param round_id Round UUID.
#' @return Enrollment UUID, study pseudonym and participation state.
#' @export
list_campaign_enrollments <- function(repo, actor, round_id) {
  r <- round_get(repo, actor, round_id, "coordinate")
  query(repo, "SELECT id AS enrollment_id,panelist_id AS pseudonym,state FROM research.enrollments WHERE study_id=$1 AND round_id=$2 ORDER BY id", r$study_id, r$id)
}
