# Anforderungskatalog mit Abnahmekriterien

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Verwendung

IDs bleiben über die Implementierung stabil. Jeder PR und jede Abnahme referenziert passende IDs. „P1“ bezeichnet Anforderungen vor Einsatz mit echten Studiendaten. „P2“ ist Erweiterung. Kritische Anforderungen brauchen ausführbare Nachweise, nicht nur Screenshots.

| ID | Priorität | Anforderung | Abnahmenachweis |
|---|---|---|---|
| STU-01 | P1 | Versioniertes Protokoll mit Methodik und Zuständigkeiten | Neue Version ersetzt keine alte; Freeze referenziert exakte Version |
| STU-02 | P1 | Studie vor Eröffnung validieren | Fehlende Pflichtregeln verhindern Öffnung mit konkreter Fehlerliste |
| STU-03 | P1 | Studienisolierung | Zugriff von Studie A auf Daten von B scheitert auch mit bekannten IDs |
| PAN-01 | P1 | Panel importieren und Dubletten prüfen | Vorschau, Fehlerzeilen, keine unbemerkten doppelten Mitgliedschaften |
| PAN-02 | P1 | Einwilligung versioniert erfassen | Ohne gültige Zustimmung keine Antwortabgabe |
| PAN-03 | P1 | Widerruf/Teilnahmerückzug abbilden | Neue Einladungen stoppen; Datenbehandlung folgt beschlossener Policy |
| PAN-04 | P1 | Stakeholderzuordnung zeitlich festhalten | Bereits eingefrorene Analysen ändern sich bei späterer Profiländerung nicht |
| ITM-01 | P1 | Itemherkunft und Versionen | Literatur-/Freitextquelle bis zur finalen Fassung nachvollziehbar |
| ITM-02 | P1 | Mehrere Dimensionen | Relevanz und Verständlichkeit besitzen getrennte Antworten und Regeln |
| ITM-03 | P1 | Skalen und Sonderantworten | Null, NA, Enthaltung und nicht vorgelegt nicht verwechselt |
| ITM-04 | P1 | Revision/Split/Merge | Herkunftskanten und Vergleichbarkeitsentscheidung exportierbar |
| RND-01 | P1 | Definierte Zustandsmaschine | Verbotene Übergänge werden serverseitig zurückgewiesen |
| RND-02 | P1 | Eingefrorener Rundensatz | Text, Reihenfolge, Skalen und Regeln nach Öffnung unveränderlich |
| RND-03 | P1 | Abschluss atomar gegen Schreibzugriffe | Gleichzeitiges Save/Close verliert keine bestätigte Antwort |
| RSP-01 | P1 | Entwurfsspeicherung | Reload stellt zuletzt bestätigten Datenstand wieder her |
| RSP-02 | P1 | Endgültige Abgabe | Genau eine wirksame Abgabe je Person/Runde; Wiederholung idempotent |
| RSP-03 | P1 | Konflikterkennung | Zweiter Tab kann neuere Antwort nicht kommentarlos überschreiben |
| RSP-04 | P1 | Abbruch/Wiederaufnahme | Offline-Eingabe wird nicht fälschlich als gespeichert angezeigt |
| ANA-01 | P1 | Deterministische Auswertung | App- und R-Auswertung desselben Snapshots stimmen überein |
| ANA-02 | P1 | Konsens ohne gerundete Schwellenprüfung | Grenzfalltests bestehen |
| ANA-03 | P1 | Nenner explizit berichten | Jede Quote enthält Zähler, Nenner und Missing-Regel |
| ANA-04 | P1 | Stabilität und Attrition getrennt | Gepaarte Fallzahl und Versionsausschlüsse sichtbar |
| ANA-05 | P1 | Gruppenregeln | Zu kleine erforderliche Gruppe führt zu insufficient_data |
| FDB-01 | P1 | Feedback freigeben und einfrieren | Alte Ansicht bleibt nach neuer Analyse unverändert |
| FDB-02 | P1 | Persönliche Vorantwort | Andere Personen erhalten keinen Zugriff auf diese Antwort |
| FDB-03 | P1 | Kleine Zellen unterdrücken | Differenzangriffe in vorgesehenen Ansichten geprüft |
| QUA-01 | P1 | Qualitative Redaktion | Original, Redaktion, Zusammenfassung und Entscheidung getrennt |
| QUA-02 | P1 | Freitext zu Items zuordnen | Mehrfachzuordnungen möglich, Herkunft bleibt erhalten |
| COM-01 | P1 | Einladungen/Reminder kontrollieren | Vorschau, freigegebene Empfängermenge und Versandstatus |
| COM-02 | P1 | Dauerhafte Jobs | Neustart führt nicht zum Verlust ausstehender Arbeit |
| EXP-01 | P1 | Pseudonymisierter Forschungsdatenexport | Keine Kontaktfelder, Tokens oder fremden Studien |
| EXP-02 | P1 | Reproduzierbarer Bericht | Daten-, Regel-, Softwareversion und Grenzen ausgewiesen |
| SEC-01 | P1 | Authentifizierung und Autorisierung | Manipulierte Header/IDs und abgelaufene Sitzungen abgewiesen |
| SEC-02 | P1 | Keine sensiblen Logs | Token-/Antwort-/E-Mail-Canaries fehlen in Standardlogs |
| SEC-03 | P1 | Rollenrevokation | Neue geschützte Aktionen prüfen aktuelle Rechte |
| AUD-01 | P1 | Änderungsnachweise | Akteur, Zeit, Objekt, Aktion und Begründung verfügbar |
| OPS-01 | P1 | Restore geprüft | Wiederhergestellte Studie besteht Integritäts- und Funktionsprüfung |
| OPS-02 | P1 | Migrationen nachvollziehbar | Leere und vorhandene Datenbank erfolgreich migriert |
| UX-01 | P1 | Tastaturbedienung und Labels | Bewertung und Abgabe ohne Maus durchführbar |
| UX-02 | P1 | DE/EN und Zeitzone | Keine übersetzten technischen IDs; Frist eindeutig angezeigt |
| RTD-01 | P2 | Echtzeit-Feedback | Eigene Spezifikation und Bias-/Zeitbehandlung erforderlich |
| RNK-01 | P2 | Rankings | Ranggleichheiten, fehlende Ränge und Auswertung definiert |

## Nichtfunktionale Ziele

Datensicherheit hat Vorrang vor falschen Erfolgsmeldungen. Bei Datenbankausfall bleiben Änderungen unbestätigt. Ein Neustart darf bereits bestätigte Schreibvorgänge nicht verlieren. Ein exportierter Snapshot muss unabhängig vom aktuellen Studienstatus lesbar sein, sofern dessen genehmigte Aufbewahrung dies vorsieht.

Als erste Leistungsziele gelten im definierten Lasttestszenario: p95 eines einzelnen bestätigten Saves unter zwei Sekunden und keine verlorenen bestätigten Änderungen. Netzwerk-, Browser- und Datenbankanteile separat messen. Diese Ziele sind zu validieren und dürfen bei Nichterreichen nur begründet geändert werden.

Jeder produktive Fehler benötigt einen verständlichen Hinweis und eine nicht sensitive Korrelations-ID. Technische Stacktraces sind nicht Teil der Teilnehmendenoberfläche.
