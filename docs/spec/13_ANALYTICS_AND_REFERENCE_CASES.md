# Analytik, Formeln und handprüfbare Referenzfälle

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Auswertungseinheit

Standard: Runde × Itemversion × Bewertungsdimension × Stratum. Eine Person liefert pro Einheit höchstens eine in den Snapshot aufgenommene Bewertung. Freitext ist keine numerische Null. Nur freigegebene Abgaben werden im Beispielprofil primär analysiert.

Zu berichten: `n_assigned`, `n_submitted`, `n_valid`, `n_not_answered`, `n_unable`, `n_abstained`, `n_not_applicable`, Kategorienhäufigkeiten, Median, Q1, Q3, IQR, Zustimmungs- und Ablehnungszähler, Prozente, Regelstatus und gegebenenfalls Unterdrückungsstatus.

## Formeln

Für gültige ordinale Bewertungen x und definierte Zustimmungsmenge A:

`n_valid = Anzahl gültiger Bewertungen`

`n_agree = Anzahl(x in A)`

`p_agree = n_agree / n_valid`, nur falls `n_valid > 0`.

Entsprechendes gilt für Ablehnung. Bei null gültigen Antworten sind Quoten und Lageparameter fehlend, Klassifikation ist `insufficient_data`. Prozentformatierung erfolgt erst bei Ausgabe. Eine angezeigte gerundete 70 darf eine tatsächliche Quote unter 0.70 nicht in Konsens verwandeln.

Median nach dokumentierter R-Definition. Quartile für P1 explizit mit `stats::quantile(type = 7)`; Typ in Provenienz aufnehmen. Interpolierte Quartile auf ordinalen Skalen beschreiben die numerische Codierung und sind keine eigenständigen Antwortkategorien. Kategorienverteilung bleibt deshalb immer verfügbar.

Keine standardmäßige Signifikanztestbatterie. Kendall-W oder Inhaltsvaliditätskennzahlen sind nicht automatisch passend zu jeder Ratingaufgabe; nur bei eigener Methodik und geprüfter Implementierung ergänzen.

## Beispielregeln R1

Skala 1–9; Zustimmung 7–9; Ablehnung 1–3; Mindest-n 10. `in`: p_agree >= 0.70 UND p_disagree < 0.15. `out`: p_disagree >= 0.70 UND p_agree < 0.15. Andernfalls `no_consensus`. Ungenügendes n hat Vorrang.

## Referenzfälle

| Fall | Daten | Erwartung |
|---|---|---|
| A | 1,4,6,7,7,8,8,9,9,9 | n=10; Zustimmung=7/10; Ablehnung=1/10; in; Median=7.5; Q1=6.25; Q3=8.75; IQR=2.5 |
| B | dieselben 10 gültigen Werte + unable + unbeantwortet | n_valid=10; n_assigned=12; 70 % Zustimmung; Sonderantworten separat; nicht 7/12 im gewählten Profil |
| C | 20 Werte: dreimal 1, dreimal 4, vierzehnmal 7 | 70 % Zustimmung, 15 % Ablehnung; no_consensus wegen strikt <15 % |
| D | siebenmal 9 und zweimal 5 | 7/9 Zustimmung; insufficient_data wegen n<10 |
| E | 20 zugewiesen, keine gültige Antwort | p/Median/IQR=NA; insufficient_data; keine Division-durch-null |
| F | 1,1,2,2,3,3,3,4,5,9 | 70 % Ablehnung, 10 % Zustimmung; out |
| G | 200 gültig: 139 zustimmend, 20 ablehnend, 41 neutral | 69.5 % Zustimmung; no_consensus auch bei Anzeige „70 %“ |
| H | 10 zustimmend, alle Werte 9 | Median=9; IQR=0; in; keine künstlichen Test-p-Werte |
| I | 10 Werte sämtlich 5 | stabiler neutraler Stand kann no_consensus sein |
| J | Werte außerhalb 1–9 | Validierungsfehler, nicht still abschneiden oder in NA umwandeln |

## Gruppenaggregation

Gruppe A: 8/10 zustimmend, 0 ablehnend → in. Gruppe B: 12/20 zustimmend, 2 ablehnend → no_consensus. Gesamt: 20/30 zustimmend → no_consensus. Eine Regel „alle Gruppen in“ bleibt no_consensus. Bei B mit nur neun gültigen Antworten lautet der Gesamtentscheid unter dieser Regel insufficient_data, selbst wenn A groß genug ist.

Der vollständige Statusvektor je Gruppe bleibt verfügbar. Eine zusammengefasste Klassifikation folgt einer im Regelprofil definierten Wahrheitstabelle. Mindestzellgröße für die Darstellung ist eine andere Größe als Mindest-n für methodische Klassifikation.

## Gepaarte Stabilität: Referenz

Dieselben vier Personen: vorher [5,7,8,9], nachher [6,7,7,9]. Änderungen [1,0,-1,0]. Mittlere absolute Änderung = 0.5; Median absolute Änderung = 0.5; exakt unverändert = 2/4; innerhalb einer Kategorie = 4/4; gepaartes n=4. Vier Personen sind hier ein Rechenbeispiel, keine ausreichende methodische Fallzahlannahme.

Runde 2 mit zusätzlichen Personen benötigt zwei Ausgaben: unpaarige Panelverteilung und gepaarter Verlauf der vier gemeinsamen Personen. Neuaufnahmen und Ausfälle werden separat gezählt. Geänderte Itembedeutung führt standardmäßig zu `not_comparable`, nicht zu einem numerischen Stabilitätswert.

## Sensitivitätsanalysen

Mögliche vorab definierte Profile: vollständige Abgaben versus zugelassene Teilantworten; alle Rundenteilnehmenden versus durchgehend Teilnehmende; alternative Quartildefinition; alternative klar begründete Nenner. Jede Sensitivität erhält Label, Zweck, Regeln und eigenen Ergebnisstand. Sie überschreibt nicht die primäre Analyse.

## Reproduzierbarkeit und Hashing

Kanonische Sortierung nach stabilen IDs und definierte Serialisierung vor Hashbildung. Flüchtige Zeitstempel nicht in den wissenschaftlichen Ergebnisvergleich einbeziehen. Separate Hashes für wissenschaftlichen Inhalt und komplette Ausführungsmetadaten. Rechnerisch identische Resultate können unterschiedliche Run-IDs und Ausführungszeiten haben.

## Interpretation

Veränderung einer Gesamtquote kann durch Panelzusammensetzung entstehen. Wenig Streuung kann gemeinsam niedrige Bewertung bedeuten. Hohe Zustimmung bei niedriger Teilnahmequote verlangt getrennte Darstellung beider Zahlen. Die Oberfläche muss diese Größen benennen, statt sie unter einer allgemeinen „Qualität“-Ampel zusammenzufassen.
