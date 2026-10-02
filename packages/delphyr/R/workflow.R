protocol_for <- function(repo, study) {
  x <- one(query(repo, "SELECT id,config::text FROM research.protocol_versions WHERE study_id=$1 ORDER BY version DESC LIMIT 1", study))
  list(id = x$id, config = new_protocol(from_json(x$config)))
}
round_get <- function(repo, actor, id, capability = NULL, lock = "") {
  valid_id(id)
  x <- one(query(repo, "SELECT study_id FROM research.rounds WHERE id=$1", id))
  authorize(repo, actor, x$study_id, capability)
  ensure(lock %in% c("", " FOR SHARE", " FOR UPDATE"), "lock")
  result <- one(query(repo, paste0("SELECT *, deadline>clock_timestamp() AS in_time FROM research.rounds WHERE id=$1", lock), id))
  # A request may have waited behind a concurrent mutation or revocation.
  authorize(repo, actor, x$study_id, capability)
  result
}
#' Validate an instrument import before any database writes
#' @param items Data frame following the v1 item import contract, with item_version.
#' @param protocol Study protocol.
#' @return TRUE or a structured validation condition.
#' @export
validate_items <- function(items, protocol) {
  protocol <- new_protocol(protocol)
  fields <- c("item_code", "item_version", "locale", "text", "dimension_code", "scale_code", "source_ref", "required", "display_order")
  ensure(is.data.frame(items) && nrow(items) > 0 && nrow(items) <= 10000 && all(fields %in% names(items)), "items.columns")
  ensure(!anyNA(items[, fields]) && is.logical(items$required) && whole(items$item_version) && all(items$item_version > 0) && whole(items$display_order) && all(items$display_order > 0), "items.types")
  ensure(all(nchar(items$text, type = "bytes") <= 20000) & all(nzchar(trimws(items$text))) && all(grepl("^[A-Za-z0-9_-]{1,80}$", items$item_code)), "items.text")
  dims <- setNames(vapply(protocol$instrument$dimensions, `[[`, character(1), "scale"), vapply(protocol$instrument$dimensions, `[[`, character(1), "code"))
  ensure(all(items$dimension_code %in% names(dims)) && all(items$scale_code == dims[items$dimension_code]), "items.scale")
  key <- paste(items$item_code, items$dimension_code)
  ensure(!anyDuplicated(paste(key, items$locale)), "items.duplicate")
  for (k in unique(key)) {
    z <- items[key == k, , drop = FALSE]
    ensure(setequal(z$locale, unlist(protocol$study$languages)), "items.translations")
    ensure(nrow(unique(z[, setdiff(fields, c("locale", "text")), drop = FALSE])) == 1, "items.translation_config")
  }
  TRUE
}
#' Publish immutable synthetic study information
#' @param repo Repository.
#' @param actor Study manager.
#' @param study_id Study UUID.
#' @param text Displayed information, explicitly synthetic in development.
#' @param locale en, fr or de.
#' @param command_id Idempotency key.
#' @return Consent version id.
#' @export
publish_consent <- function(repo, actor, study_id, text, locale, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "manage")
    ensure(scalar_text(text) && nchar(text, type = "bytes") <= 50000L && scalar_text(locale) && locale %in% c("en", "fr", "de"), "consent")
    command(repo, actor, study_id, "publish_consent", command_id, list(text, locale), function() {
      id <- uid()
      execute(repo, "INSERT INTO identity.consent_versions(id,study_id,locale,content,hash) VALUES($1,$2,$3,$4,$5)", id, study_id, locale, text, content_hash(list(text, locale)))
      list(id = id)
    }, detail = locale)
  })
}
#' Record an explicit consent decision
#' @param repo Repository.
#' @param actor Panel actor.
#' @param study_id Study UUID.
#' @param consent_version_id Displayed version UUID.
#' @param decision TRUE for consent, FALSE for refusal or withdrawal.
#' @param command_id Idempotency key.
#' @return Consent event id.
#' @export
record_consent <- function(repo, actor, study_id, consent_version_id, decision, command_id) {
  transaction(repo, function() {
    m <- authorize(repo, actor, study_id, "panel")
    valid_id(consent_version_id)
    one(query(repo, "SELECT id FROM identity.consent_versions WHERE id=$1 AND study_id=$2", consent_version_id, study_id))
    ensure(is.logical(decision) && length(decision) == 1 && !is.na(decision), "consent.decision")
    command(repo, actor, study_id, "consent", command_id, list(consent_version_id, decision), function() {
      id <- uid()
      execute(repo, "INSERT INTO identity.consents(id,study_id,membership_id,consent_version_id,decision) VALUES($1,$2,$3,$4,$5)", id, study_id, m, consent_version_id, decision)
      list(id = id)
    }, detail = if (decision) "accepted" else "declined")
  })
}
#' Register a synthetic panel member
#' @param repo Repository.
#' @param actor Study manager.
#' @param study_id Study UUID.
#' @param principal_id Existing synthetic account UUID.
#' @param group_code Declared stakeholder group.
#' @param command_id Idempotency key.
#' @return Study-specific pseudonym.
#' @export
add_panelist <- function(repo, actor, study_id, principal_id, group_code, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "manage")
    valid_id(principal_id)
    p <- protocol_for(repo, study_id)$config
    ensure(group_code %in% unlist(p$panel$groups), "panel.group")
    command(repo, actor, study_id, "add_panelist", command_id, list(principal_id, group_code), function() {
      m <- query(repo, "INSERT INTO identity.memberships(id,study_id,principal_id) VALUES($1,$2,$3) ON CONFLICT(study_id,principal_id) DO UPDATE SET principal_id=EXCLUDED.principal_id RETURNING id", uid(), study_id, principal_id)$id
      ensure(!nrow(query(repo, "SELECT panelist_id FROM identity.panelist_links WHERE study_id=$1 AND membership_id=$2", study_id, m)), "panel.duplicate", "DEL_CONFLICT")
      id <- uid()
      execute(repo, "INSERT INTO research.panelists(id,study_id,group_code) VALUES($1,$2,$3)", id, study_id, group_code)
      execute(repo, "INSERT INTO identity.panelist_links VALUES($1,$2,$3)", study_id, m, id)
      execute(repo, "INSERT INTO identity.capabilities(study_id,membership_id,capability) VALUES($1,$2,'panel') ON CONFLICT DO NOTHING", study_id, m)
      list(id = id)
    }, detail = group_code)
  })
}
# Active panel members who may take part in the given round number under the
# protocol's entry policy. Withdrawn round candidates never count as rounds.
eligible_panel <- function(repo, study_id, number, config) {
  panel <- query(repo, "SELECT p.id,p.group_code FROM research.panelists p JOIN identity.panelist_links l ON l.study_id=p.study_id AND l.panelist_id=p.id JOIN identity.memberships m ON m.study_id=l.study_id AND m.id=l.membership_id JOIN identity.principals a ON a.id=m.principal_id JOIN identity.capabilities c ON c.study_id=m.study_id AND c.membership_id=m.id AND c.capability='panel' AND c.revoked_at IS NULL WHERE p.study_id=$1 AND p.active AND m.active AND a.active ORDER BY p.id", study_id)
  if (number > 1L) {
    prior <- query(repo, "SELECT e.panelist_id,r.number,(s.id IS NOT NULL) AS submitted FROM research.enrollments e JOIN research.rounds r ON r.id=e.round_id LEFT JOIN research.submissions s ON s.study_id=e.study_id AND s.enrollment_id=e.id WHERE e.study_id=$1 AND r.number<$2 AND r.state<>'cancelled'", study_id, number)
    first <- prior$panelist_id[prior$number == 1L]
    last_submitted <- prior$panelist_id[prior$number == number - 1L & prior$submitted]
    eligible <- rep(TRUE, nrow(panel))
    if (!config$panel$late_entry) eligible <- eligible & panel$id %in% first
    if (!config$panel$return_after_missed_round) {
      eligible <- eligible &
        (panel$id %in% last_submitted | (config$panel$late_entry & !panel$id %in% prior$panelist_id))
    }
    panel <- panel[eligible, , drop = FALSE]
  }
  panel
}
#' Prepare a frozen-instrument candidate and enroll active panelists
#' @param repo Repository.
#' @param actor Study manager.
#' @param study_id Study UUID.
#' @param items Validated multilingual import data frame.
#' @param consent_version_id Required study information version.
#' @param deadline UTC timestamp string with explicit offset.
#' @param command_id Idempotency key.
#' @return Round UUID and exact instrument hash.
#' @export
prepare_round <- function(repo, actor, study_id, items, consent_version_id, deadline, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "manage")
    valid_id(consent_version_id)
    one(query(repo, "SELECT id FROM research.studies WHERE id=$1 AND state IN ('draft','active') FOR UPDATE", study_id))
    authorize(repo, actor, study_id, "manage")
    p <- protocol_for(repo, study_id)
    validate_items(items, p$config)
    one(query(repo, "SELECT id FROM identity.consent_versions WHERE id=$1 AND study_id=$2", consent_version_id, study_id))
    valid_deadline(deadline)
    command(repo, actor, study_id, "prepare_round", command_id, list(items, consent_version_id, deadline), function() {
      # A withdrawn candidate neither occupies a round number nor blocks its successor.
      number <- query(repo, "SELECT COALESCE(MAX(number),0)+1 AS n FROM research.rounds WHERE study_id=$1 AND state<>'cancelled'", study_id)$n
      ensure(number <= p$config$stopping$max_rounds, "round.max")
      ensure(!nrow(query(repo, "SELECT id FROM research.rounds WHERE study_id=$1 AND state NOT IN ('released','finalized','cancelled')", study_id)), "round.previous", "DEL_CONFLICT")
      # Reusing a version is allowed only for exactly the same scientific content.
      # Withdrawn candidates were never presented and do not bind a version.
      previous_items <- query(repo, "SELECT i.item_code,i.item_version,i.dimension_code,i.scale_code,i.texts::text,i.source_ref FROM research.round_items i JOIN research.rounds r ON r.study_id=i.study_id AND r.id=i.round_id WHERE i.study_id=$1 AND r.state<>'cancelled'", study_id)
      for (k in unique(paste(items$item_code, items$dimension_code))) {
        z <- items[paste(items$item_code, items$dimension_code) == k, , drop = FALSE]
        old <- previous_items[previous_items$item_code == z$item_code[1] &
          previous_items$dimension_code == z$dimension_code[1] &
          previous_items$item_version == z$item_version[1], , drop = FALSE]
        text_hash <- content_hash(as.list(setNames(z$text, z$locale)))
        if (nrow(old)) {
          ensure(
            all(old$scale_code == z$scale_code[1]) &&
              all(old$source_ref == z$source_ref[1]) &&
              all(vapply(old$texts, function(x) identical(content_hash(from_json(x)), text_hash), logical(1))),
            "items.version_content", "DEL_CONFLICT"
          )
        }
      }
      id <- uid()
      h <- content_hash(list(items = items, protocol = p$config, consent = consent_version_id))
      execute(repo, "INSERT INTO research.rounds(id,study_id,number,protocol_id,consent_version_id,instrument_hash,deadline) VALUES($1,$2,$3,$4,$5,$6,$7::timestamptz)", id, study_id, number, p$id, consent_version_id, h, deadline)
      key <- paste(items$item_code, items$dimension_code)
      for (k in unique(key)) {
        z <- items[key == k, , drop = FALSE]
        texts <- as.list(setNames(z$text, z$locale))
        a <- z[1, ]
        execute(repo, "INSERT INTO research.round_items VALUES($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9,$10,$11)", uid(), study_id, id, a$item_code, a$item_version, a$dimension_code, a$scale_code, json(texts), a$required, a$display_order, a$source_ref)
      }
      # Opening, not preparation, requires enrolled panel members: the
      # instrument can be reviewed while recruitment is still under way.
      panel <- eligible_panel(repo, study_id, number, p$config)
      ensure(all(panel$group_code %in% unlist(p$config$panel$groups)), "round.panel_groups", "DEL_CONFLICT")
      for (i in seq_len(nrow(panel))) execute(repo, "INSERT INTO research.enrollments(id,study_id,round_id,panelist_id,group_code) VALUES($1,$2,$3,$4,$5)", uid(), study_id, id, panel$id[i], panel$group_code[i])
      list(id = id, hash = h)
    })
  })
}
# A deadline is a complete time with an explicit offset; the database never
# has to guess a timezone or reject a text.
valid_deadline <- function(deadline) {
  ensure(scalar_text(deadline) && grepl("(Z|[+-][0-9]{2}:[0-9]{2})$", deadline), "deadline.offset")
  ensure(grepl("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9]([.][0-9]{1,6})?)?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$", deadline) &&
    !is.na(as.Date(substr(deadline, 1L, 10L), format = "%Y-%m-%d", optional = TRUE)), "deadline.format")
}
#' Change the deadline of a round that is not closed
#'
#' The deadline is not part of the reviewed instrument, so the approval of a
#' round stays valid. Before a round opens the deadline may be any future
#' time. Once the round is open it can only be moved to a later time: nobody
#' loses time they were told they had. An open round whose deadline has
#' passed accepts answers again after an extension. A closed round is never
#' reopened this way. The change is recorded with its rationale in the
#' round's history and in the audit trail.
#' @param repo Repository.
#' @param actor Study manager.
#' @param round_id Round UUID.
#' @param deadline New deadline, a timestamp with explicit offset.
#' @param expected_hash Instrument hash of the round, as shown in its review.
#' @param reason Nonempty rationale.
#' @param command_id Idempotency key.
#' @return Round id and the new deadline in UTC.
#' @export
change_round_deadline <- function(repo, actor, round_id, deadline, expected_hash, reason, command_id) {
  transaction(repo, function() {
    r <- round_get(repo, actor, round_id, "manage", " FOR UPDATE")
    ensure(scalar_text(reason), "reason")
    valid_deadline(deadline)
    command(repo, actor, r$study_id, "round_deadline", command_id, list(round_id, deadline, expected_hash, reason), function() {
      ensure(identical(r$instrument_hash, expected_hash), "round.hash", "DEL_CONFLICT")
      ensure(r$state %in% c("draft", "review", "approved", "open"), "round.state", "DEL_CONFLICT")
      check <- one(query(repo, "SELECT $2::timestamptz>clock_timestamp() AS future,$2::timestamptz>deadline AS later FROM research.rounds WHERE id=$1", r$id, deadline))
      ensure(isTRUE(check$future), "deadline.past")
      ensure(r$state != "open" || isTRUE(check$later), "deadline.earlier", "DEL_CONFLICT")
      stamp <- query(repo, "UPDATE research.rounds SET deadline=$2::timestamptz WHERE id=$1 RETURNING to_char(deadline AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS deadline", r$id, deadline)$deadline
      execute(repo, "INSERT INTO research.round_events(id,study_id,round_id,target_state,content_hash,actor_id,reason) VALUES($1,$2,$3,'deadline_changed',$4,$5,$6)", uid(), r$study_id, r$id, expected_hash, actor$principal_id, reason)
      list(id = round_id, deadline = stamp)
    }, reason = reason, detail = deadline)
  })
}
#' Advance an authorized round through its approval lifecycle
#' @param repo Repository.
#' @param actor Study manager.
#' @param round_id Round UUID.
#' @param target review, approved, open, closed, finalized or cancelled. Approval
#'   and opening are refused with DEL_VALIDATION while get_round_readiness()
#'   reports blocking findings. Only a round that was never opened can be
#'   cancelled; a cancelled round is final and frees its round number.
#' @param expected_hash Exact instrument hash shown in review.
#' @param reason Nonempty human rationale.
#' @param command_id Idempotency key.
#' @return Round id and new state.
#' @export
transition_round <- function(repo, actor, round_id, target, expected_hash, reason, command_id) {
  transaction(repo, function() {
    r <- round_get(repo, actor, round_id, "manage", " FOR UPDATE")
    ensure(scalar_text(reason), "reason")
    command(repo, actor, r$study_id, "transition_round", command_id, list(round_id, target, expected_hash, reason), function() {
      ensure(identical(r$instrument_hash, expected_hash), "round.hash", "DEL_CONFLICT")
      allowed <- list(review = "draft", approved = "review", open = "approved", closed = "open", finalized = c("analysed", "released"), cancelled = c("draft", "review", "approved"))
      ensure(target %in% names(allowed) && r$state %in% allowed[[target]], "round.transition", "DEL_CONFLICT")
      if (target == "open") ensure(isTRUE(one(query(repo, "SELECT deadline>clock_timestamp() AS ok FROM research.rounds WHERE id=$1", r$id))$ok), "round.deadline", "DEL_ROUND_CLOSED")
      if (target %in% c("approved", "open")) {
        blocking <- readiness_blocking(round_readiness(repo, r), target)
        if (length(blocking)) del_abort("DEL_VALIDATION", paste0("round.readiness:", paste(blocking, collapse = ",")))
      }
      execute(repo, "UPDATE research.rounds SET state=$2,closed_at=CASE WHEN $2='closed' THEN clock_timestamp() ELSE closed_at END WHERE id=$1", round_id, target)
      execute(repo, "INSERT INTO research.round_events(id,study_id,round_id,target_state,content_hash,actor_id,reason) VALUES($1,$2,$3,$4,$5,$6,$7)", uid(), r$study_id, r$id, target, expected_hash, actor$principal_id, reason)
      if (target == "open") execute(repo, "UPDATE research.studies SET state='active' WHERE id=$1 AND state='draft'", r$study_id)
      list(id = round_id, state = target)
    }, reason = reason, detail = target)
  })
}
enrollment_get <- function(repo, actor, id, locking = TRUE) {
  valid_id(id)
  e <- one(query(repo, "SELECT * FROM research.enrollments WHERE id=$1", id))
  m <- authorize(repo, actor, e$study_id, "panel")
  link <- query(repo, "SELECT panelist_id FROM identity.panelist_links WHERE study_id=$1 AND membership_id=$2 AND panelist_id=$3", e$study_id, m, e$panelist_id)
  ensure(nrow(link) == 1, "enrollment", "DEL_NOT_FOUND")
  r <- round_get(repo, actor, e$round_id, lock = if (locking) " FOR SHARE" else "")
  e <- one(query(repo, paste0("SELECT * FROM research.enrollments WHERE id=$1", if (locking) " FOR UPDATE" else ""), id))
  m <- authorize(repo, actor, e$study_id, "panel")
  list(enrollment = e, round = r, membership = m)
}
can_respond <- function(repo, z) {
  r <- z$round
  e <- z$enrollment
  in_time <- one(query(repo, "SELECT deadline>clock_timestamp() AS ok FROM research.rounds WHERE id=$1", r$id))$ok
  ensure(r$state == "open" && isTRUE(in_time), "round", "DEL_ROUND_CLOSED")
  ensure(e$state %in% c("eligible", "in_progress"), "enrollment.state", "DEL_CONFLICT")
  s <- one(query(repo, "SELECT state FROM research.studies WHERE id=$1", r$study_id))
  ensure(s$state == "active", "study.state", "DEL_FORBIDDEN")
  active <- query(repo, "SELECT id FROM research.panelists WHERE id=$1 AND active", e$panelist_id)
  ensure(nrow(active) == 1, "participation", "DEL_FORBIDDEN")
  c <- query(repo, "SELECT decision FROM identity.consents WHERE study_id=$1 AND membership_id=$2 AND consent_version_id=$3 ORDER BY recorded_at DESC LIMIT 1", r$study_id, z$membership, r$consent_version_id)
  ensure(nrow(c) == 1 && isTRUE(c$decision), "consent", "DEL_FORBIDDEN")
}
current_responses <- function(repo, e) query(repo, "SELECT v.* FROM research.response_current c JOIN research.response_revisions v ON v.study_id=c.study_id AND v.enrollment_id=c.enrollment_id AND v.round_item_id=c.round_item_id AND v.revision=c.revision WHERE c.study_id=$1 AND c.enrollment_id=$2 ORDER BY v.round_item_id", e$study_id, e$id)
#' Save a response with optimistic concurrency and a durable receipt
#' @param repo Repository.
#' @param actor Panel actor.
#' @param enrollment_id Own enrollment UUID.
#' @param round_item_id Assigned response field UUID.
#' @param response List with value and status.
#' @param expected_revision Last confirmed revision; zero for first save.
#' @param command_id Idempotency key, reused only for identical retries.
#' @return Committed revision id, revision and server time.
#' @export
save_response <- function(repo, actor, enrollment_id, round_item_id, response, expected_revision, command_id) {
  transaction(repo, function() {
    z <- enrollment_get(repo, actor, enrollment_id)
    e <- z$enrollment
    valid_id(round_item_id)
    command(repo, actor, e$study_id, "save", command_id, list(enrollment_id, round_item_id, response, expected_revision), function() {
      can_respond(repo, z)
      it <- one(query(repo, "SELECT * FROM research.round_items WHERE study_id=$1 AND round_id=$2 AND id=$3", e$study_id, e$round_id, round_item_id))
      p <- one(query(repo, "SELECT config::text FROM research.protocol_versions WHERE id=$1", z$round$protocol_id))
      known_keys(response, c("value", "status"), "response")
      ans <- validate_response(response$value, response$status, config_scales(from_json(p$config))[[it$scale_code]])
      ensure(whole(expected_revision) && length(expected_revision) == 1 && expected_revision >= 0, "expected_revision")
      cur <- query(repo, "SELECT revision FROM research.response_current WHERE study_id=$1 AND enrollment_id=$2 AND round_item_id=$3", e$study_id, e$id, it$id)
      rev <- if (nrow(cur)) cur$revision else 0L
      ensure(rev == expected_revision, "revision", "DEL_CONFLICT")
      id <- uid()
      rev <- rev + 1L
      created <- query(repo, "INSERT INTO research.response_revisions(id,study_id,round_id,enrollment_id,round_item_id,revision,status,value_int,value_text) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING created_at::text", id, e$study_id, e$round_id, e$id, it$id, rev, ans$status, ans$value_int, ans$value_text)$created_at
      execute(repo, "INSERT INTO research.response_current VALUES($1,$2,$3,$4,$5) ON CONFLICT(study_id,enrollment_id,round_item_id) DO UPDATE SET revision=EXCLUDED.revision", e$study_id, e$round_id, e$id, it$id, rev)
      execute(repo, "UPDATE research.enrollments SET state='in_progress' WHERE id=$1", e$id)
      list(id = id, revision = rev, saved_at = created)
    })
  })
}
#' Submit the exact confirmed revision set atomically
#' @param repo Repository.
#' @param actor Panel actor.
#' @param enrollment_id Own enrollment UUID.
#' @param expected_revision_set Named integer vector: round-item UUID to revision.
#' @param command_id Idempotency key.
#' @return Durable submission receipt id and timestamp.
#' @export
submit_round <- function(repo, actor, enrollment_id, expected_revision_set, command_id) {
  transaction(repo, function() {
    z <- enrollment_get(repo, actor, enrollment_id)
    e <- z$enrollment
    command(repo, actor, e$study_id, "submit", command_id, list(enrollment_id, expected_revision_set), function() {
      previous <- query(repo, "SELECT id,submitted_at::text FROM research.submissions WHERE study_id=$1 AND enrollment_id=$2", e$study_id, e$id)
      if (nrow(previous)) {
        return(list(id = previous$id, submitted_at = previous$submitted_at))
      }
      can_respond(repo, z)
      cur <- current_responses(repo, e)
      observed <- setNames(cur$revision, cur$round_item_id)
      ensure(!is.null(names(expected_revision_set)) && !anyDuplicated(names(expected_revision_set)) && setequal(names(observed), names(expected_revision_set)) && all(observed == expected_revision_set[names(observed)]), "revision_set", "DEL_CONFLICT")
      items <- query(repo, "SELECT id,required FROM research.round_items WHERE study_id=$1 AND round_id=$2", e$study_id, e$round_id)
      answered <- cur$round_item_id[cur$status != "not_answered"]
      ensure(all(items$id[items$required] %in% answered), "submission.required")
      id <- uid()
      stamp <- query(repo, "INSERT INTO research.submissions(id,study_id,round_id,enrollment_id) VALUES($1,$2,$3,$4) RETURNING submitted_at::text", id, e$study_id, e$round_id, e$id)$submitted_at
      for (v in cur$id) execute(repo, "INSERT INTO research.submission_entries VALUES($1,$2,$3,$4,$5)", e$study_id, e$round_id, e$id, id, v)
      execute(repo, "UPDATE research.enrollments SET state='submitted' WHERE id=$1", e$id)
      list(id = id, submitted_at = stamp)
    })
  })
}
#' Retrieve only the actor's current questionnaire and consent information
#' @param repo Repository.
#' @param actor Panel actor.
#' @param enrollment_id Own enrollment UUID.
#' @return Instrument, own responses, receipt and required consent information.
#' @export
get_questionnaire <- function(repo, actor, enrollment_id) {
  transaction(repo, function() {
    z <- enrollment_get(repo, actor, enrollment_id, FALSE)
    e <- z$enrollment
    cver <- one(query(repo, "SELECT id,locale,content FROM identity.consent_versions WHERE id=$1", z$round$consent_version_id))
    decision <- query(repo, "SELECT decision FROM identity.consents WHERE study_id=$1 AND membership_id=$2 AND consent_version_id=$3 ORDER BY recorded_at DESC LIMIT 1", e$study_id, z$membership, z$round$consent_version_id)
    cver$accepted <- nrow(decision) == 1 && isTRUE(decision$decision)
    list(round = z$round, enrollment = e, items = query(repo, "SELECT id,item_code,item_version,dimension_code,scale_code,texts::text,required,display_order FROM research.round_items WHERE study_id=$1 AND round_id=$2 ORDER BY display_order,item_code,dimension_code", e$study_id, e$round_id), responses = current_responses(repo, e), protocol = from_json(one(query(repo, "SELECT config::text FROM research.protocol_versions WHERE id=$1", z$round$protocol_id))$config), consent = cver, receipt = query(repo, "SELECT id,submitted_at::text FROM research.submissions WHERE study_id=$1 AND enrollment_id=$2", e$study_id, e$id))
  })
}
#' List own round enrollments
#' @param repo Repository.
#' @param actor Panel actor.
#' @param study_id Selected study.
#' @return Enrollment table.
#' @export
list_enrollments <- function(repo, actor, study_id) {
  m <- authorize(repo, actor, study_id, "panel")
  query(repo, "SELECT e.id,e.state,r.number,r.state AS round_state FROM research.enrollments e JOIN identity.panelist_links l ON l.study_id=e.study_id AND l.panelist_id=e.panelist_id JOIN research.rounds r ON r.id=e.round_id WHERE e.study_id=$1 AND l.membership_id=$2 AND r.state<>'cancelled' ORDER BY r.number", study_id, m)
}
# Findings that decide whether a round may be approved or opened. Content
# findings block approval; opening additionally needs time and participants.
round_readiness <- function(repo, r) {
  # Query parameters are evaluated lazily after a statement is sent; the round
  # must already be resolved so that no query starts inside another.
  force(r)
  issues <- list()
  add <- function(severity, code, path, details = "") {
    issues[[length(issues) + 1L]] <<- data.frame(severity = severity, code = code, path = path, message_key = paste0("readiness.", code), details = as.character(details), stringsAsFactors = FALSE)
  }
  finish <- function() {
    table <- if (length(issues)) do.call(rbind, issues) else data.frame(severity = character(), code = character(), path = character(), message_key = character(), details = character(), stringsAsFactors = FALSE)
    structure(list(valid = !any(table$severity == "error"), issues = table, schema_version = "1.0"), class = "delphyr_validation")
  }
  study <- one(query(repo, "SELECT state FROM research.studies WHERE id=$1", r$study_id))
  if (!study$state %in% c("draft", "active")) add("error", "study_not_active", "study.state", study$state)
  latest <- one(query(repo, "SELECT id,version FROM research.protocol_versions WHERE study_id=$1 ORDER BY version DESC LIMIT 1", r$study_id))
  own <- one(query(repo, "SELECT version,config::text FROM research.protocol_versions WHERE id=$1", r$protocol_id))
  if (!identical(latest$id, r$protocol_id)) add("error", "protocol_superseded", "round.protocol", paste0("round: version ", own$version, "; current: version ", latest$version))
  protocol <- tryCatch(new_protocol(from_json(own$config)), error = function(e) e)
  if (inherits(protocol, "error")) {
    add("error", "protocol_invalid", if (inherits(protocol, "delphyr_error")) protocol$path else "protocol")
    return(finish())
  }
  languages <- unlist(protocol$study$languages)
  consent <- one(query(repo, "SELECT locale FROM identity.consent_versions WHERE id=$1", r$consent_version_id))
  if (!consent$locale %in% languages) add("error", "consent_language", "round.consent", consent$locale)
  items <- query(repo, "SELECT item_code,dimension_code,scale_code,texts::text FROM research.round_items WHERE study_id=$1 AND round_id=$2 ORDER BY display_order,item_code,dimension_code", r$study_id, r$id)
  if (!nrow(items)) add("error", "no_items", "round.items")
  dims <- setNames(vapply(protocol$instrument$dimensions, `[[`, character(1), "scale"), vapply(protocol$instrument$dimensions, `[[`, character(1), "code"))
  for (i in seq_len(nrow(items))) {
    path <- paste("items", items$item_code[i], items$dimension_code[i], sep = ".")
    if (!items$dimension_code[i] %in% names(dims) || !identical(unname(dims[items$dimension_code[i]]), items$scale_code[i])) add("error", "dimension_unknown", path, items$scale_code[i])
    missing <- setdiff(languages, names(from_json(items$texts[i])))
    if (length(missing)) add("error", "translation_missing", path, paste(missing, collapse = ","))
  }
  if (!isTRUE(one(query(repo, "SELECT deadline>clock_timestamp() AS ok FROM research.rounds WHERE id=$1", r$id))$ok)) add("error", "deadline_passed", "round.deadline")
  enrolled <- query(repo, "SELECT e.panelist_id,e.group_code FROM research.enrollments e JOIN research.panelists p ON p.study_id=e.study_id AND p.id=e.panelist_id JOIN identity.panelist_links l ON l.study_id=e.study_id AND l.panelist_id=e.panelist_id JOIN identity.memberships m ON m.study_id=l.study_id AND m.id=l.membership_id JOIN identity.principals a ON a.id=m.principal_id JOIN identity.capabilities c ON c.study_id=m.study_id AND c.membership_id=m.id AND c.capability='panel' AND c.revoked_at IS NULL WHERE e.study_id=$1 AND e.round_id=$2 AND e.state<>'withdrawn' AND p.active AND m.active AND a.active", r$study_id, r$id)
  if (!nrow(enrolled)) add("error", "no_enrollments", "round.enrollments")
  rule <- protocol$analysis$consensus
  if (nrow(enrolled)) {
    if (identical(rule$group_policy, "all_required_groups")) {
      for (g in unlist(protocol$panel$groups)) {
        n <- sum(enrolled$group_code == g)
        if (n < rule$min_valid_n) add("warning", "group_below_minimum", paste0("panel.groups.", g), paste0(g, ": ", n, " < ", rule$min_valid_n))
      }
    } else if (nrow(enrolled) < rule$min_valid_n) {
      add("warning", "panel_below_minimum", "panel", paste0(nrow(enrolled), " < ", rule$min_valid_n))
    }
  }
  if (r$state %in% c("draft", "review", "approved", "open")) {
    everyone <- query(repo, "SELECT panelist_id FROM research.enrollments WHERE study_id=$1 AND round_id=$2", r$study_id, r$id)$panelist_id
    waiting <- sum(!eligible_panel(repo, r$study_id, r$number, protocol)$id %in% everyone)
    if (waiting > 0) add("warning", "panelists_not_enrolled", "round.enrollments", waiting)
  }
  if (r$number > 1L && !nrow(query(repo, "SELECT 1 AS x FROM research.feedback_assignments WHERE study_id=$1 AND round_id=$2 LIMIT 1", r$study_id, r$id))) {
    add("warning", "feedback_unassigned", "round.feedback")
  }
  finish()
}
readiness_blocking <- function(readiness, target) {
  codes <- unique(readiness$issues$code[readiness$issues$severity == "error"])
  if (identical(target, "approved")) codes <- setdiff(codes, c("deadline_passed", "no_enrollments"))
  codes
}
#' Review whether a round may be approved or opened
#'
#' Reports every finding at once instead of failing on the first. Errors block
#' the transition; warnings describe a foreseeable methodological consequence,
#' such as a required group below the minimum valid n, and leave the decision
#' to the study team.
#' @param repo Repository.
#' @param actor Study manager.
#' @param round_id Round UUID.
#' @return delphyr_validation: valid, issues (severity, code, path,
#'   message_key, details) and schema_version. Approval ignores the
#'   deadline_passed and no_enrollments findings; opening requires none.
#' @export
get_round_readiness <- function(repo, actor, round_id) {
  transaction(repo, function() {
    r <- round_get(repo, actor, round_id, "manage")
    round_readiness(repo, r)
  })
}
#' Read the exact instrument of a round for review
#' @inheritParams get_round_readiness
#' @return Round number, state, deadline, content hash, protocol version,
#'   study information and every item with all approved language versions.
#'   Contains no panel identities or responses.
#' @export
get_round_instrument <- function(repo, actor, round_id) {
  transaction(repo, function() {
    r <- round_get(repo, actor, round_id, "manage")
    protocol <- one(query(repo, "SELECT version,hash,config::text FROM research.protocol_versions WHERE id=$1", r$protocol_id))
    list(
      round = r[, c("id", "number", "state", "instrument_hash", "deadline"), drop = FALSE],
      protocol = list(version = protocol$version, hash = protocol$hash, config = from_json(protocol$config)),
      consent = one(query(repo, "SELECT id,locale,content,hash FROM identity.consent_versions WHERE id=$1", r$consent_version_id)),
      items = query(repo, "SELECT i.item_code,i.item_version,i.dimension_code,i.scale_code,t.key AS locale,t.value AS text,i.required,i.display_order,i.source_ref FROM research.round_items i CROSS JOIN LATERAL jsonb_each_text(i.texts) t WHERE i.study_id=$1 AND i.round_id=$2 ORDER BY i.display_order,i.item_code,i.dimension_code,t.key", r$study_id, r$id),
      enrollments = query(repo, "SELECT group_code,state,count(*)::int AS n FROM research.enrollments WHERE study_id=$1 AND round_id=$2 GROUP BY group_code,state ORDER BY group_code,state", r$study_id, r$id),
      events = query(repo, "SELECT target_state,content_hash,reason,occurred_at::text AS occurred_at FROM research.round_events WHERE study_id=$1 AND round_id=$2 ORDER BY occurred_at", r$study_id, r$id)
    )
  })
}
#' Enroll eligible panel members who joined after a round was prepared
#'
#' Applies the round's protocol entry policy and each member's current
#' stakeholder group. Enrollment is possible until the round closes. Feedback
#' already assigned to an unopened round is assigned to the new enrollments as
#' well; an open round with assigned feedback accepts no further enrollment, so
#' that everyone rating in a round has the same information.
#' @inheritParams get_round_readiness
#' @param command_id Idempotency key.
#' @return Round UUID and the number of enrollments added.
#' @export
enroll_panel <- function(repo, actor, round_id, command_id) {
  transaction(repo, function() {
    r <- round_get(repo, actor, round_id, "manage", " FOR UPDATE")
    command(repo, actor, r$study_id, "enroll_panel", command_id, list(round_id), function() {
      ensure(r$state %in% c("draft", "review", "approved", "open"), "round.state", "DEL_CONFLICT")
      one(query(repo, "SELECT id FROM research.studies WHERE id=$1 AND state IN ('draft','active')", r$study_id))
      config <- new_protocol(from_json(one(query(repo, "SELECT config::text FROM research.protocol_versions WHERE id=$1", r$protocol_id))$config))
      panel <- eligible_panel(repo, r$study_id, r$number, config)
      enrolled <- query(repo, "SELECT panelist_id FROM research.enrollments WHERE study_id=$1 AND round_id=$2", r$study_id, r$id)$panelist_id
      panel <- panel[!panel$id %in% enrolled, , drop = FALSE]
      ensure(all(panel$group_code %in% unlist(config$panel$groups)), "round.panel_groups", "DEL_CONFLICT")
      feedback <- query(repo, "SELECT DISTINCT feedback_id FROM research.feedback_assignments WHERE study_id=$1 AND round_id=$2", r$study_id, r$id)$feedback_id
      if (nrow(panel) && length(feedback)) ensure(r$state != "open" && length(feedback) == 1L, "enrollment.feedback_locked", "DEL_CONFLICT")
      for (i in seq_len(nrow(panel))) {
        id <- uid()
        execute(repo, "INSERT INTO research.enrollments(id,study_id,round_id,panelist_id,group_code) VALUES($1,$2,$3,$4,$5)", id, r$study_id, r$id, panel$id[i], panel$group_code[i])
        if (length(feedback)) execute(repo, "INSERT INTO research.feedback_assignments VALUES($1,$2,$3,$4)", r$study_id, r$id, id, feedback)
      }
      list(id = r$id, added = nrow(panel))
    })
  })
}
