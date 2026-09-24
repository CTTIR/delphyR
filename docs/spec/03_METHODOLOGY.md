# Methodischer Vertrag für Delphi-Studien

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Wissenschaftliches Modell

delphyR unterstützt strukturiertes Expertenurteil mit wiederholter individueller Bewertung und kontrolliertem Feedback. Ein klassischer explorativer Einstieg kann Freitext sammeln; ein modifiziertes Delphi kann mit literaturbasiert vorbereiteten Items beginnen. Diese Herkunft muss im Protokoll und je Item nachvollziehbar sein.

Die Plattform muss Panelzusammensetzung, Auswahlkriterien, Zweck der Expertise und Stakeholderperspektiven dokumentieren. Es gibt keine automatisch passende Panelgröße. Die Planungsgröße für einen Lasttest ist keine Stichprobenempfehlung.

## Vorab festzulegende Regeln

MUSS: Skalenanker, Bewertungsdimensionen, zustimmende/ablehnende Kategorien, Nenner, Mindestfallzahl, Gruppenaggregation, Behandlung fehlender Antworten, zulässige Antwortänderungen, Wiederzulassung nach ausgelassener Runde, Behandlung neuer Items, Feedbackinhalt, Rundenzahl und Stopkriterien.

Schwellen müssen begründet und versioniert werden. Änderungen nach Sichtung der Daten sind als Amendment zu kennzeichnen. Die primäre Analyse behält die ursprünglich freigegebene Regel; zusätzliche Regeln können als Sensitivitätsanalyse ausgewiesen werden. Eine neue Regel darf einen alten Status nicht still überschreiben.

## Beispiel eines Regelprofils, keine Empfehlung

Neunstufige Relevanzskala. Zustimmung = 7–9; Ablehnung = 1–3. `consensus_in`, wenn mindestens 70 % der gültigen Bewertungen zustimmen **und** weniger als 15 % ablehnen. `consensus_out`, wenn mindestens 70 % ablehnen **und** weniger als 15 % zustimmen. Mindestens zehn gültige Antworten pro für die Entscheidung erforderlichem Stratum. Fehlende und „nicht beurteilbare“ Antworten bleiben außerhalb des gültigen Nenners, werden aber separat berichtet.

Gleichheit an der Grenze ist relevant: 70 % erfüllt `>= 0.70`; 15 % erfüllt **nicht** `< 0.15`. Berechnungen erfolgen vor jeder Rundung. Überlappende Regeln werden bei Konfigurationsprüfung abgelehnt oder müssen eine explizite, nachvollziehbare Konfliktregel besitzen. Standard: keine überlappenden Regeln zulassen.

## Drei getrennte Ergebnisachsen

1. **Deskriptive Evidenz:** Verteilung, gültiges n, fehlende Angaben, Median, Quartile, Gruppen.
2. **Regelstatus:** consensus_in, consensus_out, no_consensus oder insufficient_data.
3. **Studienentscheidung:** beibehalten, entfernen, revidieren, teilen, zusammenführen, erneut vorlegen oder finalisieren.

Eine menschliche Studienentscheidung kann von der Klassifikation abweichen. Sie benötigt Begründung, autorisierte Person und Verweis auf die verwendete Analyse. Die analytische Klassifikation bleibt erhalten.

## Stabilität und Attrition

Konsens ist innerhalb eines Zeitpunkts definiert. Stabilität beschreibt Veränderungen zwischen Zeitpunkten. Panelweite Verteilungsänderungen und gepaarte individuelle Änderungen werden separat berechnet. Gepaarte Auswertungen verlangen dieselbe pseudonyme Person, eine vergleichbare Itemfassung, dieselbe Skala und gültige Antworten in beiden Runden.

Ein nicht signifikanter Test gilt nicht als Nachweis von Stabilität. Fehlende gepaarte Beobachtungen werden nicht mit null Änderung gleichgesetzt. Panelabgänge und ihre vorherigen Bewertungen können beschreibend untersucht werden; daraus folgt kein automatischer Beweis oder Ausschluss von Attritionsbias.

Stopregeln kombinieren maximale Rundenzahl, definierte Stabilität, erreichten Konsens, anhaltenden Dissens und gegebenenfalls organisatorischen Abbruch. Ein Abbruch aus Zeitgründen muss als solcher sichtbar bleiben.

## Gruppen

Stakeholdergruppen können gleichberechtigt getrennte Entscheidungsschwellen haben. Die Anwendung darf Gruppen nicht still nach Größe gewichten oder deren Ergebnisse durch eine Gesamtquote ersetzen. Für „Konsens in allen Gruppen“ müssen alle erforderlichen Gruppen ausreichende Daten und den definierten Status erreichen. Eine leere Gruppe ist kein Konsens.

Kleine Gruppenstatistiken können intern berechnet, aber im Feedback aus Gründen des Identitätsschutzes unterdrückt werden. Die Unterdrückung darf den internen Entscheidungsstatus nicht verändern; sie verändert nur die Darstellung. Gesamt- und Untergruppenwerte dürfen nicht zusammen Rückschlüsse auf unterdrückte Einzelpersonen ermöglichen.

## Feedback und qualitative Inhalte

Alle für einen Vergleich vorgesehenen Panelmitglieder erhalten dieselbe freigegebene statistische Grundlage; persönliche vorherige Antworten ergänzen diese individuell. Unterschiedliche Feedbackstrategien pro Gruppe sind möglich, müssen aber im Design festgelegt und gespeichert sein.

Kommentare bleiben Originaldaten. Redaktionelle Zusammenfassungen sind neue Objekte mit Herkunft, Bearbeitung und Freigabe. Identifizierende Angaben werden vor Veröffentlichung entfernt. Inhaltlicher Dissens darf nicht nur deshalb entfallen, weil er eine Minderheit betrifft.

## Reporting-Bezug

Die Erfassungsstruktur berücksichtigt Transparenzthemen aus ACCORD und Delphi-spezifischer CREDES-Literatur. Beide ersetzen keine fachliche Entscheidung. Eine automatisch befüllte Reporting-Checkliste dokumentiert vorhandene Informationen; sie bescheinigt keine methodische Qualität. Quellen und Geltungsbereiche siehe [Quellenregister](30_SOURCES_AND_COMPARATORS.md).
