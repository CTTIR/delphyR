# The canonical form of a table is written directly for speed. These tests
# hold it to the generic form, which defines the hash, and hold the column-wise
# snapshot validation to the row-by-row rules.
generic_json <- function(x) as.character(jsonlite::toJSON(canonical(x), auto_unbox = TRUE, null = "null", na = "null", digits = NA))
generic_hash <- function(x) digest::digest(generic_json(x), algo = "sha256", serialize = FALSE)

test_that("the direct table form is byte for byte the generic canonical form", {
  hostile <- c(
    "", " ", "plain", "quote\" inside", "back\\slash", "ends with backslash\\", "\",\"", "a\",\"b", "\\\",\\\"", "</script>", "<\\/b>",
    "tab\there", "line\nbreak", "carriage\rreturn", "bell\ab", "form\ffeed", "unicode \u00e4\u00f6\u00fc \u20ac \u4e2d", "\u2028 and \u2029", "emoji \U0001F600",
    "null", "true", "{\"kind\":\"missing\"}", "delphyr-table-x-1", "[1,2]", "'single'", "/slash/", "%s %d", "a,b", ","
  )
  set.seed(20261002)
  numbers <- c(0, 1, -1, 7, 9, 100000, 1e5 + 1, 123456789, 2147483647, -2147483648, 1e15, 1e16, 1e-7, 0.1, 1 / 3, 2.5, -0.000123, 1e300, 6.02214076e23)
  tables <- list(
    data.frame(text = hostile, n = seq_along(hostile), stringsAsFactors = FALSE),
    data.frame(number = numbers),
    data.frame(a = c(NA, "x", NA), b = c(NA_integer_, 2L, NA), c = c(NA, TRUE, FALSE), d = c(NA_real_, NaN, 1.5), stringsAsFactors = FALSE),
    data.frame(only = character(), stringsAsFactors = FALSE),
    data.frame(one = "single row", stringsAsFactors = FALSE),
    data.frame(flag = c(TRUE, FALSE, NA)),
    data.frame(`key with \"quote\" and \\` = 1:2, `</b>` = c("x", "y"), check.names = FALSE, stringsAsFactors = FALSE),
    data.frame(z = 3:1, a = c("b", "a", "b"), m = c(2.5, NA, 2.5), stringsAsFactors = FALSE)
  )
  for (i in 1:40) {
    n <- sample(0:60, 1)
    tables[[length(tables) + 1L]] <- data.frame(
      id = sample(c(hostile, NA), n, replace = TRUE), value = sample(c(numbers, NA), n, replace = TRUE), whole = sample(c(1:9, NA), n, replace = TRUE),
      flag = sample(c(TRUE, FALSE, NA), n, replace = TRUE), stringsAsFactors = FALSE
    )
  }
  for (x in tables) {
    expect_false(is.null(table_json(x[, sort(names(x), method = "radix"), drop = FALSE])))
    expect_identical(canonical_json(x), generic_json(x))
    expect_identical(content_hash(x), generic_hash(x))
  }
  # Tables inside declarative structures, as in a snapshot and an analysis.
  nested <- list(data = tables[[1]], items = tables[[3]], protocol = demo_protocol(), round_number = 2L, empty = tables[[4]], list_of = list(tables[[2]], "delphyr-table-x-1", NULL))
  expect_identical(canonical_json(nested), generic_json(nested))
  snapshot <- demo_snapshot(c(1, 4, NA, 7, 7, 8, 8, 9, 9, 9))
  part <- list(data = snapshot$data, items = snapshot$items, protocol = snapshot$protocol, round_number = snapshot$round_number)
  expect_identical(snapshot$content_hash, generic_hash(part))
  analysis <- analyse_round(snapshot)
  expect_identical(content_hash(analysis$results), generic_hash(analysis$results))
  expect_identical(content_hash(analysis$distributions), generic_hash(analysis$distributions))
  # Row and column order never matter; a changed cell always does.
  x <- tables[[1]]
  expect_identical(content_hash(x[rev(seq_len(nrow(x))), 2:1]), content_hash(x))
  y <- x
  y$text[5] <- paste0(y$text[5], " ")
  expect_false(identical(content_hash(y), content_hash(x)))
})

test_that("tables the direct form cannot write take the generic form with the same result", {
  x <- data.frame(when = as.Date("2026-10-02") + 0:1)
  expect_null(table_json(x))
  expect_error(content_hash(x), class = "DEL_VALIDATION")
  expect_error(content_hash(data.frame(level = factor(c("a", "b")))), class = "DEL_VALIDATION")
  expect_error(content_hash(data.frame(value = c(1, Inf))), class = "DEL_VALIDATION")
  expect_error(generic_hash(data.frame(value = c(1, Inf))), class = "DEL_VALIDATION")
  empty <- data.frame()
  expect_null(table_json(empty))
  expect_identical(canonical_json(empty), generic_json(empty))
  expect_error(content_hash(data.frame(a = 1, a = 2, check.names = FALSE)), class = "DEL_VALIDATION")
})

