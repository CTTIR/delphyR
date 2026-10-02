# Study-level exports. Every profile is assembled from immutable snapshots and
# append-only records; nothing here changes research data.

study_snapshots <- function(repo, study_id) {
  query(repo, "SELECT s.id,s.round_id,s.content::text AS content,s.hash,r.number,r.state,to_char(r.closed_at AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS closed_at,pv.version AS protocol_version FROM research.snapshots s JOIN research.rounds r ON r.study_id=s.study_id AND r.id=s.round_id JOIN research.protocol_versions pv ON pv.id=r.protocol_id WHERE s.study_id=$1 ORDER BY r.number", study_id)
}
withheld_text <- "[withheld: no released redaction]"
# A frozen snapshot as it may leave the system. Numeric rounds are unchanged.
# Free-text answers are replaced by their independently released redaction or
# withheld; statuses and ratings stay, so the analysis result is identical.
export_snapshot <- function(repo, study_id, row) {
  s <- read_snapshot(row$content)
  scales <- config_scales(s$protocol)
  text_scales <- names(scales)[vapply(scales, function(z) z$type == "free_text", logical(1))]
  unchanged <- list(snapshot = s, frozen_hash = s$content_hash, text_redacted = FALSE, released = 0L, withheld = 0L)
  if (!any(s$items$scale_code %in% text_scales) || !any(s$data$submitted & s$data$answer_status == "answered" & !is.na(s$data$value_text))) {
    return(unchanged)
  }
  texts <- query(repo, "SELECT e.panelist_id,i.item_code,i.item_version,i.dimension_code,(SELECT ed.redacted_text FROM research.qualitative_sources qs JOIN research.qualitative_edits ed ON ed.study_id=qs.study_id AND ed.source_id=qs.id AND ed.kind='redaction' JOIN research.qualitative_releases rel ON rel.study_id=ed.study_id AND rel.edit_id=ed.id WHERE qs.study_id=v.study_id AND qs.response_revision_id=v.id ORDER BY rel.released_at DESC,rel.id LIMIT 1) AS released_text FROM research.snapshot_entries se JOIN research.response_revisions v ON v.id=se.response_revision_id JOIN research.enrollments e ON e.id=se.enrollment_id JOIN research.round_items i ON i.id=v.round_item_id WHERE se.study_id=$1 AND se.snapshot_id=$2 AND v.status='answered' AND v.value_text IS NOT NULL", study_id, row$id)
  key <- function(z) paste(z$panelist_id, z$item_code, z$item_version, z$dimension_code, sep = "\034")
  d <- s$data
  answered <- which(d$submitted & d$answer_status == "answered" & !is.na(d$value_text))
  released <- texts$released_text[match(key(d[answered, , drop = FALSE]), key(texts))]
  d$value_text[answered] <- ifelse(is.na(released), withheld_text, released)
  fields <- c("panelist_id", "item_code", "item_version", "dimension_code", "answer_status", "value_integer", "value_text")
  redacted <- new_snapshot(d[d$submitted, fields, drop = FALSE], unique(d[, c("panelist_id", "group_code", "submitted"), drop = FALSE]), s$items, s$protocol, s$round_number, s$snapshot_id)
  ensure(identical(analyse_round(s)$provenance$result_hash, analyse_round(redacted)$provenance$result_hash), "export.redaction_changed_results", "DEL_STORAGE")
  list(snapshot = redacted, frozen_hash = s$content_hash, text_redacted = TRUE, released = sum(!is.na(released)), withheld = sum(is.na(released)))
}
# Aggregates for readers without access to individual responses. An item whose
# total is below the display minimum loses its statistics. Where only a group
# is below it, the groups of that item are omitted and the total stays: a
# total alone discloses nothing about a subgroup.
suppress_small_cells <- function(analysis, protocol) {
  minimum <- protocol$feedback$minimum_display_cell_n
  r <- analysis$results
  d <- analysis$distributions
  key <- function(z) paste(z$item_code, z$item_version, z$dimension_code, sep = "\034")
  small_total <- unique(key(r[r$stratum == "overall" & r$n_valid < minimum, , drop = FALSE]))
  small_group <- unique(key(r[r$stratum != "overall" & r$n_valid < minimum, , drop = FALSE]))
  r <- r[r$stratum == "overall" | !key(r) %in% small_group, , drop = FALSE]
  r$suppressed <- key(r) %in% small_total
  statistics <- setdiff(names(r)[vapply(r, is.numeric, logical(1))], c("round_number", "item_version"))
  r[r$suppressed, statistics] <- NA
  r$classification[r$suppressed] <- NA_character_
  if (nrow(d)) d <- d[!key(d) %in% small_total & (d$stratum == "overall" | !key(d) %in% small_group), , drop = FALSE]
  rownames(r) <- NULL
  list(results = r, distributions = d)
}
suppress_comparisons <- function(x, minimum) {
  if (!nrow(x)) {
    return(x)
  }
  small <- x$n_paired < minimum
  for (column in c("previous_mean", "current_mean", "mean_absolute_change", "median_absolute_change", "proportion_unchanged", "proportion_within_one")) x[[column]][small] <- NA_real_
  x$suppressed <- small
  x
}
study_comparisons <- function(snapshots, history) {
  out <- list()
  for (i in seq_along(snapshots)[-1]) {
    previous <- snapshots[[i - 1L]]
    current <- snapshots[[i]]
    x <- as.data.frame(unclass(compare_rounds(previous, current, comparability_mapping(history, previous, current))), stringsAsFactors = FALSE)
    out[[length(out) + 1L]] <- cbind(previous_round = previous$round_number, current_round = current$round_number, x, stringsAsFactors = FALSE)
  }
  if (length(out)) do.call(rbind, out) else data.frame()
}
study_software <- function() {
  recorded <- function(name) if (nzchar(Sys.getenv(name))) Sys.getenv(name) else "not recorded"
  list(
    delphyr = as.character(utils::packageVersion("delphyr")), r = R.version.string,
    git_commit = recorded("DELPHYR_GIT_COMMIT"), lockfile_sha256 = recorded("DELPHYR_LOCKFILE_SHA256"),
    locale = Sys.getlocale("LC_COLLATE"), quantile_type = 7L
  )
}
export_readme <- function(profile, study, extra = character()) {
  purpose <- c(
    research_pseudonymized = "Pseudonymized research data of every frozen round, with decisions, lineage and reviewed qualitative records. Pseudonyms are not anonymous. Not a public release.",
    study_summary = "Aggregated course and results of the study. Contains no individual responses. Statistics below the protocol's display minimum are suppressed.",
    audit_restricted = "Events, approvals and rationales. Contains no responses, contacts or qualitative originals. Panel actions carry no account reference.",
    contacts_restricted = "Contact fields of imported panel contacts and their invitation state. Contains no study pseudonyms and cannot be joined to research data."
  )
  c(
    paste("# delphyR export:", profile), "", paste("Study:", study$code, "-", study$title), "",
    purpose[[profile]], "",
    "Synthetic development data. This export is not an institutional approval, a public data release or a statement of scientific validity.",
    "`manifest.json` lists every file with its size and SHA-256 checksum. CSV text is masked against spreadsheet formulas; JSON files hold the unmodified values.",
    extra
  )
}
# Assembles the named tables, JSON documents and manifest fields of a profile.
study_export_data <- function(repo, actor, study_id, profile) {
  admit(repo, actor, study_id, export_capability(profile))
  study <- one(query(repo, "SELECT id,code,title,state FROM research.studies WHERE id=$1", study_id))
  exported_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (profile == "contacts_restricted") {
    contacts <- query(repo, "SELECT c.external_ref,c.email,c.display_name,c.locale,c.stakeholder_group,
      CASE WHEN EXISTS(SELECT 1 FROM identity.panel_invitation_acceptances a WHERE a.study_id=d.study_id AND a.draft_id=d.id) THEN 'accepted'
           WHEN i.id IS NULL THEN 'unbound'
           WHEN EXISTS(SELECT 1 FROM identity.panel_invitation_revocations r WHERE r.invitation_id=i.id) THEN 'revoked'
           WHEN i.expires_at<=clock_timestamp() THEN 'expired' ELSE 'outstanding' END AS invitation_state
      FROM identity.panel_contacts c JOIN identity.panel_invitation_drafts d ON d.study_id=c.study_id AND d.contact_id=c.id
      LEFT JOIN LATERAL (SELECT x.id,x.expires_at FROM identity.panel_invitations x WHERE x.study_id=d.study_id AND x.draft_id=d.id ORDER BY x.created_at DESC,x.id LIMIT 1) i ON true
      WHERE c.study_id=$1 ORDER BY c.external_ref", study_id)
    return(list(tables = list(contacts = contacts), json = list(), text = list(README.md = export_readme(profile, study)), manifest = list(exported_at = exported_at, rows = nrow(contacts))))
  }
  protocols <- query(repo, "SELECT p.version,p.hash,p.config::text AS config,a.reason,a.occurred_at::text AS occurred_at FROM research.protocol_versions p LEFT JOIN research.protocol_amendments a ON a.study_id=p.study_id AND a.protocol_id=p.id WHERE p.study_id=$1 ORDER BY p.version", study_id)
  amendments <- protocols[, c("version", "hash", "reason", "occurred_at"), drop = FALSE]
  if (profile == "audit_restricted") {
    events <- query(repo, "SELECT to_char(occurred_at AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"') AS occurred_at,action,detail,object_ref,reason,actor_id FROM ops.audit WHERE study_id=$1 ORDER BY occurred_at,id", study_id)
    kind <- ifelse(events$action %in% audit_panel_actions, "panel", ifelse(startsWith(events$action, "message_"), "worker", "staff"))
    events$actor_kind <- kind
    events$actor_ref <- ifelse(kind == "panel", NA_character_, events$actor_id)
    events$actor_id <- NULL
    tables <- list(
      audit_events = events,
      round_events = query(repo, "SELECT r.number AS round_number,e.target_state,e.content_hash,e.reason,e.occurred_at::text AS occurred_at,e.actor_id AS actor_ref FROM research.round_events e JOIN research.rounds r ON r.id=e.round_id WHERE e.study_id=$1 ORDER BY e.occurred_at", study_id),
      protocol_versions = amendments,
      campaign_approvals = query(repo, "SELECT c.id AS campaign_id,c.kind,c.locale,c.hash,(SELECT count(*) FROM ops.campaign_recipients cr WHERE cr.campaign_id=c.id)::int AS recipients,rel.reason AS approval_reason,rel.approved_at::text AS approved_at,rel.approved_by AS approved_by_ref,can.reason AS cancellation_reason,can.cancelled_at::text AS cancelled_at FROM ops.campaigns c LEFT JOIN ops.campaign_releases rel ON rel.campaign_id=c.id LEFT JOIN ops.campaign_cancellations can ON can.campaign_id=c.id WHERE c.study_id=$1 ORDER BY c.created_at", study_id),
      staff_rights = query(repo, "SELECT m.principal_id AS actor_ref,c.capability,(c.revoked_at IS NULL) AS active,c.revoked_at::text AS revoked_at FROM identity.capabilities c JOIN identity.memberships m ON m.study_id=c.study_id AND m.id=c.membership_id WHERE c.study_id=$1 AND c.capability<>'panel' ORDER BY m.principal_id,c.capability", study_id),
      qualitative_releases = query(repo, "SELECT rel.edit_id,e.kind,rel.content_hash,rel.reason,rel.released_at::text AS released_at,rel.reviewer_id AS reviewer_ref,e.edited_by AS editor_ref FROM research.qualitative_releases rel JOIN research.qualitative_edits e ON e.study_id=rel.study_id AND e.id=rel.edit_id WHERE rel.study_id=$1 ORDER BY rel.released_at", study_id),
      documentation_versions = query(repo, "SELECT version,hash,reason,recorded_at::text AS recorded_at,actor_id AS actor_ref FROM research.study_documentation WHERE study_id=$1 ORDER BY version", study_id)
    )
    return(list(tables = tables, json = list(), text = list(README.md = export_readme(profile, study)), manifest = list(exported_at = exported_at, events = nrow(events))))
  }
  protocol <- new_protocol(from_json(protocols$config[nrow(protocols)]))
  minimum <- protocol$feedback$minimum_display_cell_n
  summary <- profile == "study_summary"
  rows <- study_snapshots(repo, study_id)
  exported <- lapply(seq_len(nrow(rows)), function(i) export_snapshot(repo, study_id, rows[i, , drop = FALSE]))
  snapshots <- lapply(exported, `[[`, "snapshot")
  analyses <- lapply(snapshots, analyse_round)
  stored <- vapply(rows$id, function(id) {
    h <- query(repo, "SELECT hash FROM research.analyses WHERE study_id=$1 AND snapshot_id=$2 ORDER BY id", study_id, id)$hash
    if (length(h)) paste(unique(h), collapse = ";") else NA_character_
  }, character(1), USE.NAMES = FALSE)
  history <- comparability_history(repo, study_id)
  comparisons <- study_comparisons(snapshots, history)
  bind <- function(parts) if (length(parts)) do.call(rbind, parts) else data.frame()
  shown <- lapply(seq_along(analyses), function(i) if (summary) suppress_small_cells(analyses[[i]], snapshots[[i]]$protocol) else list(results = analyses[[i]]$results, distributions = analyses[[i]]$distributions))
  round_table <- function(part) bind(lapply(seq_along(analyses), function(i) {
    x <- if (part %in% c("results", "distributions")) shown[[i]][[part]] else analyses[[i]][[part]]
    if (is.data.frame(x) && nrow(x) && !"round_number" %in% names(x)) x <- cbind(round_number = snapshots[[i]]$round_number, x, stringsAsFactors = FALSE)
    x
  }))
  rounds <- query(repo, "SELECT r.number AS round_number,r.state,r.deadline::text AS deadline,r.closed_at::text AS closed_at,pv.version AS protocol_version,r.instrument_hash FROM research.rounds r JOIN research.protocol_versions pv ON pv.id=r.protocol_id WHERE r.study_id=$1 AND r.state<>'cancelled' ORDER BY r.number", study_id)
  instrument <- query(repo, "SELECT r.number AS round_number,i.item_code,i.item_version,i.dimension_code,i.scale_code,t.key AS locale,t.value AS text,i.required,i.display_order,i.source_ref FROM research.round_items i JOIN research.rounds r ON r.study_id=i.study_id AND r.id=i.round_id CROSS JOIN LATERAL jsonb_each_text(i.texts) t WHERE i.study_id=$1 AND r.state<>'cancelled' ORDER BY r.number,i.display_order,i.item_code,i.dimension_code,t.key", study_id)
  participation <- query(repo, "SELECT r.number AS round_number,count(*)::int AS enrolled,
      (count(*) FILTER (WHERE EXISTS(SELECT 1 FROM identity.panelist_links l JOIN identity.consents c ON c.study_id=l.study_id AND c.membership_id=l.membership_id AND c.consent_version_id=r.consent_version_id AND c.decision WHERE l.study_id=e.study_id AND l.panelist_id=e.panelist_id)))::int AS consent_recorded,
      (count(*) FILTER (WHERE EXISTS(SELECT 1 FROM research.response_revisions v WHERE v.study_id=e.study_id AND v.enrollment_id=e.id)))::int AS started,
      (count(*) FILTER (WHERE EXISTS(SELECT 1 FROM research.submissions s WHERE s.study_id=e.study_id AND s.enrollment_id=e.id)))::int AS submitted,
      (count(*) FILTER (WHERE e.state='withdrawn'))::int AS withdrawn
    FROM research.enrollments e JOIN research.rounds r ON r.id=e.round_id WHERE e.study_id=$1 AND r.state<>'cancelled' GROUP BY r.number ORDER BY r.number", study_id)
  recruitment <- query(repo, "SELECT (SELECT count(*) FROM identity.panel_contacts WHERE study_id=$1)::int AS contacts_imported,(SELECT count(DISTINCT draft_id) FROM identity.panel_invitations WHERE study_id=$1)::int AS invitations_issued,(SELECT count(*) FROM identity.panel_invitation_acceptances WHERE study_id=$1)::int AS invitations_accepted,(SELECT count(*) FROM research.panelists WHERE study_id=$1)::int AS panel_members,(SELECT count(*) FROM research.participation_withdrawals WHERE study_id=$1)::int AS withdrawals", study_id)
  decisions <- query(repo, "SELECT r.number AS round_number,d.item_code,d.disposition,d.reason,a.hash AS analysis_hash,(SELECT min(au.occurred_at)::text FROM ops.audit au WHERE au.study_id=d.study_id AND au.action='decision' AND au.object_ref=d.id::text) AS decided_at FROM research.decisions d JOIN research.analyses a ON a.study_id=d.study_id AND a.id=d.analysis_id JOIN research.snapshots s ON s.study_id=a.study_id AND s.id=a.snapshot_id JOIN research.rounds r ON r.id=s.round_id WHERE d.study_id=$1 ORDER BY r.number,d.item_code,decided_at,d.id", study_id)
  lineage <- query(repo, "SELECT ev.relation,p.item_code AS parent_item,p.item_version AS parent_version,c.item_code AS child_item,c.item_version AS child_version,ev.reason,ev.created_at::text AS recorded_at FROM research.item_lineage_edges e JOIN research.item_lineage_events ev ON ev.study_id=e.study_id AND ev.id=e.event_id JOIN research.item_provenance_versions p ON p.study_id=e.study_id AND p.id=e.parent_id JOIN research.item_provenance_versions c ON c.study_id=e.study_id AND c.id=e.child_id WHERE e.study_id=$1 ORDER BY ev.created_at,p.item_code,c.item_code", study_id)
  feedback <- query(repo, "SELECT r.number AS round_number,f.id AS feedback_id,f.hash,f.content::text AS content,(SELECT min(r2.number) FROM research.feedback_assignments fa JOIN research.rounds r2 ON r2.id=fa.round_id WHERE fa.study_id=f.study_id AND fa.feedback_id=f.id)::int AS assigned_round,(SELECT c.replacement_id FROM research.feedback_corrections c WHERE c.study_id=f.study_id AND c.feedback_id=f.id) AS replaced_by FROM research.feedback f JOIN research.analyses a ON a.id=f.analysis_id JOIN research.snapshots s ON s.id=a.snapshot_id JOIN research.rounds r ON r.id=s.round_id WHERE f.study_id=$1 AND f.state='released' ORDER BY r.number,f.id", study_id)
  qualitative <- query(repo, "SELECT (SELECT count(*) FROM research.qualitative_sources WHERE study_id=$1)::int AS sources,(SELECT count(*) FROM research.qualitative_releases WHERE study_id=$1)::int AS released_versions,(SELECT count(*) FROM research.qualitative_themes WHERE study_id=$1)::int AS theme_versions,(SELECT count(*) FROM research.qualitative_codings WHERE study_id=$1)::int AS coding_decisions,(SELECT count(*) FROM research.qualitative_item_sources WHERE study_id=$1)::int AS item_source_links", study_id)
  documentation <- latest_documentation(repo, study_id)
  final_items <- data.frame()
  if (length(analyses)) {
    last <- analyses[[length(analyses)]]$decisions
    last_round <- snapshots[[length(snapshots)]]$round_number
    latest <- decisions[decisions$round_number == last_round, , drop = FALSE]
    latest <- latest[!duplicated(latest$item_code, fromLast = TRUE), , drop = FALSE]
    final_items <- data.frame(
      round_number = last_round, last[, c("item_code", "item_version", "dimension_code", "classification"), drop = FALSE],
      disposition = ifelse(last$item_code %in% latest$item_code, latest$disposition[match(last$item_code, latest$item_code)], "not documented"), stringsAsFactors = FALSE
    )
  }
  round_provenance <- lapply(seq_along(snapshots), function(i) {
    list(
      round_number = snapshots[[i]]$round_number, snapshot_id = rows$id[i], frozen_snapshot_hash = exported[[i]]$frozen_hash,
      export_snapshot_hash = snapshots[[i]]$content_hash, text_redacted = exported[[i]]$text_redacted,
      free_text_released = exported[[i]]$released, free_text_withheld = exported[[i]]$withheld,
      result_hash = analyses[[i]]$provenance$result_hash, rules_hash = analyses[[i]]$provenance$rules_hash,
      stored_analysis_hash = stored[i], matches_stored_analysis = if (is.na(stored[i])) NA else identical(stored[i], analyses[[i]]$provenance$result_hash),
      protocol_version = rows$protocol_version[i], closed_at = rows$closed_at[i]
    )
  })
  limitations <- c(
    "Decisions, lineage, comparability and documentation reflect the time of export; they are not part of an earlier frozen snapshot.",
    if (any(vapply(exported, `[[`, logical(1), "text_redacted"))) "Free-text answers are replaced by their released redaction or withheld. The frozen snapshot hash of such a round cannot be recomputed from this export; its analysis result can.",
    if (summary) paste0("Statistics of an item are suppressed when any displayed cell has fewer than ", minimum, " valid ratings."),
    if (nrow(rounds) > length(snapshots)) "Rounds that are not frozen yet contribute no responses or results."
  )
  provenance <- list(
    export_schema_version = "1.0", profile = profile, study_id = study_id, study_code = study$code,
    exported_at = exported_at, data_as_of = if (nrow(rows)) max(rows$closed_at) else NA_character_,
    timezone = protocol$study$timezone, configuration_hash = protocols$hash[nrow(protocols)], software = study_software(),
    rounds = round_provenance, comparison_hash = content_hash(comparisons), documentation_version = documentation$version,
    documentation_hash = documentation$hash, limitations = as.list(limitations)
  )
  dictionary <- data.frame(
    field = c("panelist_id", "group_code", "answer_status", "value_integer", "value_text", "n_assigned", "n_submitted", "n_valid", "p_agree", "classification", "stratum", "item_version", "status (comparisons)", "n_paired", "disposition", "frozen_snapshot_hash", "export_snapshot_hash", "result_hash", "suppressed"),
    definition = c(
      "Study-specific pseudonym; valid only within this study and not anonymous", "Stakeholder group fixed at enrollment in the round",
      "answered, not_answered, unable_to_judge, abstained or not_applicable; never coded as a number", "Ordinal rating; empty for special responses",
      "Released redaction of a free-text answer, or a withheld marker; never the unreviewed original", "Assigned panel members in the frozen round", "Submitted response sets",
      "Valid numeric ratings; denominator of agreement and disagreement", "Unrounded n_agree / n_valid", "Rule outcome, separate from human item decisions",
      "Overall or protocol-defined stakeholder group", "Frozen instrument item version", "descriptive, insufficient_data or not_comparable for a pair of rounds",
      "Members with valid ratings in both rounds of a comparable item", "Human decision: retain, revise, remove, split, merge, rerate or finalize",
      "Canonical hash of the snapshot as frozen", "Canonical hash of the snapshot as exported", "Canonical hash of results, decisions and distributions", "TRUE where statistics were removed by the display minimum"
    ), stringsAsFactors = FALSE
  )
  report <- list(
    schema_version = "1.0", profile = "study_report", export_profile = profile,
    metadata = list(
      study_code = study$code, study_title = study$title, study_state = study$state, design = protocol$study$design,
      rationale = protocol$study$rationale, generated_at = exported_at, data_as_of = provenance$data_as_of,
      scope = "synthetic development report; not a public-release profile"
    ),
    protocol = unclass(protocol), protocol_versions = amendments, rounds = rounds, recruitment = recruitment, participation = participation,
    instrument = instrument, results = round_table("results"), denominators = if (summary) data.frame() else round_table("denominators"),
    missingness = if (summary) data.frame() else round_table("missingness"), distributions = round_table("distributions"),
    comparisons = if (summary) suppress_comparisons(comparisons, minimum) else comparisons,
    comparability = history[history$effective, c("item_code", "dimension_code", "previous_version", "current_version", "comparable", "reason"), drop = FALSE],
    decisions = if (summary) decisions[, c("round_number", "item_code", "disposition"), drop = FALSE] else decisions[, c("round_number", "item_code", "disposition", "reason", "decided_at"), drop = FALSE],
    lineage = if (summary) lineage[, c("relation", "parent_item", "parent_version", "child_item", "child_version"), drop = FALSE] else lineage,
    feedback = feedback[, c("round_number", "feedback_id", "hash", "assigned_round", "replaced_by"), drop = FALSE], qualitative = qualitative, final_items = final_items,
    documentation = documentation_topics(documentation$fields, documentation$version), dictionary = dictionary,
    provenance = provenance, limitations = limitations
  )
  report$content_hash <- content_hash(report)
  report <- structure(report, class = c("delphyr_report_data", "list"))
  tables <- list(
    round_items = instrument, participation = participation, analysis_results = report$results, distributions = report$distributions,
    comparisons = report$comparisons, item_decisions = report$decisions, item_lineage = report$lineage, amendments = amendments,
    data_dictionary = dictionary, documentation = report$documentation
  )
  json <- list(protocol = unclass(protocol), provenance = provenance, feedback_manifest = lapply(seq_len(nrow(feedback)), function(i) {
    list(round_number = feedback$round_number[i], feedback_id = feedback$feedback_id[i], hash = feedback$hash[i], assigned_round = feedback$assigned_round[i], replaced_by = feedback$replaced_by[i], content = from_json(feedback$content[i]))
  }))
  extra <- character()
  text <- list()
  if (!summary) {
    submissions <- query(repo, "SELECT r.number AS round_number,e.panelist_id,s.id AS submission_id,s.submitted_at::text AS submitted_at FROM research.submissions s JOIN research.enrollments e ON e.id=s.enrollment_id JOIN research.rounds r ON r.id=s.round_id WHERE s.study_id=$1 ORDER BY r.number,e.panelist_id", study_id)
    entries <- query(repo, "SELECT r.number AS round_number,e.panelist_id,i.item_code,i.item_version,i.dimension_code,v.revision AS response_revision FROM research.snapshot_entries se JOIN research.response_revisions v ON v.id=se.response_revision_id JOIN research.enrollments e ON e.id=se.enrollment_id JOIN research.round_items i ON i.id=v.round_item_id JOIN research.rounds r ON r.id=se.round_id WHERE se.study_id=$1", study_id)
    responses <- bind(lapply(seq_along(snapshots), function(i) {
      d <- snapshots[[i]]$data
      d <- d[d$submitted, , drop = FALSE]
      if (!nrow(d)) {
        return(data.frame())
      }
      d$round_number <- snapshots[[i]]$round_number
      d <- merge(d, entries, by = c("round_number", "panelist_id", "item_code", "item_version", "dimension_code"), all.x = TRUE, sort = FALSE)
      # A field left unanswered has no revision; the submission still covers it.
      d$submission_id <- submissions$submission_id[match(paste(d$round_number, d$panelist_id), paste(submissions$round_number, submissions$panelist_id))]
      d$snapshot_id <- rows$id[i]
      data.frame(
        study_code = study$code, d[, c("round_number", "panelist_id", "group_code", "item_code", "item_version", "dimension_code", "scale_code", "answer_status", "value_integer", "value_text", "response_revision", "submission_id", "snapshot_id")],
        stringsAsFactors = FALSE
      )
    }))
    if (nrow(responses)) responses <- responses[order(responses$round_number, responses$panelist_id, responses$item_code, responses$dimension_code), , drop = FALSE]
    tables <- c(tables, list(
      responses = responses,
      enrollments_pseudonymized = query(repo, "SELECT r.number AS round_number,e.panelist_id,e.group_code,e.state FROM research.enrollments e JOIN research.rounds r ON r.id=e.round_id WHERE e.study_id=$1 AND r.state<>'cancelled' ORDER BY r.number,e.panelist_id", study_id),
      submissions = submissions,
      denominators = report$denominators, missingness = report$missingness,
      item_comparability = history[, c("item_code", "dimension_code", "previous_version", "current_version", "comparable", "reason", "recorded_at", "effective"), drop = FALSE],
      qualitative_sources = query(repo, "SELECT id AS source_id,source_ref,hash,(response_revision_id IS NOT NULL) AS from_response FROM research.qualitative_sources WHERE study_id=$1 ORDER BY created_at,id", study_id),
      qualitative_released_versions = query(repo, "SELECT e.id AS edit_id,e.source_id,e.kind,e.redacted_text AS text,e.reason,rel.reason AS review_reason,rel.released_at::text AS released_at FROM research.qualitative_edits e JOIN research.qualitative_releases rel ON rel.study_id=e.study_id AND rel.edit_id=e.id WHERE e.study_id=$1 ORDER BY rel.released_at,e.id", study_id),
      qualitative_themes = query(repo, "SELECT code,version,label,definition FROM research.qualitative_themes WHERE study_id=$1 ORDER BY code,version", study_id),
      qualitative_codings = query(repo, "SELECT c.source_id,t.code AS theme_code,t.version AS theme_version,c.decision,c.reason,c.created_at::text AS recorded_at FROM research.qualitative_codings c JOIN research.qualitative_themes t ON t.study_id=c.study_id AND t.id=c.theme_id WHERE c.study_id=$1 ORDER BY c.created_at,c.id", study_id),
      qualitative_item_sources = query(repo, "SELECT v.item_code,v.item_version,s.source_id,s.reason,s.created_at::text AS recorded_at FROM research.qualitative_item_sources s JOIN research.item_provenance_versions v ON v.study_id=s.study_id AND v.id=s.item_id WHERE s.study_id=$1 ORDER BY v.item_code,v.item_version,s.created_at", study_id)
    ))
    json <- c(json, list(
      protocol_versions = lapply(seq_len(nrow(protocols)), function(i) list(version = protocols$version[i], hash = protocols$hash[i], config = from_json(protocols$config[i]))),
      item_comparability = history, study_documentation = list(version = documentation$version, hash = documentation$hash, fields = documentation$fields)
    ))
    for (i in seq_along(snapshots)) json[[paste0("snapshot-round-", snapshots[[i]]$round_number)]] <- structure(list(raw = snapshot_json(snapshots[[i]])), class = "delphyr_raw_json")
    text$reproduce.R <- c("args <- commandArgs(trailingOnly = TRUE)", "path <- if (length(args)) args[1] else '.'", "result <- delphyr::reproduce_study_export(path)", "for (round in names(result$analyses)) print(result$analyses[[round]]$decisions)", "print(result$comparisons)")
    extra <- c("", "The `snapshot-round-<n>.json` files are the authoritative data. Run `Rscript reproduce.R <directory>` with the documented delphyr version to recompute every analysis and comparison.", "Qualitative originals, unreleased redactions, contacts and account mappings are excluded.")
  } else {
    tables$recruitment <- recruitment
    tables$qualitative_work <- qualitative
    json <- c(json, list(study_documentation = list(version = documentation$version, hash = documentation$hash, fields = documentation$fields)))
  }
  text$README.md <- export_readme(profile, study, extra)
  list(
    tables = tables, json = json, text = text, report = report,
    manifest = list(exported_at = exported_at, rounds = length(snapshots), result_hashes = lapply(analyses, function(a) a$provenance$result_hash), comparison_hash = provenance$comparison_hash)
  )
}
write_study_export <- function(repo, actor, study_id, profile) {
  x <- consistent_read(repo, function() study_export_data(repo, actor, study_id, profile))
  dir.create(repo$artifact_root, recursive = TRUE, showWarnings = FALSE, mode = "0700")
  root <- normalizePath(repo$artifact_root, mustWork = TRUE)
  key <- uid()
  staging <- file.path(root, paste0(key, ".partial"))
  final <- file.path(root, key)
  dir.create(staging, mode = "0700")
  on.exit(if (dir.exists(staging)) unlink(staging, recursive = TRUE), add = TRUE)
  for (name in names(x$tables)) utils::write.csv(safe_csv(x$tables[[name]]), file.path(staging, paste0(name, ".csv")), row.names = FALSE, na = "", fileEncoding = "UTF-8")
  for (name in names(x$json)) {
    value <- x$json[[name]]
    writeLines(if (inherits(value, "delphyr_raw_json")) value$raw else json(value), file.path(staging, paste0(name, ".json")), useBytes = TRUE)
  }
  for (name in names(x$text)) writeLines(enc2utf8(x$text[[name]]), file.path(staging, name), useBytes = TRUE)
  renderer <- "none"
  if (!is.null(x$report)) {
    writeLines(json(unclass(x$report)), file.path(staging, "report-data.json"), useBytes = TRUE)
    # Only a missing optional runtime permits the report to be absent.
    renderer <- tryCatch(
      {
        render_study_report(x$report, staging)
        "quarto_html"
      },
      DEL_DEPENDENCY = function(e) "not_rendered_missing_quarto_runtime"
    )
  }
  files <- list.files(staging, full.names = TRUE)
  manifest <- c(list(
    schema_version = "1.0", profile = profile, study_id = study_id, software_version = as.character(utils::packageVersion("delphyr")),
    r_version = R.version.string, report = list(renderer = renderer, data_hash = if (is.null(x$report)) NA_character_ else x$report$content_hash)
  ), x$manifest)
  manifest$files <- lapply(files, function(f) list(name = basename(f), sha256 = digest::digest(file = f, algo = "sha256"), bytes = file.info(f)$size))
  writeLines(json(manifest), file.path(staging, "manifest.json"))
  hash <- digest::digest(file = file.path(staging, "manifest.json"), algo = "sha256")
  ensure(file.rename(staging, final), "artifact.rename", "DEL_STORAGE")
  list(id = key, study_id = study_id, checksum = hash)
}
#' Prepare the data of a study-level report
#'
#' Covers every frozen round: design, protocol versions, recruitment and
#' participation, instruments, results, comparisons between rounds, human
#' decisions, lineage, released feedback, final items and the author-supplied
#' documentation. Topics without an entry stay marked "not documented".
#' @param repo Repository.
#' @param actor Actor holding the capability of the profile.
#' @param study_id Study UUID.
#' @param profile study_summary (aggregates with small-cell suppression) or
#'   research_pseudonymized (full denominators and decision rationales).
#' @return A delphyr_report_data with a content hash, for render_study_report().
#' @export
prepare_study_report_data <- function(repo, actor, study_id, profile = "study_summary") {
  ensure(scalar_text(profile) && profile %in% c("study_summary", "research_pseudonymized"), "report.profile")
  consistent_read(repo, function() study_export_data(repo, actor, study_id, profile)$report)
}
#' Verify and reproduce a study-level research export without a database
#' @param path Extracted research_pseudonymized export under the user's control.
#' @return The recomputed analysis of every round and the comparisons between
#'   rounds, after all checksums, snapshot hashes and result hashes matched.
#' @export
reproduce_study_export <- function(path) {
  manifest <- verify_manifest(path, exact = FALSE)
  ensure(identical(manifest$profile, "research_pseudonymized"), "reproduction.profile")
  read <- function(name) paste(readLines(file.path(path, name), warn = FALSE), collapse = "\n")
  provenance <- from_json(read("provenance.json"))
  snapshots <- list()
  analyses <- list()
  for (round in provenance$rounds) {
    s <- read_snapshot(read(paste0("snapshot-round-", round$round_number, ".json")))
    a <- analyse_round(s)
    ensure(identical(s$content_hash, round$export_snapshot_hash) && identical(a$provenance$result_hash, round$result_hash), "reproduction")
    if (!isTRUE(round$text_redacted)) ensure(identical(s$content_hash, round$frozen_snapshot_hash), "reproduction")
    snapshots[[length(snapshots) + 1L]] <- s
    analyses[[as.character(round$round_number)]] <- a
  }
  history <- jsonlite::fromJSON(read("item_comparability.json"), simplifyVector = TRUE)
  if (!is.data.frame(history)) history <- data.frame(effective = logical())
  comparisons <- study_comparisons(snapshots, history)
  ensure(identical(content_hash(comparisons), provenance$comparison_hash), "reproduction.comparisons")
  structure(list(analyses = analyses, comparisons = comparisons, provenance = provenance), class = "delphyr_study_reproduction")
}
#' Write a panel member's own feedback for download
#'
#' The participant-feedback profile: the released aggregate of the previous
#' round and only this person's own previous answers.
#' @param repo Repository.
#' @param actor Panel actor.
#' @param enrollment_id Own enrollment UUID with assigned released feedback.
#' @param output_dir Existing private directory controlled by trusted server code.
#' @return Written file names; DEL_NOT_FOUND when no feedback is assigned.
#' @export
write_participant_feedback <- function(repo, actor, enrollment_id, output_dir) {
  ensure(scalar_text(output_dir) && dir.exists(output_dir), "feedback.output_dir")
  x <- get_feedback(repo, actor, enrollment_id)
  ensure(!is.null(x), "feedback", "DEL_NOT_FOUND")
  files <- c("README.md", "panel_results.csv", "own_previous_responses.csv", "feedback.json")
  ensure(!any(file.exists(file.path(output_dir, files))), "feedback.exists", "DEL_CONFLICT")
  writeLines(c(
    "# Your released feedback", "",
    "`panel_results.csv` holds the released results of the previous round for the whole panel. Statistics of small groups are suppressed.",
    "`own_previous_responses.csv` holds only your own previous answers. Nobody else receives them through this download.",
    "`feedback.json` holds the same content unmodified. CSV text is masked against spreadsheet formulas."
  ), file.path(output_dir, files[1]))
  utils::write.csv(safe_csv(as.data.frame(x$aggregate$results, stringsAsFactors = FALSE)), file.path(output_dir, files[2]), row.names = FALSE, na = "", fileEncoding = "UTF-8")
  utils::write.csv(safe_csv(x$own), file.path(output_dir, files[3]), row.names = FALSE, na = "", fileEncoding = "UTF-8")
  writeLines(json(list(feedback_id = x$id, aggregate = x$aggregate, own_previous_responses = x$own)), file.path(output_dir, files[4]), useBytes = TRUE)
  transaction(repo, function() {
    study <- one(query(repo, "SELECT study_id FROM research.enrollments WHERE id=$1", enrollment_id))$study_id
    audit(repo, actor, study, "feedback_download", x$id)
  })
  invisible(files)
}
