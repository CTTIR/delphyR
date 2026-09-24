# End-to-End-Szenarien für Demo und Abnahme

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Szenario 1 — Vollständiges modifiziertes Delphi

**Setup:** synthetische Studie, 30 Personen in zwei Gruppen, 12 Items, eine Relevanzdimension, zwei Runden. Für genügend gültige Gruppenfälle jeweils mindestens zehn gültige Bewertungen erzeugen. Skala/Regeln aus dem Beispielprofil, klar als Demo gekennzeichnet.

**Ablauf:** Leitung legt Protokoll an → Methodik prüft Regeln → Items per CSV importieren → Preview → Freigabe → Koordination legt Einladungen im Sink an → Testpersonen authentifizieren sich und stimmen zu → Runde 1 beantworten → Abgaben → Close → Freeze → Analyse → Redaktion prüft Kommentare → Feedbackfreigabe → Itementscheidungen → Runde 2 öffnen → persönliche Vorbewertung und Panelverteilung → erneute Abgabe → Abschluss → Export → Offline-Reproduktion.

**Erwartung:** jeder Schritt ist über UI möglich und im Audit erkennbar. Keine manuelle SQLreparatur. Der finale Bericht nennt Runden, Teilnahme und Entscheidungen. Forschungsexport enthält keine Kontakttabelle.

## Szenario 2 — Explorative Freitextrunde

Acht synthetische Personen liefern Vorschläge. Redaktion segmentiert Beiträge, codiert Themen, führt Duplikate zusammen und formuliert fünf Ratingitems. Eine Minderheitsposition bleibt im Feedback sichtbar. Die anschließende Ratingrunde verwendet neue Itemidentitäten mit Herkunftslinks. Acht Personen sind hier Demo, nicht methodische Empfehlung; Mindest-n-Regeln für Rating werden nicht umgangen.

**Erwartung:** Originalbeitrag bleibt unverändert; jede Ableitung referenziert Quellen; Redaktion und Freigabe nachvollziehbar; kein vorgetäuschtes numerisches Ergebnis aus Freitext.

## Szenario 3 — Abbruch und zwei Tabs

Person öffnet denselben Fragebogen in zwei Browserkontexten. A speichert neue Bewertung; B sendet alte Revision. B erhält Konflikt ohne Überschreiben. Netzwerk von A wird während weiterer Eingabe unterbrochen. UI meldet ungespeichert; nach Wiederaufnahme lädt sie bestätigten Stand.

**Erwartung:** kein fremder oder verlorener bestätigter Wert. Aktualisierung nach Konflikt nur mit bewusster Nutzeraktion. Audit enthält tatsächliche erfolgreiche Revisionen, keine erfundene Abgabe.

## Szenario 4 — Frist und Rundenabschluss

Zwei Saves befinden sich im kontrollierten Konkurrenztest vor beziehungsweise nach der Close-Sperre. Ein zugelassener Save wird committed, der andere wird mit closed-Status abgewiesen. Ein Submit konkurriert mit Close.

**Erwartung:** gültige Transaktionsreihenfolge eindeutig. Snapshot enthält genau zulässige Submissions gemäß Policy. Browser zeigt keine spätere erfolgreiche Speicherung, wenn DB abgewiesen hat.

## Szenario 5 — Geändertes Item

Runde-1-Item wird substanziell umformuliert. Redaktion markiert Bedeutungsänderung. Runde 2 zeigt aktuellen Wortlaut und Revisionshinweis. Die App berechnet keinen direkten gepaarten Stabilitätswert über die inkompatiblen Fassungen.

**Erwartung:** `not_comparable` mit Begründung; beide Fassungen im Export; kein automatisches Löschen alter Bewertungen.

## Szenario 6 — Gruppen und fehlende Daten

Gruppe A erreicht Konsens; Gruppe B hat zu wenig gültige Antworten. Gesamtquote sieht hoch aus. „Konsens in allen Gruppen“ ergibt insufficient_data. Im Feedback ist eine sehr kleine Untergruppe unterdrückt.

**Erwartung:** Gesamtquote überstimmt die Gruppenregel nicht. Darstellung ermöglicht keine Rekonstruktion über Gesamt-minus-Untergruppe. Interne Analyse und Darstellungspolicy getrennt.

## Szenario 7 — Rollenentzug während Sitzung

Ein Methodikkonto hat Analyse geöffnet. Leitung entzieht dessen Studienrolle. Nächster Export-/Datenabruf wird verweigert. Panelmitglied versucht fremde bekannte Antwort-ID. Nicht eingeloggter Besucher versucht gefälschten Identityheader.

**Erwartung:** kein neuer Zugriff nach Revokation; fremde Antwort nicht sichtbar; Headerumgehung scheitert. Bereits im Browser sichtbare Inhalte sind technisch nicht rückrufbar und werden nicht als gelöscht behauptet.

## Szenario 8 — Erinnerung und verspätete Abgabe

Koordination gibt Reminderkampagne für zehn säumige Personen frei. Zwei geben vor Workerexecution ab, eine zieht Teilnahme zurück. Worker verschickt nur an die verbleibenden sieben, soweit keine anderen Sperren greifen.

**Erwartung:** drei Nachrichten werden mit Grund unterdrückt. Sink zeigt keine Bewertungen. Ein Retry führt nicht zur doppelten Outboxeinplanung. Provider-Unknownfall separat simulieren.

## Szenario 9 — Falsche Freigabe und Korrektur

Ein Feedbacktext enthält einen erkannten redaktionellen Fehler. Nach Veröffentlichung darf er nicht in place editiert werden. Neue Version wird erstellt, freigegeben und den betroffenen späteren Ansichten zugewiesen. Auswirkungen auf bereits bewertende Personen werden fachlich dokumentiert.

**Erwartung:** alte Anzeigeereignisse referenzieren alte Version; korrigierte Version hat neue ID/Hash; keine rückwirkende Umschreibung der Informationsbasis.

## Szenario 10 — Restore und Reproduktion

Backup einer abgeschlossenen synthetischen Studie erstellen. Frische Umgebung ohne Produktivmail konfigurieren. Daten und Artefakte wiederherstellen; Migration-/Integritätscheck; Exportanalyse offline berechnen.

**Erwartung:** Antwort- und Submissionzahlen, Snapshotprüfsummen und kanonische Ergebniswerte stimmen. Worker sendet keine alten E-Mails ungeprüft erneut. Seit Backup erfolgte Revokations-/Löschereignisse werden gemäß Runbook berücksichtigt.

## Ergebnisprotokoll

Je Szenario: tatsächliche Umgebung, IDs ausschließlich synthetisch, Schritte, erwartete/erhaltene Resultate, Screenshots wenn hilfreich, Testartefakte, offene Punkte. „Durchgespielt“ ohne überprüfbare Daten-/Rechteassertions reicht für die kritischen Fälle nicht.
