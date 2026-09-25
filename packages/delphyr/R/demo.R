#' Create a synthetic two-group development study
#' @param repo Development/test repository.
#' @param n Number of synthetic panel accounts.
#' @param item_count Number of trilingual rating items.
#' @param code Unique study code.
#' @return Manager and panel actors, study/consent ids and unapproved round.
#' @export
demo_study <- function(repo, n = 30L, item_count = 12L, code = paste0("DEMO-", substr(uid(), 1, 8))) {
  ensure(repo$environment %in% c("development", "test") && whole(n) && length(n) == 1 && n >= 2 && n <= 300 && whole(item_count) && length(item_count) == 1 && item_count >= 1 && item_count <= 150, "demo")
  manager <- demo_actor(repo, provision_demo_principal(repo, paste0("demo-manager-", code), TRUE))
  p <- demo_protocol()
  p$study$code <- code
  p$study$languages <- c("en", "fr", "de")
  study <- create_study(repo, manager, p, paste0(code, "-create"))$id
  consent <- publish_consent(repo, manager, study, "Synthetic demonstration only. Do not enter real study data. / D\u00e9monstration synth\u00e9tique uniquement. Ne saisissez pas de donn\u00e9es r\u00e9elles. / Nur synthetische Demonstration. Keine echten Studiendaten eingeben.", "en", "consent-version")$id
  panel <- lapply(seq_len(n), function(i) {
    actor <- demo_actor(repo, provision_demo_principal(repo, paste0("demo-", code, "-", i)))
    group <- unlist(p$panel$groups)[1 + (i > ceiling(n / 2))]
    add_panelist(repo, manager, study, actor$principal_id, group, paste0("panel-", i))
    actor
  })
  items <- expand.grid(item_code = sprintf("I%03d", seq_len(item_count)), locale = c("en", "fr", "de"), stringsAsFactors = FALSE)
  items$item_version <- 1L
  items$text <- paste(c(en = "Synthetic example item", fr = "Exemple synth\u00e9tique", de = "Synthetisches Beispielitem")[items$locale], items$item_code)
  items$dimension_code <- "relevance"
  items$scale_code <- "relevance_9"
  items$source_ref <- "DEMO-SRC-01"
  items$required <- TRUE
  items$display_order <- match(items$item_code, unique(items$item_code))
  deadline <- format(Sys.time() + 7 * 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  round <- prepare_round(repo, manager, study, items, consent, deadline, "round-1")
  list(manager = manager, panel = panel, study_id = study, consent_id = consent, items = items, round = round)
}
