exploratory_repo <- function(env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test")
  withr::defer({
    DBI::dbDisconnect(r$con)
    unlink(r$artifact_root, recursive = TRUE)
  }, envir = env)
  r
}
exploratory_deadline <- function() format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
exploratory_items <- function(codes, dimension, scale, text) data.frame(item_code = codes, item_version = 1L, locale = "en", text = paste(text, codes), dimension_code = dimension, scale_code = scale, source_ref = "ROUND-1-CONTRIBUTIONS", required = TRUE, display_order = seq_along(codes))
# Eight synthetic members propose topics in free text; the proposals are frozen
# and analysed, and a second manager exists for independent review.
exploratory_fixture <- function(r, n = 8L) {
  code <- paste0("EXPLORE-", substr(uid(), 1, 8))
  manager <- demo_actor(r, provision_demo_principal(r, paste0("demo-manager-", code), TRUE))
  p <- demo_protocol()
  p$study$code <- code
  p$study$design <- "exploratory_round_based_delphi"
  p$study$languages <- "en"
  p$instrument$dimensions <- list(list(code = "proposal", scale = "open_text"), list(code = "relevance", scale = "relevance_9"))
  p$instrument$scales$open_text <- list(type = "free_text", values = list(), missing_options = c("unable_to_judge"))
  p$analysis$consensus$min_valid_n <- 2
  p$analysis$consensus$group_policy <- "pooled"
  study <- create_study(r, manager, p, "create")$id
  consent <- publish_consent(r, manager, study, "Synthetic information.", "en", "consent")$id
  panel <- lapply(seq_len(n), function(i) {
    actor <- demo_actor(r, provision_demo_principal(r, paste0("demo-", code, "-", i)))
    add_panelist(r, manager, study, actor$principal_id, unlist(p$panel$groups)[1 + (i > n / 2)], paste0("panel-", i))
    actor
  })
  first <- prepare_round(r, manager, study, exploratory_items("X001", "proposal", "open_text", "Which topics should be covered?"), consent, exploratory_deadline(), "round-1")
  for (state in c("review", "approved", "open")) transition_round(r, manager, first$id, state, first$hash, "Synthetic", paste("1", state))
  for (i in seq_along(panel)) {
    e <- list_enrollments(r, panel[[i]], study)$id
    record_consent(r, panel[[i]], study, consent, TRUE, "consent")
    item <- get_questionnaire(r, panel[[i]], e)$items$id
    saved <- save_response(r, panel[[i]], e, item, list(value = paste0("ORIGINAL-PROPOSAL-", i, " with a private detail"), status = "answered"), 0L, "save")
    submit_round(r, panel[[i]], e, setNames(saved$revision, item), "submit")
  }
  transition_round(r, manager, first$id, "closed", first$hash, "Close", "close")
  snapshot <- freeze_round(r, manager, first$id, "freeze")$id
  analysis <- run_analysis(r, manager, snapshot, "analyse")$id
  reviewer <- demo_actor(r, provision_demo_principal(r, paste0("demo-reviewer-", code)))
  set_capability(r, manager, study, reviewer$principal_id, "manage", TRUE, "reviewer")
  list(code = code, manager = manager, reviewer = reviewer, panel = panel, study_id = study, consent = consent, round = first, snapshot = snapshot, analysis = analysis)
}
exploratory_release <- function(r, f, source_id, text, kind, key) {
  edit <- redact_qualitative_source(r, f$manager, f$study_id, source_id, text, "Editorial rationale", paste("edit", key), kind = kind)
  release_qualitative_edit(r, f$reviewer, f$study_id, edit$id, edit$hash, "Faithful; dissent kept", paste("release", key))
  edit$id
}

