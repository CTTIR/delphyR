qual_execute <- function(r, sql, params) {
  DBI::dbBegin(r$con)
  result <- tryCatch(do.call(delphyr:::execute, c(list(repo = r, sql = sql), params)), error = function(e) {
    DBI::dbRollback(r$con)
    stop(e)
  })
  # PostgreSQL already rolls back a COMMIT rejected by a deferred constraint.
  DBI::dbCommit(r$con)
  result
}
qual_repo <- function(env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  skip_if_not_installed("RPostgres")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(r$con), envir = env)
  r
}
qual_fixture <- function(r) {
  f <- demo_study(r, n = 2L, item_count = 1L, code = paste0("QUAL-", uuid::UUIDgenerate()))
  f$editor <- demo_actor(r, provision_demo_principal(r, paste0("demo-editor-", f$study_id)))
  set_capability(r, f$manager, f$study_id, f$editor$principal_id, "edit", TRUE, "grant-edit")
  f
}

test_that("qualitative versions preserve originals and require independent exact review", {
  r <- qual_repo()
  f <- qual_fixture(r)
  s <- record_qualitative_source(r, f$editor, f$study_id, "Synthetic Person A disagrees.", "synthetic contribution 1", "source")
  expect_identical(record_qualitative_source(r, f$editor, f$study_id, "Synthetic Person A disagrees.", "synthetic contribution 1", "source"), s)
  expect_error(record_qualitative_source(r, f$editor, f$study_id, "Changed original", "synthetic contribution 1", "source"), class = "DEL_CONFLICT")
  e <- redact_qualitative_source(r, f$editor, f$study_id, s$id, "A contributor disagrees.", "Removed synthetic identifying detail; preserved dissent.", "redact")
  expect_error(release_qualitative_edit(r, f$manager, f$study_id, e$id, "wrong", "Reviewed dissent", "bad-hash"), class = "DEL_CONFLICT")
  set_capability(r, f$manager, f$study_id, f$editor$principal_id, "manage", TRUE, "grant-manage")
  expect_error(release_qualitative_edit(r, f$editor, f$study_id, e$id, e$hash, "Self review", "self-review"), class = "DEL_FORBIDDEN")
  released <- release_qualitative_edit(r, f$manager, f$study_id, e$id, e$hash, "Independent review retained dissent", "release")
  expect_identical(release_qualitative_edit(r, f$manager, f$study_id, e$id, e$hash, "Independent review retained dissent", "release"), released)
  second <- redact_qualitative_source(r, f$editor, f$study_id, s$id, "A dissenting viewpoint was recorded.", "Editorial paraphrase, not a quotation.", "summary", kind = "summary")
  internal <- get_qualitative_provenance(r, f$editor, f$study_id)
  expect_identical(internal$sources$original_text, "Synthetic Person A disagrees.")
  expect_equal(nrow(internal$edits), 2L)
  expect_identical(internal$edits$kind[internal$edits$id == second$id], "summary")
  expect_error(get_qualitative_provenance(r, f$editor, f$study_id, export = TRUE), class = "DEL_FORBIDDEN")
  exported <- get_qualitative_provenance(r, f$manager, f$study_id, export = TRUE)
  expect_false("original_text" %in% names(exported$sources))
  expect_identical(exported$edits$id, e$id)
  expect_error(qual_execute(r, "UPDATE research.qualitative_sources SET original_text='overwrite' WHERE id=$1", params = list(s$id)), "immutable record")
  expect_error(qual_execute(r, "DELETE FROM research.qualitative_edits WHERE id=$1", params = list(e$id)), "immutable record")
  set_capability(r, f$manager, f$study_id, f$editor$principal_id, "edit", FALSE, "revoke-edit")
  expect_error(get_qualitative_provenance(r, f$editor, f$study_id), class = "DEL_FORBIDDEN")
  expect_error(record_qualitative_source(r, f$editor, f$study_id, "Synthetic Person A disagrees.", "synthetic contribution 1", "source"), class = "DEL_FORBIDDEN")
})

