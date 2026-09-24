# Begriffe und kanonische Statuswerte

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Fachliche Begriffe

| Begriff | Bedeutung in delphyR |
|---|---|
| Studie | eigenständiger wissenschaftlicher Prozess und zentrale Berechtigungsgrenze |
| Protokoll | versionierter Plan einschließlich Regeln und Verantwortlichkeiten |
| Panel | teilnehmende Personen mit begründeter Expertise/Perspektive |
| Stakeholdergruppe | im Design definierte analytische Gruppe |
| Runde | abgegrenzte Erhebungsphase mit freigegebenem Instrument |
| Enrollment | Zuweisung einer Person zu einer bestimmten Runde |
| Item | stabile fachliche Frage-/Aussageidentität |
| Itemversion | konkreter Wortlaut und Bedeutung zu einem Zeitpunkt |
| Dimension | gesonderter Bewertungsaspekt wie Relevanz oder Verständlichkeit |
| Skala | zulässige Antwortwerte, Reihenfolge, Anker und Sonderoptionen |
| Entwurf | gespeicherte, noch nicht endgültig abgegebene Bewertung |
| Submission | explizit abgegebener unveränderlich referenzierter Antwortsatz |
| Snapshot | fixierte Datenbasis einer Auswertung |
| Konsens | Erfüllung einer vorher definierten Zustimmungs-/Ablehnungsregel |
| Dissens | fortbestehende Uneinigkeit; legitimes Ergebnis |
| Stabilität | geringe Veränderung über Runden gemäß separater Definition |
| Attrition | Ausscheiden/Nichtfortsetzen von Teilnehmenden |
| Feedbackrelease | exakt freigegebene Rückmeldung aus einem definierten Stand |
| Disposition | menschliche Entscheidung über weiteres Vorgehen mit einem Item |
| Amendment | dokumentierte Änderung des Studienprotokolls |
| Pseudonym | studienspezifische Kennung mit geschützter Identitätszuordnung |
| Anonymisierung | Entfernung des Personenbezugs nach tatsächlicher Kontextprüfung; nicht automatisch durch Pseudonyme erreicht |

## Technische Begriffe

| Begriff | Bedeutung |
|---|---|
| Actor | verifizierter Mensch oder begrenzter Systemakteur |
| Capability | konkrete erlaubte Aktion |
| Principal | stabil identifiziertes Konto beim Identitätsanbieter |
| OIDC | Protokoll für externe Identitätsanmeldung |
| Idempotenz | Wiederholung derselben logischen Anfrage erzeugt keinen weiteren Effekt |
| Optimistic locking | Update verlangt die erwartete alte Revision |
| Transaktion | atomare Gruppe von Datenbankoperationen |
| Outbox | dauerhaft gespeicherte freigegebene externe Nachrichtenaufträge |
| Lease | zeitlich begrenzte Beanspruchung eines Jobs durch Worker |
| Provenienz | Herkunft von Daten, Regeln und Software eines Ergebnisses |
| RPO | tolerierbarer Datenverlustzeitraum im Wiederherstellungsplan |
| RTO | angestrebte Wiederherstellungsdauer |

## Kanonische Analysezustände

`consensus_in`: Einschlussregel erfüllt. `consensus_out`: Ausschlussregel erfüllt. `no_consensus`: ausreichende Daten, aber keine definierte Konsensregel erfüllt. `insufficient_data`: Datenvoraussetzung nicht erfüllt. `not_comparable`: Längsschnittvergleich fachlich nicht zulässig. Letzteres ist ein Vergleichsstatus, kein konkurrierender Konsensstatus.

## Antwortstatus

`answered`, `not_answered`, `unable_to_judge`, `abstained`, `not_applicable`. `not_presented` ist ein Präsentations-/Zuweisungsstatus. `withdrawn` ist ein Teilnahmestatus. `submitted` ist ein Abgabestatus. Diese Kategorien dürfen nicht in einem einzigen unklaren Feld vermischt werden.

## Anzeige versus Speicherung

Deutschsprachige UIlabels können „Konsens für Aufnahme“ oder „Nicht ausreichend beurteilbar“ lauten. Datenbank und Export verwenden stabile technische Codes. Übersetzung verändert niemals die Semantik eines Status. Farben ergänzen diese Codes, ersetzen sie nicht.
