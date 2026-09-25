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

## Oberfläche: Panel und Studienleitung

Die [lokale Startanleitung](operations.md) zeigt Manager- und Panelsitzungen. In der
Panelansicht zuerst Studie und zugewiesene Runde auswählen, die Studieninformation
lesen und die Einwilligung ausdrücklich festhalten. Bewertungen beginnen ohne
vorausgewählten Skalenwert. Zulässige Sonderantworten werden separat gewählt.

Jedes Feld wird ausdrücklich gespeichert. Erst eine bestätigte Revision mit
Serverzeitpunkt zählt als gespeichert. Bei einem Fehler bleibt die Eingabe zur
Korrektur sichtbar; ein Versionskonflikt verlangt einen erneuten Abgleich mit dem
Server. Ausstehende Änderungen vor der abschließenden Abgabe speichern. Die
Abgabe liefert eine dauerhafte Quittung und beendet die Bearbeitung dieser Runde.

Die Studienleitung prüft das Instrument und bestätigt Zustandswechsel mit einer
Begründung. Eine geschlossene Runde wird eingefroren. Analyse und Export werden als
Aufträge an den getrennten Worker gegeben; den Auftragsstatus anschließend erneut
prüfen. Feedback zuerst als konkrete Fassung ansehen und danach ausdrücklich
freigeben. Es kann einer noch nicht geöffneten Folgerunde zugeordnet werden.

Deutsch und Englisch sind Oberflächensprachen. Studien- und Instrumenttexte stammen
aus den gespeicherten Fassungen; die Oberfläche übersetzt keine wissenschaftlichen
Inhalte automatisch. Ein sichtbarer oder versteckter Button ersetzt keine
serverseitige Rechteprüfung.

## Redaktion und Quellenbezug

Berechtigte Redakteure sichern synthetische Originalquellen und erstellen getrennte
redigierte Fassungen oder ausdrücklich als solche markierte Zusammenfassungen.
Die Änderung braucht eine Begründung. Eine andere berechtigte Person prüft die
genaue Fassung vor Freigabe; die eigene Fassung kann nicht selbst freigegeben werden.

Themenversionen und Einschluss-/Ausschlusscodierungen dokumentieren auch Dissens.
Quellenbezüge verbinden Itemversionen mit ihrer Herkunft. Split-/Merge-Beziehungen
werden vor dem Speichern geprüft. Ein gespeicherter Quellenbezug importiert noch
kein Item in das Instrument und erteilt keine Studienfreigabe.

## Kampagnen ohne externen Versand

Die Koordination wählt Runde, Anlass und exakte Studienpseudonyme. Betreff und
Nachrichtentext werden fertig formuliert, dann als unveränderliche Vorschau
angelegt. Erst die bestätigte Prüfung dieser Vorschau und eine Begründung erlauben
die Freigabe. Geänderter Text oder eine andere Empfängermenge benötigen eine neue
Vorschau.

Der getrennte Worker schreibt ausschließlich lokale Sinkquittungen. Er unterdrückt
unter anderem überholte Erinnerungen nach einer Abgabe, Rückzüge und stornierte
Kampagnen. `sink_recorded` ist keine echte Zustellbestätigung. `delivery_unknown`
markiert einen abgelaufenen laufenden Claim und löst keinen automatischen Neuversand
aus. Details stehen unter [Synthetische Kommunikation](communications.md).

## Berichte herunterladen und reproduzieren

Nach erfolgreichem Exportauftrag kann die berechtigte anfragende Person das private
Artefakt herunterladen. Der Download prüft erneut Rechte, Ablauf und Prüfsummen.
Der Export enthält den numerischen Datensatz mit Provenienz, Instrumenttexten und
Bericht; qualitative Originaltexte und Kontozuordnungen werden nicht übernommen.
Ein heruntergeladenes Artefakt unterliegt anschließend der Verantwortung der
empfangenden Person und wird durch einen späteren Rechteentzug nicht zurückgerufen.

```sh
Rscript reproduce.R /pfad/zum/entpackten-export
```

Für die Reproduktion muss das dokumentierte Kernpackage verfügbar sein. Quarto ist
für das Neuberechnen der Analyse nicht erforderlich. Der Renderer des vorhandenen
Berichts steht im Manifest. Details und Profilgrenzen enthält die
[Berichtsanleitung](reporting.md).

## Identitäten und Betrieb

`run_app(repo, actor)` ist für eine feste, vertrauenswürdige synthetische Identität
pro lokaler Appinstanz geeignet. Für getrennte Identitäten bietet `run_app()` eine
serverseitige `actor_factory(session, repo)`; eine `repo_factory()` kann zusätzlich
je Sitzung eine eigene Verbindung erstellen, die beim Sitzungsende geschlossen wird.
Bei direkt übergebenem `repo` bleibt dessen Lebensdauer beim aufrufenden Host.
Identität oder Rolle dürfen nicht aus Browserfeldern oder URL-Parametern abgeleitet
werden. Das Demo-Startskript ist kein Mehrbenutzer-Login.

Lokale Demos verwenden ausschließlich synthetische Daten. Produktive Identitätsprüfung,
Studienfreigaben, Nachrichtenversand und Deployment benötigen die jeweiligen
nachgewiesenen Abnahmegates. Maßgeblich sind
[Abnahme und Release](spec/26_ACCEPTANCE_AND_RELEASE.md) sowie der aktuelle
[Implementierungsstatus](IMPLEMENTATION_STATUS.md).

## Fehler melden

Für reproduzierbare Fehler bitte Packageversion, betroffene Funktion, Fehlercode und
ein synthetisches Minimalbeispiel angeben. Keine Tokens, Zugangsdaten, echten
Antworten oder Personenkennungen in Issues oder Logs übernehmen.
