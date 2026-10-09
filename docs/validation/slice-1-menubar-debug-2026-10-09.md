# Slice 1: Untersuchung der Menüleisten-Sichtbarkeit

Datum: 09.10.2026, Europe/Berlin. Lokaler `ce-debug`-Auftrag.
**Status: Untersuchung und lokale Slice-1-UI-Abnahme abgeschlossen. Screenshot
und manuelle Nutzerprüfung bestätigen die bedienbare App. Kein App-Code geändert;
kein alternativer AX-Steuerungsweg benötigt. Slice 2 wurde nicht begonnen.**

Die folgenden Untersuchungsabschnitte halten die damaligen Zwischenstände fest.
Die abschließende Nutzerbestätigung und Entscheidung stehen am Ende.

## Symptom und unveränderte Ausgangslage

Der Nutzer sieht keine App. DictationBar ist eine Menüleisten-App ohne Dock-
Eintrag (`DictationBar/Info.plist:23`). Ihr einziger Zugang ist das SwiftUI-
MenuBarExtra mit Waveform-Symbol (`DictationBar/App/DictationBarApp.swift:12`).
Der lokale native Build und die neun XCTest-Tests sind bereits bestanden.
Branch: `feat/local-slice1-validation`, HEAD: `313d97e`.

Vorhandene Änderungen betreffen README, CE-Konfiguration, Agent-Anweisungen
und Prüfdokumente. Keine dieser Dateien wird von der App geladen. Die App-,
Test- und Projektdateien sind per SHA-256 gegen den Slice-1-Import geprüft
und unverändert. Ein Stash-Experiment war deshalb nicht erforderlich.
Es gibt kein Remote, keinen Tracker und kein Issue of Record; keine externe
Suche, kein Ticket und keine PR wurden angelegt.

## Beobachtete Zustände

| Zustand | Prozess / Statusfenster | X-Position | Vom Fenster-Server sichtbar |
|---|---|---:|---|
| Vor der erneuten UI-Steuerung | PID 30432 / Fenster 4993 | 1059 | Ja |
| Nach der UI-Steuerung | derselbe PID / dasselbe Fenster | 1011 | Nein |
| Erneute native Beobachtung | derselbe PID / dasselbe Fenster | 1011 | Nein |

Das Statusfenster ist 32×43 Punkte groß, Layer 25, Name Item-0. Die App ist
vollständig gestartet, nicht verborgen und hat activationPolicy=1 (accessory).
Ein Screenshot im sichtbaren Zustand zeigt das Waveform-Symbol. Ein weiterer
Screenshot zeigt an dessen Stelle den zusätzlichen violetten macOS-Indikator
für Bildschirmaufnahme/Steuerung; DictationBars Symbol ist dann nicht sichtbar.

Der Mac hat eine einzelne Built-in Retina Display mit 1800×1169 Punkten.
Der vom SDK gemeldete rechte Bereich neben der Kameraaussparung beginnt bei
x=1010 und ist 790 Punkte breit. Der Positionsunterschied der beiden Zustände
beträgt 48 Punkte. Der gleiche laufende Prozess wechselte die Sichtbarkeit
ohne Neuübersetzung, Neustart oder Änderung des App-Codes.

Evidenz unter `build/debug-menubar-20261009/`:

- `baseline.json`, `after-click-probe.json`, `native-observation.json`, `current.json`
- `menubar-visible.png`, `menubar-recording-indicator.png`
- `menubar-probe.swift`, `current-visibility.exitcode`

## Ursachenbewertung

Die Beobachtung stützt diese Kette: Die App erzeugt ihren Menüleisteneintrag;
die UI-Steuerung fügt den macOS-Aufnahmeindikator hinzu; bei der dicht belegten
Menüleiste wird DictationBars Eintrag nach links verschoben und vom Fenster-
Server als nicht sichtbar gemeldet. Ohne den zusätzlichen Indikator war das
Symbol im Screenshot sichtbar. Die konkrete interne Überlaufregel von macOS
wurde nicht untersucht; eine Position im Fenster-Server allein beweist keine
sichtbare oder bedienbare Oberfläche.

