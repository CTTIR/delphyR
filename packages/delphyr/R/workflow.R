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
#' @param locale de or en.
#' @param command_id Idempotency key.
#' @return Consent version id.
#' @export
publish_consent <- function(repo, actor, study_id, text, locale, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "manage")
    ensure(scalar_text(text) && locale %in% c("de", "en"), "consent")
    command(repo, actor, study_id, "publish_consent", command_id, list(text, locale), function() {
      id <- uid()
      execute(repo, "INSERT INTO identity.consent_versions(id,study_id,locale,content,hash) VALUES($1,$2,$3,$4,$5)", id, study_id, locale, text, content_hash(list(text, locale)))
      list(id = id)
    })
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
    })
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
    })
  })
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
    ensure(scalar_text(deadline) && grepl("(Z|[+-][0-9]{2}:[0-9]{2})$", deadline), "deadline.offset")
    command(repo, actor, study_id, "prepare_round", command_id, list(items, consent_version_id, deadline), function() {
      number <- query(repo, "SELECT COALESCE(MAX(number),0)+1 AS n FROM research.rounds WHERE study_id=$1", study_id)$n
      ensure(number <= p$config$stopping$max_rounds, "round.max")
      if (number > 1) ensure(!nrow(query(repo, "SELECT id FROM research.rounds WHERE study_id=$1 AND state NOT IN ('released','finalized')", study_id)), "round.previous", "DEL_CONFLICT")
      # Reusing a version is allowed only for exactly the same scientific content.
      previous_items <- query(repo, "SELECT item_code,item_version,dimension_code,scale_code,texts::text,source_ref FROM research.round_items WHERE study_id=$1", study_id)
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
      panel <- query(repo, "SELECT p.id,p.group_code FROM research.panelists p JOIN identity.panelist_links l ON l.study_id=p.study_id AND l.panelist_id=p.id JOIN identity.memberships m ON m.study_id=l.study_id AND m.id=l.membership_id JOIN identity.principals a ON a.id=m.principal_id JOIN identity.capabilities c ON c.study_id=m.study_id AND c.membership_id=m.id AND c.capability='panel' AND c.revoked_at IS NULL WHERE p.study_id=$1 AND p.active AND m.active AND a.active", study_id)
      if (number > 1L) {
        prior <- query(repo, "SELECT e.panelist_id,r.number,(s.id IS NOT NULL) AS submitted FROM research.enrollments e JOIN research.rounds r ON r.id=e.round_id LEFT JOIN research.submissions s ON s.study_id=e.study_id AND s.enrollment_id=e.id WHERE e.study_id=$1 AND r.number<$2", study_id, number)
        first <- prior$panelist_id[prior$number == 1L]
        last_submitted <- prior$panelist_id[prior$number == number - 1L & prior$submitted]
        eligible <- rep(TRUE, nrow(panel))
        if (!p$config$panel$late_entry) eligible <- eligible & panel$id %in% first
        if (!p$config$panel$return_after_missed_round) {
          eligible <- eligible &
            (panel$id %in% last_submitted | (p$config$panel$late_entry & !panel$id %in% prior$panelist_id))
        }
        panel <- panel[eligible, , drop = FALSE]
      }
      ensure(nrow(panel) > 0, "round.panel")
      for (i in seq_len(nrow(panel))) execute(repo, "INSERT INTO research.enrollments(id,study_id,round_id,panelist_id,group_code) VALUES($1,$2,$3,$4,$5)", uid(), study_id, id, panel$id[i], panel$group_code[i])
      list(id = id, hash = h)
    })
  })
}
#' Advance an authorized round through its approval lifecycle
#' @param repo Repository.
#' @param actor Study manager.
#' @param round_id Round UUID.
#' @param target review, approved, open, closed or finalized.
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
      allowed <- list(review = "draft", approved = "review", open = "approved", closed = "open", finalized = c("analysed", "released"))
      ensure(target %in% names(allowed) && r$state %in% allowed[[target]], "round.transition", "DEL_CONFLICT")
      if (target == "open") ensure(isTRUE(one(query(repo, "SELECT deadline>clock_timestamp() AS ok FROM research.rounds WHERE id=$1", r$id))$ok), "round.deadline", "DEL_ROUND_CLOSED")
      execute(repo, "UPDATE research.rounds SET state=$2,closed_at=CASE WHEN $2='closed' THEN clock_timestamp() ELSE closed_at END WHERE id=$1", round_id, target)
      execute(repo, "INSERT INTO research.round_events(id,study_id,round_id,target_state,content_hash,actor_id,reason) VALUES($1,$2,$3,$4,$5,$6,$7)", uid(), r$study_id, r$id, target, expected_hash, actor$principal_id, reason)
      if (target == "open") execute(repo, "UPDATE research.studies SET state='active' WHERE id=$1 AND state='draft'", r$study_id)
      list(id = round_id, state = target)
    })
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
  query(repo, "SELECT e.id,e.state,r.number,r.state AS round_state FROM research.enrollments e JOIN identity.panelist_links l ON l.study_id=e.study_id AND l.panelist_id=e.panelist_id JOIN research.rounds r ON r.id=e.round_id WHERE e.study_id=$1 AND l.membership_id=$2 ORDER BY r.number", study_id, m)
}
