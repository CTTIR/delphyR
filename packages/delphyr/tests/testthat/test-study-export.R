export_repo <- function(env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test")
  withr::defer({
    DBI::dbDisconnect(r$con)
    unlink(r$artifact_root, recursive = TRUE)
  }, envir = env)
  r
}
export_deadline <- function() format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
export_all_text <- function(path) paste(unlist(lapply(list.files(path, full.names = TRUE), function(f) readLines(f, warn = FALSE))), collapse = "\n")
export_run <- function(r, actor, study_id, profile, key = uid()) {
  job <- request_study_export(r, actor, study_id, profile, key)
  for (attempt in 1:20) {
    op <- get_operation(r, actor, job$id)
    if (op$state %in% c("succeeded", "dead_letter")) break
    worker_step(r, study_id = study_id)
  }
  stopifnot(identical(op$state, "succeeded"))
  list(job = job$id, artifact = op$result_ref, path = download_artifact(r, actor, op$result_ref))
}
# Two rounds, a rating and a free-text dimension, one revised item, attrition,
# one released redaction, decisions, documentation and imported contacts.
export_fixture <- function(r) {
  code <- paste0("EXPORT-", substr(uid(), 1, 8))
  manager <- demo_actor(r, provision_demo_principal(r, paste0("demo-manager-", code), TRUE))
  p <- demo_protocol()
  p$study$code <- code
  p$study$languages <- "en"
  p$instrument$dimensions <- list(list(code = "relevance", scale = "relevance_9"), list(code = "comment", scale = "comment_text"))
  p$instrument$scales$comment_text <- list(type = "free_text", values = list(), anchors = list(low = "not applicable", high = "not applicable"), missing_options = c("unable_to_judge"))
  p$analysis$consensus$min_valid_n <- 2
  p$analysis$consensus$group_policy <- "pooled"
  p$feedback$minimum_display_cell_n <- 3
  study <- create_study(r, manager, p, "create")$id
  consent <- publish_consent(r, manager, study, "Synthetic information.", "en", "consent")$id
  panel <- lapply(1:4, function(i) {
    actor <- demo_actor(r, provision_demo_principal(r, paste0("demo-", code, "-", i)))
    add_panelist(r, manager, study, actor$principal_id, unlist(p$panel$groups)[1 + (i > 2)], paste0("panel-", i))
    actor
  })
  row <- function(item, version, dimension, scale, text, required, order) data.frame(item_code = item, item_version = version, locale = "en", text = text, dimension_code = dimension, scale_code = scale, source_ref = "SRC-1", required = required, display_order = order)
  items <- rbind(
    row("I001", 1L, "relevance", "relevance_9", "Synthetic item one", TRUE, 1L),
    row("I001", 1L, "comment", "comment_text", "Synthetic item one", FALSE, 1L),
    row("I002", 1L, "relevance", "relevance_9", "Synthetic item two", TRUE, 2L)
  )
  answer <- function(round, values, comments, submit = rep(TRUE, 4)) {
    for (i in seq_along(panel)) {
      actor <- panel[[i]]
      e <- tail(list_enrollments(r, actor, study)$id, 1)
      if (round == 1L) record_consent(r, actor, study, consent, TRUE, "consent")
      q <- get_questionnaire(r, actor, e)
      id <- function(item, dimension) q$items$id[q$items$item_code == item & q$items$dimension_code == dimension]
      save_response(r, actor, e, id("I001", "relevance"), list(value = values[[i]][1], status = "answered"), 0L, paste(round, "a"))
      save_response(r, actor, e, id("I002", "relevance"), list(value = values[[i]][2], status = "answered"), 0L, paste(round, "b"))
      comment <- comments[[i]]
      if (!is.null(comment)) save_response(r, actor, e, id("I001", "comment"), if (identical(comment, "unable")) list(value = NULL, status = "unable_to_judge") else list(value = comment, status = "answered"), 0L, paste(round, "c"))
      if (submit[i]) {
        q <- get_questionnaire(r, actor, e)
        submit_round(r, actor, e, setNames(q$responses$revision, q$responses$round_item_id), paste("submit", round))
      }
    }
  }
  finish <- function(round, key) {
    transition_round(r, manager, round$id, "closed", round$hash, "Close", paste("close", key))
    snapshot <- freeze_round(r, manager, round$id, paste("freeze", key))
    list(snapshot = snapshot$id, analysis = run_analysis(r, manager, snapshot$id, paste("analyse", key))$id)
  }
  first <- prepare_round(r, manager, study, items, consent, export_deadline(), "round-1")
  for (state in c("review", "approved", "open")) transition_round(r, manager, first$id, state, first$hash, "Synthetic", paste("1", state))
  answer(1L, list(c(8L, 7L), c(7L, 3L), c(9L, 8L), c(2L, 9L)), list("CANARY-ORIGINAL-ONE private remark", "CANARY-ORIGINAL-TWO second remark", "unable", NULL))
  one <- finish(first, "1")
  record_item_decision(r, manager, one$analysis, "I001", "revise", "CANARY-DECISION-REASON wording unclear", "decide-1")
  record_item_decision(r, manager, one$analysis, "I002", "rerate", "No consensus yet", "decide-2")
  feedback <- create_feedback(r, manager, one$analysis, command_id = "feedback")
  release_feedback(r, manager, feedback$id, feedback$hash, "release")
  # Independent release of a redaction for the first free-text answer only.
  revision <- DBI::dbGetQuery(r$con, "SELECT v.id FROM research.response_revisions v WHERE v.study_id=$1 AND v.value_text LIKE 'CANARY-ORIGINAL-ONE%'", params = list(study))$id
  source <- record_qualitative_source(r, manager, study, "CANARY-ORIGINAL-ONE private remark", "ROUND1-COMMENT-1", "source", revision)
  edit <- redact_qualitative_source(r, manager, study, source$id, "Reviewed remark one", "Removed identifying detail", "edit")
  reviewer <- demo_actor(r, provision_demo_principal(r, paste0("demo-reviewer-", code)))
  set_capability(r, manager, study, reviewer$principal_id, "manage", TRUE, "reviewer")
  release_qualitative_edit(r, reviewer, study, edit$id, edit$hash, "Faithful and non-identifying", "release-edit")
  changed <- items
  changed$item_version[changed$item_code == "I001" & changed$dimension_code == "relevance"] <- 2L
  changed$text[changed$item_code == "I001" & changed$dimension_code == "relevance"] <- "Synthetic item one, revised"
  second <- prepare_round(r, manager, study, changed, consent, export_deadline(), "round-2")
  assign_feedback(r, manager, second$id, feedback$id, "assign")
  for (state in c("review", "approved", "open")) transition_round(r, manager, second$id, state, second$hash, "Synthetic", paste("2", state))
  answer(2L, list(c(8L, 7L), c(8L, 4L), c(9L, 8L), c(5L, 5L)), list(NULL, NULL, NULL, NULL), submit = c(TRUE, TRUE, TRUE, FALSE))
  two <- finish(second, "2")
  for (item in c("I001", "I002")) record_item_decision(r, manager, two$analysis, item, "finalize", "Final synthetic decision", paste("final", item))
  transition_round(r, manager, second$id, "finalized", second$hash, "Final round", "finalize")
  record_item_comparability(r, manager, study, "I001", "relevance", 1L, 2L, FALSE, "Meaning changed by the revision", "comparability")
  record_study_documentation(r, manager, study, list(authors_responsibilities = "Synthetic author A.", funding = "No funding (synthetic)."), 0L, "Initial statements", "documentation")
  csv <- paste("external_ref,email,display_name,locale,stakeholder_group", "C-1,canary-contact@example.invalid,CANARY-CONTACT-NAME,en,professionals", sep = "\n")
  preview <- preview_panel_import(r, manager, study, csv)
  import_panel(r, manager, study, preview, preview$hash, "Synthetic contacts", "import")
  list(
    manager = manager, reviewer = reviewer, panel = panel, study_id = study, code = code, rounds = list(first, second), analyses = list(one$analysis, two$analysis),
    panelists = DBI::dbGetQuery(r$con, "SELECT id FROM research.panelists WHERE study_id=$1", params = list(study))$id
  )
}

