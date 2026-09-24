# Datengovernance, Einwilligung und Aufbewahrung

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Geltungsbereich

Dieses Dokument beschreibt technische und organisatorische Anforderungen, keine individuelle Rechtsberatung und keine Bescheinigung der DSGVO-Konformität. Vor Einsatz legt die verantwortliche Organisation Rechtsgrundlage, Informationspflichten, institutionelle/ethische Anforderungen, Dienstleisterrollen und Aufbewahrung fest. Die Software stellt dafür überprüfbare Funktionen bereit.

## Dateninventar

| Datenklasse | Zweck | Zugriff | Exportstandard |
|---|---|---|---|
| Namen/E-Mail | Einladungen und Support | Koordination, genehmigte Leitung | ausgeschlossen |
| Verifizierte Account-ID | Zugang und Zuordnung | Identitäts-/Serviceebene | ausgeschlossen |
| Stakeholdermerkmale | Panelbeschreibung und Gruppenanalyse | nach Rollen und Granularität | minimiert |
| Einwilligung | Teilnahmegrundlage dokumentieren | genehmigte Mitarbeitende | separater beschränkter Export |
| Numerische Bewertungen | Forschungsanalyse | pseudonymisiert für Methodik | Forschungsprofil |
| Freitext | Begründungen und Itementwicklung | Redaktion/Methodik | redigiert oder beschränkt |
| Audit | Nachvollziehbarkeit | Audit/Leitung | minimiertes Auditprofil |
| technische Logs | Fehler und Betrieb | Betrieb | nicht im Forschungsdatenexport |
| Feedback und Berichte | Rückmeldung und Dokumentation | entsprechend Zielgruppe | freigegebene Fassung |

## Studieninformation

Vor Teilnahme sind Zweck, erwarteter Aufwand, Runden, Freiwilligkeit, Umgang mit Rückzug, Datenzugriff, vorgesehene Veröffentlichungen und Kontaktinformationen in verständlicher Form vorzulegen. Die tatsächlich angezeigte Sprach-/Textversion muss gespeichert werden. Eine neue Information kann erneute Zustimmung benötigen; die Entscheidung trifft die zuständige Stelle und wird konfiguriert.

P1 benötigt eine ausdrückliche Zustimmungshandlung. Reiner Aufruf eines Links ist keine Zustimmung. Zeitstempel und Version dokumentieren; zusätzliche personenbezogene technische Daten nur erheben, wenn dafür ein begründeter Zweck besteht.

## Anonymität und Pseudonymisierung

Teilnehmende sehen keine Identitäten anderer Panelmitglieder über die App. Forschende können pseudonymisierte Längsschnittdaten benötigen. Die Kontaktzuordnung bleibt gesondert geschützt. Dies ist eine bewusst definierte Vertraulichkeitsarchitektur, keine Behauptung vollständiger Anonymität gegenüber Betreiber und allen Teammitgliedern.

Profilkombinationen und Freitexte können identifizierend sein. Exporte prüfen institutionelle Angaben, seltene Rollen, Orte und andere quasi-identifizierende Merkmale. Gruppenlabels im öffentlichen Bericht gegebenenfalls gröber fassen.

## Rückzug und Löschaufträge

Teilnahmerückzug stoppt neue Erhebung und Kommunikation. Ob bereits erhobene Antworten verbleiben, gelöscht oder anonymisiert werden, folgt der genehmigten Studieninformation und den anwendbaren Vorgaben. Nicht automatisch jedes Rückzugsereignis mit Löschung gleichsetzen.

Arbeitsablauf: Antrag erfassen → Identität/Zuständigkeit prüfen → betroffene Datenklassen und Rechts-/Studienpolicy bestimmen → fachlich freigeben → operative Umsetzung → betroffene Snapshots/Artefakte markieren → Abschluss dokumentieren. Keinen Klartextpersonenbezug aus Bequemlichkeit in Auditkopien erhalten.

Wenn genehmigte Löschung die Reproduzierbarkeit eines alten Snapshots einschränkt, ist das ein transparent zu dokumentierender Zustand. Der Anspruch auf vollständige Historie darf nicht durch unzulässige Schattenkopien erfüllt werden.

## Aufbewahrung

Separate Fristen für Kontakte, nicht angenommene Einladungen, Einwilligungen, Forschungsdaten, Audit, Downloads und Backups. Werte sind pro Institution/Studie festzulegen. Beispielwerte in technischer Entwicklung dürfen nicht unbemerkt zu produktiven Defaultfristen werden.

Automatische Löschung erfordert einen genehmigten Plan, Dry-run-Bericht und nachvollziehbare Ergebnisse. Soft delete ist kein Nachweis tatsächlicher Entfernung. Backupzyklen und Wiederherstellung können gelöschte Daten zurückbringen; Restoreverfahren muss gegebenenfalls Löschereignisse erneut anwenden.

## Veröffentlichungen

Interner Forschungsdatenexport, Teilnehmerfeedback, Manuskriptanhang und öffentlicher Datensatz sind verschiedene Freigabestufen. Standardexport ist nicht automatisch publikationsgeeignet. Für öffentliche Freigabe separaten Review und klare Dokumentation von Unterdrückungen und Anonymisierung vorsehen.

## Dienstleister und Hosting

Mailprovider, OIDC-Provider, Backupspeicher und gegebenenfalls externe Renderdienste sind Teil des Datenflusses. Die Organisation prüft Verträge, Speicherorte und Zugriffsrechte. Selbsthosting der Shiny-App allein bedeutet nicht, dass sämtliche Daten intern bleiben.

## Verarbeitungsverzeichnis für das Projekt

Die Implementierung soll eine beschreibende Vorlage liefern: Verantwortliche Stelle; Datenkategorien; betroffene Personen; Zwecke; Empfänger; Speicherorte; Fristen; technische Schutzmaßnahmen; Wiederherstellung; Ansprechpartner. Tatsächliche organisationsbezogene Angaben werden nicht erfunden.
