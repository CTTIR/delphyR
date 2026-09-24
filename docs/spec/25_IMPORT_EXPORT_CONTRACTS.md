# Import- und Exportverträge

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Allgemeiner Dateivertrag

UTF-8, eindeutige Header, explizite Schemaversion, definierte Trennzeichen und Datentypen. CSV mit Komma und standardkonformer Quotierung als kanonisches Format; Import kann nach expliziter Auswahl Semikolon unterstützen. Keine stillschweigende Datums-/Dezimalinterpretation nach Betriebssystemlocale.

IDs als Strings lesen; führende Nullen erhalten. Fehlende Werte werden je Feld definiert, nicht pauschal jedes `NA` im Text ersetzen. Dateigröße, Zeilenzahl, Feldlänge und zulässige Typen vor Übernahme prüfen.

## Itemimport v1

| Feld | Pflicht | Bedeutung |
|---|---|---|
| item_code | ja | stabiler studieninterner Code |
| locale | ja | Sprachcode |
| text | ja | Wortlaut, nicht leere Zeichenfolge |
| definition | nein | Erläuterung |
| domain_code | nein | fachliche Domäne |
| dimension_code | ja | Bewertungsdimension |
| scale_code | ja | existierende Skala |
| source_ref | nein | Literatur-/Quellenkennung |
| required | ja | true/false |
| display_order | ja | positive Ganzzahl |

```csv
item_code,locale,text,definition,domain_code,dimension_code,scale_code,source_ref,required,display_order
I001,de,"Synthetisches Beispielitem A","Nur Demonstration",D01,relevance,relevance_9,DEMO-SRC-01,true,1
I002,de,"Synthetisches Beispielitem B","Nur Demonstration",D01,relevance,relevance_9,DEMO-SRC-01,true,2
```

Mehrere Sprachzeilen desselben Item-/Dimensionsschlüssels müssen dieselbe nichtsprachliche Konfiguration haben. Doppelte identische Zeilen melden; widersprüchliche Dubletten blockieren. Freitextfragen benötigen einen expliziten Fragetyp/Skalenvertrag in der endgültigen Schemaausgestaltung.

## Panelimport v1

`external_ref`, `email`, `display_name`, `locale`, `stakeholder_group`. Nur Koordination mit entsprechender Berechtigung. Import erzeugt Einladungsentwürfe, keine E-Mails. Die endgültige Principalbindung erfolgt nach verifizierter Anmeldung. E-Mailnormalisierung konservativ: Domain normalisieren, lokale Teile nicht durch anbieterabhängige Regeln wie Punktentfernung gleichsetzen.

Dubletten als Reviewfälle anzeigen. Bestehende Mitgliedschaft nicht still auf eine andere Person übertragen. Testimporte nur synthetische Adressen wie `person01@example.invalid` verwenden; `.invalid` ist nicht für echte Zustellung vorgesehen.

## Importworkflow

Upload → sichere temporäre Speicherung → Parser → Schema-/Referenzprüfung → zeilenbezogene Fehler → Vorschau der geplanten Änderungen → explizite Übernahme → Transaktion → Importreceipt. Wiederholung desselben freigegebenen Importvorgangs ist idempotent. Teilimport standardmäßig nicht zulassen, wenn er eine unbemerkte unvollständige Studie erzeugen könnte.

Importreceipt: Dateihash, Schema, Anzahl akzeptierter/abgelehnter Zeilen, Actor, Zeit, erzeugte Objektversionen und Validierungsbericht. Originaldatei nach genehmigter Aufbewahrung behandeln, insbesondere Panelimporte mit Kontakten.

## Forschungsantwortexport v1

| Feld | Typ | Bedeutung |
|---|---|---|
| study_code | string | Studienkennung |
| round_number | integer | Rundennummer |
| panelist_id | string | studienspezifisches Pseudonym |
| group_code | string/null | zulässige Gruppierung |
| item_code | string | stabile Identität |
| item_version | integer | bewertete Fassung |
| dimension_code | string | Bewertungsdimension |
| scale_code | string | Skala |
| answer_status | enum | answered/unable/etc. |
| value_integer | integer/null | ordinale Antwort |
| value_text | string/null | nur in erlaubtem Profil |
| response_revision | integer | ausgewählte Revision |
| submission_id | string/null | Abgabereferenz |
| snapshot_id | string | fixierter Datenstand |

Datensatz ist lang und tidy; keine dynamischen Spalten pro Person. Analyse-/Missingtabellen ergänzen den Rohdatenexport. `not_presented` kann in einer gesonderten Zuweisungstabelle dargestellt werden; nicht als erfundene Rohantwort anlegen.

## CSV-Formeln und Reproduktion

Zwei klar gekennzeichnete Modi: maschinenlesbar für R mit originalgetreuen Textwerten in sicherem Container/JSON und warnungsfreier Parsernutzung; spreadsheet-sicher für manuelles Öffnen mit neutralisierten Formelinhalten. Transformierte Texte als solche dokumentieren. Kein stilles Verändern wissenschaftlicher Originaltexte im maßgeblichen Datensatz. Im ZIP kann JSON für originalgetreue Texte und sichere CSV für Ansicht kombiniert werden.

## JSON und Schemas

Schemafelder mit Typ, Pflichtstatus, Enum und Version beschreiben. Keine R-Objektserialisierung als einziges öffentliches Austauschformat. RDS kann zusätzlich für interne Nutzer existieren, ersetzt aber nicht dokumentierte CSV-/JSON-Verträge.

## Versionsmigration

Ein Import gibt seine Schemaversion an oder der Nutzer wählt sie ausdrücklich. Alte Versionen durch getestete Transformatoren migrieren. Unbekannte neue Versionen ablehnen statt erraten. Exportmanifest benennt jede enthaltene Tabellen-/Dokumentschemaversion.

## Fehlerbericht

Dateiname ohne sensible Pfade, Zeile, Spalte, Fehlercode und Korrekturhinweis. Kontaktwerte im Fehlerbericht nur innerhalb autorisierter Ansicht und nicht in Standardlogs. Fehlertexte wie „Unbekannte Skala relevance_10 in Zeile 12“ sind hilfreicher als generische Parsertracebacks.
