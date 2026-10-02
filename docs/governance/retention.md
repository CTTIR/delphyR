# Retention and removal

## What the software does by itself

| Data | Rule | Where |
|---|---|---|
| Invitation code | Valid for at most 24 hours, single use; stored only as a hash | fixed |
| Export files | Downloadable for one day; files removed afterwards by `scripts/artifact-cleanup.R --apply`, registration and time of removal kept | fixed |
| Session identity | Ends after the configured lifetime, at most one hour | configuration |

Nothing else is removed automatically. There is no function that deletes
responses, consent records, contacts, audit records or free text, and no
retention period is built in. Records of research data are immutable in the
database for the application role.

## What the organisation decides

Separate periods are needed for at least the following. All are *to be
decided* by the responsible organisation for each study; the software ships
none.

| Data class | Period | Basis and decision |
|---|---|---|
| Contacts of people who never accepted an invitation | *to be decided* | |
| Contacts of panel members | *to be decided* | |
| Consent records | *to be decided* | |
| Responses and frozen snapshots | *to be decided* | |
| Unreviewed free text | *to be decided* | |
| Audit trail | *to be decided* | |
| Messages and delivery records | *to be decided* | |
| Backups | *to be decided* | |
| Web server, gateway and identity provider logs | *to be decided* | |

Ending participation stops further collection and messages. Whether earlier
responses stay, are removed or are anonymised follows the approved study
information; the software records the withdrawal and keeps the data.

## Inventory and dry run

`get_retention_report(repo, actor, study_id)` lists every data class of a study
with its number of records and the time of the oldest and newest one. It needs
the management right. With proposed periods it also states how many records
would be older:

```r
get_retention_report(repo, actor, study_id,
  periods = c(contacts_without_accepted_invitation = 90, audit_events = 3650))
```

This is a dry run. It deletes nothing and its periods are the caller's
proposal, not a rule. The classes are `contacts`,
`contacts_without_accepted_invitation`, `invitations`, `consent_records`,
`response_revisions`, `free_text_originals`, `frozen_snapshots`,
`campaign_messages`, `audit_events` and `exports_with_files`.

## Carrying out a removal

Removing research or identity data is not a function of this version. It
requires, in this order: an approved period or an individual request; the
dry-run report for the affected study; a decision recorded by the responsible
person; a reviewed procedure executed by the operator with the database owner
role; and a record of the result. Three consequences have to be stated in
that decision:

- A frozen snapshot that loses records can no longer be recomputed to its
  recorded hash. That is a documented state, not an error to be repaired by
  keeping a hidden copy.
- Backups made before the removal still contain the data. A restore brings
  them back; the removal has to be applied again
  ([backup and restore](../runbooks/backup-and-restore.md)).
- Exports that were downloaded are outside the system.

Until an organisation has approved such a procedure, the honest statement
about this software is: data stay until an operator removes them deliberately.
