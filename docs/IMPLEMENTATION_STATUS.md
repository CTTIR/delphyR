# Implementierungsstatus

Stand: 2026-09-24. Aktueller Meilenstein: Bestandsaufnahme abgeschlossen.

## Implementiert

- Repository, MIT-Lizenz, lokaler ignorierter admin-Ordner.
- Spezifikationskopie und Arbeitsvertrag; keine bestehende Implementierung überschrieben.

## In Arbeit

- WP-01/02: Domain, Validatoren und reine Referenzanalytik.
- Lokale PostgreSQL-Testumgebung und RPostgres-Projektbibliothek.

## Noch offen

WP-03 bis WP-15 sowie alle P0/P1-Abnahmegates. Noch keine lauffähige App.
Produktive OIDC-/Mailkonfiguration, institutionelle Angaben, Einwilligung,
Aufbewahrung und wissenschaftliche Freigaben werden nicht erfunden.

## Umgebung

R 4.6.1; vorhandene DBI-, Shiny-, bslib-, testthat-, jsonlite-, digest- und
roxygen2-Installation. Docker verfügbar. PostgreSQL wird isoliert eingerichtet.

## Prüfung

Gitstatus vor Arbeitsbeginn sauber. Spezifikation gelesen; Architektur und
Testpflichten übernommen. Softwaretests noch nicht ausgeführt.
