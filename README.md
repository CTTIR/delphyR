# delphyR

**Rundenbasierte Delphi-Studien nachvollziehbar auswerten.**

delphyR verbindet ein eigenständig nutzbares R-Kernpackage `delphyr` mit einer
Shiny-Oberfläche `delphyrApp` und PostgreSQL als transaktionalem Studienbackend.
Das Kernpackage validiert Studienprotokolle und Antworten, analysiert eingefrorene
Rundendaten und trennt Konsens, deskriptive Veränderung und redaktionelle Entscheidungen.

**Entwicklungsstand:** synthetische Entwicklung und lokale Prüfung. Eine
Produktionsfreigabe oder wissenschaftliche Validierung ist damit nicht verbunden.
Den belegten Funktionsumfang, ausgeführte Prüfungen und offene Abnahmegates enthält
[Implementierungsstatus](docs/IMPLEMENTATION_STATUS.md).

## Installation

Das Repository enthält mehrere Packages. Für die Offlineanalyse genügt `delphyr`;
es benötigt weder eine laufende Shiny-App noch einen PostgreSQL-Server.

```r
# install.packages("remotes")
remotes::install_github("CTTIR/delphyR", subdir = "packages/delphyr",
                        build_vignettes = TRUE)
```

Aus einem lokalen Checkout, im Repositoryverzeichnis:

```sh
Rscript -e 'remotes::install_deps("packages/delphyr", dependencies = TRUE)'
R CMD INSTALL packages/delphyr
```

Die GitHub-Adresse heißt `CTTIR/delphyR`; in R wird das Kernpackage als
`delphyr` geladen. Die lokale Installation allein erstellt keine HTML-Vignette;
deren Quelltext liegt unter [packages/delphyr/vignettes](packages/delphyr/vignettes).

## Erste Auswertung

```r
library(delphyr)

snapshot <- demo_snapshot()
analysis <- analyse_round(snapshot)

# Gesamtergebnis unter der ausdrücklich gepoolten Demoregel
analysis$decisions

# Nenner und fehlende Antworten getrennt berichten
analysis$denominators
analysis$missingness

# Kontrollierter Feedbackentwurf; noch keine Veröffentlichung
feedback <- prepare_feedback(analysis)
validate_feedback(feedback)
```

Alle Demodaten sind synthetisch. Die Beispielschwellen sind keine methodische
Empfehlung. Die Demo enthält zehn gültige Bewertungen: sieben Zustimmungen,
eine Ablehnung und zwei mittlere Bewertungen. Die zweite, leere Panelgruppe bleibt
mit `insufficient_data` sichtbar. `demo_snapshot()` verwendet ausdrücklich die
gepoolte Gruppenregel; `demo_protocol()` fordert standardmäßig ausreichende
Ergebnisse in allen vorgesehenen Gruppen.

## Analyse und Nachvollziehbarkeit

- `new_protocol()` prüft das deklarative Protokoll; `new_scale()` und
  `validate_response()` prüfen Skalen und Antworten.
- `new_snapshot()` bildet einen prüfbaren Rundensatz mit Inhalts-Hash;
  `analyse_round()` liefert Ergebnisse, Nenner, Missingness und Provenienz.
- `compare_rounds()` berichtet gepaarte deskriptive Veränderungen und Ausfälle.
  Neue Itemversionen benötigen eine ausdrückliche Vergleichbarkeitsentscheidung.
- `prepare_feedback()` erstellt einen Entwurf mit Zellunterdrückung.
  Ein solcher Entwurf ersetzt keine redaktionelle Prüfung oder Freigabe.

Gültige Bewertungen bilden den Nenner der Zustimmungsquote. Nicht abgegebene
Antworten, Enthaltungen und fehlende Beurteilbarkeit sind keine Nullbewertungen.
Quartile verwenden Typ 7; Konsensgrenzen werden auf ungerundete Anteile angewendet.

## Lokale Shiny-Demo

Die Demo startet ausschließlich auf Loopback und verwendet synthetische Konten.
Docker, R und die in `renv.lock` dokumentierten Abhängigkeiten werden benötigt.

```sh
Rscript scripts/bootstrap.R
docker compose -f deploy/compose.dev.yaml up -d
Rscript scripts/configure-dev-role.R
Rscript scripts/worker.R
# In einem weiteren Terminal:
Rscript scripts/start-demo.R manager
# Optional eine getrennte synthetische Panelsitzung:
Rscript scripts/start-demo.R 1 3850
```

