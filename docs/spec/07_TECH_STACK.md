# Technologiestack und Abhängigkeitsstrategie

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Vorgeschlagener Stack

Die folgende Auswahl ist eine Architekturentscheidung für delphyR. Vor Installation konkrete kompatible Versionen, Lizenzen und Supportstände prüfen. Keine erfundenen Mindestversionen aus diesem Dokument ableiten.

| Bereich | Auswahl | Aufgabe / Grenze |
|---|---|---|
| Sprache | R, unterstützte stabile Version | Methodik, Services, UI und Worker |
| Kernpackage | delphyr | Domain, Validierung, Analyse, Services, DB-Adapter |
| UI-Package | delphyrApp | Shiny-Module und Appstart |
| Oberfläche | shiny, bslib | Reaktive Oberfläche und responsive Layouts |
| Appstruktur | golem als Entwicklungsgerüst | UI-Package strukturieren; nicht als Methodikkern verwenden |
| Tabellen | DT oder reactable, eine Wahl per ADR | Adminansichten; sensitive Daten nicht unkontrolliert an Browser senden |
| Grafik | ggplot2 | Reproduzierbare Verteilungen und Verlaufsgrafiken |
| Datenbank | PostgreSQL, unterstützte Hauptversion | Produktionsdaten, Zustände und Jobqueue |
| DB-Zugriff | DBI, RPostgres, pool | Parametrisierte Abfragen, Verbindungen und Transaktionen |
| Konfiguration | yaml, jsonlite, explizite Validatoren | Deklarative Regeln; keine Auswertung von R-Code |
| Hashing | digest oder geeignete Kryptobibliothek | Inhaltsprüfsummen; kein selbstgebautes Passwortsystem |
| IDs | UUID-Bibliothek oder PostgreSQL-Funktion | Zufällige opaque IDs, keine Sicherheitswirkung allein |
| Testbasis | testthat | Domain-/Service-/Integrationsprüfungen |
| Shiny-Tests | shiny::testServer, shinytest2 | Module und Browserabläufe |
| Packagepflege | roxygen2, pkgdown, rcmdcheck | API-Dokumentation und Packageprüfung |
| Versionierung | Git, renv, Container-Digests | Nachvollziehbare Quellen und Laufzeitumgebung |
| Berichte | Quarto, optional PDF-Toolchain | HTML zuerst; PDF/DOCX bei eingerichteter Runtime |
| Hosting | Shiny Server Open Source | Prozess-/Apphosting auf Linux |
| Edge | Nginx oder bestehender institutioneller Proxy | HTTPS und WebSocket-Weiterleitung |
| Anmeldung | OIDC-Provider + OAuth2 Proxy oder geprüfter institutioneller Gateway | Identität vor Appzugriff |
| Jobs | Separater R-Prozess + PostgreSQL-Queue | Dauerhafte asynchrone Aufgaben |
| E-Mail | SMTP-/API-Adapter, lokaler Mail-Sink | Freigegebene Nachrichten außerhalb Shiny-Sitzungen |
| Betrieb | systemd oder Container Compose | Wiederanlauf, Logs und Ressourcenlimits |

## Package-Abhängigkeiten

`delphyr` darf Shiny nicht importieren. Reine Analytik soll mit möglichst wenigen Abhängigkeiten funktionieren. DB-/Servicefunktionen können DBI und RPostgres benötigen; optionale Reporting-/Plottingteile gehören nach Möglichkeit in `Suggests` und prüfen ihre Verfügbarkeit explizit. Nicht jede Tabellenoperation rechtfertigt einen zusätzlichen Frameworkimport.

`delphyrApp` hängt von `delphyr` ab. Umgekehrte Abhängigkeit ist verboten. Ein `run_app()` im UI-Package ist der kanonische Start. Ein optionaler Convenience-Wrapper im Kern wäre nur mit optionaler Abhängigkeit und ohne Zirkel zulässig; für P1 weglassen.

## Versionsstrategie

Eine getestete Version pro Produktionskomponente wird im Lockfile beziehungsweise Image-Digest festgeschrieben. Keine `latest`-Tags im freigegebenen Deployment. R-Version, Betriebssystembibliotheken, PostgreSQL-Hauptversion, Quarto und Browser für Tests separat erfassen: `renv` allein versioniert diese nicht.

Development kann neue Versionen prüfen; Produktion aktualisiert erst nach Regressionstests und Datenbankkompatibilitätsprüfung. CI muss Packageversionen und Systeminformationen in ihren Artefakten ablegen. Lockfiles dürfen keine Zugangstokens oder privaten Repositorypasswörter enthalten.

## Wichtige Plattformgrenzen

Shiny Server Open Source hat keine integrierte Benutzerauthentifizierung. Die App darf nicht auf automatisch gefüllte `session$user`-Werte vertrauen. Die Headerübergabe des gewählten Gateways muss im tatsächlichen HTTP- und WebSocket-Aufbau getestet werden. Direkter Zugriff auf den Shiny-Port wird gesperrt. [Posit-Dokumentation](https://shiny.posit.co/r/articles/share/shiny-server/)

Shiny Server Pro ist keine empfohlene Zwischenlösung: Laut Posit endete dessen Support am 31.03.2026. Die Zielarchitektur bleibt Open Source Shiny Server mit externem Zugangsschutz; ein Wechsel zu Posit Connect wäre eine gesonderte Betreiberentscheidung. [Posit-Migrationshinweis](https://docs.posit.co/how-to-guides/guides/migrate-shiny-server-pro-to-connect.html)

DBI stellt Transaktionsschnittstellen bereit; Pool verwaltet wiederverwendbare Verbindungen. Transaktionen dürfen nicht versehentlich auf verschiedene Poolverbindungen verteilt werden. [DBI](https://dbi.r-dbi.org/reference/dbWithTransaction.html), [pool](https://rstudio.github.io/pool/)

## Bewusst nicht eingebaut

Redis, Kubernetes, Kafka und ein separates REST-Backend sind keine P1-Voraussetzung. Ein validierter PostgreSQL-Worker genügt für den geplanten Maßstab. Diese Komponenten nur ergänzen, wenn Messungen oder institutionelle Infrastruktur ihren Bedarf begründen.

## Entwicklungsumgebung

Eine lokale Compose-Umgebung soll PostgreSQL, Test-Identity-Provider beziehungsweise geprüftes Auth-Testsetup und Mail-Sink bereitstellen. Alle Beispieldaten sind synthetisch. Browser- und Integrationsprüfungen verwenden dieselbe Datenbankschemaversion wie die App. Entwickler können reine Packageprüfungen ohne laufenden Shiny Server ausführen.
