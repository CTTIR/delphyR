#' Prepare an exact synthetic communication campaign
#' @param repo Development/test repository.
#' @param actor Actor with coordinate capability.
#' @param round_id Study round UUID.
#' @param enrollment_ids Exact recipient enrollment UUIDs; no addresses accepted.
#' @param kind invitation, round_start, reminder, deadline_change or completion.
#' @param subject,body Final plain text without unresolved template placeholders.
#' @param locale en, fr or de.
#' @param template_version Positive immutable template version.
#' @param command_id Idempotency key.
#' @return Campaign id, exact content/recipient hash and recipient count.
#' @export
prepare_campaign <- function(repo, actor, round_id, enrollment_ids, kind, subject, body,
                             locale = "en", template_version = 1L, command_id) {
  transaction(repo, function() {
    ensure(repo$environment %in% c("development", "test"), "communications.sink_only", "DEL_FORBIDDEN")
    r <- round_get(repo, actor, round_id, "coordinate", " FOR SHARE")
    ensure(is.character(enrollment_ids) && length(enrollment_ids) > 0 && length(enrollment_ids) <= 10000 && !anyDuplicated(enrollment_ids), "campaign.recipients")
    for (id in enrollment_ids) valid_id(id)
    ensure(length(kind) == 1 && kind %in% c("invitation", "round_start", "reminder", "deadline_change", "completion"), "campaign.kind")
    ensure(scalar_text(subject) && nchar(subject, type = "bytes") <= 200 && scalar_text(body) && nchar(body, type = "bytes") <= 20000 &&
      !grepl("[\r\n]", subject) && !grepl("{{", paste(subject, body), fixed = TRUE) && !grepl("}}", paste(subject, body), fixed = TRUE), "campaign.text")
    ensure(length(locale) == 1 && locale %in% c("en", "fr", "de") && whole(template_version) && length(template_version) == 1 && template_version > 0, "campaign.template")
    recipients <- sort(enrollment_ids)
    payload <- list(round_id = round_id, enrollment_ids = recipients, kind = kind, subject = subject, body = body, locale = locale, template_version = template_version)
    command(repo, actor, r$study_id, "campaign_prepare", command_id, payload, function() {
      for (e in recipients) one(query(repo, "SELECT id FROM research.enrollments WHERE study_id=$1 AND round_id=$2 AND id=$3", r$study_id, round_id, e))
      id <- uid()
      h <- content_hash(payload)
      execute(repo, "INSERT INTO ops.campaigns(id,study_id,round_id,kind,locale,template_version,subject,body,hash,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)", id, r$study_id, round_id, kind, locale, template_version, subject, body, h, actor$principal_id)
      for (e in recipients) execute(repo, "INSERT INTO ops.campaign_recipients VALUES($1,$2,$3,$4)", r$study_id, round_id, id, e)
      list(id = id, hash = h, n_recipients = length(recipients))
    }, detail = kind)
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
#' @return Plain text, hash, the study's reminder rules, the approved send
#'   window, pseudonyms and delivery states; no contacts or answers.
#' @export
preview_campaign <- function(repo, actor, campaign_id) {
  c <- campaign_get(repo, actor, campaign_id)
  schedule <- query(repo, "SELECT to_char(not_before AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS not_before,to_char(quiet_start,'HH24:MI') AS quiet_start,to_char(quiet_end,'HH24:MI') AS quiet_end,timezone FROM ops.campaign_schedules WHERE campaign_id=$1", c$id)
  list(
    id = c$id, kind = c$kind, subject = c$subject, body = c$body, locale = c$locale, hash = c$hash,
    rules = campaign_rules(repo, c$round_id),
    schedule = if (nrow(schedule)) as.list(schedule) else NULL,
    released = nrow(query(repo, "SELECT id FROM ops.campaign_releases WHERE campaign_id=$1", c$id)) == 1L,
    cancelled = nrow(query(repo, "SELECT id FROM ops.campaign_cancellations WHERE campaign_id=$1", c$id)) == 1L,
    recipients = query(repo, "SELECT e.id AS enrollment_id,e.panelist_id AS pseudonym,coalesce(d.state,'draft') AS delivery_state,d.reason FROM ops.campaign_recipients cr JOIN research.enrollments e ON e.id=cr.enrollment_id LEFT JOIN ops.message_outbox o ON o.campaign_id=cr.campaign_id AND o.enrollment_id=cr.enrollment_id LEFT JOIN ops.message_delivery d ON d.message_id=o.id WHERE cr.campaign_id=$1 ORDER BY e.id", c$id)
  )
}
# Reminder limits and quiet hours of the protocol under which a round runs.
campaign_rules <- function(repo, round_id) {
  x <- one(query(repo, "SELECT p.config::text AS config FROM research.rounds r JOIN research.protocol_versions p ON p.id=r.protocol_id WHERE r.id=$1", round_id))
  config <- from_json(x$config)
  rules <- config$communications
  list(
    timezone = config$study$timezone, quiet_start = rules$quiet_hours$start, quiet_end = rules$quiet_hours$end,
    max_reminders = rules$max_reminders, min_reminder_interval_hours = rules$min_reminder_interval_hours
  )
}
# Earlier reminders that count against the limit: approved, not cancelled, and
# neither suppressed nor failed nor abandoned for that recipient.
prior_reminders <- function(repo, c) {
  query(repo, "SELECT cr.enrollment_id,count(*)::int AS n,max(COALESCE(s.not_before,rel.approved_at)) AS latest
    FROM ops.campaign_recipients cr JOIN ops.campaigns k ON k.id=cr.campaign_id AND k.kind='reminder' AND k.id<>$3
    JOIN ops.campaign_releases rel ON rel.campaign_id=k.id
    LEFT JOIN ops.campaign_schedules s ON s.campaign_id=k.id
    LEFT JOIN ops.message_outbox o ON o.campaign_id=k.id AND o.enrollment_id=cr.enrollment_id
    LEFT JOIN ops.message_delivery d ON d.message_id=o.id
    WHERE k.study_id=$1 AND k.round_id=$2
      AND NOT EXISTS(SELECT 1 FROM ops.campaign_cancellations x WHERE x.campaign_id=k.id)
      AND COALESCE(d.state,'queued') NOT IN ('suppressed','failed','abandoned')
      AND cr.enrollment_id IN (SELECT enrollment_id FROM ops.campaign_recipients WHERE campaign_id=$3)
    GROUP BY cr.enrollment_id", c$study_id, c$round_id, c$id)
}
#' Release an exact synthetic campaign and atomically create its outbox
#'
#' The approval covers the exact text, the exact recipients and the earliest
#' send time. Quiet hours of the protocol are fixed with the approval. A
#' reminder is refused when any recipient would exceed the protocol's maximum
#' number of reminders or receive it sooner than the minimum interval after
#' the previous one; the limits never shrink an approved audience silently.
#' @param repo Repository.
#' @param actor Actor with coordinate capability.
#' @param campaign_id Campaign UUID.
#' @param expected_hash Hash reviewed in preview.
#' @param reason Human approval rationale.
#' @param command_id Idempotency key.
#' @param not_before Earliest send time with an explicit offset, for example
#'   "2026-10-05T09:00:00+02:00"; NULL means now. At most 90 days ahead.
#' @return Campaign id, approved recipient count and the approved earliest
#'   send time. No message is sent.
#' @export
release_campaign <- function(repo, actor, campaign_id, expected_hash, reason, command_id, not_before = NULL) {
  transaction(repo, function() {
    c <- campaign_get(repo, actor, campaign_id, TRUE)
    ensure(scalar_text(reason), "campaign.reason")
    if (!is.null(not_before)) ensure(scalar_text(not_before) && grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$", not_before), "campaign.not_before")
    command(repo, actor, c$study_id, "campaign_release", command_id, list(campaign_id, expected_hash, reason, not_before), function() {
      ensure(identical(c$hash, expected_hash) && identical(c$hash, campaign_hash(repo, c)), "campaign.hash", "DEL_CONFLICT")
      ensure(!nrow(query(repo, "SELECT id FROM ops.campaign_cancellations WHERE campaign_id=$1", c$id)) &&
        !nrow(query(repo, "SELECT id FROM ops.campaign_releases WHERE campaign_id=$1", c$id)), "campaign.state", "DEL_CONFLICT")
      rules <- campaign_rules(repo, c$round_id)
      window <- one(query(repo, "SELECT COALESCE($1::timestamptz,clock_timestamp()) AS send_at,COALESCE($1::timestamptz,clock_timestamp())<=clock_timestamp()+interval '90 days' AS near,COALESCE($1::timestamptz,clock_timestamp())>=clock_timestamp()-interval '5 minutes' AS current", if (is.null(not_before)) NA_character_ else not_before))
      ensure(isTRUE(window$near) && isTRUE(window$current), "campaign.not_before")
      if (c$kind == "reminder" && (!is.null(rules$max_reminders) || !is.null(rules$min_reminder_interval_hours))) {
        prior <- prior_reminders(repo, c)
        if (!is.null(rules$max_reminders)) ensure(rules$max_reminders > 0 && !any(prior$n >= rules$max_reminders), "campaign.reminder_limit", "DEL_CONFLICT")
        if (!is.null(rules$min_reminder_interval_hours) && nrow(prior)) {
          gap <- as.numeric(difftime(window$send_at, prior$latest, units = "hours"))
          ensure(all(gap >= rules$min_reminder_interval_hours), "campaign.reminder_interval", "DEL_CONFLICT")
        }
      }
      recipients <- query(repo, "SELECT enrollment_id FROM ops.campaign_recipients WHERE campaign_id=$1 ORDER BY enrollment_id", c$id)$enrollment_id
      execute(repo, "INSERT INTO ops.campaign_releases(id,study_id,campaign_id,approved_hash,reason,approved_by) VALUES($1,$2,$3,$4,$5,$6)", uid(), c$study_id, c$id, c$hash, reason, actor$principal_id)
      scheduled <- query(repo, "INSERT INTO ops.campaign_schedules(campaign_id,study_id,not_before,quiet_start,quiet_end,timezone) VALUES($1,$2,$3,$4::time,$5::time,$6) RETURNING to_char(not_before AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS not_before", c$id, c$study_id, window$send_at, if (is.null(rules$quiet_start)) NA_character_ else rules$quiet_start, if (is.null(rules$quiet_end)) NA_character_ else rules$quiet_end, rules$timezone)
      for (e in recipients) {
        id <- uid()
        execute(repo, "INSERT INTO ops.message_outbox(id,study_id,campaign_id,enrollment_id,dedupe_key) VALUES($1,$2,$3,$4,$5)", id, c$study_id, c$id, e, content_hash(list(c$id, e, c$hash)))
        execute(repo, "INSERT INTO ops.message_delivery(message_id) VALUES($1)", id)
      }
      list(id = c$id, n_recipients = length(recipients), not_before = scheduled$not_before)
    }, reason = reason)
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
    }, reason = reason)
  })
}
claim_campaign_message <- function(repo, study_id = NULL, lease_seconds = 30L) {
  transaction(repo, function() {
    ensure(repo$environment %in% c("development", "test"), "communications.sink_only", "DEL_FORBIDDEN")
    if (!is.null(study_id)) valid_id(study_id) else study_id <- NA_character_
    ensure(whole(lease_seconds) && length(lease_seconds) == 1 && lease_seconds > 0 && lease_seconds <= 300, "message.lease")
    execute(repo, "UPDATE ops.message_delivery d SET state='delivery_unknown',reason='expired_in_flight_lease',lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp() FROM ops.message_outbox o WHERE d.message_id=o.id AND d.state='running' AND d.lease_until<=clock_timestamp() AND ($1::uuid IS NULL OR o.study_id=$1)", study_id)
    # A message waits for its approved send time, outside the quiet hours of
    # the study's timezone, and for its retry time after a transient failure.
    j <- query(repo, "SELECT o.* FROM ops.message_outbox o JOIN ops.message_delivery d ON d.message_id=o.id LEFT JOIN ops.campaign_schedules s ON s.campaign_id=o.campaign_id
      WHERE d.state='queued' AND d.available_at<=clock_timestamp() AND ($1::uuid IS NULL OR o.study_id=$1)
        AND (s.campaign_id IS NULL OR (s.not_before<=clock_timestamp() AND (s.quiet_start IS NULL OR NOT (
          CASE WHEN s.quiet_start<s.quiet_end THEN (clock_timestamp() AT TIME ZONE s.timezone)::time>=s.quiet_start AND (clock_timestamp() AT TIME ZONE s.timezone)::time<s.quiet_end
               ELSE (clock_timestamp() AT TIME ZONE s.timezone)::time>=s.quiet_start OR (clock_timestamp() AT TIME ZONE s.timezone)::time<s.quiet_end END))))
      ORDER BY o.created_at,o.id LIMIT 1 FOR UPDATE OF d SKIP LOCKED", study_id)
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
  if (identical(e$round_state, "cancelled")) {
    return("round_cancelled")
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
    execute(repo, "UPDATE ops.message_delivery SET state=$2,reason=$3,adapter='database_sink',lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp() WHERE message_id=$1", j$id, state, if (is.null(reason)) NA_character_ else reason)
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
  process_campaign_message(repo, sink_adapter(), study_id, lease_seconds)
}
sink_adapter <- function() structure(list(name = "database_sink", external = FALSE), class = "delphyr_message_adapter")
#' Define a message provider adapter
#'
#' The contract for a delivery provider. `send` receives one message as a list
#' with message_id, idempotency_key, kind, locale, subject, body, to and
#' display_name, and must return `list(status = "accepted", provider_ref = )`,
#' `list(status = "rejected", reason = )` for a permanent refusal or
#' `list(status = "retry", reason = )` for a transient failure. The same
#' idempotency key is passed on every attempt for a message. An error, a
#' timeout or any other return value leaves the delivery uncertain; it is then
#' never repeated automatically. No production adapter is shipped or approved:
#' contact addresses are restricted to the reserved `.invalid` domain.
#' @param name Short adapter name recorded with each delivery.
#' @param send Function of one message, as described.
#' @return A delphyr_message_adapter for process_campaign_message().
#' @export
new_message_adapter <- function(name, send) {
  ensure(scalar_text(name) && grepl("^[a-z0-9_]{1,40}$", name) && !identical(name, "database_sink") && is.function(send), "adapter")
  structure(list(name = name, external = TRUE, send = send), class = "delphyr_message_adapter")
}
#' Process one approved message through a delivery adapter
#'
#' Claim, eligibility check and result are separate short transactions; no
#' database transaction is held while the provider is called. Immediately
#' before sending, the worker rechecks cancellation, approval authority,
#' participation, consent, submission and round state, which can only reduce
#' the approved audience. A transient failure is retried with a growing delay
#' up to three attempts.
#' @inheritParams process_campaign_sink
#' @param adapter Adapter from new_message_adapter(); the default is the local
#'   database sink.
#' @return FALSE when idle, or message id, state and reason.
#' @export
process_campaign_message <- function(repo, adapter = sink_adapter(), study_id = NULL, lease_seconds = 30L) {
  ensure(inherits(adapter, "delphyr_message_adapter"), "adapter")
  j <- claim_campaign_message(repo, study_id, lease_seconds)
  if (!nrow(j)) {
    return(FALSE)
  }
  if (!isTRUE(adapter$external)) {
    return(complete_campaign_sink(repo, j))
  }
  finish <- function(state, reason = NULL, provider_ref = NULL, retry_seconds = NULL) {
    transaction(repo, function() {
      # A lease that expired meanwhile has already made the delivery uncertain.
      held <- query(repo, "SELECT message_id FROM ops.message_delivery WHERE message_id=$1 AND state='running' AND lease_token=$2 FOR UPDATE", j$id, j$lease_token)
      if (!nrow(held)) {
        return(list(id = j$id, state = "delivery_unknown", reason = "expired_in_flight_lease"))
      }
      execute(repo, "UPDATE ops.message_delivery SET state=$2,reason=$3,provider_ref=$4,adapter=$5,available_at=clock_timestamp()+$6*interval '1 second',lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp() WHERE message_id=$1", j$id, state, if (is.null(reason)) NA_character_ else reason, if (is.null(provider_ref)) NA_character_ else provider_ref, adapter$name, if (is.null(retry_seconds)) 0 else retry_seconds)
      approver <- one(query(repo, "SELECT approved_by FROM ops.campaign_releases WHERE campaign_id=$1", j$campaign_id))$approved_by
      audit(repo, list(principal_id = approver), j$study_id, paste0("message_", state), j$id, detail = adapter$name)
      list(id = j$id, state = state, reason = reason)
    })
  }
  prepared <- transaction(repo, function() {
    c <- one(query(repo, "SELECT * FROM ops.campaigns WHERE id=$1 FOR SHARE", j$campaign_id))
    query(repo, "SELECT id FROM research.rounds WHERE id=$1 FOR SHARE", c$round_id)
    query(repo, "SELECT id FROM research.enrollments WHERE id=$1 FOR UPDATE", j$enrollment_id)
    one(query(repo, "SELECT message_id FROM ops.message_delivery WHERE message_id=$1 AND state='running' AND lease_token=$2 AND lease_until>clock_timestamp() FOR UPDATE", j$id, j$lease_token))
    reason <- campaign_recipient_reason(repo, c, j$enrollment_id)
    contact <- query(repo, "SELECT k.email,k.display_name FROM research.enrollments e JOIN identity.panel_invitation_acceptances a ON a.study_id=e.study_id AND a.panelist_id=e.panelist_id JOIN identity.panel_invitation_drafts d ON d.study_id=a.study_id AND d.id=a.draft_id JOIN identity.panel_contacts k ON k.study_id=d.study_id AND k.id=d.contact_id WHERE e.id=$1", j$enrollment_id)
    if (is.null(reason) && nrow(contact) != 1L) reason <- "no_contact"
    attempts <- one(query(repo, "SELECT attempts FROM ops.message_delivery WHERE message_id=$1", j$id))$attempts
    list(reason = reason, attempts = attempts, message = if (is.null(reason)) list(message_id = j$id, idempotency_key = j$dedupe_key, kind = c$kind, locale = c$locale, subject = c$subject, body = c$body, to = contact$email, display_name = contact$display_name))
  })
  if (!is.null(prepared$reason)) {
    return(finish("suppressed", prepared$reason))
  }
  outcome <- tryCatch(adapter$send(prepared$message), error = function(e) NULL)
  status <- if (is.list(outcome) && is.character(outcome$status) && length(outcome$status) == 1L) outcome$status else "unknown"
  code <- function(x, default) if (is.character(x) && length(x) == 1L && grepl("^[a-z0-9_]{1,60}$", x)) x else default
  if (identical(status, "accepted") && scalar_text(outcome$provider_ref) && nchar(outcome$provider_ref, type = "bytes") <= 200L) {
    return(finish("accepted", provider_ref = outcome$provider_ref))
  }
  if (identical(status, "rejected")) {
    return(finish("failed", code(outcome$reason, "provider_rejected")))
  }
  if (identical(status, "retry")) {
    if (prepared$attempts >= 3L) {
      return(finish("failed", "retries_exhausted"))
    }
    # Growing delay with jitter; the idempotency key stays the same.
    return(finish("queued", code(outcome$reason, "provider_retry"), retry_seconds = 60 * 2^prepared$attempts + stats::runif(1, 0, 30)))
  }
  # The provider may or may not have accepted the message.
  finish("delivery_unknown", "adapter_outcome_unknown")
}
#' List deliveries whose outcome is uncertain
#' @param repo Repository.
#' @param actor Actor with coordinate capability.
#' @param study_id Study UUID.
#' @return Message UUID, campaign kind, round number, study pseudonym, the
#'   cause, the adapter and the time of the uncertain attempt.
#' @export
list_uncertain_deliveries <- function(repo, actor, study_id) {
  authorize(repo, actor, study_id, "coordinate")
  query(repo, "SELECT o.id AS message_id,c.kind,r.number AS round_number,e.panelist_id AS pseudonym,d.reason,COALESCE(d.adapter,'') AS adapter,d.attempts,d.updated_at::text AS updated_at FROM ops.message_delivery d JOIN ops.message_outbox o ON o.id=d.message_id JOIN ops.campaigns c ON c.id=o.campaign_id JOIN research.rounds r ON r.id=c.round_id JOIN research.enrollments e ON e.id=o.enrollment_id WHERE o.study_id=$1 AND d.state='delivery_unknown' ORDER BY d.updated_at,o.id", study_id)
}
#' Resolve an uncertain delivery by a documented human decision
#'
#' An uncertain delivery is never repeated automatically, because the message
#' may already have been delivered. A coordinator decides with a rationale:
#' `confirmed_delivered` records that delivery was verified; `requeue` sends it
#' again and accepts a possible duplicate; `abandon` stops it. Before a
#' requeued message is sent, eligibility is checked again.
#' @inheritParams list_uncertain_deliveries
#' @param message_id Message UUID from list_uncertain_deliveries().
#' @param resolution confirmed_delivered, requeue or abandon.
#' @param reason Rationale, including how delivery was or was not verified.
#' @param command_id Idempotency key.
#' @return Message UUID and its new delivery state.
#' @export
resolve_delivery <- function(repo, actor, study_id, message_id, resolution, reason, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "coordinate")
    valid_id(message_id)
    ensure(length(resolution) == 1L && resolution %in% c("confirmed_delivered", "requeue", "abandon"), "delivery.resolution")
    ensure(scalar_text(reason) && nchar(reason, type = "bytes") <= 10000L, "delivery.reason")
    one(query(repo, "SELECT id FROM ops.message_outbox WHERE study_id=$1 AND id=$2", study_id, message_id))
    command(repo, actor, study_id, "delivery_resolution", command_id, list(message_id, resolution, reason), function() {
      d <- one(query(repo, "SELECT state FROM ops.message_delivery WHERE message_id=$1 FOR UPDATE", message_id))
      ensure(d$state == "delivery_unknown", "delivery.state", "DEL_CONFLICT")
      state <- c(confirmed_delivered = "resolved_delivered", requeue = "queued", abandon = "abandoned")[[resolution]]
      execute(repo, "INSERT INTO ops.delivery_resolutions(id,study_id,message_id,resolution,reason,actor_id) VALUES($1,$2,$3,$4,$5,$6)", uid(), study_id, message_id, resolution, reason, actor$principal_id)
      execute(repo, "UPDATE ops.message_delivery SET state=$2,reason=$3,available_at=clock_timestamp(),lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp() WHERE message_id=$1", message_id, state, paste0("resolved_", resolution))
      list(id = message_id, state = state)
    }, reason = reason, detail = resolution)
  })
}
#' Operational status of a study's background work
#' @param repo Repository.
#' @param actor Actor with manage or coordinate capability.
#' @param study_id Study UUID.
#' @return Counts of jobs by type and state with the age of the oldest waiting
#'   job, counts of messages by delivery state with the age of the oldest
#'   waiting message, and the number of uncertain deliveries. No content.
#' @export
get_operations_status <- function(repo, actor, study_id) {
  authorize_any(repo, actor, study_id, c("manage", "coordinate"))
  list(
    jobs = query(repo, "SELECT type,profile,state,count(*)::int AS n,COALESCE(max(extract(epoch FROM clock_timestamp()-available_at)) FILTER (WHERE state IN ('queued','retry_wait')),0)::int AS oldest_waiting_seconds,string_agg(DISTINCT error_code, ', ') AS error_codes FROM ops.jobs WHERE study_id=$1 GROUP BY type,profile,state ORDER BY type,profile,state", study_id),
    messages = query(repo, "SELECT d.state,count(*)::int AS n,COALESCE(max(extract(epoch FROM clock_timestamp()-o.created_at)) FILTER (WHERE d.state='queued'),0)::int AS oldest_waiting_seconds FROM ops.message_delivery d JOIN ops.message_outbox o ON o.id=d.message_id WHERE o.study_id=$1 GROUP BY d.state ORDER BY d.state", study_id),
    uncertain_deliveries = query(repo, "SELECT count(*)::int AS n FROM ops.message_delivery d JOIN ops.message_outbox o ON o.id=d.message_id WHERE o.study_id=$1 AND d.state='delivery_unknown'", study_id)$n
  )
}

#' List rounds available to a campaign coordinator
#' @param repo Repository.
#' @param actor Actor with coordinate capability.
#' @param study_id Study UUID.
#' @return Minimal round identifiers, numbers and states.
#' @export
list_campaign_rounds <- function(repo, actor, study_id) {
  authorize(repo, actor, study_id, "coordinate")
  query(repo, "SELECT id,number,state FROM research.rounds WHERE study_id=$1 AND state<>'cancelled' ORDER BY number", study_id)
}

#' Preview eligible campaign selection fields without contacts or answers
#' @param repo Repository.
#' @param actor Actor with coordinate capability.
#' @param round_id Round UUID.
#' @return Enrollment UUID, study pseudonym, participation state and the
#'   number of approved reminders that count against the protocol's limit.
#' @export
list_campaign_enrollments <- function(repo, actor, round_id) {
  r <- round_get(repo, actor, round_id, "coordinate")
  query(repo, "SELECT e.id AS enrollment_id,e.panelist_id AS pseudonym,e.state,
      (SELECT count(*) FROM ops.campaign_recipients cr JOIN ops.campaigns k ON k.id=cr.campaign_id AND k.kind='reminder' JOIN ops.campaign_releases rel ON rel.campaign_id=k.id LEFT JOIN ops.message_outbox o ON o.campaign_id=k.id AND o.enrollment_id=cr.enrollment_id LEFT JOIN ops.message_delivery d ON d.message_id=o.id
        WHERE cr.enrollment_id=e.id AND NOT EXISTS(SELECT 1 FROM ops.campaign_cancellations x WHERE x.campaign_id=k.id) AND COALESCE(d.state,'queued') NOT IN ('suppressed','failed','abandoned'))::int AS reminders
    FROM research.enrollments e WHERE e.study_id=$1 AND e.round_id=$2 ORDER BY e.id", r$study_id, r$id)
}
