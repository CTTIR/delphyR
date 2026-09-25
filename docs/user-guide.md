# delphyR: Nutzungsanleitung

## Einstieg

Das Kernpackage `delphyr` dient zur unabhängigen Auswertung eingefrorener
Delphi-Rundendaten. `delphyrApp` ist das begleitende Oberflächenpackage.
Aktuelle Funktions- und Testnachweise stehen im
[Implementierungsstatus](IMPLEMENTATION_STATUS.md); die Spezifikation beschreibt
zusätzlich Funktionen, deren Umsetzung noch offen sein kann.

Installationsbefehle enthält die [README](../README.md#installation). Für das
Kernpackage ist bei Offlineanalysen keine laufende Datenbank erforderlich.

## Offlineworkflow

1. Mit `validate_protocol(config)` das vollständige Studienprotokoll prüfen und
   mit `new_protocol(config)` konstruieren. Ungültige Werte erzeugen
   `DEL_VALIDATION`; der Validierungsbericht nennt den betroffenen Pfad.
2. Antworten und Zuordnungen mit `new_snapshot()` zusammenführen. Antworten müssen
   abgegebenen Personen und dem Instrument zugeordnet sein. Die Rundennummer wird
   ausdrücklich mitgegeben; `demo_snapshot()` erstellt immer Runde 1.
3. `analyse_round(snapshot)` ausführen. `results` enthält die Strata,
   `decisions` die Klassifikation unter der Gruppenregel. `denominators` und
   `missingness` gehören zur Interpretation jeder Analyse.
4. Vergleichbare Runden mit `compare_rounds(previous, current)` beschreibend
   vergleichen. Für geänderte Itemversionen ist ein begründetes Mapping nötig.
5. Mit `prepare_feedback(analysis)` einen kontrollierten Entwurf erstellen und
   `validate_feedback()` prüfen. Redaktion und Veröffentlichung sind eigene Schritte.

Die [Offlinevignette](../packages/delphyr/vignettes/offline.Rmd) führt diese Schritte
mit ausführbarem Code aus. Nach Installation mit gebauten Vignetten öffnet
`vignette("offline", package = "delphyr")` die gerenderte Fassung.

## Ergebnisse richtig lesen

`n_valid` ist der Nenner der Zustimmungs- und Ablehnungsanteile. Eine Enthaltung,
fehlende Antwort oder fehlende Beurteilbarkeit zählt nicht als Skalenwert null.
`insufficient_data` bedeutet, dass die festgelegte Mindestzahl nicht erreicht ist;
`no_consensus` ist ein mögliches reguläres Studienergebnis.

Das Standardprotokoll verlangt ausreichende Ergebnisse in allen vorgesehenen
Gruppen. Die kleine Snapshotdemo nutzt ausdrücklich eine gepoolte Regel. Daher kann
ein Gesamtkonsens gleichzeitig mit einer leeren, unzureichenden Gruppe auftreten.

Ein Konsensergebnis beantwortet keine Frage nach individueller Stabilität und
entscheidet nicht automatisch über Itemaufnahme oder Studienabschluss. Die
Schwellen in den Beispielen sind keine methodische Empfehlung.

## Oberfläche und Betrieb

Die Oberfläche muss dieselben Services und Regeln wie das Kernpackage verwenden.
Eine angezeigte Speicherbestätigung setzt einen erfolgreichen Datenbankcommit
voraus. Entwürfe, abgegebene Antworten, geschlossene Runden und freigegebenes
Feedback müssen erkennbar getrennt bleiben.

Lokale Demos sind ausschließlich für synthetische Daten vorgesehen. Produktive
Identitätsprüfung, Studienfreigaben, Nachrichtenversand und Deployment benötigen die
jeweiligen nachgewiesenen Abnahmegates. Maßgeblich sind
[Abnahme und Release](spec/26_ACCEPTANCE_AND_RELEASE.md) sowie der aktuelle
[Implementierungsstatus](IMPLEMENTATION_STATUS.md).

## Fehler melden

Für reproduzierbare Fehler bitte Packageversion, betroffene Funktion, Fehlercode und
ein synthetisches Minimalbeispiel angeben. Keine Tokens, Zugangsdaten, echten
Antworten oder Personenkennungen in Issues oder Logs übernehmen.
