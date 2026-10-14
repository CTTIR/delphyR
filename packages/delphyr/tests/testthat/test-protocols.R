test_that("amendments preserve historical instruments and reject stale or redefined scales", {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  on.exit(DBI::dbDisconnect(r$con))
  f <- demo_study(r, n = 2L, item_count = 1L)
  before <- list_protocol_versions(r, f$manager, f$study_id)
  p <- delphyr:::from_json(before$config)
  p$study$title <- "Amended synthetic title"
  expect_error(amend_protocol(r, f$panel[[1]], f$study_id, p, before$hash, "Test", "forbidden"), class = "DEL_FORBIDDEN")
  result <- amend_protocol(r, f$manager, f$study_id, p, before$hash, "Prospective synthetic amendment", "amend")
  expect_equal(result$version, 2L)
  expect_identical(amend_protocol(r, f$manager, f$study_id, p, before$hash, "Prospective synthetic amendment", "amend")$id, result$id)
  expect_error(amend_protocol(r, f$manager, f$study_id, p, before$hash, "Stale review", "stale"), class = "DEL_CONFLICT")
  after <- list_protocol_versions(r, f$manager, f$study_id)
  expect_equal(nrow(after), 2L)
  expect_identical(after$config[1], before$config[1])
  expect_equal(after$reason[2], "Prospective synthetic amendment")
  existing <- DBI::dbGetQuery(r$con, "SELECT protocol_id FROM research.rounds WHERE id=$1", params = list(f$round$id))
  expect_identical(existing$protocol_id, before$id)
  reduced <- p
  reduced$panel$groups <- "professionals"
  expect_error(amend_protocol(r, f$manager, f$study_id, reduced, result$hash, "Remove occupied group", "remove-group"), class = "DEL_CONFLICT")
  expect_equal(nrow(list_protocol_versions(r, f$manager, f$study_id)), 2L)
  p$instrument$scales$relevance_9$anchors[[1]] <- "Changed meaning"
  expect_error(amend_protocol(r, f$manager, f$study_id, p, result$hash, "Scale change", "scale"), class = "DEL_CONFLICT")
  expect_error(delphyr:::execute(r, "UPDATE research.protocol_amendments SET reason='rewrite' WHERE study_id=$1", f$study_id), "immutable")
  expect_equal(nrow(list_protocol_versions(r, f$manager, f$study_id)), 2L)
})

test_that("an instrument file is read as written, without guessing types", {
  file <- tempfile(fileext = ".csv")
  withr::defer(unlink(file))
  p <- demo_protocol()
  p$study$languages <- "en"
  p$study$default_language <- "en"
  writeLines(c(
    "item_code,locale,text,definition,domain_code,dimension_code,scale_code,source_ref,required,display_order,item_version",
    "0012,en,NA,Only a demonstration,D01,relevance,relevance_9,SRC-01,true,1,1",
    "0013,en,\"Synthetic item, with a comma\",,D01,relevance,relevance_9,SRC-01,FALSE,2,1"
  ), file)
  items <- read_item_import(file)
  expect_named(items, c("item_code", "item_version", "locale", "text", "dimension_code", "scale_code", "source_ref", "required", "display_order"))
  expect_identical(items$item_code, c("0012", "0013"))
  expect_identical(items$text, c("NA", "Synthetic item, with a comma"))
  expect_identical(items$required, c(TRUE, FALSE))
  expect_identical(items$item_version, c(1L, 1L))
  expect_identical(items$display_order, 1:2)
  expect_true(validate_items(items, p))
  # A reader that guesses types turns the codes into numbers; they are refused.
  guessed <- utils::read.csv(file, stringsAsFactors = FALSE)
  expect_identical(tryCatch(validate_items(guessed[, names(items)], p), error = function(e) e$path), "items.item_code")
  # A file or value that does not follow the contract names what is wrong.
  header <- "item_code,item_version,locale,text,dimension_code,scale_code,source_ref,required,display_order"
  refused <- function(lines, delimiter = ",") {
    writeLines(lines, file)
    tryCatch(read_item_import(file, delimiter), error = function(e) e$path)
  }
  expect_identical(refused(c(header, "I001,1,en,Text,relevance,relevance_9,SRC,yes,1")), "items.required")
  expect_identical(refused(c(header, "I001,1.5,en,Text,relevance,relevance_9,SRC,true,1")), "items.item_version")
  expect_identical(refused(c(header, "I001,1,en,Text,relevance,relevance_9,SRC,true,first")), "items.display_order")
  expect_identical(refused(c("item_code,locale,text", "I001,en,Text")), "items.columns")
  # The v1 example of the specification has no item_version, which is required here.
  expect_identical(refused(c(
    "item_code,locale,text,definition,domain_code,dimension_code,scale_code,source_ref,required,display_order",
    "I001,de,\"Synthetic example item A\",\"Demonstration only\",D01,relevance,relevance_9,DEMO-SRC-01,true,1"
  )), "items.columns")
  expect_identical(refused(c(paste0(header, ",note"), "I001,1,en,Text,relevance,relevance_9,SRC,true,1,x")), "items.columns")
  expect_identical(refused(c(header, "I001,1,en,Text,relevance,relevance_9,SRC,true,1,surplus")), "items.columns")
  expect_identical(refused(c(header, "I001,1,en,\"Open quote,relevance,relevance_9,SRC,true,1")), "items.file")
  expect_identical(refused(header), "items.rows")
  expect_identical(refused(c(header, "I001,1,en,Text,relevance,relevance_9,SRC,true,1"), "\t"), "items.delimiter")
  writeBin(as.raw(c(0x69, 0x74, 0x65, 0x6d, 0xff, 0x0a)), file)
  expect_identical(tryCatch(read_item_import(file), error = function(e) e$path), "items.encoding")
  expect_identical(tryCatch(read_item_import(tempfile()), error = function(e) e$path), "items.file")
  # The semicolon is accepted when it is chosen explicitly.
  writeLines(c(gsub(",", ";", header, fixed = TRUE), "I001;1;en;Text;relevance;relevance_9;SRC;true;1"), file)
  expect_identical(read_item_import(file, ";")$item_code, "I001")
  expect_identical(tryCatch(read_item_import(file), error = function(e) e$path), "items.columns")
})
