# Implementierungsstatus

Stand: 2026-09-25. Entwicklungsstand 0.0.1, synthetische P0-Umgebung.
Die vollständige P1-Plattform ist **noch nicht abgenommen**.

## Implementiert und geprüft

- Kernpackage mit Protokoll-/Skalen-/Antwortprüfung, deterministischer Analytik,
  Gruppenregeln, Missingness, Vergleichbarkeit und kleinteiliger Feedbackunterdrückung.
- PostgreSQL mit sechs checksummierten Migrationen, studienübergreifenden
  Integritätsconstraints und technischen Unveränderlichkeitssperren.
- Aktuelle Rollenprüfung, versionsgebundene Einwilligung, Revisionen und
  inhaltsgebundene Retryreceipts; Save/Submit/Close einschließlich realer Konkurrenztests.
- Freigabe/Öffnung/Abschluss, fixierte Snapshots mit Submission-/Revisionslinks,
  Analyse, exakte Feedbackfreigabe, eigene Vorantwort und begründete Itementscheidungen.
- Dauerhafte Analyse-/Exportjobs mit Leases, Versuchslimit und erneuter Rechteprüfung.
  Private numerische Exporte mit Dateimanifest, HTML-Ergebnistabelle und Offline-Reproduktion.
- Qualitative Originale, getrennte Redaktion/Zusammenfassung, unabhängige Freigabe,
  Themen, Codierungen, Quellenbezüge und unveränderliche Split-/Merge-Historie als Services.
- Synthetische Kampagnen mit exakter Vorschau/Freigabe, Outbox, Abbruch,
  Eligibilityprüfung und ausschließlich lokalem Datenbank-Sink.
- `delphyrApp`: DE/EN-Panel, bestätigte Saves, Konflikt-/Fehlerzustände,
  Einwilligung, Abgabequittung; Management für Rundenzustände, Analyse, Feedback,
  CSV-Instrumentvorschau, Folgerunde und autorisierten Export.
- README, ausführbare Vignetten beider Packages, reproduzierbare Browserfixtures,
  Lockfile, gepinnte CI-Aktionen und lokale Betriebs-/Restoreanleitung.

## Tatsächlich ausgeführte Nachweise

| Prüfung | Ergebnis | Umfang |
|---|---|---|
| Reine Kernverträge | 63 Assertions, keine Warnungen | Methodik, Hashing, Validierung |
| PostgreSQL-Serviceverträge | 59 Assertions | Identität, Revisionen, Rollback, vier Konkurrenzfälle |
| Zusätzliche Rennen/Versionsverträge | 6 Assertions | Revokation/Frist nach Lockwartezeit, Eintritt/Return, Itemversion |
| Worker und Export | 17 Assertions | Leasewiederaufnahme, Versuchslimit, Rechte, Dateimanipulation |
| Qualitative Services | 30 Assertions | Originalschutz, unabhängige Freigabe, Herkunft, Isolation |
| Kommunikations-Sink | 38 Assertions | Freigabe, Dedupe, Unterdrückung, Unsicherheit, Isolation |
| Zweirundiger Servicepfad | bestanden | 30 Personen, 12 Items, 720 Antworten, eigene Vorwerte, Exportreproduktion |
| Shiny-Module und Browser | bestanden, siehe Testbericht | Simulierte Services und separater echter PostgreSQL-Panelpfad |
| Packagechecks | beide Status OK | `--as-cran --no-manual`, Incomingprüfung deaktiviert |
| Datenbankrestore | bestanden | 44 Tabellen, 32 Snapshots, sechs Migrationen in frischer Instanz |

Logs liegen lokal unter `.checks/`. Einzelheiten und tatsächliche Grenzen:
[Validierung](validation/2026-09-25.md), [Browser-QA](../packages/delphyrApp/inst/qa/README.md).
Hosted CI wird separat vom lokalen Nachweis bewertet.

## Offene Arbeit bis P1

- Institutionelle OIDC-/Gatewayintegration einschließlich WebSocket, Sessionablauf,
  Einladungstoken und externe Kontobindung; getrennte produktive DB-/Workerrollen.
- Panel-/Kontaktdatenimport, tatsächliche Governance, vollständige Protokollamendments,
  Widerrufs-/Lösch-/Aufbewahrungsprozesse und redaktionelle Managementoberflächen.
- Vollständige qualitative Herkunft im Teilnehmerfeedback und freigegebene Freitextexporte.
- Produktiver Provideradapter, Reminderpläne, Zeitzonen-/Ruhezeitregeln und
  kontrollierte Auflösung unklarer Zustellungszustände. Kein externer Versand freigegeben.
- Vollständiger Quarto-Studienbericht, zusätzliche Exportprofile, kombinierter
  Datenbank-/Artefaktrestore und bereinigte Aufbewahrung verwaister Dateien.
- Autosave, Netzunterbrechung/Wiederaufnahme im Browser, vollständiger
  Management-Browserpfad, Tastatur-/Assistenztechnik-/Browsermatrix und Lasttest.
- Vollständiges produktives Shiny-Server-/Proxydeployment, Release-/Pilotabnahme.

Fehlende P1-Funktionen sind keine optionalen P2-Erweiterungen. Produktionsangaben
und tatsächliche Studienfreigaben werden nicht aus synthetischen Fixtures abgeleitet.

## Start und Fortsetzung

[README](../README.md), [Betrieb](operations.md), [CURRENT_STATE](../CURRENT_STATE.md)
und [HANDOVER](../HANDOVER.md). `admin/`, lokale Daten, Bibliotheken und Backups
bleiben ignoriert. Nächster großer Arbeitsschritt: vollständige Managementabläufe
und echte Testgatewayintegration mit getrennten Sessions; die übrigen offenen
P1-Gates bleiben in der [Anforderungsmatrix](requirements-matrix.md) sichtbar.
