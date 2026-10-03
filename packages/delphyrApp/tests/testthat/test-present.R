test_that("moments are read from every form the database and services return", {
  expected <- as.POSIXct("2026-10-08 17:49:00", tz = "UTC")
  for (x in list(
    expected, as.numeric(expected), "2026-10-08T17:49:00Z", "2026-10-08 17:49:00+00", "2026-10-08 19:49:00+02",
    "2026-10-08T19:49:00+02:00", "2026-10-08T19:49:00.123456+0200", "2026-10-08 17:49", "2026-10-08T17:49:00.000Z"
  )) {
    expect_equal(as.numeric(delphyrApp:::parse_moment(x)), as.numeric(expected), info = format(x))
  }
  expect_equal(as.numeric(delphyrApp:::parse_moment("2026-10-08")), as.numeric(as.POSIXct("2026-10-08", tz = "UTC")))
  expect_true(all(is.na(delphyrApp:::parse_moment(c("now", "", NA, "2026-13-45 99:99")))))
  expect_length(delphyrApp:::parse_moment(NULL), 0L)
})

test_that("a moment shows date, time, zone and offset in the interface language", {
  x <- "2026-10-08T17:49:00Z"
  expect_identical(delphyrApp:::format_moment(x, "Europe/Berlin", "en"), "8 Oct 2026, 19:49 (Europe/Berlin, UTC+2)")
  expect_identical(delphyrApp:::format_moment(x, "Europe/Berlin", "fr"), "8 oct. 2026, 19:49 (Europe/Berlin, UTC+2)")
  expect_identical(delphyrApp:::format_moment(x, "Europe/Berlin", "de"), "8. Okt. 2026, 19:49 (Europe/Berlin, UTC+2)")
  expect_identical(delphyrApp:::format_moment(x, "UTC", "en"), "8 Oct 2026, 17:49 (UTC)")
  expect_identical(delphyrApp:::format_moment(x, "Asia/Kolkata", "en"), "8 Oct 2026, 23:19 (Asia/Kolkata, UTC+5:30)")
  expect_identical(delphyrApp:::format_moment(x, "America/St_Johns", "en"), "8 Oct 2026, 15:19 (America/St_Johns, UTC-2:30)")
  expect_identical(delphyrApp:::format_moment(x, "Europe/Berlin", "en", with_zone = FALSE), "8 Oct 2026, 19:49")
  # An unknown or missing zone falls back to UTC and says so.
  expect_identical(delphyrApp:::format_moment(x, "Mars/Olympus", "en"), "8 Oct 2026, 17:49 (UTC)")
  expect_identical(delphyrApp:::format_moment(x, NULL, "en"), "8 Oct 2026, 17:49 (UTC)")
  expect_identical(delphyrApp:::format_moment(x, "", "en"), "8 Oct 2026, 17:49 (UTC)")
  # Month names do not depend on the locale of the server.
  months <- delphyrApp:::format_moment(sprintf("2026-%02d-15T12:00:00Z", 1:12), "UTC", "fr", with_zone = FALSE)
  expect_identical(sub("^15 (.*) 2026.*$", "\\1", months), c("janv.", "f\u00e9vr.", "mars", "avr.", "mai", "juin", "juil.", "ao\u00fbt", "sept.", "oct.", "nov.", "d\u00e9c."))
  # A missing moment is a dash; the result keeps the length of the input.
  expect_identical(delphyrApp:::format_moment(c(x, NA, "later"), "UTC", "en"), c("8 Oct 2026, 17:49 (UTC)", "\u2014", "\u2014"))
  expect_identical(delphyrApp:::format_moment(character(), "UTC", "en"), character())
  expect_true(all(grepl("^[ -~]*$", c(delphyrApp:::format_moment(x, "Europe/Berlin", "en"), delphyrApp:::format_moment(x, "UTC", "en")))))
})

test_that("the hour that occurs twice in autumn stays unambiguous", {
  shown <- delphyrApp:::format_moment(c("2026-10-25 00:30:00+00", "2026-10-25 01:30:00+00"), "Europe/Berlin", "en")
  expect_identical(shown, c("25 Oct 2026, 02:30 (Europe/Berlin, UTC+2)", "25 Oct 2026, 02:30 (Europe/Berlin, UTC+1)"))
})

test_that("numbers and percentages use the decimal sign of the language", {
  expect_identical(delphyrApp:::format_number(c(7.24, 8, NA, -0.04), "en"), c("7.2", "8", "\u2014", "0"))
  expect_identical(delphyrApp:::format_number(7.26, "fr"), "7,3")
  expect_identical(delphyrApp:::format_number(7.26, "de", 2L), "7,26")
  expect_identical(delphyrApp:::format_number("not a number", "en"), "\u2014")
  expect_identical(delphyrApp:::format_percent(c(0.75, 1, NA), "en"), c("75%", "100%", "\u2014"))
  expect_identical(delphyrApp:::format_percent(0.5, "fr"), "50\u00a0%")
  expect_identical(delphyrApp:::format_percent(2 / 3, "de"), "67\u00a0%")
})

