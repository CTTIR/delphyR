feedback_questionnaire <- function(version = 1L) {
  protocol <- list(
    study = list(timezone = "Europe/Berlin", default_language = "en"),
    instrument = list(
      dimensions = list(list(code = "relevance", scale = "relevance_9"), list(code = "comment", scale = "comment_text")),
      scales = list(
        relevance_9 = list(type = "ordinal_integer", values = 1:9, anchors = list(low = "not relevant", high = "extremely relevant"), missing_options = c("unable_to_judge", "abstained")),
        comment_text = list(type = "free_text", values = list(), missing_options = "unable_to_judge")
      )
    ),
    analysis = list(consensus = list(agree_values = 7:9)),
    feedback = list(own_previous_rating = TRUE, median = TRUE, iqr = TRUE)
  )
  list(
    protocol = protocol,
    round = list(id = "round-2", number = 2L, state = "open", in_time = TRUE, deadline = "2026-12-10T17:00:00Z", study_id = "study"),
    enrollment = list(id = "enrollment-2", state = "eligible"),
    consent = list(id = "consent", locale = "en", content = "Synthetic study information.", accepted = TRUE),
    receipt = data.frame(),
    items = data.frame(
      id = c("I001-relevance", "I001-comment"), item_code = "I001", item_version = version, dimension_code = c("relevance", "comment"),
      scale_code = c("relevance_9", "comment_text"), texts = '{"en":"Risks are presented as absolute numbers and with a picture."}', required = c(TRUE, FALSE),
      display_order = 1L, stringsAsFactors = FALSE
    ),
    responses = data.frame(round_item_id = character(), revision = integer(), status = character(), value_int = integer(), value_text = character(), stringsAsFactors = FALSE)
  )
}
# Released feedback of round 1 as get_feedback() returns it: columns in the
# order of the stored document, a suppressed free-text row, own answers.
released_feedback <- function(version = 1L, own = c("not_answered", "answered"), value = 8L, suppressed = FALSE) {
  results <- data.frame(
    q1 = c(NA, 7.75), q3 = c(NA, 9), iqr = c(NA, 1.25), median = c(NA, 8), n_agree = c(NA, 8L), n_valid = c(NA, 8L), p_agree = c(NA, 1),
    stratum = "overall", n_unable = c(NA, 0L), item_code = "I001", n_assigned = 8L, n_disagree = c(NA, 0L), suppressed = c(TRUE, FALSE),
    classification = c(NA, "consensus_in"), dimension_code = c("comment", "relevance"), item_version = version, n_submitted = c(NA, 8L), round_number = 1L,
    scale_code = c("comment_text", "relevance_9"), stringsAsFactors = FALSE
  )
  if (suppressed) {
    results[2, c("q1", "q3", "iqr", "median", "n_agree", "n_valid", "p_agree", "n_unable", "n_disagree", "n_submitted")] <- NA
    results$suppressed[2] <- TRUE
    results$classification[2] <- NA
  }
  distributions <- if (suppressed) list() else data.frame(item_code = "I001", item_version = version, dimension_code = "relevance", scale_code = "relevance_9", stratum = "overall", value = 1:9, n = c(0L, 0L, 0L, 0L, 0L, 0L, 2L, 3L, 3L))
  qualitative <- data.frame(text = "Several members ask for pictures.", kind = "summary", source_ref = "S1", stringsAsFactors = FALSE)
  qualitative$item_codes <- list("I001")
  list(
    id = "feedback", aggregate = list(results = results, distributions = distributions, policy = list(minimum_display_cell_n = 3L)),
    own = if (length(own)) {
      data.frame(item_code = "I001", item_version = version, dimension_code = c("comment", "relevance"), answer_status = own, value_integer = c(NA, if (identical(own[2], "answered")) value else NA), value_text = NA_character_, stringsAsFactors = FALSE)
    } else {
      data.frame(item_code = character(), item_version = integer(), dimension_code = character(), answer_status = character(), value_integer = integer(), value_text = character(), stringsAsFactors = FALSE)
    },
    comparability = data.frame(item_code = character(), dimension_code = character(), previous_version = integer(), current_version = integer(), comparable = logical()),
    qualitative = qualitative
  )
}
# The same feedback where the protocol releases group statistics: the panel
# of 8 and its two stakeholder groups of 5 and 3. With a minimum cell of 5
# the smaller group keeps back every result of the field, as
# prepare_feedback() does.
grouped_feedback <- function(minimum = 3L) {
  f <- released_feedback()
  r <- f$aggregate$results
  groups <- r[c(2L, 2L), , drop = FALSE]
  groups$stratum <- c("professionals", "public_contributors")
  groups$n_assigned <- c(5L, 3L)
  groups$n_submitted <- c(5L, 3L)
  groups$n_valid <- c(5L, 3L)
  groups$n_agree <- c(5L, 3L)
  groups$median <- c(8, 8)
  groups$q1 <- c(8, 7.5)
  groups$q3 <- c(9, 8.5)
  groups$iqr <- c(1, 1)
  groups$classification <- c("consensus_in", "insufficient_data")
  r <- rbind(r, groups)
  rownames(r) <- NULL
  d <- f$aggregate$distributions
  d <- rbind(d, transform(d, stratum = "professionals", n = c(0L, 0L, 0L, 0L, 0L, 0L, 1L, 2L, 2L)), transform(d, stratum = "public_contributors", n = c(0L, 0L, 0L, 0L, 0L, 0L, 1L, 1L, 1L)))
  if (minimum > 3L) {
    field <- r$dimension_code == "relevance"
    for (x in c("q1", "q3", "iqr", "median", "n_agree", "n_valid", "p_agree", "n_unable", "n_assigned", "n_disagree", "n_submitted")) r[[x]][field] <- NA
    r$suppressed[field] <- TRUE
    r$classification[field] <- NA
    d <- list()
  }
  f$aggregate <- list(results = r, distributions = d, policy = list(group_statistics = TRUE, minimum_display_cell_n = minimum, complementary_suppression = TRUE))
  f
}
title_of <- function(q, row, lang = "en", card = NULL) {
  html <- NULL
  shiny::testServer(delphyrApp:::rating_server, args = list(q = q, item = q$items[row, , drop = FALSE], lang = function() lang, call = function(...) stop("unused"), autosave_ms = 0, card = card), {
    html <<- as.character(output$title$html)
  })
  html
}
# The visible text of a fragment.
text_of <- function(html) trimws(gsub("[[:space:]]+", " ", gsub("<[^>]+>", " ", html)))

