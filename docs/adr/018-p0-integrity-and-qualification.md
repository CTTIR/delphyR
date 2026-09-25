# ADR-018: Entwicklungspfad und Qualifikationsgrenzen

Status: accepted. Datum: 2026-09-25.

Die erste ausführbare Umgebung verwendet ausschließlich synthetische Identitäten
und PostgreSQL auf Loopback. Das Schema trennt Identität, Forschung und Betrieb;
Migrationen und Fixtures nutzen eine Ownerverbindung; App und Worker den
begrenzten delphyr_runtime-Zugang. Dies
qualifiziert weder produktive DB-Rollen noch institutionelle Authentifizierung.
Der App-Service verlangt serverseitig erzeugte Actorobjekte. Browserparameter
sind keine Identitätsquelle. Die nächste geschützte Aktion prüft aktuelle Rechte;
bereits vor einem Widerruf zugelassene Transaktionen dürfen abschließen.

Antworten sperren Runde gemeinsam und Enrollment exklusiv; Close sperrt die Runde
exklusiv. Fristen werden nach Wartezeiten mit Datenbankzeit geprüft. Jede fachliche
Mutation ist transaktional und an einen inhaltsgebundenen Retrykey gebunden.
Angewandte Migrationsdateien sind checksummiert und unveränderlich.

Der Vorabstand 0.0.1 erhält strukturell getaggte wissenschaftliche Hashes. Dies
korrigiert Kollisionen leerer Tabellen und benannter Vektoren im übernommenen
Entwicklungsstand. Frühere lokale Demonstrationshashes sind damit nicht gleich;
es gibt keine veröffentlichte stabile Exportversion oder produktive Migration.

Export v1 unterstützt numerische Studien ohne Freitextantworten. Unverändertes
JSON ist maßgeblich; CSV neutralisiert Formelpräfixe. HTML wird aus demselben
Analysestand escaped erzeugt. Ein vollständiger Quarto-Studienbericht bleibt offen.
Die Shiny-Demo verwendet ausdrückliches Speichern; Autosave ist noch nicht abgenommen.
Keine dieser Grenzen wird als erfüllte P1-Anforderung gewertet.