test_that("a free-text scale needs no anchors and is reported as not rated", {
  p <- demo_protocol()
  p$instrument$dimensions <- c(p$instrument$dimensions, list(list(code = "proposal", scale = "open_text")))
  p$instrument$scales$open_text <- list(type = "free_text", values = list(), missing_options = c("unable_to_judge"))
  expect_true(validate_protocol(p)$valid)
  p$instrument$scales$open_text$anchors <- list(low = "", high = "x")
  expect_identical(validate_protocol(p)$issues$path, "scale.anchors")
  rating <- demo_protocol()
  rating$instrument$scales$relevance_9$anchors <- NULL
  expect_false(validate_protocol(rating)$valid)
  p$instrument$scales$open_text$anchors <- NULL
  p$analysis$consensus$group_policy <- "pooled"
  assignments <- data.frame(panelist_id = c("P1", "P2"), group_code = "professionals", submitted = TRUE)
  items <- data.frame(item_code = "X001", item_version = 1L, dimension_code = "proposal", scale_code = "open_text")
  responses <- data.frame(panelist_id = c("P1", "P2"), item_code = "X001", item_version = 1L, dimension_code = "proposal", answer_status = c("answered", "unable_to_judge"), value_integer = NA_integer_, value_text = c("A synthetic proposal", NA))
  s <- new_snapshot(responses, assignments, items, p)
  a <- analyse_round(s)
  expect_setequal(a$results$classification, "not_rated")
  expect_identical(a$decisions$classification, "not_rated")
  expect_identical(a$results$n_answered[a$results$stratum == "overall"], 1L)
  expect_equal(a$results$n_valid[a$results$stratum == "overall"], 0)
  expect_identical(compare_rounds(s, s)$status, "not_rated")
  # The group rule never turns free text into a consensus statement.
  p$analysis$consensus$group_policy <- "all_required_groups"
  expect_identical(analyse_round(new_snapshot(responses, assignments, items, p))$decisions$classification, "not_rated")
})

test_that("free-text answers of a frozen round become sources once, without pseudonyms", {
  r <- exploratory_repo()
  f <- exploratory_fixture(r)
  editor <- f$manager
  rounds <- list_contribution_rounds(r, editor, f$study_id)
  expect_identical(c(rounds$round_number, rounds$contributions, rounds$imported), c(1L, 8L, 0L))
  expect_error(import_round_contributions(r, f$panel[[1]], f$snapshot, "import"), class = "DEL_FORBIDDEN")
  expect_error(list_contribution_rounds(r, f$panel[[1]], f$study_id), class = "DEL_FORBIDDEN")
  done <- import_round_contributions(r, editor, f$snapshot, "import")
  expect_identical(done$imported, 8L)
  expect_identical(import_round_contributions(r, editor, f$snapshot, "import"), done)
  expect_identical(import_round_contributions(r, editor, f$snapshot, "import-again")$imported, 0L)
  expect_identical(list_contribution_rounds(r, editor, f$study_id)$imported, 8L)
  sources <- get_qualitative_provenance(r, editor, f$study_id)$sources
  expect_equal(nrow(sources), 8L)
  expect_setequal(sources$original_text, paste0("ORIGINAL-PROPOSAL-", 1:8, " with a private detail"))
  expect_true(all(grepl("^R1-X001-proposal-[0-9a-f]{8}$", sources$source_ref)))
  panelists <- DBI::dbGetQuery(r$con, "SELECT id FROM research.panelists WHERE study_id=$1", params = list(f$study_id))$id
  expect_false(any(vapply(c(panelists, vapply(f$panel, `[[`, character(1), "principal_id")), function(id) any(grepl(id, unlist(lapply(sources, as.character)), fixed = TRUE)), logical(1))))
  # The database admits one source per answer.
  revision <- sources$response_revision_id[1]
  expect_error(record_qualitative_source(r, editor, f$study_id, sources$original_text[1], "DUPLICATE", "duplicate", revision), class = "DEL_STORAGE")
  other <- exploratory_fixture(r, n = 2L)
  expect_error(import_round_contributions(r, other$manager, f$snapshot, "foreign"), class = "DEL_NOT_FOUND")
})

