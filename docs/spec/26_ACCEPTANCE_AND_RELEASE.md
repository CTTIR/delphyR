# Abnahme und Definition of Done

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Drei getrennte Aussagen

1. **Dokumentationspaket vollständig:** alle Spezifikationsdateien vorhanden, Links und Struktur geprüft.
2. **Software technisch bereit:** Code implementiert, relevante Tests bestanden, bekannte Grenzen dokumentiert.
3. **Studie produktiv freigegeben:** lokale Konfiguration, methodisches Protokoll und institutionelle Entscheidungen bestätigt.

Keine dieser Aussagen impliziert automatisch die nächste. Dieses ZIP erfüllt nur die erste Ebene nach dem beigefügten Prüfbericht.

## Feature-Definition-of-Done

- Anforderungs-ID und fachlicher Effekt eindeutig.
- Implementierung im richtigen Layer, keine doppelte Methodik in UI.
- Eingaben, Rechte, Objektzugehörigkeit und Zustände serverseitig geprüft.
- Persistente Änderungen atomar und bei Retry sicher.
- Relevante positive und negative Tests bestanden.
- Fehlerzustände menschenlesbar, keine falsche Speicherbestätigung.
- API-/Nutzerdokumentation aktualisiert.
- Keine echten Daten oder Secrets in Testartefakten.
- Migration/Kompatibilität bei Datenänderung dokumentiert.
- Tatsächliche Testkommandos und Resultate festgehalten.

## P0-Demoabnahme

Synthetische Studie von Konfiguration bis Runde-2-Abgabe und Export durchführbar. Analyse referenziert den richtigen Snapshot. Demoidentitäten sind deutlich gekennzeichnet. Realer Mailversand deaktiviert. Fehlende Produktionsfunktionen werden konkret aufgelistet.

## P1-Technikabnahme

| Gate | Mussnachweis |
|---|---|
| Methodik | alle Referenzfälle, Nenner, Gruppen und Versionsvergleich geprüft |
| Speicherung | Save/Submit/Close-Konkurrenz und Retry bestehen |
| Isolation | Zwei-Studien-/Zwei-Personenfälle und Exportrechte bestehen |
| Identität | realer Gatewaypfad, Subjectbindung und Sessiongrenzen getestet |
| Feedback | eingefrorene Freigabe, persönliche Vorantwort und Unterdrückung korrekt |
| Qualitativ | Ursprung bis finalem Item exportierbar |
| Kommunikation | Kampagnenfreigabe, Sinktest, Retry-/Unknownverhalten dokumentiert |
| Reporting | unabhängige Offline-Reproduktion aus Export |
| Betrieb | Migration, Neustart, Workerwiederaufnahme, Backuprestore |
| UX | Kernpfad mobil und per Tastatur nutzbar |
| Leistung | definierter Lasttest; Ziele erfüllt oder genehmigte Grenzen |
| Dokumentation | Installations-, Bedienungs- und Incidentanleitungen vorhanden |

## Studienfreigabe

Tatsächliche Organisation, Ansprechpartner, Einwilligungs-/Informationstexte, zuständige Freigaben, Konsens-/Stopregeln, Panelkriterien, Übersetzungen, Kontakt-/Mailkonfiguration, Zugriffsrollen, Speicher-/Aufbewahrungspolicy und Pilotprüfung müssen geklärt sein. Diese Angaben werden durch den Softwareagenten nicht erfunden.

## Blockierende Fehler

Verlust bestätigter Antworten; fremde Daten sichtbar; nicht reproduzierbare primäre Klassifikation; veränderliches freigegebenes Feedback; undokumentierte Regeländerung; fehlende Authentifizierung auf Produktivpfad; Exporte öffentlich erreichbar; Restore nicht nachgewiesen; echte E-Mails aus Testläufen.

## Nicht blockierende Einschränkungen

Optionales XLSX, zusätzliche Diagramme, Real-Time-Delphi, Rankings und KI-Funktionen können fehlen, wenn sie nicht zum freigegebenen Scope gehören. Eine fehlende P1-Anforderung darf nicht als optional umetikettiert werden, ohne den Scope mit verantwortlicher Stelle zu ändern.

## Releasebericht

Version/Commit; Schema-/Lockfileversion; implementierte Anforderungen; getestete Umgebungen; Testresultate; Last-/Restoreergebnis; offene Fehler; bekannte methodische Grenzen; Migrationsschritte; Rollback-/Recovery; benötigte Betreiberentscheidungen; Freigebende und Datum. Ein Feld „nicht ausgeführt“ bleibt sichtbar und wird nicht als bestanden gewertet.

## Übergabe

Lauffähiger Code; Installationsanleitung; synthetische Demostudie; Konfigurationsvorlagen; Paketdokumentation; Testberichte; Betriebsrunbooks; Exportbeispiel und Reproduktionsskript. Credentials separat über genehmigten Kanal, niemals in der allgemeinen Übergabedatei.
