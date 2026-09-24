# Relationales Datenmodell und Integritätsregeln

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Grundsätze

PostgreSQL ist das verbindliche Backend. Primärschlüssel sind opaque UUIDs. Alle fachlichen Tabellen tragen `study_id`, sofern sie zu einer Studie gehören. Zusammengesetzte Fremdschlüssel sichern zusätzlich zur Serviceprüfung, dass referenzierte Objekte dieselbe Studie besitzen. Zeitwerte werden als `timestamptz` gespeichert, in UTC verarbeitet und bei Ausgabe lokalisiert.

Normalisierte Tabellen speichern Kernbeziehungen und analysierbare Werte. JSONB ist für versionierte deklarative Regeln, Render-Metadaten und begrenzte typspezifische Zusatzdaten geeignet. Vollständige Antwortdaten nicht ausschließlich in undurchsichtigen JSON-Blobs verstecken.

## Schemata

- `identity`: Principals, Kontaktinformationen, geschützte Verknüpfungen, Einwilligungen.
- `research`: Studien, Runden, Items, Antworten, Analysen, Feedback und Entscheidungen.
- `ops`: Jobs, Outbox, Artefaktregister, Migrationszustand, Audit und technische Zustände.

Zugriffsrechte müssen diese Trennung tatsächlich umsetzen. Eine Tabellennamenskonvention allein ist kein Zugriffsschutz.

## Tabellenvertrag

| Tabelle | Wesentliche Felder | Regeln |
|---|---|---|
| principals | id, issuer, subject, status | unique(issuer, subject); keine E-Mail als primärer Schlüssel |
| contacts | principal_id, email, display_name, locale | Zugriff auf Kommunikationsrollen begrenzen |
| studies | id, code, title, status, timezone, created_at | code eindeutig in Installation |
| memberships | id, study_id, principal_id, status | unique(study_id, principal_id) |
| role_assignments | membership_id, capability/role, valid_from, revoked_at | zeitlich nachvollziehbar |
| panelists | id, study_id, status | studienspezifische zufällige Analyse-ID |
| panelist_links | study_id, membership_id, panelist_id | geschützte 1:1-Zuordnung je Studie |
| stakeholder_groups | id, study_id, code, label | code je Studie eindeutig |
| group_assignments | panelist_id, group_id, valid_from, valid_to | Historie statt Überschreiben |
| consent_versions | id, study_id, locale, text, hash, published_at | veröffentlichte Version unveränderlich |
| consents | membership_id, consent_version_id, decision, recorded_at | Ereignisse statt Boolean allein |
| protocol_versions | id, study_id, version, config, hash, status | approved bedeutet immutable |
| rule_versions | id, study_id, protocol_version_id, version, config, hash, status | referenzierte Regeln nach Freigabe unveränderlich; Ziel von rules_version_id |
| sources | id, study_id, source_type, citation, source_ref | Literatur oder interne Beitragsreferenz |
| items | id, study_id, stable_code, lifecycle_status | semantische Identität |
| item_versions | id, study_id, item_id, version, meaning_change, hash | unique(item_id, version) |
| item_texts | item_version_id, locale, text, help_text | Übersetzungen gehören zur Version |
| item_sources | item_id/version_id, source_id, relation | mehrere Quellen möglich |
| item_lineage | from_item_id, to_item_id, relation, reason | Split/Merge nicht als bloße Umbenennung |
| scales | id, study_id, version, type, config | freigegebene Skala unveränderlich |
| dimensions | id, study_id, code, label, scale_id | Dimension ist Teil des Antwortschlüssels |
| rounds | id, study_id, number, type, state, protocol_version_id, open_at, close_at | unique(study_id, number) |
| round_items | id, study_id, round_id, item_version_id, dimension_id, scale_id, display_order | freigegebene Präsentation |
| round_enrollments | id, study_id, round_id, panelist_id, status, group_snapshot, order_seed | unique(round_id, panelist_id) |
| response_current | id, study_id, enrollment_id, round_item_id, revision, status, value_int, value_text | unique(enrollment_id, round_item_id) |
| response_revisions | response_id, revision, payload, actor_id, created_at, command_id | append-only; vorherige Werte nicht überschreiben |
| submissions | id, study_id, enrollment_id, version, state, submitted_at, response_set_hash | aktive Abgabe höchstens einmal je Enrollment |
| submission_entries | submission_id, response_id, response_revision | fixiert exakt abgegebene Revisionen |
| response_snapshots | id, study_id, round_id, inclusion_policy, content_hash, created_at | festgelegte Analysegrundlage |
| snapshot_entries | snapshot_id, response_id, response_revision, inclusion_status | kein Zugriff auf wandelbaren Current-Stand nötig |
| analysis_runs | id, study_id, snapshot_id, rules_version_id, code_version, result_hash, status | jeder Lauf eigenständig |
| analysis_results | run_id, round_item_id, stratum_id, n_valid, metrics, classification | eindeutige Zeile je Auswertungseinheit |
| qualitative_sources | id, study_id, response_revision_ref, original_text | Originalzugriff begrenzen |
| qualitative_edits | id, source_id, redacted_text, reason, reviewer_id | Bearbeitungshistorie |
| themes | id, study_id, label, definition, version | Codierstruktur nachvollziehbar |
| theme_assignments | theme_id, source_id, coder_id, decision | mehrere Codierungen möglich |
| feedback_releases | id, study_id, analysis_run_id, template_version, policy, hash, state | immutable nach Freigabe |
| feedback_entries | release_id, item_version_id, stratum_id, content | nur freigegebene Inhalte |
| feedback_assignments | target_enrollment_id, release_id, personal_snapshot_ref | bindet Person/Runde an Feedback |
| display_events | membership_id, feedback_release_id, displayed_at | ausgeliefert, nicht „gelesen“ behaupten |
| item_decisions | id, study_id, item_id, analysis_run_id, disposition, reason, actor_id | analytischer Status bleibt separat |
| approvals | id, study_id, object_type, object_id, object_hash, actor_id, at | Genehmigung gilt für exakten Inhalt |
| audit_events | id, study_id, actor_id, action, object_ref, occurred_at, command_id, redacted_delta | kein unbegrenzter Klartextdatenspiegel |
| commands | id, study_id, actor_id, idempotency_key, payload_hash, outcome_ref | gleicher Key mit anderem Inhalt ist Fehler |
| jobs | id, study_id, type, payload_ref, state, attempts, available_at, lease_until | dauerhafte Queue |
| outbox_messages | id, study_id, campaign_id, recipient_ref, template_version, state, dedupe_key | eindeutige logische Nachricht |
| artifacts | id, study_id, storage_key, media_type, checksum, size, expires_at, audience | privater Speicher, kein beliebiger Dateipfad |
| schema_migrations | version, checksum, applied_at, code_version | bereits angewandte Migration nicht editieren |

