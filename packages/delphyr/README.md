# delphyr

**Reproducible Delphi analysis, independent of the application.**

`delphyr` validates protocols and response scales, analyses frozen round data,
and provides the transactional services used by `delphyrApp`. Offline analysis
runs without Shiny or a database. Study services use PostgreSQL.

This is development software for synthetic studies. It is not a CRAN release,
a production qualification, or a validation of a study's scientific choices.

## Install and start

```r
# install.packages("remotes")
remotes::install_github("CTTIR/delphyR", subdir = "packages/delphyr",
                        build_vignettes = TRUE)

library(delphyr)
analysis <- analyse_round(demo_snapshot())
analysis$decisions
analysis$denominators
analysis$missingness
```

The synthetic snapshot explicitly uses pooled consensus. The complete demo
protocol instead requires adequate results in all designated groups. Example
thresholds are not recommendations. Missing responses are not zero ratings.

## Follow the worked example

```r
vignette("offline", package = "delphyr")
```

The [offline vignette](vignettes/offline.Rmd) executes two-round analysis,
contrasts group rules, reports missingness, checks comparability, and prepares
suppressed feedback. A feedback draft still needs a reviewed release before
participant use.

`reproduce_export(path)` verifies a previously obtained private export and
recomputes its analysis without the application or Quarto. Numeric exports do
not include qualitative originals or account mappings; they are not automatically
suitable for public release.

## Study services

The [repository guide](../../README.md) covers the local PostgreSQL environment,
worker, application, and verification commands. Services recheck identity,
study membership, capability, and state. Save receipts follow database commits;
submitted revisions and released scientific records remain traceable.

Panel imports create unbound drafts. Synthetic invitation acceptance requires
explicit approval of an existing issuer/subject identity. Campaigns produce only
local sink receipts. These boundaries do not qualify real recruitment,
external messages, or production identity infrastructure.

See [implementation status](../../docs/IMPLEMENTATION_STATUS.md) for executed
checks and remaining acceptance gates. Licensed under the [MIT License](LICENSE).