test_that("the research profile exports every round reproducibly without originals or contacts", {
  r <- export_repo()
  f <- export_fixture(r)
  x <- export_run(r, f$manager, f$study_id, "research_pseudonymized")
  files <- list.files(x$path)
  expect_true(all(c("README.md", "manifest.json", "provenance.json", "protocol.json", "protocol_versions.json", "responses.csv", "submissions.csv", "enrollments_pseudonymized.csv", "round_items.csv", "analysis_results.csv", "missingness.csv", "denominators.csv", "comparisons.csv", "item_comparability.csv", "item_comparability.json", "item_decisions.csv", "item_lineage.csv", "amendments.csv", "data_dictionary.csv", "feedback_manifest.json", "study_documentation.json", "qualitative_released_versions.csv", "snapshot-round-1.json", "snapshot-round-2.json", "reproduce.R", "report-data.json") %in% files))
  text <- export_all_text(x$path)
  # Unreviewed originals, contacts and account references never leave.
  expect_false(grepl("CANARY-ORIGINAL", text, fixed = TRUE))
  expect_false(grepl("canary-contact", text, fixed = TRUE))
  expect_false(grepl("CANARY-CONTACT-NAME", text, fixed = TRUE))
  for (actor in c(f$panel, list(f$manager, f$reviewer))) expect_false(grepl(actor$principal_id, text, fixed = TRUE))
  responses <- utils::read.csv(file.path(x$path, "responses.csv"), stringsAsFactors = FALSE)
  expect_named(responses, c("study_code", "round_number", "panelist_id", "group_code", "item_code", "item_version", "dimension_code", "scale_code", "answer_status", "value_integer", "value_text", "response_revision", "submission_id", "snapshot_id"))
  expect_true(all(responses$panelist_id %in% f$panelists))
  comments <- responses[responses$round_number == 1 & responses$dimension_code == "comment", ]
  expect_setequal(comments$answer_status, c("answered", "answered", "unable_to_judge", "not_answered"))
  expect_setequal(comments$value_text[comments$answer_status == "answered"], c("Reviewed remark one", "[withheld: no released redaction]"))
  # Only submitted response sets are research data: the fourth member did not
  # submit in round two.
  expect_equal(length(unique(responses$panelist_id[responses$round_number == 2])), 3L)
  expect_true(all(!is.na(responses$submission_id)))
  provenance <- delphyr:::from_json(paste(readLines(file.path(x$path, "provenance.json")), collapse = "\n"))
  expect_identical(provenance$profile, "research_pseudonymized")
  expect_true(provenance$rounds[[1]]$text_redacted)
  expect_identical(c(provenance$rounds[[1]]$free_text_released, provenance$rounds[[1]]$free_text_withheld), c(1L, 1L))
  expect_false(identical(provenance$rounds[[1]]$frozen_snapshot_hash, provenance$rounds[[1]]$export_snapshot_hash))
  expect_true(provenance$rounds[[1]]$matches_stored_analysis)
  expect_false(provenance$rounds[[2]]$text_redacted)
  expect_identical(provenance$rounds[[2]]$frozen_snapshot_hash, provenance$rounds[[2]]$export_snapshot_hash)
  expect_identical(provenance$software$git_commit, "not recorded")
  expect_identical(provenance$documentation_version, 1L)
  again <- reproduce_study_export(x$path)
  expect_s3_class(again, "delphyr_study_reproduction")
  stored <- get_analysis(r, f$manager, f$analyses[[2]])
  expect_identical(again$analyses[["2"]]$provenance$result_hash, stored$provenance$result_hash)
  changed <- again$comparisons[again$comparisons$item_code == "I001" & again$comparisons$dimension_code == "relevance", ]
  expect_identical(changed$status, "not_comparable")
  expect_identical(changed$reason, "Meaning changed by the revision")
  same <- again$comparisons[again$comparisons$item_code == "I002", ]
  expect_identical(c(same$status, same$n_paired, same$n_lost), c("descriptive", "3", "1"))
  decisions <- utils::read.csv(file.path(x$path, "item_decisions.csv"), stringsAsFactors = FALSE)
  expect_true(any(grepl("CANARY-DECISION-REASON", decisions$reason, fixed = TRUE)))
  # A changed byte is detected before reproduction and before download.
  target <- file.path(x$path, "snapshot-round-2.json")
  original <- readLines(target, warn = FALSE)
  writeLines(sub("\"value_integer\":7", "\"value_integer\":9", original, fixed = TRUE), target)
  expect_error(reproduce_study_export(x$path), class = "DEL_VALIDATION")
  expect_error(download_artifact(r, f$manager, x$artifact), class = "DEL_VALIDATION")
  writeLines(original, target)
  expect_identical(download_artifact(r, f$manager, x$artifact), x$path)
  writeLines("unlisted", file.path(x$path, "added.txt"))
  expect_error(download_artifact(r, f$manager, x$artifact), class = "DEL_VALIDATION")
})

