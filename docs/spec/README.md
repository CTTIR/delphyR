# delphyR — Spezifikationspaket v1.0

Vollständiger Implementierungsentwurf für eine Delphi-Studienplattform mit R-Package, Shiny-App und selbst betriebenem Shiny Server.

**Start:** [Lesereihenfolge und Übersicht](00_START_HERE.md)

**Coding-Agent starten:** [Vollständiger Orchestrator-Prompt](27_ORCHESTRATOR_PROMPT.md)

**Studie vorbereiten:** [Ausfüllbares Protokoll und Konfigurationsbeispiel](24_STUDY_PROTOCOL_TEMPLATE.md)

**Entwicklung steuern:** [Roadmap](22_IMPLEMENTATION_ROADMAP.md), [Arbeitspakete](28_WORK_PACKETS.md), [Abnahme](26_ACCEPTANCE_AND_RELEASE.md)

**Qualität und Herkunft:** [Prüfbericht](VALIDATION_REPORT.md), [Quellenregister](30_SOURCES_AND_COMPARATORS.md)

## Inhalt

33 nummerierte Fach- und Arbeitsdokumente; diese README; ein Prüfbericht; ein JSON-Manifest und SHA-256-Prüfsummen. Alle Dokumente sind in UTF-8 gespeichert und ohne besondere Anwendung lesbar. Mermaid-Diagramme werden von geeigneten Markdown-Viewern gerendert; ihr Quelltext bleibt auch in einfachen Editoren lesbar.

Die Dokumente sind überwiegend deutsch, Code- und Schnittstellenbezeichner englisch. Beispiele sind synthetisch. Methodische Beispielschwellen sind keine universellen Empfehlungen.

## Status

Dies ist eine detaillierte **Spezifikation**, keine fertig implementierte oder produktiv getestete Software. Enthaltene APIs, Konfigurationen und Strukturen sind geplante Verträge. Eine Implementierung muss die beschriebenen Tests und institutionellen Freigaben durchlaufen.

Stand: 24.09.2026. Marke: delphyR; Kernpackage: delphyr; UI-Package: delphyrApp. Namens-/Markenverfügbarkeit und endgültige Softwarelizenz sind offen.

## Nutzung

Archiv entpacken, Ordner nach `docs/spec/` des Zielrepositorys kopieren und den Orchestrator-Prompt mit dem tatsächlichen Repositorypfad an den Coding-Agenten übergeben. Für einen ersten eigenen Überblick mit `00_START_HERE.md` beginnen.

Produktivkonfiguration, reale Nachrichten und Deployment werden nicht durch das Übergeben dieser Spezifikation automatisch autorisiert. Entwicklung und Tests können mit synthetischen Daten, Testauthentifizierung und Mail-Sink beginnen.

## Prüfsummen

`MANIFEST.json` führt die Markdown-Dateien mit Größe und SHA-256 auf. `CHECKSUMS.sha256` umfasst diese Dateien und das Manifest. Aus dem entpackten Ordner kann auf Linux `sha256sum -c CHECKSUMS.sha256` verwendet werden.
