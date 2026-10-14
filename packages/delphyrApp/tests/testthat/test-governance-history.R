squish <- function(x) gsub("\\s+", " ", x)
history_services <- function(names) stats::setNames(rep(list(function(...) NULL), length(names)), names)
history_events <- function(n = 3L) {
  data.frame(
    occurred_at = sprintf("2026-10-02T%02d:00:00.000Z", 23L - seq_len(n) %% 24L),
    action = rep("save", n), detail = NA_character_, object_ref = sprintf("revision-%03d", seq_len(n)), reason = NA_character_,
    actor_kind = "panel", actor_ref = NA_character_, stringsAsFactors = FALSE
  )
}

test_that("the filter for requested exports covers round exports and every study export profile", {
  expect_null(audit_filter(NULL))
  expect_identical(audit_filter(c("save", "submit")), c("save", "submit"))
  profiles <- paste0("request_export:", c("research_pseudonymized", "study_summary", "audit_restricted", "contacts_restricted"))
  expect_setequal(audit_filter(c("request_export", "save")), c("request_export", "save", profiles))
  # Every code the filter asks for is shown under the label of the filter entry.
  expect_true(all(audit_action_label(audit_filter("request_export"), "en") == "Export requested"))
  requests <- list()
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "audit",
      list_audit_events = {
        requests[[length(requests) + 1L]] <<- list(...)
        history_events(1L)
      },
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::audit_server, args = list(study = function() "study", lang = function() "en", call = call, services = history_services(c("get_capabilities", "list_audit_events"))), {
    session$flushReact()
    session$setInputs(actions = "request_export", load = 1)
    expect_setequal(requests[[1]]$actions, c("request_export", profiles))
  })
})

test_that("history names staff, objects and details in words for study management", {
  events <- data.frame(
    occurred_at = c("2026-10-03T17:51:14.241Z", "2026-10-03T17:50:00.000Z", "2026-10-03T17:49:59.000Z", "2026-10-03T17:49:58.000Z", "2026-10-03T17:49:57.000Z", "2026-10-03T17:49:56.000Z", "2026-10-03T17:49:55.000Z", "2026-10-03T17:49:54.000Z", "2026-10-03T17:49:53.000Z"),
    action = c("transition_round", "message_sink_recorded", "decision", "item_comparability", "capability", "feedback_draft", "qualitative_import", "freeze", "publish_consent"),
    detail = c("open", "database_sink", "I001 rerate", "I007 relevance v1->v2 not comparable", "analyse granted", "1 released editorial versions", NA, NA, "en"),
    object_ref = c("round-2", "message-1", "decision-1", "comparability-1", "membership-1", "feedback-1", "snapshot-1", "snapshot-1", "consent-1"),
    reason = c("Instrument reviewed", NA, "Decision after round 1", "Adding a picture changes what is rated", "Reviews the analysis", NA, NA, NA, NA),
    actor_kind = c("staff", "worker", "staff", "staff", "staff", "staff", "staff", "staff", "staff"),
    actor_ref = c("lead-id", "lead-id", "lead-id", "lead-id", "lead-id", "lead-id", "lead-id", "former-id-0000", "lead-id"), stringsAsFactors = FALSE
  )
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "manage",
      list_audit_events = events,
      list_study_staff = data.frame(principal_id = "lead-id", issuer = "urn:delphyr:demo", subject = "demo-lead", active = TRUE, granted = "manage", revoked = ""),
      list_rounds = data.frame(id = c("round-1", "round-2"), number = 1:2, state = c("closed", "open"), snapshot_id = c("snapshot-1", NA), analysis_id = c("analysis-1", NA)),
      list_protocol_versions = data.frame(id = "protocol-1", version = 1L, config = "{}"),
      get_study_setup = list(consent_versions = data.frame(id = "consent-1", locale = "en", content = "Synthetic", hash = "h")),
      stop("Unexpected service")
    )
  }
  language <- shiny::reactiveVal("en")
  services <- history_services(c("get_capabilities", "list_audit_events", "list_study_staff", "list_rounds", "list_protocol_versions", "get_study_setup"))
  shiny::testServer(delphyrApp:::audit_server, args = list(study = function() "study", lang = function() language(), call = call, services = services), {
    session$flushReact()
    session$setInputs(load = 1)
    html <- squish(output$events$html)
    # Staff by the name the team table shows; the account reference stays in the title.
    expect_match(html, "by <span title=\"lead-id\">demo-lead</span>", fixed = TRUE)
    expect_match(html, "by the background worker, approved by <span title=\"lead-id\">demo-lead</span>", fixed = TRUE)
    # An account outside the team is shown by its short reference.
    expect_match(html, "the study team account <span class=\"del-ref\" title=\"former-id-0000\">former-i</span>", fixed = TRUE)
    # Objects by round, round data and version; other objects by short reference.
    expect_match(html, "Round 2", fixed = TRUE)
    expect_match(html, "Frozen data of round 1", fixed = TRUE)
    expect_match(html, "Study information, version 1 (English)", fixed = TRUE)
    expect_match(html, "title=\"decision-1\">decision<", fixed = TRUE)
    # Details in the words of the other screens.
    expect_match(html, "Round state changed</strong> \u00b7 Open", fixed = TRUE)
    expect_match(html, "Local test receipt, no email", fixed = TRUE)
    expect_match(html, "I001 \u00b7 Rate again", fixed = TRUE)
    expect_match(html, "I007 \u00b7 Relevance \u00b7 Version 1 \u2192 2 \u00b7 Not comparable", fixed = TRUE)
    expect_match(html, "Analysis \u00b7 granted", fixed = TRUE)
    expect_match(html, "1 released editorial version </div>", fixed = TRUE)
    expect_match(html, "Free-text contributions imported as sources", fixed = TRUE)
    # Times without seconds, the date above the time of day.
    expect_match(html, "3 Oct 2026 <br/> 17:51", fixed = TRUE)
    expect_false(grepl("17:51:14", html, fixed = TRUE))
    for (code in c("rerate", "analyse granted", "database_sink", "->", "lead-id</span>")) expect_false(grepl(paste0(">", code), html, fixed = TRUE))
    language("fr")
    session$flushReact()
    html <- squish(output$events$html)
    expect_match(html, "Ouvert", fixed = TRUE)
    expect_match(html, "\u00c9valuer de nouveau", fixed = TRUE)
    expect_match(html, "Justification : Instrument reviewed", fixed = TRUE)
    language("de")
    session$flushReact()
    html <- squish(output$events$html)
    expect_match(html, "1 freigegebene redaktionelle Fassung </div>", fixed = TRUE)
    expect_match(html, "3. Okt. 2026 <br/> 17:51", fixed = TRUE)
  })
  expect_identical(audit_detail_label(c("feedback_draft", "feedback_draft"), c("3 released editorial versions", "0 released editorial versions"), "fr"), c("3 versions \u00e9ditoriales publi\u00e9es", "0 version \u00e9ditoriale publi\u00e9e"))
  expect_identical(audit_detail_label(c("transition_round", "unknown_action", "request_export:x"), c("cancelled", "raw value", "contacts_restricted"), "en"), c("Withdrawn (never opened)", "raw value", "Contact data"))
})