test_that("the panel's result of the previous round is stated in words beside the statement", {
  q <- feedback_questionnaire()
  q$feedback <- released_feedback()
  html <- title_of(q, 1L)
  text <- text_of(html)
  expect_match(text, "Round 1: 8 valid ratings from 8 members, median 8 (IQR 7.8\u20139), 100% rated 7 to 9.", fixed = TRUE)
  expect_match(text, "Classification: consensus for inclusion.", fixed = TRUE)
  expect_match(text, "Your rating: 8", fixed = TRUE)
  expect_match(text, "Moderated summary (not a quotation): Several members ask for pictures.", fixed = TRUE)
  expect_match(html, "class=\"del-feedback\"", fixed = TRUE)
  # The distribution, with the anchors at its ends, behind one line after the
  # member's own answer.
  expect_match(text, "Distribution of the 8 valid ratings", fixed = TRUE)
  expect_lt(regexpr("Your rating: 8", text, fixed = TRUE), regexpr("Distribution of the", text, fixed = TRUE))
  expect_match(html, "<caption>Valid ratings per value</caption>", fixed = TRUE)
  expect_match(text, "9 = extremely relevant 3", fixed = TRUE)
  expect_match(text, "1 = not relevant 0", fixed = TRUE)
  # Nothing technical reaches the participant.
  for (raw in c("q1", "n_agree", "stratum", "overall", "consensus_in", "NA", "I001", "answered")) expect_false(grepl(paste0("\\b", raw, "\\b"), text), info = raw)
  # Numbers in the interface language.
  expect_match(text_of(title_of(q, 1L, "de")), "Runde 1: 8 g\u00fcltige Bewertungen von 8 Mitgliedern, Median 8 (IQR 7,8\u20139), 100\u00a0% mit 7 bis 9 bewertet.", fixed = TRUE)
  expect_match(text_of(title_of(q, 1L, "fr")), "Tour 1 : 8 \u00e9valuations valides de 8 membres, m\u00e9diane 8 (EIQ 7,8\u20139), 100\u00a0% ont attribu\u00e9 une note de 7 \u00e0 9.", fixed = TRUE)
  # A comment carries no statistics.
  expect_false(grepl("valid ratings", title_of(q, 2L), fixed = TRUE))
})

test_that("a suppressed result states its reason and an own answer is put in words", {
  q <- feedback_questionnaire()
  q$feedback <- released_feedback(suppressed = TRUE)
  text <- text_of(title_of(q, 1L))
  expect_match(text, "Round 1: \u2014 (fewer than 3 valid ratings)", fixed = TRUE)
  expect_false(grepl("Distribution", text, fixed = TRUE))
  q$feedback <- released_feedback(own = c("not_answered", "unable_to_judge"))
  expect_match(text_of(title_of(q, 1L)), "You chose: Unable to judge", fixed = TRUE)
  expect_match(text_of(title_of(q, 1L, "de")), "Ihre Wahl: Kann ich nicht beurteilen", fixed = TRUE)
  q$feedback <- released_feedback(own = c("not_answered", "not_answered"))
  expect_match(text_of(title_of(q, 1L)), "You did not answer.", fixed = TRUE)
  # Without own answers in the feedback nothing is claimed about them.
  q$feedback <- released_feedback(own = character())
  text <- text_of(title_of(q, 1L))
  expect_false(grepl("Your rating|You chose|You did not", text))
})

