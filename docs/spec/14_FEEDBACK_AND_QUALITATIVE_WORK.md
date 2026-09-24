# Kontrolliertes Feedback und qualitative Arbeit

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Feedback als Forschungsartefakt

Ein Feedbackrelease ist ein unveränderliches Artefakt mit Analysequelle, Itemversionen, Darstellungspolicy, Sprachfassungen, redaktionellen Inhalten, Templateversion, Freigabe und Prüfsumme. Es ist kein Dashboard, das beim Öffnen automatisch den aktuellen Datenbankstand neu zusammenfasst.

Der ursprüngliche Feedbackstand wird einer Folgerunde und ihren Enrollments zugewiesen. Persönliche Vorantworten stammen aus dem referenzierten vorherigen Snapshot beziehungsweise einer explizit definierten eigenen Submissionquelle, nicht aus einer inzwischen veränderten Current-Tabelle.

## Bestandteile pro Item

- Wortlaut der vorherigen und aktuellen Fassung, falls geändert.
- Kurze Begründung einer Revision, wenn relevant.
- Eigene vorherige Bewertung oder verständliches „keine Vorbewertung“.
- Verteilung gültiger Bewertungen mit n und Skalenankern.
- Konfigurierte Lage-/Streuungsmaße.
- Gesamt- oder Gruppenstatistik nach vorher festgelegtem Design.
- Moderierte Kommentare oder thematisch gegliederte Zusammenfassung.
- Kennzeichnung, wenn Vergleichbarkeit eingeschränkt ist.
- Neue Bewertungsmöglichkeit ohne voreingestellte Zustimmung.

Eine alte Antwort kann sichtbar sein, darf aber nicht unbemerkt als neue Antwort gespeichert werden. „Vorherige Bewertung übernehmen“ wäre eine ausdrückliche Nutzeraktion und im Instrumentdesign festzulegen.

## Redaktionsworkflow

1. Originalbeitrag unverändert erfassen.
2. Hinweise auf Identität, Dritte und unangemessene Inhalte prüfen.
3. Redigierte Fassung anlegen, Original nicht überschreiben.
4. Themen codieren und Quellen mehreren Themen zuordnen, falls nötig.
5. Zusammenfassung entwerfen; zustimmende und abweichende Positionen sachlich abbilden.
6. Zweite Prüfung gemäß Studienpolicy durchführen.
7. Exakte Fassung freigeben und im Feedbackrelease referenzieren.

Jede Auslassung oder wesentliche Umformulierung benötigt einen Grund. Eine redaktionelle Zusammenfassung darf nicht als wörtliches Zitat erscheinen. Die Anzeige „n Kommentare“ muss auf definierter Zähleinheit beruhen: Beiträge, Personen oder Codierungen sind verschiedene Größen.

## Explorative Runde und Itemableitung

Ein Freitextbeitrag kann mehrere Vorschläge enthalten. Redaktion kann ihn in Segmente gliedern, mehreren Themen zuordnen und daraus ein oder mehrere Items ableiten. Jeder abgeleitete Itemdatensatz enthält Herkunftslinks und Entscheidung über Zusammenführung. Mehrere Beiträge können zu einem Item führen; ein Beitrag kann mehrere Items begründen.

Die App unterstützt das Management der qualitativen Arbeit. Sie ersetzt keine Auswahl eines geeigneten qualitativen Analyseverfahrens. Codierleitfaden, beteiligte Personen, Umgang mit Uneinigkeit und abschließende Entscheidung werden dokumentiert.

## Itementscheidungen

Dispositionen: `retain`, `revise`, `remove`, `split`, `merge`, `rerate`, `finalize`. Jede Disposition referenziert die Analyse und gegebenenfalls qualitative Quellen. `remove` löscht keinen historischen Datensatz. `split`/`merge` erzeugt neue Itemidentitäten mit Herkunftskanten. `revise` erzeugt neue Version und eine explizite Vergleichbarkeitsentscheidung.

Die Software kann regelbasierte Vorschläge anzeigen. Tatsächliche Aufnahme in die Folgerunde braucht menschliche Freigabe. Ein Item ohne Konsens wird nicht automatisch endlos wiederholt; Stop- und Abschlussregeln greifen.

## Kleine Zellen

Mindestzellgröße ist konfigurierbar und im Protokoll begründet. Unterdrückung umfasst Tabellen, Diagramme, Tooltips, HTML-Datenattribute und Downloads. Gesamtwerte können zusammen mit sichtbaren Untergruppen eine unterdrückte Gruppe rekonstruierbar machen; gegebenenfalls komplementäre Unterdrückung oder nur Gesamtfeedback verwenden.

Fein granulierte institutionelle Angaben und sehr charakteristische Freitexte können Personen auch ohne Namen erkennen lassen. Das Feedbackdesign muss diesen Kontext berücksichtigen. Pseudonymisierung allein löst dieses Problem nicht.

## Änderungen nach Veröffentlichung

Ein sachlicher Fehler wird nicht durch Ersetzen einer Datei unter identischem Namen repariert. Neue Version erzeugen, Grund und betroffene Runden dokumentieren, Auswirkungen auf bereits erfolgte Bewertungen fachlich beurteilen. Ob neue Bewertungen oder eine Protokollabweichung nötig sind, entscheidet die Studienleitung mit Methodik.

## Optionales KI-Modul, P2

Nur ausdrückliche Aktivierung mit genehmigtem Datenfluss. Keine personenbezogenen Originaltexte an externe Dienste ohne passende Freigabe. Modell, Promptversion, Eingaben, Outputs und menschliche Änderungen dokumentieren. Keine automatische Löschung von Minderheitsmeinungen, Klassifikation von Konsens oder Veröffentlichung. P1 benötigt keine KI-Abhängigkeit.
