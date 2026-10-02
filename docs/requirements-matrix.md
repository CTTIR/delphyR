# Requirements matrix

As of 3 October 2026. `implemented_tested` denotes the technical component
with its evidence on synthetic data, not an institutional approval and not
the acceptance decision. Test files without a path are in
`packages/delphyr/tests/testthat/`; `browser-*.R` are the checks under
`packages/delphyrApp/inst/qa/`, run in Chromium against PostgreSQL under the
restricted application role. The boundary of each row is part of its status.

| ID | Status | Evidence / boundary |
|---|---|---|
| STU-01 | implemented_tested | Immutable protocol history, approval bound to a hash, group and scale identity (`test-protocols.R`); protocol upload, diff and approval in the browser. |
| STU-02 | implemented_tested | Readiness findings listed completely; approval and opening refused with concrete codes (`test-round-lifecycle.R`, `browser-management-postgres.R`, ADR-020). |
| STU-03 | implemented_tested | Every exported service is called with the valid identifiers of another study by a manager and a member of a different study; every call is refused (`test-security.R`). Foreign keys across studies are rejected by the database (`test-services.R`, `test-qualitative.R`). |
| PAN-01 | implemented_tested | CSV schema, row errors, duplicates, approval of the exact file, atomic import (`test-panel-import.R`, `browser-import-postgres.R`). |
| PAN-02 | implemented_tested | Consent is recorded with the exact version shown; no response without consent to the round's version (`test-services.R`, `test-languages.R`); explicit action in every browser journey. |
| PAN-03 | implemented_tested | Withdrawal stops collection, enrollment and messages and is recorded with the statement shown to the person; a save racing with it is decided by the database (`test-participation.R`); a reminder to a withdrawn member is suppressed with its reason (`test-delivery.R`). The only data rule implemented is to keep earlier data. Removing or anonymising data on request is not a function of this version and needs the organisation's policy ([retention](governance/retention.md)). |
| PAN-04 | implemented_tested | Recorded group changes apply to new rounds only; earlier enrollments keep their group (`test-participation.R`). |
| ITM-01 | implemented_tested | Free-text answers become sources, derived items are linked to them, and source reference, links and lineage are exported (`test-exploratory.R`, `browser-exploratory-postgres.R`, ADR-023). |
| ITM-02 | implemented_tested | Dimensions have separate answers, scales and rules (`test-domain-analytics.R`); two dimensions per item in the browser (`browser-accessibility-postgres.R`, load qualification). |
| ITM-03 | implemented_tested | A rating, a special response and a missing answer are different states; the members an item was assigned to, valid ratings, special responses and missing answers are counted separately in analysis and reports (`test-domain-analytics.R`, `test-core-contracts.R`). |
| ITM-04 | implemented_tested | Split and merge lineage; explicit, superseding comparability decisions, exported and used for comparisons between rounds (`test-qualitative.R`, `test-audit-documentation.R`, `browser-governance-postgres.R`, ADR-021). |
| RND-01 | implemented_tested | Every transition is checked by the service against the allowed predecessor; forbidden ones are refused (`test-round-lifecycle.R`, `test-services.R`). |
| RND-02 | implemented_tested | Text, order, scales and rules of an opened round cannot change; the database refuses it as well (`test-services.R`, `test-service-contracts.R`). |
| RND-03 | implemented_tested | Save, submit and close in every order with independent processes and database locks as barriers; two closes close once (`test-services.R`, `test-service-contracts.R`). |
| RSP-01 | implemented_tested | A reload restores the last committed revision (`browser-network-keyboard.R`, `browser-autosave-postgres.R`, `browser-firefox-postgres.R`). |
| RSP-02 | implemented_tested | One effective submission per person and round; a repeated or concurrent submit returns the same receipt (`test-services.R`). |
| RSP-03 | implemented_tested | A stale revision is refused as a conflict; a second tab cannot overwrite silently and resolves only by a deliberate action (`test-services.R`, `browser-autosave-postgres.R`). |
| RSP-04 | implemented_tested | Settled entries are saved automatically and marked saved only after the commit; an entry made offline stays visibly unconfirmed and uncommitted, is saved after reconnection, and reload restores the last committed revision (ADR-019). |
| ANA-01 | implemented_tested | The analysis of a snapshot is repeated offline from the export with the identical result hash (`test-study-export.R`, `scripts/demo-e2e.R`, scenario 1, restore rehearsal). |
| ANA-02 | implemented_tested | Thresholds are compared on unrounded proportions; boundary cases (`test-core-contracts.R`, `test-domain-analytics.R`). |
| ANA-03 | implemented_tested | Every proportion carries numerator, denominator and the missing rule in results, feedback and exports (`test-domain-analytics.R`, `test-study-export.R`). |
| ANA-04 | implemented_tested | Paired stability, its number of pairs and excluded versions are reported apart from consensus and attrition (`test-domain-analytics.R`; 28 and 27 pairs in scenario 1). |
| ANA-05 | implemented_tested | A required group below the minimum gives `insufficient_data` whatever the total (`test-domain-analytics.R`). |
| FDB-01 | implemented_tested | Released feedback is immutable in the database; a correction is a new version and earlier displays keep the earlier one (`test-exploratory.R`, `test-core-contracts.R`). |
| FDB-02 | implemented_tested | A member receives only the own previous answers, read from the frozen revisions (`test-large-rounds.R`, `test-exploratory.R`, `test-security.R`; scenario 1 in the browser). |
| FDB-03 | implemented_tested | Small cells are suppressed including totals that would allow subtraction (`test-domain-analytics.R`, `test-study-export.R`). |
| QUA-01 | implemented_tested | Original, redaction, summary and release are separate and immutable; only independently released versions reach feedback and exports; released feedback is corrected by a new version. |
| QUA-02 | implemented_tested | Several sources per item and several items per source; the exploratory path from free-text round to rating round runs through the interface. |
| COM-01 | implemented_tested | Exact preview and approval, send time, quiet hours, reminder limits, delivery states, human resolution of uncertain delivery, renewed eligibility check before delivery (scenario 8) and a hold of waiting messages after a restore, in the local sink and through the adapter contract with test doubles. No production provider adapter is shipped or approved. |
| COM-02 | implemented_tested | Jobs and messages are durable rows with leases; a crashed worker's claim expires and is resumed or becomes terminal; a worker reports that it is alive (`test-jobs.R`, `test-delivery.R`, `test-operations.R`). |
| EXP-01 | implemented_tested | Research, summary, audit and contact profiles with separate rights; canary tests for originals, contacts and account references; released redactions only. Public release is refused by design. |
| EXP-02 | implemented_tested | Study report across rounds with versions, hashes, limitations and versioned author-supplied documentation; offline reproduction of analyses and comparisons. Institutional content of the documentation remains the study team's. |
| SEC-01 | implemented_tested | Real sign-in through Keycloak, OAuth2 Proxy and nginx with one, two and three application processes: forged headers, cookies and callbacks, the direct port, revoked rights, a disabled account, invitation acceptance bound to the account, expired identity and expired gateway session, sign-out ([authentication](authentication.md)). Boundary: the directly served application over local HTTP; stock Shiny Server OSS drops the identity headers and is not qualified. |
| SEC-02 | implemented_tested | Technical log of fixed tokens with a reference in every failure message; marked values absent from the technical log, conditions, audit trail, command receipts, the database server log of the application role and the process output in a browser run ([security](security.md)). |
| SEC-03 | implemented_tested | Current rights are read before every protected action, also after waiting for a lock and at download (`test-service-contracts.R`, `test-jobs.R`, `test-study-export.R`, `browser-revocation-postgres.R`, gateway qualification). |
| AUD-01 | implemented_tested | Actor, time, object, action, detail and rationale for every command; History view and audit export; panel account references withheld ([audit](audit.md)). |
| OPS-01 | implemented_tested | A dump is restored into an isolated instance; every table, the schema, migrations and snapshots are compared; the services then use the restored database (status, role, a member's and a staff read, snapshots verified and analysed again, waiting messages held); one study's exports are recomputed (`scripts/restore-check.sh`). Boundary: synthetic data; no point-in-time recovery, no production recovery objectives, no sign-in through the gateway on the restored instance. |
| OPS-02 | implemented_tested | All migrations on an empty database with an idempotent repeat; the latest migration on a database of the previous release that holds a conducted round, with data, hashes and results unchanged; a changed checksum of an applied migration is refused (`scripts/migration-empty.R`). |
| UX-01 | implemented_tested | Rating in blocks and submission with real key events only; visible focus; names for all controls; headings in order; reflow at 320 pixels and 200 percent (`browser-accessibility-postgres.R`); the core path in Firefox. Boundary: checks a script can make; no screen reader, no Safari, no mobile device, no statement of conformance. |
| UX-02 | implemented_tested | Interface in English, French and German with every registered text translated and technical identifiers untouched (`test-i18n.R`, `browser-languages.R`); deadlines with offset and timezone, unambiguous in the hour that occurs twice (`test-deadline.R`). Study content is shown as authored. |
| RTD-01 | out_of_scope | P2 under the specification. |
| RNK-01 | out_of_scope | P2 under the specification. |
