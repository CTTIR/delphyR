# Shiny-Oberfläche, Module und Interaktionsdesign

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Gestaltungsziel

Panelmitglieder sollen bewerten können, ohne die interne Architektur zu verstehen. Studienmitarbeitende brauchen einen klaren Ablauf mit Prüfungen, Zuständen und konkreten nächsten Schritten. Technische IDs, Hashes und SQL-Begriffe gehören in administrative Detailansichten, nicht in normale Fragebogentexte.

Die Marke delphyR kann einen Delphin mit Flammenassoziation verwenden. Wissenschaftliche Ansichten bleiben ruhig und gut lesbar. Kein „Feuer“-Wording für angeblich richtige Antworten, keine gamifizierte Belohnung für Konformität und keine Rangliste der Teilnehmenden.

## Informationsarchitektur

**Panelbereich:** Meine Studien → Studieninformation/Einwilligung → aktuelle Runde → Fragenblock → Prüfung/Abgabe → Bestätigung. Freigegebene Vorinformationen sind direkt bei den relevanten Items zugänglich.

**Studienbereich:** Übersicht → Protokoll → Panel → Instrument → Runden → qualitative Arbeit → Analyse → Feedback → Kommunikation → Exporte → Verlauf. Sichtbarkeit folgt Rollen; Services prüfen unabhängig davon.

**Betriebsbereich:** Status, Worker, Artefakterzeugung und technische Fehler. Kein pauschales Interface für alle Rohantworten.

## Modulvertrag

| Modul | Eingaben | Ausgaben/Ereignisse |
|---|---|---|
| `mod_study_selector` | autorisierte Studienliste | ausgewählte Studien-ID |
| `mod_consent` | aktive Information/Version | akzeptiert/abgelehnt, Receipt |
| `mod_round_home` | Enrollment und Rundenzustand | Start/Fortsetzen, Fristinformationen |
| `mod_rating_item` | Round-Item, eigener Antwortstand, freigegebenes Feedback | validierter Savewunsch |
| `mod_rating_block` | geordnete Items | Fortschritt, Navigation, Fehlermenge |
| `mod_submission` | aktueller Antwortsatz | ausdrücklich ausgelöste Abgabe |
| `mod_protocol` | Protokollversionen | Entwurf/Validierung/Freigabewunsch |
| `mod_item_editor` | Itemversionen, Quellen | neue Fassung/Importvorschau |
| `mod_panel_admin` | minimale zulässige Kontaktdaten | Rekrutierungs-/Zuweisungsaktionen |
| `mod_round_control` | Rundenzustände | autorisierte Übergangswünsche |
| `mod_qualitative` | zugewiesene Beiträge | Codierung/Redaktion/Itemableitung |
| `mod_analysis` | Analyseobjekt | Filter innerhalb erlaubter Sichten |
| `mod_feedback_editor` | Analyse und Texte | Preview/Freigabe |
| `mod_communications` | Kampagnenentwurf | Empfängervorschau/Freigabe |
| `mod_exports` | Exportrechte, verfügbare Snapshots | Auftrag/Download |
| `mod_audit` | gefilterte Ereignisse | Suche/zulässiger Export |

Jedes Modul verwendet Namespaces. Serviceabhängigkeiten werden injiziert. Keine Datenbankoperation in einem Plotrenderer, keine Konsensformel in `observeEvent()` duplizieren.

## Bewertungsscreen

```text
Runde 2 · Block 3 von 6 · Abgabe bis 18.11., 18:00 Europe/Berlin
Item 24: [klar formulierter Wortlaut]
[Definition / Hintergrund aufklappen]

Ihre Bewertung in Runde 1: 6
Panel Runde 1: n=42 · Verteilung anzeigen
[freigegebenes Feedback und Kommentare]

Wie relevant ist dieses Item?
1 2 3 4 5 6 7 8 9   [vollständige oder erreichbare Skalenanker]
[Kann ich nicht beurteilen] [Enthaltung, falls zulässig]
Kommentar: [optionales Textfeld]

Gespeichert um 14:32:08
[Zurück] [Weiter]
```

Bei geändertem Wortlaut ein klarer Hinweis, keine versteckte Vergleichbarkeit. Kein vorausgewählter mittlerer oder vorheriger Wert. Optionales Kommentarfeld eindeutig von obligatorischen Begründungen unterscheiden.

## Autosave

Eingaben nach kurzer Debouncezeit speichern, jedoch Abgabe und Navigation mit ausstehenden Saves koordinieren. UI-Zustände: „Ungespeicherte Änderung“, „Wird gespeichert“, „Gespeichert“, „Speichern fehlgeschlagen“, „Konflikt“. Nur die Serverantwort nach Commit erlaubt „Gespeichert“.

Bei Netzverlust keine fortlaufenden Erfolgssymbole. Lokalen aktuellen Formularinhalt soweit möglich erhalten, Wiederverbindung prüfen und vor erneutem Senden Serverrevision laden. Keine dauerhafte Browserablage vollständiger Antworten auf gemeinsam benutzten Geräten als Standard.

## Abgabe

Vor Abgabe Zusammenfassung von beantworteten, unbeantworteten und bewusst ausgelassenen Items. Pflichtverletzungen führen zu direkten Sprunglinks. Falls die Methodik Teilabgaben zulässt, dies ausdrücklich erklären. Nach Abgabe Receipt, Zeitpunkt und Bearbeitungspolitik zeigen. Eine zweite Bestätigung ist für irreversible Abgabe sachlich gerechtfertigt, aber nicht für jeden normalen Save.

## Fortschritt

Fortschritt basiert auf zugewiesenen Antwortfeldern und erlaubten Sonderantworten. Nicht vorgelegte Items zählen nicht. Mehrere Dimensionen können getrennte Antworten erfordern; „20 von 40“ muss daher erklären, ob Fragen oder Bewertungsfelder gezählt werden.

## Barrierefreiheit

Tastaturbedienung, sichtbarer Fokus, Labels, verständliche Fehlermeldungen, ausreichender Kontrast, sinnvolle Headinghierarchie und Screenreaderstatus für Saves. Diagramme haben tabellarische Alternativen. Farben ergänzen Textstatus; sie tragen ihn nicht allein. Große Matrizen auf kleinen Bildschirmen vermeiden. Browserzoom und reduzierte Bewegung prüfen. Keine pauschale Konformitätsbehauptung ohne entsprechende Prüfung.

## Sprache und Zeit

Übersetzungsschlüssel statt verstreuter Textliterale. Instrumentübersetzungen werden fachlich geprüft und versioniert; spontane Maschinenübersetzung ist kein Standard. Sprache ändern darf keine Antworten löschen. Fristen zeigen Zeitzone; gespeicherte Zeiten bleiben UTC.

## Leere und fehlerhafte Zustände

Geplante Ansichten: keine aktive Runde, noch kein Feedback, keine berechtigte Studie, Teilnahme zurückgezogen, Sitzung abgelaufen, Datenbank nicht erreichbar, Export in Arbeit, Runde während Bearbeitung geschlossen. Jeder Zustand erklärt die mögliche nächste Handlung und vermeidet falsche Datenverlustbehauptungen.
