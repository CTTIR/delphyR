# Authentifizierung, Autorisierung und Sicherheitsdesign

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Bedrohungsmodell

Zu schützen sind Antworten, Kontaktzuordnungen, Einwilligungen, wissenschaftliche Integrität, Zugangsdaten und Verfügbarkeit. Relevante Angreifer: nicht eingeloggte Besucher; legitime Panelmitglieder mit manipulierten IDs; Nutzer einer anderen Studie; kompromittierte Mitarbeitendenkonten; fehlerhafte Hintergrundjobs; bösartige Freitexte/Uploads; versehentliche Fehlkonfigurationen. Technische Superuser bleiben eine gesonderte Vertrauensrolle.

## Anmeldung über institutionelle Infrastruktur

P1 nutzt OIDC über einen geprüften Gateway/Reverse Proxy. Der Provider muss externe Panelkonten unterstützen. Gateway verarbeitet Redirect, State/Nonce, Cookies und Tokenprüfung gemäß unterstütztem Produkt. R implementiert diese Protokolle nicht selbst.

Gateway übergibt eine verifizierte stabile Identität an die App. `issuer + subject` ist maßgeblich. Eine E-Mail allein kann geändert oder wiedervergeben werden und ist kein dauerhafter Identitätsanker. Falls ein Gateway nur E-Mail exportiert, muss ein überprüfter stabiler Subject-Transport ergänzt oder ein anderer Adapter gewählt werden.

## Vertrauenswürdige Header

Öffentliche Requests dürfen eigene Identitätsheader nicht einschleusen. Edge entfernt solche Header und setzt ausschließlich verifizierte Werte. Shiny-Port nur intern erreichbar. Wenn Komponenten nicht auf demselben vertrauenswürdigen Netz laufen, authentifizierten Transport oder signierte Identitätsassertion vorsehen.

Die tatsächliche Headerverfügbarkeit in der gewählten Shiny-Server-Konfiguration ist durch einen End-to-End-Test zu belegen. `session$user` nicht voraussetzen. Ein Headername im Spezifikationsdokument ist keine Sicherheitsgarantie.

## Einladungen und Kontobindung

Einladung und Anmeldung sind getrennte Vorgänge. Einladungs-Token ist zufällig, kurzlebig, nur gehasht gespeichert, an Studie/Einladung gebunden und nach erfolgreicher Annahme verbraucht. GET-Aufruf durch einen Mail-Sicherheitsscanner darf noch keine Teilnahme oder Einwilligung auslösen. Annahme erst nach authentifizierter bestätigter Aktion.

Bindung an das eingeladene Konto über verifizierte Providerinformationen und definierte Policy prüfen. Abweichende Konten lösen einen kontrollierten Klärungsprozess aus. Keine automatische Übernahme einer beliebigen `panelist_id` aus URL oder Formular. Einladungstoken ist kein dauerhafter Zugangsschlüssel für alle Folgerunden.

## Sitzungen

HTTPS, Secure-/HttpOnly-Cookies und passende SameSite-Einstellung im Gateway. Logout muss den Appzustand beenden und die vorgesehene Gateway-/Providersitzung berücksichtigen. Verhalten dokumentieren. Maximaldauer und Inaktivitätsdauer werden konfiguriert.

Eine WebSocket-Verbindung kann länger leben als ein ursprünglicher HTTP-Logincheck. Deshalb maximale Identitätslebensdauer und regelmäßige serverseitige Revalidierung/erzwungene Neuanmeldung einplanen. Eigene Rollen-/Accountrevokation vor jeder geschützten Aktion prüfen. Providerseitige Revokation wirkt je nach Gateway-/Tokenarchitektur nicht automatisch sofort; garantierte maximale Verzögerung messen und dokumentieren.

## Eingaben und Ausgaben

- SQL immer parametrisieren; IDs, Sortierspalten und Tabellen aus Allowlisten.
- Freitext als Text rendern; HTML standardmäßig nicht zulassen.
- Markdown nur mit definierter sanitizierter Teilmenge und sicheren Links.
- Uploadgrößen und Zeilenzahlen begrenzen; Dateiendung/MIME nicht allein vertrauen.
- Keine vom Browser vorgegebenen Dateipfade lesen oder schreiben.
- CSV-/XLSX-Ausgabe gegen Formelinterpretation in Tabellenkalkulation absichern.
- Fehlermeldungen ohne Querytext, Secrets, Rohantworten oder vollständige Kontaktdaten.
- Downloadberechtigung bei tatsächlichem Zugriff erneut prüfen.

## Audit und Logs

Audit enthält fachliche Ereignisse mit minimalen erforderlichen Daten. Technische Logs enthalten Korrelations-ID, Operation, Dauer und Fehlerklasse. Keine OIDC-/Einladungstokens, Cookies, DSNs mit Passwort, Antwortpayloads oder unredigierten Freitexte.

Append-only-Audit mit separaten Rechten schützt vor gewöhnlichen Appänderungen, nicht vor allmächtigen DB-Administratoren. Manipulationserkennung durch unabhängige Kopien/Hashketten kann ergänzt werden; „fälschungssicher“ darf ohne entsprechende Infrastruktur nicht behauptet werden.

## Datenbank

Produktive App niemals als Datenbankowner oder Superuser. DB nur intern erreichbar; Transport nach Infrastruktur absichern. Rollen und Schemas prüfen. Verschlüsselung von Speichermedien und Backups nach Betriebskonzept. Schlüssel gehören nicht in dieselbe öffentlich zugängliche Ablage wie Backups.

## Exporte und Artefakte

Privater Speicher außerhalb `www/` und öffentlicher Shinyverzeichnisse. Opaque storage keys. Temporäre Downloads mit Ablauf oder authentifizierter Streamingfunktion. Empfänger-/Studienbezug serverseitig prüfen. Ein erratbarer Dateiname darf niemals reichen.

## Prüfmatrix

Unangemeldeter Zugriff; fremde Studien-ID; fremde Antwort-ID; bekannte fremde Artefakt-ID; gefälschter Identitätsheader; direkte Portumgehung; widerrufene Rolle in laufender Sitzung; abgelaufener Einladungslink; erneut verwendeter Token; GET durch Scanner; XSS-Text; SQL-Injection-Payload; CSV-Formel; oversized Upload; sensible Canarystrings in Logs. Ergebnisse im Releasebericht dokumentieren.

Diese Spezifikation ist ein Sicherheitsentwurf und kein Penetrationstestbericht. Externe produktive Systeme nur innerhalb ausdrücklich genehmigter Testgrenzen prüfen.