test_that("column-wise snapshot validation reports what the row-by-row rules report", {
  p <- demo_protocol()
  p$instrument$dimensions <- list(list(code = "relevance", scale = "relevance_9"), list(code = "comment", scale = "comment_text"))
  p$instrument$scales$comment_text <- list(type = "free_text", values = list(), missing_options = c("unable_to_judge"))
  scales <- config_scales(p)
  reference <- function(joined) {
    tryCatch(
      {
        for (i in seq_len(nrow(joined))) {
          sc <- scales[[joined$scale_code[i]]]
          value <- if (sc$type == "free_text") joined$value_text[i] else joined$value_integer[i]
          other <- if (sc$type == "free_text") joined$value_integer[i] else joined$value_text[i]
          ensure(is.na(other), "responses.wrong_value_type")
          validate_response(value, joined$answer_status[i], sc)
        }
        "valid"
      },
      error = function(e) e$path
    )
  }
  current <- function(joined) tryCatch(
    {
      validate_snapshot_rows(joined, scales)
      "valid"
    },
    error = function(e) e$path
  )
  valid <- data.frame(
    scale_code = c("relevance_9", "relevance_9", "relevance_9", "relevance_9", "comment_text", "comment_text", "comment_text"),
    answer_status = c("answered", "not_answered", "unable_to_judge", "abstained", "answered", "unable_to_judge", "not_answered"),
    value_integer = c(7L, NA, NA, NA, NA, NA, NA), value_text = c(NA, NA, NA, NA, "A remark", NA, NA), stringsAsFactors = FALSE
  )
  expect_identical(current(valid), "valid")
  expect_identical(reference(valid), "valid")
  expect_identical(current(valid[0, ]), "valid")
  change <- function(row, column, value) {
    x <- valid
    x[[column]][row] <- value
    x
  }
  cases <- list(
    change(1, "value_integer", 10L), change(1, "value_integer", NA), change(1, "value_text", "stray text"), change(2, "value_integer", 5L),
    change(3, "answer_status", "not_applicable"), change(4, "answer_status", "unknown"), change(5, "value_text", "   "), change(5, "value_text", NA),
    change(5, "value_text", strrep("x", 20001L)), change(5, "value_integer", 3L), change(6, "value_text", "text beside a special response"),
    change(6, "answer_status", "abstained"), change(7, "value_text", "text although unanswered"),
    # Two faults: the earlier row decides, and within a row the earlier rule.
    change(3, "value_integer", 4L)[c(3, 1, 2, 4:7), ], transform(change(1, "value_integer", 99L), value_text = c("stray", value_text[-1]))
  )
  set.seed(7)
  for (i in 1:60) {
    x <- valid[sample(nrow(valid), 12, replace = TRUE), ]
    k <- sample(nrow(x), 2)
    x$answer_status[k[1]] <- sample(c("answered", "not_answered", "abstained", "unknown"), 1)
    if (x$scale_code[k[2]] == "relevance_9") x$value_integer[k[2]] <- sample(c(0L, 5L, 10L, NA), 1) else x$value_text[k[2]] <- sample(c("", "text", NA), 1)
    cases[[length(cases) + 1L]] <- x
  }
  for (x in cases) expect_identical(current(x), reference(x))
  expect_true(sum(vapply(cases, function(x) current(x) != "valid", logical(1))) > 30L)
  # A rating that is not a whole number or not numeric at all is refused.
  fraction <- valid
  fraction$value_integer <- as.numeric(fraction$value_integer)
  fraction$value_integer[1] <- 7.5
  expect_identical(current(fraction), reference(fraction))
  expect_identical(current(fraction), "value_int")
})

