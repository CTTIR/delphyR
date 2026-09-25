for (path in c(".R-library", ".local", ".checks", ".artifacts")) {
  dir.create(path, showWarnings = FALSE, mode = "0700")
}
.libPaths(c(normalizePath(".R-library"), .libPaths()))
dependencies <- c("DBI", "RPostgres", "digest", "jsonlite", "uuid", "testthat", "callr", "withr", "pkgload", "roxygen2", "knitr", "rmarkdown", "shiny", "bslib", "htmltools", "zip")
missing <- dependencies[!vapply(dependencies, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, lib = ".R-library", repos = "https://cloud.r-project.org")

unavailable <- dependencies[!vapply(dependencies, requireNamespace, logical(1), quietly = TRUE)]
if (length(unavailable)) stop("Dependencies could not be loaded: ", paste(unavailable, collapse = ", "))
