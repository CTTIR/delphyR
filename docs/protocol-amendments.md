# Protocol amendments

`list_protocol_versions()` gives study managers the immutable version history,
hashes and reasons. `amend_protocol()` accepts a fully validated protocol, the
last reviewed hash and a reason. It rejects a stale hash; identical confirmed
commands return the same receipt.

A new version applies to subsequently prepared rounds. Existing rounds,
instruments, responses and snapshots keep their previous protocol ID. Even a
prepared round that has not opened is not silently moved to the new version.
The study code stays fixed. Previously used scale identifiers cannot acquire a
different meaning in later protocols; a changed scale needs a new identifier and
an appropriate item version.

Migration `007_protocol_amendments.sql` adds immutable events with predecessor,
successor, actor, timestamp and reason. Technical approval of a synthetic version
does not replace institutional or ethical decisions. The management interface
supports JSON upload, field comparison, full preview and explicit approval; it is
not a schema-driven form editor.

Historical evidence: 13 PostgreSQL assertions in `test-protocols.R` covered
authorization, history, retries, stale reviews, scale identity and immutability.
See the current validation logs for later additions.
