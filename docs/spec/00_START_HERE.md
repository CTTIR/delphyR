# delphyR — Start und Dokumentationskarte

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Zweck und Status

Dieses Paket spezifiziert eine vollständige Plattform für rundenbasierte Delphi-Studien: von Planung und Rekrutierung über qualitative Itemarbeit und wiederholte Bewertungen bis zu Feedback, Abschluss und reproduzierbarer Berichterstattung. Zielplattform ist ein selbst betriebener Shiny Server Open Source mit R und PostgreSQL.

Es enthält Anforderungen, Architekturentscheidungen, Verträge, Vorlagen, Referenzfälle und einen ausführbaren Arbeitsauftrag für einen Coding-Orchestrator. Es enthält **noch keine implementierte Anwendung**, keinen getesteten Deployment-Stack und keine bereits erteilte Studienfreigabe. Alle Funktionsnamen, SQL-Ausschnitte, Konfigurationen und Verzeichnisstrukturen sind vorgeschlagene Implementierungsverträge, soweit nicht ausdrücklich als bestehende Fremdsoftware bezeichnet.

Marke: **delphyR**. Kanonischer Package-/Repositoryname: **delphyr**. Begleitpackage für die Oberfläche: **delphyrApp**. Die gewünschte Aussprache „del-fire“ ist eine Markenentscheidung; der Name ist auch mit einer Delphin-/Flammen-Bildidee vereinbar. Verfügbarkeit und Markenrechte sind nicht geprüft.

Dokumentationssprache: Deutsch. Code, API, Datenbankfelder und Fehlercodes: Englisch. Produktoberfläche: Deutsch und Englisch. Standardzeit in Speicherung und Schnittstellen: UTC; Anzeige entsprechend Studienzeitzone.

## Verbindlichkeit

- **MUSS**: erforderlich für den angegebenen Release-/Produktionsumfang.
- **SOLL**: begründete Abweichung durch dokumentierte Architekturentscheidung möglich.
- **KANN**: Erweiterung; nicht stillschweigend in den ersten Release aufnehmen.
- **Annahme**: Arbeitsgrundlage bis zu einer expliziten Entscheidung.
- **Beispiel**: illustrative Daten oder Schwellen; niemals automatisch eine methodische Empfehlung.

Bei Konflikten gelten explizite aktuelle Nutzerentscheidungen vor diesem Paket. Innerhalb des Pakets gelten Daten-/Sicherheitsinvarianten vor UI-Bequemlichkeit. Das Entscheidungsregister dokumentiert Änderungen. Eine geplante Funktion ist nicht als vorhanden zu berichten.

## Empfohlene Lesereihenfolge

1. [Produkt und Umfang](01_PRODUCT_AND_SCOPE.md), [Annahmen und Entscheidungen](02_DECISIONS_AND_ASSUMPTIONS.md).
2. [Methodik](03_METHODOLOGY.md), [Anforderungskatalog](04_REQUIREMENTS.md), [Rollen](05_ROLES_AND_PERMISSIONS.md).
3. [Architektur](06_ARCHITECTURE.md), [Stack](07_TECH_STACK.md), [Repository](08_REPOSITORY_LAYOUT.md).
4. [Datenmodell](09_DATA_MODEL.md), [Zustände](10_STATE_MACHINES.md), [Transaktionen](11_TRANSACTIONS_AND_CONCURRENCY.md).
5. [R-API](12_R_PACKAGE_API.md), [Statistik](13_ANALYTICS_AND_REFERENCE_CASES.md), [Feedback](14_FEEDBACK_AND_QUALITATIVE_WORK.md).
6. [Shiny-UX](15_SHINY_UX_AND_MODULES.md), [Identität](16_AUTHENTICATION_AND_SECURITY.md), [Datengovernance](17_DATA_GOVERNANCE.md).
7. [Jobs und Nachrichten](18_JOBS_AND_COMMUNICATIONS.md), [Berichte](19_REPORTING_AND_EXPORTS.md), [Betrieb](20_DEPLOYMENT_AND_OPERATIONS.md).
8. [Tests](21_TEST_STRATEGY.md), [Roadmap](22_IMPLEMENTATION_ROADMAP.md), [Risiken](23_RISKS_AND_FAILURE_MODES.md).
9. [Studienvorlage](24_STUDY_PROTOCOL_TEMPLATE.md), [Import/Export](25_IMPORT_EXPORT_CONTRACTS.md), [Abnahme](26_ACCEPTANCE_AND_RELEASE.md).
10. [Orchestrator-Prompt](27_ORCHESTRATOR_PROMPT.md), [Arbeitspakete](28_WORK_PACKETS.md), [Übergabevorlagen](29_PROGRESS_AND_HANDOFF_TEMPLATES.md).
11. [Quellen](30_SOURCES_AND_COMPARATORS.md), [Begriffe](31_GLOSSARY.md), [Szenarien](32_END_TO_END_SCENARIOS.md).

## Übergabe an einen Coding-Agenten

Den entpackten Ordner in das Zielrepository unter `docs/spec/` legen. Den vollständigen Text aus `27_ORCHESTRATOR_PROMPT.md` als Arbeitsauftrag verwenden und den tatsächlichen Repositorypfad ergänzen. Der Agent beginnt mit Bestandsaufnahme und dem ersten vertikalen Funktionspfad. Er soll die Dokumente lesen, Entscheidungen festhalten und anschließend Code liefern, nicht nur einen weiteren Plan.

Der erste produktive Release ist bewusst rundenbasiert. Ein offener qualitativer Start ist über Freitext-Items und manuell freigegebene Ableitungen vorgesehen. Real-Time-Delphi, autonome KI-Entscheidungen und beliebige Plugins sind spätere Erweiterungen.

## Paketprüfung

`MANIFEST.json` enthält Dateigrößen und SHA-256-Prüfsummen der Markdown-Dateien. `VALIDATION_REPORT.md` dokumentiert die strukturellen Prüfungen dieses Dokumentenpakets. Diese Prüfungen belegen keine Softwarefunktion und keine wissenschaftliche Validierung einer künftigen Implementierung.
