legacy_service_repo <- function(env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  repo <- connect_repository(host = "127.0.0.1", port = 55439,
    dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(repo$con), envir = env)
  repo
}
# Create representative old records through the service APIs, without editing
# immutable tables. Explicit version arguments still follow their own contract.
legacy_service_hash <- local({
  current <- content_hash
  function(x, version = "1") current(x, version = version)
})

test_that("legacy command receipts survive retries and protocol changes retain full precision", {
  r <- legacy_service_repo()
  f <- with_mocked_bindings(demo_study(r, n = 2L, item_count = 1L),
    content_hash = legacy_service_hash, .package = "delphyr")
  old <- list_protocol_versions(r, f$manager, f$study_id)
  expect_match(old$hash, "^[0-9a-f]{64}$")
  first <- with_mocked_bindings(
    set_capability(r, f$manager, f$study_id, f$panel[[1]]$principal_id, "audit", TRUE, "old-grant"),
    content_hash = legacy_service_hash, .package = "delphyr")
  stored <- query(r, "SELECT payload_hash FROM ops.commands WHERE study_id=$1 AND command_key='old-grant'", f$study_id)$payload_hash
  expect_match(stored, "^[0-9a-f]{64}$")
  expect_identical(set_capability(r, f$manager, f$study_id, f$panel[[1]]$principal_id, "audit", TRUE, "old-grant"), first)
  expect_error(set_capability(r, f$manager, f$study_id, f$panel[[1]]$principal_id, "audit", FALSE, "old-grant"), class = "DEL_CONFLICT")

  p <- from_json(old$config)
  unchanged <- tryCatch(amend_protocol(r, f$manager, f$study_id, p, old$hash, "No content change", "unchanged"), error = identity)
  expect_s3_class(unchanged, "DEL_CONFLICT")
  expect_identical(unchanged$path, "protocol.unchanged")
  p$analysis$consensus$`in`$agree$proportion <- .7 + .Machine$double.eps / 2
  changed <- amend_protocol(r, f$manager, f$study_id, p, old$hash, "Exact prospective threshold", "precise-amendment")
  expect_match(changed$hash, "^v2:[0-9a-f]{64}$")
  after <- list_protocol_versions(r, f$manager, f$study_id)
  expect_identical(after$hash[1], old$hash)
  expect_identical(from_json(after$config[2])$analysis$consensus$`in`$agree$proportion, p$analysis$consensus$`in`$agree$proportion)
  expect_identical(amend_protocol(r, f$manager, f$study_id, p, old$hash, "Exact prospective threshold", "precise-amendment")$id, changed$id)
  altered <- p
  altered$analysis$consensus$`in`$agree$proportion <- .7
  expect_error(amend_protocol(r, f$manager, f$study_id, altered, old$hash, "Exact prospective threshold", "precise-amendment"), class = "DEL_CONFLICT")
})

test_that("legacy panel previews and invitation acceptance receipts remain usable", {
  r <- legacy_service_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  csv <- paste("external_ref,email,display_name,locale,stakeholder_group",
    "legacy,legacy@example.invalid,Synthetic,en,professionals", sep = "\n")
  preview <- with_mocked_bindings(preview_panel_import(r, f$manager, f$study_id, csv),
    content_hash = legacy_service_hash, .package = "delphyr")
  expect_match(preview$hash, "^[0-9a-f]{64}$")
  altered <- preview
  altered$rows$display_name[1] <- "Changed after review"
  expect_error(import_panel(r, f$manager, f$study_id, altered, preview$hash, "Synthetic review", "altered"), class = "DEL_CONFLICT")
  imported <- import_panel(r, f$manager, f$study_id, preview, preview$hash, "Synthetic review", "import")
  expect_identical(imported$preview_hash, preview$hash)
  expect_identical(get_panel_import_receipt(r, f$manager, imported$id)$receipt$preview_hash, preview$hash)
  expect_identical(import_panel(r, f$manager, f$study_id, preview, preview$hash, "Synthetic review", "import"), imported)
  expect_identical(imported$file_hash, preview$file_hash)

  issuer <- "https://synthetic.example.invalid"
  subject <- uid()
  principal <- register_invited_account(r, f$manager, f$study_id, issuer, subject, "Verified synthetic identity", "account")$id
  config <- new_authentication_config(issuer, paste(rep("a", 64), collapse = ""), "127.0.0.1")
  actor <- authenticated_actor(r, list(REMOTE_ADDR = "127.0.0.1", HTTP_X_DELPHYR_GATEWAY = config$gateway_secret, HTTP_X_FORWARDED_USER = subject), config)
  token <- new_invitation_token()
  invitation <- issue_panel_invitation(r, f$manager, f$study_id, imported$invitation_ids[[1]], principal,
    token, reason = "Approved synthetic account", command_id = "issue")
  first <- with_mocked_bindings(accept_panel_invitation(r, actor, f$study_id, invitation$id, token, TRUE, "accept"),
    content_hash = legacy_service_hash, .package = "delphyr")
  stored <- query(r, "SELECT payload_hash FROM identity.panel_invitation_acceptances WHERE invitation_id=$1", invitation$id)$payload_hash
  expect_match(stored, "^[0-9a-f]{64}$")
  expect_identical(accept_panel_invitation(r, actor, f$study_id, invitation$id, token, TRUE, "accept"), first)
  expect_error(accept_panel_invitation(r, actor, f$study_id, invitation$id, new_invitation_token(), TRUE, "accept"), class = "DEL_UNAUTHORIZED")
  expect_identical(query(r, "SELECT token_hash FROM identity.panel_invitations WHERE id=$1", invitation$id)$token_hash,
    digest::digest(as.character(token), algo = "sha256", serialize = FALSE))
})

test_that("legacy campaign hashes still bind release to exact content and recipients", {
  r <- legacy_service_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic communications", state)
  enrollments <- vapply(f$panel, function(actor) {
    record_consent(r, actor, f$study_id, f$consent_id, TRUE, "consent")
    list_enrollments(r, actor, f$study_id)$id[1]
  }, character(1))
  campaign <- with_mocked_bindings(
    prepare_campaign(r, f$manager, f$round$id, enrollments, "reminder", "Synthetic reminder",
      "Synthetic demonstration only.", command_id = "prepare"),
    content_hash = legacy_service_hash, .package = "delphyr")
  expect_match(campaign$hash, "^[0-9a-f]{64}$")
  stored <- campaign_get(r, f$manager, campaign$id)
  expect_identical(campaign_hash(r, stored), campaign$hash)
  altered <- stored
  altered$body <- "Different text"
  expect_false(identical(campaign_hash(r, altered), campaign$hash))
  released <- release_campaign(r, f$manager, campaign$id, campaign$hash, "Exact synthetic review", "release")
  expect_identical(release_campaign(r, f$manager, campaign$id, campaign$hash, "Exact synthetic review", "release"), released)
  expect_identical(query(r, "SELECT approved_hash FROM ops.campaign_releases WHERE campaign_id=$1", campaign$id)$approved_hash, campaign$hash)
  expect_true(all(startsWith(query(r, "SELECT dedupe_key FROM ops.message_outbox WHERE campaign_id=$1", campaign$id)$dedupe_key, "v2:")))
})

test_that("invitation secrets retain unversioned SHA-256 independently of content hashes", {
  token <- paste(rep("a", 64), collapse = "")
  expect_identical(invitation_hash(token), digest::digest(token, algo = "sha256", serialize = FALSE))
  expect_match(invitation_hash(token), "^[0-9a-f]{64}$")
  expect_error(invitation_hash(paste0("v2:", token)), class = "DEL_UNAUTHORIZED")
})
