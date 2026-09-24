# Quellen, Vergleichslösungen und Evidenzgrenzen

> delphyR · Spezifikation v1.0 · 24.09.2026 · Entwurf für die Implementierung

## Rechercheumfang

Recherche-/Abrufstand: 24.09.2026. Grundlage sind öffentlich zugängliche Primärdokumentation und Publikationen. Es erfolgte kein Praxistest kommerzieller Plattformen, keine systematische Marktübersicht, kein Securityaudit und keine vollständige Literaturübersicht. Architekturvorschläge dieses Pakets sind eigene Entwurfsentscheidungen, keine Behauptung, dass ein Anbieter genau diese Lösung implementiert.

Keine vollständige R-/Shiny-Komplettlösung für den gesamten beschriebenen Prozess wurde in dieser begrenzten Recherche verifiziert. Diese Aussage bedeutet nicht, dass es keine solche Lösung gibt. Preise, Hostingverträge und aktuelle Lizenzbedingungen müssen vor Auswahl separat geprüft werden.

## Vergleichslösungen

| Quelle | Beobachteter Beitrag | Wie als Inspiration nutzen |
|---|---|---|
| [COMET DelphiManager](https://www.comet-initiative.org/delphimanager/) | webbasierte Rundenverwaltung, Excelvorlage, Kommunikation, Datenexport | geordneter Studienablauf und Import |
| [DelphiManager Exporte](https://www.comet-initiative.org/delphimanager/dataextracts.html) | Score-/Teilnahme-/Missingexport und Bericht | getrennte Exportprofile |
| [Welphi Tour](https://www.welphi.com/review-delphi-survey-software/) | qualitative/quantitative Fragen, Ranking, Rundenfeedback | einfache Instrument- und Folgerundenbedienung |
| [Welphi FAQ](https://www.welphi.com/welphi-faq/) | beschreibt Feedback zwischen getrennten Runden | klassisches Rundenfeedback nicht mit echtem Real-Time-Delphi gleichsetzen |
| [Delphi Studio Methodology Brief](https://delphistudio.org/downloads/methodology-overview.pdf) | beschreibt Protokoll, Regeln, Feedbackversionen und Reporting | Nachvollziehbarkeit als eigenes Produktmerkmal |
| [contentvalidR Changelog](https://juhalt.github.io/contentvalidR/news/index.html) | Inhaltsvalidität, Expertenurteile und Rundenvergleiche | mögliche Analyseintegration nach eigener Validierung |
| [ElicitationWizard auf CRAN-Mirror](https://www.stat.math.ethz.ch/CRAN/web/packages/ElicitationWizard/index.html) | Shiny zur LLM-basierten Prior-Elicitation mit Delphi-Mechanismen | technisch verwandt, nicht als menschliche Panelplattform verwechseln |

Einzelne contentvalidR-Seiten erwähnen Delphi-Funktionen; Entwicklungs-/Releasedokumentation war nicht in allen Treffern eindeutig deckungsgleich. Deshalb schreibt dieses Paket keine konkrete contentvalidR-API oder Abhängigkeit verbindlich vor. Bei späterer Integration Release, Lizenz, Methodik und Tests prüfen.

## Methodik und Reporting

- [ACCORD Explanation and Elaboration, PLOS Medicine, 2024](https://journals.plos.org/plosmedicine/article?id=10.1371/journal.pmed.1004390): Orientierung für transparente Beschreibung von Konsensverfahren in biomedizinischer Forschung, insbesondere Panel, Ablauf, Schwellen, Feedback und Abweichungen. ACCORD ist eine Reportinghilfe, kein automatisches Qualitätszertifikat.
- [CREDES-Empfehlungen, in zugänglichem Supplement wiedergegeben](https://bmjopen.bmj.com/content/bmjopen/11/3/e043021/DC1/embed/inline-supplementary-material-1.pdf?download=true): Delphi-spezifische Planungs-/Berichtsthemen. Kontext und ursprüngliche Publikation bei wissenschaftlicher Zitation prüfen; die hier zugängliche Darstellung ist nicht mit einer neu erstellten universellen Softwarecheckliste gleichzusetzen.

Das Beispielprofil mit 70 %/15 % und Mindest-n 10 ist eine explizite Demonstrationskonfiguration dieses Entwurfs. Es ist keine aus den Quellen abgeleitete universelle Vorgabe. Dasselbe gilt für Quartiltyp, Zellunterdrückung, Lasttestgröße und RPO/RTO-Planungswerte.

## Technische Primärquellen

- [Shiny Server Einführung](https://shiny.posit.co/r/articles/share/shiny-server/): Grenze der integrierten Authentifizierung in Open Source Shiny Server.
- [Shiny Server Open Source](https://opensource.posit.co/software/shiny-server/): Hosting mehrerer Shiny-Apps auf Linux.
- [Posit: Ende des Shiny Server Pro Supports](https://docs.posit.co/how-to-guides/guides/migrate-shiny-server-pro-to-connect.html): Supportende 31.03.2026; keine Empfehlung für eine neue Pro-Installation in diesem Entwurf.
- [DBI Transaktionen](https://dbi.r-dbi.org/reference/dbWithTransaction.html): Transaktionsschnittstelle und Rollback bei Fehlern.
- [pool](https://rstudio.github.io/pool/): Verwaltung wiederverwendbarer Datenbankverbindungen.
- [PostgreSQL SELECT / Locking](https://www.postgresql.org/docs/current/sql-select.html): Grundlagen für Rowlocks und Queueclaims.
- [PostgreSQL Row Security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html): zusätzliche Zugriffspolitiken und besondere Rollen-/Ownerbedingungen.
- [OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/): möglicher externer Authentifizierungsgateway.
- [Shiny testServer](https://shiny.posit.co/r/reference/shiny/latest/testserver.html): Modul-/Serverfunktionsprüfung.
- [shinytest2](https://rstudio.github.io/shinytest2/): Browsergestützte Shiny-Prüfungen.
- [renv](https://rstudio.github.io/renv/): Aufzeichnung und Wiederherstellung von R-Packageumgebungen.
- [golem](https://github.com/ThinkR-open/golem): Packageorientierte Strukturierung von Shiny-Anwendungen.

## Reuse und Lizenz

Fachliche Abläufe als Inspiration verwenden, keine Oberflächen, Texte oder proprietären Komponenten kopieren. Vor jeder Codeübernahme Lizenz und Kompatibilität prüfen. Quellenangabe allein ersetzt keine Nutzungserlaubnis. Auch eine offene Softwarelizenz erlaubt keine Veröffentlichung fremder personenbezogener Studiendaten.

## Vor Umsetzung erneut prüfen

Aktuelle R-/PostgreSQL-/Packageversionen; Authgatewayfunktionen; unterstützte Linuxdistribution; Sicherheitsupdates; OIDC-Providerfähigkeit für externe Teilnehmende; institutioneller Mailversand; CI-/Browserruntime; Quarto-/PDF-Abhängigkeiten. Konkrete Versionen nach erfolgreichem Integrationstest festschreiben, nicht auf Basis eines Namens im Stacktable allein.
