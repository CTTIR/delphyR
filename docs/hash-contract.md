# Scientific content identity

From 0.0.2, new scientific content hashes start with `v2:` followed by a
lowercase SHA-256 digest. The canonical representation retains the existing
type tags, sorted object keys and row-order-independent tables, but writes
numeric values with 17 digits and treats positive and negative zero as the
same numeric value. Persistence, protocol downloads and amendment
review use the same precision. Two adjacent double values around 0.7 can give
different consensus classifications; they must remain distinguishable.

The unprefixed 64-character hashes written by 0.0.1 remain version 1. Reads
and verification select the algorithm from the recorded hash. Legacy
snapshots, analysis results, feedback, reports, campaign approvals, previews
and retry receipts are verified with their recorded contract. New snapshot
analysis uses version 2; analysis of an existing version 1 snapshot retains
version 1 result and rule hashes so its export remains reproducible. An
export that redacts legacy free text retains the snapshot's hash version.
Unknown prefixes and malformed hashes are rejected. A failed version 2 check
does not fall back to version 1.

No migration rewrites a recorded hash or historical JSON. Version 1 rounds
numbers to at most 15 digits and cannot detect changes below that precision.
Information already rounded during storage cannot be recovered. In particular,
old command receipts store only a payload hash, so retry checking retains
that limitation. Version 1 also retains its original signed-zero handling.
An old snapshot containing a signed negative-zero rating could already fail
JSON reconstruction; preserving its contract does not repair that record.
New commands use version 2; an import receipt records the exact preview hash
that was approved, including a version 1 preview. Prospective protocol amendments
compare the exact stored content with the proposed content; a close but
meaningful threshold change is accepted even when the previous protocol has
a legacy hash.

`content_hash(x, version = "1")` and
`new_snapshot(..., hash_version = "1")` exist for explicit reconstruction of
older records. Use their defaults for new work. Consumers that assumed every
scientific hash was exactly 64 characters must accept the versioned string.
Invitation token digests, migration checksums and artifact file SHA-256
checksums retain their existing unprefixed formats.

The minimum jsonlite version is 1.8.8: 17-digit output was introduced in 1.8.5,
the legacy `digits = NA` behavior was restored in 1.8.7, and 1.8.8 includes
parser security fixes. See the [upstream release notes](https://jeroen.r-universe.dev/jsonlite/NEWS).
PostgreSQL stores JSON numbers as numeric values; exact transport still
depends on the client representation ([PostgreSQL JSON types](https://www.postgresql.org/docs/17/datatype-json.html)).
