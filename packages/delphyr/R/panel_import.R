panel_csv_bytes <- function(csv) {
  ensure(is.raw(csv) || (is.character(csv) && length(csv) == 1L && !is.na(csv)), "panel_import.csv")
  bytes <- if (is.raw(csv)) csv else charToRaw(enc2utf8(csv))
  ensure(length(bytes) > 0L && length(bytes) <= 1024L * 1024L, "panel_import.size")
  ensure(!any(bytes == as.raw(0)), "panel_import.encoding")
  text <- rawToChar(bytes)
  ensure(!is.na(iconv(text, from = "UTF-8", to = "UTF-8", sub = NA)), "panel_import.encoding")
  list(bytes = bytes, text = text, hash = digest::digest(bytes, algo = "sha256", serialize = FALSE))
}
panel_normalize_email <- function(email) {
  if (!scalar_text(email) || nchar(email, type = "bytes") > 254L || grepl("[[:space:][:cntrl:]]", email)) {
    return(NA_character_)
  }
  parts <- strsplit(email, "@", fixed = TRUE)[[1]]
  if (length(parts) != 2L || !nzchar(parts[2]) || nchar(parts[1], type = "bytes") > 64L ||
    !grepl("^[A-Za-z0-9][A-Za-z0-9._+%=-]*$", parts[1]) || grepl("..", parts[1], fixed = TRUE) || endsWith(parts[1], ".")) {
    return(NA_character_)
  }
  domain <- tolower(parts[2])
  if (!endsWith(domain, ".invalid") || !grepl("^[a-z0-9.-]+$", domain) || grepl("..", domain, fixed = TRUE)) {
    return(NA_character_)
  }
  labels <- strsplit(domain, ".", fixed = TRUE)[[1]]
  if (any(nchar(labels) > 63L) || any(!grepl("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", labels))) {
    return(NA_character_)
  }
  paste0(parts[1], "@", domain)
}
panel_preview_value <- function(repo, study_id, csv, schema_version, delimiter) {
  ensure(identical(schema_version, "1.0"), "panel_import.schema_version")
  ensure(length(delimiter) == 1L && delimiter %in% c(",", ";"), "panel_import.delimiter")
  input <- panel_csv_bytes(csv)
  issues <- data.frame(row = integer(), column = character(), code = character(), stringsAsFactors = FALSE)
  add <- function(row, column, code) issues <<- rbind(issues, data.frame(row = as.integer(row), column = column, code = code))
  fields <- c("external_ref", "email", "display_name", "locale", "stakeholder_group")
  text <- sub("^\ufeff", "", input$text)
  # read.table(text=) adds a final connection newline; remove one existing terminator.
  # Hashing continues to use the untouched uploaded bytes.
  text <- sub("\r?\n$", "", text)
  rows <- tryCatch(withCallingHandlers(
    utils::read.table(
      text = text, header = TRUE, sep = delimiter,
      quote = '"', comment.char = "", colClasses = "character", check.names = FALSE, fill = FALSE,
      blank.lines.skip = FALSE, na.strings = character(), row.names = NULL, stringsAsFactors = FALSE
    ),
    warning = function(w) stop("csv parse failed")
  ), error = function(e) NULL)
  if (is.null(rows)) {
    add(0L, "", "csv_parse_error")
    rows <- as.data.frame(setNames(rep(list(character()), length(fields)), fields))
  } else if (anyDuplicated(names(rows)) || !setequal(names(rows), fields) || ncol(rows) != length(fields)) {
    add(0L, "", "csv_schema_columns")
    rows <- as.data.frame(setNames(rep(list(character()), length(fields)), fields))
  } else {
    rows <- rows[, fields, drop = FALSE]
  }
  if (nrow(rows) == 0L) add(0L, "", "empty_import")
  ensure(nrow(rows) <= 10000L, "panel_import.rows")
  protocol <- protocol_for(repo, study_id)$config
  groups <- unlist(protocol$panel$groups)
  locales <- unlist(protocol$study$languages)
  rows$source_row <- seq_len(nrow(rows))
  rows$normalized_email <- vapply(rows$email, panel_normalize_email, character(1))
  for (i in seq_len(nrow(rows))) {
    if (!scalar_text(rows$external_ref[i]) || nchar(rows$external_ref[i], type = "bytes") > 128L || grepl("[[:cntrl:]]", rows$external_ref[i])) add(i, "external_ref", "invalid_external_ref")
    if (!scalar_text(rows$display_name[i]) || nchar(rows$display_name[i], type = "bytes") > 200L || grepl("[[:cntrl:]]", rows$display_name[i])) add(i, "display_name", "invalid_display_name")
    if (is.na(rows$normalized_email[i])) add(i, "email", "synthetic_email_required")
    if (!rows$locale[i] %in% locales) add(i, "locale", "unsupported_locale")
    if (!rows$stakeholder_group[i] %in% groups) add(i, "stakeholder_group", "unknown_group")
  }
  for (field in c("external_ref", "normalized_email")) {
    values <- rows[[field]]
    dup <- !is.na(values) & (duplicated(values) | duplicated(values, fromLast = TRUE))
    for (i in which(dup)) add(i, if (field == "normalized_email") "email" else field, "duplicate_in_file")
  }
  # Case variants are reviewed, never silently merged into an account identity.
  folded <- tolower(rows$normalized_email)
  case_dup <- !is.na(folded) & (duplicated(folded) | duplicated(folded, fromLast = TRUE))
  for (i in which(case_dup)) if (length(unique(rows$normalized_email[!is.na(folded) & folded == folded[i]])) > 1L) add(i, "email", "email_case_review")
  existing <- query(repo, "SELECT external_ref,email FROM identity.panel_contacts WHERE study_id=$1", study_id)
  for (i in seq_len(nrow(rows))) {
    if (rows$external_ref[i] %in% existing$external_ref) add(i, "external_ref", "existing_external_ref")
    if (!is.na(rows$normalized_email[i]) && rows$normalized_email[i] %in% existing$email) {
      add(i, "email", "existing_email")
    } else if (!is.na(folded[i]) && folded[i] %in% tolower(existing$email)) add(i, "email", "existing_email_case_review")
  }
  value <- list(
    study_id = study_id, schema_version = schema_version, delimiter = delimiter, file_hash = input$hash,
    rows = rows, issues = issues, valid = nrow(issues) == 0L, accepted_rows = if (nrow(issues)) 0L else nrow(rows),
    rejected_rows = if (nrow(issues)) nrow(rows) else 0L
  )
  value$hash <- content_hash(value)
  # Source bytes stay only in the caller's restricted preview, not audit/receipts.
  value$csv <- input$bytes
  structure(value, class = c("delphyr_panel_preview", "list"))
}
#' Preview a synthetic panel CSV with blocking duplicate review
#' @param repo Development/test repository.
#' @param actor Current study coordinator.
#' @param study_id Study UUID.
#' @param csv UTF-8 CSV bytes or one CSV text string, not a file path.
#' @param schema_version Explicit supported schema, 1.0.
#' @param delimiter Explicit comma or semicolon.
#' @return Restricted preview with rows, row/column issues, exact file hash and approval hash.
#' @export
preview_panel_import <- function(repo, actor, study_id, csv, schema_version = "1.0", delimiter = ",") {
  ensure(repo$environment %in% c("development", "test"), "panel_import.synthetic_only", "DEL_FORBIDDEN")
  authorize(repo, actor, study_id, "coordinate")
  panel_preview_value(repo, study_id, csv, schema_version, delimiter)
}
#' Atomically import exactly reviewed synthetic contacts as unbound drafts
#' @param repo Development/test repository.
#' @param actor Current study coordinator.
#' @param study_id Study UUID.
#' @param preview Output of preview_panel_import().
#' @param expected_hash Exact preview hash explicitly reviewed by the coordinator.
#' @param reason Approval rationale.
#' @param command_id Idempotency key for this approved import.
#' @return Receipt id, file/preview hashes, counts and opaque invitation-draft IDs.
#' @export
import_panel <- function(repo, actor, study_id, preview, expected_hash, reason, command_id) {
  transaction(repo, function() {
    ensure(repo$environment %in% c("development", "test"), "panel_import.synthetic_only", "DEL_FORBIDDEN")
    authorize(repo, actor, study_id, "coordinate")
    ensure(inherits(preview, "delphyr_panel_preview") && identical(preview$study_id, study_id) && scalar_text(reason), "panel_import.preview")
    original <- unclass(preview)
    original$hash <- NULL
    original$csv <- NULL
    ensure(identical(content_hash(original), preview$hash) && identical(preview$hash, expected_hash), "panel_import.hash", "DEL_CONFLICT")
    bytes <- panel_csv_bytes(preview$csv)
    ensure(identical(bytes$hash, preview$file_hash), "panel_import.file_hash", "DEL_CONFLICT")
    query(repo, "SELECT id FROM research.studies WHERE id=$1 FOR UPDATE", study_id)
    command(repo, actor, study_id, "panel_import", command_id, list(preview_hash = expected_hash, file_hash = bytes$hash, reason = reason), function() {
      study <- one(query(repo, "SELECT state FROM research.studies WHERE id=$1", study_id))
      ensure(study$state %in% c("draft", "active"), "panel_import.study_state", "DEL_CONFLICT")
      current <- panel_preview_value(repo, study_id, bytes$bytes, preview$schema_version, preview$delimiter)
      ensure(isTRUE(current$valid), "panel_import.review_required", "DEL_VALIDATION")
      ensure(identical(current$hash, expected_hash), "panel_import.preview_changed", "DEL_CONFLICT")
      receipt <- uid()
      report <- list(valid = TRUE, issues = list(), accepted_rows = nrow(current$rows), rejected_rows = 0L)
      execute(repo, "INSERT INTO identity.panel_import_receipts(id,study_id,file_hash,preview_hash,schema_version,accepted_rows,rejected_rows,actor_id,reason,validation_report) VALUES($1,$2,$3,$4,$5,$6,0,$7,$8,$9::jsonb)", receipt, study_id, current$file_hash, current$hash, current$schema_version, nrow(current$rows), actor$principal_id, reason, json(report))
      invitations <- character()
      for (i in seq_len(nrow(current$rows))) {
        row <- current$rows[i, ]
        contact <- uid()
        invitation <- uid()
        execute(repo, "INSERT INTO identity.panel_contacts(id,study_id,external_ref,email,display_name,locale,stakeholder_group,import_id,source_row) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)", contact, study_id, row$external_ref, row$normalized_email, row$display_name, row$locale, row$stakeholder_group, receipt, i)
        execute(repo, "INSERT INTO identity.panel_invitation_drafts(id,study_id,contact_id,import_id) VALUES($1,$2,$3,$4)", invitation, study_id, contact, receipt)
        invitations <- c(invitations, invitation)
      }
      list(id = receipt, file_hash = current$file_hash, preview_hash = current$hash, accepted_rows = nrow(current$rows), rejected_rows = 0L, invitation_ids = invitations)
    })
  })
}
#' Retrieve a minimal panel import receipt through current coordination rights
#' @param repo Repository.
#' @param actor Study coordinator.
#' @param receipt_id Receipt UUID.
#' @return Receipt metadata and invitation IDs without contact values.
#' @export
get_panel_import_receipt <- function(repo, actor, receipt_id) {
  valid_id(receipt_id)
  x <- one(query(repo, "SELECT study_id FROM identity.panel_import_receipts WHERE id=$1", receipt_id))
  authorize(repo, actor, x$study_id, "coordinate")
  list(
    receipt = one(query(repo, "SELECT id,file_hash,preview_hash,schema_version,accepted_rows,rejected_rows,imported_at FROM identity.panel_import_receipts WHERE id=$1", receipt_id)),
    invitation_ids = query(repo, "SELECT id FROM identity.panel_invitation_drafts WHERE import_id=$1 ORDER BY id", receipt_id)$id
  )
}
