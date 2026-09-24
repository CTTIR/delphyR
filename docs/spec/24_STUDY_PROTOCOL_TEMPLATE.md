# Studienprotokoll: ausfüllbare Vorlage und Konfigurationsbeispiel

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Ausfüllbare Studienvorlage

### Identität und Verantwortung

- Studientitel: `[ausfüllen]`
- Kurzcode: `[ausfüllen]`
- Verantwortliche Organisation und Kontakt: `[ausfüllen]`
- Studienleitung/Methodik/Koordination/Redaktion: `[ausfüllen]`
- Protokollversion und Datum: `[ausfüllen]`
- Registrierung/Protokollpublikation, falls vorgesehen: `[ausfüllen oder begründet nicht vorgesehen]`
- Finanzierung und Interessenkonflikte: `[ausfüllen]`

### Ziel und Design

- Forschungsfrage und Zweck des Konsenses: `[ausfüllen]`
- Warum Delphi für diese Frage geeignet ist: `[ausfüllen]`
- Klassisch explorativ oder modifiziert; Begründung: `[ausfüllen]`
- Geplante/maximale Rundenzahl: `[ausfüllen]`
- Zeitplan und Fristen: `[ausfüllen]`
- Stopregeln und Umgang mit anhaltendem Dissens: `[ausfüllen]`

### Panel

- Einschluss-/Ausschlusskriterien und Expertise: `[ausfüllen]`
- Stakeholdergruppen und Auswahlbegründung: `[ausfüllen]`
- Angestrebte Größe und Begründung: `[ausfüllen]`
- Rekrutierung und Einladungswege: `[ausfüllen]`
- Neue Teilnahme nach Runde 1 / Rückkehr nach ausgelassener Runde: `[ausfüllen]`
- Profilmerkmale für Analyse und deren Zweck: `[ausfüllen]`

### Instrument

- Herkunft der Ausgangsitems: `[Literatur, qualitative Beiträge, bestehendes Instrument usw.]`
- Bewertungsdimensionen und Definitionen: `[ausfüllen]`
- Skalenanker und Sonderantworten: `[ausfüllen]`
- Pflicht-/optionale Fragen: `[ausfüllen]`
- Pilottest und Übersetzungsprüfung: `[ausfüllen]`
- Regeln zur Itemrevision, Aufteilung und Zusammenführung: `[ausfüllen]`

### Analyse

- Definition von Zustimmung und Ablehnung: `[ausfüllen]`
- Nenner und Umgang mit Missingness: `[ausfüllen]`
- Mindestzahl gültiger Bewertungen: `[ausfüllen]`
- Gruppenregeln: `[ausfüllen]`
- Konsens-in/-out und unentschiedene Fälle: `[ausfüllen]`
- Stabilitätsmaße und Mindestzahl gepaarter Antworten: `[ausfüllen]`
- Primäre Analyse und Sensitivitäten: `[ausfüllen]`
- Umgang mit Panelwechsel und Attrition: `[ausfüllen]`

### Feedback und qualitative Arbeit

- Statistiken für Teilnehmende: `[ausfüllen]`
- Eigene Vorantwort sichtbar: `[ja/nein und Begründung]`
- Gruppenfeedback und Unterdrückungsregeln: `[ausfüllen]`
- Auswahl/Redaktion/Zusammenfassung von Kommentaren: `[ausfüllen]`
- Codierverfahren und Freigabeverantwortung: `[ausfüllen]`
- Begründungspflicht bei Bewertungsänderungen: `[ausfüllen]`

### Daten und Betrieb

- Studieninformation/Einwilligung und Versionen: `[ausfüllen]`
- Institutionelle/ethische Freigaben: `[ausfüllen]`
- Datenspeicherung, Zugriff, Aufbewahrung und Rückzug: `[ausfüllen]`
- Kommunikationsplan: `[ausfüllen]`
- Finaler Bericht und vorgesehene Datenteilung: `[ausfüllen]`

## Deklaratives Beispiel

**Nur synthetisches Konfigurationsbeispiel. Schwellen, Fristen und Policywerte müssen fachlich bestätigt werden.** Der Validator akzeptiert keine freigegebene Produktivstudie mit ungefüllten Pflichtangaben.

```yaml
schema_version: "1.0"
study:
  code: "DEMO-001"
  title: "Synthetische delphyR-Demonstration"
  environment: "demo"
  timezone: "Europe/Berlin"
  languages: [de, en]
  default_language: de
  design: modified_round_based_delphi
  rationale: "Demonstration, keine reale Forschungsstudie"

panel:
  eligibility_policy: invited_only
  late_entry: false
  return_after_missed_round: false
  groups: [professionals, public_contributors]

instrument:
  dimensions:
    - code: relevance
      scale: relevance_9
  scales:
    relevance_9:
      type: ordinal_integer
      values: [1, 2, 3, 4, 5, 6, 7, 8, 9]
      anchors:
        low: "nicht relevant"
        high: "äußerst relevant"
      missing_options: [unable_to_judge, abstained]
  randomize_items: false
  require_explicit_answer: true
  editing_after_submission: false

analysis:
  primary_population: submitted_only
  denominator: valid_ratings
  quantile_type: 7
  consensus:
    agree_values: [7, 8, 9]
    disagree_values: [1, 2, 3]
    min_valid_n: 10
    in:
      agree: {operator: gte, proportion: 0.70}
      disagree: {operator: lt, proportion: 0.15}
    out:
      disagree: {operator: gte, proportion: 0.70}
      agree: {operator: lt, proportion: 0.15}
    group_policy: all_required_groups
  stability:
    enabled: true
    comparable_versions_only: true
    metrics: [median_absolute_change, proportion_unchanged]
    decision_threshold: null

feedback:
  own_previous_rating: true
  distribution: true
  median: true
  iqr: true
  valid_n: true
  group_statistics: false
  minimum_display_cell_n: 5
  complementary_suppression: true
  comments: moderated_summary
  live_current_round_results: false

communications:
  mode: sink
  campaign_approval_required: true
  automated_reminders_enabled: false

stopping:
  max_rounds: 3
  allow_persistent_dissensus: true
  automatic_study_completion: false
```

## Validierungsregeln für die Konfiguration

Unbekannte Schlüssel als Fehler behandeln, damit Tippfehler nicht unbemerkt Defaults auslösen. Proportionen müssen zwischen 0 und 1 liegen. Kategorien müssen in der jeweiligen Skala vorkommen. Agree-/Disagree-Mengen dürfen sich nicht überlappen. Operatoren kommen aus Allowlist. Mindest-n ist positive Ganzzahl. Erforderliche Gruppen müssen definiert sein. Die Höchstzahl der Runden steht maßgeblich unter `stopping.max_rounds`; widersprüchliche zusätzliche Definitionen sind abzulehnen.

`decision_threshold: null` erlaubt deskriptive Stabilitätsberichte, aber keinen automatisch behaupteten Stabilitätsentscheid. Eine fehlende Datenschutz-/Aufbewahrungsentscheidung ist in der Demo zulässig, vor Produktivfreigabe nicht.

## Amendmentvorlage

Amendment-ID; vorherige Protokollversion; neue Version; Datum; Auslöser; Zeitpunkt relativ zur Datensichtung; betroffene Runden/Items; neue Regeln; Begründung; Auswirkungen auf primäre Analyse; Freigabe; Teilnehmerinformation falls erforderlich; Berichtsfundstelle.