test_that("references are shortened and codes made readable", {
  id <- "0b5e3c1a-6f2d-4c7e-9a10-3d2f1e0c9b8a"
  expect_identical(delphyrApp:::short_ref(c(id, NA, "")), c("0b5e3c1a", "\u2014", "\u2014"))
  expect_identical(delphyrApp:::short_ref(id, 12L), "0b5e3c1a-6f2")
  tag <- delphyrApp:::ref_tag(id)
  expect_identical(tag$attribs$title, id)
  expect_identical(tag$children[[1]], "0b5e3c1a")
  expect_identical(delphyrApp:::humanize_code(c("public_contributors", "relevance", NA, "")), c("Public contributors", "Relevance", "\u2014", "\u2014"))
})

test_that("the round table shows deadlines with zone and offset", {
  rounds <- data.frame(id = "a", number = 1L, state = "open", deadline = as.POSIXct("2026-12-10 17:00:00", tz = "UTC"))
  expect_identical(round_display(rounds, "en", "Europe/Berlin")$Deadline, "10 Dec 2026, 18:00 (Europe/Berlin, UTC+1)")
  expect_identical(round_display(rounds, "de", "Europe/Berlin")$Abgabefrist, "10. Dez. 2026, 18:00 (Europe/Berlin, UTC+1)")
  expect_identical(round_display(rounds, "en", NULL)$Deadline, "10 Dec 2026, 17:00 (UTC)")
})

test_that("a date and a time of day in the study's zone become a moment with its offset", {
  read <- delphyrApp:::read_moment
  expect_identical(read("2026-12-10", "18:00", "Europe/Berlin"), list(value = "2026-12-10T18:00:00+01:00"))
  expect_identical(read(as.Date("2026-07-01"), "9:05", "Europe/Berlin"), list(value = "2026-07-01T09:05:00+02:00"))
  expect_identical(read("2026-07-01", " 23:59 ", "America/New_York"), list(value = "2026-07-01T23:59:00-04:00"))
  expect_identical(read("2026-07-01", "12:00", "Asia/Kolkata"), list(value = "2026-07-01T12:00:00+05:30"))
  expect_identical(read("2026-07-01", "12:00", NULL), list(value = "2026-07-01T12:00:00+00:00"))
  # The clocks go forward: 02:30 does not exist; they go back: 02:30 occurs twice.
  expect_identical(read("2026-03-29", "02:30", "Europe/Berlin"), list(error = "nonexistent"))
  expect_identical(read("2026-10-25", "02:30", "Europe/Berlin"), list(error = "ambiguous"))
  expect_identical(read("2026-10-25", "03:30", "Europe/Berlin"), list(value = "2026-10-25T03:30:00+01:00"))
  for (bad in list(list("", "18:00"), list("2026-12-10", ""), list(NULL, "18:00"), list(NA, "18:00"), list("2026-02-30", "18:00"), list("10.12.2026", "18:00"), list("2026-12-10", "24:00"), list("2026-12-10", "18.00"), list("2026-12-10", "6 pm"))) {
    expect_identical(read(bad[[1]], bad[[2]], "Europe/Berlin"), list(error = "format"), info = paste(format(bad), collapse = " "))
  }
  expect_match(delphyrApp:::moment_error_text("ambiguous", "en"), "occurs twice")
  expect_match(delphyrApp:::moment_error_text("format", "fr"), "AAAA-MM-JJ")
})

test_that("the moment input shows date, time and the study's zone, prefilled in that zone", {
  html <- as.character(delphyrApp:::moment_input("deadline", "New deadline", "Europe/Berlin", "en", "2026-12-10T17:00:00Z"))
  expect_match(html, "id=\"deadline_date\"", fixed = TRUE)
  expect_match(html, "data-initial-date=\"2026-12-10\"", fixed = TRUE)
  expect_match(html, "id=\"deadline_time\"", fixed = TRUE)
  expect_match(html, "value=\"18:00\"", fixed = TRUE)
  expect_match(html, "Time zone of the study: Europe/Berlin", fixed = TRUE)
  expect_match(html, "<legend>New deadline</legend>", fixed = TRUE)
  empty <- as.character(delphyrApp:::moment_input("x", "When", "Nowhere/Unknown", "de"))
  expect_match(empty, "Zeitzone der Studie: UTC", fixed = TRUE)
  expect_false(grepl("data-initial-date=\"[0-9]", empty))
  # The date field's own English tooltip is not shown; the label names the format.
  expect_false(grepl("Date format", empty, fixed = TRUE))
})
