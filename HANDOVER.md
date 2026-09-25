# Übergabe

Einstieg: CURRENT_STATE.md, docs/IMPLEMENTATION_STATUS.md, AGENTS.md und
`docs/spec/27_ORCHESTRATOR_PROMPT.md`. Der volle Plattformauftrag ist aktiv;
ein bestandener P0-Pfad ist keine P1-Abnahme.

## Fortsetzen

1. Gitstatus und laufende Tests/Entwicklungsprozesse prüfen; vorhandene Arbeit bewahren.
2. `.checks/` für die jeweils aktuellen Logs nutzen; historische Fehlversuche
   nicht mit späteren bestandenen Läufen verwechseln.
3. `Rscript scripts/bootstrap.R` bei fehlenden R-Abhängigkeiten.
4. Datenbank läuft separat auf Loopback-Port 55439. Keine anderen Container ändern.
5. `DELPHYR_TEST_DB=true Rscript scripts/integration.R` und
   `Rscript scripts/demo-e2e.R` prüfen reale Datenbankverträge.
6. `Rscript scripts/check-packages.R` baut beide Packages samt Vignetten.
7. `bash scripts/restore-check.sh` erstellt ein isoliertes Backup-/Restoreexperiment.
8. `Rscript scripts/start-demo.R manager` startet eine lokale Demo; separate
   synthetische Panelsitzung mit `Rscript scripts/start-demo.R 1 3850`.
   `Rscript scripts/worker.R` bearbeitet dauerhaft geplante Jobs.

Keine echte Rekrutierung, externe Nachrichten oder Produktionsdeployments.
`admin/` und lokale Daten bleiben ignoriert. Keine angewandte SQL-Migration ändern;
weitere Korrekturen als neue nummerierte Migration ergänzen.

## Neuer integrierter Stand

338 reale PostgreSQL-Assertions, 77 Offline-Assertions und 115 App-Assertions;
beide lokalen Packagechecks Status OK. Die endgültige Aufteilung, Builds und
Restorehashes stehen in `docs/validation/2026-09-25.md`. Institutionelle Gates,
Stock-OSS-Headertransport und Einladungsoberflächen bleiben ausdrücklich offen.

Elf Migrationen sind angewandt und gefroren. Entwürfe künftiger Migrationen zuerst
außerhalb des `*.sql`-Globs vorbereiten, dann als fertig geprüfte Datei hinzufügen;
ein paralleler Integrationslauf wendet jede sichtbare SQL-Datei an. Es werden
niemals registrierte Checksummen auf nachträglich geänderte Dateien umgeschrieben.

Ausgewählte Studienartefakte zusammen mit der Datenbank prüfen:
`DELPHYR_RESTORE_STUDY=$(cat .checks/latest-e2e-study.txt) scripts/restore-check.sh`.
Der Auth-Qualifikationspfad und seine kontrollierten Start-/Stopbefehle stehen in
`docs/authentication.md`. Private Authfixtures niemals veröffentlichen.