test_that("the summary profile holds aggregates only and suppresses small cells", {
  r <- export_repo()
  f <- export_fixture(r)
  analyst <- demo_actor(r, provision_demo_principal(r, paste0("demo-analyst-", f$code)))
  set_capability(r, f$manager, f$study_id, analyst$principal_id, "analyse", TRUE, "analyst")
  expect_error(request_study_export(r, analyst, f$study_id, "research_pseudonymized", "no-export-right"), class = "DEL_FORBIDDEN")
  x <- export_run(r, analyst, f$study_id, "study_summary")
  files <- list.files(x$path)
  expect_false(any(c("responses.csv", "submissions.csv", "enrollments_pseudonymized.csv", "snapshot-round-1.json", "qualitative_released_versions.csv", "denominators.csv") %in% files))
  expect_true(all(c("participation.csv", "recruitment.csv", "analysis_results.csv", "comparisons.csv", "item_decisions.csv", "documentation.csv") %in% files))
  text <- export_all_text(x$path)
  for (id in f$panelists) expect_false(grepl(id, text, fixed = TRUE))
  expect_false(grepl("CANARY", text, fixed = TRUE))
  results <- utils::read.csv(file.path(x$path, "analysis_results.csv"), stringsAsFactors = FALSE)
  # Two members per group are below the display minimum of three: only the
  # total of each item is shown.
  expect_setequal(results$stratum, "overall")
  expect_true(all(c("n_valid", "suppressed") %in% names(results)))
  rating <- results[results$dimension_code == "relevance", ]
  expect_true(all(!rating$suppressed) && all(rating$n_valid >= 3))
  comment <- results[results$dimension_code == "comment", ]
  expect_true(all(comment$suppressed) && all(is.na(comment$n_valid)))
  participation <- utils::read.csv(file.path(x$path, "participation.csv"))
  expect_identical(participation$enrolled, c(4L, 4L))
  expect_identical(participation$submitted, c(4L, 3L))
  expect_identical(participation$consent_recorded, c(4L, 4L))
  recruitment <- utils::read.csv(file.path(x$path, "recruitment.csv"))
  expect_identical(c(recruitment$contacts_imported, recruitment$panel_members), c(1L, 4L))
  documentation <- utils::read.csv(file.path(x$path, "documentation.csv"), stringsAsFactors = FALSE)
  expect_identical(documentation$status[documentation$topic == "Funding"], "documented")
  expect_identical(documentation$status[documentation$topic == "Conflicts of interest"], "not documented")
  report <- prepare_study_report_data(r, analyst, f$study_id)
  expect_s3_class(report, "delphyr_report_data")
  expect_identical(report$final_items$disposition, rep("finalize", 3))
  expect_error(prepare_study_report_data(r, analyst, f$study_id, "research_pseudonymized"), class = "DEL_FORBIDDEN")
  expect_error(prepare_study_report_data(r, f$panel[[1]], f$study_id), class = "DEL_FORBIDDEN")
  if (nzchar(Sys.which("quarto")) && requireNamespace("rmarkdown", quietly = TRUE)) {
    html <- paste(readLines(file.path(x$path, "report.html"), warn = FALSE), collapse = "\n")
    expect_match(html, "Author-supplied documentation", fixed = TRUE)
    expect_match(html, "Synthetic author A.", fixed = TRUE)
    expect_match(html, "not documented", fixed = TRUE)
  } else {
    expect_false("report.html" %in% files)
  }
})

