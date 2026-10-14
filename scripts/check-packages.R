dir.create(".checks", showWarnings = FALSE, mode = "0700")
.libPaths(c(normalizePath(".R-library"), .libPaths()))
root <- getwd()
# An installation from the repository uses the committed NAMESPACE and help
# pages, not regenerated ones. After roxygen has run, both must equal the
# commit. The comparison needs a Git checkout and the roxygen2 version that
# generated the committed files, as their committed DESCRIPTION records it
# (roxygen itself may already have rewritten the working copy). In CI a
# comparison that cannot be made is an error, so that it is never left out
# unnoticed, for example after a new roxygen2 release.
git <- function(...) suppressWarnings(system2("git", c("-C", shQuote(root), ...), stdout = TRUE, stderr = FALSE))
not_compared <- function(pkg, reason) {
  text <- paste0("Committed documentation of ", pkg, " not compared: ", reason)
  if (tolower(Sys.getenv("CI")) %in% c("true", "1")) stop(text, call. = FALSE)
  message(text)
  character()
}
committed_documentation <- function(pkg) {
  description <- git("show", paste0("HEAD:packages/", pkg, "/DESCRIPTION"))
  if (!is.null(attr(description, "status"))) {
    return(not_compared(pkg, "no Git checkout."))
  }
  connection <- textConnection(description)
  on.exit(close(connection))
  fields <- read.dcf(connection)
  field <- intersect(c("Config/roxygen2/version", "RoxygenNote"), colnames(fields))
  documented <- if (length(field)) trimws(unname(fields[1, field[1]])) else "an unrecorded version"
  installed <- as.character(utils::packageVersion("roxygen2"))
  if (!identical(installed, documented)) {
    return(not_compared(pkg, paste0("roxygen2 ", installed, " is installed, but it was generated with roxygen2 ", documented, ". Install that version, or regenerate the documentation with ", installed, " and commit the result.")))
  }
  changed <- git("status", "--porcelain", "--", shQuote(file.path("packages", pkg, c("NAMESPACE", "man"))))
  if (!is.null(attr(changed, "status"))) {
    return(not_compared(pkg, "Git could not report changes."))
  }
  changed
}
# Each package is installed before the next one, which may import it, is
# documented.
for (pkg in c("delphyr", "delphyrApp")) {
  source <- file.path(root, "packages", pkg)
  if (!dir.exists(source)) next
  roxygen2::roxygenise(source)
  stale <- committed_documentation(pkg)
  if (length(stale)) stop("The committed roxygen output of ", pkg, " is out of date. Regenerate it with roxygen2::roxygenise() and commit:\n", paste(stale, collapse = "\n"))
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
