test_that("protocols reject typos and unsupported scientific rules", {
  p <- demo_protocol()
  expect_true(validate_protocol(p)$valid)
  p$analysis$denominater <- "all"
  expect_false(validate_protocol(p)$valid)
  p <- demo_protocol()
  p$analysis$consensus$agree_values <- 1:3
  expect_error(new_protocol(p), class = "DEL_VALIDATION")
  p <- demo_protocol()
  p$instrument$scales$relevance_9$values <- 1:5
  expect_false(validate_protocol(p)$valid)
  p <- demo_protocol()
  p$analysis$consensus$out <- p$analysis$consensus$`in`
  expect_false(validate_protocol(p)$valid)
  p <- demo_protocol()
  p$stopping$max_rounds <- 0
  expect_false(validate_protocol(p)$valid)
  s <- new_scale("binary", 0:1)
  expect_equal(validate_response(0, "answered", s)$value_int, 0L)
  expect_error(validate_response(0, "abstained", s), class = "DEL_VALIDATION")
  expect_error(validate_response(10, "answered", new_scale("ordinal_integer", 1:9)), class = "DEL_VALIDATION")
  expect_equal(validate_response("NA", "answered", new_scale("free_text"))$value_text, "NA")
})
test_that("independent reference cases A to J match the specification", {
  overall <- function(x) {
    a <- analyse_round(demo_snapshot(x))
    a$results[a$results$stratum == "overall", ]
  }
  a <- overall(c(1, 4, 6, 7, 7, 8, 8, 9, 9, 9))
  expect_equal(unname(unlist(a[c("n_valid", "n_agree", "n_disagree", "median", "q1", "q3", "iqr")])), c(10, 7, 1, 7.5, 6.25, 8.75, 2.5))
  expect_equal(a$classification, "consensus_in")
  s <- demo_snapshot(c(1, 4, 6, 7, 7, 8, 8, 9, 9, 9, NA, NA))
  z <- s$data
  z$answer_status[11] <- "unable_to_judge"
  s <- new_snapshot(transform(z, value_integer = value_integer)[, c("panelist_id", "item_code", "item_version", "dimension_code", "answer_status", "value_integer", "value_text")], unique(z[, c("panelist_id", "group_code", "submitted")]), s$items, s$protocol)
  b <- analyse_round(s)$results[1, ]
  expect_equal(c(b$n_assigned, b$n_valid, b$n_unable, b$n_not_answered), c(12, 10, 1, 1))
  expect_equal(b$p_agree, .7)
  expect_equal(overall(c(rep(1, 3), rep(4, 3), rep(7, 14)))$classification, "no_consensus")
  expect_equal(overall(c(rep(9, 7), 5, 5))$classification, "insufficient_data")
  e <- overall(rep(NA_real_, 20))
  expect_true(all(is.na(e[c("p_agree", "median", "iqr")])))
  expect_equal(e$classification, "insufficient_data")
  expect_equal(overall(c(1, 1, 2, 2, 3, 3, 3, 4, 5, 9))$classification, "consensus_out")
  expect_equal(overall(c(rep(7, 139), rep(1, 20), rep(5, 41)))$classification, "no_consensus")
  h <- overall(rep(9, 10))
  expect_equal(h$iqr, 0)
  expect_equal(h$classification, "consensus_in")
  expect_equal(overall(rep(5, 10))$classification, "no_consensus")
  expect_error(demo_snapshot(c(1:9, 10)), class = "DEL_VALIDATION")
})
test_that("groups, hashes and dimensions remain independent", {
  s <- demo_snapshot(rep(9, 10))
  s$protocol$analysis$consensus$group_policy <- "all_required_groups"
  s <- new_snapshot(s$data[, c("panelist_id", "item_code", "item_version", "dimension_code", "answer_status", "value_integer", "value_text")], unique(s$data[, c("panelist_id", "group_code", "submitted")]), s$items, s$protocol)
  a <- analyse_round(s)
  expect_equal(a$decisions$classification, "insufficient_data")
  s2 <- s
  s2$data <- s2$data[nrow(s2$data):1, ]
  expect_identical(analyse_round(s2)$provenance$result_hash, a$provenance$result_hash)
  s2$data$value_integer[1] <- 1
  expect_error(analyse_round(s2), class = "DEL_VALIDATION")
  p <- demo_protocol()
  p$instrument$dimensions[[2]] <- list(code = "clarity", scale = "relevance_9")
  items <- rbind(s$items, transform(s$items, dimension_code = "clarity"))
  r <- s$data[, c("panelist_id", "item_code", "item_version", "dimension_code", "answer_status", "value_integer", "value_text")]
  r <- rbind(r, transform(r, dimension_code = "clarity", value_integer = 1L))
  a <- analyse_round(new_snapshot(r, unique(s$data[, c("panelist_id", "group_code", "submitted")]), items, p))
  expect_equal(a$results$classification[a$results$stratum == "overall"], c("consensus_in", "consensus_out"))
})
test_that("paired stability is separate from consensus and attrition", {
  a <- demo_snapshot(c(5, 7, 8, 9))
  b <- demo_snapshot(c(6, 7, 7, 9))
  x <- compare_rounds(a, b)
  expect_equal(c(x$n_paired, x$mean_absolute_change, x$median_absolute_change, x$proportion_unchanged, x$proportion_within_one), c(4, .5, .5, .5, 1))
  m <- data.frame(item_code = "I001", dimension_code = "relevance", previous_version = 1, current_version = 1, comparable = FALSE, reason = "meaning changed")
  x <- compare_rounds(a, b, m)
  expect_equal(x$status, "not_comparable")
  expect_true(is.na(x$mean_absolute_change))
})
test_that("feedback removes small cells including complementary totals", {
  s <- demo_snapshot(rep(9, 14), c(rep("professionals", 10), rep("public_contributors", 4)))
  f <- prepare_feedback(analyse_round(s), policy = list(group_statistics = TRUE, minimum_display_cell_n = 5L, complementary_suppression = TRUE))
  expect_true(all(f$results$suppressed))
  expect_true(all(is.na(f$results$n_valid)))
  expect_equal(nrow(f$distributions), 0L)
  expect_true(validate_feedback(f))
  f$results$n_valid[1] <- 14
  expect_error(validate_feedback(f), class = "DEL_VALIDATION")
})

