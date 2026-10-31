precision_protocol <- function(value) {
  p <- delphyr::demo_protocol()
  p$analysis$consensus$`in`$agree$proportion <- value
  delphyr::new_protocol(p)
}
precision_upload <- function(protocol, env = parent.frame()) {
  path <- tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(unclass(protocol), auto_unbox = TRUE, null = "null", digits = 17L), path)
  withr::defer(unlink(path), envir = env)
  data.frame(name = "protocol.json", size = file.info(path)$size, datapath = path, type = "application/json")
}

test_that("complete protocol previews retain the exact threshold used for analysis", {
  threshold <- 0.7 + .Machine$double.eps / 2
  p <- precision_protocol(threshold)
  shown <- jsonlite::fromJSON(as.character(delphyrApp:::protocol_json(p)), simplifyVector = FALSE)
  expect_identical(shown$analysis$consensus$`in`$agree$proportion, threshold)
  counts <- list(n_valid = 10, n_agree = 7, n_disagree = 0)
  expect_identical(delphyr::classify_consensus(counts, shown$analysis$consensus)$classification, "no_consensus")
})

test_that("protocol changes reveal adjacent thresholds and summaries do not round them away", {
  previous <- precision_protocol(0.7)
  proposed <- precision_protocol(0.7 + .Machine$double.eps / 2)
  changes <- delphyrApp:::protocol_changes(previous, proposed)
  expect_identical(changes$field, "analysis.consensus.in.agree.proportion")
  if (nrow(changes) == 1L) {
    expect_identical(jsonlite::fromJSON(changes$previous), 0.7)
    expect_identical(jsonlite::fromJSON(changes$proposed), proposed$analysis$consensus$`in`$agree$proportion)
  }
  for (lang in c("en", "de", "fr")) {
    before <- delphyrApp:::protocol_summary(previous, lang)[8L, 2L]
    after <- delphyrApp:::protocol_summary(proposed, lang)[8L, 2L]
    expect_false(identical(before, after))
    expect_match(after, if (lang == "de") "Anteil 0,70000000000000007" else if (lang == "fr") "proportion 0,70000000000000007" else "proportion 0.70000000000000007", fixed = TRUE)
  }
  summary <- delphyrApp:::protocol_summary(precision_protocol(0.7012345), "en")
  shown <- sub(".*\\(proportion ([0-9.]+)\\).*", "\\1", summary[8L, 2L])
  expect_identical(as.numeric(shown), 0.7012345)
})

test_that("legacy protocols are compared by exact content and close amendments require fresh approval", {
  previous <- precision_protocol(0.7)
  proposed <- precision_protocol(0.7 + .Machine$double.eps / 2)
  legacy_hash <- delphyr::content_hash(previous, version = "1")
  file <- precision_upload(previous)
  changed_file <- precision_upload(proposed)
  saved <- list()
  call <- function(name, ...) switch(name,
    get_capabilities = "manage",
    list_protocol_versions = data.frame(
      id = "original", version = 1L, hash = legacy_hash,
      config = as.character(jsonlite::toJSON(unclass(previous), auto_unbox = TRUE, null = "null", digits = NA)),
      reason = NA_character_
    ),
    amend_protocol = {
      saved[[length(saved) + 1L]] <<- list(...)
      list(version = 2L)
    },
    stop("Unexpected service")
  )
  services <- stats::setNames(rep(list(function(...) NULL), 3L), c("get_capabilities", "list_protocol_versions", "amend_protocol"))
  shiny::testServer(delphyrApp:::protocols_server, args = list(study = function() "study", lang = function() "en", call = call, services = services), {
    session$flushReact()
    session$setInputs(file = file, validate = 1)
    expect_null(candidate())
    expect_match(output$status, "identical to the current version", fixed = TRUE)
    session$setInputs(file = changed_file, validate = 2)
    expect_false(is.null(candidate()))
    expect_identical(candidate()$expected_hash, legacy_hash)
    preview <- jsonlite::fromJSON(output$preview, simplifyVector = FALSE)
    expect_identical(preview$analysis$consensus$`in`$agree$proportion, proposed$analysis$consensus$`in`$agree$proportion)
    expect_match(output$changes, "0.70000000000000007", fixed = TRUE)
    inputs <- stats::setNames(list("Exact threshold reviewed", TRUE), paste0(c("reason_", "confirm_"), form()))
    do.call(session$setInputs, c(inputs, list(approve = 1)))
    expect_length(saved, 1L)
    expect_identical(saved[[1]][[2]]$analysis$consensus$`in`$agree$proportion, proposed$analysis$consensus$`in`$agree$proportion)
    expect_identical(saved[[1]][[3]], legacy_hash)
    # Replacing the on-disk upload with a nearby value after its preview must
    # invalidate approval even when a legacy hash would have been identical.
    session$setInputs(file = changed_file, validate = 3)
    writeLines(jsonlite::toJSON(unclass(previous), auto_unbox = TRUE, null = "null", digits = 17L), changed_file$datapath)
    inputs <- stats::setNames(list("Stale preview", TRUE), paste0(c("reason_", "confirm_"), form()))
    do.call(session$setInputs, c(inputs, list(approve = 2)))
    expect_length(saved, 1L)
    expect_match(output$status, "file changed after it was validated", fixed = TRUE)
  })
})