test_that("an audit reader without study management sees references, not team names", {
  calls <- character()
  call <- function(name, ...) {
    calls <<- c(calls, name)
    switch(name,
      get_capabilities = "audit",
      list_audit_events = data.frame(occurred_at = "2026-10-03T17:00:00.000Z", action = "transition_round", detail = "open", object_ref = "round-id-1", reason = NA, actor_kind = "staff", actor_ref = "lead-id-123", stringsAsFactors = FALSE),
      stop("must not be called")
    )
  }
  services <- history_services(c("get_capabilities", "list_audit_events", "list_study_staff", "list_rounds"))
  shiny::testServer(delphyrApp:::audit_server, args = list(study = function() "study", lang = function() "en", call = call, services = services), {
    session$flushReact()
    session$setInputs(load = 1)
    html <- squish(output$events$html)
    expect_match(html, "the study team account <span class=\"del-ref\" title=\"lead-id-123\">lead-id-</span>", fixed = TRUE)
    expect_match(html, "Object <span class=\"del-ref\" title=\"round-id-1\">round-id</span>", fixed = TRUE)
    expect_false(any(c("list_study_staff", "list_rounds") %in% calls))
  })
})

test_that("the history says when older events exist and reads them on request", {
  requests <- list()
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "audit",
      list_audit_events = {
        args <- list(...)
        requests[[length(requests) + 1L]] <<- args
        history_events(min(args$limit, 150L))
      },
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::audit_server, args = list(study = function() "study", lang = function() "en", call = call, services = history_services(c("get_capabilities", "list_audit_events"))), {
    session$flushReact()
    session$setInputs(actions = "save", load = 1)
    expect_true(older())
    expect_identical(nrow(events()), 100L)
    html <- squish(output$events$html)
    expect_match(html, "Showing the latest 100 events. Older events exist.", fixed = TRUE)
    # The count stands above the list.
    expect_lt(regexpr("Showing the latest", html, fixed = TRUE), regexpr("<table", html, fixed = TRUE))
    expect_match(html, "Show older events", fixed = TRUE)
    session$setInputs(actions = character(), older = 1)
    # Older events are read with the filter of the list they extend.
    expect_identical(requests[[2]]$actions, "save")
    expect_identical(requests[[2]]$limit, 201L)
    expect_false(older())
    expect_identical(nrow(events()), 150L)
    html <- squish(output$events$html)
    expect_match(html, "Showing all 150 events.", fixed = TRUE)
    expect_false(grepl("Show older events", html, fixed = TRUE))
  })
  expect_identical(audit_count_text(1L, FALSE, "en"), "Showing 1 event.")
  expect_identical(audit_count_text(1L, TRUE, "de"), "Das neueste Ereignis wird angezeigt. Es gibt \u00e4ltere Ereignisse.")
  expect_identical(audit_count_text(5000L, TRUE, "fr"), "Affichage des 5000 \u00e9v\u00e9nements les plus r\u00e9cents. Il existe des \u00e9v\u00e9nements plus anciens.")
})

test_that("the history filter and its button are laid out as one group", {
  call <- function(name, ...) if (name == "get_capabilities") "audit" else stop("Unexpected service")
  shiny::testServer(delphyrApp:::audit_server, args = list(study = function() "study", lang = function() "en", call = call, services = history_services(c("get_capabilities", "list_audit_events"))), {
    session$flushReact()
    html <- output$body$html
    expect_match(html, "\"placeholder\":\"All actions\"", fixed = TRUE)
    expect_match(html, "<div class=\"del-actions\">\\s*<button[^>]*id=\"[^\"]*load\"")
    expect_false(grepl("limit", html, fixed = TRUE))
  })
})