test_that("metamorphic relations hold and the minimum is not mistaken for one", {
  fields <- c("panelist_id", "item_code", "item_version", "dimension_code", "answer_status", "value_integer", "value_text")
  rebuild <- function(responses, assignments, s) new_snapshot(responses[, fields], assignments, s$items, s$protocol)
  statistics <- function(a) {
    r <- a$results
    r <- r[order(r$item_code, r$dimension_code, r$stratum), setdiff(names(r), "round_number")]
    rownames(r) <- NULL
    r
  }
  values <- c(1, 4, 6, 7, 7, 8, 8, 9, 9, 9, 2, 8)
  groups <- rep(c("professionals", "public_contributors"), 6)
  s <- demo_snapshot(values, groups)
  base <- analyse_round(s)
  responses <- s$data[s$data$submitted, fields]
  assignments <- unique(s$data[, c("panelist_id", "group_code", "submitted")])
  # The order of the rows changes nothing, not even the result hash.
  set.seed(20261003)
  shuffled <- analyse_round(rebuild(responses[sample(nrow(responses)), ], assignments[sample(nrow(assignments)), ], s))
  expect_identical(statistics(shuffled), statistics(base))
  expect_identical(shuffled$provenance$result_hash, base$provenance$result_hash)
  # A bijective renaming of the pseudonyms leaves every aggregate unchanged.
  rename <- stats::setNames(sprintf("X%03d", rev(seq_len(nrow(assignments)))), assignments$panelist_id)
  renamed <- analyse_round(rebuild(transform(responses, panelist_id = unname(rename[panelist_id])), transform(assignments, panelist_id = unname(rename[panelist_id])), s))
  expect_identical(statistics(renamed), statistics(base))
  # Members who cannot judge change missingness, not the agreement among valid ratings.
  extra <- data.frame(panelist_id = c("U001", "U002"), group_code = "professionals", submitted = TRUE)
  unable <- data.frame(panelist_id = extra$panelist_id, item_code = "I001", item_version = 1L, dimension_code = "relevance", answer_status = "unable_to_judge", value_integer = NA_integer_, value_text = NA_character_)
  more <- analyse_round(rebuild(rbind(responses, unable), rbind(assignments, extra), s))
  overall <- function(a) a$results[a$results$stratum == "overall", ]
  expect_identical(overall(more)$p_agree, overall(base)$p_agree)
  expect_identical(overall(more)$n_valid, overall(base)$n_valid)
  expect_identical(overall(more)$n_unable, overall(base)$n_unable + 2L)
  expect_identical(overall(more)$n_assigned, overall(base)$n_assigned + 2L)
  # Doubling every observation keeps the proportions but may change whether
  # the minimum number of valid ratings is reached: no invariance is assumed
  # for the classification.
  small <- demo_snapshot(c(9, 9, 9, 8, 8, 7, 7, 2))
  twice <- function(z) {
    d <- z$data[z$data$submitted, fields]
    copy <- transform(d, panelist_id = paste0(panelist_id, "-B"))
    a <- unique(z$data[, c("panelist_id", "group_code", "submitted")])
    rebuild(rbind(d, copy), rbind(a, transform(a, panelist_id = paste0(panelist_id, "-B"))), z)
  }
  one <- overall(analyse_round(small))
  two <- overall(analyse_round(twice(small)))
  expect_identical(two$p_agree, one$p_agree)
  expect_identical(two$n_valid, 2L * one$n_valid)
  expect_identical(one$classification, "insufficient_data")
  expect_identical(two$classification, "consensus_in")
})
