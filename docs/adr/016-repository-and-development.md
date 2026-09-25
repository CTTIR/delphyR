# ADR-016: Repository, license and development

Status: accepted. Date: 2026-09-24; naming update: 2026-09-25.

The user explicitly selected the public repository `CTTIR/delpyR` and MIT license.
On 2026-09-25, the repository was renamed `CTTIR/delphyR` at the user's request.
Technical package names follow the specification: `delphyr` and `delphyrApp`.
The copyright holder is Raban Heller, consistent with existing CTTIR packages.
The private original directory `admin/` remains ignored; the unchanged historical
specification copy under `docs/spec/` preserves the source requirements.

Implementation proceeds through verifiable steps. Independent work may run in
parallel when explicitly authorized. Local PostgreSQL uses isolated synthetic
data. Production approval is separate. Initial builds use available R dependencies
and record actual versions. No release gate is claimed without evidence.

Initial sequence: pure domain and analytics; PostgreSQL and authorization;
two-round service path; Shiny; management, jobs, exports and operational evidence.
Current documentation and interface language policy is defined by ADR-017.
