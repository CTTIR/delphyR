# ADR-025: Technical log, references in failure messages and input limits

Status: accepted. Date: 2026-10-02.

## Context

Requirement SEC-02 asks that tokens, answers and addresses never appear in
standard logs, and the specification asks for a technical log with a
correlation ID, operation, duration and error class, and for a non-sensitive
reference in every failure message. Until now a failure showed a generic
message and left no trace an operator could find, and nothing was written
about background work.

## Decisions

- **One entry per operation, built from fixed tokens.** The log is written by
  the core package as one JSON line with a closed set of fields. Every field
  has a fixed shape; anything else is replaced by `withheld`. Condition
  messages are never written, because a database or provider message can quote
  a value.
- **Refusals are warnings, failures are errors.** A rule that refuses an
  action is expected behaviour and logged as a warning; a storage failure or
  an unexpected condition is an error. Successful operations are written only
  at level `info`.
- **The reference is random.** The correlation ID is derived from nothing and
  is safe to show and to quote. It is attached to the condition, so that the
  interface can append it to its message without knowing the cause.
- **Background work is logged by the worker.** A job or message names its own
  identifier as reference; an uncertain delivery is an error entry, because it
  needs a person.
- **The worker ends on an unexpected failure.** It records the class and
  exits, so that its supervisor restarts it with a fresh connection instead of
  looping on a broken one.
- **The database role is part of the log design.** The application role logs
  tersely; the provisioning script sets it and a test reads the server log.
- **Limits are central where possible.** The rationale of every command has
  one limit in the command layer; a stored protocol has one size limit.
- **Arguments are evaluated before a transaction opens.** A service call used
  as an argument of another would otherwise start inside its transaction and
  fail as a storage error.

## Consequences

`log_event()`, `log_operation()` and `new_correlation_id()` are exported.
`run_app()` routes every service call through the log. Failure messages end
with a reference; a failed background operation quotes its operation ID. No
migration is needed. Hosting must keep standard error of the application and
worker and must configure the application role as described in
[security](../security.md).

## Validation

`test-logging.R` (43 assertions), `test-security.R` of the core (88,
PostgreSQL) and of the application (33), and
`inst/qa/browser-security-postgres.R` in Chromium on 2026-10-02.
