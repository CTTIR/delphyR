restore_artifact_verifier <- function() {
  script <- normalizePath(test_path("..", "restore-verify.R"), mustWork = FALSE)
  stopifnot(file.exists(script))
  expressions <- parse(script)
  selected <- vapply(expressions, function(x) is.call(x) && identical(x[[1]], as.name("<-")) && identical(x[[2]], as.name("verify_restored_artifact")), logical(1))
  environment <- new.env(parent = asNamespace("delphyr"))
  eval(expressions[selected], envir = environment)
  environment$verify_restored_artifact
}
restore_artifact_fixture <- function(profile, files, env = parent.frame()) {
  path <- tempfile("restored-artifact-")
  dir.create(path, mode = "0700")
  withr::defer(unlink(path, recursive = TRUE), envir = env)
  for (name in names(files)) writeLines(files[[name]], file.path(path, name), useBytes = TRUE)
  manifest <- list(profile = profile, files = lapply(names(files), function(name) list(name = name, sha256 = digest::digest(file = file.path(path, name), algo = "sha256"))))
  writeLines(json(manifest), file.path(path, "manifest.json"))
  path
}

test_that("restored round artifacts are recomputed and tampered bytes fail", {
  verify <- restore_artifact_verifier()
  s <- demo_snapshot()
  a <- analyse_round(s)
  path <- restore_artifact_fixture("research_round", list(snapshot.json = snapshot_json(s)))
  manifest <- from_json(paste(readLines(file.path(path, "manifest.json")), collapse = "\n"))
  manifest$snapshot_hash <- s$content_hash
  manifest$result_hash <- a$provenance$result_hash
  writeLines(json(manifest), file.path(path, "manifest.json"))
  expect_true(verify(path, "research_round")$analysis_reproduced)
  expect_error(verify(path, "research_pseudonymized"), class = "DEL_VALIDATION")
  writeLines("altered", file.path(path, "snapshot.json"))
  expect_error(verify(path, "research_round"), class = "DEL_VALIDATION")
})

test_that("restored study research artifacts use their own reproduction contract", {
  verify <- restore_artifact_verifier()
  s <- demo_snapshot()
  a <- analyse_round(s)
  provenance <- list(rounds = list(list(round_number = 1L, export_snapshot_hash = s$content_hash,
    frozen_snapshot_hash = s$content_hash, result_hash = a$provenance$result_hash, text_redacted = FALSE)),
    comparison_hash = content_hash(data.frame()))
  files <- list("snapshot-round-1.json" = snapshot_json(s), "provenance.json" = json(provenance),
    "item_comparability.json" = json(data.frame(effective = logical())))
  path <- restore_artifact_fixture("research_pseudonymized", files)
  expect_false(file.exists(file.path(path, "snapshot.json")))
  expect_true(verify(path, "research_pseudonymized")$analysis_reproduced)
  provenance$rounds[[1]]$result_hash <- paste0("v2:", strrep("0", 64))
  files$provenance.json <- json(provenance)
  changed <- restore_artifact_fixture("research_pseudonymized", files)
  expect_error(verify(changed, "research_pseudonymized"), class = "DEL_VALIDATION")
})

test_that("non-research restored profiles verify all files without claiming analysis", {
  verify <- restore_artifact_verifier()
  for (profile in c("study_summary", "audit_restricted", "contacts_restricted")) {
    path <- restore_artifact_fixture(profile, list(README.md = "Synthetic integrity fixture"))
    proof <- verify(path, profile)
    expect_true(proof$passed && proof$checksums_verified)
    expect_false(proof$analysis_reproduced)
    expect_identical(proof$profile, profile)
    writeLines("unregistered", file.path(path, "extra.txt"))
    expect_error(verify(path, profile), class = "DEL_VALIDATION")
  }
})

test_that("artifact verification CLI exits without opening a database", {
  restore_artifact_verifier()
  root <- normalizePath(test_path("..", ".."))
  path <- restore_artifact_fixture("study_summary", list(README.md = "Synthetic integrity fixture"))
  withr::local_dir(root)
  output <- system2(file.path(R.home("bin"), "Rscript"), c("scripts/restore-verify.R", "--artifact", shQuote(path), "study_summary"), stdout = TRUE, stderr = TRUE)
  expect_null(attr(output, "status"))
  proof <- from_json(tail(output[startsWith(output, "{")], 1L))
  expect_true(proof$passed && proof$checksums_verified)
  expect_false(proof$analysis_reproduced)
})


test_that("standalone recovery ignores inherited routing but keeps password authentication", {
  script <- parse(test_path("..", "restore-verify.R"))
  routing <- vapply(script, function(x) is.call(x) && identical(x[[1]], as.name("Sys.unsetenv")), logical(1))
  variables <- c("PGHOSTADDR", "PGSERVICE", "PGSERVICEFILE")
  withr::local_envvar(c(PGHOSTADDR = "192.0.2.1", PGSERVICE = "unrelated", PGSERVICEFILE = "/unrelated/service", PGPASSWORD = "synthetic-password"))
  eval(script[routing])
  expect_identical(unname(Sys.getenv(variables)), rep("", length(variables)))
  expect_identical(Sys.getenv("PGPASSWORD"), "synthetic-password")
})

test_that("role setup subprocess uses only the isolated restored database and account", {
  script <- parse(test_path("..", "restore-verify.R"))
  configured <- vapply(script, function(x) is.call(x) && identical(x[[1]], as.name("<-")) && identical(x[[2]], as.name("configured")), logical(1))
  directory <- tempfile("restore-role-subprocess-")
  dir.create(directory)
  withr::defer(unlink(directory, recursive = TRUE))
  report <- file.path(directory, "environment.txt")
  program <- file.path(directory, "Rscript")
  writeLines(c("#!/bin/sh", 'printf "%s\\n" "$DELPHYR_DB_HOST" "$DELPHYR_DB_PORT" "$DELPHYR_DB_NAME" "$DELPHYR_DB_ADMIN" > "$DELPHYR_TEST_ENV_REPORT"'), program)
  Sys.chmod(program, "0755")
  withr::local_envvar(c(PATH = paste(directory, Sys.getenv("PATH"), sep = .Platform$path.sep), DELPHYR_TEST_ENV_REPORT = report,
    DELPHYR_DB_HOST = "unrelated", DELPHYR_DB_PORT = "1", DELPHYR_DB_NAME = "unrelated", DELPHYR_DB_ADMIN = "unrelated"))
  environment <- new.env(parent = baseenv())
  environment$socket <- "/tmp/private restore socket"
  eval(script[configured], envir = environment)
  expect_identical(environment$configured, 0L)
  expect_identical(readLines(report), c(environment$socket, "5432", "delphyr", "postgres"))
})