test_that("themes and item provenance are many-to-many and retain split-merge history", {
  r <- qual_repo()
  f <- qual_fixture(r)
  source <- record_qualitative_source(r, f$editor, f$study_id, "Synthetic proposal: two separate priorities.", "synthetic source", "source")
  theme <- create_qualitative_theme(r, f$editor, f$study_id, "priority", 1L, "Priority", "Include statements about priority.", "theme")
  other_theme <- create_qualitative_theme(r, f$editor, f$study_id, "dissent", 1L, "Dissent", "Include disagreement, including minority positions.", "theme-two")
  code_qualitative_source(r, f$editor, f$study_id, source$id, theme$id, "include", "Explicit priority proposal", "code")
  code_qualitative_source(r, f$editor, f$study_id, source$id, other_theme$id, "include", "Alternative to the original item", "code-two")
  link_item_source(r, f$editor, f$study_id, "I001", 1L, source$id, "Original proposal", "link-old")
  link_item_source(r, f$editor, f$study_id, "I002", 1L, source$id, "First separated priority", "link-new")
  pair <- function(code) data.frame(item_code = code, item_version = rep(1L, length(code)))
  split <- record_item_lineage(r, f$manager, f$study_id, pair("I001"), pair(c("I002", "I003")), "split", "Separate two distinct concepts", "split")
  expect_identical(record_item_lineage(r, f$manager, f$study_id, pair("I001"), pair(c("I003", "I002")), "split", "Separate two distinct concepts", "split"), split)
  merged <- record_item_lineage(r, f$manager, f$study_id, pair(c("I002", "I003")), pair("I004"), "merge", "Consolidate after review", "merge")
  expect_error(record_item_lineage(r, f$manager, f$study_id, pair("I001"), pair("I005"), "split", "Invalid cardinality", "bad-split"), class = "DEL_VALIDATION")
  expect_error(record_item_lineage(r, f$manager, f$study_id, pair(c("I002", "I003")), pair("I001"), "merge", "Cannot reuse an old identity", "cycle"), class = "DEL_CONFLICT")
  out <- get_qualitative_provenance(r, f$editor, f$study_id)
  expect_equal(nrow(out$codings), 2L)
  expect_equal(nrow(out$item_sources), 2L)
  expect_equal(nrow(out$lineage_events), 2L)
  expect_equal(nrow(out$lineage_edges), 4L)
  expect_true(out$items$imported[out$items$item_code == "I001"])
  expect_false(out$items$imported[out$items$item_code == "I004"])
  expect_error(qual_execute(r, "UPDATE research.item_lineage_events SET reason='changed' WHERE id=$1", params = list(merged$id)), "immutable record")
  parent <- out$items$id[out$items$item_code == "I001"]
  child <- out$items$id[out$items$item_code == "I004"]
  expect_error(qual_execute(r, "INSERT INTO research.item_lineage_edges VALUES($1,$2,$3,$4)", params = list(f$study_id, split$id, parent, child)), "incomplete or modified lineage")
})

test_that("qualitative services and foreign keys reject cross-study references", {
  r <- qual_repo()
  a <- qual_fixture(r)
  b <- qual_fixture(r)
  source <- record_qualitative_source(r, a$editor, a$study_id, "Synthetic text", "source", "source")
  theme <- create_qualitative_theme(r, b$editor, b$study_id, "topic", 1L, "Topic", "Definition", "theme")
  expect_error(redact_qualitative_source(r, b$editor, b$study_id, source$id, "Other study text", "Reason", "foreign"), class = "DEL_NOT_FOUND")
  expect_error(code_qualitative_source(r, a$editor, a$study_id, source$id, theme$id, "include", "Cross study", "foreign-theme"), class = "DEL_NOT_FOUND")
  expect_error(get_qualitative_provenance(r, a$panel[[1]], a$study_id), class = "DEL_FORBIDDEN")
  expect_error(qual_execute(r, paste("INSERT INTO research.qualitative_codings(id,study_id,source_id,theme_id,decision,reason,coder_id)", "VALUES($1,$2,$3,$4,'include','Invalid cross-study reference',$5)"), params = list(uuid::UUIDgenerate(), a$study_id, source$id, theme$id, a$editor$principal_id)), "foreign key")
})