test_that("released group statistics are shown for each stakeholder group", {
  q <- feedback_questionnaire()
  q$feedback <- grouped_feedback()
  html <- title_of(q, 1L)
  text <- text_of(html)
  expect_match(text, "Round 1: 8 valid ratings from 8 members, median 8 (IQR 7.8\u20139), 100% rated 7 to 9. Classification: consensus for inclusion. By stakeholder group:", fixed = TRUE)
  expect_match(text, "Professionals: 5 valid ratings from 5 members, median 8 (IQR 8\u20139), 100% rated 7 to 9. Classification: consensus for inclusion.", fixed = TRUE)
  expect_match(text, "Public contributors: 3 valid ratings from 3 members, median 8 (IQR 7.5\u20138.5), 100% rated 7 to 9. Classification: too few valid ratings to classify.", fixed = TRUE)
  expect_match(html, "<li>Professionals: ", fixed = TRUE)
  # The groups belong to the panel's result; the own answer follows them.
  expect_lt(regexpr("Public contributors: 3", text, fixed = TRUE), regexpr("Your rating: 8", text, fixed = TRUE))
  # The distribution has a column per group beside the total.
  expect_match(text, "Rating Total Professionals Public contributors", fixed = TRUE)
  expect_match(text, "8 3 2 1 9 = extremely relevant 3 2 1", fixed = TRUE)
  for (raw in c("public_contributors", "professionals", "stratum", "overall", "insufficient_data")) expect_false(grepl(raw, text, fixed = TRUE), info = raw)
  expect_match(text_of(title_of(q, 1L, "de")), "Nach Interessengruppe: Professionals: 5 g\u00fcltige Bewertungen von 5 Mitgliedern, Median 8 (IQR 8\u20139), 100\u00a0% mit 7 bis 9 bewertet. Einstufung: Konsens f\u00fcr Einschluss.", fixed = TRUE)
  expect_match(text_of(title_of(q, 1L, "fr")), "Par groupe de parties prenantes : Professionals : 5 \u00e9valuations valides de 5 membres, m\u00e9diane 8 (EIQ 8\u20139), 100\u00a0% ont attribu\u00e9 une note de 7 \u00e0 9. Classement : consensus pour l\u2019inclusion.", fixed = TRUE)
  expect_match(text_of(title_of(q, 1L, "fr")), "Note Total Professionals Public contributors", fixed = TRUE)
  # A protocol that shows no distribution shows none.
  q$protocol$feedback$distribution <- FALSE
  expect_false(grepl("Distribution", title_of(q, 1L), fixed = TRUE))
})

test_that("a small group keeps back the whole field and the reason says so", {
  q <- feedback_questionnaire()
  q$feedback <- grouped_feedback(minimum = 5L)
  text <- text_of(title_of(q, 1L))
  expect_match(text, "Round 1: \u2014 (fewer than 5 valid ratings in the panel or in one of its groups) Your rating: 8", fixed = TRUE)
  expect_false(grepl("Professionals|Public contributors|By stakeholder group|Distribution", text))
  expect_match(text_of(title_of(q, 1L, "de")), "Runde 1: \u2014 (weniger als 5 g\u00fcltige Bewertungen im Panel oder in einer seiner Gruppen)", fixed = TRUE)
  expect_match(text_of(title_of(q, 1L, "fr")), "Tour 1 : \u2014 (moins de 5 \u00e9valuations valides dans le panel ou dans l\u2019un de ses groupes)", fixed = TRUE)
  # A group kept back on its own is named with the same reason.
  q$feedback <- grouped_feedback()
  r <- q$feedback$aggregate$results
  r$suppressed[r$stratum == "public_contributors"] <- TRUE
  r$n_valid[r$stratum == "public_contributors"] <- NA
  q$feedback$aggregate$results <- r
  text <- text_of(title_of(q, 1L))
  expect_match(text, "Professionals: 5 valid ratings", fixed = TRUE)
  expect_match(text, "Public contributors: \u2014 (fewer than 3 valid ratings in the panel or in one of its groups)", fixed = TRUE)
  expect_match(text, "Rating Total Professionals 1 = not relevant 0 0", fixed = TRUE)
})

