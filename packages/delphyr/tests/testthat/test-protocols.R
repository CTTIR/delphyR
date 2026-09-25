test_that("amendments preserve historical instruments and reject stale or redefined scales", {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test")
  on.exit(DBI::dbDisconnect(r$con))
  f <- demo_study(r, n = 2L, item_count = 1L)
  before <- list_protocol_versions(r, f$manager, f$study_id)
  p <- delphyr:::from_json(before$config)
  p$study$title <- "Amended synthetic title"
  expect_error(amend_protocol(r, f$panel[[1]], f$study_id, p, before$hash, "Test", "forbidden"), class = "DEL_FORBIDDEN")
  result <- amend_protocol(r, f$manager, f$study_id, p, before$hash, "Prospective synthetic amendment", "amend")
  expect_equal(result$version, 2L)
  expect_identical(amend_protocol(r, f$manager, f$study_id, p, before$hash, "Prospective synthetic amendment", "amend")$id, result$id)
  expect_error(amend_protocol(r, f$manager, f$study_id, p, before$hash, "Stale review", "stale"), class = "DEL_CONFLICT")
  after <- list_protocol_versions(r, f$manager, f$study_id)
  expect_equal(nrow(after), 2L)
  expect_identical(after$config[1], before$config[1])
  expect_equal(after$reason[2], "Prospective synthetic amendment")
  existing <- DBI::dbGetQuery(r$con, "SELECT protocol_id FROM research.rounds WHERE id=$1", params = list(f$round$id))
  expect_identical(existing$protocol_id, before$id)
  reduced <- p
  reduced$panel$groups <- "professionals"
  expect_error(amend_protocol(r, f$manager, f$study_id, reduced, result$hash, "Remove occupied group", "remove-group"), class = "DEL_CONFLICT")
  expect_equal(nrow(list_protocol_versions(r, f$manager, f$study_id)), 2L)
  p$instrument$scales$relevance_9$anchors[[1]] <- "Changed meaning"
  expect_error(amend_protocol(r, f$manager, f$study_id, p, result$hash, "Scale change", "scale"), class = "DEL_CONFLICT")
  expect_error(delphyr:::execute(r, "UPDATE research.protocol_amendments SET reason='rewrite' WHERE study_id=$1", f$study_id), "immutable")
  expect_equal(nrow(list_protocol_versions(r, f$manager, f$study_id)), 2L)
})
