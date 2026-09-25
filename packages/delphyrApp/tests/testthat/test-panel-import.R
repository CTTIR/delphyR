panel_import_services <- function() stats::setNames(rep(list(function(...) NULL), 4), c("get_capabilities", "preview_panel_import", "import_panel", "get_panel_import_receipt"))

test_that("panel import blocks duplicate previews and binds approval to exact CSV bytes", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  text <- "external_ref,email,display_name,locale,stakeholder_group\nREF1,demo@example.invalid,Synthetic,en,professionals\n"
  writeChar(text, path, eos = NULL, useBytes = TRUE)
  file <- data.frame(name = "panel.csv", size = file.info(path)$size, datapath = path, type = "text/csv")
  valid <- FALSE
  imports <- list()
  preview_value <- function(bytes) {
    structure(list(
      study_id = "study", csv = bytes, hash = "reviewed-preview", file_hash = "file-hash", schema_version = "1.0", delimiter = ",", valid = valid,
      rows = data.frame(source_row = 1L, external_ref = "REF1", normalized_email = "demo@example.invalid", display_name = "Synthetic", locale = "en", stakeholder_group = "professionals"),
      issues = if (valid) data.frame(row = integer(), column = character(), code = character()) else data.frame(row = 1L, column = "email", code = "duplicate_in_file")
    ), class = c("delphyr_panel_preview", "list"))
  }
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "coordinate",
      preview_panel_import = preview_value(list(...)[[2]]),
      import_panel = {
        imports[[length(imports) + 1L]] <<- list(...)
        list(id = "receipt")
      },
      get_panel_import_receipt = list(receipt = data.frame(id = "receipt", accepted_rows = 1L, imported_at = as.POSIXct("2026-09-25 12:00:00", tz = "UTC")), invitation_ids = "draft-id"),
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::panel_import_server, args = list(study = function() "study", lang = function() "en", call = call, services = panel_import_services()), {
    session$setInputs(file = file, schema = "1.0", delimiter = ",")
    session$setInputs(preview = 1)
    expect_match(output$issues, "Duplicate in this file", fixed = TRUE)
    session$setInputs(confirm = TRUE, reason = "Reviewed synthetic contacts", approve = 1)
    expect_length(imports, 0L)
    valid <<- TRUE
    session$setInputs(preview = 2)
    writeChar(paste0(text, "changed"), path, eos = NULL, useBytes = TRUE)
    session$setInputs(approve = 2)
    expect_length(imports, 0L)
    writeChar(text, path, eos = NULL, useBytes = TRUE)
    session$setInputs(confirm = FALSE, approve = 3)
    expect_length(imports, 0L)
    session$setInputs(confirm = TRUE, approve = 4)
    expect_length(imports, 1L)
    expect_equal(imports[[1]][[3]], "reviewed-preview")
    expect_match(output$receipt$html, "unbound invitation drafts", fixed = TRUE)
    expect_false(grepl("demo@example.invalid", output$receipt$html, fixed = TRUE))
    expect_null(preview())
  })
})

test_that("panel import controls and data reads require coordination rights", {
  read <- FALSE
  call <- function(name, ...) {
    if (name == "get_capabilities") {
      return("manage")
    }
    read <<- TRUE
    stop("Forbidden")
  }
  shiny::testServer(delphyrApp:::panel_import_server, args = list(study = function() "study", lang = function() "en", call = call, services = panel_import_services()), {
    session$flushReact()
    expect_false(allowed())
    session$setInputs(preview = 1, approve = 1)
    expect_false(read)
  })
})