test_that("proposals lead to derived items and feedback shows only released versions", {
  r <- exploratory_repo()
  f <- exploratory_fixture(r)
  import_round_contributions(r, f$manager, f$snapshot, "import")
  sources <- get_qualitative_provenance(r, f$manager, f$study_id)$sources
  id <- function(i) sources$id[sources$original_text == paste0("ORIGINAL-PROPOSAL-", i, " with a private detail")]
  summary <- exploratory_release(r, f, id(1), "Several members propose covering shared decision making.", "summary", "summary")
  minority <- exploratory_release(r, f, id(8), "One member argues that cost must not be a criterion.", "summary", "minority")
  redaction <- exploratory_release(r, f, id(2), "Proposal two, identifying detail removed.", "redaction", "redaction")
  unreleased <- redact_qualitative_source(r, f$manager, f$study_id, id(3), "UNRELEASED-EDIT must not reach participants", "Draft", "draft")$id
  theme <- create_qualitative_theme(r, f$manager, f$study_id, "DECISION", 1L, "Shared decision making", "Proposals on joint decisions", "theme")$id
  for (i in 1:3) code_qualitative_source(r, f$manager, f$study_id, id(i), theme, "include", "Fits the definition", paste("code", i))
  code_qualitative_source(r, f$manager, f$study_id, id(8), theme, "exclude", "A different concern", "code-8")
  # Five rating items: several sources support one item, one source supports two.
  link <- function(item, i, key) link_item_source(r, f$manager, f$study_id, item, 1L, id(i), "Derived from this proposal", key)
  link("N001", 1, "l1"); link("N002", 2, "l2"); link("N002", 3, "l3"); link("N003", 4, "l4"); link("N004", 1, "l5"); link("N005", 8, "l6")
  expect_error(create_feedback(r, f$manager, f$analysis, list(list(text = "Injected text", reviewed = TRUE, source_ref = "X")), "injected"), class = "DEL_VALIDATION")
  expect_error(create_feedback(r, f$manager, f$analysis, command_id = "unreleased", released_edits = unreleased), class = "DEL_NOT_FOUND")
  other <- exploratory_fixture(r, n = 2L)
  expect_error(create_feedback(r, other$manager, other$analysis, command_id = "foreign", released_edits = summary), class = "DEL_NOT_FOUND")
  expect_error(create_feedback(r, f$manager, f$analysis, command_id = "duplicate", released_edits = c(summary, summary)), class = "DEL_VALIDATION")
  offered <- list_released_edits(r, f$manager, f$study_id)
  expect_setequal(offered$edit_id, c(summary, minority, redaction))
  expect_identical(offered$item_codes[offered$edit_id == summary], "N001, N004")
  expect_false(any(grepl("ORIGINAL-PROPOSAL", unlist(offered), fixed = TRUE)))
  expect_error(list_released_edits(r, f$panel[[1]], f$study_id), class = "DEL_FORBIDDEN")
  feedback <- create_feedback(r, f$manager, f$analysis, command_id = "feedback", released_edits = c(summary, minority, redaction))
  expect_identical(create_feedback(r, f$manager, f$analysis, command_id = "feedback", released_edits = c(redaction, summary, minority)), feedback)
  candidate <- get_feedback_candidate(r, f$manager, feedback$id)
  expect_setequal(candidate$content$qualitative$kind, c("summary", "summary", "redaction"))
  release_feedback(r, f$manager, feedback$id, feedback$hash, "release")
  rating <- prepare_round(r, f$manager, f$study_id, exploratory_items(sprintf("N%03d", 1:5), "relevance", "relevance_9", "Derived synthetic item"), f$consent, exploratory_deadline(), "round-2")
  assign_feedback(r, f$manager, rating$id, feedback$id, "assign")
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, rating$id, state, rating$hash, "Synthetic", paste("2", state))
  actor <- f$panel[[5]]
  shown <- get_feedback(r, actor, tail(list_enrollments(r, actor, f$study_id)$id, 1))
  expect_named(shown$qualitative, c("text", "kind", "source_ref", "item_codes"))
  expect_setequal(shown$qualitative$text, c("Several members propose covering shared decision making.", "One member argues that cost must not be a criterion.", "Proposal two, identifying detail removed."))
  expect_setequal(unlist(shown$qualitative$item_codes[shown$qualitative$kind == "redaction"]), "N002")
  expect_null(shown$correction)
  # Only the person's own original proposal accompanies the released content.
  expect_identical(shown$own$value_text, "ORIGINAL-PROPOSAL-5 with a private detail")
  everything <- paste(unlist(lapply(shown, function(x) unlist(lapply(x, as.character)))), collapse = "\n")
  expect_false(grepl("UNRELEASED-EDIT", everything, fixed = TRUE))
  expect_false(any(vapply(setdiff(1:8, 5), function(i) grepl(paste0("ORIGINAL-PROPOSAL-", i, " "), everything, fixed = TRUE), logical(1))))
  for (i in seq_along(f$panel)) {
    e <- tail(list_enrollments(r, f$panel[[i]], f$study_id)$id, 1)
    q <- get_questionnaire(r, f$panel[[i]], e)
    for (item in q$items$id) save_response(r, f$panel[[i]], e, item, list(value = 7L + (i %% 3L), status = "answered"), 0L, paste("rate", item))
    q <- get_questionnaire(r, f$panel[[i]], e)
    submit_round(r, f$panel[[i]], e, setNames(q$responses$revision, q$responses$round_item_id), "submit-2")
  }
  transition_round(r, f$manager, rating$id, "closed", rating$hash, "Close", "close-2")
  second <- freeze_round(r, f$manager, rating$id, "freeze-2")$id
  run_analysis(r, f$manager, second, "analyse-2")
  proposals <- get_analysis(r, f$manager, f$analysis)
  expect_setequal(proposals$decisions$classification, "not_rated")
  job <- request_study_export(r, f$manager, f$study_id, "research_pseudonymized", "export")
  while (!identical(worker_step(r, study_id = f$study_id), FALSE)) NULL
  path <- download_artifact(r, f$manager, get_operation(r, f$manager, job$id)$result_ref)
  text <- paste(unlist(lapply(list.files(path, full.names = TRUE), function(p) readLines(p, warn = FALSE))), collapse = "\n")
  expect_false(grepl("ORIGINAL-PROPOSAL", text, fixed = TRUE))
  expect_false(grepl("UNRELEASED-EDIT", text, fixed = TRUE))
  responses <- utils::read.csv(file.path(path, "responses.csv"), stringsAsFactors = FALSE)
  texts <- responses$value_text[responses$round_number == 1]
  expect_identical(sum(texts == "Proposal two, identifying detail removed."), 1L)
  expect_identical(sum(texts == "[withheld: no released redaction]"), 7L)
  links <- utils::read.csv(file.path(path, "qualitative_item_sources.csv"), stringsAsFactors = FALSE)
  expect_setequal(links$item_code, sprintf("N%03d", 1:5))
  expect_equal(sum(links$item_code == "N002"), 2L)
  again <- reproduce_study_export(path)
  expect_setequal(again$analyses[["1"]]$decisions$classification, "not_rated")
  # The derived items are new identities, not continuations of the proposal item.
  expect_setequal(again$comparisons$status, "not_comparable")
})

