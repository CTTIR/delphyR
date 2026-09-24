# Konkrete Arbeitspakete und Schnittstellen

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Verwendung

Arbeitspakete können sequentiell durch einen Agenten umgesetzt werden. Parallele Delegation nur bei gesonderter Autorisierung und stabilen Schnittstellen. Jeder Paketabschluss nennt Code, Tests, Dokumentation und Restpunkte. Eine Person oder ein Agent übernimmt Integrationsverantwortung.

## WP-01 — Domänenverträge

**Eingaben:** Methodik, API, Protokollvorlage. **Ausgabe:** S3-Objekte oder klar dokumentierte Listenverträge, Schema-/Antwortvalidatoren, strukturierte Conditions. **Dateibereich:** `packages/delphyr/R/domain-*`, `validate-*`, zugehörige Tests. **Abnahme:** unbekannte Keys, ungültige Skalen, widersprüchliche Regeln und fehlende Pflichtfelder liefern präzise Fehler. **Abhängigkeit:** keine.

## WP-02 — Referenzanalytik

**Eingaben:** WP-01, Rechenfälle. **Ausgabe:** `analyse_round`, Konsensklassifikation, Missingness, Gruppen, `compare_rounds`. **Abnahme:** unabhängig handgeprüfte Fälle A–J und gepaarter Verlauf; Zeilenreihenfolge ohne Einfluss. **Grenze:** keine DB oder Shiny-Abhängigkeit. **Abhängigkeit:** WP-01.

## WP-03 — Schema und Migration

**Eingaben:** Datenmodell. **Ausgabe:** versionierte SQLmigrationen, Repositorygrundlage, Seeds mit synthetischen Daten. **Abnahme:** Studie-fremde Referenzen unmöglich, Unique-/Checkconstraints wirksam, Migration von leer und Vorgängerschema. **Grenze:** keine produktive DB ändern. **Abhängigkeit:** stabiler Objektvertrag aus WP-01.

## WP-04 — Rechte und Actor

**Eingaben:** Rollen, Sicherheitsmodell. **Ausgabe:** Capabilityprüfung, Membershipmapping, Servicekontext, Testidentitäten nur Development. **Abnahme:** fremde Studie, fremde Person, widerrufene Rolle abgewiesen. **Grenze:** keine Clientrollen akzeptieren. **Abhängigkeit:** WP-03.

## WP-05 — Antwortservices

**Eingaben:** WP-03/04. **Ausgabe:** Save, Submit, Close, Revisions-/Commandverwaltung. **Abnahme:** Konkurrenzbarrieren und Retries mit realem PostgreSQL. **Grenze:** kein Last-write-wins. **Abhängigkeit:** WP-01/03/04.

## WP-06 — Snapshot und Workflow

**Eingaben:** Zustandsmaschinen, Antwortservices. **Ausgabe:** Rundenfreigabe, Freeze, Analysejobs, Abschlussweg. **Abnahme:** eingefrorene Daten unverändert; finale Runde ohne unnötige Folgerunde abschließbar. **Abhängigkeit:** WP-02/05.

## WP-07 — Paneloberfläche

**Eingaben:** API und UX. **Ausgabe:** Information/Einwilligung, Rating, Autosave, Konflikt, Abgabe, Receipt. **Abnahme:** Wiederaufnahme, Tastatur, mobile Ansicht, getrennte Sitzungen. **Grenze:** keine Service-/Methodiklogik duplizieren. **Abhängigkeit:** WP-05.

## WP-08 — Studienleitung und Instrument

**Eingaben:** Workflow und Importvertrag. **Ausgabe:** Studieneditor, Itemimportvorschau, Rundensteuerung, Panelverwaltung. **Abnahme:** falsche Skala blockiert Import; gestartete Runde nicht frei editierbar. **Abhängigkeit:** WP-03/04/06.

## WP-09 — Qualitative Herkunft und Revision

**Eingaben:** qualitative Spezifikation. **Ausgabe:** Original/Redaktion, Codes, Zusammenfassungen, Itemableitung, Split/Merge. **Abnahme:** finaler Itemtext bis Quelle nachvollziehbar; Original nicht überschrieben. **Abhängigkeit:** WP-03/08.

## WP-10 — Feedback

**Eingaben:** Analyseobjekt, Redaktion, Policy. **Ausgabe:** Feedbackbuilder, Preview, Freigabe, personale Zuweisung. **Abnahme:** alte Freigabe unverändert, eigene Vorantwort korrekt, kleine Zellen unterdrückt. **Abhängigkeit:** WP-02/06/09.

## WP-11 — Authgateway

**Eingaben:** Sicherheitsmodell, bestehende Institution. **Ausgabe:** geprüfter OIDC-/Headeradapter, Einladungsannahme, Sessionlimits, Konfigvorlagen. **Abnahme:** realer Testgateway einschließlich WebSocket; kein direkter Portzugriff; gefälschter Header scheitert. **Grenze:** institutionelle Produktivwerte nicht erfinden. **Abhängigkeit:** WP-04.

## WP-12 — Worker und Kommunikation

**Eingaben:** Jobvertrag. **Ausgabe:** Queue, Claim/Lease, Outbox, Sinkadapter, Kampagneneditor. **Abnahme:** Neustart/Wiederaufnahme, keine doppelte Einplanung, dokumentierter Unknownzustand. **Grenze:** echte Empfänger nicht anschreiben. **Abhängigkeit:** WP-03/04/06.

## WP-13 — Export und Bericht

**Eingaben:** Snapshot, Analyse und Governance. **Ausgabe:** Exportprofile, private Artefakte, Quarto, Reproduktionsskript. **Abnahme:** keine Kontakte im Forschungsprofil, fremder Download scheitert, Offlineanalyse stimmt. **Abhängigkeit:** WP-02/10/12.

## WP-14 — Betrieb

**Eingaben:** fertige Kernkomponenten. **Ausgabe:** Lockfiles, Deployment, Healthchecks, Migration-/Backup-/Restore-/Incidentrunbooks. **Abnahme:** frische Instanz startet; Restore und Workercrash geprüft. **Abhängigkeit:** WP-11/12/13.

## WP-15 — Integration und Pilot

**Eingaben:** alle Pakete. **Ausgabe:** vollständiger zweirundiger Ablauf, Anforderungsmatrix, Testbericht, restliche Produktiventscheidungen. **Abnahme:** End-to-End-Szenarien und P1-Gates. **Grenze:** institutionelle Freigabe bleibt beim Verantwortlichen.

## Schnittstellen-Freeze

Vor potenzieller Parallelisierung WP-01-Verträge und Datenbankschlüssel festhalten. Änderungen an gemeinsam genutzten Objektfeldern erfordern Integrationsnachricht, Vertragsupdate und Verbrauchertests. Zwei Bearbeiter ändern nicht unkoordiniert dieselbe Migration oder öffentliche API.

## Reviewfragen pro Paket

Ist der wissenschaftliche Effekt korrekt? Welche Rechte braucht die Operation? Was passiert bei Retry oder Absturz? Welche Version bleibt historisch sichtbar? Welche Daten verlassen das System? Welcher unabhängige Test zeigt das Ergebnis? Welche verbleibende Annahme könnte die Abnahme ändern?
