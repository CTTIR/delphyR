governance_repo <- function(env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(r$con), envir = env)
  r
}
governance_staff <- function(r, f, capabilities) {
  actor <- demo_actor(r, provision_demo_principal(r, paste0("demo-staff-", uid())))
  for (capability in capabilities) set_capability(r, f$manager, f$study_id, actor$principal_id, capability, TRUE, paste0(capability, "-", actor$principal_id))
  actor
}

test_that("the audit trail names actor, time, object, action and rationale", {
  r <- governance_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, paste("Reason for", state), state)
  actor <- f$panel[[1]]
  e <- list_enrollments(r, actor, f$study_id)$id
  record_consent(r, actor, f$study_id, f$consent_id, TRUE, "consent")
  item <- get_questionnaire(r, actor, e)$items$id
  save_response(r, actor, e, item, list(value = 7L, status = "answered"), 0L, "save")
  x <- list_audit_events(r, f$manager, f$study_id)
  expect_named(x, c("occurred_at", "action", "detail", "object_ref", "reason", "actor_kind", "actor_ref"))
  expect_match(x$occurred_at[1], "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$")
  opened <- x[x$action == "transition_round" & x$detail == "open", ]
  expect_identical(opened$reason, "Reason for open")
  expect_identical(opened$object_ref, f$round$id)
  expect_identical(opened$actor_kind, "staff")
  expect_identical(opened$actor_ref, f$manager$principal_id)
  panel <- x[x$action %in% c("save", "consent"), ]
  expect_equal(nrow(panel), 2L)
  expect_true(all(panel$actor_kind == "panel") && all(is.na(panel$actor_ref)))
  expect_identical(x$detail[x$action == "consent"], "accepted")
  # No account reference of a panel member appears anywhere in the trail.
  expect_false(any(vapply(x, function(column) any(grepl(actor$principal_id, column, fixed = TRUE)), logical(1))))
  expect_true(all(diff(order(x$occurred_at, decreasing = TRUE)) == 1L))
  only <- list_audit_events(r, f$manager, f$study_id, actions = c("save", "consent"), limit = 1L)
  expect_equal(nrow(only), 1L)
  expect_true(only$action %in% c("save", "consent"))
  expect_equal(nrow(list_audit_events(r, f$manager, f$study_id, to = "2000-01-01T00:00:00Z")), 0L)
  expect_gt(nrow(list_audit_events(r, f$manager, f$study_id, from = "2000-01-01T00:00:00+01:00")), 5L)
  for (bad in list(list(from = "yesterday"), list(limit = 0L), list(actions = "DROP TABLE"), list(actions = character())))
    expect_error(do.call(list_audit_events, c(list(r, f$manager, f$study_id), bad)), class = "DEL_VALIDATION")
  expect_error(execute(r, "UPDATE ops.audit SET reason='rewritten' WHERE study_id=$1", f$study_id), "immutable")
})

test_that("only audit and management roles of the same study read the trail", {
  r <- governance_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  auditor <- governance_staff(r, f, "audit")
  analyst <- governance_staff(r, f, c("analyse", "export"))
  expect_gt(nrow(list_audit_events(r, auditor, f$study_id)), 0L)
  expect_error(list_audit_events(r, analyst, f$study_id), class = "DEL_FORBIDDEN")
  expect_error(list_audit_events(r, f$panel[[1]], f$study_id), class = "DEL_FORBIDDEN")
  other <- demo_study(r, n = 2L, item_count = 1L)
  expect_error(list_audit_events(r, other$manager, f$study_id), class = "DEL_NOT_FOUND")
  grant <- list_audit_events(r, auditor, f$study_id, actions = "capability")
  expect_true("audit granted" %in% grant$detail)
  set_capability(r, f$manager, f$study_id, auditor$principal_id, "audit", FALSE, "revoke-audit")
  expect_error(list_audit_events(r, auditor, f$study_id), class = "DEL_FORBIDDEN")
  expect_true("audit revoked" %in% list_audit_events(r, f$manager, f$study_id, actions = "capability")$detail)
  expect_error(set_capability(r, f$manager, f$study_id, auditor$principal_id, "superuser", TRUE, "invalid"), class = "DEL_VALIDATION")
})

