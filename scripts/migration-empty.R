# Ephemeral synthetic database; never reuse or drop an existing database.
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
admin <- DBI::dbConnect(RPostgres::Postgres(), host = "127.0.0.1", port = 55439, dbname = "postgres", user = "postgres")
name <- paste0("delphyr_migration_", gsub("-", "", uuid::UUIDgenerate()))
quoted <- as.character(DBI::dbQuoteIdentifier(admin, name))
DBI::dbExecute(admin, paste("CREATE DATABASE", quoted))
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
      cat("EMPTY MIGRATION PASS:", nrow(rows), "migrations, idempotent rerun, synthetic service fixture.\n")
    },
    finally = DBI::dbDisconnect(r$con)
  )
}, finally = {
  DBI::dbExecute(admin, paste("DROP DATABASE", quoted))
  DBI::dbDisconnect(admin)
})
