# delphyrApp <img src="inst/www/delphyR-hex.png" align="right" width="150" alt="delphyR dolphin hex logo" />

**A focused workspace for synthetic Delphi studies.**

`delphyrApp` brings panel responses, round management, editorial review, and
coordination into the CTTIR suite. Participants explicitly save their own
responses and receive a durable submission receipt. Managers review instruments,
advance rounds, prepare feedback, and request private research exports.

The interface offers **English, German, and French**, with English as the default.
Scientific text stays in its stored authored language; selecting an interface
language does not translate a protocol or manufacture an instrument translation.
This is development software, not a production release.

![Synthetic panel workspace](inst/figures/panel-desktop.png)

## Install and start

Install the core package first, then the application package:

```r
# install.packages("remotes")
remotes::install_github("CTTIR/delphyR", subdir = "packages/delphyr")
remotes::install_github("CTTIR/delphyR", subdir = "packages/delphyrApp",
                        build_vignettes = TRUE)
```

The [repository guide](../../README.md#run-the-local-application) provisions the
synthetic PostgreSQL fixture and starts a separate worker. With a repository
and actor already resolved by trusted server code:

```r
app <- delphyrApp::run_app(repo, actor, language = "en")
shiny::runApp(app, host = "127.0.0.1", port = 3838)
```

A fixed actor is shared by every session of that demo instance. A trusted host
can instead use `actor_factory(session, repo)` and `repo_factory()` for separate
session identities and connections. Factory connections close at session end;
a directly supplied repository remains the caller's responsibility. Factory
errors or missing identities close the session before service access. Browser
fields and URL parameters never establish identity or authority.

Local OIDC evidence is documented separately. The stock Shiny Server OSS
identity-header path and production deployment remain unqualified. No external
mail transport is enabled.

## Participant workflow

1. Choose a study and load an assigned round.
2. Read the stored study information and explicitly record consent.
3. Select a response or allowed special category; save each field explicitly.
4. Review the confirmed field count and submit deliberately.

A failed save keeps the typed value and does not advance its confirmed revision.
Submission is blocked while fields have pending changes. Services independently
check consent, ownership, rights, deadline, required fields, and revision sets.
Submitted responses cannot be edited. Ratings have no default midpoint and the
panel does not see live current-round results.

On connection loss, the interface does not claim that pending changes are saved.
The tested reload path restores committed values; it is not an offline editor.
Released feedback includes approved aggregates and only the person's own prior
answers, with a changed-wording notice where applicable.

## Study team workflows

Permission-filtered navigation preserves forms while moving between sections.
Managers review round transitions and exact feedback releases, queue analysis
and exports, validate instrument imports, and approve future-round protocol
amendments after reviewing field changes. Existing rounds retain their protocol.

Editors preserve originals and record separate redactions or summaries. Another
person reviews exact versions. Theme coding and item-source/split/merge records
remain traceable. Coordinators review contact CSVs and blocking duplicates before
creating unbound invitation drafts; importing an address grants no account access.
Campaign previews bind exact pseudonyms and text before local sink processing.

Analysis, report rendering, exports, and sink processing belong to a separate
worker. **Check operation** refreshes queued work. Downloads recheck authorization
and artifact integrity. A hidden control is never the authorization boundary.

## Design and verification

System fonts, teal and slate accents, visible labels, focus states, responsive
forms, and restrained surfaces follow the CTTIR `brainwritR` family. Status
messages use a polite live region and do not depend on color. Tables can scroll;
reduced-motion preferences are respected. Deadlines include the study time zone
and UTC offset.

Namespaced modules call injected services and contain no SQL or consensus rules.
Read the [workflow vignette](vignettes/synthetic-workflow.Rmd) and
[qualification evidence](inst/qa/README.md) for reproducible local checks.

```r
testthat::test_local("packages/delphyrApp")
```

Specific Chromium/PostgreSQL checks do not certify every browser, assistive
technology, or mobile device. Formal accessibility, complete cross-browser
acceptance, autosave, the complete invitation browser journey, real mail, and
production operations remain distinct gates. Licensed under [MIT](LICENSE).