Eine fehlgeschlagene App-Initialisierung erklärt die Beobachtung schlechter:
Die gleiche App-Instanz erzeugte bereits ein sichtbar gerendertes Symbol.
Ein fehlendes SF-Symbol ist damit ebenfalls ausgeschlossen. Ein Defekt im
StatusModel kann den Sichtbarkeitswechsel ohne Modell-/Codeänderung nicht
erklären. Es wird kein App-Code auf Grundlage dieser Umweltbeobachtung geändert.

## Nächster Prüfschritt

Die normale UI-Steuerung erreicht das fensterlose Statusmenü nicht. Ihre
`getApp`-Aufrufe enden mit timeoutReached. Ein konkreter Versuch, die
Statusansicht vom Nutzer öffnen zu lassen, ergab die Rückmeldung
„ich sehe überhaupt keine App“.

Als alternativer lokaler Prüfweg wurde ein auf genau die Bundle-ID
`com.primocammino.DictationBar` begrenztes Swift-/AX-Prüfprogramm vorbereitet
und erfolgreich kompiliert. Es benutzt ausschließlich vorhandene
Bedienungshilfen-Freigaben, fordert keine an und verweigert Aktionen, wenn
mehrere App-Instanzen vorliegen oder das exakt erwartete Steuerelement fehlt.
Es kann den eigenen Menüleisteneintrag sowie „Status aktualisieren“ und
„Beenden“ über die jeweils angebotene AXPress-Aktion bedienen.

Vor dieser alternativen UI-Steuerung wurde um ausdrückliche Freigabe gebeten,
weil das Computer-Use-Werkzeug andere Techniken für UI-Aktionen nur bei
ausdrücklichem Nutzerwunsch zulässt. Das Programm wurde noch nicht ausgeführt.
Die offene Bedienprüfung umfasst Öffnen, Statusanzeige, wiederholtes
Aktualisieren, Beenden, Verschwinden des Prozesses und Neustart ohne Dialog.

## Tests und Abnahme

Die bestehenden neun Tests bleiben unverändert. Sie prüfen Permission-Mapping,
Audio-Verfügbarkeit und Modellzustand; den macOS-Fenster-Server und den Platz
in der Menüleiste können sie nicht prüfen. Ein künstlicher Unit-Test über
eine solche Platzannahme würde keinen realen Nachweis liefern. Der passende
Nachweis ist die native Sichtbarkeitsprobe plus echte Bedienung und Screenshot.

Der Sichtbarkeitscheck meldete im Zustand mit Aufnahmeindikator FAIL; diese
Beobachtung ist keine fehlgeschlagene XCTest-Suite. Ein grüner Build oder das
bestehende XCTest-Ergebnis ersetzt die weiterhin offene UI-Abnahme nicht.
Siehe [nativer Prüfbericht](slice-1-local-2026-10-09.md).

## Klärung von Arbeitsordner und App-Start

Auf die Rückfrage des Nutzers wurde der bisherige Nachbarordner vollständig
in `.local-backups/consolidation-20261009-edo8hg4j/extracted-slice-1/`
verschoben. Die 19 Dateien stimmen weiterhin mit dem Sicherungsmanifest
überein. Nur `spechless_macos` bleibt als aktiver Projektordner; seine lokale
Git-Historie und App-/Test-/Projektquellen sind unverändert.

Eine erneute rein lesende Laufzeitprobe zeigt weiterhin PID 30432 aus dem
aktiven Projekt, finishedLaunching=true, hidden=false. Menüleistenfenster
4993 ist wieder bei x=1059 und kCGWindowIsOnscreen=true. Das ersetzt keine
Bedienprüfung. Ein kleiner neuer Screenshot-Ausschnitt konnte vom OS nicht
erstellt werden; es wird deshalb kein neuer Screenshot-Nachweis behauptet.

