# Disk full

## Recognise

- `scripts/status.R` shows little free space for the export directory, or
  `expired_exports_not_removed`.
- Exports fail with `DEL_STORAGE`; the database stops accepting writes and the
  situation becomes a [database outage](database-outage.md).

## First

1. Find out which volume is full: database, export directory, backups or logs.
   They should be separate volumes.
2. Never delete files of the database, and never delete a backup that is the
   only one of its period.
3. Exports are temporary private copies of data that stay in the database.
   Their download period is one day. List what has expired:

   ```sh
   Rscript scripts/artifact-cleanup.R
   ```

   The dry run writes a report under `.checks/` and removes nothing.

## Resume

1. Remove the files of expired exports and record the time:

   ```sh
   Rscript scripts/artifact-cleanup.R --apply
   ```

   Only exports past their download period are touched. Research data, audit
   records and registrations stay. An export can be requested again at any
   time.
2. Rotate or move logs according to the organisation's rules. The technical
   log holds no content and may be kept or removed without a data protection
   decision of its own; web server and gateway logs hold addresses and follow
   the organisation's rules.
3. Enlarge the volume if the database is the cause. Removing research data is
   not an operational measure: it needs an approved retention decision
   ([retention](../governance/retention.md)).
4. `status.R` exits with 0; save a response with a synthetic account.

## Responsible

Operator.

## Evidence

The cleanup report, free space before and after, and what else was moved or
removed.
