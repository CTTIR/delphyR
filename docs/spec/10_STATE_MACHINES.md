# Zustandsmaschinen und erlaubte Übergänge

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Studie

`draft → configured → recruiting → active → completed → archived`

Zusätzlich `suspended` und `cancelled`. Suspension stoppt neue wissenschaftliche Schreibaktionen nach Policy, löscht aber keine Daten. Ein technischer Ausfall ist nicht automatisch eine wissenschaftliche Suspension. `completed` erfordert Abschlussentscheidung, finalen Datenstand und dokumentierte offene Items. `archived` regelt Zugriff und Betrieb, nicht automatisch Datenlöschung.

## Runde

| Von | Nach | Voraussetzungen | Wirkung |
|---|---|---|---|
| draft | review | Instrument und Regeln syntaktisch gültig | Reviewfassung erzeugen |
| review | approved | fachliche Freigabe, erforderliche Übersetzungen, Testvorschau | Inhaltshash fixieren |
| approved | open | aktives Protokoll, Zeitfenster, Enrollments, passende Einwilligung | Bewertung zulassen |
| open | closed | berechtigter Befehl oder freigegebener Scheduler; transaktionale Sperre | weitere Antworten zurückweisen |
| closed | frozen | Antwortsnapshot vollständig und geprüft | Datenbasis unveränderlich |
| frozen | analysed | erfolgreiche deterministische Analyse | Auswertung bereitstellen |
| analysed | feedback_ready | Inhalte geprüft, Redaktionen abgeschlossen | Feedbackfreigabe erlauben |
| feedback_ready | released | autorisierte Freigabe | Feedback für zugewiesene Folgerunde nutzbar |

Eine letzte Runde kann nach `analysed` in den Studienabschluss eingehen, ohne Teilnehmerfeedback als Pflichtvoraussetzung. Das Rundenschema muss diesen expliziten Abschlussweg erlauben, beispielsweise `analysed → finalized` bzw. `released → finalized`; beide führen zu einem unveränderlichen Abschlussstatus.

## Korrekturen

Vor Öffnung darf eine genehmigte Runde in `draft` zurückgesetzt werden; ihre alte Genehmigung wird ungültig und bleibt historisch erhalten. Nach Öffnung sind Itemtext und Regeln nicht frei editierbar.

Eine geschlossene Runde wird in P1 nicht einfach wieder geöffnet. Falls eine notwendige Ausnahme vorliegt: Amendment, neue Runden-/Erhebungsinstanz oder eine ausdrücklich implementierte Korrekturprozedur mit separatem Datenstand. Ein UI-Knopf „Unlock all“ ist ausgeschlossen. Die ursprüngliche Analyse bleibt als superseded markiert nachvollziehbar.

## Enrollment und Antworten

Enrollment: `invited → eligible → in_progress → submitted`. Alternativ `declined`, `withdrawn`, `ineligible`, `expired`. Teilnahme- und Antwortzustände nicht in einer einzigen Statusspalte mischen. Eine Person kann gültig eingewilligt haben und trotzdem die Runde nicht abschließen.

Antworten sind editierbare Entwürfe, solange Runde offen und Enrollment nicht abgegeben ist. P1 sperrt nach Abgabe weitere Bearbeitung. Das Protokoll darf eine Änderungspolitik vorsehen, aber deren Implementierung benötigt eine neue Submission-Version und gesonderte Tests; nicht still im MVP aktivieren.

Abgabe bedeutet: Pflichtfelder entsprechend Protokoll erfüllt; zulässige Sonderantworten akzeptiert; aktuelle Revisionen fixiert; Serverbestätigung ausgegeben. Eine fehlgeschlagene Abgabe verändert den Status nicht teilweise.

## Feedback

`draft → reviewed → approved → released → superseded`

Nach Release keine In-place-Änderung. Kritische redaktionelle Korrektur erzeugt neue Version, dokumentiert betroffene Zuweisungen und Benachrichtigungsentscheidung. Bereits erfolgte Auslieferungen bleiben dem alten Release zugeordnet.

## Jobs

`queued → running → succeeded` oder `retry_wait → queued`; bei erschöpften Versuchen `dead_letter`; vor Ausführung `cancelled`. Running-Jobs besitzen eine Lease. Nach Workerabsturz können abgelaufene Leases kontrolliert übernommen werden. Ein fachlicher Effekt braucht eine zusätzliche Idempotenzsicherung; eine Queue allein garantiert ihn nicht.

## Artefakte

`requested → building → ready → expired/deleted`; Fehlerstatus `failed`. `ready` erst, wenn Datei vollständig geschrieben, Prüfsumme berechnet und registriert ist. Download vor `ready` ist unmöglich. Eine Anzeige des Dateinamens allein ist keine Berechtigung.

## Fristen und Zeit

Die Datenbankzeit entscheidet über Zulässigkeit. Anzeigen verwenden Studienzeitzone mit eindeutigem Offset beziehungsweise lokalem Datum. Sommerzeitwechsel und doppelte lokale Uhrzeiten testen. Ein im Browser vor Fristablauf gestarteter, aber erst danach am Server zugelassener Save folgt der dokumentierten Fristpolicy. Standard: serverseitige Zulassung unter Rundensperre ist maßgeblich.

UI zeigt konkrete Gründe für verbotene Übergänge: fehlende Freigabe, fehlende Übersetzung, unvollständiges Feedback, geänderte Konfiguration oder unzureichende Rechte. Keine kryptischen Zustandsnummern für Studienanwender.
