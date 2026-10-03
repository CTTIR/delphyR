# ADR-029: Presentation conventions of the interface and the reports

Status: accepted. Date: 2026-10-03.

## Context

A review of every screen and of the reports on a synthetic study (screenshots
at desktop and phone width, in English, French and German) found the same
kinds of defect in many places: times in database formats with seconds and
microseconds, raw codes and identifiers, `NA` in tables, statistics tables
with technical column names shown to participants, headings whose size
contradicted their level, and controls offered in states where they do
nothing. Each screen had been built on its own; nothing said how a moment, a
number or a code is to be shown.

## Decisions

- **Words, not codes.** A person never sees an internal code, `NA`, `NULL`, a
  column name or a UUID where a label can be given. States, statuses,
  classifications, dispositions, export profiles, delivery causes,
  capabilities and message kinds go through label functions. Stakeholder
  groups and dimensions have no labels in the protocol; their codes are shown
  readable ("public_contributors" as "Public contributors") and are not
  translated, because they are study content.
- **A missing value is a dash** (—), with the reason where it matters, for
  example "— (fewer than 3 valid ratings)".
- **Identifiers are shortened.** References and pseudonyms show their first
  eight characters, with the full value in a tooltip; hashes are not shown to
  participants and show twelve characters to staff. Full values stay in the
  exports and in the audit export.
- **One format for moments.** Date and time in the study's time zone, followed
  by the zone and the offset from UTC, so that the hour that occurs twice in
  autumn stays unambiguous: "8 Oct 2026, 19:49 (Europe/Berlin, UTC+2)", in
  French "8 oct. 2026, 19:49 (…)", in German "8. Okt. 2026, 19:49 (…)". Month
  names come from fixed lists, not from the locale of the server. Where the
  study's zone is not known the moment is shown in UTC and says so.
- **Numbers** use the decimal sign of the language; proportions are whole
  percentages, medians and quartiles have at most one decimal.
- **Tables** have labelled columns in the interface language, a caption or a
  heading directly above them, and only the columns a person needs; the rest
  belongs in an export. Wide tables scroll inside their frame and keep the
  first column visible.
- **Hierarchy and spacing.** Headings inside a section are 1.5, 1.2 and
  1.05 rem for levels 2 to 4; a lower level is never larger than a higher
  one. Rows of buttons are spaced; a button is never directly followed by a
  heading or a field. Fields have a white background and a border with a
  contrast of at least 3:1. Collapsible groups have a visible summary line.
- **Only applicable controls.** A control that does nothing in the current
  state is not shown, or is shown disabled with the reason.

The helpers are in `packages/delphyrApp/R/present.R` (`format_moment()`,
`format_number()`, `format_percent()`, `short_ref()`, `ref_tag()`,
`humanize_code()`) and the styles in `app_css()` in
`packages/delphyrApp/R/theme.R`.

## Consequences

- Times in the interface no longer carry seconds; the exact value stays in
  the exports and in the audit export.
- Screens and reports that do not follow these conventions are defects, not
  matters of taste. Their tests assert the formatted form.
