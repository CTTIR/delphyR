dir.create(".checks", showWarnings = FALSE, mode = "0700")
.libPaths(c(normalizePath(".R-library"), .libPaths()))
root <- getwd()
for (pkg in c("delphyr", "delphyrApp")) {
  source <- file.path(root, "packages", pkg)
  if (!dir.exists(source)) next
  roxygen2::roxygenise(source)
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL", paste0("--library=", shQuote(.libPaths()[1])), shQuote(source)))
  if (status != 0) stop("Installation failed: ", pkg)
}
writeLines(c(capture.output(sessionInfo()), capture.output(installed.packages(lib.loc = .libPaths()[1])[, c("Package", "Version"), drop = FALSE])), file.path(root, ".checks", "session-info.txt"))
# R subprocess must inherit both the project and existing user library.
Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
Sys.setenv(`_R_CHECK_CRAN_INCOMING_` = "false")
setwd(file.path(root, ".checks"))
for (pkg in c("delphyr", "delphyrApp")) {
  source <- file.path(root, "packages", pkg)
  if (!dir.exists(source)) next
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "build", shQuote(source)), stdout = paste0(pkg, "-build.log"), stderr = paste0(pkg, "-build.log"))
  if (status != 0) stop("Build failed: ", pkg)
  version <- read.dcf(file.path(source, "DESCRIPTION"))[1, "Version"]
  archive <- paste0(pkg, "_", version, ".tar.gz")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "check", "--as-cran", "--no-manual", shQuote(archive)), stdout = paste0(pkg, "-check.log"), stderr = paste0(pkg, "-check.log"))
  if (status != 0) stop("Check failed: ", pkg)
  log <- readLines(file.path(paste0(pkg, ".Rcheck"), "00check.log"))
  if (!any(log == "Status: OK")) stop("Package check has unresolved findings: ", pkg)
}
