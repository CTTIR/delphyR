#' Prepare an authorized aggregate report and numeric export supplement
#' @param repo Repository.
#' @param actor Actor with current export capability.
#' @param snapshot_id Immutable numeric snapshot UUID.
#' @return A delphyr_report_data with allowlisted tables and a content hash.
#' @export
prepare_report_data <- function(repo, actor, snapshot_id) {
  transaction(repo, function() {
    valid_id(snapshot_id)
    x <- one(query(repo, "SELECT study_id,round_id,content::text FROM research.snapshots WHERE id=$1", snapshot_id))
    authorize(repo, actor, x$study_id, "export")
    snapshot <- read_snapshot(x$content)
    ensure(!any(vapply(config_scales(snapshot$protocol), function(s) s$type == "free_text", logical(1))), "report.free_text_review_required", "DEL_FORBIDDEN")
    analysis <- analyse_round(snapshot)
    instrument <- query(repo, "SELECT i.item_code,i.item_version,i.dimension_code,i.scale_code,t.key AS locale,t.value AS text,i.required,i.display_order FROM research.round_items i CROSS JOIN LATERAL jsonb_each_text(i.texts) t WHERE i.study_id=$1 AND i.round_id=$2 ORDER BY i.display_order,i.item_code,i.dimension_code,t.key", x$study_id, x$round_id)
    decisions <- query(repo, "SELECT d.item_code,d.disposition,a.hash AS analysis_hash FROM research.decisions d JOIN research.analyses a ON a.id=d.analysis_id WHERE d.study_id=$1 AND a.snapshot_id=$2 ORDER BY d.item_code,d.disposition,a.hash", x$study_id, snapshot_id)
    lineage <- query(repo, "SELECT p.item_code AS parent_item,p.item_version AS parent_version,c.item_code AS child_item,c.item_version AS child_version,ev.relation FROM research.item_lineage_edges e JOIN research.item_lineage_events ev ON ev.study_id=e.study_id AND ev.id=e.event_id JOIN research.item_provenance_versions p ON p.study_id=e.study_id AND p.id=e.parent_id JOIN research.item_provenance_versions c ON c.study_id=e.study_id AND c.id=e.child_id WHERE e.study_id=$1 ORDER BY p.item_code,p.item_version,c.item_code,c.item_version,ev.relation", x$study_id)
    # Provenance follows exact semantic versions, not only a reused item code.
    frozen_keys <- paste(snapshot$items$item_code, snapshot$items$item_version, sep = "\034")
    parent_keys <- paste(lineage$parent_item, lineage$parent_version, sep = "\034")
    child_keys <- paste(lineage$child_item, lineage$child_version, sep = "\034")
    lineage <- lineage[parent_keys %in% frozen_keys | child_keys %in% frozen_keys, , drop = FALSE]
    dictionary <- data.frame(
      field = c("n_assigned", "n_submitted", "n_valid", "n_agree", "n_disagree", "p_agree", "classification", "stratum", "item_version", "snapshot_hash", "rules_hash", "result_hash"),
      definition = c("Assigned panel members in the frozen round", "Submitted response sets", "Valid numeric ratings; denominator of agreement and disagreement", "Ratings in the protocol agreement categories", "Ratings in the protocol disagreement categories", "Unrounded n_agree / n_valid", "Rule outcome, separate from human item decisions", "Overall or protocol-defined stakeholder group", "Frozen instrument item version", "Canonical frozen snapshot content hash", "Canonical analysis rule hash", "Canonical result content hash"), stringsAsFactors = FALSE
    )
    missing <- data.frame(topic = c("Authors and responsibilities", "Funding", "Conflicts of interest", "Institutional approval", "Methodological interpretation", "Protocol deviations", "ACCORD/CREDES review"), status = rep("not documented", 7), stringsAsFactors = FALSE)
    data <- list(
      schema_version = "1.0", profile = "numeric_research_supplement",
      metadata = list(
        study_id = x$study_id, snapshot_id = snapshot_id, round_number = snapshot$round_number,
        study_title = snapshot$protocol$study$title, generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
        scope = "synthetic development report; not a public-release profile",
        editorial_scope = "decisions and lineage observed at export time; not frozen at snapshot time"
      ),
      protocol = unclass(snapshot$protocol), provenance = analysis$provenance,
      instrument = instrument, results = analysis$results, decisions = decisions, lineage = lineage,
      denominators = analysis$denominators, missingness = analysis$missingness, distributions = analysis$distributions,
      dictionary = dictionary, author_fields = missing
    )
    data$content_hash <- content_hash(data)
    structure(data, class = c("delphyr_report_data", "list"))
  })
}
validate_report_data <- function(data) {
  ensure(inherits(data, "delphyr_report_data"), "report.data")
  value <- unclass(data)
  h <- value$content_hash
  value$content_hash <- NULL
  ensure(identical(content_hash(value), h), "report.hash")
  invisible(TRUE)
}
#' Write allowlisted numeric report supplements to a private staging directory
#' @param data Report data returned by prepare_report_data().
#' @param output_dir Existing private staging directory under caller control.
#' @return Written basenames, to include in the enclosing export manifest.
#' @export
write_report_data <- function(data, output_dir) {
  validate_report_data(data)
  ensure(scalar_text(output_dir) && dir.exists(output_dir), "report.output_dir")
  files <- c("report-data.json", "data_dictionary.csv", "round_items.csv", "item_decisions.csv", "item_lineage.csv", "missingness.csv", "denominators.csv", "distributions.csv", "author_fields.csv")
  ensure(!any(file.exists(file.path(output_dir, files))), "report.exists", "DEL_CONFLICT")
  writeLines(json(unclass(data)), file.path(output_dir, files[1]), useBytes = TRUE)
  tables <- list(data$dictionary, data$instrument, data$decisions, data$lineage, data$missingness, data$denominators, data$distributions, data$author_fields)
  for (i in seq_along(tables)) utils::write.csv(safe_csv(tables[[i]]), file.path(output_dir, files[i + 1]), row.names = FALSE, na = "", fileEncoding = "UTF-8")
  invisible(files)
}
#' Render a trusted packaged Quarto report without executing study text
#' @param data Report data returned by prepare_report_data().
#' @param output_dir Existing private output directory. report.html must not exist.
#' @param timeout Render timeout in seconds, from 1 to 300.
#' @return Path of the rendered report.html; DEL_DEPENDENCY if Quarto is absent.
#' @export
render_study_report <- function(data, output_dir, timeout = 60L) {
  validate_report_data(data)
  ensure(scalar_text(output_dir) && dir.exists(output_dir), "report.output_dir")
  ensure(whole(timeout) && length(timeout) == 1 && timeout >= 1 && timeout <= 300, "report.timeout")
  ensure(!file.exists(file.path(output_dir, "report.html")), "report.exists", "DEL_CONFLICT")
  quarto <- Sys.which("quarto")
  ensure(nzchar(quarto) && requireNamespace("rmarkdown", quietly = TRUE) && requireNamespace("knitr", quietly = TRUE), "report.quarto_runtime", "DEL_DEPENDENCY")
  template <- system.file("reports", "study.qmd", package = "delphyr")
  ensure(nzchar(template) && file.exists(template), "report.template", "DEL_RENDER")
  output_dir <- normalizePath(output_dir, mustWork = TRUE)
  work <- tempfile("delphyr-report-")
  dir.create(work, mode = "0700")
  previous_dir <- getwd()
  on.exit(
    {
      setwd(previous_dir)
      unlink(work, recursive = TRUE)
    },
    add = TRUE
  )
  ensure(file.copy(template, file.path(work, "study.qmd")), "report.template_copy", "DEL_STORAGE")
  writeLines(json(unclass(data)), file.path(work, "report-data.json"), useBytes = TRUE)
  log <- file.path(work, "render.log")
  setwd(work)
  # Command arguments are fixed or shell-quoted local paths, never study text.
  status <- suppressWarnings(system2(quarto,
    args = c(
      "render", shQuote(file.path(work, "study.qmd")),
      "--to", "html", "--output", "report.html", "--quiet"
    ), stdout = log, stderr = log, timeout = timeout,
    env = paste0("R_LIBS=", shQuote(paste(.libPaths(), collapse = .Platform$path.sep)))
  ))
  ensure(identical(status, 0L) && file.exists(file.path(work, "report.html")), "report.render_failed", "DEL_RENDER")
  destination <- file.path(output_dir, "report.html")
  ensure(file.copy(file.path(work, "report.html"), destination, overwrite = FALSE), "report.copy", "DEL_STORAGE")
  destination
}
