# Annahmen, Entscheidungen und offene Punkte

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Festgelegte Basis

| ID | Entscheidung | Begründung |
|---|---|---|
| ADR-001 | Marke delphyR, Kernpackage delphyr, UI-Package delphyrApp | Konsistente technische Namen und sichtbarer R-Bezug |
| ADR-002 | Rundenbasiertes Delphi in P1 | Kontrollierbares Feedback und klare Freeze-Grenzen |
| ADR-003 | Modularer Monolith mit separatem Worker | Weniger Betriebsaufwand als Microservices bei klaren Verantwortlichkeiten |
| ADR-004 | PostgreSQL als verbindliches Produktionsbackend | Transaktionen, Integritätsregeln, konkurrierende Zugriffe |
| ADR-005 | Shiny Server Open Source hinter HTTPS-Proxy | Gewünschte selbst betriebene Zielplattform |
| ADR-006 | Institutioneller OIDC-Provider für Mitarbeitende und externe Panelkonten | Identitätsverwaltung außerhalb des R-Prozesses |
| ADR-007 | Kein produktives Passwortsystem als Eigenentwicklung in P1 | Bestehende Identitätsinfrastruktur nutzen |
| ADR-008 | Service-Layer prüft jeden geschützten Befehl | UI allein ist keine Berechtigungsgrenze |
| ADR-009 | Unveränderliche Runden-, Analyse- und Feedbackstände | Historische Reproduzierbarkeit |
| ADR-010 | Analytik als reine Funktionen | Vergleichbare Ergebnisse in R, App und Worker |
| ADR-011 | Explizite Regeln statt beliebiger R-Ausdrücke in Konfiguration | Validierbarkeit und sichere Ausführung |
| ADR-012 | E-Mail über dauerhafte Outbox und Worker | Kein Versand abhängig von Browser-Laufzeit |
| ADR-013 | CSV zuerst, XLSX später optional | Klarer, prüfbarer Importvertrag |
| ADR-014 | DE/EN-Oberfläche und versionierte Instrumentübersetzungen | Sprache nicht mit Itemidentität vermischen |
| ADR-015 | Vollständige Historie ohne komplette Event-Sourcing-Architektur | Nachvollziehbarkeit bei beherrschbarer Komplexität |

OIDC setzt einen Provider voraus, der externe Teilnehmende aufnehmen kann. Falls lokal nicht vorhanden, ist die Providerwahl ein Deployment-Entscheidungspunkt. Der Agent darf für eine Demonstration Testidentitäten nutzen, jedoch keine provisorische Anmeldung als produktionsreif deklarieren. Eine separate passwortlose Gateway-Lösung wäre eine dokumentierte alternative Architektur, nicht eine unbemerkte Ergänzung zur Shiny-App.

## Arbeitsannahmen

Eine Installation gehört zunächst einer verantwortlichen Organisation. Mehrere Studien sind möglich; eine Studie ist die zentrale Berechtigungsgrenze. Panelmitglieder können an mehreren Studien teilnehmen, erhalten aber pro Studie eine eigene Analyse-ID. Wissenschaftliche Rollen sind studienspezifisch. Organisationsexterne Forschende können nicht automatisch auf andere Studien zugreifen.

Skalen dürfen pro Dimension definiert werden, bleiben innerhalb einer freigegebenen Runde unverändert. Auch Dimensionsdefinitionen, Skalenanker, Sprachfassungen und Anzeigeanordnung gehören in den unveränderlichen Rundensatz; nachträgliche Stammdatenänderungen dürfen ihn nicht umdeuten. Spätere Wortlautänderungen erhalten neue Itemversionen. Kritische Bedeutungsänderungen unterbrechen standardmäßig die direkte statistische Vergleichbarkeit.

Der produktive Mailversand wird erst nach Einrichtung eines genehmigten Absenderkontos und einer ausdrücklich freigegebenen Kampagne aktiviert. Entwicklung benutzt einen lokalen Mail-Sink. Die Umsetzung der Versandfunktion ist von der Erlaubnis zum tatsächlichen Versand zu unterscheiden.

## Vor erster echter Rekrutierung zu entscheiden

| Thema | Verantwortlich | Umgang bis zur Entscheidung |
|---|---|---|
| Organisation, Studienzweck, Rechtsraum | Studienleitung | Platzhalter; keine produktive Erhebung |
| Rechtsgrundlage, Einwilligung, Aufbewahrung | Verantwortliche Stelle | Technisch konfigurierbar; keine erfundenen Fristen |
| Ethik-/Institutionserfordernisse | Studienleitung | Freigabefeld bleibt offen |
| OIDC-Provider und externe Accounts | Betrieb | Testprovider nur in Development |
| SMTP-/Mailprovider, Absenderdomain | Betrieb/Koordination | Mail-Sink |
| Konsens- und Stopregeln | Methodik | Synthetisches Beispiel als Demo markiert |
| Gruppenauswertung und Mindestzellgröße | Methodik/Datengovernance | Keine personenbezogenen Gruppendetails ausgeben |
| Erwartete Last, RPO/RTO | Betrieb/Studienleitung | Lasttest- und Restore-Planungswerte verwenden |
| Softwarelizenz, Autoren und Zitation | Eigentümer/Maintainer | Keine öffentliche Lizenzbehauptung |

Diese Punkte blockieren nicht die Entwicklung mit synthetischen Daten. Sie blockieren die jeweils abhängige produktive Handlung.

## Änderungsverfahren

Jede Architekturänderung erhält ID, Datum, Status, Kontext, Optionen, Entscheidung, Konsequenzen, betroffene Dateien und Migration. Entscheidungen dürfen ersetzt, aber nicht kommentarlos gelöscht werden. Protokolländerungen einer Studie sind eigene Datenobjekte, keine Git-Commits der Software.

Beispiel einer ADR-Struktur: `Context`, `Decision`, `Alternatives`, `Consequences`, `Security impact`, `Data migration`, `Validation`, `Supersedes`. Ein geschlossener ADR-Status bedeutet eine getroffene Entwurfsentscheidung, keinen bestandenen Test.

## Namens- und Lizenzprüfung

Vor Veröffentlichung CRAN-/Repositorykollisionen, Domain und Marke prüfen. Dieses Paket garantiert keine Verfügbarkeit. Fremdcode nicht aus konkurrierenden Plattformen übernehmen. Methodische Inspiration, zitierte Dokumentation und tatsächlich lizenzierter Code sind getrennt zu behandeln.
