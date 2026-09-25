# Synthetischer Panelimport und ungebundene Einladungsentwürfe

Der Panelimport übernimmt ausschließlich synthetische Kontaktdaten in das separate
`identity`-Schema. Er erzeugt **ungebundene Einladungsentwürfe**. Er verschickt keine
Nachrichten, erstellt keine Zugangstokens und bindet keine Principals anhand einer
E-Mailadresse. Studienmitgliedschaft, Panelpseudonym, Einwilligung und
Fragebogenzuweisung entstehen durch diesen Import nicht.

## CSV-Vertrag

Schema `1.0` verwendet UTF-8 und exakt diese Spalten:

```csv
external_ref,email,display_name,locale,stakeholder_group
001,Person.One+Demo@EXAMPLE.INVALID,Synthetische Person Eins,de,professionals
002,person02@example.invalid,Synthetische Person Zwei,en,public_contributors
```

Das Trennzeichen wird ausdrücklich als Komma oder Semikolon gewählt. Sämtliche
Felder werden als Zeichenketten gelesen: führende Nullen und der Text `NA` bleiben
erhalten. Es gibt keine localeabhängige Typinterpretation. Ein UTF-8-BOM am Dateianfang
wird beim Parsen toleriert; der Dateihash bezieht sich weiterhin auf die Originalbytes.
Maximalgröße ist 1 MiB, maximal 10.000 Datenzeilen. Name und externe Referenz haben
zusätzliche Längen- und Kontrollzeichenprüfungen. Locale und Stakeholdergruppe
müssen zum aktuellen Studienprotokoll passen.

In Entwicklung sind nur synthetische Domains mit `.invalid` erlaubt. Der
Domainteil wird kleingeschrieben; Groß-/Kleinschreibung, Punkte und Pluszusätze des
lokalen Teils bleiben erhalten. Es werden keine anbieterspezifischen Aliasregeln
angewendet. Der Parser unterstützt einfache ASCII-Adressen; internationalisierte
Domains und quotierte lokale Teile werden nicht stillschweigend umgewandelt.

## Autorisierte Vorschau

```r
# csv_bytes stammt aus der vertrauenswürdigen Uploadverarbeitung, nicht aus einem
# vom Browser frei gewählten Dateipfad. Ausschließlich synthetische Inhalte.
preview <- delphyr::preview_panel_import(
  repo, coordinator, study_id, csv_bytes,
  schema_version = "1.0", delimiter = ","
)
preview$rows
preview$issues
preview$valid
```

Der Dienst verlangt die aktuelle Studienberechtigung `coordinate`, bevor
Kontaktwerte verarbeitet oder angezeigt werden. Die API akzeptiert CSV-Bytes oder
einen Textwert und liest selbst keine beliebigen Dateipfade. Die Vorschau verbleibt
im aufrufenden autorisierten Kontext; sie wird nicht automatisch dauerhaft abgelegt.

Fehler enthalten Datenzeilennummer, Spalte und technischen Code, keine kopierten
Kontaktwerte. Zeile `0` bedeutet einen datei- oder schemaweiten Fehler. Die
Zeilennummer zählt logische Datenzeilen nach der Kopfzeile; ein CSV-Feld kann
mehrere physische Textzeilen umfassen.

Doppelte externe Referenzen und gleiche normalisierte Adressen werden sowohl in
der Datei als auch gegenüber bereits importierten Kontakten derselben Studie
angezeigt. Unterschiede nur in der Groß-/Kleinschreibung des lokalen Adressteils
werden vorsorglich als Reviewfall gemeldet, nicht automatisch zusammengeführt.
Alle solchen Fälle blockieren die Übernahme der **gesamten** Datei. Die Koordination
muss die Eingabe prüfen, korrigieren und erneut vorlegen; eine automatische
Deduplizierung, Aktualisierung bestehender Kontakte oder stillschweigende Übertragung
von Mitgliedschaften ist nicht vorgesehen.

## Exakt geprüfte Übernahme

```r
receipt <- delphyr::import_panel(
  repo, coordinator, study_id, preview,
  expected_hash = preview$hash,
  reason = "Synthetische Zeilen und Zielgruppe geprüft",
  command_id = "panel-import-001"
)
delphyr::get_panel_import_receipt(repo, coordinator, receipt$id)
```

Der Approval-Hash bindet Datei, Schema, Trennzeichen, Zeilen und Validierungsbericht.
Vor der Übernahme werden die Originalbytes erneut geparst und Rechte, Studienzustand,
Protokollreferenzen sowie Dubletten erneut geprüft. Eine Studiensperre serialisiert
konkurrierende Übernahmen. Es gibt keine Teilimporte: Kontaktzeilen, ungebundene
Entwürfe, Receipt, Commandquittung und Auditereignis werden gemeinsam committed
oder gemeinsam zurückgerollt.

Ein identischer Retry mit demselben Command-Key liefert dieselbe Receipt, auch wenn
die inzwischen importierten Zeilen nun in der Datenbank existieren. Geänderter
Inhalt oder eine andere Begründung unter demselben Key wird abgewiesen. Rechte
werden auch beim Retry erneut geprüft. Ein neuer Importvorgang derselben Kontakte
wird als Dublette zur Überprüfung zurückgewiesen.

Die unveränderliche Receipt enthält Datei-/Vorschauhash, Schema, angenommene und
abgewiesene Anzahl, Actor, Zeitpunkt, Freigabebegründung und Validierungsbericht.
Die Rückgabe enthält zusätzlich die erzeugten opaken Einladungsentwurf-IDs.
Standard-Audit und Commandpayload enthalten keine Kontaktwerte. Die minimale
Receipt-Leseansicht enthält ebenfalls keine Namen oder E-Mailadressen.

## Identitätsbindung und Governance bleiben getrennt

Ein Entwurf hat den Zustand `unbound` und keine Principalreferenz. Die spätere
Einladungsannahme benötigt einen eigenen geprüften Vertrag: verifizierter Issuer
und Subject, kurzlebiger nur gehasht gespeicherter Token, bewusste authentifizierte
Annahme sowie Schutz vor Wiederverwendung und Mail-Scannern. Dieser Import
implementiert diese Kontobindung ausdrücklich noch nicht.

Kontaktwerte liegen nicht im Forschungsantwortschema und werden durch das
numerische Exportprofil nicht aufgenommen. Aufbewahrung, Kontaktkorrektur und
rechtlich freigegebene Löschung benötigen gesonderte institutionelle Regeln; diese
werden nicht aus einer Beispiel-CSV abgeleitet. Die unveränderlichen P0-Importtabellen
sind kein vollständiger produktiver Retention- oder Löschworkflow.

## Nachweise

`test-panel-import.R` nutzt nur die mit `DELPHYR_TEST_DB=true` ausdrücklich aktivierte
lokale synthetische Datenbank. Geprüft werden konservative Normalisierung, exakte
Hashes, Schema-/Zeilenfehler, Dubletten, Studiengrenzen, Rollenentzug, Retry und
Rollback nach einem Fehler mitten im Schreibvorgang. Kein Test nimmt eine
Kontobindung vor oder sendet eine Nachricht.
