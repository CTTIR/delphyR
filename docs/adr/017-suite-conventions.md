# ADR-017: CTTIR-Konventionen für Dokumentation und Oberfläche

Status: accepted. Datum: 2026-09-25.

## Kontext

Die aktuelle Nutzerentscheidung benennt das Repository `CTTIR/delphyR` und fordert
Konsistenz mit der CTTIR-Suite. Die technischen Packagenamen bleiben `delphyr` und
`delphyrApp`. Diese Namensentscheidung ersetzt die frühere Repositoryschreibweise
in ADR-016; die archivierte Spezifikation bleibt unverändert.

Als konkrete lokale Referenzen wurden die READMEs von `brainwritR` und `cellspecR`
geprüft: kurzer Produktzweck, ehrlicher Entwicklungsstand, unmittelbar ausführbare
Installation und Einstieg, anschließend Fähigkeiten, Reproduzierbarkeit und Lizenz.
Die Dokumentationssprache für delphyR bleibt gemäß Spezifikation Deutsch.

## Entscheidung

Die README verwendet den Markennamen delphyR, erklärt die abweichende technische
Schreibweise und berücksichtigt die Monorepository-Unterverzeichnisse in der
Installation. Status- und CI-Badges dürfen nur vorhandene, belegte Zustände abbilden.
Ein vorhandenes fremdes Logo wird nicht als delphyR-Logo übernommen.

Die Offlinevignette ist ausführbar und benötigt keine externen Dienste. Sie erläutert
Nenner, Gruppenregel, Missingness, Rundennummer, Vergleichbarkeit und Provenienz.
Zahlenbeispiele bleiben synthetisch und werden nicht als wissenschaftliche Empfehlung
beschrieben. README, Anleitung und Vignette verweisen auf den zentralen
Implementierungsstatus, ohne abgeschlossene Releasegates zu erfinden.

Für die Shiny-Oberfläche gelten ruhige, klare Seiten mit lesbarer Typografie,
ausreichendem Kontrast, ausdrücklich beschrifteten Formularfeldern und einer klaren
Hauptaktion je Arbeitsschritt. Deutsch und Englisch müssen bei Navigation, Aktionen,
Validierung und Status konsistent sein; Sprachwechsel dürfen Eingaben nicht löschen.
Tastaturbedienung, sichtbarer Fokus, mobile Formulare und verständliche Rückmeldungen
sind Pflichtkriterien. Farbe allein vermittelt weder Status noch Fehler.

Eine Oberfläche bestätigt nur tatsächlich abgeschlossene Serviceaktionen. Ein
synthetischer Demomodus bleibt sichtbar. Produktive Authentifizierung, Ergebnisse,
Speicherbestätigungen und Feedbackfreigaben dürfen nicht durch rein visuelle
Platzhalter simuliert werden. Fortschritt, Antwortentwurf und Abgabe sind getrennte
Zustände; sensible Antworten werden nicht in globalen UI-Objekten gehalten.

## Nachweise und Grenzen

Diese ADR legt überprüfbare Konventionen fest; sie bescheinigt keine bestandene
Barrierefreiheits-, Browser-, Sicherheits- oder Produktionsabnahme. Die jeweiligen
Tests und offenen Punkte gehören in `docs/IMPLEMENTATION_STATUS.md`.
