administration_repo <- function(env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = Sys.getenv("DELPHYR_TEST_DB_NAME", "delphyr"), user = "postgres", environment = "test")
  withr::defer(DBI::dbDisconnect(r$con), envir = env)
  r
}

test_that("creating studies is an account right and staff are listed without panel links", {
  r <- administration_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  expect_true(get_account_rights(r, f$manager)$can_create_study)
  expect_false(get_account_rights(r, f$panel[[1]])$can_create_study)
  expired <- f$manager
  expired$expires_at <- Sys.time() - 1
  expect_error(get_account_rights(r, expired), class = "DEL_UNAUTHORIZED")
  staff <- list_study_staff(r, f$manager, f$study_id)
  expect_named(staff, c("principal_id", "issuer", "subject", "active", "granted", "revoked"))
  expect_identical(staff$principal_id, f$manager$principal_id)
  expect_identical(staff$granted, "analyse, coordinate, edit, export, manage")
  expect_identical(staff$revoked, "")
  expect_error(list_study_staff(r, f$panel[[1]], f$study_id), class = "DEL_FORBIDDEN")
  other <- demo_study(r, n = 2L, item_count = 1L)
  expect_error(list_study_staff(r, other$manager, f$study_id), class = "DEL_NOT_FOUND")
})

test_that("staff accounts are bound to a stable identity and receive no right by registration", {
  r <- administration_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  subject <- paste0("staff-", uid())
  expect_error(register_staff_account(r, f$panel[[1]], f$study_id, "https://idp.example.invalid", subject, "No right", "a"), class = "DEL_FORBIDDEN")
  expect_error(register_staff_account(r, f$manager, f$study_id, "https://idp.example.invalid", "has space", "Reviewed", "b"), class = "DEL_VALIDATION")
  expect_error(register_staff_account(r, f$manager, f$study_id, "https://idp.example.invalid", subject, " ", "c"), class = "DEL_VALIDATION")
  account <- register_staff_account(r, f$manager, f$study_id, "https://idp.example.invalid", subject, "Analyst of the synthetic study", "register")
  expect_identical(register_staff_account(r, f$manager, f$study_id, "https://idp.example.invalid", subject, "Analyst of the synthetic study", "register"), account)
  expect_equal(DBI::dbGetQuery(r$con, "SELECT count(*)::int AS n FROM identity.memberships WHERE principal_id=$1", params = list(account$id))$n, 0L)
  expect_false(account$id %in% list_study_staff(r, f$manager, f$study_id)$principal_id)
  # A development account is resolved only when the operator provisioned it.
  expect_error(register_staff_account(r, f$manager, f$study_id, "urn:delphyr:demo", paste0("demo-missing-", uid()), "Unknown", "d"), class = "DEL_NOT_FOUND")
  name <- paste0("demo-existing-", uid())
  existing <- provision_demo_principal(r, name)
  expect_identical(register_staff_account(r, f$manager, f$study_id, "urn:delphyr:demo", name, "Provisioned synthetic account", "e")$id, existing)
  execute(r, "UPDATE identity.principals SET active=false WHERE id=$1", existing)
  expect_error(register_staff_account(r, f$manager, f$study_id, "urn:delphyr:demo", name, "Disabled", "f"), class = "DEL_FORBIDDEN")
  set_capability(r, f$manager, f$study_id, account$id, "analyse", TRUE, "grant", reason = "Performs the analysis")
  set_capability(r, f$manager, f$study_id, account$id, "export", TRUE, "grant-export", reason = "Receives the research export")
  set_capability(r, f$manager, f$study_id, account$id, "export", FALSE, "revoke-export", reason = "Export duty ended")
  row <- list_study_staff(r, f$manager, f$study_id)
  row <- row[row$principal_id == account$id, ]
  expect_identical(c(row$issuer, row$subject, row$granted, row$revoked), c("https://idp.example.invalid", subject, "analyse", "export"))
  events <- list_audit_events(r, f$manager, f$study_id, actions = "capability")
  expect_true(all(c("Performs the analysis", "Export duty ended") %in% events$reason))
  expect_true("export revoked" %in% events$detail)
  expect_error(set_capability(r, f$manager, f$study_id, account$id, "audit", TRUE, "bad-reason", reason = ""), class = "DEL_VALIDATION")
  # The rationale belongs to the request: the same key with another rationale
  # is a conflict, the identical retry returns the receipt.
  granted <- set_capability(r, f$manager, f$study_id, account$id, "edit", TRUE, "grant-edit", reason = "Edits the free text")
  expect_identical(set_capability(r, f$manager, f$study_id, account$id, "edit", TRUE, "grant-edit", reason = "Edits the free text"), granted)
  refused <- tryCatch(set_capability(r, f$manager, f$study_id, account$id, "edit", TRUE, "grant-edit", reason = "Another rationale"), error = function(e) e)
  expect_s3_class(refused, "DEL_CONFLICT")
  expect_identical(refused$path, "command.payload")
  expect_identical(sum(list_audit_events(r, f$manager, f$study_id, actions = "capability")$detail == "edit granted"), 1L)
  # Without a rationale the payload is the one earlier releases stored, so
  # their receipts still answer a retry under a fixed key.
  plain <- set_capability(r, f$manager, f$study_id, account$id, "coordinate", TRUE, "auth-coordinate")
  stored <- DBI::dbGetQuery(r$con, "SELECT payload_hash FROM ops.commands WHERE study_id=$1 AND actor_id=$2 AND command_type='capability' AND command_key='auth-coordinate'", params = list(f$study_id, f$manager$principal_id))
  expect_identical(stored$payload_hash, content_hash(list(account$id, "coordinate", TRUE)))
  expect_identical(set_capability(r, f$manager, f$study_id, account$id, "coordinate", TRUE, "auth-coordinate"), plain)
})

