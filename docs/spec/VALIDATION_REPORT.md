# Prüfbericht — delphyR-Spezifikationspaket

Stand: 24.09.2026. Geprüft wurde das Dokumentenpaket v1.0, **nicht eine implementierte delphyR-Anwendung**.

## Bestand

- 33 fortlaufend nummerierte Fach- und Arbeitsdokumente: 00 bis 32.
- README und dieser Prüfbericht, insgesamt 35 Markdown-Dateien.
- JSON-Manifest mit Größen und SHA-256-Prüfsummen.
- Zusätzliche SHA-256-Liste einschließlich Manifest.

## Automatisch geprüft

| Prüfung | Ergebnis |
|---|---|
| Nummerierte Dokumente vollständig und eindeutig | bestanden: 33/33 |
| UTF-8, Haupttitel und keine Unicode-Ersatzzeichen | bestanden |
| Markdown-Codeblöcke paarig geschlossen | bestanden |
| Relative Markdown-Dateilinks im Paket auflösbar | bestanden |
| Nummerierte Dateiverweise in Inlinecode vorhanden | bestanden |
| YAML-Beispiel syntaktisch parsebar | bestanden |
| Beispielskala, Konsenskategorien und Mindest-n konsistent | bestanden |
| Demo-Mailmodus sink und kein Livefeedback | bestanden |
| Referenzklassifikationen A–I unabhängig nachgerechnet | bestanden |
| Ungültige Skala in Referenz J zurückgewiesen | bestanden |
| Median, Q1, Q3 und IQR für Referenz A | bestanden |
| Beispiel gepaarter absoluter Änderungen | bestanden |
| Zwei Beispielgruppen unabhängig klassifiziert | bestanden |

Die Rechenbeispiele wurden mit einem kleinen separaten Pythonprüfer und ganzzahligen Schwellenvergleichen nachgerechnet. Das validiert die hier dokumentierten Beispiele, nicht eine künftige R-Implementierung und nicht die Eignung dieser Beispielregeln für eine reale Studie.

## Redaktionell geprüft

- Trennung von Spezifikation, Demonstration, technischer Softwarefreigabe und Studienfreigabe.
- Getrennte Kern- und UI-Packages ohne beabsichtigte zyklische Abhängigkeit.
- Regeln, Datensnapshots, Feedback und menschliche Entscheidungen als getrennte versionierte Objekte.
- Datenbankziel für `rules_version_id` als Tabelle `rule_versions` ausdrücklich ergänzt.
- Unveränderliche Dimensions-/Skalen-/Sprachdefinitionen im Rundensatz erläutert.
- Maximale Rundenzahl im YAML nur an einer maßgeblichen Stelle.
- Einladungsfreigabe, reale Kommunikation und Deployment nicht automatisch autorisiert.
- Reale Parallelagentenarbeit im Prompt nur bei gesonderter Autorisierung.
- Kein behaupteter Echtzeit-Delphi-, KI- oder Rankingumfang in P1.

## ZIP-Prüfung

Nach Erstellung prüft das Verpackungsskript CRC, Dateiliste, Rootordner und byteidentische Inhalte gegenüber dem Ausgangsordner. Das ZIP enthält nur die Dokumente, das Manifest und die Prüfsummen, keine Arbeits-/Generierungsskripte, Zugangsdaten oder echten Studiendaten.

## Nicht geprüft / Grenzen

- Kein R-Code, Shiny-Deployment oder PostgreSQL-Schema aus diesem Entwurf implementiert oder getestet.
- Keine produktive OIDC-/SMTP-Integration, kein Lasttest, kein Restore und kein Securityaudit.
- Keine systematische Literaturübersicht und kein Praxistest der Vergleichsplattformen.
- Keine Marken-, Domain- oder Package-Namensfreigabe.
- Keine automatische Verifikation aller externen Links auf dauerhafte Erreichbarkeit.
- Keine institutionelle, rechtliche oder ethische Freigabe.
- Die strukturellen Prüfungen garantieren keine vollständige semantische Fehlerfreiheit; die Umsetzung benötigt die beschriebenen Reviews und Tests.
