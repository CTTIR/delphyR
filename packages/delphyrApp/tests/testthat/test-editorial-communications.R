editorial_services <- function() {
  stats::setNames(rep(list(function(...) NULL), 10), c(
    "get_capabilities", "get_qualitative_provenance", "list_qualitative_reviews",
    "record_qualitative_source", "redact_qualitative_source", "release_qualitative_edit",
    "create_qualitative_theme", "code_qualitative_source", "link_item_source", "record_item_lineage"
  ))
}

test_that("restricted originals are not fetched for a manager-only reviewer", {
  originals <- FALSE
  released <- list()
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "manage",
      get_qualitative_provenance = {
        originals <<- TRUE
        stop("Forbidden originals")
      },
      list_qualitative_reviews = data.frame(id = "edit", source_ref = "source-ref", kind = "summary", redacted_text = "Reviewed synthetic summary", reason = "Remove identifiers", hash = "exact-edit", released = FALSE, can_review = TRUE),
      release_qualitative_edit = {
        released[[length(released) + 1L]] <<- list(...)
      },
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::editorial_server, args = list(study = function() "study", lang = function() "en", call = call, services = editorial_services()), {
    session$flushReact()
    expect_false(originals)
    expect_false(grepl("Original text", output$body$html, fixed = TRUE))
    session$setInputs(review_edit = "edit", preview_review = 1)
    expect_match(output$review_preview$html, "Summary (not a quotation)", fixed = TRUE)
    session$setInputs(review_reason = "Faithful and preserves dissent", review_confirm = FALSE, release = 1)
    expect_length(released, 0L)
    session$setInputs(review_confirm = TRUE, release = 2)
    expect_length(released, 1L)
    expect_equal(released[[1]][[3]], "exact-edit")
    session$setInputs(release = 3)
    expect_length(released, 1L)
  })
})

test_that("lineage parser rejects extra columns and preserves all split targets", {
  expect_equal(delphyrApp:::parse_lineage_rows("I002,1\nI003,2")$item_code, c("I002", "I003"))
  expect_error(delphyrApp:::parse_lineage_rows("I001,1,extra"), "pair")
  expect_error(delphyrApp:::parse_lineage_rows("I001,1.5"), "Invalid")
  expect_error(delphyrApp:::parse_lineage_rows("I001,1\nI001,2"), "Invalid")
})

campaign_services <- function() {
  stats::setNames(rep(list(function(...) NULL), 7), c(
    "get_capabilities", "list_campaign_rounds", "list_campaign_enrollments",
    "prepare_campaign", "preview_campaign", "release_campaign", "cancel_campaign"
  ))
}

test_that("campaign approval is bound to the exact text and selected pseudonyms", {
  released <- list()
  prepared <- list()
  approved <- FALSE
  preview <- function() {
    list(
      id = "campaign", subject = "Synthetic invitation", body = "Synthetic body", hash = "campaign-hash", released = approved, cancelled = FALSE,
      recipients = data.frame(enrollment_id = "enrollment", pseudonym = "study-pseudonym", delivery_state = "draft")
    )
  }
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "coordinate",
      list_campaign_rounds = data.frame(id = "round", number = 1L, state = "draft"),
      list_campaign_enrollments = data.frame(enrollment_id = "enrollment", pseudonym = "study-pseudonym", state = "eligible"),
      prepare_campaign = {
        prepared <<- list(...)
        list(id = "campaign", hash = "campaign-hash")
      },
      preview_campaign = preview(),
      release_campaign = {
        released[[length(released) + 1L]] <<- list(...)
        approved <<- TRUE
      },
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::communications_server, args = list(study = function() "study", lang = function() "en", call = call, services = campaign_services()), {
    session$setInputs(round = "round", enrollments = "enrollment", kind = "invitation", subject = "Synthetic invitation", message = "Synthetic body", locale = "en", version = 1)
    session$setInputs(prepare = 1)
    expect_equal(prepared[[2]], "enrollment")
    expect_match(output$recipient_preview, "study-pseudonym", fixed = TRUE)
    expect_false(grepl("enrollment", output$recipient_preview, fixed = TRUE))
    session$setInputs(confirm = TRUE, reason = "Exact scope reviewed", subject = "Changed after preview", release = 1)
    expect_length(released, 0L)
    session$setInputs(subject = "Synthetic invitation", release = 2)
    expect_length(released, 1L)
    expect_equal(released[[1]][[2]], "campaign-hash")
    expect_true(candidate()$released)
  })
})

test_that("coordinate UI is absent without the coordinate capability", {
  call <- function(name, ...) {
    if (name == "get_capabilities") {
      return("panel")
    }
    stop("Unauthorized read")
  }
  shiny::testServer(delphyrApp:::communications_server, args = list(study = function() "study", lang = function() "en", call = call, services = campaign_services()), {
    session$flushReact()
    expect_false(allowed())
  })
})

test_that("an editor can start from empty provenance tables", {
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "edit",
      get_qualitative_provenance = list(
        sources = data.frame(id = character(), source_ref = character()),
        themes = data.frame(id = character(), label = character(), version = integer())
      ),
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::editorial_server, args = list(study = function() "study", lang = function() "en", call = call, services = editorial_services()), {
    session$flushReact()
    expect_match(output$body$html, "Preserve original", fixed = TRUE)
    expect_false(grepl("Independent review", output$body$html, fixed = TRUE))
  })
})