test_that("an analyst finds the rounds, analyses and feedback drafts and changes nothing else", {
  r <- administration_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  analyst <- demo_actor(r, provision_demo_principal(r, paste0("demo-analyst-", uid())))
  set_capability(r, f$manager, f$study_id, analyst$principal_id, "analyse", TRUE, "analyst", reason = "Performs the analysis")
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic", state)
  for (actor in f$panel) {
    e <- list_enrollments(r, actor, f$study_id)$id
    record_consent(r, actor, f$study_id, f$consent_id, TRUE, "consent")
    item <- get_questionnaire(r, actor, e)$items$id
    saved <- save_response(r, actor, e, item, list(value = 7L, status = "answered"), 0L, "save")
    submit_round(r, actor, e, setNames(saved$revision, item), "submit")
  }
  transition_round(r, f$manager, f$round$id, "closed", f$round$hash, "Close", "close")
  snapshot <- freeze_round(r, f$manager, f$round$id, "freeze")
  rounds <- list_rounds(r, analyst, f$study_id)
  expect_identical(rounds$snapshot_id, snapshot$id)
  analysis <- run_analysis(r, analyst, rounds$snapshot_id, "analyse")
  expect_identical(list_rounds(r, analyst, f$study_id)$analysis_id, analysis$id)
  expect_identical(get_study_setup(r, analyst, f$study_id)$protocol$study$timezone, "Europe/Berlin")
  draft <- create_feedback(r, analyst, analysis$id, command_id = "feedback")
  expect_identical(get_feedback_candidate(r, analyst, draft$id)$hash, draft$hash)
  # Lifecycle, release and the instrument review stay with management.
  expect_error(release_feedback(r, analyst, draft$id, draft$hash, "release"), class = "DEL_FORBIDDEN")
  expect_error(transition_round(r, analyst, f$round$id, "finalized", f$round$hash, "Synthetic", "finalize"), class = "DEL_FORBIDDEN")
  expect_error(get_round_instrument(r, analyst, f$round$id), class = "DEL_FORBIDDEN")
  for (read in list(list_rounds, get_study_setup)) expect_error(read(r, f$panel[[1]], f$study_id), class = "DEL_FORBIDDEN")
  expect_error(get_feedback_candidate(r, f$panel[[1]], draft$id), class = "DEL_FORBIDDEN")
})

