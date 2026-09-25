rebuild_core_snapshot <- function(s, responses = s$data, assignments = unique(s$data[, c("panelist_id", "group_code", "submitted")]), items = s$items, protocol = s$protocol) {
  new_snapshot(responses, assignments, items, protocol)
}

test_that("strict narrow rule overlaps and probability boundaries are exact", {
  r <- demo_protocol()$analysis$consensus
  r$`in`$agree <- list(operator = "gt", proportion = .49)
  r$`in`$disagree <- list(operator = "gt", proportion = .49)
  r$out <- r$`in`
  expect_error(classify_consensus(list(n_valid = 1000, n_agree = 495, n_disagree = 495), r), class = "DEL_VALIDATION")
  r$`in`$agree$proportion <- .5
  r$out <- r$`in`
  r$`in`$disagree$proportion <- .5
  r$out <- r$`in`
  expect_equal(classify_consensus(list(n_valid = 10, n_agree = 5, n_disagree = 5), r)$classification, "no_consensus")
  r$`in`$agree$operator <- r$`in`$disagree$operator <- "gte"
  r$out <- r$`in`
  expect_error(classify_consensus(list(n_valid = 10, n_agree = 5, n_disagree = 5), r), class = "DEL_VALIDATION")
})

test_that("configuration rejects ambiguous group and scale identities", {
  p <- demo_protocol()
  p$panel$groups <- c("overall", "professionals")
  expect_false(validate_protocol(p)$valid)
  p <- demo_protocol()
  p$panel$groups <- c(NA_character_, "professionals")
  expect_false(validate_protocol(p)$valid)
  p <- demo_protocol()
  p$instrument$scales[[2]] <- p$instrument$scales[[1]]
  names(p$instrument$scales) <- rep("relevance_9", 2)
  expect_false(validate_protocol(p)$valid)
  p <- demo_protocol()
  p$analysis$stability$enabled <- "yes"
  expect_false(validate_protocol(p)$valid)
})

test_that("snapshot units cannot silently duplicate a person across item versions", {
  s <- demo_snapshot()
  items <- rbind(s$items, transform(s$items, item_version = 2L))
  expect_error(rebuild_core_snapshot(s, items = items), class = "DEL_VALIDATION")
  r <- s$data
  r$answer_status[1] <- NA_character_
  expect_error(rebuild_core_snapshot(s, responses = r), class = "DEL_VALIDATION")
  r <- s$data
  r$panelist_id[1] <- "P\034001"
  expect_error(rebuild_core_snapshot(s, responses = r), class = "DEL_VALIDATION")
  a <- unique(s$data[, c("panelist_id", "group_code", "submitted")])
  a$panelist_id[1] <- " "
  expect_error(rebuild_core_snapshot(s, assignments = a), class = "DEL_VALIDATION")
})

test_that("unrelated source metadata cannot corrupt snapshot joins", {
  s <- demo_snapshot()
  a <- unique(s$data[, c("panelist_id", "group_code", "submitted")])
  a$item_code <- "source_metadata"
  expect_identical(rebuild_core_snapshot(s, assignments = a)$content_hash, s$content_hash)
})

test_that("feedback refuses altered analysis and invalid disclosure policy", {
  a <- analyse_round(demo_snapshot())
  altered <- a
  altered$results$n_valid[1] <- 999L
  expect_error(prepare_feedback(altered), class = "DEL_VALIDATION")
  expect_error(prepare_feedback(a, policy = list(
    group_statistics = NA, minimum_display_cell_n = 5L,
    complementary_suppression = TRUE
  )), class = "DEL_VALIDATION")
})

test_that("paired mappings require an explicit nonmissing reason", {
  a <- demo_snapshot()
  m <- data.frame(
    item_code = "I001", dimension_code = "relevance", previous_version = 1L,
    current_version = 1L, comparable = TRUE, reason = " "
  )
  expect_error(compare_rounds(a, a, m), class = "DEL_VALIDATION")
  m$reason <- "reviewed"
  m$comparable <- NA
  expect_error(compare_rounds(a, a, m), class = "DEL_VALIDATION")
})

test_that("canonical hashes retain names, missingness and empty table schemas", {
  expect_false(identical(content_hash(c(item_a = 1L)), content_hash(c(item_b = 1L))))
  expect_false(identical(content_hash(data.frame(a = integer())), content_hash(data.frame(b = integer()))))
  expect_false(identical(content_hash(NULL), content_hash(NA_real_)))
  expect_false(identical(content_hash(list(a = 1)), content_hash(list("a", 1))))
  expect_identical(content_hash(1L), content_hash(1))
  expect_identical(content_hash(c(1L, 2L)), content_hash(list(1, 2)))
  expect_identical(content_hash(list(z = c(x = 2, y = 1), a = TRUE)), content_hash(list(a = TRUE, z = c(y = 1L, x = 2L))))
  expect_identical(
    content_hash(data.frame(a = c(2L, 1L), b = c("b", "a"))),
    content_hash(data.frame(b = c("a", "b"), a = c(1, 2)))
  )
  expect_error(content_hash(setNames(list(1, 2), c("a", "a"))), class = "DEL_VALIDATION")
})

test_that("analysis and feedback retain scientific hashes across JSON persistence", {
  a <- analyse_round(demo_snapshot())
  restored <- structure(jsonlite::fromJSON(delphyr:::json(a)), class = "delphyr_analysis")
  f <- prepare_feedback(restored)
  restored_feedback <- structure(jsonlite::fromJSON(delphyr:::json(f)), class = "delphyr_feedback_draft")
  expect_true(validate_feedback(restored_feedback))
  expect_identical(prepare_feedback(a)$hash, f$hash)
})
