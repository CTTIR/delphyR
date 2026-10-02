# Ephemeral synthetic database; never reuse or drop an existing database.
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
admin <- DBI::dbConnect(RPostgres::Postgres(), host = "127.0.0.1", port = 55439, dbname = "postgres", user = "postgres")
name <- paste0("delphyr_migration_", gsub("-", "", uuid::UUIDgenerate()))
quoted <- as.character(DBI::dbQuoteIdentifier(admin, name))
invisible(DBI::dbExecute(admin, paste("CREATE DATABASE", quoted)))
tryCatch({
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = name, user = "postgres", environment = "test")
  tryCatch(
    {
      migrate_repository(r)
      migrate_repository(r)
      rows <- DBI::dbGetQuery(r$con, "SELECT version FROM ops.schema_migrations ORDER BY version")
      expected <- sort(list.files(system.file("sql", package = "delphyr"), pattern = "[.]sql$"))
      stopifnot(identical(rows$version, expected))
      f <- demo_study(r, n = 2, item_count = 1)
      stopifnot(nrow(list_studies(r, f$manager)) == 1)
      # An applied migration whose file was changed afterwards is refused and
      # reported; nothing is applied.
      altered <- tempfile("delphyr-altered-sql-")
      dir.create(altered)
      files <- list.files(system.file("sql", package = "delphyr"), pattern = "[.]sql$", full.names = TRUE)
      stopifnot(all(file.copy(files, altered)))
      cat("\n-- edited after it was applied\n", file = file.path(altered, expected[1]), append = TRUE)
      refused <- tryCatch(migrate_repository(r, altered), error = function(e) e)
      stopifnot(
        inherits(refused, "DEL_CONFLICT"), identical(refused$path, "migration.checksum"),
        identical(DBI::dbGetQuery(r$con, "SELECT version FROM ops.schema_migrations ORDER BY version")$version, expected),
        identical(get_system_status(r, altered)$schema$state, "changed"), !isTRUE(get_system_status(r, altered)$ready), isTRUE(get_system_status(r)$ready)
      )
      cat("EMPTY MIGRATION PASS:", nrow(rows), "migrations, idempotent rerun, synthetic service fixture, changed checksum refused.\n")
    },
    finally = DBI::dbDisconnect(r$con)
  )
}, finally = {
  DBI::dbExecute(admin, paste("DROP DATABASE", quoted))
})

# A database of the previous release that holds data: every migration but the
# latest, a conducted and analysed round, then the latest migration. Data,
# hashes and results must be untouched and the services must read them.
name <- paste0("delphyr_upgrade_", gsub("-", "", uuid::UUIDgenerate()))
quoted <- as.character(DBI::dbQuoteIdentifier(admin, name))
invisible(DBI::dbExecute(admin, paste("CREATE DATABASE", quoted)))
tryCatch({
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = name, user = "postgres", environment = "test")
  tryCatch(
    {
      files <- sort(list.files(system.file("sql", package = "delphyr"), pattern = "^[0-9]+.*[.]sql$", full.names = TRUE))
      previous <- tempfile("delphyr-previous-release-")
      dir.create(previous)
      stopifnot(all(file.copy(utils::head(files, -1L), previous)))
      migrate_repository(r, previous)
      f <- demo_study(r, n = 4, item_count = 2)
      for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic upgrade check", state)
      for (i in seq_along(f$panel)) {
        enrollment <- list_enrollments(r, f$panel[[i]], f$study_id)$id
        record_consent(r, f$panel[[i]], f$study_id, f$consent_id, TRUE, "consent")
        q <- get_questionnaire(r, f$panel[[i]], enrollment)
        revisions <- vapply(seq_len(nrow(q$items)), function(j) save_response(r, f$panel[[i]], enrollment, q$items$id[j], list(value = 5L + i, status = "answered"), 0L, paste("save", j))$revision, integer(1))
        submit_round(r, f$panel[[i]], enrollment, stats::setNames(revisions, q$items$id), "submit")
      }
      transition_round(r, f$manager, f$round$id, "closed", f$round$hash, "All submitted", "close")
      snapshot <- freeze_round(r, f$manager, f$round$id, "freeze")$id
      analysis <- run_analysis(r, f$manager, snapshot, "analyse")
      state <- function() list(
        counts = DBI::dbGetQuery(r$con, "SELECT (SELECT count(*) FROM research.response_revisions)::int AS revisions,(SELECT count(*) FROM research.submissions)::int AS submissions,(SELECT count(*) FROM ops.audit)::int AS audit,(SELECT count(*) FROM ops.commands)::int AS commands"),
        snapshot = DBI::dbGetQuery(r$con, "SELECT hash,md5(content::text) AS content FROM research.snapshots"), analysis = DBI::dbGetQuery(r$con, "SELECT hash FROM research.analyses")
      )
      before <- state()
      stopifnot(before$counts$revisions == 8L, before$counts$submissions == 4L, nrow(before$snapshot) == 1L)
      migrate_repository(r)
      rows <- DBI::dbGetQuery(r$con, "SELECT version FROM ops.schema_migrations ORDER BY version")
      stopifnot(
        identical(rows$version, basename(files)), identical(state(), before), isTRUE(get_system_status(r)$ready),
        # Reading rebuilds the snapshot against its hash; the analysis repeats to the recorded result.
        identical(analyse_round(get_snapshot(r, f$manager, snapshot))$provenance$result_hash, before$analysis$hash),
        nrow(get_questionnaire(r, f$panel[[1]], list_enrollments(r, f$panel[[1]], f$study_id)$id)$responses) == 2L
      )
      cat("UPGRADE MIGRATION PASS:", basename(utils::tail(files, 1L)), "applied to a database of the previous release with a conducted round; data, hashes and results unchanged.\n")
    },
    finally = DBI::dbDisconnect(r$con)
  )
}, finally = {
  DBI::dbExecute(admin, paste("DROP DATABASE", quoted))
  DBI::dbDisconnect(admin)
})
