# Anforderungsmatrix

Stand: 2026-09-25. `implemented_tested` bezeichnet den belegten synthetischen technischen Teil; keine institutionelle Studienfreigabe.

| ID | Status | Nachweis / Grenze |
|---|---|---|
| STU-01 | implemented_tested | Immutable Historie, Hashfreigabe, Gruppen-/Skalenidentität; Protokollupload/-diff/-freigabe im echten Browser. |
| STU-02 | in_progress | Teilfunktion vorhanden; vollständiges P1-Gate offen. |
| STU-03 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| PAN-01 | implemented_tested | CSV-Schema, Zeilenfehler, Dubletten, genaue Dateifreigabe und atomarer Import; echter Browser und Rollbacktest. |
| PAN-02 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| PAN-03 | in_progress | Synthetischer Rückzug stoppt neue Aktivität; Save/Withdraw-Rennen geprüft. Produktive Datenpolicy/Löschung offen. |
| PAN-04 | implemented_tested | Ereignisgebundene Gruppenänderung gilt nur für neue Runden; alte Enrollmentgruppen unverändert. |
| ITM-01 | in_progress | Teilfunktion vorhanden; vollständiges P1-Gate offen. |
| ITM-02 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| ITM-03 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| ITM-04 | in_progress | Teilfunktion vorhanden; vollständiges P1-Gate offen. |
| RND-01 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| RND-02 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| RND-03 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| RSP-01 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| RSP-02 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| RSP-03 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| RSP-04 | in_progress | Realer Browser: Verbindungsverlust bleibt unbestätigt, Reload stellt letzte Revision her; Autosave offen. |
| ANA-01 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| ANA-02 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| ANA-03 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| ANA-04 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| ANA-05 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| FDB-01 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| FDB-02 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| FDB-03 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| QUA-01 | in_progress | Services und echte PostgreSQL-Browserredaktion samt unabhängiger Freigabe geprüft. |
| QUA-02 | in_progress | Mehrfachverknüpfungen geprüft; vollständiger explorativer UI-Pfad offen. |
| COM-01 | in_progress | Exakte Freigabe/Outbox im Sink geprüft; Provider/Kontakte offen. |
| COM-02 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| EXP-01 | in_progress | Numerisches P0-Profil ohne Kontakte; weitere Profile/Freitext offen. |
| EXP-02 | in_progress | Quarto, Instrument-/Nenner-/Missingness-Tabellen und Manifest geprüft; Autorenangaben fehlen bewusst. |
| SEC-01 | in_progress | Direkter Shiny-Gatewaypfad besteht zwölf reale Checks; Stock OSS verwirft Header und bleibt offen. |
| SEC-02 | in_progress | Minimale Fehler/Auditdaten; vollständige Canarymatrix offen. |
| SEC-03 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| AUD-01 | in_progress | Teilfunktion vorhanden; vollständiges P1-Gate offen. |
| OPS-01 | in_progress | DB und ausgewählter Studienartefaktrestore samt Offline-Reproduktion bestanden; Produktivrestore offen. |
| OPS-02 | implemented_tested | Reale Service-/DB- oder unabhängige Methodiktests; siehe Validierungsbericht. |
| UX-01 | in_progress | 390px ohne Overflow, ausgewählter Tastatur-/Abgabepfad bestanden; vollständige Tab-/Assistenztechnikmatrix offen. |
| UX-02 | in_progress | DE/EN, erhaltene Entwürfe, Rechte-Navigation und Zeitzone geprüft; vollständige Managementmatrix offen. |
| RTD-01 | out_of_scope | P2 gemäß Spezifikation. |
| RNK-01 | out_of_scope | P2 gemäß Spezifikation. |