## Antworttypen und Missingness

P1 `answer_status`: `answered`, `not_answered`, `unable_to_judge`, `abstained`, `not_applicable`. „Nicht vorgelegt“ entsteht aus fehlender Rundenzuweisung und darf nicht als unbeantwortete Pflichtfrage zählen. Eine nicht gespeicherte Antwort wird bei Analyse anhand des eingefrorenen Instruments explizit als fehlend abgeleitet, nicht aus zufällig fehlenden SQL-Zeilen erraten.

Bei ordinalen Antworten ist `value_int` nur bei `answered` erlaubt und muss zur freigegebenen Skala gehören. `value_text` kann Antworttext oder separat gespeicherter Kommentar sein; deren Semantik nicht vermischen. Kommentare zur Bewertung erhalten einen eigenen Vertrag, falls sie unabhängig vom Antwortwert geändert werden können.

## Schlüssel und Constraints

Ein Enrollment und sein Round-Item müssen dieselbe Runde und Studie haben. Ein Submission-Entry darf nur Antworten desselben Enrollments enthalten. Ein Snapshot darf nur Revisionen aus seiner Runde enthalten. Foreign Keys über `study_id` plus Objekt-ID implementieren, nicht nur UUIDs vergleichen. Unique-Constraints verhindern Duplikate auch bei Race Conditions.

Zulässige Antworten werden zusätzlich im Service gegen Skalenkonfiguration validiert. SQL-Constraints schützen grundlegende Typ-/Nullregeln. Keine Trigger, deren wissenschaftliche Semantik nur dort versteckt ist; komplexe Regeln bleiben im getesteten Domaincode, technische Schutztrigger sind dokumentiert.

## Indizes und Volumen

Indizes für Mitgliedschaftssuche, Studie/Runde/Panelist, aktuelle Antworten je Enrollment, Antwortrevisionen, Queue nach Status/available_at, Audit nach Studie/Zeit und Artefakte nach Besitzer. Indexpläne anhand realer Abfragen messen. Audit und Revisionen wachsen stärker als aktuelle Antworten; Archivierung und Aufbewahrung in Kapazitätsplanung aufnehmen.

## Löschung und Integrität

Keine pauschalen `ON DELETE CASCADE` über abgeschlossene Forschungsdaten. Lösch- und Pseudonymisierungsaufträge folgen einer dokumentierten Policy. Personenbezug in Kontaktzuordnung, Freitexten, Exports und Backups separat berücksichtigen. Nach genehmigter Löschung kann exakte historische Reproduktion eingeschränkt sein; dies wird sichtbar dokumentiert und nicht durch versteckte Restkopien umgangen.
