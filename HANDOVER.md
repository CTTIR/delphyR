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