test_that("a study always keeps one person who can manage it", {
  r <- administration_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  own <- f$manager$principal_id
  expect_error(set_capability(r, f$manager, f$study_id, own, "manage", FALSE, "self"), class = "DEL_CONFLICT")
  second <- demo_actor(r, provision_demo_principal(r, paste0("demo-second-", uid())))
  set_capability(r, f$manager, f$study_id, second$principal_id, "manage", TRUE, "second")
  # A disabled account does not count as a remaining manager.
  execute(r, "UPDATE identity.principals SET active=false WHERE id=$1", second$principal_id)
  expect_error(set_capability(r, f$manager, f$study_id, own, "manage", FALSE, "self-2"), class = "DEL_CONFLICT")
  execute(r, "UPDATE identity.principals SET active=true WHERE id=$1", second$principal_id)
  set_capability(r, second, f$study_id, own, "manage", FALSE, "handover")
  expect_error(list_study_staff(r, f$manager, f$study_id), class = "DEL_FORBIDDEN")
  expect_error(set_capability(r, second, f$study_id, second$principal_id, "manage", FALSE, "last"), class = "DEL_CONFLICT")
  expect_identical(list_study_staff(r, second, f$study_id)$granted[list_study_staff(r, second, f$study_id)$principal_id == second$principal_id], "manage")
})

test_that("the panel and decision lists are pseudonymous and limited to staff", {
  r <- administration_repo()
  f <- demo_study(r, n = 2L, item_count = 1L)
  panel <- list_panel(r, f$manager, f$study_id)
  expect_named(panel, c("panelist_id", "group_code", "active", "withdrawn", "rounds_enrolled", "rounds_submitted"))
  expect_setequal(panel$group_code, c("professionals", "public_contributors"))
  expect_identical(panel$rounds_enrolled, c(1L, 1L))
  expect_false(any(vapply(f$panel, function(a) a$principal_id %in% unlist(panel), logical(1))))
  expect_error(list_panel(r, f$panel[[1]], f$study_id), class = "DEL_FORBIDDEN")
  for (state in c("review", "approved", "open")) transition_round(r, f$manager, f$round$id, state, f$round$hash, "Synthetic", state)
  actor <- f$panel[[1]]
  e <- list_enrollments(r, actor, f$study_id)$id
  record_consent(r, actor, f$study_id, f$consent_id, TRUE, "consent")
  item <- get_questionnaire(r, actor, e)$items$id
  saved <- save_response(r, actor, e, item, list(value = 7L, status = "answered"), 0L, "save")
  submit_round(r, actor, e, setNames(saved$revision, item), "submit")
  withdraw_participation(r, f$panel[[2]], f$study_id, "synthetic_retain_prior_data", "withdraw")
  panel <- list_panel(r, f$manager, f$study_id)
  expect_identical(sort(panel$rounds_submitted), c(0L, 1L))
  expect_identical(sum(panel$withdrawn), 1L)
  expect_identical(sum(panel$active), 1L)
  transition_round(r, f$manager, f$round$id, "closed", f$round$hash, "Close", "close")
  snapshot <- freeze_round(r, f$manager, f$round$id, "freeze")
  analysis <- run_analysis(r, f$manager, snapshot$id, "analyse")
  expect_equal(nrow(list_item_decisions(r, f$manager, f$study_id)), 0L)
  record_item_decision(r, f$manager, analysis$id, "I001", "rerate", "No consensus yet", "decide")
  decisions <- list_item_decisions(r, f$manager, f$study_id)
  expect_identical(c(decisions$round_number, decisions$item_code, decisions$disposition, decisions$reason), c("1", "I001", "rerate", "No consensus yet"))
  expect_false(is.na(decisions$decided_at))
  expect_error(list_item_decisions(r, f$panel[[1]], f$study_id), class = "DEL_FORBIDDEN")
  expect_error(publish_consent(r, f$manager, f$study_id, strrep("x", 50001L), "en", "too-long"), class = "DEL_VALIDATION")
})
