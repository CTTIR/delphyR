protocol_services <- function() stats::setNames(rep(list(function(...) NULL), 3), c("get_capabilities", "list_protocol_versions", "amend_protocol"))

test_that("protocol approval uses the reviewed prior hash and rejects replaced uploads", {
  old <- delphyr::new_protocol(delphyr::demo_protocol())
  proposed <- unclass(old)
  proposed$stopping$max_rounds <- 4L
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path))
  jsonlite::write_json(proposed, path, auto_unbox = TRUE, digits = NA, null = "null")
  upload <- data.frame(name = "protocol.json", size = file.info(path)$size, type = "application/json", datapath = path)
  saved <- list()
  call <- function(name, ...) {
    switch(name,
      get_capabilities = "manage",
      list_protocol_versions = data.frame(id = "original", version = 1L, hash = "reviewed-base-hash", config = jsonlite::toJSON(unclass(old), auto_unbox = TRUE, digits = NA, null = "null"), reason = NA_character_),
      amend_protocol = {
        saved[[length(saved) + 1L]] <<- list(...)
        list(version = 2L)
      },
      stop("Unexpected service")
    )
  }
  shiny::testServer(delphyrApp:::protocols_server, args = list(study = function() "study", lang = function() "en", call = call, services = protocol_services()), {
    session$setInputs(file = upload, validate = 1)
    expect_match(output$changes, "stopping.max_rounds", fixed = TRUE)
    expect_equal(candidate()$expected_hash, "reviewed-base-hash")
    session$setInputs(confirm = FALSE, reason = "Permit another future round", approve = 1)
    expect_length(saved, 0L)
    changed <- proposed
    changed$stopping$max_rounds <- 5L
    jsonlite::write_json(changed, path, auto_unbox = TRUE, digits = NA, null = "null")
    session$setInputs(confirm = TRUE, approve = 2)
    expect_length(saved, 0L)
    jsonlite::write_json(proposed, path, auto_unbox = TRUE, digits = NA, null = "null")
    session$setInputs(approve = 3)
    expect_length(saved, 1L)
    expect_equal(saved[[1]][[3]], "reviewed-base-hash")
    expect_equal(saved[[1]][[2]]$stopping$max_rounds, 4L)
    expect_null(candidate())
  })
})

test_that("invalid protocol uploads cannot create a preview", {
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path))
  writeLines('{"study":{}}', path)
  expect_error(delphyrApp:::read_protocol_upload(list(size = file.info(path)$size, datapath = path)))
  expect_error(delphyrApp:::read_protocol_upload(list(size = 1000001, datapath = path)), "1 MB")
})
