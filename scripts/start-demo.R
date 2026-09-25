# Run from the repository root. All identities and data are synthetic.
.libPaths(c(normalizePath(".R-library"), .libPaths()))
pkgload::load_all("packages/delphyr", quiet = TRUE)
pkgload::load_all("packages/delphyrApp", quiet = TRUE)
r <- delphyr::connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "development", artifact_root = file.path(getwd(), ".artifacts"))
delphyr::migrate_repository(r)
dir.create(".local", showWarnings = FALSE, mode = "0700")
fixture_file <- ".local/demo-fixture.rds"
if (file.exists(fixture_file)) {
  f <- readRDS(fixture_file)
} else {
  f <- delphyr::demo_study(r)
  saveRDS(f, fixture_file)
}
DBI::dbDisconnect(r$con)
r <- delphyr::connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "delphyr_runtime", environment = "development", artifact_root = file.path(getwd(), ".artifacts"))
args <- commandArgs(trailingOnly = TRUE)
role <- if (length(args)) args[1] else "manager"
if (role == "manager") {
  id <- f$manager$principal_id
} else {
  index <- suppressWarnings(as.integer(role))
  if (is.na(index) || index < 1 || index > length(f$panel)) stop("Choose manager or a synthetic panel number 1–30.")
  id <- f$panel[[index]]$principal_id
}
actor <- delphyr::demo_actor(r, id)
port <- if (length(args) > 1) as.integer(args[2]) else 3849L
tryCatch(shiny::runApp(delphyrApp::run_app(r, actor), host = "127.0.0.1", port = port), finally = DBI::dbDisconnect(r$con))
