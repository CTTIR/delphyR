# Security checks, the technical log and input limits

This page records what was checked, how to repeat it, and what was not. All
checks ran on synthetic data in the local development environment. They are
design and regression checks of this software, not a penetration test and not
the qualification of a production deployment.

## Check matrix

The rows follow the check matrix of the specification
([chapter 16](spec/16_AUTHENTICATION_AND_SECURITY.md)). "PostgreSQL" means the
opt-in contract tests of `scripts/integration.R`; "Chromium" means a real
browser against the application under the restricted database role.

| Check | Evidence | Result |
|---|---|---|
| Unauthenticated access | `test-authentication.R` (missing or wrong gateway transport, secret and subject fail closed); `test-session-identity.R` (a session without identity is closed before any service is called); real gateway run, see [authentication](authentication.md) | passed |
| Identifier of another study | `test-security.R`: a manager and a member of another study call every exported service with the valid identifiers of a study; every call is refused | passed |
| Response or enrollment of another person | `test-security.R`: another member of the same study reaches only services about their own participation; `test-services.R` (person boundaries) | passed |
| Known artifact of another person | `test-study-export.R` (an export is delivered only to its requester with the current right of its profile); `test-jobs.R` (right checked again at download, tampered file refused) | passed |
| Forged identity header | `test-authentication.R`; real gateway run (forged and spoofed subject headers) | passed |
| Direct access to the application port | Real gateway run (no published port, direct forgery rejected) | passed |
| Right revoked during a session | `test-service-contracts.R` (a blocked save rechecks the right after the lock); `test-jobs.R` (revocation after queueing stops the worker); `browser-revocation-postgres.R` (rights revoked in the interface: the next request and the download of an earlier export are refused in the open page); real gateway run (a right revoked and the account disabled during a session; an expired identity) | passed |
| Expired invitation | `test-invitations.R` (expiry and revocation deny acceptance) | passed |
| Reused invitation token | `test-invitations.R` (single use, retry safe, concurrent consumers create one membership) | passed |
| Link opened by a mail scanner | `test-invitations.R` (the preview reads only and discloses no contact); `browser-invitation-postgres.R` (acceptance needs a confirmed action after login); real gateway run (a visit without a session is sent to the sign-in, the code is never part of a request, opening and checking create nothing) | passed |
| Script in free text | `browser-security-postgres.R`: markup in every free-text field is shown literally in all views of study management and of a panel member; no element is created and no script runs. `test-reporting.R`: in rendered reports study text cannot become markup, a link, an image, formatting, a shortcode or code | passed |
| Statement payload | `test-security.R`: payloads in text are stored literally and change nothing else; malformed identifiers are refused before any statement is bound, for every identifier argument of every service | passed |
| Spreadsheet formula | `test-security.R`: no cell of any CSV file of any export profile, round export, round report or participant download starts like a formula | passed |
| Oversized input | `test-security.R`: text of 2 MiB is refused by every service and never bound to a statement; `test-security.R` of the application and `browser-security-postgres.R` (files beyond 1 MiB and beyond the request limit) | passed |
| Marked values in logs | `test-logging.R`, `test-security.R` and `browser-security-postgres.R`, see below | passed |

The real gateway run is the local Keycloak, OAuth2 Proxy and nginx chain with
the directly served application, with one, two and three application
processes. It was repeated with the current sources on 3 October 2026; all
of its checks passed. It also covers the acceptance of an invitation by the invited
account only, the lifetime of an identity and of the gateway session, and
signing out; see [authentication](authentication.md). Stock Shiny Server OSS
drops the identity headers and stays unqualified.

## Marked values in logs

A complete synthetic study is conducted with a marked value in every sensitive
field: free-text answers, contact address, name and external reference, the
invitation token, the gateway secret, the account subject, original and
redacted texts, campaign text, study information, item text, rationales and a
database password. The run includes refused and failed operations: a wrong
gateway secret, a wrong and a malformed token, an invalid and an outdated
answer, a message adapter that fails with the address in its error text, one
that refuses with the address in its reason, and a statement the database
refuses. The marked values are then searched for in five places:

| Place | Result |
|---|---|
| Technical log of the application and worker | none; every entry has only the fields listed below |
| Condition messages, which an uncaught failure would print | none |
| Audit trail | the rationale, as intended; no answer, contact, token, secret, account subject or text |
| Command receipts | none |
| PostgreSQL server log of the application role | none |

