readiness_snapshot <- function(values, study_code = "READINESS-STUDY", round_number = 1L,
                               title = "Synthetic boundary checks", extreme = FALSE,
                               item_version = 1L) {
  protocol <- demo_protocol()
  protocol$study$code <- study_code
  protocol$study$title <- title
  protocol$analysis$consensus$group_policy <- "pooled"
  if (extreme) {
    endpoints <- c(-.Machine$integer.max, .Machine$integer.max)
    protocol$instrument$scales$relevance_9$values <- endpoints
    protocol$analysis$consensus$agree_values <- endpoints[2]
    protocol$analysis$consensus$disagree_values <- endpoints[1]
  }
  assignments <- data.frame(panelist_id = paste0("P", seq_along(values)),
                            group_code = "professionals", submitted = TRUE)
  items <- data.frame(item_code = "I001", item_version = item_version,
                      dimension_code = "relevance", scale_code = "relevance_9")
  responses <- data.frame(panelist_id = assignments$panelist_id, item_code = "I001",
                          item_version = item_version, dimension_code = "relevance",
                          answer_status = "answered", value_integer = values,
                          value_text = NA_character_)
  new_snapshot(responses, assignments, items, protocol, round_number)
}

test_that("scale construction rejects unrepresentable integer categories without coercion warnings", {
  for (levels in list(c(.Machine$integer.max, .Machine$integer.max + 1),
                      c(1, .Machine$integer.max + 1),
                      c(-.Machine$integer.max - 1, 1), c(-1e20, 1e20))) {
    expect_warning(expect_error(new_scale("ordinal_integer", levels),
                                class = "DEL_VALIDATION"), NA)
  }
  endpoints <- as.integer(c(-.Machine$integer.max, .Machine$integer.max))
  scale <- expect_warning(new_scale("ordinal_integer", endpoints), NA)
  expect_identical(scale$levels, endpoints)
  expect_identical(validate_response(endpoints[1], "answered", scale)$value_int, endpoints[1])
  expect_identical(validate_response(endpoints[2], "answered", scale)$value_int, endpoints[2])
})

test_that("response validation refuses overflow even for an altered scale", {
  scale <- new_scale("ordinal_integer", 1:9)
  scale$levels <- c(1, .Machine$integer.max + 1)
  expect_warning(expect_error(validate_response(.Machine$integer.max + 1,
                                                "answered", scale),
                              class = "DEL_VALIDATION"), NA)
})

test_that("accepted item versions survive portable snapshot reconstruction", {
  expect_warning(expect_error(readiness_snapshot(c(7L, 8L),
    item_version = .Machine$integer.max + 1), "items.keys", class = "DEL_VALIDATION"), NA)
  snapshot <- readiness_snapshot(c(7L, 8L), item_version = .Machine$integer.max)
  restored <- read_snapshot(snapshot_json(snapshot))
  expect_identical(restored$items$item_version, .Machine$integer.max)
  expect_identical(restored$content_hash, snapshot$content_hash)
})

test_that("round comparison does not pair unrelated study pseudonyms", {
  previous <- readiness_snapshot(c(5L, 7L, 8L))
  foreign <- readiness_snapshot(c(6L, 7L, 9L), study_code = "OTHER-STUDY", round_number = 2L)
  expect_error(compare_rounds(previous, foreign), "comparison.study", class = "DEL_VALIDATION")
  current <- readiness_snapshot(c(6L, 7L, 9L), round_number = 2L,
                                title = "Reviewed same-study amendment")
  result <- compare_rounds(previous, current)
  expect_identical(result$status, "descriptive")
  expect_equal(result$n_paired, 3L)
  expect_equal(result$mean_absolute_change, 2 / 3)
})

test_that("paired differences remain exact across supported integer endpoints", {
  previous <- readiness_snapshot(as.integer(c(-.Machine$integer.max, .Machine$integer.max)),
                                 extreme = TRUE)
  current <- readiness_snapshot(as.integer(c(.Machine$integer.max, -.Machine$integer.max)),
                                round_number = 2L, extreme = TRUE)
  result <- expect_warning(compare_rounds(previous, current), NA)
  expect_equal(result$n_paired, 2L)
  expect_equal(result$mean_absolute_change, 2 * as.double(.Machine$integer.max))
  expect_equal(result$median_absolute_change, 2 * as.double(.Machine$integer.max))
  expect_equal(result$proportion_unchanged, 0)
  expect_equal(result$proportion_within_one, 0)
})

