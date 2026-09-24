# Teststrategie und wissenschaftliche Validierung

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Testprinzip

Tests sichern wissenschaftliche und technische Invarianten. Sie dürfen nicht lediglich die eigene Implementierung mit derselben Formel wiederholen. Handberechnete Referenzen, unabhängige Rechenwege, echte PostgreSQL-Transaktionen und adversariale Zugriffsfälle sind erforderlich.

## Ebenen

| Ebene | Gegenstand | Werkzeug/Umgebung |
|---|---|---|
| Domain | Skalen, Regeln, Klassifikation, Zustände | testthat, deterministische Fixtures |
| Property/Metamorphic | Invarianten unter Permutation und Transformation | generierte kleine Datensätze mit festen Seeds |
| Persistence | Constraints, Migrationen, Rollbacks | echte PostgreSQL-Instanz |
| Service | Rechte, Idempotenz, Workflow | Integrationstests mit Rollenfixtures |
| Shiny-Modul | Reaktivität, UIzustände, Callbacks | shiny::testServer |
| Browser | Bewertung, Reload, Abgabe, Feedback | shinytest2 mit getrennten Sitzungen |
| Security | Isolation, Header, Exporte, Payloads | genehmigte lokale Testumgebung |
| Operational | Neustart, Workercrash, Restore | isoliertes Staging |
| Performance | Save/Submit bei definierter Parallelität | Lastskript und Messbericht |
| Reproduction | Offline-Ergebnisse aus Export | saubere R-Umgebung mit Lockfile |

## Wissenschaftliche Pflichtfälle

Alle Referenzfälle aus [Analytik](13_ANALYTICS_AND_REFERENCE_CASES.md). Ergänzend: gerade/ungerade n; ein gültiger Wert; ausschließlich Sonderantworten; Skala mit anderem Bereich; explizit umgekehrte Richtung; ungültiger Wert; mehrere Dimensionen; leeres Stratum; überlappende Konsensregeln; geänderte Itembedeutung; unbekannte Gruppe; Teilabgabenpolicy; Randomisierungsreihenfolge ohne Auswirkung auf Klassifikation.

Metamorphische Tests: Reihenfolge der Zeilen ändert Ergebnisse nicht. Bijektives Umbenennen von Pseudonymen ändert aggregierte Ergebnisse nicht. Hinzufügen von „unable“ verändert unter valid-only-Regel nicht die Zustimmungsquote, aber Missingness. Verdopplung jeder gültigen Beobachtung erhält Quoten, kann jedoch Mindest-n-Status ändern. Deshalb keinen falschen Invariantentest für die gesamte Klassifikation schreiben.

## Datenbanktests

Migration von leerem Schema bis aktuell; Migration eines vorherigen Releases mit Daten; Prüfsummenabweichung einer bereits angewandten Migration; Fremdschlüssel über Studiengrenzen; doppelte Enrollment-/Antwort-/Commandkeys; Rollback nach künstlichem Fehler zwischen Revision und Currentupdate; kein verwaister Submissioneintrag; kein stiller Cascadeverlust.

## Konkurrenztests

Mit zwei oder mehr echten Verbindungen und kontrollierten Barrieren: zwei Saves derselben Revision; parallele Saves verschiedener Personen; Save gegen Submit; Save gegen Close; zwei Closebefehle; abgebrochene Transaktion; wiederholter Submit nach verlorener HTTP-Antwort; mehrere Worker um denselben Job; abgelaufene Lease. Assert auf endgültige Daten, Revisionszahlen, Audit und erlaubte Clientantworten.

## Sitzungsisolation

Zwei Browserkontexte mit unterschiedlichen Panelkonten. Jede Person erhält eigene Vorantworten. Wechsel der Studie setzt abhängige UIzustände zurück. Ein globales Objekt darf keine andere Person beeinflussen. Manipulierte Requests mit fremden IDs werden serverseitig abgewiesen, auch wenn die UI keine solche Aktion anbietet.

## Authentifizierungstests

End-to-End durch realen Testgateway: Login, Logout, Einladungsannahme, Subjectbindung, gefälschte Header, direkter Shinyport, Sitzungserneuerung, maximale Sessiondauer, Rollenrevokation im offenen WebSocket und gesperrtes Konto. Ein gemockter Actor-Test ersetzt den Gatewaytest nicht.

## Ausfalltests

DB-Verbindung während Save unterbrechen: kein „Gespeichert“ ohne Commit. App nach Commit vor Clientbestätigung beenden: Retry findet dieselbe wirksame Operation. Worker während Rendern beenden: Teilfile wird nicht als fertiger Export registriert. Worker nach Providerannahme beenden: unklaren Zustellungsstatus entsprechend Adaptervertrag behandeln.

## Browser- und Zugänglichkeitstests

Tastaturpfad durch Bewertung und Abgabe; Skalenlabels; Fehlerfokus; Zoom; schmaler Viewport; Diagrammtabelle; Save-Livestatus; DE/EN-Wechsel; Fristdarstellung über Sommerzeitgrenze. Visuelle Snapshots sparsam für wichtige Layouts; funktionale Assertions für Daten und Zustände bevorzugen.

## Lasttest

Definierte Hardware, R-/Packageversion, Datenbankgröße und Netzbedingungen dokumentieren. Geplante Basis: 50 gleichzeitige aktive Sitzungen, 150 Items, zwei Dimensionen, kurze reale Denkpausen. Kein rein synthetischer Requestspam als Ersatz für Sessionlast.

Messwerte: p50/p95/p99 Save und Submit, Fehlerraten, DBlocks, Poolauslastung, RAM, CPU, Queuealter. Pflicht: keine verlorenen bestätigten Writes. Ziel p95 Save <2 s ist erst nach Messung bestätigt. Bei Überschreitung Engpass analysieren und Kapazität/Architektur oder Ziel begründet anpassen.

## CI und Release

Schnell: Packagechecks, reine Tests, Lint selektiv. Integration: PostgreSQL, Migrations- und Servicetests. Browser: gezielte Kernpfade. Vor Produktionsrelease: Securitymatrix, Restore, Lasttest und Reproduktion. Keine echte Mailzustellung in CI; Provideradapter mit kontrolliertem Sandbox-/Sinkvertrag.

## Nachweisformat

Test-ID, Anforderungs-ID, Fixtureversion, Umgebung, Start/Ende, Ergebnis, Artefaktpfad und Einschränkungen. „Nicht ausgeführt“ ist ein eigener Status. Übersprungene kritische Tests blockieren die entsprechende Freigabe. Ein grüner Packagecheck allein bedeutet keine freigegebene Studienplattform.