test_that("a participant's own previous answers equal their rows of the frozen snapshot", {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "PostgreSQL opt-in required")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(r$con))
  code <- paste0("OWN-", substr(uid(), 1, 8))
  manager <- demo_actor(r, provision_demo_principal(r, paste0("demo-manager-", code), TRUE))
  p <- demo_protocol()
  p$study$code <- code
  p$study$languages <- "en"
  p$panel$late_entry <- TRUE
  p$panel$return_after_missed_round <- TRUE
  p$instrument$dimensions <- list(list(code = "relevance", scale = "relevance_9"), list(code = "comment", scale = "comment_text"))
  p$instrument$scales$comment_text <- list(type = "free_text", values = list(), missing_options = c("unable_to_judge"))
  p$analysis$consensus$min_valid_n <- 2
  p$analysis$consensus$group_policy <- "pooled"
  study <- create_study(r, manager, p, "create")$id
  consent <- publish_consent(r, manager, study, "Synthetic information.", "en", "consent")$id
  member <- function(i) {
    actor <- demo_actor(r, provision_demo_principal(r, paste0("demo-", code, "-", i)))
    add_panelist(r, manager, study, actor$principal_id, unlist(p$panel$groups)[1], paste0("panel-", i))
    actor
  }
  panel <- lapply(1:4, member)
  row <- function(item, dimension, scale, required) data.frame(item_code = item, item_version = 1L, locale = "en", text = paste("Synthetic", item), dimension_code = dimension, scale_code = scale, source_ref = "SRC", required = required, display_order = match(item, c("b-item", "A-item", "a_item")))
  items <- rbind(row("b-item", "relevance", "relevance_9", FALSE), row("b-item", "comment", "comment_text", FALSE), row("A-item", "relevance", "relevance_9", FALSE), row("a_item", "relevance", "relevance_9", FALSE))
  stamp <- function() format(Sys.time() + 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  first <- prepare_round(r, manager, study, items, consent, stamp(), "round-1")
  for (state in c("review", "approved", "open")) transition_round(r, manager, first$id, state, first$hash, "Synthetic", paste("1", state))
  answer <- function(actor, values, submit) {
    e <- list_enrollments(r, actor, study)$id
    record_consent(r, actor, study, consent, TRUE, "consent")
    q <- get_questionnaire(r, actor, e)
    id <- function(item, dimension) q$items$id[q$items$item_code == item & q$items$dimension_code == dimension]
    for (v in values) save_response(r, actor, e, id(v$item, v$dimension), v$response, 0L, paste(v$item, v$dimension))
    if (submit) {
      q <- get_questionnaire(r, actor, e)
      submit_round(r, actor, e, setNames(q$responses$revision, q$responses$round_item_id), "submit")
    }
  }
  # Answers, a special response, free text and fields left open; one member
  # saves without submitting.
  answer(panel[[1]], list(list(item = "b-item", dimension = "relevance", response = list(value = 8L, status = "answered")), list(item = "b-item", dimension = "comment", response = list(value = "A remark, with \"quotes\"", status = "answered")), list(item = "A-item", dimension = "relevance", response = list(value = NULL, status = "abstained"))), TRUE)
  answer(panel[[2]], list(list(item = "a_item", dimension = "relevance", response = list(value = 3L, status = "answered")), list(item = "b-item", dimension = "comment", response = list(value = NULL, status = "unable_to_judge"))), TRUE)
  answer(panel[[3]], list(list(item = "b-item", dimension = "relevance", response = list(value = 5L, status = "answered"))), FALSE)
  answer(panel[[4]], list(), TRUE)
  transition_round(r, manager, first$id, "closed", first$hash, "Close", "close")
  snapshot <- freeze_round(r, manager, first$id, "freeze")$id
  analysis <- run_analysis(r, manager, snapshot, "analyse")$id
  feedback <- create_feedback(r, manager, analysis, command_id = "feedback")
  release_feedback(r, manager, feedback$id, feedback$hash, "release")
  late <- member(5)
  second <- prepare_round(r, manager, study, items, consent, stamp(), "round-2")
  assign_feedback(r, manager, second$id, feedback$id, "assign")
  for (state in c("review", "approved", "open")) transition_round(r, manager, second$id, state, second$hash, "Synthetic", paste("2", state))
  frozen <- get_snapshot(r, manager, snapshot)
  pseudonym <- function(actor) query(r, "SELECT l.panelist_id FROM identity.panelist_links l JOIN identity.memberships m ON m.study_id=l.study_id AND m.id=l.membership_id WHERE m.study_id=$1 AND m.principal_id=$2", study, actor$principal_id)$panelist_id
  for (actor in panel) {
    e <- list_enrollments(r, actor, study)
    own <- get_feedback(r, actor, e$id[e$number == 2L])$own
    expected <- frozen$data[frozen$data$panelist_id == pseudonym(actor), c("item_code", "item_version", "dimension_code", "answer_status", "value_integer", "value_text"), drop = FALSE]
    expected <- expected[order(expected$item_code, expected$item_version, expected$dimension_code), ]
    rownames(expected) <- NULL
    expect_identical(own, expected)
    expect_identical(nrow(own), 4L)
  }
  own <- function(i) {
    e <- list_enrollments(r, panel[[i]], study)
    get_feedback(r, panel[[i]], e$id[e$number == 2L])$own
  }
  expect_identical(own(1)$value_text[own(1)$dimension_code == "comment"], "A remark, with \"quotes\"")
  expect_setequal(own(1)$answer_status, c("answered", "abstained", "not_answered"))
  # Saved but never submitted: nothing of it was frozen.
  expect_true(all(own(3)$answer_status == "not_answered") && all(is.na(own(3)$value_integer)))
  # A member who joined later has no previous answers.
  e <- list_enrollments(r, late, study)
  record_consent(r, late, study, consent, TRUE, "consent")
  joined <- get_feedback(r, late, e$id[e$number == 2L])
  expect_identical(nrow(joined$own), 0L)
  expect_identical(names(joined$own), c("item_code", "item_version", "dimension_code", "answer_status", "value_integer", "value_text"))
  expect_true(nrow(joined$aggregate$results) > 0L)
})
