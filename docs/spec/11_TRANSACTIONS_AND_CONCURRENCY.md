# Transaktionen, Idempotenz und konkurrierende Zugriffe

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Ziel

Gleichzeitige Aktionen dürfen keine bestätigten Daten verlieren, fremde Antworten überschreiben oder geschlossene Datenstände verändern. Die Reihenfolge fachlicher Operationen wird durch Datenbanktransaktionen definiert, nicht durch die Reihenfolge von Browserereignissen.

## Save-Vertrag

Input: verifizierter Actor, Enrollment-ID, Round-Item-ID, erwartete Revision, validierter Antwortpayload und eindeutiger `command_id` beziehungsweise Idempotency-Key. Output: dauerhaft bestätigte neue Revision, Serverzeit und Status. Bestätigung erst nach Commit.

1. Berechtigung und Studienzuordnung ermitteln.
2. Connection aus Pool ausleihen; Transaktion starten.
3. Rundendatensatz mit einem gemeinsamen Row-Lock sperren, der parallele Saves erlaubt, aber Round-Close blockiert; konkrete PostgreSQL-Lockmodi testen, z. B. `FOR SHARE` für Saves und `FOR UPDATE` für Close.
4. Aktuellen Rundenzustand und Frist unter Lock prüfen.
5. Enrollment exklusiv sperren. So werden Save und Submit derselben Person serialisiert.
6. Einwilligung und Enrollmentstatus prüfen.
7. Idempotency-Key prüfen; gleiche Anfrage liefert dasselbe Ergebnis, anderer Payload mit gleichem Key führt zu Konflikt.
8. Aktuelle Antwort mit erwarteter Revision vergleichen; bei Konflikt nicht überschreiben.
9. Antwortrevision ergänzen und Current-Zeile aktualisieren; Audit und Commandresultat schreiben.
10. Commit; Connection zurückgeben; UI bestätigen.

Lockreihenfolge überall: Runde → Enrollment → Antwort/Submission → nachgeordnete Zeilen. Niemals in einem anderen Service umkehren. Ein eindeutiger Constraint fängt konkurrierende Erstinserts ab. Kurzlebige Transaktionen; kein Mailversand, Rendering oder Benutzerwarten innerhalb eines Locks.

## Submit-Vertrag

Submit sperrt Runde gemeinsam und Enrollment exklusiv, liest alle maßgeblichen aktuellen Antwortrevisionen, validiert Pflichtangaben und erzeugt Submission plus Entries in derselben Transaktion. Ein gleichzeitiger Save muss entweder vorher vollständig wirksam sein oder danach wegen des abgegebenen Enrollments scheitern.

Doppelklick oder Netzwerkretry mit identischem Key erzeugt keine zweite Abgabe. Ein anderer Key nach erfolgreicher Abgabe liefert einen bereits-abgegeben-Status mit der vorhandenen Receipt-ID, ohne neue Inhalte einzuschleusen.

## Round-Close-Vertrag

Close erlangt exklusiven Lock auf dieselbe Runde. Bereits laufende zulässige Saves/Submitoperationen können abschließen; spätere Operationen sehen `closed` und werden abgewiesen. Das Closeevent speichert Datenbankzeit und Akteur. Die Fristpolicy kann dafür sorgen, dass ein lange wartender Save nach Fristende zurückgewiesen wird.

Nach Commit des Close kann ein Worker einen Snapshot erstellen, weil normale Writes gesperrt sind. Der Snapshotjob nutzt eine konsistente Transaktion und dokumentierte Einschlusspolicy. Standard primäre Analyse: gültige endgültige Abgaben. Teilweise Entwürfe werden separat ausgewiesen; ihre Nutzung verlangt eine vorab definierte Policy.

## Versionskonflikte in zwei Tabs

Tab A und B kennen Revision 4. A speichert Revision 5. B mit erwarteter Revision 4 erhält `DEL_CONFLICT`, den aktuellen Serverstand und eine sichere Konfliktansicht. Keine automatische Last-write-wins-Strategie. Textentwürfe können zur manuellen Wiederübernahme im aktuellen Browser gehalten werden; dauerhaftes lokales Speichern sensibler Freitexte ist nicht Standard.

## Idempotenz

Eindeutigkeit mindestens innerhalb Studie, Actor, Commandtyp und Key. Payloadhash bindet den Key an den Inhalt. Erfolgsresultate werden referenziert. Fehlgeschlagene fachliche Validierung darf nach Korrektur mit neuem Key wiederholt werden. Aufbewahrung von Commandkeys muss länger als das unterstützte Retryfenster sein.

Analysen und Exporte deduplizieren nach Snapshot, Regelversion, Templateversion und relevanten Optionen. Ein absichtlicher neuer Lauf kann neue Run-ID erhalten, aber dieselbe wissenschaftliche Ergebnisprüfsumme besitzen.

## Isolation und Retries

Default `READ COMMITTED` mit expliziten Locks kann genügen; Verhalten durch Integrationstests belegen. Starke Snapshotanforderungen können `REPEATABLE READ` benötigen. `SERIALIZABLE` ist keine automatische Lösung ohne Retrystrategie.

Deadlocks und Serialization-Failures werden begrenzt mit Jitter wiederholt, nur für idempotente Operationen. Validierungs-, Berechtigungs- und Versionsfehler werden nicht blind retried. Alle Rollbacks dürfen keine Teilantwort, Abgabe oder Freigabe zurücklassen.

## RLS und Connection-Pooling

Optionales RLS muss mit der tatsächlichen Approlle getestet werden; Eigentümer- und Superuserverhalten beachten. Kontext nur transaktionslokal setzen und bei Return sicher bereinigen. Ein frei durch den Client gesetztes `study_id`-Sessionattribut wäre keine Schutzgrenze. Serviceautorisierung bleibt notwendig.

## Nachweise

Deterministische Barrieretests mit zwei realen PostgreSQL-Verbindungen für Save/Save, Save/Submit, Save/Close, Close/Close und Jobübernahme. Nicht bloß schnelle Schleifen mit unvorhersehbarem Timing. Fachliche Invarianten nach beiden möglichen gültigen Reihenfolgen prüfen.