Studienleitung: <http://127.0.0.1:3849>; erste Panelperson:
<http://127.0.0.1:3850>. Die Studienleitung prüft und öffnet die vorbereitete Runde.
Die Panelperson stimmt der angezeigten Demoinformation zu, speichert Antworten
und gibt sie ausdrücklich ab. Eine geschlossene Runde wird eingefroren; die separate Workerinstanz bearbeitet
anschließend Analyse und Export sowie freigegebene lokale Nachrichtenquittungen.

Berechtigte Redakteure bewahren Originaltexte und getrennte redigierte Fassungen,
Zusammenfassungen, Codierungen und Itembeziehungen. Eine andere berechtigte Person
prüft die genaue Fassung vor Freigabe. Koordinatoren wählen Studienpseudonyme und
prüfen Nachrichtentext und Empfängermenge ausdrücklich; es erfolgt kein E-Mailversand.

`run_app(repo, actor)` verwendet eine feste synthetische Identität für alle Sitzungen
dieser lokalen Instanz. Für getrennte Sitzungen stehen `repo_factory()` und
`actor_factory(session, repo)` zur Verfügung; der Host muss die Identität
serverseitig auflösen. Diese Schnittstellen sind noch kein geprüfter OIDC-Adapter.

Die UI ist im [App-Package](packages/delphyrApp/README.md) mit geprüften Ansichten
dokumentiert. [Betriebsanleitung](docs/operations.md) erläutert den isolierten
Datenbankstart, Wiederherstellung und Grenzen der Entwicklungsumgebung.

Ein vollständiger zweirundiger **Servicepfad** ist unabhängig von der UI ausführbar:

```sh
Rscript scripts/demo-e2e.R
DELPHYR_TEST_DB=true Rscript scripts/integration.R
Rscript scripts/check-packages.R
```

## Private Forschungsberichte

Der numerische Export enthält den reproduzierbaren Snapshot, Protokoll und
Analyseergebnisse sowie ein Datenwörterbuch, eingefrorene Instrumenttexte,
Missingness, strukturierte Itementscheidungen und Itembeziehungen. Qualitative
Originale, redaktionelle Freitextbegründungen und Kontozuordnungen gehören nicht
zu diesem Profil. Pseudonyme sind nicht anonym.

Mit installierter Quarto-Laufzeit erstellt der Worker einen HTML-Bericht aus einem
festen Pakettemplate. Fehlende Autorenangaben werden ausdrücklich ausgewiesen.
Ohne optionale Renderlaufzeit entsteht ein gekennzeichneter einfacher HTML-Fallback;
ein tatsächlicher Renderfehler lässt den Auftrag fehlschlagen. Das Manifest nennt
den Renderer und prüft sämtliche ausgelieferten Dateien.

## Dokumentation und Entwicklung

- [Nutzungsanleitung](docs/user-guide.md): Installation, Offlineworkflow und Grenzen.
- [Ausführbare Offlinevignette](packages/delphyr/vignettes/offline.Rmd): zwei Runden,
  Gruppenregeln, Missingness und Feedback. Nach Installation mit Vignetten:
  `vignette("offline", package = "delphyr")`.
- [Berichte und Exportprofile](docs/reporting.md): Inhalt, Quarto und Reproduktion.
- [Synthetische Kommunikation](docs/communications.md): Vorschau, Freigabe, Sink und Absturzverhalten.
- [Protokolländerungen](docs/protocol-amendments.md), [Panelimport](docs/panel-import.md)
  und [Teilnahme](docs/participation.md): versionierte Managementabläufe.
- [Authentifizierung](docs/authentication.md) und [Einladungen](docs/invitations.md):
  tatsächliche Nachweise und verbleibende Hosting-/UI-Gates.
- [Spezifikation](docs/spec/00_START_HERE.md): Methodik, Rollen, Sicherheit und Betrieb.
- [CTTIR-Konventionen](docs/adr/017-suite-conventions.md): Dokumentation und Oberflächengestaltung.
- [Implementierungsstatus](docs/IMPLEMENTATION_STATUS.md): aktuelle Nachweise und offene Arbeit.

Entwicklung und Beispiele verwenden ausschließlich synthetische Daten. `admin/`
bleibt eine lokale, ignorierte Ablage. Zugangsdaten, echte Studiendaten und lokale
Bibliotheken gehören nicht ins Repository.

## Lizenz

MIT © Raban Heller. Siehe [LICENSE](LICENSE).
