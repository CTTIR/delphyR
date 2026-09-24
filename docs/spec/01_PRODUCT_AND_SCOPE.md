# Produktvision und verbindlicher Umfang

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Problem

Eine Delphi-Studie benötigt miteinander verknüpfte Informationen über Protokoll, Panel, Items, Antwortversionen, Feedback und Entscheidungen. Werden diese in separaten Fragebögen, Tabellen und E-Mails gepflegt, ist später schwer nachvollziehbar, warum ein Item in einer bestimmten Fassung erneut vorgelegt wurde und welche Informationen den Bewertungen zugrunde lagen.

## Produktversprechen

Eine Studiengruppe kann eine rundenbasierte Delphi-Studie ohne R-Kenntnisse durchführen. Ein Methodiker kann dieselben eingefrorenen Daten unabhängig von Shiny im R-Package auswerten. Ein Reviewer kann den Weg von einer Ausgangsfrage bis zur finalen Entscheidung anhand exportierter Versionen und Begründungen nachvollziehen.

Das Ergebnis einer Studie darf auch Dissens oder unzureichende Datenlage sein. Die Anwendung optimiert nicht auf möglichst viele grüne Konsensanzeigen. Zustimmung darf nicht als empirische Wahrheit oder Nachweis von Wirksamkeit dargestellt werden.

## Primäre Nutzer

| Nutzer | Aufgabe | Erfolgskriterium |
|---|---|---|
| Studienleitung | Studie planen, starten, abschließen | Vollständige Freigaben und nachvollziehbarer Verlauf |
| Koordination | Rekrutierung, Einladungen, Rückfragen | Teilnahme verwalten ohne routinemäßigen Zugriff auf Einzelbewertungen |
| Methodik | Regeln, Auswertung, Feedback | Unabhängig reproduzierbare Zahlen und deklarierte Nenner |
| Panelmitglied | Einschätzen, begründen, erneut beurteilen | Einfacher Zugang, sichere Speicherung und transparentes Feedback |
| Redaktion | Qualitative Inhalte und Itemrevision | Herkunft und Bearbeitungsschritte erhalten |
| Auditor | Verlauf prüfen | Lesbare unveränderte Nachweise innerhalb seiner Rechte |
| Betrieb | Verfügbarkeit und Wiederherstellung | Fehler erkennen, Wiederherstellung nachweisen |

## Erster produktiver Release: P1

MUSS enthalten: mehrere voneinander isolierte Studien; vordefinierte Rollen; versioniertes Protokoll; einsprachige oder DE/EN-Instrumente; CSV-Itemimport; ordinale Einzelauswahl, Ja/Nein und Freitext; ausdrückliche Missing-Kategorien; Einwilligung; Stakeholdergruppen; externe Teilnehmende; Entwurfsspeicherung und endgültige Abgabe; manuell gesteuerte Runden; Bewertung nach mehreren Dimensionen; quantitative Analyse; qualitative Zuordnung; persönliches Vorfeedback; definierte Gruppenstatistik; moderierte Kommentare; Itemhistorie; kontrollierte Einladungs-/Reminderkampagnen; Forschungsdatenexport; Berichte; Audit-Ereignisse; vollständige Tests der kritischen Wege; Betriebs- und Restore-Anleitung.

P1 kann eine erste explorative Freitextrunde enthalten. Die Umwandlung in bewertbare Items erfolgt redaktionell, mit dokumentierter Herkunft und Freigabe. Die App behauptet nicht, eine vollständige qualitative Analyse automatisch erledigt zu haben.

## Vorstufe: P0, ausschließlich Entwicklung/Demo

Ein synthetisches Panel, feste Items und eine zweirundige Demonstration reichen für den ersten vertikalen Pfad. P0 darf lokale Testidentitäten und vereinfachte Vorschau verwenden. Ein deutliches Demo-Banner, deaktivierter echter Mailversand und synthetische Daten sind zwingend. P0 ist kein freigegebener Studienbetrieb.

## Spätere Erweiterungen: P2

- Ranking und Ranggleichheiten mit eigener Methodikspezifikation.
- Numerische Prognosen und probabilistische Elicitation.
- Real-Time-Delphi mit ereignisbasierten Feedbackständen.
- Konsensuskonferenzen als separat dokumentierte Prozessphase.
- Zusätzliche Sprachen, komplexe Verzweigungen und externe APIs.
- Optionale KI-Unterstützung für redaktionelle Vorschläge; keine automatische Veröffentlichung oder Entscheidung.
- Mandantenübergreifende Plattformadministration mit eigenem Sicherheitsmodell.

## Explizite Nichtziele

Kein Ersatz für Literaturrecherche oder fachliche Begründung. Kein generischer Survey-Builder mit beliebigen ausführbaren Formeln. Kein Nachweis regulatorischer Konformität durch Installation. Kein Austausch menschlicher Experten durch LLMs im Standardprozess. Keine öffentliche Einsicht in Rohdaten, nur weil ein Package Open Source ist.

## Erfolgsmessung

Produktiv relevant sind: erfolgreich abgeschlossene Bewertungen ohne Datenverlust; Wiederaufnahme nach Verbindungsabbruch; reproduzierbare Ergebnisstände; dokumentierte Entscheidungen; fehlerfreie Trennung von Identität und Analyse; verständliche Fehlermeldungen; auswertbare Teilnahmezahlen. Antwortquote und Konsensquote sind Studienergebnisse und keine Software-Qualitätsnachweise.

Zielgröße für den ersten Lasttest: eine Studie mit 300 eingeladenen Personen, 150 Items, zwei Dimensionen und 50 gleichzeitig aktiven Sitzungen. Dies sind **zu prüfende Planungsgrößen**, keine bereits belegte Kapazität und keine methodische Panelgrößenempfehlung.
