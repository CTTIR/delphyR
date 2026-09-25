# Synthetische Kampagnen und lokale Outbox

Die P0-Kommunikationsdienste schreiben ausschließlich in einen PostgreSQL-Mail-Sink.
Sie enthalten keinen SMTP-Client, keinen externen Provideradapter und keine
Empfängeradressen. `sink_recorded` bedeutet eine lokale Testquittung; es belegt weder
Versand noch Zustellung oder Lesen einer Nachricht.

## Exakte Vorschau und ausdrückliche Freigabe

`prepare_campaign()` erhält eine Runde, eine ausdrückliche Liste ihrer Enrollment-IDs,
einen Anlass, Sprache, Templateversion sowie fertigen Betreff und Nachrichtentext.
Erlaubte Anlässe sind `invitation`, `round_start`, `reminder`, `deadline_change` und
`completion`. Nicht ersetzte `{{...}}`-Platzhalter werden abgewiesen. Es gibt keine
Adressfelder und keine automatische Erweiterung der freigegebenen Zielgruppe.

`preview_campaign()` zeigt exakt diesen Text, den Hash und Studienpseudonyme der
Empfänger. Kontaktdaten, Principal-IDs und individuelle Antworten werden nicht
zurückgegeben. Kampagnenzugriffe benötigen die aktuelle Capability `coordinate`;
der synthetische Manager verfügt standardmäßig darüber.

```r
# repo, manager, round_id und enrollment_ids stammen aus einer synthetischen Studie.
campaign <- delphyr::prepare_campaign(
  repo, manager, round_id, enrollment_ids,
  kind = "reminder", subject = "Synthetische Erinnerung",
  body = "Lokaler Funktionstest. Es erfolgt kein externer Versand.",
  locale = "de", template_version = 1L, command_id = "campaign-01"
)
delphyr::preview_campaign(repo, manager, campaign$id)

# Erst nach menschlicher Prüfung der konkreten Vorschau ausführen.
delphyr::release_campaign(
  repo, manager, campaign$id, expected_hash = campaign$hash,
  reason = "Synthetischen Text und exakte Zielgruppe geprüft",
  command_id = "campaign-01-release"
)
```

Der Hash bindet Text, Anlass, Sprache, Templateversion, Runde und die sortierte
Empfängerliste. Freigabeereignis und deduplizierte Outboxeinträge entstehen in einer
Transaktion. Identische Wiederholungen mit gleichem Command-Key liefern die frühere
Quittung; derselbe Key mit geändertem Inhalt wird zurückgewiesen. Kampagne,
Freigaben, Empfänger und Outboxhüllen sind unveränderlich. Änderungen benötigen
somit eine neue geprüfte Kampagne.

`cancel_campaign(repo, manager, campaign$id, reason, command_id)` stoppt noch nicht
verarbeitete Nachrichten. Bereits protokollierte Sinkquittungen bleiben erhalten.

## Getrennter Sink-Worker

Vertrauenswürdiger Worker-Code ruft `process_campaign_sink(repo, study_id)` auf.
Die Funktion benötigt keinen Browser-Actor und gehört daher nicht in einen
unautorisierten UI-Handler. Sie beansprucht höchstens eine Nachricht mit einer
dauerhaften Lease und verarbeitet sie in einer zweiten kurzen Transaktion.

Unmittelbar vor dem Sinkeintrag werden erneut geprüft:

- Kampagne nicht storniert und freigebende Person weiterhin koordinationsberechtigt;
- Principal, Studienmitgliedschaft und Panelteilnahme aktiv, Panelrecht nicht entzogen;
- kein Rückzug oder negatives jüngstes Einwilligungsereignis;
- erforderliche Einwilligung vorhanden; Einladung und Rundenstart dürfen zur
  Einwilligung auffordern, sofern kein Rückzug vorliegt;
- bei Erinnerung keine bereits erfolgte Abgabe;
- für Rundenstart, Erinnerung und Friständerung Runde offen und Frist nicht abgelaufen.

Die Prüfung kann die freigegebene Menge nur reduzieren. Veraltete oder gesperrte
Nachrichten erhalten `suppressed` mit einem technischen Grund. Die Sperrfolge
Runde → Enrollment entspricht Save/Submit/Close; ein bereits abgeschlossener Submit
verhindert damit eine nachfolgend zugelassene Erinnerung.

Erfolgreiche lokale Verarbeitung schreibt eine eindeutige, unveränderliche
`ops.message_sink`-Quittung und `sink_recorded` atomar. Verarbeitungsergebnisse
erscheinen zusätzlich im Auditprotokoll. Nachrichtentext und Antworten werden
nicht als Audit-Objektreferenz verwendet.

## Absturz und unklare Zustellung

Ein abgelaufener `running`-Claim wird konservativ zu `delivery_unknown`. Er wird
nicht automatisch neu versendet oder erneut beansprucht. Ein alter Leaseinhaber
kann nach Ablauf keinen Erfolg mehr verbuchen. Der Sink ist pro Nachrichten-ID
eindeutig, doch daraus folgt keine Exactly-once-Zusage für einen zukünftigen
externen Provider.

Das P0-System implementiert keine manuelle Auflösung von `delivery_unknown`, keine
Providerbestätigung, Bounceverarbeitung, Kontaktverwaltung, Ruhezeiten oder
automatischen Reminderpläne. Dafür sind ein gesonderter Adaptervertrag, explizite
Freigaben und weitere Tests erforderlich. Der aktuelle Sink liefert lediglich den
nachprüfbaren lokalen Kampagnen-/Outboxpfad.

## Tests

`test-communications.R` benötigt die ausdrückliche Umgebungsvariable
`DELPHYR_TEST_DB=true` und die lokale synthetische PostgreSQL-Datenbank. Es prüft
Freigabe-Hash, Deduplizierung, Studiengrenzen, Rollenentzug, nachträgliche Abgabe,
Rückzug, Storno, unveränderliche Daten und abgelaufene Leases. Kein Test sendet eine
externe Nachricht.
