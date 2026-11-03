report_precision_fixture <- function(profile) {
  seed <- demo_snapshot()
  protocol <- seed$protocol
  protocol$analysis$consensus$`in`$agree$proportion <- .7 + .Machine$double.eps / 2
  snapshot <- new_snapshot(seed$data,
    unique(seed$data[c("panelist_id", "group_code", "submitted")]), seed$items, protocol)
  analysis <- analyse_round(snapshot)
  data <- list(
    schema_version = "1.0", profile = profile,
    metadata = list(study_code = protocol$study$code, study_title = protocol$study$title,
      round_number = 1L, generated_at = "2026-10-31T00:00:00Z",
      scope = "synthetic development report; not a public-release profile"),
    protocol = unclass(snapshot$protocol), provenance = analysis$provenance,
    instrument = data.frame(item_code = "I001", item_version = 1L,
      dimension_code = "relevance", scale_code = "relevance_9", locale = "en",
      text = "Synthetic item", required = TRUE, display_order = 1L),
    results = analysis$results, denominators = analysis$denominators,
    missingness = analysis$missingness, distributions = analysis$distributions,
    decisions = data.frame(item_code = character(), disposition = character(), analysis_hash = character()),
    lineage = data.frame(parent_item = character(), parent_version = integer(),
      child_item = character(), child_version = integer(), relation = character()),
    dictionary = data.frame(field = "classification", definition = "Consensus rule outcome"),
    author_fields = documentation_topics()
  )
  if (profile == "study_report") {
    data$export_profile <- "research_pseudonymized"
    data$metadata$study_state <- "active"
    data$metadata$design <- protocol$study$design
    data$metadata$rationale <- protocol$study$rationale
    data$protocol_versions <- data.frame(version = 1L, hash = content_hash(protocol))
    data$rounds <- data.frame(round_number = 1L, state = "frozen")
    data$recruitment <- data.frame(group_code = "professionals", n_assigned = 10L)
    data$participation <- data.frame(round_number = 1L, n_assigned = 10L, n_submitted = 10L)
    data$comparisons <- data$comparability <- data$feedback <- data$qualitative <- data.frame()
    data$final_items <- data.frame(item_code = "I001", classification = analysis$decisions$classification,
      disposition = "not documented")
    data$documentation <- data$author_fields
    data$limitations <- "Synthetic fixture; no institutional approval or scientific interpretation."
  }
  data$content_hash <- content_hash(data)
  data <- structure(data, class = c("delphyr_report_data", "list"))
  overall <- analysis$results[analysis$results$stratum == "overall", ]
  list(data = data, counts = as.list(overall[c("n_valid", "n_agree", "n_disagree")]))
}

# Read the protocol that a report reader sees, rather than the separate JSON
# payload. Only the entities emitted by the trusted template need decoding.
report_displayed_protocol <- function(html) {
  blocks <- regmatches(html, gregexpr("(?s)<pre(?:\\s[^>]*)?>.*?</pre>", html, perl = TRUE))[[1]]
  blocks <- gsub("(?s)^<pre[^>]*>|</pre>$", "", blocks, perl = TRUE)
  entities <- list(c("&quot;", '"'), c("&#39;", "'"), c("&#96;", "`"),
    c("&#123;", "{"), c("&#125;", "}"), c("&lt;", "<"), c("&gt;", ">"), c("&amp;", "&"))
  for (entity in entities) blocks <- gsub(entity[1], entity[2], blocks, fixed = TRUE)
  parsed <- lapply(blocks, function(text) tryCatch(from_json(text), error = function(e) NULL))
  Filter(function(value) is.list(value) && !is.null(value$analysis$consensus), parsed)
}

for (profile in c("numeric_research_supplement", "study_report")) {
  local({
    report_profile <- profile
    test_that(paste(report_profile, "renders the exact consensus boundary"), {
      skip_if(!nzchar(Sys.which("quarto")), "Quarto executable not installed")
      skip_if_not_installed("rmarkdown")
      skip_if_not_installed("knitr")
      fixture <- report_precision_fixture(report_profile)
      data <- fixture$data
      threshold <- .7 + .Machine$double.eps / 2
      expect_true(validate_report_data(data))
      original <- classify_consensus(fixture$counts, data$protocol$analysis$consensus)$classification
      expect_identical(original, "no_consensus")

      transported <- from_json(json(unclass(data)))
      expect_identical(transported$protocol$analysis$consensus$`in`$agree$proportion, threshold)
      expect_identical(classify_consensus(fixture$counts,
        transported$protocol$analysis$consensus)$classification, original)

      directory <- tempfile("report-precision-")
      dir.create(directory)
      withr::defer(unlink(directory, recursive = TRUE))
      before <- getwd()
      output <- render_study_report(data, directory)
      expect_true(file.exists(output))
      expect_identical(getwd(), before)
      html <- paste(readLines(output, warn = FALSE), collapse = "\n")
      expect_true(grepl(format(threshold, digits = 17L), html, fixed = TRUE))
      displayed <- report_displayed_protocol(html)
      expect_length(displayed, 1L)
      expect_identical(displayed[[1]]$analysis$consensus$`in`$agree$proportion, threshold)
      expect_identical(classify_consensus(fixture$counts,
        displayed[[1]]$analysis$consensus)$classification, original)
      expect_true(grepl(data$provenance$result_hash, html, fixed = TRUE))
    })
  })
}
