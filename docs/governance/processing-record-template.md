# Processing record template

A description of the processing for one study, to be completed by the
responsible organisation. The left column and the technical statements
describe the software; everything marked *to be completed* is the
organisation's.

## Responsibility

| | |
|---|---|
| Responsible organisation | *to be completed* |
| Study and study lead | *to be completed* |
| Data protection contact | *to be completed* |
| Operator of the installation | *to be completed* |
| Processors (hosting, identity provider, message provider, backup storage) | *to be completed* |

## Purposes and legal basis

| | |
|---|---|
| Purpose | Conducting a round-based Delphi study: inviting panel members, collecting ratings and comments, feeding back aggregated results, reporting. *Study-specific purpose to be completed.* |
| Legal basis | *to be completed* |
| Ethics or institutional review | *to be completed* |

## People and data

| Data class | Content | Who can read it in the software | Leaves the system as |
|---|---|---|---|
| Contact | Name, address, external reference, stakeholder group | Coordination; holders of the separate contact export right | Contact export only |
| Account reference | Issuer and subject of the verified sign-in | Service layer; study leads see staff accounts | Never in research exports |
| Consent record | Version of the study information shown, decision, time | Study management | Counts in reports |
| Ratings | Value or special response per item and dimension, with revisions | Analysis and export roles, under a study pseudonym | Research export |
| Free text | Original answer | Editors only | Never; only a version released by a second person |
| Stakeholder group | Group fixed at enrollment in a round | Analysis roles | Research export, possibly coarsened for publication |
| Audit trail | Actor, time, action, object, rationale | Audit role and study management; panel accounts withheld | Audit export |
| Technical log | Operation, time, class of a failure | Operator | Not part of any export |

A study pseudonym is valid within one study. It is not anonymity: the
operator and the coordination can relate it to a person.

## Recipients

| Recipient | What | Basis |
|---|---|---|
| Panel members | Aggregated results of the previous round, their own earlier answers, released editorial text | Study information |
| Study team by role | See the table above | Assigned rights, recorded in the audit trail |
| *Others, for example publication or data repository* | *to be completed* | *to be completed* |

A research export is not a public data set. Publication needs its own review.

## Storage and transfer

| | |
|---|---|
| Location of database, exports and backups | *to be completed* |
| Transfers outside the organisation or country | *to be completed* |
| Message provider | None in this version; a provider is *to be completed* with its own assessment |

## Retention

See [retention and removal](retention.md). Periods: *to be completed*.

## Technical and organisational measures of the software

- Sign-in through the organisation's identity provider behind a gateway; the
  application accepts an identity only from that gateway.
- Rights per study and role, checked by the server for every action and again
  for every download; changes of rights are recorded.
- The application's database role cannot delete records, change the schema or
  act as owner.
- Responses are saved in transactions; a save is shown only after it was
  committed. Frozen snapshots and released feedback are immutable.
- Exports are private, limited to one day and separated by profile; the
  contact export is a right of its own.
- Free text reaches other people only as a version released by a second
  person.
- Logs hold no content, contacts or accounts.
- Backup and restore are rehearsed with a documented check.

Measures of the hosting environment, such as encryption of storage and
transport, network separation, administrator access and physical security:
*to be completed*.

## Rights of participants

How a person asks for information, correction, removal or the end of
participation, and who answers: *to be completed*. The software records the end
of participation and stops further collection and messages for that person.

## Review

| Date | Reviewed by | Changes |
|---|---|---|
| *to be completed* | | |