test_that("zero ratings retain scientific identity regardless of the sign of zero", {
  expect_identical(content_hash(-0), content_hash(0))
  table <- data.frame(value = c(-0, 0))
  expect_identical(content_hash(table), content_hash(table[2:1, , drop = FALSE]))
  nested <- list(table = table, values = list(-0, 0), zero = -0)
  generic <- as.character(jsonlite::toJSON(canonical(nested), auto_unbox = TRUE,
    null = "null", na = "null", digits = 17L))
  expect_identical(canonical_json(nested), generic)
  expect_identical(content_hash(nested),
    content_hash(list(table = data.frame(value = c(0, 0)), values = list(0, 0), zero = 0)))
  # Preserve the old contract for existing records, including its zero behavior.
  expect_false(identical(content_hash(-0, version = "1"), content_hash(0, version = "1")))
  expect_identical(content_hash(-0, version = "1"),
    "7e77f1bd0fa7c653cb45d2940b7cc8a10cc139950b7fb8c6ee29ca8f81128942")

  seed <- readiness_snapshot(c(1L, 1L))
  protocol <- seed$protocol
  protocol$instrument$scales$relevance_9$type <- "binary"
  protocol$instrument$scales$relevance_9$values <- 0:1
  protocol$analysis$consensus$agree_values <- 1L
  protocol$analysis$consensus$disagree_values <- 0L
  responses <- seed$data
  responses$value_integer <- c(-0, 0)
  snapshot <- new_snapshot(responses,
    unique(seed$data[c("panelist_id", "group_code", "submitted")]), seed$items, protocol)
  restored <- read_snapshot(snapshot_json(snapshot))
  expect_equal(restored$data$value_integer, c(0L, 0L))
  expect_identical(restored$content_hash, snapshot$content_hash)
})

# These files were produced with the unmodified functions at commit
# 02e81e5b3f4f9b53eaaf6d66d86750a74261aa26, in an independent environment.
# Expected legacy hashes are fixed oracles, never computed by the new writer.
test_that("legacy portable snapshots retain their original scientific hashes", {
  path <- test_path("fixtures", "legacy-hashes")
  snapshot_hash <- "118323283b2b5c2e4216e158aee90af11d2946fc76446f5ce24f96f4561837da"
  result_hash <- "695733ec62eeb4d91b5041c99048ac3d203d607c78682a1418f1296e01dd51d0"
  snapshot <- read_snapshot(paste(readLines(file.path(path, "snapshot.json")), collapse = "\n"))
  expect_identical(snapshot$content_hash, snapshot_hash)
  analysis <- reproduce_export(path)
  expect_identical(analysis$provenance$result_hash, result_hash)
  expect_identical(analysis$provenance$rules_hash,
                   "e48b42f6679cccedbabb13b5d887e451b151b7d127e389f89ae421df15b900ce")
  overall <- analysis$results[analysis$results$stratum == "overall", ]
  expect_equal(c(overall$n_assigned, overall$n_valid, overall$n_not_answered), c(12, 11, 1))
  expect_equal(c(overall$p_agree, overall$p_disagree, overall$median, overall$iqr), c(8 / 11, 2 / 11, 8, 3))
  expect_identical(overall$classification, "no_consensus")
  restored <- read_snapshot(snapshot_json(snapshot))
  expect_identical(restored$content_hash, snapshot_hash)
  expect_identical(analyse_round(restored)$provenance$result_hash, result_hash)
})

test_that("legacy persisted analyses and feedback still pass integrity checks", {
  path <- test_path("fixtures", "legacy-hashes")
  analysis <- structure(jsonlite::fromJSON(file.path(path, "analysis.json")),
                         class = "delphyr_analysis")
  draft <- prepare_feedback(analysis)
  expect_true(validate_feedback(draft))
  expect_identical(draft$analysis_hash,
                   "695733ec62eeb4d91b5041c99048ac3d203d607c78682a1418f1296e01dd51d0")
  legacy <- structure(jsonlite::fromJSON(file.path(path, "feedback.json")),
                       class = "delphyr_feedback_draft")
  expect_identical(legacy$hash,
                   "aed7010ff21098e2b9ec80ff1dfb80c477060db063e13172bd66c82d5bd02e72")
  expect_true(validate_feedback(legacy))
  expect_equal(draft$results, legacy$results)
  legacy$results$p_agree[1] <- 0.5
  expect_error(validate_feedback(legacy), "feedback.hash", class = "DEL_VALIDATION")
})

test_that("legacy study exports reproduce round and paired-comparison hashes", {
  result <- reproduce_study_export(test_path("fixtures", "legacy-study-hashes"))
  expect_length(result$analyses, 2L)
  expect_identical(result$provenance$comparison_hash,
    "8cde3721fc9facb7b90a36f6db36b46e2b882b20e612b8bbe719f41b08849c47")
  expect_identical(result$analyses[["2"]]$provenance$snapshot_hash,
    "fba7c283ca190631654fa717e5adba43101fd0d517f8cc77f6223ea67a7ba580")
  expect_identical(result$analyses[["2"]]$provenance$result_hash,
    "c9d8f2a5d550662cd0b73d8f88fd4bc34d0b6a4c725250c64d991fd39b3d01f7")
  comparison <- result$comparisons
  expect_identical(comparison$status, "descriptive")
  expect_equal(c(comparison$n_paired, comparison$n_lost, comparison$n_new), c(10, 1, 1))
  expect_equal(c(comparison$mean_absolute_change, comparison$proportion_unchanged), c(0.4, 0.6))
})
