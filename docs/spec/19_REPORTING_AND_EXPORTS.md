# Berichte, Exporte und Reproduktionspakete

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Exportprofile

| Profil | Inhalt | Empfänger |
|---|---|---|
| study_summary | aggregierter Ablauf, Items, Ergebnisse | freigegebene Studienrollen |
| research_pseudonymized | Antworten, Pseudonyme, Versionen, Gruppen nach Policy | Methodik mit Exportrecht |
| participant_feedback | freigegebene Zusammenfassung und eigene Informationen | jeweiliges Panelmitglied |
| contacts_restricted | minimale Kontaktdaten | gesondert berechtigte Koordination |
| audit_restricted | Ereignisse und Freigaben ohne unnötige Inhalte | Auditor/Leitung |
| public_release | zusätzlich geprüfte anonymisierte Inhalte | Öffentlichkeit nach gesonderter Freigabe |

Ein Export ist an Profil, Datenstand, anfragenden Actor und Zweck gebunden. Ein heruntergeladener Datensatz entzieht sich späterer Zugriffskontrolle; diese Grenze in Governance berücksichtigen.

## Abschlussbericht

1. Studienziel und Begründung des Verfahrens.
2. Design, Varianten, Runden und Änderungen.
3. Verantwortlichkeiten, Panelkriterien und Rekrutierung.
4. Anzahl eingeladen, eingewilligt, begonnen, abgegeben und ausgeschieden je Runde.
5. Instrumentherkunft, Dimensionen und Skalen.
6. Konsens-, Missing-, Gruppen- und Stopregeln.
7. Tatsächlich bereitgestelltes Feedback.
8. Qualitative Aufbereitung und Itementscheidungen.
9. Ergebnisse mit gültigen n, Verteilungen und Regelstatus.
10. Stabilität, Attrition, Sensitivitäten und Einschränkungen.
11. Finale Items, persistierender Dissens und nicht entscheidbare Items.
12. Protokollabweichungen, Finanzierung und Interessenkonflikte soweit erfasst.
13. Daten-/Softwareverfügbarkeit und Reproduktionsinformationen.

Automatisierbare Tabellen werden erzeugt; fachliche Interpretation bleibt ein klar markierter Autorenbereich. Fehlende Angaben als „nicht dokumentiert“ kennzeichnen, nicht durch plausibel klingenden Text ergänzen.

## Reproduktionspaket

```text
study-export/
  README.md
  manifest.json
  data_dictionary.csv
  protocol.json
  items.csv
  item_versions.csv
  round_items.csv
  enrollments_pseudonymized.csv
  responses.csv
  submissions.csv
  analysis_results.csv
  missingness.csv
  item_decisions.csv
  feedback_manifest.json
  amendments.csv
  provenance.json
  reproduce.R
  reports/
```

Dateien je Profil reduzieren. Kontaktdaten, Token und direkte Identitätszuordnungen fehlen im Forschungsprofil. Freitext ist nur enthalten, wenn dieses Profil ihn ausdrücklich erlaubt und die vorgesehene Redaktion stattgefunden hat. Personenübergreifende Analyse-IDs gelten nur innerhalb der exportierten Studie.

## Provenienz

Studien-ID, Exportschemaversion, Snapshot-IDs, Regelversionen, Item-/Skalenversionen, relevante Softwareversionen, Git-Commit, R-Version, Paketlockfilehash, Zeitzone, Locale, Quartildefinition und Konfigurationshash. Exportzeit von Datenstichtag unterscheiden.

Daten- und Resultathashes verwenden kanonische Sortierung und definierte Encodingregeln. Binäre PDF-Prüfsummen können wegen Render-Metadaten variieren; wissenschaftliche Gleichheit deshalb über kanonische Inhalte prüfen. Ein Archivmanifest listet tatsächlich enthaltene Dateien mit Größe und SHA-256 auf.

## Quarto

HTML als Basisformat; PDF/DOCX optional nach eingerichteter Runtime. Renderprozess läuft als Worker mit Ressourcen- und Zeitlimit. Keine Ausführung beliebiger Nutzer-R-Chunks in Templates. Nur vertrauenswürdige versionierte Templates; Nutzereingaben sind Daten.

Langer Bericht blockiert keine Teilnehmendensitzung. Fehlgeschlagenes Rendering beeinflusst eingefrorene Rohdaten nicht. Renderlogs werden bereinigt, bevor sie an Admins ausgegeben werden.

## Download

Privater Artefaktspeicher, berechtigungsgeprüfter Download, Ablaufdatum, Größenlimit und Audit. Eine Artefaktliste zeigt nur zulässige Exporte. Bei Rollenentzug verweigert der Server zukünftige Downloads auch dann, wenn ein alter UI-Link existiert.

## Reporting-Checkliste

Für jedes unterstützte ACCORD-/CREDES-Thema: Quellfeld, vorhandener Stand, Fundstelle im Bericht und noch notwendiger Autorentext. Eine vollständig verlinkte Checkliste ist ein Dokumentationshilfsmittel, keine automatische Compliance- oder Qualitätszertifizierung.

## Reproduktionsabnahme

In einer sauberen Umgebung den Export einlesen, primäre Analyse mit dokumentierter Software berechnen und Tabellen gegen kanonische Referenzen prüfen. Ohne Zugriff auf produktive Kontaktinformationen oder die laufende Shiny-App. Gültigkeitsgrenzen durch Löschung, externe Quellen oder nicht exportierte sensitive Inhalte ausdrücklich nennen.
