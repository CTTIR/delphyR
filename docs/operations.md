# Lokaler Betrieb und Wiederherstellung

## Geltungsbereich

Diese Anleitung gilt für die synthetische P0-Entwicklungsumgebung. PostgreSQL läuft
lokal auf `127.0.0.1:55439`, Datenbank `delphyr`, Container
`delphyr-dev-postgres`. Migrationen und Fixtures verwenden `postgres`; App und Worker verwenden
`delphyr_runtime` ohne Owner-, DDL-, Lösch- oder Superuserrechte. Die lokale
Trust-Authentifizierung bleibt eine Entwicklungsvereinfachung und ist keine
produktive Zugriffsarchitektur.

`demo_actor()` erzeugt ausschließlich kurzlebige synthetische Serveridentitäten.
Ein geprüfter OIDC-Gateway, institutionelle Einwilligungs- und Aufbewahrungsvorgaben,
produktive Datenbankrollen und ein öffentliches Deployment sind nicht qualifiziert.
Die Compose-Datei bindet PostgreSQL nur an Loopback; diese Bindung darf für die Demo
nicht auf alle Netzwerkschnittstellen erweitert werden.

## Start aus dem Repositoryverzeichnis

R mit Entwicklungsabhängigkeiten und Docker werden vorausgesetzt. Vorhandene
Datenbankcontainer und Volumes bleiben erhalten. Falls die lokale Datenbank bereits
läuft, wird kein zweiter Container gestartet.

```sh
Rscript scripts/bootstrap.R
# Nur beim Einrichten bzw. Starten der Entwicklungsdatenbank:
docker compose -f deploy/compose.dev.yaml up -d
Rscript scripts/configure-dev-role.R
Rscript scripts/start-demo.R manager 3849
```

Die Manageroberfläche läuft auf `http://127.0.0.1:3849`. In einem weiteren Terminal
kann ein synthetischer Panelzugang gestartet werden:

```sh
Rscript scripts/start-demo.R 1 3850
```

Die Zahl wählt eine synthetische Person aus; sie ist kein Anmeldeverfahren.
Die lokale Fixture-Datei `.local/demo-fixture.rds` hält die Zuordnung zur Demostudie.
App-Neustarts sollen auf denselben Datenbankstand und dieselbe Fixture verweisen.
Eine Fixture darf nicht blind gegen eine andere oder geleerte Datenbank verwendet
werden. Nach einem Datenbankfehler zuerst Verbindung und Zuordnungen prüfen.

Der separate Worker verarbeitet Analyse-/Exportaufträge und freigegebene
synthetische Nachrichten ausschließlich im Datenbank-Sink:

```sh
Rscript scripts/worker.R
```

Prozesse im jeweiligen Terminal mit `Ctrl+C` beenden. Das Beenden einer App löscht
keine Datenbank. Lokale Bibliotheken, Fixture-Dateien, Prüfprotokolle und Artefakte
sind ignoriert und werden nicht mit Git übertragen.

## Gezielte Funktionsprüfung

```sh
Rscript scripts/check.R
DELPHYR_TEST_DB=true Rscript scripts/integration.R
Rscript scripts/demo-e2e.R
```

Die PostgreSQL-Integrationstests benötigen ausdrücklich `DELPHYR_TEST_DB=true`.
Sie legen eindeutig benannte synthetische Studien an. Sie löschen keine vorhandenen
Studien und setzen kein Schema zurück. Die Konkurrenztests starten unabhängige
R-Prozesse mit eigenen Verbindungen; beobachtete Datenbanksperren bestimmen die
Reihenfolge. Ein zufälliges Warten ersetzt keinen Synchronisationsnachweis.

## Reale Datenbankwiederherstellung prüfen

```sh
scripts/restore-check.sh
```

Das Skript liest ausschließlich aus dem vorhandenen synthetischen Quellcontainer.
Es exportiert einen konsistenten PostgreSQL-Snapshot und nutzt genau diesen sowohl
für `pg_dump` als auch für die Vergleichswerte. Parallel abgeschlossene neue
Transaktionen verändern damit nicht die erwarteten Werte des Backups.

Anschließend startet es mit dem lokal vorhandenen Image der Quelle eine neue,
eindeutig benannte PostgreSQL-Instanz. Diese besitzt kein Docker-Netzwerk und keine
veröffentlichten Hostports. Zugriff erfolgt über `docker exec`. `pg_restore` spielt
das Backup mit Fehlerabbruch in einer Transaktion ein. Geprüft werden:

- Zeilenzahl und Inhaltsfingerprint aller Tabellen in `identity`, `research`, `ops`;
- Spalten, Constraints, benutzerdefinierte Trigger und Funktionen;
- Migrationsversionen und Prüfsummen gegen die lokalen SQL-Dateien;
- IDs, gespeicherte Hashes und JSON-Inhalte der eingefrorenen Snapshots.

Mindestens ein eingefrorener synthetischer Snapshot muss vorhanden sein. Der
zweirundige Demopfad erzeugt solche Snapshots. Ein leeres Datenbankschema allein
gilt nicht als erfolgreicher Recovery-Nachweis.

Jeder Lauf legt ein neues, nur für den lokalen Benutzer zugängliches Verzeichnis
unter `.checks/restore-*` an. Darin liegen `database.dump`, `restore.log`, die
Quell- und Zielvergleiche sowie bei Erfolg `result.json` mit `status: PASS`,
Image-ID, Dump-SHA-256 und Prüfbereich. Vorherige Nachweise werden nicht gelöscht.
Das Skript entfernt ausschließlich seinen eigenen temporären Restorecontainer
samt dessen Volume; der Quellcontainer und dessen Volume bleiben bestehen.

Dies belegt **Datenbankwiederherstellung im synthetischen P0-System**. Exportdateien
im privaten Artefaktspeicher werden hier nicht gesichert oder wiederhergestellt;
entsprechende Datenbankeinträge allein stellen deren Bytes nicht wieder her.
OIDC, SMTP, Betriebskonfiguration, Schlüssel, produktive Rollen, Point-in-time-Recovery
und zugesicherte Wiederanlauf- oder Datenverlustzeiten sind ebenfalls nicht Teil
dieses Tests. Eine vollständige Betriebsfreigabe erfordert zusätzliche Nachweise
aus [Abnahme und Release](spec/26_ACCEPTANCE_AND_RELEASE.md).

## Fehlerbehandlung

Bei Datenbankausfall keine Speicherung als erfolgreich melden. Verbindung und
Containerzustand prüfen; anschließend aktuelle Antworten und dauerhafte
Abgabequittungen neu laden. Idempotenzschlüssel nur für identische Wiederholungen
verwenden. Konflikte verlangen einen erneuten Abgleich des Serverstands.

Bei Export- oder Workerfehlern Auftragszustand und Fehlercode prüfen. Einen
abgelaufenen Auftrag nur über die vorgesehene Queue erneut beanspruchen; laufende
Leases und erfolgreiche Ergebnisse nicht manuell überschreiben. Artefakte bleiben
privat und werden beim Abruf erneut autorisiert.

Bei gescheitertem Restore den neuen Nachweisordner und `restore.log` bewahren.
Die produktive oder ursprüngliche Datenbank wird nicht als Reparaturversuch
überschrieben. Ein echter Rücksicherungsentscheid braucht einen konkreten
Datenverlust-, Freigabe- und Wiederanlaufplan.
