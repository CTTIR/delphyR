# Rollen, Berechtigungen und Identitätstrennung

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Rollenmodell

Rollen sind studienspezifisch, additiv nur innerhalb genehmigter Kombinationen und standardmäßig restriktiv. Betrieb ist eine technische Zuständigkeit und erhält nicht automatisch wissenschaftliche UI-Rechte. Ein Systemadministrator kann technisch weitreichenden Zugriff besitzen; „anonym gegenüber jedem Administrator“ darf deshalb nicht versprochen werden.

| Fähigkeit | Leitung | Koordination | Methodik | Redaktion | Panel | Audit |
|---|---|---|---|---|---|---|
| Protokoll bearbeiten | Ja | Nein | Entwurf | Nein | Nein | Lesen |
| Runde freigeben/öffnen | Ja | Nein | Nein | Nein | Nein | Lesen |
| Kontakte bearbeiten | Nur Zusatzrecht | Ja | Nein | Nein | Eigene | Nein |
| Einladungskampagne vorbereiten | Ja | Ja | Nein | Nein | Nein | Status |
| Pseudonyme Einzelantworten lesen | Zusatzrecht | Nein | Ja | Nur benötigte Texte | Eigene | Zusatzrecht |
| Aggregierte Analyse lesen | Ja | Optional | Ja | Optional | Freigegeben | Ja |
| Qualitative Beiträge redigieren | Optional | Nein | Optional | Ja | Eigene vor Abgabe | Lesen |
| Feedback freigeben | Ja | Nein | Vorschlag | Vorschlag | Nein | Lesen |
| Endgültige Abgabe | Nein | Nein | Nein | Nein | Eigene | Nein |
| Forschungsdaten exportieren | Zusatzrecht | Nein | Ja | Nein | Nein | Zusatzrecht |
| Kontaktexport | Zusatzrecht | Zusatzrecht | Nein | Nein | Nein | Nein |
| Rollen verwalten | Ja, eingeschränkt | Nein | Nein | Nein | Nein | Nein |

„Zusatzrecht“ bedeutet explizite Capability, nicht impliziter Zugriff über eine Bildschirmnavigation. Leitung kann nicht ohne Protokollierung zu jedem Panelkonto wechseln. Support-Impersonation gehört nicht zu P1.

## Autorisierungsvertrag

Jeder Service-Befehl erhält einen vertrauenswürdig erzeugten `actor_context`. Er enthält Principal-ID, ausgewählte Studie, angeforderte Capability und Korrelations-ID. Der Client darf weder Rollen noch Analyse-ID frei setzen. Der Server löst diese aus verifizierter Identität und aktuellen Mitgliedschaften auf.

Reihenfolge: Identität prüfen; aktiven Account und Mitgliedschaft prüfen; Capability prüfen; Objektzugehörigkeit prüfen; aktuellen Prozesszustand prüfen; Datenoperation ausführen; Audit-Ereignis erzeugen. Auch Downloads, Vorschauen, Hintergrundjobs und Wiederaufnahme-Links durchlaufen diese Kontrolle.

Rechte werden an jeder Mutation und jedem sensiblen Abruf neu geprüft. Langlebige Shiny-Sitzungen dürfen veraltete Rollen nicht unbegrenzt im Session-Cache behalten. Eine Account-Sperre oder Mitgliedschaftsrevokation muss spätestens bei der nächsten geschützten Aktion wirken. Bereits ausgelieferte Daten können technisch nicht zurückgerufen werden.

## Identität und Pseudonyme

`principal_id` identifiziert ein authentifiziertes Konto. `membership_id` verbindet es mit einer Studie. `panelist_id` ist eine zufällige studienspezifische Analysekennung. Nicht aus E-Mail-Adressen hashen und nicht über Studien wiederverwenden. Die Zuordnung liegt in einem stärker geschützten Schema als Forschungsantworten.

Einwilligungen und Kontaktinformationen sind personenbezogen. Ein pseudonymisierter Datensatz ist nicht automatisch anonym. Freitexte können zusätzliche Identifikatoren enthalten. Die zugesicherte Anonymität muss unterscheiden zwischen anderen Panelmitgliedern, Koordination, Forschenden und technischen Administratoren.

## Trennung von Datenbankrollen

Vorzusehen sind: Migration-Owner ohne Nutzung durch die App; App-Service mit beschränkten DML-Rechten; Workerrolle; Backuprolle; Audit-Leser; gegebenenfalls separater Kontakt-/Kommunikationszugriff. Keine interaktiven R-Sitzungen mit produktiven Superuser-Zugangsdaten im normalen Workflow.

Die erste Implementierung darf einen Servicezugang mit mehreren eng gefassten Rechten benötigen. Dann ist die logische Trennung ausdrücklich dokumentiert und gegen Zugriffspfade getestet. Getrennte Schemata allein erzeugen keine Anonymität. PostgreSQL-RLS kann zusätzlich schützen, ersetzt jedoch keine korrekt implementierte Authentifizierung und keinen vertrauenswürdigen Kontext.

## Freigaben

Für Protokoll, Runde, Feedback und Abschluss gibt es separate Freigabeobjekte. Ein Vier-Augen-Prinzip kann aktiviert werden: Urheber und Freigebender müssen unterschiedliche Principals sein. Standardmäßig wird jede Freigabe auch ohne Vier-Augen-Pflicht vollständig protokolliert. Rollenänderungen sind nie ein erlaubter Weg, gesperrte wissenschaftliche Objekte still zu überschreiben.
