test_that("a heading is never larger than the heading of a higher level, also on a phone", {
  css <- app_css()
  phone <- regmatches(css, regexpr("@media\\(max-width:600px\\) \\{[^\n]*", css))
  size <- function(text, selector) as.numeric(regmatches(text, regexec(paste0("(?:^|[ };\n])", selector, " ?\\{font-size:([0-9.]+)rem"), text, perl = TRUE))[[1]][2])
  desktop <- c(h2 = size(css, "h2"), h3 = size(css, "h3"), h4 = size(css, "h4"), h5 = size(css, "h5,h6"))
  expect_false(anyNA(desktop))
  expect_identical(order(desktop, decreasing = TRUE), 1:4)
  # On a phone only the section heading shrinks; it stays the largest.
  expect_gt(size(phone, "h2"), desktop[["h3"]])
})

test_that("fields and tables in a card are white, and tables span the card", {
  css <- app_css()
  # Bootstrap takes the background of fields, lists and tables from the body
  # colour, which is the grey of the page.
  expect_match(css, ".del-sheet {--bs-body-bg:#fff;", fixed = TRUE)
  expect_match(css, ".shiny-html-output > .table {display:table;width:100%!important;", fixed = TRUE)
  # A non-empty output is a pass-through box in Bootstrap 5; a table output must be a box to scroll.
  expect_match(css, ".shiny-html-output:has(> .table) {display:block;overflow-x:auto;", fixed = TRUE)
  # Lists with search show the same arrow as plain lists and no empty line.
  expect_match(css, ".selectize-control.single .selectize-input.has-items:not(.focus) > input {position:absolute!important;", fixed = TRUE)
  expect_match(css, ".table th:first-child,.table td:first-child {position:sticky;left:0;", fixed = TRUE)
})

test_that("spacing, groups and focus follow the conventions", {
  css <- app_css()
  # A button followed by an output that is still empty keeps its distance to what comes next.
  expect_match(css, ".btn:has(+ .shiny-html-output:empty) {margin-bottom:16px;}", fixed = TRUE)
  expect_match(css, ".btn + .shiny-html-output:not(:empty) > :first-child", fixed = TRUE)
  # Before a table the distance lies outside its scrolling frame, so that the
  # edge shadow starts with the table, not beside the button.
  frame <- regexpr(".btn + .shiny-html-output:has(> .table) {margin-top:16px;}", css, fixed = TRUE)
  inner <- regexpr(".btn + .shiny-html-output:has(> .table) > .table {margin-top:0;}", css, fixed = TRUE)
  expect_gt(frame, 0)
  expect_gt(inner, regexpr(".btn + .shiny-html-output:not(:empty) > :first-child", css, fixed = TRUE))
  # The last control of an open group does not touch its border.
  expect_match(css, "details[open] {padding-bottom:14px;}", fixed = TRUE)
  # A heading that receives the focus from a script is marked beside the text, not framed.
  expect_match(css, "[tabindex=\"-1\"]:focus {outline:none;}", fixed = TRUE)
  expect_match(css, "[tabindex=\"-1\"]:focus-visible {box-shadow:", fixed = TRUE)
})