test_that("released feedback is corrected by a new version, never in place", {
  r <- exploratory_repo()
  f <- exploratory_fixture(r, n = 4L)
  import_round_contributions(r, f$manager, f$snapshot, "import")
  sources <- get_qualitative_provenance(r, f$manager, f$study_id)$sources
  wrong <- exploratory_release(r, f, sources$id[1], "Most members reject topic A.", "summary", "wrong")
  feedback <- create_feedback(r, f$manager, f$analysis, command_id = "feedback", released_edits = wrong)
  release_feedback(r, f$manager, feedback$id, feedback$hash, "release")
  rating <- prepare_round(r, f$manager, f$study_id, exploratory_items("N001", "relevance", "relevance_9", "Derived synthetic item"), f$consent, exploratory_deadline(), "round-2")
  assign_feedback(r, f$manager, rating$id, feedback$id, "assign")
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, rating$id, state, rating$hash, "Synthetic", paste("2", state))
  actor <- f$panel[[1]]
  enrollment <- tail(list_enrollments(r, actor, f$study_id)$id, 1)
  before <- get_feedback(r, actor, enrollment)
  expect_identical(before$id, feedback$id)
  expect_identical(before$qualitative$text, "Most members reject topic A.")
  right <- exploratory_release(r, f, sources$id[1], "Most members support topic A.", "summary", "right")
  candidate <- create_feedback(r, f$manager, f$analysis, command_id = "feedback-2", released_edits = right)
  args <- list(r, f$manager, feedback$id, candidate$id, candidate$hash, "The summary reversed the direction of the proposals", "Two members had already rated; the lead reviewed their ratings", "The summary of round one was corrected: most members support topic A.")
  expect_error(do.call(release_feedback_correction, c(args[1], list(f$panel[[1]]), args[3:8], "forbidden")), class = "DEL_FORBIDDEN")
  expect_error(do.call(release_feedback_correction, c(args[1:4], "stale-hash", args[6:8], "stale")), class = "DEL_CONFLICT")
  expect_error(do.call(release_feedback_correction, c(args[1:7], " ", "no-note")), class = "DEL_VALIDATION")
  expect_error(do.call(release_feedback_correction, c(args[1:2], candidate$id, feedback$id, feedback$hash, args[6:8], "reversed")), class = "DEL_CONFLICT")
  done <- do.call(release_feedback_correction, c(args, "correct"))
  expect_identical(done$id, candidate$id)
  expect_identical(do.call(release_feedback_correction, c(args, "correct")), done)
  expect_error(do.call(release_feedback_correction, c(args, "again")), class = "DEL_CONFLICT")
  after <- get_feedback(r, actor, enrollment)
  expect_identical(after$id, candidate$id)
  expect_identical(after$qualitative$text, "Most members support topic A.")
  expect_identical(after$correction$participant_note, "The summary of round one was corrected: most members support topic A.")
  # The earlier version is unchanged and earlier views still refer to it.
  stored <- DBI::dbGetQuery(r$con, "SELECT hash,state,content::text AS content FROM research.feedback WHERE id=$1", params = list(feedback$id))
  expect_identical(stored$hash, feedback$hash)
  expect_match(stored$content, "Most members reject topic A.", fixed = TRUE)
  shown <- DBI::dbGetQuery(r$con, "SELECT object_ref FROM ops.audit WHERE study_id=$1 AND action='feedback_displayed' ORDER BY occurred_at", params = list(f$study_id))$object_ref
  expect_identical(shown, c(feedback$id, candidate$id))
  expect_error(execute(r, "UPDATE research.feedback SET content='{}'::jsonb WHERE id=$1", feedback$id), "feedback locked")
  expect_error(execute(r, "DELETE FROM research.feedback_corrections WHERE study_id=$1", f$study_id), "immutable")
  listed <- list_released_feedback(r, f$manager, f$study_id)
  expect_identical(listed$replacement_id[listed$feedback_id == feedback$id], candidate$id)
  expect_true(listed$is_correction[listed$feedback_id == candidate$id])
  expect_identical(listed$assigned_round[listed$feedback_id == feedback$id], 2L)
  events <- list_audit_events(r, f$manager, f$study_id, actions = "correct_feedback")
  expect_identical(events$reason, "The summary reversed the direction of the proposals")
  # A correction can itself be corrected; a reviewed candidate cannot be forced in.
  third <- exploratory_release(r, f, sources$id[1], "Most members support topic A; one dissents.", "summary", "third")
  final <- create_feedback(r, f$manager, f$analysis, command_id = "feedback-3", released_edits = third)
  expect_error(execute(r, "INSERT INTO research.feedback_corrections(id,study_id,feedback_id,replacement_id,reason,impact_note,participant_note,actor_id) VALUES($1,$2,$3,$4,'x','x','x',$5)", uid(), f$study_id, candidate$id, final$id, f$manager$principal_id), "feedback correction invalid")
  release_feedback_correction(r, f$manager, candidate$id, final$id, final$hash, "Dissent was missing", "No rating affected", "The summary now also states the dissenting view.", "correct-2")
  expect_identical(get_feedback(r, actor, enrollment)$qualitative$text, "Most members support topic A; one dissents.")
})
