dir.create(".checks", showWarnings = FALSE, mode = "0700")
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test", artifact_root = file.path(getwd(), ".artifacts"))
migrate_repository(r)
f <- demo_study(r)
round <- f$round
snapshots <- list()
for (number in 1:2) {
  if (number == 2) {
    round <- prepare_round(r, f$manager, f$study_id, f$items, f$consent_id, format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), "round-2")
    assign_feedback(r, f$manager, round$id, feedback$id, "assign-feedback")
  }
  for (st in c("review", "approved", "open")) transition_round(r, f$manager, round$id, st, round$hash, "Synthetic E2E", paste(number, st))
  for (i in seq_along(f$panel)) {
    actor <- f$panel[[i]]
    e <- tail(list_enrollments(r, actor, f$study_id)$id, 1)
    if (number == 1) record_consent(r, actor, f$study_id, f$consent_id, TRUE, "consent")
    if (number == 2) {
      prior <- get_feedback(r, actor, e)
      stopifnot(nrow(prior$own) == 12, all(prior$own$value_integer == 7 + (i %% 3)))
    }
    q <- get_questionnaire(r, actor, e)
    for (it in q$items$id) save_response(r, actor, e, it, list(value = 7 + (i %% 3), status = "answered"), 0, paste(number, it))
    q <- get_questionnaire(r, actor, e)
    submit_round(r, actor, e, setNames(q$responses$revision, q$responses$round_item_id), paste0("submit-", number))
  }
  transition_round(r, f$manager, round$id, "closed", round$hash, "Complete synthetic panel", paste0("close-", number))
  snap <- freeze_round(r, f$manager, round$id, paste0("freeze-", number))
  snapshots[[number]] <- get_snapshot(r, f$manager, snap$id)
  job <- request_analysis(r, f$manager, snap$id, paste0("analysis-", number))
  for (attempt in 1:100) {
    op <- get_operation(r, f$manager, job$id)
    if (op$state == "succeeded") break
    worker_step(r, study_id = f$study_id)
  }
  stopifnot(op$state == "succeeded")
  analysis <- get_analysis(r, f$manager, op$result_ref)
  stopifnot(all(analysis$results$n_valid %in% c(15, 30)), all(analysis$decisions$classification == "consensus_in"))
  for (it in unique(f$items$item_code)) record_item_decision(r, f$manager, op$result_ref, it, if (number == 1) "rerate" else "finalize", "Synthetic example decision", paste(number, it))
  if (number == 1) {
    feedback <- create_feedback(r, f$manager, op$result_ref, command_id = "feedback")
    release_feedback(r, f$manager, feedback$id, feedback$hash, "release")
  } else {
    transition_round(r, f$manager, round$id, "finalized", round$hash, "Final synthetic round", "finalize")
  }
}
complete_study(r, f$manager, f$study_id, "Synthetic scenario complete; no study approval claimed", "complete")
comparison <- compare_rounds(snapshots[[1]], snapshots[[2]])
stopifnot(all(comparison$n_paired == 30), all(comparison$proportion_unchanged == 1))
job <- request_export(r, f$manager, snap$id, "export")
for (attempt in 1:100) {
  op <- get_operation(r, f$manager, job$id)
  if (op$state == "succeeded") break
  worker_step(r, study_id = f$study_id)
}
stopifnot(op$state == "succeeded")
path <- download_artifact(r, f$manager, op$result_ref)
reproduced <- reproduce_export(path)
stopifnot(identical(reproduced$provenance$result_hash, analysis$provenance$result_hash))
writeLines(path, ".checks/latest-export-path.txt")
writeLines(f$study_id, ".checks/latest-e2e-study.txt")
cat("E2E PASS: 30 synthetic participants, 12 bilingual items, 2 rounds, 720 committed responses, personal feedback, queue, private export, offline reproduction.\n")
DBI::dbDisconnect(r$con)
