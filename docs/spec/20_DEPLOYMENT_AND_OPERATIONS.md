# Deployment, Betrieb und Wiederherstellung

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Referenzbetrieb

Linuxhost oder institutionelle VM; HTTPS-Reverse-Proxy; OIDC-Gateway; Shiny Server Open Source mit installiertem `delphyrApp`; PostgreSQL; separater R-Worker; privater Artefaktspeicher; institutioneller Maildienst; geschützte Backups. Container Compose ist eine mögliche reproduzierbare Verpackung, aber kein Muss. Bestehende institutionelle Infrastruktur bevorzugen, wenn sie die Verträge erfüllt.

Keine produktiven Ports für PostgreSQL oder Shiny direkt im Internet. Nur Edge öffentlich. Appcode und installierte Packages read-only; Datenbank, Artefakte und Backups außerhalb des App-Bundles. Neustarts oder Neuinstallation dürfen Forschungsdaten nicht ersetzen.

## Umgebungen

- Development: synthetische Daten, Testidentitäten, Mail-Sink.
- Test/CI: ephemere PostgreSQL-Datenbank, reproduzierbare Fixtures, isolierte Artefakte.
- Staging: produktionsähnliche Komponenten, weiterhin synthetische oder ausdrücklich genehmigte Daten.
- Production: freigegebene Version, reale Konfiguration, genehmigte Kommunikation, Restore-Nachweis.

Jede Oberfläche kennzeichnet ihre Umgebung. Ein Stagingbanner darf nicht allein verhindern müssen, dass echte Mailadressen angeschrieben werden; Adapter/Netzkonfiguration müssen echte Zustellung zusätzlich verhindern.

## Konfigurationsvertrag

```text
DELPHYR_ENV=development|test|staging|production
DELPHYR_DB_HOST=<internal host>
DELPHYR_DB_PORT=<port>
DELPHYR_DB_NAME=<database>
DELPHYR_DB_USER=<least privilege role>
DELPHYR_DB_PASSWORD_FILE=<secret file>
DELPHYR_PUBLIC_URL=<https origin>
DELPHYR_ARTIFACT_ROOT=<private path>
DELPHYR_AUTH_MODE=trusted_oidc_gateway
DELPHYR_AUTH_ISSUER=<expected issuer>
DELPHYR_MAIL_MODE=sink|provider
DELPHYR_WORKER_ENABLED=true|false
DELPHYR_LOG_LEVEL=info
```

Diese Namen sind Entwurfsverträge. Secrets ausschließlich aus erlaubtem Secretstore oder restriktiv lesbaren Dateien. `production` plus `sink` kann bewusst für einen Vorabtest erlaubt sein; `development` plus echter Provider sollte explizite Schutzfreigabe benötigen. Beispielkonfigurationen enthalten keine echten Credentials.

## Releaseablauf

1. Gitstand und Lockfiles einfrieren; Tests und Packagecheck bestehen.
2. Images/Binaries bauen und Digests dokumentieren.
3. Migration auf leerer und bestehender Stagingdatenbank testen.
4. Backup und Restorefähigkeit prüfen.
5. Gegebenenfalls Wartungsfenster, Schreibpause und Nutzerinformation planen.
6. Worker kontrolliert drainen; keine laufenden Jobs unklar abbrechen.
7. Migration mit gesonderter Rolle und Migrationslock durchführen.
8. App/Worker auf kompatible Version aktualisieren.
9. Healthchecks und synthetischen Smoke-Test ausführen.
10. Schreibbetrieb freigeben; Logs und Queue beobachten.

Produktionsdeployment ist eine gesonderte autorisierte Handlung. Ein Implementierungsagent darf alle Artefakte und Stagingnachweise vorbereiten, ohne automatisch einen realen Server zu verändern.

## Migrationen

Vorwärts gerichtete nummerierte Migrationen mit Prüfsumme. Bereits angewandte Dateien nicht editieren. Neue Spalten zunächst kompatibel einführen, Daten kontrolliert migrieren, später alte Strukturen entfernen. Destruktive Migrationen benötigen konkreten Datenverlust-/Recoveryplan.

Rollback von Appcode funktioniert nur bei kompatiblem Schema. Ein einfaches `git checkout` stellt keine Datenbank zurück. Restore kann seit dem Backup bestätigte Antworten verlieren; daher vor Rücksicherung RPO, aktuelle Schreibstände und Rettungsmöglichkeiten prüfen.

## Backup und Recovery

Backup umfasst PostgreSQL, Artefakte, notwendige Konfiguration/Versionen und separat verwaltete Wiederherstellungszugänge. Verschlüsselung und Zugriff gemäß Betriebskonzept. Backuperfolg allein reicht nicht; Wiederherstellung in isolierter Umgebung erproben.

Planungswerte, vor Betrieb zu bestätigen: RPO höchstens 24 Stunden für kleinen Pilotbetrieb; RTO ein Arbeitstag. Bei höheren Anforderungen PostgreSQL-WAL-/Point-in-time-Recovery und häufigere Artefaktsicherung vorsehen. Diese Werte sind bewusst keine zugesicherte Produkteigenschaft.

Restoretest: frische Instanz → Backup einspielen → Migrationstatus prüfen → Artefaktprüfsummen prüfen → Studien-/Antwortzahlen vergleichen → synthetischer Login und Roundread → Reproduktionsanalyse → Lösch-/Revokationsereignisse nach Backup berücksichtigen → dokumentierter Abschluss. Reale Nachrichten bleiben beim Test deaktiviert.

## Monitoring

App erreichbar; DB erreichbar; Workerheartbeat; ältester ausstehender Job; Dead-letter-Zahl; Savefehler; Responsezeiten; verfügbare Disk; Backupalter; Zertifikatsablauf; Artefaktfehler. Keine Antwortwerte in Metriklabels. Studien-IDs sparsam und nicht öffentlich exponieren.

Liveness bedeutet laufender Prozess. Readiness bedeutet nötige Abhängigkeiten verfügbar und Schema kompatibel. Eine HTML-Startseite mit Status 200 ist kein vollständiger Funktionsnachweis.

## Ressourcen

DB-Poolgrößen über alle R-Prozesse und Worker zusammen planen. Lange Reports in separatem Prozess mit Memory-/Zeitlimit. Keine massive parallele Workerzahl ohne Lasttest. Der gewählte Shiny-Server-Betrieb skaliert nicht automatisch wie eine beliebige zustandslose REST-Anwendung; WebSockets und Sessionlebensdauer berücksichtigen.

## Runbooks

Je ein Runbook für: DB-Ausfall; Authprovider-Ausfall; nicht ankommende Einladung; Queue hängt; Platte voll; Zertifikat abgelaufen; versehentlicher falscher Rundenabschluss; versehentliches Feedbackrelease; Backuprestore; Sicherheitsvorfall. Jedes enthält Erkennung, Sofortmaßnahme, sichere Wiederaufnahme, Verantwortliche und Nachweis.