The server log check reads the log of the database container. Its control runs
one refused statement twice: the owner role's failing row is logged with its
values, which proves that the live log is read; the application role's is not.
Where the log cannot be read the check reports itself as not executed.

In the browser run, the standard error output of both application processes is
searched for marked text, contact addresses, study and account identifiers.

## Technical log

Every service call of the application, every job and every message leaves one
JSON line on standard error:

```json
{"time":"2026-10-02T17:52:52.006Z","level":"warning","correlation_id":"dc8e1fe1f892","component":"app","operation":"save_response","duration_ms":75,"outcome":"refused","error_class":"DEL_ROUND_CLOSED","error_path":"round"}
```

| Field | Content |
|---|---|
| `time` | UTC time of the entry |
| `level` | `info` (success), `warning` (refused by a rule) or `error` (failed) |
| `correlation_id` | Twelve random hexadecimal characters; derived from nothing |
| `component` | `app`, `worker` or `service` |
| `operation` | Service name, `job.<type>`, `message.deliver`, `session_identity` or `interface` |
| `duration_ms` | Duration of the operation |
| `outcome` | `ok`, `refused`, `failed`, or the state of a job or message |
| `error_class`, `error_path` | Condition code and field path, both fixed by the code |
| `reason` | Fixed reason code of a message state |
| `reference` | UUID of the job or message |

Arguments, results, condition messages, request headers, study and account
identifiers are never written. A value that does not have the fixed shape of
its field is replaced by `withheld`.

`options(delphyr.log_level = )` or `DELPHYR_LOG_LEVEL` selects `off`, `error`,
`warning` (default) or `info`. `options(delphyr.log_sink = function(line) ...)`
routes the lines elsewhere; a failing destination never changes the outcome of
an operation.

A failure message in the interface ends with `Reference:` and the correlation
ID of its entry. A background operation that did not succeed quotes its
operation ID, which the worker's entry carries as `reference`. A person can
quote the reference; the operator finds the operation, time and condition
class, and nothing about the content.

## Database server log

PostgreSQL writes the values of a failing row, of a duplicate key and of bound
parameters into the detail lines of its log. The application role therefore
needs

```sql
ALTER ROLE delphyr_runtime SET log_error_verbosity = 'terse';
```

which `scripts/configure-dev-role.R` sets. With it the log names the refused
statement with placeholders and the violated constraint, without detail lines,
also when statement logging is switched on.

One thing remains: PostgreSQL quotes a value it cannot convert to the type of
its column in the first line of the error, which `terse` does not remove. The
services therefore check identifiers, numbers and times before any statement:
the identifier check above covers every identifier argument of every service.
An owner or migration session logs with details; it handles no participant
input.

## Limits on input

| Input | Limit |
|---|---|
| Rationale of any command | 10 000 bytes, enforced centrally |
| Free-text answer, qualitative text, documentation field, campaign body | 20 000 bytes each |
| Item text | 20 000 bytes; 10 000 rows per round |
| Study information | 50 000 bytes |
| Protocol | 1 MB as stored JSON |
| Panel file | 1 MiB and 10 000 rows |
| Item file in the interface | 5 MB |
| Any upload | the request limit of the web server (5 MB by default) |

Three services accepted a rationale of any length and one bound an unchecked
code to a statement before the checks of 2 October 2026; the central limit and
the test over all services close this.

## Reports

A rendered report shows study text as text only. Until 2 October 2026 the
report templates wrote table cells where the renderer still interpreted
Markdown: a study text such as `[label](javascript:…)` became an active link
and `![x](http://…)` an image that the renderer fetched while building the
report. Angle brackets were already escaped, so no script element could be
written. The templates now write every table, list and block as final markup
that the renderer passes through unchanged, and escape the characters that
could end such a block or start a shortcode. Reports rendered before that date
from untrusted text should be rendered again.

## Not covered

- No penetration test, dependency audit or review by a security team.
- No production deployment: TLS, security headers, rate limits, secret
  management and network separation belong to the hosting qualification.
- Protection against a database administrator or host administrator is out of
  scope; the audit trail is append-only for the application role only.
- Availability under hostile load was not examined.
