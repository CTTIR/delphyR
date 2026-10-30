# Maintenance audit — 31 October 2026

Scope: public delphyR, isolated from the original working copy. Base
`02e81e5b3f4f9b53eaaf6d66d86750a74261aa26`. The original 52 modified tracked
files and 11 untracked files already match upstream byte-for-byte and remain
untouched. This is synthetic-development qualification, not study approval.

## Evidence and strategy before implementation

Confirmed offline probes:

* Adjacent doubles around 0.7 serialize identically and produce the same
  scientific content hash. A threshold can therefore change without provenance
  changing, and persistence can change a consensus boundary. Repair numeric
  serialization and version the hash contract; preserve verification of earlier
  records explicitly, without silently rewriting recorded hashes or migrations.
* `new_scale()` accepts 2147483648, then coerces it to missing with a warning.
  Reject categories outside the supported R/PostgreSQL integer range before
  conversion; protect the input contract with boundary tests.
* `compare_rounds()` pairs identical participant codes from different study
  codes. Require the same study identity before making paired claims.
* Summary exports suppress a small cell in the statistics but repeat its
  classification in the final-item table and report. Suppression must cover
  both routes; the authorized research export retains its full results.
* Signed zero can make the hash of a table depend on row order. Normalize
  numeric zero in version 2 while keeping legacy verification unchanged.
* An item version above R's integer limit is accepted when constructing a
  snapshot but becomes missing on JSON reconstruction. Validate before storage.

The baseline core suite passed 443 assertions, with 124 database-gated test
blocks skipped; the application suite passed 1,626 assertions without skips.
Neither had failures or warnings. Logs and serialized results are retained
under the workspace audit's `evidence/delphyR/`. Existing October 3 reports
are historical and will not be relabelled as current evidence.

| Finding | Severity / impact | Main location | Repair |
|---|---|---|---|
| Numeric JSON and hash collision | High: a threshold and classification can change during storage without provenance changing | `conditions.R`, `snapshots.R`, app `setup.R` and `protocols.R` | Exact JSON and explicitly versioned hashes; legacy fixtures and threshold boundary tests |
| Summary classification disclosure | High: a suppressed small-cell result remains visible | `study_export.R` | Filter final-item classifications with the same disclosure policy; verify JSON, CSV and report data |
| Foreign-study pairing | High: unrelated pseudonyms are described as repeated participants | `analytics.R` | Require matching study code before pairing |
| Integer overflow | Medium: accepted ratings or versions become missing, or valid paired differences overflow | `domain.R`, `analytics.R` | Bound coercible values and calculate differences as doubles |
| Signed-zero table identity | Medium: row reordering changes scientific identity | `conditions.R` | Normalize zero in the new contract only |

The fixed legacy fixtures come from the unmodified base commit, not the new
implementation's compatibility branch. Their snapshot, result, rules and
feedback hashes are fixed test oracles. Service tests also exercise existing
approvals and retry receipts. A receipt retains the exact preview hash that
was approved, even when that preview predates the new contract.

## Milestones and acceptance

1. Repair scientific identity and invalid inputs, with meaningful failing
   baseline examples, compatibility fixtures and exact numeric round trips.
2. Exercise real transactional services in an isolated PostgreSQL container:
   permissions, concurrent saves/submission/close, exports, offline reproduction,
   migrations, worker recovery and a complete synthetic study journey.
3. Audit application and packaging boundaries; fix confirmed material defects,
   run both package checks and realistic browser journeys, document first use.
4. Review the final changes independently. Record exact results and limitations.
   Production authentication, institutional study approval, real recruitment,
   external messages and publishing remain separate gates. Longer-term features
   and cosmetic restructuring are outside this maintenance increment.
