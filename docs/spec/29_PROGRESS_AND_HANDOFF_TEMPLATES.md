# Fortschritt, Testnachweise und Übergabevorlagen

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Fortschrittsdatei für die Implementierung

Empfohlener Pfad im späteren Repository: `docs/IMPLEMENTATION_STATUS.md`.

```markdown
# Implementierungsstatus
Stand: [Datum, Commit]
Aktueller Meilenstein: [M1–M7]

## Tatsächlich funktionsfähig
- [Anforderungs-ID]: [Funktion] — [Codepfad] — [Nachweis]

## In Arbeit
- [WP-ID]: [konkreter verbleibender Schritt]

## Blockiert
- [fehlende Information oder Infrastruktur]
- Betroffene Arbeit: [...]
- Unabhängig fortsetzbar: [...]

## Nächste Schritte
1. [...]
2. [...]

## Letzte relevante Tests
| Kommando | Umgebung | Ergebnis | Artefakt |
|---|---|---|---|
| [...] | [...] | pass/fail/not_run | [...] |

## Bekannte Grenzen
- [...]
```

## Anforderungsmatrix

```markdown
| ID | Status | Implementierung | Test | Hinweis |
|---|---|---|---|---|
| RSP-01 | implemented_tested | ... | ... | ... |
| SEC-01 | implemented_not_tested | ... | noch offen | fehlender Testprovider |
| RTD-01 | out_of_scope | — | — | P2 |
```

Statuswerte nicht kreativ vermischen: `not_started`, `in_progress`, `implemented_not_tested`, `implemented_tested`, `blocked`, `out_of_scope`. Dokumentation allein ist keine Implementierung.

## Testbericht

```markdown
# Testlauf [ID]
Commit:
R / PostgreSQL / OS:
Package-/Lockfileversion:
Fixtureversion:
Start/Ende:

## Ausgeführt
[exakte Kommandos]

## Ergebnis
[Anzahl oder benannte Suiten; Exitcodes]

## Fehler
[Reproduktion, Auswirkung, nächste Maßnahme]

## Nicht ausgeführt
[Grund und betroffene Releasegates]

## Artefakte
[Logs, Reports, Screenshots ohne echte Daten]
```

## ADR

```markdown
# ADR-XXX: [Entscheidung]
Status: proposed/accepted/superseded
Datum:

## Kontext
[Problem und relevante Randbedingungen]
## Entscheidung
[konkrete Wahl]
## Alternativen
[ernsthaft betrachtete Optionen]
## Folgen
[Implementierung, Betrieb, Methodik, Sicherheit]
## Migration und Tests
[notwendige Änderungen und Nachweise]
## Ersetzt
[vorherige ADR, falls relevant]
```

## Übergabe bei Unterbrechung

Repository/Branch/Commit; vorhandene uncommittete Änderungen; erreichter Meilenstein; zuletzt bestandene Tests; aktuell laufende Prozesse mit IDs; benötigte lokale Dienste; genaue nächste Aktion; relevante Dateien; offene fachliche Entscheidungen; keine Secrets. Die nächste Bearbeitung soll fortsetzen können, ohne bereits erledigte Arbeit erneut zu implementieren.

## PR-/Änderungsbeschreibung

Problem und neues Verhalten zuerst. Danach wenige technische Details, die die Bewertung erleichtern, gefolgt von tatsächlichen Tests und Einschränkungen. Migrationen und mögliche Auswirkungen auf laufende Studien explizit nennen. Keine bloße Chronologie aller Werkzeugaufrufe.

## Fehlerbericht

Titel; Umgebung; synthetische Reproduktion; erwartetes Verhalten; tatsächliches Verhalten; betroffene IDs ohne personenbezogene Inhalte; Korrelations-ID; Ausmaß; Datenintegrität betroffen ja/nein/unbekannt; Workaround; Nachweis nach Fix. Unbekannt bleibt unbekannt, bis geprüft.

## Abschlussnotiz

„Implementiert: … Getestet: … Start: … Verbleibend: … Für Produktivbetrieb noch erforderlich: …“ Diese Struktur verhindert, dass ein Demoerfolg als gesamte Studienfreigabe gelesen wird.
