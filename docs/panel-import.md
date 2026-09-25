# Synthetic panel import and unbound invitation drafts

Panel import writes synthetic contacts to the separate `identity` schema and
creates **unbound invitation drafts**. It sends no messages, creates no tokens and
never binds a principal by email. Import creates no study membership, panel
pseudonym, consent or questionnaire assignment.

## CSV contract

Schema `1.0` requires UTF-8 and exactly these columns:

```csv
external_ref,email,display_name,locale,stakeholder_group
001,Person.One+Demo@EXAMPLE.INVALID,Synthetic Person One,en,professionals
002,person02@example.invalid,Synthetic Person Two,fr,public_contributors
```

Choose comma or semicolon explicitly. All fields are strings: leading zeros and
the literal `NA` survive. There is no locale-dependent type inference. An initial
UTF-8 BOM is tolerated; the file hash still binds the original bytes. Limits are
1 MiB and 10,000 data rows, with additional length and control-character checks
for names and references. Locale and stakeholder group must belong to the current
study protocol. Supported content locales are `en`, `fr` and `de`; a study may
declare a subset.

Development accepts only `.invalid` synthetic email domains. Domains become
lowercase; local-part case, dots and plus suffixes remain unchanged. No provider
alias rules are applied. The parser supports simple ASCII addresses and does not
silently convert internationalized domains or quoted local parts.

## Authorized preview

```r
# Trusted upload handling supplies bytes, not an arbitrary browser-selected path.
preview <- delphyr::preview_panel_import(
  repo, coordinator, study_id, csv_bytes,
  schema_version = "1.0", delimiter = ","
)
preview$rows
preview$issues
preview$valid
```

Current `coordinate` capability is required before contacts are processed or
shown. The API accepts bytes or text and reads no arbitrary file paths. Preview
stays in the authorized caller's context; it is not automatically persisted.

Issues contain logical data-row number, column and code, without copied contact
values. Row `0` denotes a file-wide or schema-wide issue. Row numbers count records
after the header; a CSV field may contain multiple physical lines.

Duplicate external references and normalized addresses are checked within the
file and against existing contacts in the same study. Local-part case-only
collisions require review instead of automatic merging. Every such issue blocks
the **whole file**. Correct and preview the input again. There is no automatic
deduplication, contact update or silent membership transfer.

## Approval of the exact preview

```r
receipt <- delphyr::import_panel(
  repo, coordinator, study_id, preview,
  expected_hash = preview$hash,
  reason = "Synthetic rows and target group reviewed",
  command_id = "panel-import-001"
)
delphyr::get_panel_import_receipt(repo, coordinator, receipt$id)
```

The approval hash binds file, schema, delimiter, rows and validation report.
Before import, original bytes are reparsed and rights, study state, protocol
references and duplicates are rechecked. A study lock serializes concurrent
imports. Contacts, drafts, receipt, command receipt and audit event commit or
roll back together; there are no partial imports.

An identical retry returns the same receipt even though the imported rows now
exist. Changed content or reason under the same command key is rejected. Rights
are rechecked on retries. A new import of the same contacts is a duplicate review.

The immutable receipt contains file/preview hashes, schema, accepted/rejected
counts, actor, timestamp, reason and validation report. The response also includes
opaque draft IDs. Standard audit records and command payloads contain no contact
values. The minimal receipt view contains no names or email addresses.

## Identity and governance remain separate

Drafts remain `unbound` without a principal reference. Separate
[invitation services](invitations.md) implement exact verified issuer/subject
approval, expiring hashed tokens and confirmed single-use acceptance. Import
itself performs none of that binding and never triggers acceptance on a GET.

Contacts are outside research responses and the numeric export profile.
Retention, correction and permitted deletion need separate institutional rules.
Immutable development import tables are not a complete production retention or
deletion workflow.

`test-panel-import.R` uses the explicitly enabled synthetic PostgreSQL database
(`DELPHYR_TEST_DB=true`). Cases cover normalization, exact hashes, schema/row errors,
duplicates, study boundaries, revocation, retries and rollback after a mid-write
failure. Import tests neither bind accounts nor send messages.
