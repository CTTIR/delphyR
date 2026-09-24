# Repositorystruktur und Entwicklungsregeln

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Monorepository

```text
delphyr/
  README.md
  AGENTS.md                    # aus freigegebenem Arbeitsvertrag ableiten
  LICENSE                     # erst nach Lizenzentscheidung finalisieren
  renv.lock
  .gitignore
  packages/
    delphyr/
      DESCRIPTION
      NAMESPACE
      R/
        domain-study.R
        domain-round.R
        domain-item.R
        validate-protocol.R
        validate-response.R
        analyse-consensus.R
        analyse-stability.R
        service-round.R
        service-response.R
        service-feedback.R
        service-export.R
        auth-capabilities.R
        repository-postgres.R
        jobs.R
        conditions.R
      inst/
        schema/               # deklarative Konfigurationsschemata
        sql/migrations/
        templates/            # keine produktiven Studien- oder Kontaktdaten
        extdata/              # ausschließlich synthetische Beispieldaten
      tests/testthat/
      vignettes/
      man/
    delphyrApp/
      DESCRIPTION
      NAMESPACE
      R/
        run_app.R
        app_ui.R
        app_server.R
        mod_panel.R
        mod_rating.R
        mod_feedback.R
        mod_study_setup.R
        mod_round_control.R
        mod_item_editor.R
        mod_analysis.R
        mod_exports.R
        mod_audit.R
      inst/app/www/
      tests/testthat/
  apps/delphyr/app.R
  worker/run_worker.R
  deploy/
    compose.yaml
    Dockerfile
    nginx.conf.template
    shiny-server.conf.template
    env.example
    systemd/
  scripts/
    bootstrap.R
    migrate.R
    seed_demo.R
    verify_restore.R
  reports/templates/
  tests/
    integration/
    e2e/
    security/
    load/
    fixtures/
  docs/
    spec/                     # dieses Dokumentenpaket
    adr/
    runbooks/
    generated/
  .github/workflows/          # falls GitHub als CI-Plattform gewählt
```

Die Struktur ist ein Zielbild. Bestehende Repositories respektieren und sinnvoll integrieren. Kein automatisches Umbenennen oder Verschieben bestehender Nutzerarbeit, nur um die Baumdarstellung exakt nachzubauen.

## Paketgrenzen

Domainfunktionen erhalten gewöhnliche R-Objekte, keine Shiny-reactives. Services erhalten Repositoryadapter und Actor-Kontext. UI-Module beziehen ihre Abhängigkeiten über Initialisierung, nicht über zufällig vorhandene globale Variablen. Der Worker nutzt dieselben Services und Analysefunktionen.

Datenbankmigrationen haben genau eine maßgebliche Quelle: `packages/delphyr/inst/sql/migrations/`. Kopierte Migrationsdateien im Deployordner sind zu vermeiden. Das Schema und der Paketcode werden gemeinsam versioniert.

## Codekonventionen

- `snake_case` für R-Funktionen, SQL-Spalten und deklarative Schlüssel.
- Packagefunktionen mit explizitem Namespace aufrufen, besonders in Services.
- Exportierte Funktionen benötigen Argumentvertrag, Rückgabewert, Fehlerbedingungen und ein ausführbares synthetisches Beispiel.
- Keine `eval(parse(...))`-Konfigurationen, versteckten Working-Directory-Wechsel oder `setwd()`-Abhängigkeiten.
- Keine `install.packages()`-Aufrufe beim Appstart.
- Zeit, Zufall und IDs in reinen Tests injizierbar gestalten.
- Keine produktiven Zugangsdaten in `.Renviron`, Beispielen, Screenshots oder CI-Artefakten einchecken.
- Benutzertexte über einen Übersetzungskatalog, Fehlercodes sprachunabhängig.

## Konfigurationsebenen

Produktkonfiguration: Ports, DB-Endpunkt, Authgateway, Speicherpfad, Mailadapter. Studienkonfiguration: Instrumente, Regeln, Fristen, Feedback und Rekrutierung. Sessionkonfiguration: verifizierte Identität, ausgewählte Studie und Anzeigepräferenzen. Diese Ebenen nicht in einer globalen YAML-Datei vermischen.

## Branches und Änderungen

Kleine nachvollziehbare Änderungseinheiten; jede Einheit führt passende Tests mit. Schemaänderungen müssen Migration, Rückwärtskompatibilitätsentscheidung und Rollback-/Recovery-Verfahren enthalten. Bestehende Änderungen im Workspace vor Beginn erfassen und nicht überschreiben.

Generated files sind als solche markiert. `NAMESPACE` und Rd-Dokumentation werden mit dem gewählten Werkzeug erzeugt. Ein großer Formatierungscommit darf keine fachlichen Änderungen verstecken.

## Dokumentation

Mindestens Vignetten für: Studie konfigurieren; zwei Runden synthetisch auswerten; Konsensprofile; qualitative Herkunft; Import/Export; Deployment; Rechte und Datenschutzgrenzen. Softwarezitation mit tatsächlichen Autoren, Version und gegebenenfalls DOI erst nach Veröffentlichung erzeugen.
