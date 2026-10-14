# Run only against the synthetic loopback database after migrations, or
# against a database restored from it (DELPHYR_DB_HOST may name the directory
# of a local socket).
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
r <- delphyr::connect_repository(
  host = Sys.getenv("DELPHYR_DB_HOST", "127.0.0.1"), port = as.integer(Sys.getenv("DELPHYR_DB_PORT", "55439")),
  dbname = Sys.getenv("DELPHYR_DB_NAME", "delphyr"), user = Sys.getenv("DELPHYR_DB_ADMIN", "postgres")
)
delphyr::migrate_repository(r)
DBI::dbExecute(r$con, "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='delphyr_runtime') THEN CREATE ROLE delphyr_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT; END IF; END $$")
for (schema in c("identity", "research", "ops")) {
  DBI::dbExecute(r$con, paste("GRANT USAGE ON SCHEMA", schema, "TO delphyr_runtime"))
  DBI::dbExecute(r$con, paste("GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA", schema, "TO delphyr_runtime"))
}
for (table in c("identity.principals", "identity.memberships", "identity.capabilities", "ops.jobs")) DBI::dbExecute(r$con, paste("GRANT UPDATE ON", table, "TO delphyr_runtime"))
# Research rows are changed only in the columns the services write; triggers
# check every change of state. Revoking the table right first also removes
# the whole-table right of an earlier configuration.
writable <- list(
  "research.studies" = "state", "research.rounds" = c("state", "deadline", "closed_at"), "research.enrollments" = "state",
  "research.panelists" = c("active", "group_code"), "research.response_current" = "revision", "research.feedback" = "state"
)
for (table in names(writable)) {
  DBI::dbExecute(r$con, paste("REVOKE UPDATE ON", table, "FROM delphyr_runtime"))
  DBI::dbExecute(r$con, paste0("GRANT UPDATE (", paste(writable[[table]], collapse = ", "), ") ON ", table, " TO delphyr_runtime"))
}
# Optional component delivery-state tables are granted only if migrated.
for (table in c("ops.message_delivery", "ops.campaigns", "identity.panel_invitations", "ops.worker_heartbeats", "ops.artifacts")) if (!is.na(DBI::dbGetQuery(r$con, paste0("SELECT to_regclass('", table, "')::text AS x"))$x)) DBI::dbExecute(r$con, paste("GRANT UPDATE ON", table, "TO delphyr_runtime"))
# The server log of the application role names the refused statement and the
# violated constraint, never the values of a failing row, a duplicate key or
# a bound parameter.
DBI::dbExecute(r$con, "ALTER ROLE delphyr_runtime SET log_error_verbosity = 'terse'")
DBI::dbDisconnect(r$con)
cat("Synthetic runtime role configured; no owner, DDL, delete or superuser rights; research rows writable only in service columns; terse server log.\n")
