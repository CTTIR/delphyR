# Implementierungsplan und Release-Gates

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Grundsatz

In vertikalen, überprüfbaren Schritten implementieren. Zuerst einen vollständigen Pfad mit synthetischen Daten herstellen; danach methodische Breite, Mehrbenutzerhärte und Betriebsfähigkeit vervollständigen. Keine produktive Freigabe allein wegen einer gut aussehenden Oberfläche.

## Phase 0 — Bestandsaufnahme und Entscheidungen

Repository und lokale Anweisungen prüfen; vorhandene Änderungen schützen; installierte R-/DB-/Systemtools erfassen; Annahmen aus ADR-Datei übernehmen; offene produktive Konfiguration getrennt halten. Ergebnis: kurzer Implementierungsplan, tatsächliche Verzeichnisstruktur, klare Grenze zwischen Demo und Produktion. Keine wiederholte Nachfrage zu reversiblen Architekturdetails, die diese Spezifikation bereits entscheidet.

## Phase 1 — Kern und Referenzanalytik

Packages scaffolden; Domainobjekte und Conditionvertrag; Protokollvalidator; Rating-/Missingvertrag; Konsens und deskriptive Werte; handberechnete Referenztests; synthetische Fixtures; erste Vignette. Gate: reine Auswertung ohne Shiny/DB möglich und korrekt. Noch keine Behauptung vollständiger Studie.

## Phase 2 — Datenbank und sicherer Schreibpfad

Migrationen, Repositoryadapter, Actor-/Capabilitymodell, Enrollment, Antwortrevisionen, Save, Submit, Close, Idempotenz. Gate: konkurrierende Zugriffe und Studienisolierung mit echter PostgreSQL-Datenbank getestet. Kein zusätzlicher UIkomfort vor zuverlässiger Speicherung.

## Phase 3 — Erster zweirundiger Funktionspfad

Shiny-Panelmodule; Studienentwurf; feste Testidentitäten nur Development; Runde 1 beantworten und abgeben; schließen und einfrieren; analysieren; Feedback prüfen/freigeben; Runde 2 vorbereiten; eigene Vorantwort und Panelstatistik zeigen; exportieren. Gate P0: Demonstration vollständig, reproduzierbar und eindeutig nicht produktiv.

## Phase 4 — Vollständiges Studienmanagement

Protokolleditor, CSVimport, mehrere Dimensionen, Stakeholder, explorative Freitextphase, qualitative Herkunft, Revision/Split/Merge, DE/EN, Regeln und Sensitivitäten. Gate: alle methodischen P1-Workflows mit synthetischer Studie nachgewiesen.

## Phase 5 — Identität, Governance und Kommunikation

OIDC-Gateway real integrieren; externe Kontobindung; Einwilligung; Rechte in laufenden Sessions; privater Export; Mailoutbox und Kampagnenfreigabe; Rückzug und Aufbewahrung. Gate: Security-/Governancefälle bestehen; echter Mailversand bleibt bis autorisierter Kampagne deaktiviert.

## Phase 6 — Bericht und Betrieb

Quarto, Manifest, Offline-Reproduktion, Workerhärtung, Monitoring, Migrationsrunbooks, Backup/Restore, Container-/systemd-Artefakte, Lasttests. Gate: P1 technisch bereit; fehlende institutionsbezogene Freigaben ausdrücklich ausweisen.

## Phase 7 — Pilot und Produktionsfreigabe

Studienprotokoll und Zugangskonfiguration vervollständigen; genehmigten Pilot durchführen; Nutzbarkeitsprobleme beheben; neue Fehler mit Regressionstests sichern; finale Abnahme dokumentieren. Erst nach den produktiven Gates mit echter Rekrutierung beginnen.

## Meilensteine

| Meilenstein | Überprüfbares Ergebnis | Nicht ausreichend |
|---|---|---|
| M1 | korrekte Offline-Analyse | leere Packagehülle |
| M2 | sichere persistente Abgabe | Daten nur im reactiveValues |
| M3 | vollständiger zweirundiger Demopfad | statischer Dashboardmock |
| M4 | methodisch vollständiges Studienmanagement | freie Texte ohne Herkunft |
| M5 | echte Authintegration und Mail-Sink-Prozess | versteckte Admin-Tabs |
| M6 | reproduzierbarer Export und Restore | Backupskript ohne Restoretest |
| M7 | dokumentierte Freigabe | allgemeines „alles getestet“ |

## Priorisierung bei Engpässen

Keine Kürzungen bei Datenspeicherung, Autorisierung, Freeze, Fehlermeldungsehrlichkeit oder wissenschaftlicher Klassifikation. Zuerst optionale Diagramme, XLSXimport, dekorative Features und Spezialmethoden verschieben. Scopeänderung schriftlich kennzeichnen; P1 nicht umdefinieren, um einen unfertigen Zustand als fertig zu präsentieren.

## Aufwand und Ressourcen

Keine belastbare Kalender-/Budgetschätzung ohne Team, vorhandene Infrastruktur und verbindliche Spezialmethoden. Der Plan ist ein Arbeitsstrukturplan, keine Zeitgarantie. Schätzungen nach Phase 1/2 anhand tatsächlicher Durchlaufzeit, Integrationserfahrung und institutioneller Anforderungen ergänzen.

## Spätere Roadmap

Real-Time-Delphi als eigener Entwurf mit zeitabhängigen Feedbackdaten; Rankings mit vollständiger Missing-/Tie-Methodik; institutionenübergreifende Mandanten; API für externe Studienverwaltung; optionale KI-Redaktionshilfe. Jede Erweiterung erhält eigene Datenmigrationen und Validierungsfälle.
