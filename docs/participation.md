# Teilnahme und Stakeholderhistorie

`withdraw_participation()` beendet die eigene weitere Teilnahme. Der Aufruf
verlangt ausdrücklich die synthetische Policy `synthetic_retain_prior_data`:
Bisher bestätigte Forschungsdaten und Abgaben bleiben bestehen. Weitere Saves
und Abgaben werden abgewiesen; die Person ist für neue Rundenzuweisungen und
Nachrichten im lokalen Sink nicht mehr zugelassen. Bereits vor dem Rückzug
abgeschlossene Zustellungen werden dadurch nicht rückgängig gemacht.

Die Paneloberfläche erklärt diesen Datenverbleib und verlangt eine bewusste
Bestätigung. Sie zeigt anschließend den dauerhaften Rückzugsbeleg. Der Service
leitet die Person aus der aktuellen Serveridentität ab; eine beliebige fremde
Personen-ID ist kein Eingabeparameter. Wiederholungen liefern denselben Beleg.
Die Migration `009_participation.sql` schützt Ereignisse vor nachträglicher
Änderung. Bestätigte Saves und Rückzug serialisieren am Enrollment; neue
Runden werden über dieselbe Studiensperre mit dem Rückzug koordiniert.

`set_panel_group()` erfasst eine begründete neue Stakeholderzuordnung durch die
Studienleitung. Sie gilt nur für künftig vorbereitete Runden. Bestehende
Enrollments und deren eingefrorene Analysen behalten ihre alte Gruppenzuordnung.
Vorgänger, neue Gruppe, Akteur und Zeitpunkt bleiben in einem Ereignis erhalten.

Die geprüfte synthetische Policy ist **keine produktive Lösch- oder
Aufbewahrungsregel**. Reale Anträge, institutionelle Fristen, Freigaben und eine
zulässige Datenlöschung benötigen den separaten Governanceprozess aus der
Spezifikation. Dieser Service nimmt keine automatische Löschung vor.
