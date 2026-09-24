# Hintergrundjobs, Einladungen und Erinnerungen

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Warum ein Worker

E-Mailversand, Berichterstellung und umfangreiche Analysen dürfen nicht von einer geöffneten Shiny-Sitzung abhängen. Ein separater R-Prozess liest eine dauerhafte Queue in PostgreSQL. Ein Neustart der App darf weder Aufträge verlieren noch mehrere gleichartige wissenschaftliche Freigaben auslösen.

## Jobvertrag

Felder: ID, Studie, Typ, referenzierter unveränderlicher Input, Status, Priorität, `available_at`, Versuchszahl, Leaseinhaber, `lease_until`, Heartbeat, Fehlerklasse, Resultatreferenz und Deduplizierungsschlüssel. Payloads enthalten vorzugsweise Referenzen statt kopierter Kontakte/Antworten.

Worker beansprucht Jobs transaktional. `FOR UPDATE SKIP LOCKED` ist ein mögliches PostgreSQL-Muster für mehrere Worker; Verhalten unter Absturz und Leaseablauf testen. Kein Job wird während langsamer externer Operationen mit einer minutenlangen DB-Transaktion gehalten. Claim und Ergebnisverbuchung sind kurze getrennte Transaktionen.

## Typen

- `freeze_round`: konsistenten Antwortsnapshot erzeugen.
- `analyse_snapshot`: reine Analyse mit exakten Regeln ausführen.
- `render_feedback`: freigegebenen Inhalt rendern.
- `render_report`: Bericht aus unveränderlichen Quellen bauen.
- `build_export`: genehmigtes Exportprofil materialisieren.
- `send_message`: freigegebene Nachricht versenden.
- `retention_task`: ausschließlich genehmigte Aufbewahrungsaktion ausführen.

Jobs dürfen keine fachlichen Freigaben selbst erteilen. Ein Renderjob ist keine Genehmigung seines Inhalts.

## Outbox

Die Freigabe einer Kampagne und die Erstellung ihrer Outboxeinträge erfolgen atomar. Jede logische Nachricht hat einen eindeutigen Deduplizierungsschlüssel, z. B. Studie + Runde + Kampagne + Empfänger + Templateversion. Das verhindert doppelte Einplanung, garantiert aber bei einem unklaren externen Providerergebnis noch keinen exakt einmaligen Versand.

Wenn der Provider Idempotency-Keys unterstützt, denselben Key bei Retry verwenden. Ohne diese Unterstützung kann „Provider hat angenommen, Antwort ging verloren“ zu unklarer Zustellung führen. Status `delivery_unknown` vorsehen und nicht unbegrenzt blind neu senden. Provider-ID und Eventverarbeitung deduplizieren. Kein pauschales „exactly once“ versprechen.

## Kampagnenworkflow

1. Anlass wählen: Einladung, Rundenstart, Erinnerung, Friständerung, Abschluss.
2. Vorlage und Sprache wählen; Variablen validieren.
3. Empfängerregel berechnen und Kontakte rollenbeschränkt anzeigen.
4. Vorschau einschließlich Testnachricht an explizit freigegebene interne Testadresse.
5. Exakte Kampagne mit Inhalt, Zielgruppe und Zeit freigeben.
6. Outbox anlegen.
7. Worker prüft unmittelbar vor Versand erneut Sperre, Rückzug, Abgabe und Kampagnenstatus.
8. Gesendet, unterdrückt, zurückgewiesen, fehlgeschlagen oder unbekannt dokumentieren.

Ein nach Freigabe abgegebenes Panelmitglied erhält keine überholte Erinnerung. Die erneute Prüfung unterdrückt den Versand, erweitert aber nicht unbemerkt die freigegebene Empfängermenge.

## Nachrichtendaten

Nur nötige Inhalte in E-Mails: Studie, Runde, Frist, sicherer Zugangsweg und Kontakt. Keine individuellen Bewertungen oder sensible Freitexte. Empfänger einzeln adressieren; keine offenen Gruppenverteiler. Betreff und Vorschautext dürfen keine ungewollten sensiblen Informationen offenlegen.

Mailzustände unterscheiden: erstellt, beim Provider angenommen, zugestellt soweit messbar, bounced, beschwerdebedingt blockiert. „Gesendet“ beweist nicht „gelesen“. Open-Tracking ist kein P1-Standard.

## Vorlagen

```text
Einladung: Einladung zur Delphi-Studie {{study_title}}
Guten Tag {{display_name}},
wir laden Sie zur Teilnahme an {{study_title}} ein.
Informationen zu Ziel, Aufwand und Teilnahme finden Sie über Ihren Zugang.
{{access_url}}
Ansprechpartner: {{contact}}
```

Alle Platzhalter werden kontextgerecht escaped. Fehlender Pflichtplatzhalter blockiert die Kampagne. Templateversionen bleiben nachvollziehbar. Zugangstokens werden nicht in technische Logs geschrieben.

## Reminderregeln

Maximale Zahl, Mindestabstand, Ruhezeiten/Zeitzone und Ausschlüsse konfigurieren. Default in Entwicklung: kein echter Versand. Produktiv muss eine verantwortliche Person Kampagne oder klar begrenzten Reminderplan ausdrücklich freigeben. Ein Agent darf im Rahmen einer Softwareimplementierung die Funktionen und Tests bauen, aber nicht dadurch reale Teilnehmende anschreiben.

## Betriebsaspekte

Queuealter, Fehlerrate, Dead-letter-Zahl, Versandrate und Providerfehler überwachen. Retry mit begrenztem exponentiellem Backoff und Jitter. Dauerhafte Fehler wie ungültige Adresse nicht endlos wiederholen. Admin kann Job neu einplanen, muss aber die Idempotenz-/Zustellungsunsicherheit sehen.
