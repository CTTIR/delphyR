security_repo <- function(user = "postgres", env = parent.frame()) {
  skip_if(Sys.getenv("DELPHYR_TEST_DB") != "true", "PostgreSQL opt-in required")
  r <- connect_repository(host = "127.0.0.1", port = 55439, dbname = "delphyr", user = user, environment = "test", artifact_root = tempfile("delphyr-security-"))
  withr::defer({
    DBI::dbDisconnect(r$con)
    unlink(r$artifact_root, recursive = TRUE)
  }, envir = env)
  r
}
security_stamp <- function(seconds) format(Sys.time() + seconds, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
security_items <- function(text = "Synthetic item") {
  row <- function(dimension, scale, required) data.frame(item_code = "I001", item_version = 1L, locale = "en", text = text, dimension_code = dimension, scale_code = scale, source_ref = "SRC-1", required = required, display_order = 1L)
  rbind(row("relevance", "relevance_9", TRUE), row("comment", "comment_text", FALSE))
}
security_protocol <- function(code) {
  p <- demo_protocol()
  p$study$code <- code
  p$study$languages <- "en"
  p$instrument$dimensions <- list(list(code = "relevance", scale = "relevance_9"), list(code = "comment", scale = "comment_text"))
  p$instrument$scales$comment_text <- list(type = "free_text", values = list(), anchors = list(low = "not applicable", high = "not applicable"), missing_options = c("unable_to_judge"))
  p$analysis$consensus$min_valid_n <- 2
  p$analysis$consensus$group_policy <- "pooled"
  p
}
# The database server log, when the test can read it: the command named by
# DELPHYR_DB_LOG_COMMAND or the local development container.
security_server_log <- function() {
  command <- Sys.getenv("DELPHYR_DB_LOG_COMMAND")
  if (!nzchar(command) && nzchar(Sys.which("docker"))) {
    running <- suppressWarnings(tryCatch(system2("docker", c("inspect", "--format", "{{.State.Running}}", "delphyr-dev-postgres"), stdout = TRUE, stderr = FALSE), error = function(e) ""))
    if (identical(as.character(running), "true")) command <- "docker logs delphyr-dev-postgres"
  }
  if (!nzchar(command)) {
    return(NULL)
  }
  function() paste(suppressWarnings(system2("sh", c("-c", shQuote(paste(command, "2>&1"))), stdout = TRUE)), collapse = "\n")
}

# One synthetic study conducted with a marked value in every sensitive field,
# including refused and failed operations. Service calls pass through the
# technical log as they do in the application.
security_scenario <- function(admin, r) {
  tag <- toupper(substr(gsub("-", "", uid()), 1, 10))
  canary <- list(
    answer = paste0("CANARY-ANSWER-", tag), email = paste0("canary-", tolower(tag), "@example.invalid"), name = paste0("CANARY-NAME-", tag),
    external = paste0("CANARY-REF-", tag), token = unclass(new_invitation_token()), wrong_token = unclass(new_invitation_token()),
    malformed_token = paste0("CANARY-TOKEN-", tag), secret = paste0("CANARYSECRET", tag, strrep("x", 32)), subject = paste0("canary-subject-", tolower(tag)),
    original = paste0("CANARY-ORIGINAL-", tag), redaction = paste0("CANARY-REDACTION-", tag), campaign = paste0("CANARY-CAMPAIGN-", tag),
    consent = paste0("CANARY-CONSENT-", tag), item = paste0("CANARY-ITEM-", tag), reason = paste0("CANARY-REASON-", tag), password = paste0("CANARY-PASSWORD-", tag)
  )
  lines <- character()
  withr::local_options(list(delphyr.log_level = "info", delphyr.log_sink = function(line) lines <<- c(lines, line)))
  conditions <- list()
  call <- function(name, actor, ...) {
    arguments <- list(...)
    log_operation(name, function() do.call(get(name, mode = "function"), c(list(r, actor), arguments)), component = "app")
  }
  refused <- function(expression) {
    e <- tryCatch(expression, error = function(e) e)
    if (!inherits(e, "error")) stop("An operation expected to be refused succeeded.")
    conditions[[length(conditions) + 1L]] <<- e
    invisible(e)
  }
  code <- paste0("SECURITY-", tag)
  manager <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-manager-", code), TRUE))
  reviewer <- demo_actor(admin, provision_demo_principal(admin, paste0("demo-reviewer-", code)))
  demo <- lapply(1:2, function(i) demo_actor(admin, provision_demo_principal(admin, paste0("demo-", code, "-", i))))
  p <- security_protocol(code)
  study <- call("create_study", manager, p, "create")$id
  consent <- call("publish_consent", manager, study, paste("Synthetic information.", canary$consent), "en", "consent")$id
  for (i in 1:2) call("add_panelist", manager, study, demo[[i]]$principal_id, unlist(p$panel$groups)[1], paste0("panel-", i))
  call("set_capability", manager, study, reviewer$principal_id, "manage", TRUE, "reviewer", canary$reason)
  # A contact is imported, an account registered and its invitation accepted.
  csv <- paste("external_ref,email,display_name,locale,stakeholder_group", paste(canary$external, canary$email, canary$name, "en", unlist(p$panel$groups)[1], sep = ","), sep = "\n")
  preview <- call("preview_panel_import", manager, study, csv)
  receipt <- call("import_panel", manager, study, preview, preview$hash, canary$reason, "import")
  refused(call("import_panel", manager, study, call("preview_panel_import", manager, study, csv), preview$hash, canary$reason, "import-again"))
  issuer <- "https://security-idp.example.invalid"
  account <- call("register_invited_account", manager, study, issuer, canary$subject, canary$reason, "register")$id
  token <- structure(canary$token, class = "delphyr_invitation_token")
  invitation <- call("issue_panel_invitation", manager, study, receipt$invitation_ids[[1]], account, token, 900L, canary$reason, "issue")$id
  config <- new_authentication_config(issuer, canary$secret, "127.0.0.1")
  request <- list(REMOTE_ADDR = "127.0.0.1", HTTP_X_DELPHYR_GATEWAY = canary$secret, HTTP_X_FORWARDED_USER = canary$subject)
  identity <- function(request) log_operation("session_identity", function() authenticated_actor(r, request, config), component = "app")
  refused(identity(utils::modifyList(request, list(HTTP_X_DELPHYR_GATEWAY = paste0(canary$secret, "x")))))
  refused(identity(utils::modifyList(request, list(REMOTE_ADDR = "203.0.113.9"))))
  refused(identity(utils::modifyList(request, list(HTTP_X_FORWARDED_USER = paste0(canary$subject, "-unknown")))))
  member <- identity(request)
  refused(call("accept_panel_invitation", member, study, invitation, canary$malformed_token, TRUE, "accept-malformed"))
  refused(call("accept_panel_invitation", member, study, invitation, canary$wrong_token, TRUE, "accept-wrong"))
  refused(call("preview_panel_invitation", member, study, invitation, canary$wrong_token))
  call("accept_panel_invitation", member, study, invitation, canary$token, TRUE, "accept")
  # A round with a rating and a free-text dimension.
  items <- security_items(paste("Synthetic item", canary$item))
  round <- call("prepare_round", manager, study, items, consent, security_stamp(86400), "round-1")
  for (state in c("review", "approved", "open")) call("transition_round", manager, round$id, state, round$hash, canary$reason, paste("1", state))
  panel <- c(demo, list(member))
  enrollments <- character()
  for (i in seq_along(panel)) {
    actor <- panel[[i]]
    call("record_consent", actor, study, consent, TRUE, "consent")
    e <- call("list_enrollments", actor, study)$id
    enrollments <- c(enrollments, e)
    q <- call("get_questionnaire", actor, e)
    rating <- q$items$id[q$items$dimension_code == "relevance"]
    comment <- q$items$id[q$items$dimension_code == "comment"]
    refused(call("save_response", actor, e, rating, list(value = canary$answer, status = "answered"), 0L, "invalid"))
    call("save_response", actor, e, rating, list(value = 6L + i, status = "answered"), 0L, "rating")
    call("save_response", actor, e, comment, list(value = paste(canary$answer, i), status = "answered"), 0L, "comment")
    refused(call("save_response", actor, e, comment, list(value = paste(canary$answer, "stale"), status = "answered"), 0L, "stale"))
    q <- call("get_questionnaire", actor, e)
    call("submit_round", actor, e, setNames(q$responses$revision, q$responses$round_item_id), "submit")
  }
  # Messages: an adapter that fails, one that refuses, and the local sink.
  campaign <- function(kind, recipients, key) {
    c <- call("prepare_campaign", manager, round$id, recipients, kind, paste("Subject", canary$campaign), paste("Body", canary$campaign), command_id = paste("prepare", key))
    call("release_campaign", manager, c$id, c$hash, canary$reason, paste("release", key))
    c$id
  }
  refused(call("prepare_campaign", manager, round$id, enrollments, paste("kind", canary$campaign), paste("Subject", canary$campaign), paste("Body", canary$campaign), command_id = "prepare-invalid"))
  campaign("deadline_change", enrollments, "failing")
  failing <- new_message_adapter("test_failing", function(message) stop(paste("550 mailbox", message$to, "of", message$display_name, "refused:", message$body)))
  while (!identical(process_campaign_message(r, failing, study), FALSE)) NULL
  campaign("round_start", enrollments[3], "rejecting")
  rejecting <- new_message_adapter("test_rejecting", function(message) list(status = "rejected", reason = paste("Invalid address", message$to)))
  while (!identical(process_campaign_message(r, rejecting, study), FALSE)) NULL
  campaign("round_start", enrollments[1:2], "sink")
  while (!identical(process_campaign_sink(r, study), FALSE)) NULL
  # Closing, analysis, feedback, a decision and a reviewed free-text version.
  call("transition_round", manager, round$id, "closed", round$hash, canary$reason, "close")
  snapshot <- call("freeze_round", manager, round$id, "freeze")$id
  analysis <- call("run_analysis", manager, snapshot, "analyse")$id
  call("record_item_decision", manager, analysis, "I001", "retain", canary$reason, "decide")
  revision <- DBI::dbGetQuery(admin$con, "SELECT id FROM research.response_revisions WHERE study_id=$1 AND value_text=$2", params = list(study, paste(canary$answer, 1)))$id
  refused(call("record_qualitative_source", manager, study, canary$original, "ROUND1-COMMENT-1", "source-mismatch", revision))
  source <- call("record_qualitative_source", manager, study, paste(canary$answer, 1), "ROUND1-COMMENT-1", "source", revision)
  edit <- call("redact_qualitative_source", manager, study, source$id, canary$redaction, canary$reason, "edit")
  call("release_qualitative_edit", reviewer, study, edit$id, edit$hash, canary$reason, "release-edit")
  feedback <- call("create_feedback", manager, analysis, command_id = "feedback", released_edits = edit$id)
  call("release_feedback", manager, feedback$id, feedback$hash, "release-feedback")
  job <- call("request_study_export", manager, study, "research_pseudonymized", "export")
  while (!identical(worker_step(r, study_id = study), FALSE)) NULL
  # A statement the database refuses, as an application defect would cause.
  refused(log_operation("import_panel", function() {
    transaction(r, function() execute(r, "INSERT INTO identity.panel_contacts(id,study_id,external_ref,email,display_name,locale,stakeholder_group,import_id,source_row) VALUES($1,$2,$3,$4,$5,'en',$6,$7,1)", uid(), study, canary$external, canary$email, canary$name, unlist(p$panel$groups)[1], receipt$id))
  }, component = "app"))
  refused(connect_repository(host = "127.0.0.1", port = 1L, dbname = "delphyr", user = "delphyr_runtime", password = canary$password, environment = "test", connect_timeout = 2L))
  list(
    canary = canary, lines = lines, conditions = conditions, study = study, job = job$id,
    principals = c(manager$principal_id, reviewer$principal_id, vapply(panel, function(a) a$principal_id, character(1)))
  )
}
security_cache <- new.env()
security_run <- function(admin, r) {
  if (is.null(security_cache$scenario)) security_cache$scenario <- security_scenario(admin, r)
  security_cache$scenario
}
contains <- function(text, values) vapply(values, function(v) grepl(v, text, fixed = TRUE), logical(1))

test_that("marked values never reach the technical log, conditions, the audit trail or command receipts", {
  admin <- security_repo()
  r <- security_repo("delphyr_runtime")
  s <- security_run(admin, r)
  canaries <- unlist(s$canary)
  # Technical log: valid JSON lines of known fields only.
  entries <- lapply(s$lines, jsonlite::fromJSON)
  fields <- c("time", "level", "correlation_id", "component", "operation", "duration_ms", "reference", "outcome", "error_class", "error_path", "reason")
  expect_gt(length(entries), 60L)
  expect_true(all(vapply(entries, function(x) all(names(x) %in% fields), logical(1))))
  log_text <- paste(s$lines, collapse = "\n")
  expect_false(any(contains(log_text, canaries)))
  expect_false(grepl("canary", log_text, ignore.case = TRUE))
  # No account or study is named; a job or message is the only reference.
  expect_false(any(contains(log_text, c(s$principals, s$study))))
  expect_true(grepl(s$job, log_text, fixed = TRUE))
  found <- function(operation, outcome, class = NULL, reason = NULL) any(vapply(entries, function(x) identical(x$operation, operation) && identical(x$outcome, outcome) && (is.null(class) || identical(x$error_class, class)) && (is.null(reason) || identical(x$reason, reason)), logical(1)))
  expect_true(found("save_response", "refused", "DEL_VALIDATION"))
  expect_true(found("save_response", "refused", "DEL_CONFLICT"))
  expect_true(found("accept_panel_invitation", "refused", "DEL_UNAUTHORIZED"))
  expect_true(found("session_identity", "refused", "DEL_UNAUTHORIZED"))
  expect_true(found("import_panel", "failed", "DEL_STORAGE"))
  expect_true(found("message.deliver", "delivery_unknown", reason = "adapter_outcome_unknown"))
  expect_true(found("message.deliver", "failed", reason = "provider_rejected"))
  expect_true(found("message.deliver", "suppressed", reason = "no_contact"))
  expect_true(found("message.deliver", "sink_recorded"))
  expect_true(found("job.export.research_pseudonymized", "succeeded"))
  # Conditions: what an uncaught failure would print.
  expect_gte(length(s$conditions), 15L)
  messages <- paste(vapply(s$conditions, conditionMessage, character(1)), collapse = "\n")
  expect_false(any(contains(messages, canaries)))
  expect_true(all(vapply(s$conditions[-length(s$conditions)], function(e) inherits(e, "delphyr_error") && grepl("^[0-9a-f]{12}$", e$correlation_id), logical(1))))
  # Audit trail: the rationale is recorded; content, contacts and secrets are not.
  audit <- DBI::dbGetQuery(admin$con, "SELECT action,object_ref,COALESCE(reason,'') AS reason,COALESCE(detail,'') AS detail FROM ops.audit WHERE study_id=$1", params = list(s$study))
  audit_text <- paste(unlist(audit), collapse = "\n")
  expect_gt(nrow(audit), 30L)
  expect_true(grepl(s$canary$reason, audit_text, fixed = TRUE))
  expect_false(any(contains(audit_text, canaries[setdiff(names(canaries), "reason")])))
  # Command receipts hold identifiers and states only.
  receipts <- DBI::dbGetQuery(admin$con, "SELECT command_type,command_key,outcome::text AS outcome FROM ops.commands WHERE study_id=$1", params = list(s$study))
  expect_gt(nrow(receipts), 30L)
  expect_false(any(contains(paste(unlist(receipts), collapse = "\n"), canaries)))
  # The invitation is stored by hash only.
  stored <- DBI::dbGetQuery(admin$con, "SELECT token_hash FROM identity.panel_invitations WHERE study_id=$1", params = list(s$study))$token_hash
  expect_false(identical(stored, s$canary$token))
  expect_identical(stored, digest::digest(s$canary$token, algo = "sha256", serialize = FALSE))
})

test_that("the database server log of the application role holds no marked value", {
  admin <- security_repo()
  r <- security_repo("delphyr_runtime")
  read_log <- security_server_log()
  skip_if(is.null(read_log), "PostgreSQL server log not readable: not executed")
  expect_identical(DBI::dbGetQuery(r$con, "SHOW log_error_verbosity")$log_error_verbosity, "terse")
  s <- security_run(admin, r)
  # Control: one statement the database refuses, run by the owner role and by
  # the application role. The owner's failing row is logged with its values,
  # which proves that the log read here is the live one; the application
  # role's is not.
  tag <- toupper(substr(gsub("-", "", uid()), 1, 10))
  marker <- c(owner = paste0("CONTROL-OWNER-", tag), application = paste0("CONTROL-APPLICATION-", tag))
  refuse <- function(repo, value) {
    tryCatch(
      execute(repo, "INSERT INTO identity.panel_contacts(id,study_id,external_ref,email,display_name,locale,stakeholder_group,import_id,source_row) SELECT $1,study_id,$2,'not-a-reserved-address',$2,'en',stakeholder_group,import_id,2 FROM identity.panel_contacts WHERE study_id=$3 LIMIT 1", uid(), value, s$study),
      error = function(e) "refused"
    )
  }
  expect_identical(refuse(admin, marker[["owner"]]), "refused")
  expect_identical(refuse(r, marker[["application"]]), "refused")
  log <- ""
  for (attempt in 1:40) {
    log <- read_log()
    if (grepl(marker[["owner"]], log, fixed = TRUE)) break
    Sys.sleep(.25)
  }
  lines <- strsplit(log, "\n", fixed = TRUE)[[1]]
  expect_true(any(grepl(marker[["owner"]], lines, fixed = TRUE) & grepl("Failing row contains", lines, fixed = TRUE)))
  expect_gte(sum(grepl("violates check constraint \"panel_contacts_email_check\"", lines, fixed = TRUE)), 2L)
  expect_false(grepl(marker[["application"]], log, fixed = TRUE))
  # Every refusal and failure of the scenario ran under the application role.
  expect_false(any(contains(log, unlist(s$canary))))
  expect_true(grepl("duplicate key value violates unique constraint", log, fixed = TRUE))
})

# A complete study with every kind of object, for the argument checks below.
# `text` supplies the free text of a field kind; the default is plain.
security_fixture <- function(r, text = function(kind) c(item = "Synthetic item", remark = "Synthetic remark", reason = "Synthetic rationale", redaction = "Reviewed remark", external = "F-1", name = "Synthetic Contact")[[kind]]) {
  code <- paste0("FUZZ-", substr(uid(), 1, 8))
  manager <- demo_actor(r, provision_demo_principal(r, paste0("demo-manager-", code), TRUE))
  p <- security_protocol(code)
  study <- create_study(r, manager, p, "create")$id
  consent <- publish_consent(r, manager, study, "Synthetic information.", "en", "consent")$id
  panel <- lapply(1:3, function(i) {
    actor <- demo_actor(r, provision_demo_principal(r, paste0("demo-", code, "-", i)))
    add_panelist(r, manager, study, actor$principal_id, unlist(p$panel$groups)[1], paste0("panel-", i))
    actor
  })
  items <- security_items(text("item"))
  first <- prepare_round(r, manager, study, items, consent, security_stamp(86400), "round-1")
  for (state in c("review", "approved", "open")) transition_round(r, manager, first$id, state, first$hash, text("reason"), paste("1", state))
  for (i in seq_along(panel)) {
    actor <- panel[[i]]
    e <- list_enrollments(r, actor, study)$id
    record_consent(r, actor, study, consent, TRUE, "consent")
    q <- get_questionnaire(r, actor, e)
    save_response(r, actor, e, q$items$id[q$items$dimension_code == "relevance"], list(value = 6L + i, status = "answered"), 0L, "a")
    save_response(r, actor, e, q$items$id[q$items$dimension_code == "comment"], list(value = paste(text("remark"), i), status = "answered"), 0L, "c")
    q <- get_questionnaire(r, actor, e)
    submit_round(r, actor, e, setNames(q$responses$revision, q$responses$round_item_id), "submit")
  }
  transition_round(r, manager, first$id, "closed", first$hash, text("reason"), "close")
  snapshot <- freeze_round(r, manager, first$id, "freeze")$id
  analysis <- run_analysis(r, manager, snapshot, "analyse")$id
  feedback <- create_feedback(r, manager, analysis, command_id = "feedback")
  release_feedback(r, manager, feedback$id, feedback$hash, "release")
  revision <- query(r, "SELECT id FROM research.response_revisions WHERE study_id=$1 AND value_text=$2", study, paste(text("remark"), 1))$id
  source <- record_qualitative_source(r, manager, study, paste(text("remark"), 1), "R1-C1", "source", revision)
  edit <- redact_qualitative_source(r, manager, study, source$id, text("redaction"), text("reason"), "edit")
  theme <- create_qualitative_theme(r, manager, study, "T1", 1L, "Theme", "Definition", "theme")
  second <- prepare_round(r, manager, study, items, consent, security_stamp(86400), "round-2")
  assign_feedback(r, manager, second$id, feedback$id, "assign")
  for (state in c("review", "approved", "open")) transition_round(r, manager, second$id, state, second$hash, text("reason"), paste("2", state))
  enrollment <- list_enrollments(r, panel[[1]], study)
  enrollment <- enrollment$id[enrollment$number == 2L]
  q <- get_questionnaire(r, panel[[1]], enrollment)
  campaign <- prepare_campaign(r, manager, second$id, enrollment, "reminder", "Synthetic subject", "Synthetic body.", command_id = "campaign")
  release_campaign(r, manager, campaign$id, campaign$hash, text("reason"), "release-campaign")
  csv <- paste("external_ref,email,display_name,locale,stakeholder_group", paste(text("external"), "fuzz-contact@example.invalid", text("name"), "en", "professionals", sep = ","), sep = "\n")
  preview <- preview_panel_import(r, manager, study, csv)
  receipt <- import_panel(r, manager, study, preview, preview$hash, "Synthetic contacts", "import")
  account <- register_invited_account(r, manager, study, "https://fuzz-idp.example.invalid", paste0("member-", uid()), "Stable account", "register")$id
  token <- new_invitation_token()
  invitation <- issue_panel_invitation(r, manager, study, receipt$invitation_ids[[1]], account, token, 900L, "Approved account", "issue")$id
  job <- request_study_export(r, manager, study, "study_summary", "export")
  repeat {
    operation <- get_operation(r, manager, job$id)
    if (operation$state %in% c("succeeded", "dead_letter")) break
    worker_step(r, study_id = study)
  }
  ids <- list(
    study_id = study, round_id = second$id, snapshot_id = snapshot, analysis_id = analysis, feedback_id = feedback$id, replacement_id = feedback$id,
    enrollment_id = enrollment, enrollment_ids = enrollment, campaign_id = campaign$id, invitation_id = invitation, draft_id = receipt$invitation_ids[[1]],
    principal_id = account, artifact_id = operation$result_ref, operation_id = job$id, receipt_id = receipt$id, source_id = source$id, theme_id = theme$id,
    edit_id = edit$id, message_id = query(r, "SELECT id FROM ops.message_outbox WHERE campaign_id=$1", campaign$id)$id, consent_version_id = consent,
    response_revision_id = revision, round_item_id = q$items$id[1], panelist_id = query(r, "SELECT id FROM research.panelists WHERE study_id=$1 LIMIT 1", study)$id
  )
  stopifnot(all(lengths(ids) == 1L), !anyNA(unlist(ids)))
  defaults <- function() {
    directory <- tempfile("delphyr-security-out-")
    dir.create(directory)
    list(
      command_id = uid(), reason = "Synthetic rationale", expected_hash = strrep("0", 64), token = token, confirmed = TRUE,
      group_code = unlist(p$panel$groups)[1], protocol = p, decision = "include", code = "T2", version = 1L, label = "Label", definition = "Definition",
      qualitative = list(), released_edits = character(), export = FALSE, preview = preview, from = NULL, to = NULL, actions = NULL, limit = 10L,
      kind = "reminder", subject = "Synthetic", body = "Synthetic", locale = "en", template_version = "1", items = items, deadline = security_stamp(86400),
      profile = "study_summary", csv = csv, schema_version = "1.0", delimiter = ",", text = "Synthetic text", item_code = "I001", item_version = 1L,
      dimension_code = "relevance", previous_version = 1L, current_version = 2L, comparable = TRUE, disposition = "retain",
      parents = data.frame(item_code = "I001", item_version = 1L), children = data.frame(item_code = "I001", item_version = 2L), relation = "revision",
      source_ref = "SRC", fields = list(funding = "None"), expected_version = 0L, issuer = "https://fuzz-idp.example.invalid", subject = "fuzz-subject",
      ttl_seconds = 900L, not_before = NULL, impact_note = "Synthetic", participant_note = "Synthetic", resolution = "abandon",
      response = list(value = 5L, status = "answered"), expected_revision = 0L, capability = "edit", enabled = TRUE, retention_policy = "retain",
      expected_revision_set = setNames(integer(), character()), target = "closed", output_dir = directory, periods = NULL
    )
  }
  list(manager = manager, panel = panel, study_id = study, ids = ids, defaults = defaults, protocol = p, items = items, round = second, first = first, edit = edit, code = code)
}
# Calls every exported service once per chosen argument, with that argument
# replaced and all others valid, and records what was bound to a statement.
security_probe <- function(r, f, arguments_of, replace, hit, actors = list(manager = f$manager, panel = f$panel[[1]])) {
  original_query <- query
  original_execute <- execute
  seen <- FALSE
  record <- function(parameters) for (x in parameters) if (is.character(x) && any(hit(x), na.rm = TRUE)) seen <<- TRUE
  local_mocked_bindings(
    query = function(repo, sql, ...) {
      record(list(...))
      original_query(repo, sql, ...)
    },
    execute = function(repo, sql, ...) {
      record(list(...))
      original_execute(repo, sql, ...)
    }
  )
  namespace <- asNamespace("delphyr")
  results <- list()
  for (name in sort(getNamespaceExports(namespace))) {
    service <- get(name, namespace)
    if (!is.function(service)) next
    formal <- names(formals(service))
    if (length(formal) < 3L || !identical(formal[1:2], c("repo", "actor"))) next
    for (target in arguments_of(formal[-(1:2)], f$defaults())) {
      for (role in names(actors)) {
        values <- f$defaults()
        arguments <- list()
        for (n in formal[-(1:2)]) {
          if (n %in% names(f$ids)) {
            arguments[[n]] <- f$ids[[n]]
          } else if (n %in% names(values)) {
            arguments[n] <- list(values[[n]])
          } else {
            stop("No default for ", name, "$", n)
          }
        }
        arguments[[target]] <- replace(target, arguments[[target]])
        seen <- FALSE
        outcome <- tryCatch(
          {
            do.call(service, c(list(r, actors[[role]]), arguments))
            "accepted"
          },
          error = function(e) if (inherits(e, "delphyr_error")) paste(e$code, e$path) else paste("unstructured", class(e)[1])
        )
        unlink(values$output_dir, recursive = TRUE)
        results[[length(results) + 1L]] <- data.frame(service = name, argument = target, role = role, outcome = outcome, bound = seen)
      }
    }
  }
  do.call(rbind, results)
}

test_that("malformed identifiers are refused before any statement is bound", {
  r <- security_repo()
  withr::local_options(list(delphyr.log_level = "off"))
  f <- security_fixture(r)
  payload <- "CANARY-ID' OR 1=1; --"
  x <- security_probe(r, f,
    arguments_of = function(formal, defaults) intersect(formal, names(f$ids)),
    replace = function(target, value) if (target == "enrollment_ids") c(value, payload) else payload,
    hit = function(x) grepl("CANARY-ID", x, fixed = TRUE)
  )
  expect_gt(nrow(x), 180L)
  expect_identical(sum(x$bound), 0L)
  expect_true(all(grepl("^DEL_(NOT_FOUND|FORBIDDEN|VALIDATION|UNAUTHORIZED|CONFLICT) ", x$outcome)), info = paste(unique(x$outcome), collapse = "; "))
  # Every identifier argument of every service is refused by its format for
  # at least one of the two roles; the other role is refused earlier by right.
  pairs <- split(x$outcome, paste(x$service, x$argument))
  unchecked <- names(pairs)[!vapply(pairs, function(o) any(o == "DEL_NOT_FOUND object"), logical(1))]
  expect_identical(unchecked, character())
})

test_that("oversized text is refused by every service and never stored", {
  r <- security_repo()
  withr::local_options(list(delphyr.log_level = "off"))
  f <- security_fixture(r)
  big <- strrep("A", 2L * 1024L * 1024L)
  x <- security_probe(r, f,
    arguments_of = function(formal, defaults) formal[vapply(formal, function(n) !n %in% c(names(f$ids), "output_dir") && is.character(defaults[[n]]) && length(defaults[[n]]) == 1L, logical(1))],
    replace = function(target, value) big,
    hit = function(x) nchar(x, type = "bytes") > 1000000L
  )
  expect_gt(nrow(x), 200L)
  expect_identical(x[x$bound | !grepl("^DEL_(NOT_FOUND|FORBIDDEN|VALIDATION|UNAUTHORIZED|CONFLICT) ", x$outcome), c("service", "argument", "role", "outcome")], x[0, c("service", "argument", "role", "outcome")])
  # Nested text: a response, an item, a documentation field and a protocol.
  record_consent(r, f$panel[[1]], f$study_id, f$ids$consent_version_id, TRUE, "consent-2")
  q <- get_questionnaire(r, f$panel[[1]], f$ids$enrollment_id)
  comment <- q$items$id[q$items$dimension_code == "comment"]
  expect_identical(tryCatch(save_response(r, f$panel[[1]], f$ids$enrollment_id, comment, list(value = big, status = "answered"), 0L, "oversized"), error = function(e) e$path), "value_text")
  # The rationale of every command has one limit, whatever the service checks.
  expect_identical(tryCatch(transition_round(r, f$manager, f$round$id, "closed", f$round$hash, big, "oversized"), error = function(e) e$path), "reason")
  expect_identical(tryCatch(cancel_campaign(r, f$manager, f$ids$campaign_id, big, "oversized"), error = function(e) e$path), "reason")
  expect_identical(tryCatch(record_item_decision(r, f$manager, f$ids$analysis_id, "I001", "retain", big, "oversized"), error = function(e) e$path), "reason")
  expect_identical(tryCatch(revoke_panel_invitation(r, f$manager, f$study_id, f$ids$invitation_id, big, "oversized"), error = function(e) e$path), "reason")
  expect_identical(transition_round(r, f$manager, f$round$id, "closed", f$round$hash, strrep("A", 10000L), "limit")$state, "closed")
  items <- f$items
  items$text[1] <- big
  expect_identical(tryCatch(prepare_round(r, f$manager, f$study_id, items, f$ids$consent_version_id, security_stamp(86400), "oversized"), error = function(e) e$path), "items.text")
  expect_error(record_study_documentation(r, f$manager, f$study_id, list(funding = big), 0L, "Synthetic", "oversized"), class = "DEL_VALIDATION")
  p <- f$protocol
  p$study$title <- big
  latest <- query(r, "SELECT hash FROM research.protocol_versions WHERE study_id=$1 ORDER BY version DESC LIMIT 1", f$study_id)$hash
  expect_identical(tryCatch(amend_protocol(r, f$manager, f$study_id, p, latest, "Synthetic", "oversized"), error = function(e) e$path), "protocol.size")
  p$study$code <- paste0("FUZZ-BIG-", substr(uid(), 1, 8))
  expect_identical(tryCatch(create_study(r, f$manager, p, "oversized"), error = function(e) e$path), "protocol.size")
  expect_identical(tryCatch(preview_panel_import(r, f$manager, f$study_id, strrep("x", 1024L * 1024L + 1L)), error = function(e) e$path), "panel_import.size")
  rows <- paste(c("external_ref,email,display_name,locale,stakeholder_group", sprintf("R-%d,row-%d@example.invalid,Synthetic,en,professionals", 1:10001, 1:10001)), collapse = "\n")
  expect_identical(tryCatch(preview_panel_import(r, f$manager, f$study_id, rows), error = function(e) e$path), "panel_import.rows")
  expect_identical(query(r, "SELECT count(*)::int AS n FROM research.studies WHERE code=$1", p$study$code)$n, 0L)
})

test_that("statement payloads in text are stored literally and change nothing else", {
  r <- security_repo()
  withr::local_options(list(delphyr.log_level = "off"))
  f <- security_fixture(r)
  payload <- "x'); DROP TABLE research.studies; UPDATE identity.capabilities SET revoked_at=NULL; --"
  before <- query(r, "SELECT (SELECT count(*) FROM research.studies)::int AS studies,(SELECT count(*) FROM identity.capabilities WHERE study_id=$1)::int AS capabilities", f$study_id)
  q <- get_questionnaire(r, f$panel[[1]], f$ids$enrollment_id)
  comment <- q$items$id[q$items$dimension_code == "comment"]
  record_consent(r, f$panel[[1]], f$study_id, f$ids$consent_version_id, TRUE, "consent-2")
  save_response(r, f$panel[[1]], f$ids$enrollment_id, comment, list(value = payload, status = "answered"), 0L, "payload")
  stored <- get_questionnaire(r, f$panel[[1]], f$ids$enrollment_id)$responses
  expect_identical(stored$value_text[stored$round_item_id == comment], payload)
  expect_identical(transition_round(r, f$manager, f$round$id, "closed", f$round$hash, payload, payload)$state, "closed")
  events <- list_audit_events(r, f$manager, f$study_id)
  expect_true(payload %in% events$reason)
  theme <- create_qualitative_theme(r, f$manager, f$study_id, "T9", 1L, payload, payload, "payload-theme")
  expect_identical(query(r, "SELECT label FROM research.qualitative_themes WHERE id=$1", theme$id)$label, payload)
  documentation <- record_study_documentation(r, f$manager, f$study_id, list(funding = payload), 0L, payload, "payload-documentation")
  expect_identical(get_study_documentation(r, f$manager, f$study_id)$fields$funding, payload)
  # Payloads where an identifier, a code or a filter is expected are refused.
  expect_error(get_round_instrument(r, f$manager, payload), class = "DEL_NOT_FOUND")
  expect_error(list_audit_events(r, f$manager, f$study_id, actions = payload), class = "DEL_VALIDATION")
  expect_error(request_study_export(r, f$manager, f$study_id, payload, "payload-export"), class = "DEL_VALIDATION")
  expect_error(set_capability(r, f$manager, f$study_id, f$ids$principal_id, payload, TRUE, "payload-capability"), class = "DEL_VALIDATION")
  after <- query(r, "SELECT (SELECT count(*) FROM research.studies)::int AS studies,(SELECT count(*) FROM identity.capabilities WHERE study_id=$1)::int AS capabilities", f$study_id)
  expect_identical(after, before)
})

test_that("no exported spreadsheet cell can be read as a formula", {
  cells <- data.frame(text = c("=1+1", "+2", "-3+4", "@SUM(A1)", "\t=1+1", " =1+1", "plain", "-5", NA, ""), n = 1:10, stringsAsFactors = FALSE)
  masked <- safe_csv(cells)
  expect_identical(masked$text, c("'=1+1", "'+2", "'-3+4", "'@SUM(A1)", "'\t=1+1", "' =1+1", "plain", "'-5", NA, ""))
  expect_identical(masked$n, cells$n)
  r <- security_repo()
  withr::local_options(list(delphyr.log_level = "off"))
  triggers <- c(item = "=HYPERLINK(1) item", remark = "+1 remark", reason = "-2+3 rationale", redaction = "@SUM(A1) reviewed", external = "+REF-1", name = "=1+1 contact")
  f <- security_fixture(r, text = function(kind) triggers[[kind]])
  reviewer <- demo_actor(r, provision_demo_principal(r, paste0("demo-reviewer-", f$code)))
  set_capability(r, f$manager, f$study_id, reviewer$principal_id, "manage", TRUE, "reviewer", triggers[["reason"]])
  release_qualitative_edit(r, reviewer, f$study_id, f$edit$id, f$edit$hash, triggers[["reason"]], "release-edit")
  for (capability in c("contacts_export", "audit")) set_capability(r, f$manager, f$study_id, f$manager$principal_id, capability, TRUE, capability, triggers[["reason"]])
  record_item_decision(r, f$manager, f$ids$analysis_id, "I001", "retain", triggers[["reason"]], "decide")
  record_study_documentation(r, f$manager, f$study_id, list(funding = "=1+1 funding", authors_responsibilities = "@author"), 0L, triggers[["reason"]], "documentation")
  directories <- character()
  finish <- function(job, manager = f$manager, study = f$study_id) {
    repeat {
      operation <- get_operation(r, manager, job$id)
      if (operation$state %in% c("succeeded", "dead_letter")) break
      worker_step(r, study_id = study)
    }
    operation
  }
  for (profile in c("research_pseudonymized", "study_summary", "audit_restricted", "contacts_restricted")) {
    operation <- finish(request_study_export(r, f$manager, f$study_id, profile, paste("export", profile)))
    expect_identical(operation$state, "succeeded")
    directories[profile] <- download_artifact(r, f$manager, operation$result_ref)
  }
  # The round export never carries free text; a round with a free-text
  # dimension is refused there and exported by the reviewed study profile.
  expect_identical(finish(request_export(r, f$manager, f$ids$snapshot_id, "export-round"))$error_code, "DEL_FORBIDDEN")
  # A rating-only study whose group names and item code start like formulas.
  code <- paste0("FORMULA-", substr(uid(), 1, 8))
  manager <- demo_actor(r, provision_demo_principal(r, paste0("demo-manager-", code), TRUE))
  p <- demo_protocol()
  p$study$code <- code
  p$study$languages <- "en"
  p$panel$groups <- c("=1+1 group", "+group")
  p$analysis$consensus$group_policy <- "pooled"
  study <- create_study(r, manager, p, "create")$id
  consent <- publish_consent(r, manager, study, "Synthetic information.", "en", "consent")$id
  members <- lapply(1:2, function(i) {
    actor <- demo_actor(r, provision_demo_principal(r, paste0("demo-", code, "-", i)))
    add_panelist(r, manager, study, actor$principal_id, p$panel$groups[i], paste0("panel-", i))
    actor
  })
  round <- prepare_round(r, manager, study, data.frame(item_code = "-1-1", item_version = 1L, locale = "en", text = "=1+1 item", dimension_code = "relevance", scale_code = "relevance_9", source_ref = "@SRC", required = TRUE, display_order = 1L), consent, security_stamp(86400), "round")
  for (state in c("review", "approved", "open")) transition_round(r, manager, round$id, state, round$hash, "Synthetic", state)
  for (actor in members) {
    record_consent(r, actor, study, consent, TRUE, "consent")
    e <- list_enrollments(r, actor, study)$id
    q <- get_questionnaire(r, actor, e)
    save_response(r, actor, e, q$items$id, list(value = 7L, status = "answered"), 0L, "save")
    q <- get_questionnaire(r, actor, e)
    submit_round(r, actor, e, setNames(q$responses$revision, q$responses$round_item_id), "submit")
  }
  transition_round(r, manager, round$id, "closed", round$hash, "Close", "close")
  snapshot <- freeze_round(r, manager, round$id, "freeze")$id
  operation <- finish(request_export(r, manager, snapshot, "export"), manager, study)
  expect_identical(operation$state, "succeeded")
  directories["research_round"] <- download_artifact(r, manager, operation$result_ref)
  directories["report"] <- tempfile("delphyr-security-report-")
  directories["participant"] <- tempfile("delphyr-security-feedback-")
  for (directory in directories[c("report", "participant")]) dir.create(directory)
  withr::defer(unlink(directories[c("report", "participant")], recursive = TRUE))
  expect_error(prepare_report_data(r, f$manager, f$ids$snapshot_id), class = "DEL_FORBIDDEN")
  write_report_data(prepare_report_data(r, manager, snapshot), directories[["report"]])
  record_consent(r, f$panel[[1]], f$study_id, f$ids$consent_version_id, TRUE, "consent-2")
  write_participant_feedback(r, f$panel[[1]], f$ids$enrollment_id, directories[["participant"]])
  files <- unlist(lapply(directories, list.files, pattern = "[.]csv$", full.names = TRUE))
  expect_gt(length(files), 25L)
  number <- "^-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$"
  unsafe <- character()
  masked <- 0L
  for (file in files) {
    # A table without rows and columns is written as an empty file.
    if (!any(nzchar(gsub("\"", "", readLines(file, warn = FALSE), fixed = TRUE)))) next
    x <- utils::read.csv(file, colClasses = "character", check.names = FALSE, na.strings = character(), encoding = "UTF-8")
    values <- unlist(c(names(x), x), use.names = FALSE)
    bad <- grepl("^[[:space:]]*[=+@-]", values) & !grepl(number, values)
    if (any(bad)) unsafe <- c(unsafe, paste(basename(dirname(file)), basename(file), values[bad]))
    masked <- masked + sum(grepl("^'[[:space:]]*[=+@-]", values))
  }
  expect_identical(unsafe, character())
  # The marked texts did reach the files, each behind a text marker.
  expect_gt(masked, 20L)
  all_text <- paste(unlist(lapply(files, readLines, warn = FALSE)), collapse = "\n")
  for (value in c(triggers[c("item", "reason", "redaction", "external", "name")], "=1+1 group", "-1-1")) expect_true(grepl(paste0("'", value), all_text, fixed = TRUE), info = value)
})

test_that("known identifiers of another study or person give no access", {
  r <- security_repo()
  withr::local_options(list(delphyr.log_level = "off"))
  f <- security_fixture(r)
  other <- security_fixture(r)
  x <- security_probe(r, f,
    arguments_of = function(formal, defaults) formal[1], replace = function(target, value) value, hit = function(x) FALSE,
    actors = list(foreign_manager = other$manager, foreign_member = other$panel[[1]], other_member = f$panel[[2]])
  )
  expect_gt(nrow(x), 220L)
  refused <- grepl("^DEL_(NOT_FOUND|FORBIDDEN|UNAUTHORIZED) ", x$outcome)
  # A manager and a member of another study are refused by every service.
  expect_identical(x$service[!refused & x$role != "other_member"], character())
  # Another member of the same study reaches only services about that
  # member's own participation, and reads only own enrollments there.
  expect_setequal(x$service[!refused & x$role == "other_member"], c("get_capabilities", "list_enrollments", "record_consent", "withdraw_participation"))
  own <- list_enrollments(r, f$panel[[2]], f$study_id)$id
  expect_length(own, 2L)
  expect_false(f$ids$enrollment_id %in% own)
  expect_identical(get_capabilities(r, f$panel[[2]], f$study_id), "panel")
})
