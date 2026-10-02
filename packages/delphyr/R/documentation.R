documentation_fields <- c(
  authors_responsibilities = "Authors and responsibilities",
  panel_criteria_recruitment = "Panel criteria and recruitment",
  funding = "Funding",
  conflicts_of_interest = "Conflicts of interest",
  institutional_approval = "Institutional approval",
  methodological_interpretation = "Methodological interpretation",
  protocol_deviations = "Protocol deviations",
  reporting_guideline_review = "ACCORD/CREDES review",
  data_software_availability = "Data and software availability"
)
# One row per reporting topic; an absent entry stays visibly undocumented.
documentation_topics <- function(fields = list(), version = 0L) {
  documented <- names(documentation_fields) %in% names(fields)
  data.frame(
    topic = unname(documentation_fields), status = ifelse(documented, "documented", "not documented"),
    text = vapply(names(documentation_fields), function(k) if (k %in% names(fields)) fields[[k]] else NA_character_, character(1), USE.NAMES = FALSE),
    documentation_version = ifelse(documented, as.integer(version), NA_integer_), stringsAsFactors = FALSE
  )
}
latest_documentation <- function(repo, study_id) {
  x <- query(repo, "SELECT id,version,content::text,hash,reason,recorded_at::text AS recorded_at FROM research.study_documentation WHERE study_id=$1 ORDER BY version DESC LIMIT 1", study_id)
  if (!nrow(x)) {
    return(list(version = 0L, hash = NA_character_, fields = list()))
  }
  list(version = x$version, hash = x$hash, fields = from_json(x$content), recorded_at = x$recorded_at)
}
#' Record author-supplied study documentation for reports
#'
#' Reports never invent authorship, funding, conflicts of interest, approvals,
#' interpretation or deviations. Study staff record these statements here; each
#' change is a new immutable version, and topics without an entry stay marked
#' "not documented". Recording a reference to an approval does not grant one.
#' @param repo Repository.
#' @param actor Study manager.
#' @param study_id Study UUID.
#' @param fields Named list of plain text. Allowed names:
#'   authors_responsibilities, panel_criteria_recruitment, funding,
#'   conflicts_of_interest, institutional_approval,
#'   methodological_interpretation, protocol_deviations,
#'   reporting_guideline_review and data_software_availability. The list
#'   replaces the previous version completely; empty entries are omitted.
#' @param expected_version Version shown during editing; 0 for the first.
#' @param reason Rationale for this version.
#' @param command_id Idempotency key.
#' @return Documentation id, version and content hash.
#' @export
record_study_documentation <- function(repo, actor, study_id, fields, expected_version, reason, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "manage")
    ensure(is.list(fields) && length(fields) > 0L && !is.null(names(fields)) && !anyDuplicated(names(fields)) && all(names(fields) %in% names(documentation_fields)), "documentation.fields")
    fields <- lapply(fields, function(x) if (is.null(x) || (length(x) == 1L && is.na(x))) "" else x)
    ensure(all(vapply(fields, function(x) is.character(x) && length(x) == 1L && nchar(x, type = "bytes") <= 20000L, logical(1))), "documentation.text")
    fields <- lapply(fields[vapply(fields, function(x) nzchar(trimws(x)), logical(1))], enc2utf8)
    ensure(length(fields) > 0L, "documentation.empty")
    fields <- fields[intersect(names(documentation_fields), names(fields))]
    ensure(whole(expected_version) && length(expected_version) == 1L && expected_version >= 0, "documentation.version")
    ensure(scalar_text(reason) && nchar(reason, type = "bytes") <= 10000L, "documentation.reason")
    # Versions of one study are assigned one at a time.
    one(query(repo, "SELECT id FROM research.studies WHERE id=$1 FOR NO KEY UPDATE", study_id))
    command(repo, actor, study_id, "study_documentation", command_id, list(fields, expected_version, reason), function() {
      current <- query(repo, "SELECT COALESCE(MAX(version),0)::int AS n FROM research.study_documentation WHERE study_id=$1", study_id)$n
      ensure(current == expected_version, "documentation.version", "DEL_CONFLICT")
      id <- uid()
      h <- content_hash(fields)
      execute(repo, "INSERT INTO research.study_documentation(id,study_id,version,content,hash,actor_id,reason) VALUES($1,$2,$3,$4::jsonb,$5,$6,$7)", id, study_id, current + 1L, json(fields), h, actor$principal_id, reason)
      list(id = id, version = current + 1L, hash = h)
    }, reason = reason)
  })
}
#' Read the current study documentation and its version history
#' @inheritParams record_study_documentation
#' @param actor Actor with manage, analyse, export or audit capability.
#' @return Current version, hash and fields; a topic table that marks every
#'   reporting topic documented or not documented; and the version history.
#' @export
get_study_documentation <- function(repo, actor, study_id) {
  authorize_any(repo, actor, study_id, c("manage", "analyse", "export", "audit"))
  latest <- latest_documentation(repo, study_id)
  list(
    version = latest$version, hash = latest$hash, fields = latest$fields,
    topics = documentation_topics(latest$fields, latest$version),
    history = query(repo, "SELECT version,hash,reason,recorded_at::text AS recorded_at FROM research.study_documentation WHERE study_id=$1 ORDER BY version", study_id)
  )
}
#' Decide whether two versions of an item may be compared directly
#'
#' A changed item version interrupts paired comparison by default. This
#' records the study team's explicit decision for one version pair, with its
#' rationale. A later decision for the same pair supersedes the earlier one;
#' the history is kept and exported.
#' @inheritParams record_study_documentation
#' @param item_code,dimension_code Item and rating dimension.
#' @param previous_version,current_version Distinct versions used in rounds
#'   of this study.
#' @param comparable TRUE if ratings of both versions may be paired.
#' @return Decision UUID.
#' @export
record_item_comparability <- function(repo, actor, study_id, item_code, dimension_code, previous_version, current_version, comparable, reason, command_id) {
  transaction(repo, function() {
    authorize(repo, actor, study_id, "manage")
    ensure(scalar_text(item_code) && grepl("^[A-Za-z0-9_-]{1,80}$", item_code) && scalar_text(dimension_code), "comparability.item")
    ensure(whole(previous_version) && length(previous_version) == 1L && previous_version > 0 && whole(current_version) && length(current_version) == 1L && current_version > 0 && previous_version != current_version, "comparability.versions")
    ensure(is.logical(comparable) && length(comparable) == 1L && !is.na(comparable), "comparability.decision")
    ensure(scalar_text(reason) && nchar(reason, type = "bytes") <= 10000L, "comparability.reason")
    command(repo, actor, study_id, "item_comparability", command_id, list(item_code, dimension_code, previous_version, current_version, comparable, reason), function() {
      known <- query(repo, "SELECT DISTINCT i.item_version FROM research.round_items i JOIN research.rounds r ON r.study_id=i.study_id AND r.id=i.round_id WHERE i.study_id=$1 AND i.item_code=$2 AND i.dimension_code=$3 AND r.state<>'cancelled'", study_id, item_code, dimension_code)$item_version
      ensure(all(c(previous_version, current_version) %in% known), "comparability.unknown_version")
      id <- uid()
      execute(repo, "INSERT INTO research.item_comparability(id,study_id,item_code,dimension_code,previous_version,current_version,comparable,reason,actor_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)", id, study_id, item_code, dimension_code, as.integer(previous_version), as.integer(current_version), comparable, reason, actor$principal_id)
      list(id = id)
    }, reason = reason, detail = paste0(item_code, " ", dimension_code, " v", previous_version, "->v", current_version, if (comparable) " comparable" else " not comparable"))
  })
}
comparability_history <- function(repo, study_id) {
  x <- query(repo, "SELECT id,item_code,dimension_code,previous_version,current_version,comparable,reason,recorded_at::text AS recorded_at FROM research.item_comparability WHERE study_id=$1 ORDER BY recorded_at,id", study_id)
  key <- paste(x$item_code, x$dimension_code, x$previous_version, x$current_version, sep = "\034")
  x$effective <- !duplicated(key, fromLast = TRUE)
  x
}
#' Read the comparability decisions of a study
#' @inheritParams get_study_documentation
#' @param actor Actor with manage, analyse, export, edit or audit capability.
#' @return Decision history; effective marks the latest decision per version pair.
#' @export
get_item_comparability <- function(repo, actor, study_id) {
  authorize_any(repo, actor, study_id, c("manage", "analyse", "export", "edit", "audit"))
  comparability_history(repo, study_id)
}
# Mapping for compare_rounds(): the effective decision for exactly the version
# pair that the two snapshots contain.
comparability_mapping <- function(history, previous, current) {
  x <- history[history$effective, , drop = FALSE]
  if (!nrow(x)) {
    return(NULL)
  }
  old <- previous$items
  new <- current$items
  pair <- merge(old[, c("item_code", "dimension_code", "item_version")], new[, c("item_code", "dimension_code", "item_version")], by = c("item_code", "dimension_code"), suffixes = c(".previous", ".current"))
  x <- merge(x, pair, by = c("item_code", "dimension_code"))
  x <- x[x$previous_version == x$item_version.previous & x$current_version == x$item_version.current, c("item_code", "dimension_code", "previous_version", "current_version", "comparable", "reason"), drop = FALSE]
  if (nrow(x)) x else NULL
}
