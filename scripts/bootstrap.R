# Dependency selection is separate from installation so it can be checked
# without changing a library or contacting a package repository.
bootstrap_dependencies <- function(description, include_suggests = TRUE) {
  fields <- intersect(c("Depends", "Imports", "LinkingTo", if (include_suggests) "Suggests"), colnames(description))
  entries <- trimws(unlist(strsplit(paste(description[1, fields], collapse = ","), ",", fixed = TRUE)))
  entries <- entries[nzchar(entries)]
  parsed <- regmatches(entries, regexec("^([[:alnum:].]+)[[:space:]]*(?:\\((>=|<=|==|>|<)[[:space:]]*([^()[:space:]]+)\\))?$", entries, perl = TRUE))
  if (any(lengths(parsed) != 4L)) stop("Unsupported dependency declaration: ", paste(entries[lengths(parsed) != 4L], collapse = ", "))
  data.frame(package = vapply(parsed, `[`, character(1), 2L),
    operator = vapply(parsed, `[`, character(1), 3L),
    version = vapply(parsed, `[`, character(1), 4L), stringsAsFactors = FALSE)
}

bootstrap_requirements <- function(paths = file.path("packages", c("delphyr", "delphyrApp"), "DESCRIPTION")) {
  descriptions <- lapply(paths, read.dcf)
  packages <- vapply(descriptions, function(x) x[1, "Package"], character(1))
  roxygen <- vapply(descriptions, function(x) x[1, "Config/roxygen2/version"], character(1))
  if (anyNA(roxygen) || any(!nzchar(roxygen)) || length(unique(roxygen)) != 1L) {
    stop("Both packages must record the same Config/roxygen2/version.")
  }
  requirements <- do.call(rbind, lapply(descriptions, bootstrap_dependencies))
  requirements <- requirements[!requirements$package %in% packages, , drop = FALSE]
  unique(rbind(requirements, data.frame(package = "roxygen2", operator = "==", version = roxygen[1])))
}

bootstrap_versions <- function() {
  installed <- utils::installed.packages()
  installed <- installed[!duplicated(installed[, "Package"]), , drop = FALSE]
  c(R = as.character(getRversion()), setNames(installed[, "Version"], installed[, "Package"]))
}

bootstrap_unmet <- function(requirements, versions) {
  meets <- vapply(seq_len(nrow(requirements)), function(i) {
    rule <- requirements[i, ]
    installed <- unname(versions[rule$package])
    if (!length(installed) || is.na(installed)) return(FALSE)
    if (!nzchar(rule$operator)) return(TRUE)
    comparison <- utils::compareVersion(installed, rule$version)
    switch(rule$operator, `>=` = comparison >= 0L, `<=` = comparison <= 0L,
      `==` = comparison == 0L, `>` = comparison > 0L, `<` = comparison < 0L)
  }, logical(1))
  unique(requirements$package[!meets])
}

bootstrap_install_roxygen <- function(version, library, repository) {
  available <- utils::available.packages(repos = repository)
  if ("roxygen2" %in% rownames(available) && identical(unname(available["roxygen2", "Version"]), version)) {
    utils::install.packages("roxygen2", lib = library, repos = repository)
    return(invisible(NULL))
  }
  # Binary repositories may lag CRAN, and older versions live in its archive.
  # Download the exact source and install its own declared dependencies first.
  staging <- tempfile("delphyr-roxygen-")
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  archive <- file.path(staging, paste0("roxygen2_", version, ".tar.gz"))
  urls <- paste0(sub("/$", "", repository), c("/src/contrib/", "/src/contrib/Archive/roxygen2/"), basename(archive))
  downloaded <- FALSE
  errors <- character()
  for (url in urls) {
    downloaded <- tryCatch({
      status <- suppressWarnings(utils::download.file(url, archive, mode = "wb", quiet = TRUE))
      if (!identical(status, 0L)) stop("download status ", status)
      utils::untar(archive, files = "roxygen2/DESCRIPTION", exdir = staging)
      description <- read.dcf(file.path(staging, "roxygen2", "DESCRIPTION"))
      if (!identical(unname(description[1, "Version"]), version)) stop("archive version does not match")
      TRUE
    }, error = function(e) {
      errors <<- c(errors, paste(url, conditionMessage(e), sep = ": "))
      FALSE
    })
    if (downloaded) break
  }
  if (!downloaded) stop("Cannot obtain the documented roxygen2 version:\n", paste(errors, collapse = "\n"))
  requirements <- bootstrap_dependencies(description, include_suggests = FALSE)
  requirements <- requirements[requirements$package != "roxygen2", , drop = FALSE]
  missing <- bootstrap_unmet(requirements, bootstrap_versions())
  if ("R" %in% missing) stop("The documented roxygen2 version requires a newer R.")
  if (length(missing)) utils::install.packages(missing, lib = library, repos = repository)
  utils::install.packages(archive, lib = library, repos = NULL, type = "source")
}

bootstrap <- function(repository = "https://cloud.r-project.org") {
  for (path in c(".R-library", ".local", ".checks", ".artifacts")) {
    dir.create(path, showWarnings = FALSE, mode = "0700")
  }
  library <- normalizePath(".R-library")
  .libPaths(c(library, .libPaths()))
  requirements <- bootstrap_requirements()
  missing <- bootstrap_unmet(requirements, bootstrap_versions())
  if ("R" %in% missing) stop("The package DESCRIPTION files require a newer R.")
  dependencies <- setdiff(missing, "roxygen2")
  if (length(dependencies)) utils::install.packages(dependencies, lib = library, repos = repository)
  if ("roxygen2" %in% missing) {
    version <- requirements$version[requirements$package == "roxygen2" & requirements$operator == "=="]
    bootstrap_install_roxygen(version, library, repository)
  }
  unavailable <- bootstrap_unmet(requirements, bootstrap_versions())
  if (length(unavailable)) stop("Dependency versions remain unsatisfied: ", paste(unavailable, collapse = ", "))
  dependencies <- setdiff(unique(requirements$package), "R")
  unavailable <- dependencies[!vapply(dependencies, requireNamespace, logical(1), quietly = TRUE)]
  if (length(unavailable)) stop("Dependencies could not be loaded: ", paste(unavailable, collapse = ", "))
  message("Dependencies satisfy both packages and the recorded roxygen2 version.")
}

if (sys.nframe() == 0L) bootstrap()
