# delphyr / delphyrApp 0.0.1 (development)

- Validated protocols, explicit missingness, and independent round analysis.
- PostgreSQL services with revisions, retry receipts, consent, and authorization.
- Immutable snapshots and approved feedback with the participant's own prior answers.
- Durable jobs and private numeric research exports reproducible offline.
- English, French, and German Shiny interface, initially English, with confirmed saves and conflict handling.
- Versioned protocol amendments with immutable reasons and history.
- Editorial review and campaign approval in the permission-filtered Shiny interface.
- Quarto reports, private export supplements, and combined study artifact recovery.
- Gateway identity resolution and a separate database connection for each session.
- Panel CSV import with duplicate review and an atomic approval receipt.
- Account-bound single-use token services, synthetic withdrawal, and group history.
- Permission-filtered navigation and tested connection-loss/recovery indicators.
- English package guides and executable offline analysis vignette; authored study content retains its language.
- Invitation issuance, account onboarding and confirmed acceptance in the interface, with a one-time hand-over code.
- Automatic saving of settled responses with per-field commit confirmation, deliberate conflict resolution and retry-safe keys.
- Round readiness findings that block approval or opening, exact instrument review, withdrawal of unopened round candidates and explicit enrollment of late panel members.
- Audit trail with rationale and a History view; versioned author-supplied study documentation; explicit comparability decisions for revised items.
- Study-level export profiles (research, summary, audit, contacts) with separate rights, a study report across rounds, offline reproduction and a participant feedback download.
- Study creation from a reviewed protocol, study information, staff rights, the pseudonymous panel and item decisions in the interface; a study always keeps one manager.
- Exploratory free-text rounds: answers become sources, feedback takes qualitative content only from independently released versions, and released feedback is corrected by a new version.
- Approved send times, quiet hours and reminder limits for campaigns; a provider adapter contract; documented human resolution of uncertain deliveries; a status view of background work.
- A technical log of fixed tokens (`log_event()`, `log_operation()`), a reference in every failure message, one limit for every recorded rationale and a size limit for stored protocols.
- Rounds of specification size: a direct, hash-compatible canonical form for tables, column-wise snapshot validation, previous answers read per participant, and reports that render large tables. Study text in a report can no longer become a link or an image.
- The questionnaire of a long round is shown in blocks with an overview before submission; ratings use the browser's own list control.
- `change_round_deadline()` and its interface: an unopened round takes any future deadline, an open round can only be extended, a closed round is not reopened.
- `get_system_status()`, worker heartbeats, `remove_expired_artifacts()`, `get_retention_report()`, `scripts/status.R`, `scripts/artifact-cleanup.R`, runbooks and governance templates.
- `hold_pending_messages()` and `scripts/hold-messages.R`: after a restore, messages that waited for delivery are held for the coordinator's decision. The restore rehearsal now also uses the restored database through the services.
- `run_app(sign_out_url = )`: a sign-out link that ends every session of the account in the process. An expired sign-in is named as such. A process serves the files of its page from its start, so that several processes work behind one gateway.
- The list of rounds starts with the round that is due; the focus moves to the heading of a newly shown block; the display of a chosen file has a name; long checksums wrap on narrow screens.
- Fixed: the management section of a study without any round failed to render, and an input that was not ready could show a failure message.
- Load qualification with 50 browser sessions on a round of specification size, and a gateway qualification with one, two and three application processes, session lifetimes and sign-out.

This is a development version using synthetic data, not acceptance of the complete P1 platform.

- Align the dolphin hex sticker with the CTTIR badge family: restrained flat illustration, petrol borders, dark green background and an external monospaced wordmark.
