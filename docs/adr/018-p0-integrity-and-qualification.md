# ADR-018: Development path and qualification boundaries

Status: accepted. Date: 2026-09-25.

The initial runnable environment uses synthetic identities and loopback PostgreSQL.
The schema separates identity, research and operations. Migrations and fixtures use
an owner connection; the app and worker use restricted `delphyr_runtime` access.
This does not qualify production database roles or institutional authentication.
Services require server-created actors; browser parameters are not identities.
The next protected action checks current rights. Transactions admitted before a
revocation may finish.

Responses lock the round in shared mode and the enrollment exclusively; closing
locks the round exclusively. Deadlines are checked after waits using database time.
Mutations are transactional and use content-bound retries. Applied migration files
are checksummed and immutable.

Prerelease 0.0.1 uses structurally tagged scientific hashes. This corrects empty
table and named-vector collisions in the inherited development state. Earlier
local demo hashes therefore differ; there is no published stable export version
or production migration to preserve.

Numeric export v1 excludes free-text responses. Unmodified JSON is authoritative;
CSV neutralizes formula prefixes. HTML escapes content from the same analysis.
At the initial decision, a full Quarto report was still open. Later local evidence
covers the packaged numeric Quarto report and its supplements; institutional
author fields and broader release profiles remain open. See the implementation
status rather than treating the initial limitation as current functionality.

The Shiny demo uses explicit saves; autosave is not accepted. Interface-language
changes never rewrite approved content or historical snapshots. English public
documentation and en/fr/de interface policy supersede the earlier bilingual scope
under ADR-017. None of these decisions alone establishes full P1 acceptance.