test_that("audit and contact profiles are separate rights with separate content", {
  r <- export_repo()
  f <- export_fixture(r)
  auditor <- demo_actor(r, provision_demo_principal(r, paste0("demo-auditor-", f$code)))
  set_capability(r, f$manager, f$study_id, auditor$principal_id, "audit", TRUE, "auditor")
  for (profile in c("research_pseudonymized", "study_summary", "contacts_restricted")) expect_error(request_study_export(r, auditor, f$study_id, profile, paste("auditor", profile)), class = "DEL_FORBIDDEN")
  x <- export_run(r, auditor, f$study_id, "audit_restricted")
  expect_setequal(list.files(x$path), c("README.md", "manifest.json", "audit_events.csv", "round_events.csv", "protocol_versions.csv", "campaign_approvals.csv", "staff_rights.csv", "qualitative_releases.csv", "documentation_versions.csv"))
  text <- export_all_text(x$path)
  expect_false(grepl("CANARY-ORIGINAL", text, fixed = TRUE))
  expect_false(grepl("canary-contact", text, fixed = TRUE))
  expect_false(grepl("Reviewed remark one", text, fixed = TRUE))
  for (actor in f$panel) expect_false(grepl(actor$principal_id, text, fixed = TRUE))
  events <- utils::read.csv(file.path(x$path, "audit_events.csv"), stringsAsFactors = FALSE)
  expect_true(all(c("save", "submit", "transition_round", "decision", "release_feedback") %in% events$action))
  expect_true(all(is.na(events$actor_ref[events$actor_kind == "panel"]) | events$actor_ref[events$actor_kind == "panel"] == ""))
  expect_true("Final round" %in% events$reason)
  rights <- utils::read.csv(file.path(x$path, "staff_rights.csv"), stringsAsFactors = FALSE)
  expect_false("panel" %in% rights$capability)
  # The contact export is never implied by management or coordination.
  expect_error(request_study_export(r, f$manager, f$study_id, "contacts_restricted", "no-contact-right"), class = "DEL_FORBIDDEN")
  set_capability(r, f$manager, f$study_id, f$manager$principal_id, "contacts_export", TRUE, "contacts")
  contacts <- export_run(r, f$manager, f$study_id, "contacts_restricted")
  expect_setequal(list.files(contacts$path), c("README.md", "manifest.json", "contacts.csv"))
  rows <- utils::read.csv(file.path(contacts$path, "contacts.csv"), stringsAsFactors = FALSE)
  expect_identical(rows$email, "canary-contact@example.invalid")
  expect_identical(rows$invitation_state, "unbound")
  contact_text <- export_all_text(contacts$path)
  for (id in f$panelists) expect_false(grepl(id, contact_text, fixed = TRUE))
  # Another person cannot fetch the artifact; a revoked right ends access.
  expect_error(download_artifact(r, auditor, contacts$artifact), class = "DEL_FORBIDDEN")
  set_capability(r, f$manager, f$study_id, auditor$principal_id, "contacts_export", TRUE, "contacts-auditor")
  expect_error(download_artifact(r, auditor, contacts$artifact), class = "DEL_NOT_FOUND")
  set_capability(r, f$manager, f$study_id, f$manager$principal_id, "contacts_export", FALSE, "contacts-revoked")
  expect_error(download_artifact(r, f$manager, contacts$artifact), class = "DEL_FORBIDDEN")
  expect_error(get_operation(r, f$manager, contacts$job), class = "DEL_FORBIDDEN")
  downloads <- list_audit_events(r, f$reviewer, f$study_id, actions = "artifact_download")
  expect_setequal(downloads$detail, c("audit_restricted", "contacts_restricted"))
})

