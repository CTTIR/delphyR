# Berichte und numerische Exportergänzungen

`prepare_report_data(repo, actor, snapshot_id)` erzeugt Berichtsdaten für einen
unveränderlichen numerischen Snapshot. Der Dienst prüft das aktuelle Exportrecht
in der zugehörigen Studie. Ein zusätzliches Analyserecht ist nicht erforderlich;
Teilnehmende und fremde Studienrollen erhalten darüber keinen Zugang.

## Inhalt und Grenzen

Die Berichtsdaten enthalten Protokoll, Konsensregeln, wissenschaftliche Provenienz,
Ergebnisse, Nenner, Missingness, Verteilungen und die mehrsprachigen eingefrorenen
Instrumenttexte. Das Datenwörterbuch erläutert zentrale Felder und Hashes.

Menschliche Itementscheidungen werden ausschließlich als Item, Disposition und
zugehöriger Analyse-Hash übernommen. Itembeziehungen enthalten Itemcodes, Versionen
und den Beziehungstyp. Nur Beziehungen zu einer exakt im Snapshot enthaltenen
Itemcode-/Versionskombination werden aufgenommen. Diese redaktionellen Angaben zeigen den Stand zum
Exportzeitpunkt; sie werden nicht als Bestandteil des früheren Antwortsnapshots
ausgegeben. Freitextbegründungen, qualitative Originale, individuelle Freitextantworten,
Kontaktdaten und Principal-/Actor-IDs werden nicht in diese Ergänzung übernommen.
Ein Snapshot mit einer Freitextskala wird für dieses Profil zurückgewiesen.

Autoren, Finanzierung, Interessenkonflikte, institutionelle Freigaben, fachliche
Interpretation, Protokollabweichungen und ACCORD-/CREDES-Prüfung erscheinen ausdrücklich
als **nicht dokumentiert**. Diese Kennzeichnung besagt, dass der Berichtsdienst
keinen freigegebenen strukturierten Eintrag dafür verwendet. Sie ist keine Aussage,
dass eine reale Studie diese Angaben grundsätzlich nicht besitzt.

## Private Artefakte schreiben

```r
data <- delphyr::prepare_report_data(repo, actor, snapshot_id)
# staging ist ein neu angelegtes privates Verzeichnis des Exportworkers.
files <- delphyr::write_report_data(data, staging)
```

Geschrieben werden `report-data.json`, `data_dictionary.csv`, `round_items.csv`,
`item_decisions.csv`, `item_lineage.csv`, `missingness.csv`, `denominators.csv`,
`distributions.csv` und `author_fields.csv`. Die CSV-Dateien verwenden dieselbe
Formelmaskierung wie der numerische Forschungsexport. Bereits vorhandene gleichnamige
Dateien werden nicht überschrieben.

Der Exportworker erzeugt diese Dateien und den fertig gerenderten Bericht **vor**
Berechnung des endgültigen Manifests. Alle tatsächlich ausgelieferten Dateien
werden mit Bytezahl und SHA-256 ins Manifest aufgenommen. Berichtsdaten
haben zusätzlich einen eigenen kanonischen Inhalts-Hash. Dieser umfasst den
Exportzeitpunkt und ist vom wissenschaftlichen Ergebnis-Hash zu unterscheiden.

## Vertrauenswürdiges Quarto-Template

```r
path <- delphyr::render_study_report(data, staging, timeout = 60L)
```

Das installierte Template `inst/reports/study.qmd` ist der einzige ausführbare
Berichtsquelltext. Die API nimmt keinen Templatepfad und keine frei übergebenen
Renderargumente entgegen. Sie kopiert das Pakettemplate und die JSON-Daten in ein
neues temporäres Verzeichnis. Studieninhalte werden ausschließlich als Daten geladen
und HTML-maskiert; sie werden weder in R-Chunks noch in YAML eingesetzt.

Der Renderaufruf verwendet `system2()` mit festen beziehungsweise shell-maskierten
Argumenten, einem Zeitlimit von höchstens 300 Sekunden und privaten temporären
Dateien. Der Bericht ist eine HTML-Datei mit eingebetteten Ressourcen. Temporäre
Daten und Renderlogs werden entfernt; Fehler liefern einen sicheren Code
`DEL_RENDER` ohne rohe Studiendaten im Fehlertext. Das ist ein begrenzter vertrauenswürdiger
Workerprozess, keine allgemeine Sandbox für fremde Templates.

Quarto, `knitr` und `rmarkdown` sind optionale Laufzeitvoraussetzungen. Fehlen sie,
meldet die Funktion `DEL_DEPENDENCY`. Ausschließlich dann verwendet der Exportworker
den einfachen, ausdrücklich gekennzeichneten HTML-Fallback. Das Manifest nennt
`quarto_html` oder `basic_html_missing_quarto_runtime` als Renderer und bindet den
Berichtsdaten-Hash. Ein echter Renderfehler oder ein fehlendes Pakettemplate führt
zum Fehlerzustand des Exportauftrags; es wird kein unvollständiges Artefakt registriert.
PDF und DOCX sind durch diesen Pfad nicht implementiert.

## Nachweise

`test-reporting.R` prüft Studiengrenzen, Rechteentzug, Exportrecht ohne Analyserecht,
Ausschluss redaktioneller Freitextbegründungen, Dateiallowlist und Inhalts-Hash.
Bei vorhandener Quarto-Runtime wird der reale HTML-Render ausgeführt. Eingeschleuste
HTML-Skripte, Inline-R und Include-Text bleiben dabei Daten; ein angegebener
Ausführungsmarker wird nicht erstellt. Der integrierte Workerpfad prüft zusätzlich
das endgültige Manifest, die spätere Prüfsummenprüfung beim Download, den
Dependency-Fallback und den Abbruch ohne Artefakt bei `DEL_RENDER`.

Der lokale Integrationslauf am 25.09.2026 bestand 45 Berichtstest-Assertions und
17 bestehende Jobtest-Assertions, einschließlich realem Quarto-Render. Diese Zahlen
beschreiben diesen Prüflauf; der zentrale Implementierungsstatus dokumentiert den
aktuellen Gesamtstand.

Die Tests benötigen `DELPHYR_TEST_DB=true` für die synthetische lokale Datenbank.
Die Standardprüfung ohne diesen Opt-in greift nicht auf PostgreSQL zu.
