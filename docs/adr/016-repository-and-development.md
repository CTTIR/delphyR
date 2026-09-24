# ADR-016: Repository, Lizenz und Entwicklung

Status: accepted. Datum: 2026-09-24.

Der Nutzer hat das öffentliche Repository CTTIR/delpyR und MIT ausdrücklich gewählt.
Der Repositoryname bleibt delpyR, die technischen Packages folgen der Spezifikation:
delphyr und delphyrApp. Copyrightinhaber entsprechend bestehender CTTIR-Packages:
Raban Heller. Die private Originalablage admin/ bleibt ignoriert; eine unveränderte
Spezifikationskopie unter docs/spec/ macht den Arbeitsvertrag nachvollziehbar.

Die Umsetzung erfolgt sequentiell in überprüfbaren Schritten. Lokales PostgreSQL
läuft isoliert mit synthetischen Daten. Produktionsfreigabe bleibt gesondert.
Für den ersten Build werden vorhandene R-Abhängigkeiten benutzt und tatsächliche
Versionen protokolliert. Keine Behauptung eines bestandenen Releasegates ohne Test.

Reihenfolge: reine Domain/Analytik; PostgreSQL und Autorisierung;
zweirundiger Servicepfad; Shiny; Management, Jobs, Exporte und Betriebsnachweise.