test_that("export requests are repeatable, merged while pending and never public", {
  r <- export_repo()
  f <- export_fixture(r)
  expect_error(request_study_export(r, f$manager, f$study_id, "public_release", "public"), class = "DEL_FORBIDDEN")
  expect_error(request_study_export(r, f$manager, f$study_id, "everything", "unknown"), class = "DEL_VALIDATION")
  expect_error(request_study_export(r, f$panel[[1]], f$study_id, "study_summary", "panel"), class = "DEL_FORBIDDEN")
  a <- request_study_export(r, f$manager, f$study_id, "study_summary", "a")
  expect_identical(request_study_export(r, f$manager, f$study_id, "study_summary", "a"), a)
  expect_identical(request_study_export(r, f$manager, f$study_id, "study_summary", "b")$id, a$id)
  other <- request_study_export(r, f$manager, f$study_id, "audit_restricted", "c")
  expect_false(identical(other$id, a$id))
  while (!identical(worker_step(r, study_id = f$study_id), FALSE)) NULL
  expect_identical(get_operation(r, f$manager, a$id)$state, "succeeded")
  later <- request_study_export(r, f$manager, f$study_id, "study_summary", "d")
  expect_false(identical(later$id, a$id))
  # Analyses stay one per requester and snapshot.
  snapshot <- DBI::dbGetQuery(r$con, "SELECT id FROM research.snapshots WHERE study_id=$1 LIMIT 1", params = list(f$study_id))$id
  first <- request_analysis(r, f$manager, snapshot, "analysis-a")
  expect_identical(request_analysis(r, f$manager, snapshot, "analysis-b")$id, first$id)
  expect_error(execute(r, "INSERT INTO ops.jobs(id,study_id,actor_id,type,input_id,profile) VALUES($1,$2,$3,'export',$2,'analysis')", uid(), f$study_id, f$manager$principal_id), "jobs_profile_check")
})

