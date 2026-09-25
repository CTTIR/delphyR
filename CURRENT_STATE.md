# Aktueller Stand

Stand: 2026-09-25. Repository CTTIR/delphyR, Branch main.
`admin/` bleibt ignoriert; maßgebliche Spezifikation unter `docs/spec/`.

## Verifizierte synthetische Implementierung

Kernpackage, PostgreSQL, Worker und Shiny unterstützen Rundenfreigabe,
Einwilligung, bestätigte Saves, Abgabe, Snapshot, Analyse, Feedback und Export.
Ergänzt: versionierte Protokollamendments, qualitative Redaktion mit unabhängiger
Freigabe, Kampagnen im lokalen Sink, Panel-CSV-Vorschau und atomarer Import,
kontogebundene Einmaltoken-Services, Teilnahmerückzug sowie Stakeholderhistorie.
Quarto-Berichte und private Exportsupplemente sind offline reproduzierbar.

Der eingefrorene kombinierte Testlauf umfasst 338 PostgreSQL-Assertions ohne
Fehler/Warnungen/Skips. Separat: 77 Offline-Assertions (47 explizite DB-Skips)
und 115 Shiny-Assertions. Reale Chromium-Pfade prüfen Panel/Abgabe, Netzabbruch,
Redaktion, Kampagnen, Protokollamendments, Panelimport und rollenabhängige Navigation.
Der zweirundige Servicepfad bestätigt 720 Antworten von 30 synthetischen Personen.
Elf Migrationen sind checksummiert; alte SQL-Dateien nicht verändern.
Beide Packagechecks bestehen lokal und in Hosted CI für `0f03ae6`:
https://github.com/CTTIR/delphyR/actions/runs/36123381681.

## Authentifizierung und Grenzen

Realer Keycloak-/OAuth2-Proxy-Login mit direktem Shiny-Backend: zwölf Prüfungen
bestanden. Stock Shiny Server OSS verwirft die erforderlichen Identitätsheader;
dieser Zielpfad ist nachweislich nicht qualifiziert. Beide Ergebnisse getrennt
unter `docs/authentication.md`. Die Tokenannahme ist als Kernservice geprüft,
aber noch nicht als Browserworkflow integriert.

Die vollständige P1-Plattform ist noch nicht abgenommen. Institutionelle
Governance, produktives Hosting, Einladungsscreens, weitere Exportprofile,
Reminderplanung, vollständige Management-/Browser-/Assistenztechnikabnahme und
wissenschaftliche Autorenangaben bleiben sichtbar in
`docs/IMPLEMENTATION_STATUS.md` und `docs/requirements-matrix.md`.

## Lokale Umgebung und Fortsetzung

PostgreSQL `delphyr-dev-postgres`, ausschließlich 127.0.0.1:55439, DB delphyr.
App/Worker verwenden `delphyr_runtime`; Migrationen verwenden eine getrennte
Ownerverbindung. Private Dateien `.local/`, `.checks/`, `.artifacts/`, `.R-library/`.
Der lokale Authpfad verwendet 127.0.0.1:4189 und eine isolierte Docker-Backendgruppe.

`HANDOVER.md` enthält reproduzierbare Befehle. Aktuelle Prozesse und Gitstatus
vor Fortsetzung prüfen. Nicht von alten Prozess-IDs ausgehen. Kein externer
Mailversand oder produktiver Einsatz wurde freigegeben.
