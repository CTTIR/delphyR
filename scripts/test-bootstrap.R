# No downloads, installations, or package loads: exercise selection using
# synthetic installed-version inventories and the real DESCRIPTION files.
source("scripts/bootstrap.R")
requirements <- bootstrap_requirements()
packages <- unique(requirements$package)
roxygen <- requirements$version[requirements$package == "roxygen2" & requirements$operator == "=="]
stopifnot(length(roxygen) == 1L, !any(c("delphyr", "delphyrApp") %in% packages))
stopifnot(all(c("jsonlite", "testthat", "RPostgres", "shiny", "roxygen2") %in% packages))

versions <- setNames(rep("9999.0", length(packages)), packages)
versions["roxygen2"] <- roxygen
stopifnot(length(bootstrap_unmet(requirements, versions)) == 0L)
old_json <- versions
old_json["jsonlite"] <- "1.8.7"
stopifnot(identical(bootstrap_unmet(requirements, old_json), "jsonlite"))
missing <- versions[names(versions) != "DBI"]
stopifnot(identical(bootstrap_unmet(requirements, missing), "DBI"))
for (other_roxygen in c("0.0.1", "9999.0")) {
  other <- versions
  other["roxygen2"] <- other_roxygen
  stopifnot(identical(bootstrap_unmet(requirements, other), "roxygen2"))
}

# Archived documentation tools need their runtime/build dependencies, without
# installing their optional development and website toolchains.
connection <- textConnection(c("Package: example", "Depends: R (>= 4.1)",
  "Imports: DBI, jsonlite (>= 1.8.8)", "LinkingTo: cpp11", "Suggests: covr"))
description <- read.dcf(connection)
close(connection)
runtime <- bootstrap_dependencies(description, include_suggests = FALSE)
stopifnot(identical(runtime$package, c("R", "DBI", "jsonlite", "cpp11")))
stopifnot(identical(bootstrap_unmet(runtime,
  c(R = "4.0.5", DBI = "1.2.3", jsonlite = "2.0.0", cpp11 = "0.5.5")), "R"))
cat("Bootstrap selection checks passed: missing packages, minimum versions, exact roxygen pin, and archive runtime dependencies.\n")