test_that("a panel member downloads only the own released feedback", {
  r <- export_repo()
  f <- export_fixture(r)
  actor <- f$panel[[1]]
  enrollments <- list_enrollments(r, actor, f$study_id)
  directory <- tempfile("feedback-")
  dir.create(directory)
  withr::defer(unlink(directory, recursive = TRUE))
  expect_error(write_participant_feedback(r, actor, enrollments$id[1], directory), class = "DEL_NOT_FOUND")
  files <- write_participant_feedback(r, actor, enrollments$id[2], directory)
  expect_setequal(list.files(directory), files)
  own <- utils::read.csv(file.path(directory, "own_previous_responses.csv"), stringsAsFactors = FALSE)
  expect_setequal(own$value_integer[!is.na(own$value_integer)], c(8L, 7L))
  expect_true(any(grepl("CANARY-ORIGINAL-ONE", own$value_text, fixed = TRUE)))
  text <- export_all_text(directory)
  expect_false(grepl("CANARY-ORIGINAL-TWO", text, fixed = TRUE))
  for (id in f$panelists) expect_false(grepl(id, text, fixed = TRUE))
  expect_error(write_participant_feedback(r, actor, enrollments$id[2], directory), class = "DEL_CONFLICT")
  expect_error(write_participant_feedback(r, f$panel[[2]], enrollments$id[2], tempdir()), class = "DEL_NOT_FOUND")
  expect_true("feedback_download" %in% list_audit_events(r, f$manager, f$study_id)$action)
})
