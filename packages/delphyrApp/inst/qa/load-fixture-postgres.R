# Builds the synthetic study of the load qualification through the services:
# 300 invited members in two groups, 150 items in two rating dimensions, a
# completed first round with released feedback and an open second round.
#   DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/load-fixture-postgres.R
# The identifiers are written to .local/load-fixture.rds for the load run.
source("packages/delphyrApp/inst/qa/browser-helpers.R")
members <- as.integer(Sys.getenv("DELPHYR_LOAD_MEMBERS", "300"))
item_count <- as.integer(Sys.getenv("DELPHYR_LOAD_ITEMS", "150"))
workers <- as.integer(Sys.getenv("DELPHYR_LOAD_BUILDERS", "12"))
admin <- qa_admin()
code <- paste0("QA-LOAD-", substr(uuid::UUIDgenerate(), 1, 8))
manager <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-manager-", code), TRUE))
p <- demo_protocol()
p$study$code <- code
p$study$title <- paste("Synthetic load study", code)
p$study$languages <- "en"
p$instrument$dimensions <- list(list(code = "relevance", scale = "relevance_9"), list(code = "clarity", scale = "clarity_9"))
p$instrument$scales$clarity_9 <- list(type = "ordinal_integer", values = 1:9, anchors = list(low = "not clear", high = "entirely clear"), missing_options = c("unable_to_judge", "abstained"))
study <- create_study(admin, manager, p, "create")$id
consent <- publish_consent(admin, manager, study, "Synthetic load qualification only. Do not enter real data.", "en", "consent")$id
started <- Sys.time()
panel <- lapply(seq_len(members), function(i) {
  actor <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-", code, "-", i)))
  add_panelist(admin, manager, study, actor$principal_id, unlist(p$panel$groups)[1 + (i > members / 2)], paste0("panel-", i))
  actor
})
codes <- sprintf("I%03d", seq_len(item_count))
items <- do.call(rbind, lapply(c("relevance", "clarity"), function(dimension) {
  data.frame(item_code = codes, item_version = 1L, locale = "en", text = paste("Synthetic statement", codes, "about a synthetic topic of moderate length for the load qualification."), dimension_code = dimension, scale_code = paste0(dimension, "_9"), source_ref = "LOAD-SRC", required = TRUE, display_order = seq_len(item_count))
}))
deadline <- function() format(Sys.time() + 7 * 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
first <- prepare_round(admin, manager, study, items, consent, deadline(), "round-1")
for (state in c("review", "approved", "open")) invisible(transition_round(admin, manager, first$id, state, first$hash, "Synthetic load qualification", paste("1", state)))
cat("Study, panel and first round:", round(as.numeric(difftime(Sys.time(), started, units = "secs"))), "s\n")
# The first round is answered through the services by parallel processes.
started <- Sys.time()
answer <- function(root, libs, study, consent, principals, seed) {
  .libPaths(libs)
  pkgload::load_all(file.path(root, "packages/delphyr"), quiet = TRUE)
  options(delphyr.log_level = "off")
  r <- delphyr::connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "delphyr_runtime", environment = "development")
  on.exit(DBI::dbDisconnect(r$con))
  set.seed(seed)
  for (principal in principals) {
    actor <- delphyr::demo_actor(r, principal)
    enrollment <- delphyr::list_enrollments(r, actor, study)$id
    delphyr::record_consent(r, actor, study, consent, TRUE, "consent")
    q <- delphyr::get_questionnaire(r, actor, enrollment)
    values <- sample(1:9, nrow(q$items), replace = TRUE, prob = c(1, 1, 1, 2, 3, 4, 6, 6, 4))
    revisions <- integer(nrow(q$items))
    for (i in seq_len(nrow(q$items))) revisions[i] <- delphyr::save_response(r, actor, enrollment, q$items$id[i], list(value = values[i], status = "answered"), 0L, paste0("r1-", i))$revision
    delphyr::submit_round(r, actor, enrollment, stats::setNames(revisions, q$items$id), "submit")
  }
  length(principals)
}
principals <- vapply(panel, function(a) a$principal_id, character(1))
chunks <- split(principals, rep_len(seq_len(workers), length(principals)))
jobs <- lapply(seq_along(chunks), function(i) callr::r_bg(answer, list(qa_root, .libPaths(), study, consent, chunks[[i]], i)))
for (job in jobs) {
  job$wait()
  stopifnot(identical(job$get_result(), length(chunks[[which(vapply(jobs, identical, logical(1), job))]])))
}
cat("First round answered and submitted:", round(as.numeric(difftime(Sys.time(), started, units = "secs"))), "s\n")
started <- Sys.time()
invisible(transition_round(admin, manager, first$id, "closed", first$hash, "All submissions received", "close"))
snapshot <- freeze_round(admin, manager, first$id, "freeze")$id
analysis <- run_analysis(admin, manager, snapshot, "analyse")$id
feedback <- create_feedback(admin, manager, analysis, command_id = "feedback")
invisible(release_feedback(admin, manager, feedback$id, feedback$hash, "release"))
second <- prepare_round(admin, manager, study, items, consent, deadline(), "round-2")
invisible(assign_feedback(admin, manager, second$id, feedback$id, "assign"))
for (state in c("review", "approved", "open")) invisible(transition_round(admin, manager, second$id, state, second$hash, "Synthetic load qualification", paste("2", state)))
cat("Freeze, analysis, feedback and second round:", round(as.numeric(difftime(Sys.time(), started, units = "secs"))), "s\n")
fixture <- list(code = code, study_id = study, consent = consent, manager = manager$principal_id, principals = principals, rounds = c(first$id, second$id), round_hash = second$hash, snapshot = snapshot, analysis = analysis, members = members, items = item_count, fields = nrow(items))
saveRDS(fixture, file.path(qa_root, ".local", "load-fixture.rds"))
counts <- DBI::dbGetQuery(admin$con, "SELECT (SELECT count(*) FROM research.response_revisions WHERE study_id=$1)::int AS revisions,(SELECT count(*) FROM research.submissions WHERE study_id=$1)::int AS submissions,(SELECT count(*) FROM research.enrollments WHERE study_id=$1)::int AS enrollments", params = list(study))
print(c(fixture[c("code", "members", "items", "fields")], as.list(counts)))
DBI::dbDisconnect(admin$con)
