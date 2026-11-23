#' delphyrApp: Trilingual 'shiny' Workflows for Delphi Studies
#'
#' An English, French and German 'shiny' interface for round-based Delphi
#' studies. It uses the transactional services of 'delphyr' and adds no
#' authority of its own: every action is checked again by the service that
#' performs it.
#'
#' [run_app()] builds the application for a trusted server identity. Panel
#' members read the study information, record consent, save responses with
#' explicit receipts and submit a round. Study managers prepare and advance
#' rounds, release reviewed feedback and request exports; editors review
#' qualitative sources; coordinators approve campaigns.
#'
#' The bundled examples use synthetic studies only. Production
#' authentication and deployment remain acceptance gates.
#' `vignette("synthetic-workflow", package = "delphyrApp")` describes the
#' workflows.
#'
#' @keywords internal
"_PACKAGE"
