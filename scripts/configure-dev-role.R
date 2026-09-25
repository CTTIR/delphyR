# Run only against the synthetic loopback database after migrations.
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
r <- delphyr::connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres")
delphyr::migrate_repository(r)
DBI::dbExecute(r$con, "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='delphyr_runtime') THEN CREATE ROLE delphyr_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT; END IF; END $$")
for (schema in c("identity", "research", "ops")) {
  DBI::dbExecute(r$con, paste("GRANT USAGE ON SCHEMA", schema, "TO delphyr_runtime"))
  DBI::dbExecute(r$con, paste("GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA", schema, "TO delphyr_runtime"))
}
for (table in c("identity.principals", "identity.memberships", "identity.capabilities", "research.studies", "research.rounds", "research.enrollments", "research.response_current", "research.feedback", "ops.jobs")) DBI::dbExecute(r$con, paste("GRANT UPDATE ON", table, "TO delphyr_runtime"))
# Optional component delivery-state tables are granted only if migrated.
for (table in c("ops.message_delivery", "ops.campaigns")) if (!is.na(DBI::dbGetQuery(r$con, paste0("SELECT to_regclass('", table, "')::text AS x"))$x)) DBI::dbExecute(r$con, paste("GRANT UPDATE ON", table, "TO delphyr_runtime"))
DBI::dbDisconnect(r$con)
cat("Synthetic runtime role configured; no owner, DDL, delete or superuser rights.\n")
