job_repo <- function(env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "PostgreSQL opt-in required")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test", artifact_root = tempfile("delphyr-test-"))
  withr::defer(
    {
      DBI::dbDisconnect(r$con)
      unlink(r$artifact_root, recursive = TRUE)
    },
    envir = env
  )
  r
}
job_fixture <- function(r) {
  f <- demo_study(r, n = 2, item_count = 1)
  for (state in c("review", "approved", "open", "closed")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic fixture", state)
  f$snapshot <- freeze_round(r, f$manager, f$round$id, "freeze")$id
  f
}
test_that("leases recover and exhausted crashes become terminal", {
  r <- job_repo()
  f <- job_fixture(r)
  id <- request_analysis(r, f$manager, f$snapshot, "analysis")$id
  j <- claim_job(r, study_id = f$study_id)
  expect_equal(j$id, id)
  expect_equal(nrow(claim_job(r, study_id = f$study_id)), 0L)
  execute(r, "UPDATE ops.jobs SET lease_until=clock_timestamp()-interval '1 second' WHERE id=$1", id)
  newer <- claim_job(r, study_id = f$study_id)
  expect_equal(newer$id, id)
  expect_false(identical(j$lease_token, newer$lease_token))
  expect_equal(newer$attempts, 2L)
  execute(r, "UPDATE ops.jobs SET lease_until=clock_timestamp()-interval '1 second',attempts=3 WHERE id=$1", id)
  expect_equal(nrow(claim_job(r, study_id = f$study_id)), 0L)
  expect_equal(get_operation(r, f$manager, id)$state, "dead_letter")
})
test_that("private exports reproduce and rights are checked again on download", {
  r <- job_repo()
  f <- job_fixture(r)
  id <- request_export(r, f$manager, f$snapshot, "export")$id
  expect_equal(request_export(r, f$manager, f$snapshot, "export")$id, id)
  result <- worker_step(r, study_id = f$study_id)
  expect_equal(result$state, "succeeded")
  path <- download_artifact(r, f$manager, result$result_ref)
  expect_true(file.exists(file.path(path, "report.html")))
  a <- reproduce_export(path)
  expect_true(all(a$results$n_valid == 0))
  files <- list.files(path)
  expect_false(any(grepl("contact|principal|token", files)))
  set_capability(r, f$manager, f$study_id, f$manager$principal_id, "export", FALSE, "revoke")
  expect_error(download_artifact(r, f$manager, result$result_ref), class = "DEL_FORBIDDEN")
  set_capability(r, f$manager, f$study_id, f$manager$principal_id, "export", TRUE, "restore")
  write("tampered", file.path(path, "analysis-results.csv"))
  expect_error(download_artifact(r, f$manager, result$result_ref), class = "DEL_VALIDATION")
})
test_that("revocation after queueing prevents worker export", {
  r <- job_repo()
  f <- job_fixture(r)
  id <- request_export(r, f$manager, f$snapshot, "export")$id
  set_capability(r, f$manager, f$study_id, f$manager$principal_id, "export", FALSE, "revoke")
  expect_equal(worker_step(r, study_id = f$study_id)$error_code, "DEL_FORBIDDEN")
  expect_equal(query(r, "SELECT state FROM ops.jobs WHERE id=$1", id)$state, "dead_letter")
  expect_false(dir.exists(r$artifact_root))
})
