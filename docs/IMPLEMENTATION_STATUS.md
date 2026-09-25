# Implementierungsstatus

Stand: 2026-09-25. Version 0.0.1, ausschließlich synthetische Entwicklung.
Die vollständige P1-Plattform ist **noch nicht abgenommen**.

## Implementiert und lokal geprüft

- Deterministische Offlineanalytik: Skalen, Missingness, Nenner, Gruppenregeln,
  Versionen, Stabilität und kontrollierte Feedbackunterdrückung.
- Elf checksummierte PostgreSQL-Migrationen, Unveränderlichkeit, aktuelle Rechte,
  Studien-/Personenisolierung und inhaltsgebundene Retryreceipts.
- Einwilligung, bestätigte Revisionen und atomare Abgabe/Schließung; reale
  Konkurrenzprüfungen einschließlich Teilnahmerückzug gegen laufende Saves.
- Protokollamendments mit Vorgänger, Begründung, Versionshash und Prüfung belegter
  Gruppen sowie unveränderter Skalenidentität; bestehende Runden bleiben unverändert.
- Rundenzustände, eingefrorene Snapshots, Analyse, genaue Feedbackfreigabe,
  persönliche Vorantworten und menschliche Entscheidungen.
- Qualitative Originale, separate Redaktion/Zusammenfassung, unabhängige Freigabe,
  Themen, Codierung, Quellenzuordnung und Split-/Merge-Historie.
- Synthetische Kampagnen mit exakter Empfängervorschau, Freigabe, Outbox, Leases,
  Unterdrückung und ausschließlich lokalem Datenbank-Sink.
- Panelimport mit Zeilenfehlern, konservativer Normalisierung, blockierenden
  Dublettenreviews, genauer Dateifreigabe und atomarem Receipt; Kontakte getrennt.
- Einmaltoken-Services: kryptographische Zufallswerte, ausschließlich Tokenhashes
  gespeichert, Ablauf, Revokation, explizit vorab genehmigte Issuer-/Subject-Bindung,
  bestätigte Annahme und echte Konkurrenzprüfung. Keine Kontozuordnung per E-Mail.
- Synthetischer Teilnahmerückzug mit ausdrücklich erklärtem Datenverbleib;
  künftige Stakeholderänderungen verändern keine früheren Rundenzuordnungen.
- Durable Analyse-/Exportjobs, private numerische Exporte, Quarto-Berichte,
  Datendictionary, Instrument-/Nenner-/Missingness-/Entscheidungs-/Herkunftstabellen,
  Manifest und unabhängige Offline-Reproduktion.
- DE/EN-Shiny mit bestätigten Saves, Fehler-/Konfliktzuständen, Verbindungswarnung,
  ausdrücklicher Abgabe und Rückzug; rollenabhängige Navigation, Protokollreview,
  Management, Redaktion, Panelimport und Kampagnenfreigabe.
- README und ausführbare Vignetten nach den geprüften CTTIR-Konventionen;
  mobile Ansichten, Live-Status und reproduzierbare Browserprüfungen.

## Ausgeführte Prüfungen

| Prüfung | Ergebnis | Abgrenzung |
|---|---|---|
| Offline-Testlauf | 77 Assertions | 47 DB-Testfälle dort bewusst übersprungen |
| PostgreSQL-Integration | 338 Assertions, keine Fehler/Warnungen/Skips | Aufteilung im Validierungsbericht |
| Shiny-Module | 115 Assertions | Service-/Session-/Navigationstests |
| Reale Chromium-Pfade | bestanden | Panel, Netzabbruch, Tastaturpfad, Redaktion, Kampagne, Protokoll, Import, Navigation |
| Reale OIDC-Integration | 12 Prüfungen bestanden | Direkter Shiny-Backendpfad, lokal synthetisch |
| Stock Shiny Server OSS | nicht qualifiziert | Header gehen im WebSocket-Transport verloren; Sitzung wird korrekt abgewiesen |
| Zweirundiger Servicepfad | bestanden | 30 Personen, 12 bilinguale Items, 720 Antworten, Feedback, Exportreproduktion |
| Leere Migration | bestanden | Elf Migrationen, identischer Wiederholungslauf, Servicefixture |
| Packagechecks | beide Status OK im abschließenden lokalen Lauf | Vignetten gebaut; Incomingprüfung deaktiviert |
| DB-/Artefaktrestore | bestanden | Konsistenter DB-Snapshot und ausgewählter Studienexport; keine Produktions-RPO/RTO |
| Lokaler Servicelasttest | 360 Saves bestätigt und neu gelesen | 30 Prozesse, p95 0,083 s; Browser/Internet nicht enthalten |

Details: [Validierung](validation/2026-09-25.md), [Browser-QA](../packages/delphyrApp/inst/qa/README.md),
[Authentifizierung](authentication.md), [Reporting](reporting.md),
[Panelimport](panel-import.md), [Einladungen](invitations.md),
[Teilnahme](participation.md), [Protokolländerungen](protocol-amendments.md).
Keine CRAN-Einreichung oder wissenschaftliche/klinische Validierung behauptet.
Hosted CI wird pro tatsächlichem Commit separat geprüft.

## Verbleibende P1-Arbeit und externe Gates

- Produktive institutionelle Governance, Einwilligungs-/Aufbewahrungs-/Löschregeln,
  Betreiberverantwortung und genehmigter Umgang mit Forschungsdaten.
- Stock-OSS-Hostingentscheidung oder gesonderte Qualifikation des direkten
  Backends mit produktivem TLS, Geheimnisverwaltung und getrennten Betriebsrollen.
- Browserworkflow für Einladungsausgabe/-annahme und vollständige Kontoeinrichtung;
  bestehende vorab provisionierte Konten sind Voraussetzung der geprüften Services.
- Vollständige qualitative Herkunft im Teilnehmerfeedback, freigegebene
  Freitext-/Audit-/Publikationsprofile und wissenschaftliche Autorenangaben.
- Produktiver Provideradapter, Reminderpläne, Ruhezeiten und kontrollierte
  Auflösung unklarer Zustellungen. Kein externer Versand freigegeben.
- Autosave, vollständiger Management-End-to-End-Browserpfad, systematische
  Tab-Reihenfolge/Assistenztechnik-/Cross-Browser-Abnahme und End-to-End-Lasttest.
- Genehmigte Aufbewahrung/Bereinigung, vollständiger Produktivrestore, Pilot-/Releaseabnahme.

Diese Punkte werden nicht durch synthetische Beispiele oder grüne lokale Tests
als erledigt dargestellt. `admin/`, Daten, Backups und lokale Bibliotheken bleiben
ignoriert. Einstieg und reproduzierbare Befehle: [README](../README.md),
[Betrieb](operations.md), [HANDOVER](../HANDOVER.md).
