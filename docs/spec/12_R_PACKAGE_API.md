# R-Package: öffentliche API und Serviceverträge

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Ebenen der API

Die vorgeschlagenen Namen sind Sollverträge. Änderungen sind möglich, müssen aber durchgängig in Dokumentation, Tests und Beispielen erfolgen. Das Package exportiert wenige fachlich vollständige Funktionen statt SQL-Hilfsfunktionen als primäre Oberfläche.

### Reine Konstruktion und Validierung

| Funktion | Eingabe | Rückgabe |
|---|---|---|
| `new_protocol(config)` | deklarative Liste | `delphyr_protocol` |
| `validate_protocol(protocol)` | Protokollobjekt | `delphyr_validation` mit Fehlern/Warnungen |
| `new_scale(type, levels, labels, missing_options)` | Skalenvertrag | `delphyr_scale` |
| `validate_items(items, scales)` | Itemtabelle und Skalen | strukturierter Validierungsbericht |
| `validate_response(value, status, scale)` | Wert und Status | normalisierte Antwort oder Condition |
| `classify_consensus(counts, rule)` | Zähler/Nenner + Regel | Klassifikation mit Erklärungsdaten |
| `analyse_round(snapshot, rules)` | eingefrorene Antwortdaten | `delphyr_analysis` |
| `compare_rounds(previous, current, mapping)` | kompatible Snapshots | `delphyr_comparison` |
| `prepare_feedback(analysis, qualitative, policy)` | geprüfte Quellen | `delphyr_feedback_draft` |
| `validate_feedback(draft)` | Feedbackentwurf | Redaktions-/Sichtbarkeitsprüfung |

Reine Funktionen schreiben keine Dateien und versenden keine Nachrichten. Zufallsbasierte Sensitivitätsanalysen verlangen einen expliziten Seed und dokumentierte Verfahren.

### Autorisierte Services

| Funktion | Fachlicher Effekt |
|---|---|
| `create_study(repo, actor, protocol, command_id)` | Entwurf anlegen |
| `import_items(repo, actor, study_id, import, command_id)` | geprüften Import atomar übernehmen |
| `prepare_round(repo, actor, study_id, specification, command_id)` | Rundensatz erzeugen |
| `approve_round(repo, actor, round_id, expected_hash, command_id)` | exakten Inhalt freigeben |
| `open_round(repo, actor, round_id, command_id)` | erlaubte Erhebung öffnen |
| `save_response(repo, actor, enrollment_id, round_item_id, response, expected_revision, command_id)` | Antwortentwurf versioniert speichern |
| `submit_round(repo, actor, enrollment_id, expected_revision_set, command_id)` | gültigen Antwortsatz abgeben |
| `close_round(repo, actor, round_id, reason, command_id)` | neue Erhebung sperren |
| `freeze_round(repo, actor, round_id, inclusion_policy, command_id)` | Snapshotauftrag erzeugen |
| `request_analysis(repo, actor, snapshot_id, rules_version_id, command_id)` | Analysejob registrieren |
| `approve_feedback(repo, actor, feedback_id, expected_hash, command_id)` | Feedback freigeben |
| `record_item_decision(repo, actor, item_id, analysis_id, decision, reason, command_id)` | Entscheidung dokumentieren |
| `prepare_next_round(repo, actor, study_id, decisions, command_id)` | neue Fassung, noch nicht automatisch öffnen |
| `request_export(repo, actor, study_id, export_profile, command_id)` | berechtigten Exportauftrag registrieren |
| `get_operation(repo, actor, operation_id)` | autorisierten Jobstatus lesen |

Alle Services prüfen Rechte intern. Ein Admin-UI-Aufruf umgeht dies nicht. Worker besitzen explizite Systemakteure und delegierte Zwecke, keine unbegrenzte Phantomrolle.

## Rückgabeobjekte

Ein `delphyr_analysis` enthält `results`, `denominators`, `missingness`, `settings`, `provenance`, `warnings` und `schema_version`. `results` hat eine Zeile je Runde × Itemversion × Dimension × Stratum. `provenance` enthält Snapshot-ID/Hash, Regelversion, Softwareversion und Berechnungsoptionen.

`delphyr_validation` enthält `valid`, eine Tabelle `issues` mit `severity`, `code`, `path`, `message_key`, `details`, und die geprüfte Schemasversion. Keine bloße Liste unstrukturierter Warnstrings.

`delphyr_operation` enthält `operation_id`, `state`, `result_ref`, `created_at` und zulässige Fehlerinformation. Asynchrone API meldet nicht vor Abschluss „Analyse fertig“.

S3-Methoden `print()`, `summary()`, `as.data.frame()` und gegebenenfalls `plot()` bieten menschenlesbare Ausgaben. `print()` eines Studienobjekts darf nicht versehentlich Kontakte, Tokens oder komplette Freitexte ausgeben.

## Conditionvertrag

| Code | Bedeutung | Behandlung |
|---|---|---|
| DEL_VALIDATION | unzulässige Konfiguration/Antwort | konkrete Felder markieren |
| DEL_UNAUTHORIZED | keine verifizierte Identität | erneute Anmeldung |
| DEL_FORBIDDEN | fehlende Rechte | Zugriff verweigern, keine Datenlecks |
| DEL_NOT_FOUND | Objekt nicht verfügbar | nicht zwischen fremd und nicht existent unterscheiden |
| DEL_CONFLICT | veraltete Revision/Idempotenzkonflikt | aktuellen Stand laden, bewusst auflösen |
| DEL_ROUND_CLOSED | Erhebung beendet | keine Savebestätigung, Status erläutern |
| DEL_INSUFFICIENT_DATA | Analysevoraussetzung fehlt | Status ausgeben statt künstlicher Null |
| DEL_DEPENDENCY | optionale Runtime fehlt | konkrete Installations-/Betriebsinformation an Admin |
| DEL_STORAGE | Datenoperation fehlgeschlagen | Korrelations-ID, keine sensiblen Details |

## Beispiel: reine Analyse

```r
# Geplante API, noch keine vorhandene Implementierung.
protocol <- delphyr::new_protocol(config)
validation <- delphyr::validate_protocol(protocol)
stopifnot(validation$valid)
analysis <- delphyr::analyse_round(snapshot, protocol$consensus_rules)
summary(analysis)
as.data.frame(analysis)
```

Die produktive App bezieht Snapshots über autorisierte Repositoryfunktionen. Offlineanwender dürfen legitime pseudonymisierte Exporte einlesen und dieselben reinen Analysen ausführen.

## Kompatibilität

Konfigurationsschema, Exportschema und Packageversion getrennt versionieren. Ein Major-Packageupdate darf alte Daten nicht still anders interpretieren. Historische Exporte müssen mit der dokumentierten passenden Softwareversion rekonstruierbar bleiben. Veraltete API mit klaren Warnungen und Migrationshinweisen ablösen.