test_that("study documentation is versioned, author supplied and never invented", {
  r <- governance_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  empty <- get_study_documentation(r, f$manager, f$study_id)
  expect_identical(empty$version, 0L)
  expect_true(all(empty$topics$status == "not documented"))
  expect_equal(nrow(empty$topics), 9L)
  expect_error(record_study_documentation(r, f$panel[[1]], f$study_id, list(funding = "x"), 0L, "Reason", "a"), class = "DEL_FORBIDDEN")
  expect_error(record_study_documentation(r, f$manager, f$study_id, list(unknown_topic = "x"), 0L, "Reason", "b"), class = "DEL_VALIDATION")
  expect_error(record_study_documentation(r, f$manager, f$study_id, list(funding = "  "), 0L, "Reason", "c"), class = "DEL_VALIDATION")
  expect_error(record_study_documentation(r, f$manager, f$study_id, list(funding = "x"), 0L, "", "d"), class = "DEL_VALIDATION")
  first <- record_study_documentation(r, f$manager, f$study_id, list(funding = "Synthetic: no funding.", authors_responsibilities = "Synthetic author A (lead)."), 0L, "Initial statements", "first")
  expect_identical(first$version, 1L)
  expect_identical(record_study_documentation(r, f$manager, f$study_id, list(funding = "Synthetic: no funding.", authors_responsibilities = "Synthetic author A (lead)."), 0L, "Initial statements", "first"), first)
  expect_error(record_study_documentation(r, f$manager, f$study_id, list(funding = "Stale edit"), 0L, "Stale", "stale"), class = "DEL_CONFLICT")
  second <- record_study_documentation(r, f$manager, f$study_id, list(funding = "Synthetic: internal budget.", conflicts_of_interest = "None declared (synthetic)."), 1L, "Funding corrected", "second")
  expect_identical(second$version, 2L)
  x <- get_study_documentation(r, f$manager, f$study_id)
  expect_identical(x$fields$funding, "Synthetic: internal budget.")
  # A version replaces the previous one completely.
  expect_null(x$fields$authors_responsibilities)
  expect_identical(x$topics$status[x$topics$topic == "Authors and responsibilities"], "not documented")
  expect_identical(x$topics$status[x$topics$topic == "Conflicts of interest"], "documented")
  expect_identical(x$history$reason, c("Initial statements", "Funding corrected"))
  expect_error(execute(r, "UPDATE research.study_documentation SET reason='x' WHERE study_id=$1", f$study_id), "immutable")
  analyst <- governance_staff(r, f, "analyse")
  expect_identical(get_study_documentation(r, analyst, f$study_id)$version, 2L)
  expect_error(get_study_documentation(r, f$panel[[1]], f$study_id), class = "DEL_FORBIDDEN")
  reasons <- list_audit_events(r, f$manager, f$study_id, actions = "study_documentation")$reason
  expect_setequal(reasons, c("Initial statements", "Funding corrected"))
})

test_that("comparability decisions are explicit, superseding and limited to used versions", {
  r <- governance_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  expect_error(record_item_comparability(r, f$manager, f$study_id, "I001", "relevance", 1L, 2L, TRUE, "Unknown version", "a"), class = "DEL_VALIDATION")
  expect_error(record_item_comparability(r, f$manager, f$study_id, "I001", "relevance", 1L, 1L, TRUE, "Same version", "b"), class = "DEL_VALIDATION")
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic", state)
  for (actor in f$panel) {
    e <- list_enrollments(r, actor, f$study_id)$id
    record_consent(r, actor, f$study_id, f$consent_id, TRUE, "consent")
    item <- get_questionnaire(r, actor, e)$items$id
    saved <- save_response(r, actor, e, item, list(value = 7L, status = "answered"), 0L, "save")
    submit_round(r, actor, e, setNames(saved$revision, item), "submit")
  }
  transition_round(r, f$manager, f$round$id, "closed", f$round$hash, "Close", "close")
  s1 <- freeze_round(r, f$manager, f$round$id, "freeze")
  a1 <- run_analysis(r, f$manager, s1$id, "analyse")
  feedback <- create_feedback(r, f$manager, a1$id, command_id = "feedback")
  release_feedback(r, f$manager, feedback$id, feedback$hash, "release")
  changed <- f$items
  changed$item_version <- 2L
  changed$text <- paste(changed$text, "(clarified)")
  second <- prepare_round(r, f$manager, f$study_id, changed, f$consent_id, format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), "round-2")
  expect_error(record_item_comparability(r, f$panel[[1]], f$study_id, "I001", "relevance", 1L, 2L, TRUE, "No right", "c"), class = "DEL_FORBIDDEN")
  expect_error(record_item_comparability(r, f$manager, f$study_id, "I001", "relevance", 1L, 2L, TRUE, " ", "d"), class = "DEL_VALIDATION")
  record_item_comparability(r, f$manager, f$study_id, "I001", "relevance", 1L, 2L, FALSE, "Meaning changed", "first")
  record_item_comparability(r, f$manager, f$study_id, "I001", "relevance", 1L, 2L, TRUE, "Wording clarified only", "second")
  history <- get_item_comparability(r, f$manager, f$study_id)
  expect_identical(history$comparable, c(FALSE, TRUE))
  expect_identical(history$effective, c(FALSE, TRUE))
  expect_error(execute(r, "DELETE FROM research.item_comparability WHERE study_id=$1", f$study_id), "immutable")
  previous <- get_snapshot(r, f$manager, s1$id)
  current <- new_snapshot(previous$data[previous$data$submitted, c("panelist_id", "item_code", "dimension_code", "answer_status", "value_integer", "value_text")] |> transform(item_version = 2L), unique(previous$data[, c("panelist_id", "group_code", "submitted")]), transform(previous$items, item_version = 2L), previous$protocol, 2L)
  expect_identical(compare_rounds(previous, current)$status, "not_comparable")
  mapping <- delphyr:::comparability_mapping(history, previous, current)
  expect_identical(mapping$reason, "Wording clarified only")
  paired <- compare_rounds(previous, current, mapping)
  expect_identical(paired$status, "descriptive")
  expect_identical(paired$n_paired, 2L)
  expect_identical(list_audit_events(r, f$manager, f$study_id, actions = "item_comparability")$detail, c("I001 relevance v1->v2 comparable", "I001 relevance v1->v2 not comparable"))
})