Der lokale Verweis `DictationBar.app` im aktiven Projekt führt zum geprüften
Debug-Build. Die App hat weiterhin kein normales Fenster und keinen Dock-
Eintrag. Statusansicht, Aktualisieren, Beenden und Neustart bleiben offen.

## Nutzernachweis der geöffneten Statusansicht

Der Nutzer hat einen Screenshot mit sichtbarem, ausgewähltem Waveform-Symbol
und geöffneter DictationBar-Statusansicht geliefert. Die Werte sind wie erwartet:
Mikrofon „Noch nicht angefragt“, Systemaudio „Noch nicht geprüft“, Aufnahme
„Noch nicht verfügbar“. Beide Buttons sind sichtbar. Der Nachweis liegt unter
`build/debug-menubar-20261009/user-status-view.png` samt SHA-256-Beleg.

Ein neuer `cua.getApp('com.primocammino.DictationBar')`-Versuch nach diesem
Screenshot endete erneut mit `timeoutReached`. Es wurde kein alternativer
AX-Steuerungsweg ausgeführt. Die verbleibenden Bedienprüfungen wurden dem
Nutzer als drei konkrete Schritte vorgelegt; deren Ergebnis ist noch offen.
Die sichtbare Statusansicht rechtfertigt keine Behauptung, die Buttons seien
bereits geprüft oder Slice 1 sei vollständig abgenommen.

## Abschluss der manuellen Bedienprüfung

Am 09.10.2026 bestätigte der Nutzer auf die konkret erläuterten Prüfschritte:
**„Alle drei Schritte funktionieren.“** Die Schritte waren:

1. „Status aktualisieren“ zweimal anklicken; die drei Statuswerte bleiben gleich.
2. „Beenden“ anklicken; das Waveform-Symbol verschwindet.
3. Den App-Verweis im aktiven Projekt doppelklicken und das Waveform-Symbol
   erneut öffnen; dieselbe Statusansicht erscheint ohne Freigabedialog.

Dieser manuelle Nachweis schließt die verbleibende Bedienprüfung ab. Der
vorbereitete AX-Steuerungsweg wurde nicht ausgeführt und wird für diese
Abnahme nicht benötigt. Es wurde kein App-Code geändert.

## Debug Summary

**Problem:** Der Nutzer sah zunächst keine gestartete App; die automatische
UI-Steuerung konnte das Menü nicht erreichen.

**Root Cause:** Die App besitzt ausschließlich ein SwiftUI-MenuBarExtra mit
Waveform-Symbol (`DictationBar/App/DictationBarApp.swift:12`) und läuft ohne
Dock-Eintrag (`DictationBar/Info.plist:23`). Der zusätzliche Aufnahmeindikator
der UI-Steuerung korrelierte mit der Verdeckung des Eintrags in der dicht
belegten Menüleiste. Die interne macOS-Überlaufregel wurde nicht bewiesen.
Screenshot und manuelle Bedienung bestätigen, dass die App selbst funktioniert.

**Recommended Tests:** Die neun bestehenden XCTest-Tests für Mapping, Services
und Modell bleiben relevant. Sichtbarkeit und Bedienung benötigen zusätzlich
einen nativen Screenshot und die reale Prüfung von Aktualisieren, Beenden
und Neustart; diese Nachweise liegen jetzt vor.

**Fix:** Keine App-Codekorrektur. Eindeutiger aktiver Projektordner, vollständig
erhaltene Ausgangssicherung, direkter lokaler App-Verweis und verständliche
Startanleitung; UI-Abnahme mit manueller Nutzerprüfung abgeschlossen.

**Prevention:** Eine laufende Menüleisten-App nicht allein anhand eines
fehlenden normalen Fensters oder eines UI-Steuerungs-Timeouts als defekt
einstufen. Aufnahmeindikator und verfügbare Menüleistenfläche berücksichtigen.

**Confidence:** Hoch für die funktionierende App und die bestätigten
Bedienaktionen; mittel für die genaue Ursache der zeitweisen Verdeckung.
