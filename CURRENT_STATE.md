# Aktueller Stand

Stand: 2026-09-25. Repository: CTTIR/delphyR, Branch main.

Die Implementierung umfasst PostgreSQL-Services, Shiny, Worker, Exporte,
qualitative Provenienz und synthetische Kommunikationskampagnen.
`admin/` bleibt ignoriert; die Spezifikation unter `docs/spec/` ist maßgeblich.

## Bereits geprüft

- 63 Offline-/Methodikassertions ohne Warnungen.
- PostgreSQL-Speicherung, Rollen, Studien-/Personengrenzen, Revisionen, Retry,
  Save/Save, Save/Close, Doppelsubmit: 59 Assertions.
- Sechs zusätzliche Vertragsassertions für Versionsidentität, Folgerunden,
  Revokation und Fristablauf während einer Sperrwartezeit.
- Zweirundiger Servicepfad: 30 synthetische Personen, 12 zweisprachige Items,
  720 bestätigte Antworten, Feedback, Queue und Offline-Exportreproduktion.
- Datenbankbackup in frische Instanz wiederhergestellt; Tabelleninhalte,
  Schema, Migrationshashes und Snapshots stimmen überein.

## Verifizierter Integrationsstand

Beide Packages bestehen `R CMD check --as-cran --no-manual` mit Status OK
(CRAN-Incomingprüfung deaktiviert). 63 reine Kernassertions, 150 PostgreSQL-
assertions und 40 Shiny-Modulassertions bestehen. Ein echter Chromium-Panelpfad
unter delphyr_runtime bestätigt Einwilligung, Revision 1, Wert 7 und Submission.
Managementdatum, DE/EN-Anzeige und Rollenansicht separat im Browser geprüft.

Das volle P1-Produkt ist noch nicht fertig. Maßgeblich sind
`docs/IMPLEMENTATION_STATUS.md`, `docs/requirements-matrix.md` und
`docs/validation/2026-09-25.md`. Offene technische Arbeit: realer Testgateway,
Management-End-to-End, redaktionelle UI, weitere Export-/Reportprofile,
Autosave/Netzabbruch, Artefaktrestore, Last- und Accessibilitymatrix.

## Lokale Umgebung

Isolierter Container `delphyr-dev-postgres`, nur 127.0.0.1:55439, DB `delphyr`.
Ausschließlich synthetische Daten. Lokale R-Abhängigkeiten `.R-library/` plus
bestehende Benutzerbibliothek; Dateien und Exporte `.local/`, `.artifacts/`.
Keine OIDC-/SMTP-Produktionskonfiguration, kein produktiver Einsatz freigegeben.

## Nächster Schritt

`DELPHYR_TEST_DB=true Rscript scripts/integration.R`, danach
`Rscript scripts/demo-e2e.R` und `Rscript scripts/check-packages.R`.
Aktuelle Liveprozesse und Gitstatus vor Fortsetzung prüfen. Die lokale
Manager-Demo wurde auf http://127.0.0.1:3849 gestartet; ein separater Worker
verarbeitet ausschließlich synthetische Jobs und Datenbank-Sinknachrichten.
IDs nicht aus dieser Datei übernehmen: Prozesse vor Fortsetzung live abfragen.
