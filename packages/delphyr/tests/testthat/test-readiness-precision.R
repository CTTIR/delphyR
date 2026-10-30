test_that("scientific JSON and hashes distinguish adjacent binary doubles", {
  values <- c(.7, .7 + .Machine$double.eps / 2, 1 / 7, 1e-300,
    .Machine$double.xmin, .Machine$double.xmin * .Machine$double.eps,
    .Machine$double.xmax)
  expect_identical(jsonlite::fromJSON(json(values)), values)
  expect_false(identical(content_hash(values[1]), content_hash(values[2])))
  expect_false(identical(content_hash(data.frame(x = values[1])), content_hash(data.frame(x = values[2]))))
  expect_match(content_hash(values), "^v2:[0-9a-f]{64}$")
  # This value was recorded with the pre-versioned implementation.
  expect_identical(content_hash(.7, version = "1"), "8ce1dc81f29831f3bfdbb570189615e7fcdfbbdca3687777e8aebadcfe9abf6e")
  expect_identical(hash_version(content_hash(.7, version = "1")), "1")
  expect_identical(hash_version(content_hash(.7)), "2")
  for (bad in list(NULL, NA_character_, "", "v1:123", paste0("v3:", strrep("a", 64)), c("1", "2"))) {
    expect_error(hash_version(bad), class = "DEL_VALIDATION")
    expect_error(content_hash(.7, version = bad), class = "DEL_VALIDATION")
  }
})

test_that("a frozen near-boundary protocol keeps its classification after JSON transport", {
  original <- demo_snapshot()
  data <- original$data
  fields <- c("panelist_id", "item_code", "item_version", "dimension_code", "answer_status", "value_integer", "value_text")
  p <- original$protocol
  p$analysis$consensus$`in`$agree$proportion <- .7 + .Machine$double.eps / 2
  changed <- new_snapshot(data[, fields], unique(data[, c("panelist_id", "group_code", "submitted")]), original$items, p)
  expect_identical(analyse_round(original)$decisions$classification, "consensus_in")
  expect_identical(analyse_round(changed)$decisions$classification, "no_consensus")
  expect_false(identical(changed$content_hash, original$content_hash))
  restored <- read_snapshot(snapshot_json(changed))
  expect_identical(restored$protocol$analysis$consensus$`in`$agree$proportion, p$analysis$consensus$`in`$agree$proportion)
  expect_identical(restored$content_hash, changed$content_hash)
  expect_identical(analyse_round(restored)$provenance$result_hash, analyse_round(changed)$provenance$result_hash)
  expect_identical(analyse_round(restored)$decisions$classification, "no_consensus")
  changed$protocol <- original$protocol
  expect_error(analyse_round(changed), "snapshot.hash", class = "DEL_VALIDATION")
  # A v2 record is never verified by trying the legacy algorithm instead.
  changed$content_hash <- paste0("v2:", content_hash(list(data = changed$data, items = changed$items,
    protocol = changed$protocol, round_number = changed$round_number), version = "1"))
  expect_error(analyse_round(changed), "snapshot.hash", class = "DEL_VALIDATION")
})

test_that("PostgreSQL persistence retains a protocol's exact consensus boundary", {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  r <- connect_repository(host = "127.0.0.1", port = 55439,
    dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  on.exit(DBI::dbDisconnect(r$con))
  actor <- demo_actor(r, provision_demo_principal(r, paste0("precision-", uid()), TRUE))
  p <- demo_protocol()
  p$study$code <- paste0("PREC-", substr(uid(), 1, 8))
  p$analysis$consensus$`in`$agree$proportion <- .7 + .Machine$double.eps / 2
  study <- create_study(r, actor, p, "create")
  stored <- list_protocol_versions(r, actor, study$id)
  roundtrip <- from_json(stored$config)
  expect_identical(roundtrip$analysis$consensus$`in`$agree$proportion, p$analysis$consensus$`in`$agree$proportion)
  expect_identical(content_hash(roundtrip), stored$hash)
  expect_identical(classify_consensus(list(n_valid = 10, n_agree = 7, n_disagree = 1),
    roundtrip$analysis$consensus)$classification, "no_consensus")
})
