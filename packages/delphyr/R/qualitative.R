qualitative_text <- function(x, path) {
  ensure(scalar_text(x) && nchar(x, type = "bytes") <= 20000L, path)
  enc2utf8(x)
}
qualitative_object <- function(repo, study, id, table) {
  valid_id(id)
  ensure(table %in% c("qualitative_sources", "qualitative_edits", "qualitative_themes"), "qualitative.table")
  one(query(repo, paste0("SELECT * FROM research.", table, " WHERE study_id=$1 AND id=$2"), study, id))
}
#' Preserve an original synthetic qualitative contribution
#' @param repo Repository.
#' @param actor Actor with edit capability.
#' @param study_id Study UUID.
#' @param text Original text, preserved without redaction.
#' @param source_ref Explicit provenance reference.
#' @param command_id Idempotency key.
#' @param response_revision_id Optional immutable free-text response revision.
#' @return Source UUID and content hash. This is restricted editorial data.
#' @export
record_qualitative_source <- function(repo, actor, study_id, text, source_ref, command_id, response_revision_id = NULL) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "edit")
    text <- qualitative_text(text, "qualitative.text")
    source_ref <- qualitative_text(source_ref, "qualitative.source_ref")
    if (!is.null(response_revision_id)) {
      valid_id(response_revision_id)
      v <- one(query(repo, "SELECT status,value_text FROM research.response_revisions WHERE study_id=$1 AND id=$2", study_id, response_revision_id))
      ensure(v$status == "answered" && identical(v$value_text, text), "qualitative.response_text")
    }
    payload <- list(text = text, source_ref = source_ref, response_revision_id = response_revision_id)
    command(repo, actor, study_id, "qualitative_source", command_id, payload, function() {
      id <- uid()
      h <- content_hash(payload)
      execute(repo, "INSERT INTO research.qualitative_sources(id,study_id,original_text,source_ref,response_revision_id,created_by,hash) VALUES($1,$2,$3,$4,$5,$6,$7)", id, study_id, text, source_ref, if (is.null(response_revision_id)) NA_character_ else response_revision_id, actor$principal_id, h)
      list(id = id, hash = h)
    })
  })
}
#' Create a separate redacted qualitative version
#' @param repo Repository.
#' @param actor Actor with edit capability.
#' @param study_id Study UUID.
#' @param source_id Original source UUID.
#' @param text Redacted text or a faithful editorial summary.
#' @param kind redaction or summary; summaries must not be presented as quotations.
#' @param reason Rationale for all omissions or reformulation.
#' @param command_id Idempotency key.
#' @return Edit UUID and exact hash, requiring independent release.
#' @export
redact_qualitative_source <- function(repo, actor, study_id, source_id, text, reason, command_id, kind = "redaction") {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "edit")
    qualitative_object(repo, study_id, source_id, "qualitative_sources")
    text <- qualitative_text(text, "qualitative.redaction")
    reason <- qualitative_text(reason, "qualitative.reason")
    ensure(length(kind) == 1 && kind %in% c("redaction", "summary"), "qualitative.kind")
    payload <- list(source_id = source_id, text = text, reason = reason, kind = kind)
    command(repo, actor, study_id, "qualitative_edit", command_id, payload, function() {
      id <- uid()
      h <- content_hash(payload)
      execute(repo, "INSERT INTO research.qualitative_edits(id,study_id,source_id,kind,redacted_text,reason,edited_by,hash) VALUES($1,$2,$3,$4,$5,$6,$7,$8)", id, study_id, source_id, kind, text, reason, actor$principal_id, h)
      list(id = id, hash = h)
    })
  })
}
#' Release an exact qualitative version after independent review
#' @param repo Repository.
#' @param actor Manager different from the redaction author.
#' @param study_id Study UUID.
#' @param edit_id Redaction UUID.
#' @param expected_hash Exact hash shown to the reviewer.
#' @param reason Review rationale, including representation of dissent.
#' @param command_id Idempotency key.
#' @return Immutable release UUID and content hash.
#' @export
release_qualitative_edit <- function(repo, actor, study_id, edit_id, expected_hash, reason, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "manage")
    e <- qualitative_object(repo, study_id, edit_id, "qualitative_edits")
    reason <- qualitative_text(reason, "qualitative.review_reason")
    ensure(e$edited_by != actor$principal_id, "qualitative.independent_review", "DEL_FORBIDDEN")
    ensure(scalar_text(expected_hash) && identical(e$hash, expected_hash), "qualitative.hash", "DEL_CONFLICT")
    command(repo, actor, study_id, "qualitative_release", command_id, list(edit_id, expected_hash, reason), function() {
      id <- uid()
      execute(repo, "INSERT INTO research.qualitative_releases(id,study_id,edit_id,reviewer_id,reason,content_hash) VALUES($1,$2,$3,$4,$5,$6)", id, study_id, edit_id, actor$principal_id, reason, expected_hash)
      list(id = id, hash = expected_hash)
    })
  })
}
#' Define an immutable version of a qualitative theme
#' @param repo Repository.
#' @param actor Actor with edit capability.
#' @param study_id Study UUID.
#' @param code Stable theme code.
#' @param version Positive integer version.
#' @param label Short theme label.
#' @param definition Coding definition or decision rule.
#' @param command_id Idempotency key.
#' @return Theme UUID.
#' @export
create_qualitative_theme <- function(repo, actor, study_id, code, version, label, definition, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "edit")
    ensure(scalar_text(code) && grepl("^[A-Za-z0-9_-]{1,80}$", code) && whole(version) && length(version) == 1 && version > 0, "qualitative.theme")
    label <- qualitative_text(label, "qualitative.label")
    definition <- qualitative_text(definition, "qualitative.definition")
    command(repo, actor, study_id, "qualitative_theme", command_id, list(code, version, label, definition), function() {
      id <- uid()
      execute(repo, "INSERT INTO research.qualitative_themes(id,study_id,code,version,label,definition,created_by) VALUES($1,$2,$3,$4,$5,$6,$7)", id, study_id, code, version, label, definition, actor$principal_id)
      list(id = id)
    })
  })
}
#' Append a reasoned theme coding decision
#' @param repo Repository.
#' @param actor Actor with edit capability.
#' @param study_id Study UUID.
#' @param source_id Original source UUID.
#' @param theme_id Exact theme-version UUID.
#' @param decision include or exclude. Later decisions never overwrite history.
#' @param reason Coding rationale or explanation of disagreement.
#' @param command_id Idempotency key.
#' @return Coding-event UUID. Counts represent decisions, not unique people.
#' @export
code_qualitative_source <- function(repo, actor, study_id, source_id, theme_id, decision, reason, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "edit")
    qualitative_object(repo, study_id, source_id, "qualitative_sources")
    qualitative_object(repo, study_id, theme_id, "qualitative_themes")
    ensure(length(decision) == 1 && decision %in% c("include", "exclude"), "qualitative.decision")
    reason <- qualitative_text(reason, "qualitative.reason")
    command(repo, actor, study_id, "qualitative_code", command_id, list(source_id, theme_id, decision, reason), function() {
      id <- uid()
      execute(repo, "INSERT INTO research.qualitative_codings(id,study_id,source_id,theme_id,decision,reason,coder_id) VALUES($1,$2,$3,$4,$5,$6,$7)", id, study_id, source_id, theme_id, decision, reason, actor$principal_id)
      list(id = id)
    })
  })
}
qualitative_item <- function(repo, study, code, version) {
  ensure(scalar_text(code) && grepl("^[A-Za-z0-9_-]{1,80}$", code) && whole(version) && length(version) == 1 && version > 0, "qualitative.item")
  execute(repo, "INSERT INTO research.item_provenance_versions(id,study_id,item_code,item_version) VALUES($1,$2,$3,$4) ON CONFLICT(study_id,item_code,item_version) DO NOTHING", uid(), study, code, version)
  one(query(repo, "SELECT id FROM research.item_provenance_versions WHERE study_id=$1 AND item_code=$2 AND item_version=$3", study, code, version))$id
}
#' Link an imported or proposed item version to its original source
#' @param repo Repository.
#' @param actor Actor with edit capability.
#' @param study_id Study UUID.
#' @param item_code Stable existing or proposed item code.
#' @param item_version Positive version number.
#' @param source_id Original qualitative source UUID.
#' @param reason Rationale for derivation or consolidation.
#' @param command_id Idempotency key.
#' @return Source-link UUID. This does not import or approve an instrument item.
#' @export
link_item_source <- function(repo, actor, study_id, item_code, item_version, source_id, reason, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "edit")
    qualitative_object(repo, study_id, source_id, "qualitative_sources")
    reason <- qualitative_text(reason, "qualitative.reason")
    command(repo, actor, study_id, "qualitative_item_source", command_id, list(item_code, item_version, source_id, reason), function() {
      item <- qualitative_item(repo, study_id, item_code, item_version)
      id <- uid()
      execute(repo, "INSERT INTO research.qualitative_item_sources(id,study_id,item_id,source_id,reason,actor_id) VALUES($1,$2,$3,$4,$5,$6)", id, study_id, item, source_id, reason, actor$principal_id)
      list(id = id)
    })
  })
}
#' Record a complete item split or merge without deleting its parents
#' @param repo Repository.
#' @param actor Actor with manage capability.
#' @param study_id Study UUID.
#' @param parents,children Data frames with item_code and item_version.
#' @param relation split (one to at least two) or merge (at least two to one).
#' @param reason Human decision rationale.
#' @param command_id Idempotency key.
#' @return Lineage-event UUID and hash. Child codes are new semantic identities.
#' @export
record_item_lineage <- function(repo, actor, study_id, parents, children, relation, reason, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "manage")
    valid_items <- function(z) {
      is.data.frame(z) && all(c("item_code", "item_version") %in% names(z)) &&
        nrow(z) > 0 && !anyNA(z) && is.character(z$item_code) && all(grepl("^[A-Za-z0-9_-]{1,80}$", z$item_code)) &&
        whole(z$item_version) && all(z$item_version > 0) && !anyDuplicated(z$item_code)
    }
    ensure(valid_items(parents) && valid_items(children) && length(relation) == 1 && relation %in% c("split", "merge"), "lineage.items")
    parents <- parents[, c("item_code", "item_version"), drop = FALSE]
    children <- children[, c("item_code", "item_version"), drop = FALSE]
    ensure((relation == "split" && nrow(parents) == 1 && nrow(children) >= 2) || (relation == "merge" && nrow(parents) >= 2 && nrow(children) == 1), "lineage.cardinality")
    ensure(!length(intersect(parents$item_code, children$item_code)), "lineage.new_identity")
    reason <- qualitative_text(reason, "lineage.reason")
    # A study-level lineage lock serializes checks for new child identities.
    query(repo, "SELECT pg_advisory_xact_lock(hashtextextended($1,0))", paste0("lineage:", study_id))
    command(repo, actor, study_id, "qualitative_lineage", command_id, list(parents, children, relation, reason), function() {
      known <- query(repo, "SELECT item_code,item_version FROM research.round_items WHERE study_id=$1 UNION SELECT v.item_code,v.item_version FROM research.item_lineage_edges e JOIN research.item_provenance_versions v ON v.study_id=e.study_id AND v.id=e.child_id WHERE e.study_id=$1", study_id)
      key <- function(z) paste(z$item_code, z$item_version, sep = "\034")
      ensure(all(key(parents) %in% key(known)), "lineage.parent_unknown")
      ensure(!any(children$item_code %in% known$item_code), "lineage.child_exists", "DEL_CONFLICT")
      from <- vapply(seq_len(nrow(parents)), function(i) qualitative_item(repo, study_id, parents$item_code[i], parents$item_version[i]), character(1))
      to <- vapply(seq_len(nrow(children)), function(i) qualitative_item(repo, study_id, children$item_code[i], children$item_version[i]), character(1))
      id <- uid()
      h <- content_hash(list(parents = parents, children = children, relation = relation, reason = reason))
      execute(repo, "INSERT INTO research.item_lineage_events(id,study_id,relation,parent_count,child_count,reason,actor_id,hash) VALUES($1,$2,$3,$4,$5,$6,$7,$8)", id, study_id, relation, length(from), length(to), reason, actor$principal_id, h)
      for (a in from) for (b in to) execute(repo, "INSERT INTO research.item_lineage_edges VALUES($1,$2,$3,$4)", study_id, id, a, b)
      list(id = id, hash = h)
    })
  })
}
#' Read restricted qualitative provenance or reviewed export tables
#' @param repo Repository.
#' @param actor Actor with edit capability; export also requires export capability.
#' @param study_id Study UUID.
#' @param export FALSE includes originals for editorial review. TRUE excludes
#'   originals and unreleased redactions and returns authorized export tables.
#' @return Named tables with explicit source, coding, item and review provenance.
#'   These are restricted research records, not participant feedback.
#' @export
get_qualitative_provenance <- function(repo, actor, study_id, export = FALSE) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "edit")
    ensure(is.logical(export) && length(export) == 1 && !is.na(export), "qualitative.export")
    if (export) authorize(repo, actor, study_id, "export")
    sources <- if (export) {
      query(repo, "SELECT id,source_ref,hash FROM research.qualitative_sources WHERE study_id=$1 ORDER BY id", study_id)
    } else {
      query(repo, "SELECT * FROM research.qualitative_sources WHERE study_id=$1 ORDER BY created_at,id", study_id)
    }
    edits <- if (export) {
      query(repo, "SELECT e.*,r.id AS release_id,r.reviewer_id,r.reason AS review_reason,r.released_at FROM research.qualitative_edits e JOIN research.qualitative_releases r ON r.study_id=e.study_id AND r.edit_id=e.id WHERE e.study_id=$1 ORDER BY e.created_at,e.id", study_id)
    } else {
      query(repo, "SELECT * FROM research.qualitative_edits WHERE study_id=$1 ORDER BY created_at,id", study_id)
    }
    result <- list(
      sources = sources, edits = edits,
      releases = query(repo, "SELECT * FROM research.qualitative_releases WHERE study_id=$1 ORDER BY released_at,id", study_id),
      themes = query(repo, "SELECT * FROM research.qualitative_themes WHERE study_id=$1 ORDER BY code,version", study_id),
      codings = query(repo, "SELECT * FROM research.qualitative_codings WHERE study_id=$1 ORDER BY created_at,id", study_id),
      items = query(repo, "SELECT v.*,EXISTS(SELECT 1 FROM research.round_items r WHERE r.study_id=v.study_id AND r.item_code=v.item_code AND r.item_version=v.item_version) AS imported FROM research.item_provenance_versions v WHERE v.study_id=$1 ORDER BY item_code,item_version", study_id),
      item_sources = query(repo, "SELECT * FROM research.qualitative_item_sources WHERE study_id=$1 ORDER BY created_at,id", study_id),
      lineage_events = query(repo, "SELECT * FROM research.item_lineage_events WHERE study_id=$1 ORDER BY created_at,id", study_id),
      lineage_edges = query(repo, "SELECT * FROM research.item_lineage_edges WHERE study_id=$1 ORDER BY event_id,parent_id,child_id", study_id)
    )
    audit(repo, actor, study_id, if (export) "qualitative_export" else "qualitative_read", study_id)
    result
  })
}
