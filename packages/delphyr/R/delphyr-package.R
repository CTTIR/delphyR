#' delphyr: Reproducible Round-Based Delphi Studies
#'
#' Validated study protocols, deterministic consensus classification and
#' longitudinal analysis of round-based Delphi studies, with transactional
#' study services backed by 'PostgreSQL'.
#'
#' @section Offline analysis:
#' Needs neither a database nor the application. [new_protocol()] and
#' [new_scale()] validate the declarative study configuration,
#' [new_snapshot()] freezes the submitted answers of a round under a content
#' hash, [analyse_round()] classifies consensus with explicit denominators
#' and missingness, [compare_rounds()] describes paired change between
#' comparable rounds and [prepare_feedback()] applies small-cell suppression.
#' [reproduce_export()] and [reproduce_study_export()] verify a research
#' export and recompute its analysis. `vignette("offline", package =
#' "delphyr")` is the worked example.
#'
#' @section Study services:
#' The services work on a 'PostgreSQL' database reached through
#' [connect_repository()] and prepared with [migrate_repository()]. Each
#' service checks identity, study membership, capability and state again and
#' signals a structured condition, see [del_abort()]. [demo_study()] creates
#' a synthetic study for development and tests.
#'
#' @section Scope:
#' The bundled examples use synthetic data only. Consensus thresholds in
#' [demo_protocol()] are examples, not recommendations. Production use
#' requires the documented security and operational acceptance gates.
#'
#' @keywords internal
"_PACKAGE"
