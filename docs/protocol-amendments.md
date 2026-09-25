# Protokolländerungen

`list_protocol_versions()` zeigt der Studienleitung den unveränderten Versionsverlauf,
Hashes und Änderungsbegründungen. `amend_protocol()` nimmt ein vollständig validiertes
Protokoll, den zuletzt geprüften Hash und eine Begründung entgegen. Ein veralteter
Hash wird zurückgewiesen; derselbe bestätigte Auftrag liefert denselben Beleg.

Die neue Version gilt für künftig vorbereitete Runden. Vorhandene Runden,
Instrumente, Antworten und Snapshots behalten ihre bisherige Protokoll-ID. Auch eine
noch nicht geöffnete vorbereitete Runde wird nicht still auf die neue Fassung
umgestellt. Der Studiencode bleibt gleich. Bereits verwendete Skalenkennungen
dürfen in keiner späteren Protokollversion eine andere Bedeutung erhalten; eine
geänderte Skala braucht eine neue Kennung und eine passende Itemversion.

Die PostgreSQL-Migration `007_protocol_amendments.sql` ergänzt unveränderliche
Änderungsereignisse mit Vorgänger, Nachfolger, Akteur, Zeitpunkt und Begründung.
Das technische Freigeben einer synthetischen Fassung ersetzt keine institutionelle
oder ethische Entscheidung. Die Managementoberfläche unterstützt JSON-Upload, Feldvergleich, vollständige
Vorschau und ausdrückliche Freigabe; ein schemaorientierter Formulareditor ist
damit nicht behauptet.

Nachweis: 13 PostgreSQL-Assertions in `test-protocols.R` für Autorisierung,
Historienerhalt, Retry, veraltete Reviews, Skalenidentität und Unveränderlichkeit.
