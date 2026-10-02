administration_repo <- function(env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "Opt-in PostgreSQL tests")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = "postgres", environment = "test")
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
