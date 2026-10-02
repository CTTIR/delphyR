# Security incident

An incident is any sign that data were seen, changed or lost by somebody not
entitled to, or that an account or secret is in the wrong hands. When in doubt
it is one.

## Recognise

Examples: a participant sees content that is not theirs; an account acts that
its holder did not use; the gateway secret, a database password or a backup
left its place; many refused sign-ins or `DEL_FORBIDDEN` entries from one
session; an export with contacts was sent to the wrong person.

## First

1. Tell the data protection contact and the study lead now. Deadlines for
   notification are the organisation's and may be short; the software cannot
   judge them.
2. Contain without destroying evidence:
   - A compromised staff account: a study lead revokes its rights under
     *Setup → Study team and rights*. The next action of that account is
     refused, also in an open session. The operator disables the account at
     the identity provider.
   - A leaked gateway secret: replace it at the gateway and the application
     and restart both; every session ends.
   - A leaked database password: change it and restart application and worker.
   - A wrongly sent export: it cannot be recalled. Its download in the
     application ends after one day; record who received which profile.
3. Do not delete logs, audit records or exports. Do not "repair" data by hand.

## Establish what happened

- The audit trail (*History*, or the audit export) lists every action with
  actor, time, object and rationale, including every export download and
  every display of feedback.
- The technical log lists refused and failed operations by time and class,
  without content.
- Gateway and web server logs hold addresses and sign-ins; they belong to the
  operator.
- Which data an account could reach follows from its rights at the time; the
  audit trail records every change of rights.

## Resume

1. Close the cause before reopening access.
2. Review all rights of the study and all outstanding invitations.
3. If data may have been changed, compare with the last backup rehearsal and
   the hashes of frozen snapshots: a snapshot's content and hash are immutable
   in the database and are recomputed when it is read.
4. Record the incident and what was decided. Notification of participants and
   authorities is decided by the organisation.

## Responsible

Data protection contact and study lead; operator for containment.

## Evidence

Times, accounts by role (not by name in shared notes), audit export, relevant
log lines, measures taken and decisions with their reasons.
