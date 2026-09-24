# Risiken und konkrete Fehlerbilder

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Risikoregister

| ID | Fehlerbild | Auswirkung | Vorbeugung/Nachweis |
|---|---|---|---|
| R-01 | Zustimmungsquote mit wechselndem Nenner | falscher Konsens | explizite Regeln, Missingtabellen, Referenzfälle |
| R-02 | Klassifikation nach gerundetem Prozent | Grenzfälle falsch | ungerundete Prüfung, Fall G |
| R-03 | neues Item als alte Version behandelt | ungültiger Stabilitätsvergleich | Lineage und Vergleichbarkeitsflag |
| R-04 | live berechnetes Feedback verändert sich | unterschiedliche Informationsgrundlage | unveränderliche Feedbackreleases |
| R-05 | kleine Gruppen sind rekonstruierbar | Identitätsrisiko | Unterdrückung einschließlich Differenzangriffen |
| R-06 | fremde IDs im Request | Daten anderer Personen sichtbar | Studien-/Objektprüfung in Services |
| R-07 | globaler Shinyzustand | Antworten vermischt | Sessionisolation und Zweibrowsertest |
| R-08 | Save bestätigt vor Commit | vermeintlich gespeicherte Daten fehlen | Commitgebundene Bestätigung |
| R-09 | alter Tab überschreibt neue Antwort | Datenverlust | erwartete Revision und Konfliktanzeige |
| R-10 | Close und Save unkoordiniert | unklarer Datenstichtag | gemeinsame Lockstrategie |
| R-11 | Mailretry nach unklarem Providerergebnis | doppelte Erinnerung | Outbox, Providerkey, unknown-Zustand |
| R-12 | Reminder trotz Abgabe/Rückzug | Vertrauensverlust | erneute Eligibilityprüfung direkt vor Versand |
| R-13 | Gatewayheader gefälscht | Kontoübernahme | Headerstrip, Netzwerkgrenze, E2Etest |
| R-14 | Revokation wirkt nicht in alter Session | weiterer Zugriff | aktuelle Rechte und begrenzte Identitätslebensdauer |
| R-15 | Artefakt in öffentlichem www-Verzeichnis | ungeschützter Export | privater Speicher, Downloadautorisierung |
| R-16 | Freitext enthält HTML/Script | XSS | textbasierte Ausgabe und Sanitizing |
| R-17 | Export öffnet Formel in Excel | schädliche Interpretation | Spreadsheet-sicheres Exportprofil |
| R-18 | Restore stellt widerrufene Rechte wieder her | unzulässiger Zugriff | Revokations-/Löschereignisse nachführen |
| R-19 | Datenbankupgrade ohne Migrationstest | Studienausfall | getestete Migrationskette und Backup |
| R-20 | KI-Zusammenfassung entfernt Dissens | verzerrtes Feedback | P1 ohne KI, spätere menschliche Freigabe |
| R-21 | Protokolländerung wird verborgen | wissenschaftliche Intransparenz | unveränderte Primärregel und Amendment |
| R-22 | Konsens mit Wahrheit verwechselt | überzogene Interpretation | getrennte Berichterstattung und Begrenzungen |
| R-23 | Dropout erzeugt scheinbare Annäherung | fehlgeleitete Schlussfolgerung | gepaarte und unpaarige Auswertung |
| R-24 | zu viele DB-Verbindungen | Ausfälle unter Last | Poolbudget über Prozesse und Worker |
| R-25 | lokale Appdatei als Datenhaltung | Verlust bei Deployment | zentrale DB und private persistente Volumes |

## Incidentklassen

**Integrität:** bestätigte Antwort fehlt, falsche Klassifikation, verändertes Feedback. Betroffene Runde gegebenenfalls pausieren; Snapshot/Logs sichern; Ausmaß bestimmen; korrigierten Stand separat erzeugen; wissenschaftliche Auswirkungen dokumentieren.

**Vertraulichkeit:** fremde Antwort oder Export sichtbar. Zugriff begrenzen, betroffene Tokens/Accounts nach Bedarf sperren, verantwortliche Stelle informieren und deren Prozess befolgen. Nicht eigenständig externe Meldungen versenden oder behaupten, keine Daten seien abgeflossen, solange das ungeklärt ist.

**Verfügbarkeit:** DB/Auth/Worker nicht erreichbar. Ehrliche UIzustände; Wartungs-/Retryverfahren; keine unkontrollierte Ersatzspeicherung in CSV-Dateien.

## Ungewöhnliche, aber geplante Fälle

Eine Person wird in Runde 2 einer anderen Stakeholdergruppe zugeordnet: Gruppenzugehörigkeit der jeweiligen Runde bleibt im Snapshot erhalten; Analysen kennzeichnen den Wechsel. Ein Item wird in Runde 3 gestrichen: frühere Antworten bleiben nachvollziehbar, aber keine neue Missingzeile als „vergessen“ erzeugen. Eine Sprachfassung wird korrigiert: neue Version und Bewertung der Vergleichbarkeit.

## Priorität

Sicherheits- und Integritätsrisiken mit potentiell fremden Daten oder falscher wissenschaftlicher Entscheidung blockieren produktiven Release. Ein kosmetischer Fehler in einem optionalen Diagramm kann mit dokumentiertem Workaround vertretbar sein. Risikoakzeptanz benötigt benannte verantwortliche Person und darf nicht allein vom Coding-Agenten als Produktfreigabe erteilt werden.

## Restrisiken

Auch ein korrektes System verhindert kein ungeeignet ausgewähltes Panel, keine unklare Forschungsfrage und keine fachlich verzerrte Redaktion. Es macht diese Entscheidungen sichtbar und unterstützt deren Prüfung. Technische Superuser und bereits heruntergeladene Daten bleiben außerhalb vollständiger Appkontrolle.