test_that("a revised statement says so whether or not the person answered the earlier wording", {
  q <- feedback_questionnaire(version = 2L)
  # Late entrants and protocols without own previous ratings have no own rows.
  q$feedback <- released_feedback(version = 1L, own = character())
  text <- text_of(title_of(q, 1L))
  expect_match(text, "The wording changed since round 1. Results of the earlier wording are not directly comparable.", fixed = TRUE)
  expect_match(text, "Round 1 (earlier wording): 8 valid ratings", fixed = TRUE)
  expect_match(title_of(q, 1L), "class=\"del-revision\"", fixed = TRUE)
  # The notice belongs to the statement, not to each of its fields.
  expect_identical(title_of(q, 2L, card = list(lead = FALSE, required = TRUE, several = FALSE)), "")
  q$feedback$comparability <- data.frame(item_code = "I001", dimension_code = "relevance", previous_version = 1L, current_version = 2L, comparable = TRUE)
  expect_match(text_of(title_of(q, 1L)), "The wording changed since round 1. The study team assessed both versions as comparable.", fixed = TRUE)
  # The earlier wording, where it is known, in a disclosure.
  q$previous_items <- data.frame(item_code = "I001", item_version = 1L, texts = '{"en":"Risks are presented as absolute numbers."}', stringsAsFactors = FALSE)
  html <- title_of(q, 1L)
  expect_match(html, "<summary>Earlier wording</summary>\\s*<p lang=\"en\">Risks are presented as absolute numbers.</p>")
})

test_that("the earlier wording is read from the member's own enrollment in the source round", {
  current <- feedback_questionnaire(version = 2L)
  earlier <- feedback_questionnaire(version = 1L)
  earlier$items$texts <- '{"en":"Risks are presented as absolute numbers."}'
  calls <- character()
  call <- function(name, ...) {
    calls <<- c(calls, paste(name, ...))
    switch(name,
      list_enrollments = data.frame(id = c("enrollment-1", "enrollment-2"), number = 1:2, state = c("submitted", "eligible"), round_state = c("released", "open"), stringsAsFactors = FALSE),
      get_questionnaire = if (identical(list(...)[[1]], "enrollment-1")) earlier else current,
      get_feedback = released_feedback(version = 1L),
      stop("unexpected call")
    )
  }
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "en", call = call, feedback_available = TRUE, feedback_download_available = TRUE), {
    session$setInputs(enrollment = "enrollment-2", load = 1)
    expect_true("get_questionnaire enrollment-1" %in% calls)
    expect_match(output[["slot_1-title"]]$html, "Risks are presented as absolute numbers.</p>", fixed = TRUE)
    # Where the feedback is, and the download, in the interface language.
    area <- text_of(output$round_feedback$html)
    expect_match(area, "Feedback from round 1 The results are shown with each statement.", fixed = TRUE)
    expect_match(area, "Download my feedback", fixed = TRUE)
  })
  # One term for feedback in German, in the heading as on the button.
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() "de", call = call, feedback_available = TRUE, feedback_download_available = TRUE), {
    session$setInputs(enrollment = "enrollment-2", load = 1)
    expect_match(text_of(output$round_feedback$html), "^Feedback aus Runde 1 .* Mein Feedback herunterladen$")
  })
})

test_that("texts of the questionnaire follow a change of the interface language", {
  q <- feedback_questionnaire()
  q$consent$recorded_at <- "2026-10-03 17:49:00+00"
  language <- shiny::reactiveVal("en")
  call <- function(name, ...) {
    switch(name,
      list_enrollments = data.frame(id = "enrollment-2", number = 2L, state = "eligible", round_state = "open", stringsAsFactors = FALSE),
      get_questionnaire = q,
      get_feedback = released_feedback(),
      stop("unexpected call")
    )
  }
  shiny::testServer(delphyrApp:::panel_server, args = list(study = function() "study", lang = function() language(), call = call, feedback_available = TRUE, feedback_download_available = TRUE), {
    session$setInputs(enrollment = "enrollment-2", load = 1)
    expect_match(text_of(output$consent_area$html), "Consent recorded on 3 Oct 2026, 19:49 (Europe/Berlin, UTC+2).", fixed = TRUE)
    language("de")
    session$flushReact()
    expect_match(text_of(output$consent_area$html), "Einwilligung erteilt am 3. Okt. 2026, 19:49 (Europe/Berlin, UTC+2).", fixed = TRUE)
    expect_match(text_of(output$round_feedback$html), "Mein Feedback herunterladen", fixed = TRUE)
    expect_identical(output$deadline, "Abgabe bis: 10. Dez. 2026, 18:00 (Europe/Berlin, UTC+1)")
    expect_identical(output$content_note, "Studientexte, Skalenanker und Einwilligung bleiben in ihrer genehmigten Sprache.")
    # Notes are paragraphs of their own style, not blocks after an empty one.
    expect_match(output$questionnaire$html, "<p class=\"del-note\">\\s*<span id=\"proxy1-save_note\" class=\"shiny-text-output\"></span>")
  })
})
