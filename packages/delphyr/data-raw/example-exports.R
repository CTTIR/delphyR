# Regenerates the synthetic exports in inst/extdata that the examples of
# reproduce_export() and reproduce_study_export() check without a database.
#
# Needs a disposable PostgreSQL database prepared with migrate_repository(),
# reached through the libpq environment variables (PGHOST, PGPORT, PGUSER)
# and named by DELPHYR_EXAMPLE_DB. Run it from the package directory with
# this version of delphyr installed and without Quarto on the PATH, so that
# the round export carries the portable basic report.
library(delphyr)
options(delphyr.log_level = "off")

repo <- connect_repository(
  dbname = Sys.getenv("DELPHYR_EXAMPLE_DB", "delphyr"),
  artifact_root = tempfile("delphyr-exports-")
)
study <- demo_study(repo, n = 4L, item_count = 2L)

# Opens a round, lets every panel member answer and submit, closes it and
# freezes its snapshot.
answer_round <- function(round, values, key) {
  for (state in c("review", "approved", "open")) {
    transition_round(repo, study$manager, round$id, state, round$hash, "Synthetic", paste(key, state))
  }
  for (i in seq_along(study$panel)) {
    panelist <- study$panel[[i]]
    enrollments <- list_enrollments(repo, panelist, study$study_id)
    enrollment <- enrollments$id[enrollments$round_state == "open"]
    record_consent(repo, panelist, study$study_id, study$consent_id, TRUE, "consent")
    q <- get_questionnaire(repo, panelist, enrollment)
    saved <- lapply(seq_along(q$items$id), function(j) {
      save_response(repo, panelist, enrollment, q$items$id[j], list(value = values[i, j], status = "answered"), 0L, paste(key, "save", j))
    })
    submit_round(repo, panelist, enrollment, setNames(vapply(saved, `[[`, integer(1), "revision"), q$items$id), paste(key, "submit"))
  }
  transition_round(repo, study$manager, round$id, "closed", round$hash, "Synthetic", paste(key, "closed"))
  freeze_round(repo, study$manager, round$id, paste(key, "freeze"))
}

first <- answer_round(study$round, matrix(c(8L, 7L, 9L, 3L, 5L, 8L, 6L, 2L), 4L), "round-1")
analysis <- run_analysis(repo, study$manager, first$id, "round-1 analysis")
feedback <- create_feedback(repo, study$manager, analysis$id, command_id = "round-1 feedback")
release_feedback(repo, study$manager, feedback$id, feedback$hash, "round-1 release")
deadline <- format(Sys.time() + 7 * 86400, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
round_2 <- prepare_round(repo, study$manager, study$study_id, study$items, study$consent_id, deadline, "round-2")
assign_feedback(repo, study$manager, round_2$id, feedback$id, "round-2 feedback")
answer_round(round_2, matrix(c(8L, 8L, 9L, 6L, 6L, 8L, 7L, 4L), 4L), "round-2")

# Runs one export job and returns the directory of its verified files.
export_files <- function(job) {
  force(job)
  worker_step(repo, study_id = study$study_id)
  download_artifact(repo, study$manager, get_operation(repo, study$manager, job$id)$result_ref)
}
copy_export <- function(path, name) {
  target <- file.path("inst", "extdata", name)
  dir.create(target, recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files(path, full.names = TRUE), target, overwrite = TRUE)
  invisible(target)
}
copy_export(export_files(request_export(repo, study$manager, first$id, "round export")), "example-round-export")
copy_export(export_files(request_study_export(repo, study$manager, study$study_id, "research_pseudonymized", "study export")), "example-study-export")
DBI::dbDisconnect(repo$con)
