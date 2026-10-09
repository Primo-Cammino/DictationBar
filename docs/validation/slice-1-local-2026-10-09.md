# Slice 1: lokale native Prüfung am 09.10.2026

**Status: Slice 1 lokal abgenommen am 09.10.2026. Nativer Build, neun XCTest-
Tests und die Menüleisten-Bedienprüfung sind bestanden. Die letzten UI-Schritte
hat der Nutzer selbst geprüft und bestätigt. Slice 2 wurde nicht begonnen.**

Dieser Bericht ergänzt den unveränderten [Cloud-Prüfstand](slice-1.md).
Maßgeblich ist der aktuelle Nutzerauftrag zur ausschließlich lokalen Prüfung,
nicht die frühere Cloud-Zuweisung der Geräteprüfung an den Nutzer.

## Geprüfter Stand und Sicherung

Aktives Projekt: `DictationBar`.
Alle sechs App- und drei Testquelldateien sowie Xcode-Projekt, Schema und Plist
entsprechen bytegenau dem Slice-1-ZIP und dem entpackten Quellordner.
App-Code, Tests und Projektkonfiguration wurden nicht geändert.

Der ursprüngliche Zielordner war leer; in beiden Ordnern fehlte `.git`.
Vollständige Ausgangssicherung, ZIP-Kopie und SHA-256-Inventar:
`.local-backups/consolidation-20261009-edo8hg4j/`.
Kein Ausgangsstand wurde gelöscht oder überschrieben. Der Vergleich und die
19 übernommenen Dateien sind im dortigen `manifest.json` dokumentiert.
Der vollständige frühere Nachbarordner liegt jetzt unter `extracted-slice-1/`
in dieser Sicherung; `relocation.json` dokumentiert die erneute Hash-Prüfung.
Ein lokaler `DictationBar.app`-Verweis im aktiven Projekt zeigt auf den geprüften
Debug-Build. App-Quellen und Git-Historie wurden beim Ortswechsel nicht verändert.

Nach den nativen Läufen wurde der Import als neuer lokaler Git-Ausgangsstand
`313d97ece2145a1a72d758596c1194e23ff42fe9` gesichert, Branch
`feat/local-slice1-validation`, ohne Remote. Dieser Commit enthält genau die
geprüften App-/Test-/Projektdateien; spätere Änderungen betreffen Dokumente,
Agent-Anweisungen und lokale Workflow-Konfiguration. Die Importversionen der
Dokumente bleiben in diesem Commit und in der Vollsicherung erhalten.

## Umgebung

| Merkmal | Tatsächlicher Wert |
|---|---|
| Datum | 09.10.2026, Europe/Berlin; XCTest-Start 06:47:58 MESZ, aus dem Ergebnisbundle-Zeitstempel verifiziert |
| macOS | 15.7.3, Build 24G419 |
| Architektur / Gerät | arm64 / MacBook Pro |
| Xcode | 26.3, Build 17C529 |
| Swift | Apple Swift 6.2.4, Projekt-Sprachmodus 5 |
| SDK / Deploymentziel | macOS SDK 26.2 / macOS 14.0 |
| Schema / Konfiguration | DictationBar / Debug |
| Signierung | Ad-hoc, „Sign to Run Locally“, kein Developer-Team |

Rohdaten: `build/local-validation-20261009/environment.log`.

## Build und XCTest

| Prüfung | Ergebnis / Evidenz |
|---|---|
| Schema-Ermittlung | DictationBar und DictationBarTests, Debug/Release, geteiltes Schema DictationBar; `schemes.log` |
| Erster Build in Agent-Sandbox | Exit 65, `sandbox-exec: sandbox_apply: Operation not permitted`; `build.log`. Umgebungsfehler, keine erfolgreiche native Prüfung |
| Debug-Build mit lokalem Xcode-Zugriff außerhalb der Agent-Sandbox | **BUILD SUCCEEDED**, Exit 0; `build-native.log`, `build-native.exitcode` |
| XCTest mit demselben lokalen Xcode-Zugriff | **TEST SUCCEEDED**, Exit 0; `tests.log`, `tests.exitcode`, `tests.xcresult` |
| Ergebnisbundle unabhängig ausgelesen | result Passed, totalTestCount 9, passedTests 9, failedTests 0, skippedTests 0; `test-summary.json` |

| Klasse | Ausgeführt | Bestanden | Fehler |
|---|---:|---:|---:|
| PermissionMappingTests | 4 | 4 | 0 |
| AudioAvailabilityTests | 1 | 1 | 0 |
| StatusModelTests | 4 | 4 | 0 |
| Gesamt | **9** | **9** | **0** |

Apple meldete beim Test-Build Warnungen zum unveränderten signierten XCTest-
Framework und zur übersprungenen AppIntents-Metadatenextraktion. Kein App-/Test-
Quellfehler wurde im erfolgreichen Lauf gemeldet. Der XCTest-Lauf hatte kein
beobachtetes Red-before-Implementation; diese Einschränkung aus der Cloud
wird durch den jetzigen grünen Lauf nicht rückwirkend aufgehoben.

## Echte App-Prüfung

Das gebaute Bundle wurde mit dem lokalen macOS-Launcher gestartet:
`build/DerivedData/Build/Products/Debug/DictationBar.app`.

| Check / Bezug | Beobachtung | Status |
|---|---|---|
| App startet aus Bundle, R1/AE1 | Prozess PID 30432, Bundle-ID com.primocammino.DictationBar, finishedLaunching=true, terminated=false | Bestanden für Prozessstart |
| Kein Dock-Eintrag, AE1 | AppKit activationPolicy=1 (accessory); auch im Desktop-Screenshot kein DictationBar-Dock-Eintrag | Bestanden |
| Sichtbares Menüleisten-Symbol, R1/AE1 | Nutzer-Screenshot zeigt das ausgewählte Waveform-Symbol und die geöffnete DictationBar-Statusansicht; `build/debug-menubar-20261009/user-status-view.png` | **Bestanden für diesen sichtbaren Zustand** |
| Automatischer Freigabedialog beim Start, R4/AE1 | Beim ersten Start kein Dialog beobachtet; Nutzer bestätigt beim geprüften Neustart die gleiche Statusansicht ohne Freigabedialog | **Bestanden, Neustart manuell bestätigt** |
| Symbol anklicken und Statusansicht lesen, R2/R3/R5/AE1/AE2 | Nutzer-Screenshot der geöffneten Ansicht: Mikrofon „Noch nicht angefragt“, Systemaudio „Noch nicht geprüft“, Aufnahme „Noch nicht verfügbar“; beide erwarteten Buttons sichtbar | **Bestanden für Öffnen und angezeigte Werte** |
| Öffnen und zweimal aktualisieren, R4/AE3 | Nutzer klickte „Status aktualisieren“ zweimal; Werte bleiben unverändert. Statusansicht vor und nach dem Neustart erfolgreich geöffnet | **Bestanden, manuell bestätigt** |
| Externe Mikrofonfreigabe ändern / aktualisieren, AE3 | Keine OS-Freigabe geändert, kein TCC-Reset; echte autorisierte/abgelehnte/eingeschränkte Zustände nicht geprüft. XCTest prüft injizierte Werte | Nicht geprüft |
| „Beenden“ und Neustart, R2/AE4 | Nutzer bestätigt: Nach „Beenden“ verschwindet das Waveform-Symbol; Doppelklick auf den App-Verweis startet die App wieder, Statusansicht lässt sich ohne Freigabedialog öffnen | **Bestanden, manuell bestätigt** |

Eine Bildschirmgrenzen-Abfrage zeigt genau eine Built-in Retina Display mit
1800×1169 Punkten. Der nicht sichtbare Status-Window-Eintrag allein beweist
keine bedienbare Menüleisten-App. Die weitere Untersuchung zeigte einen
Sichtbarkeitswechsel bei zusätzlichem Aufnahmeindikator der UI-Steuerung;
Details und Grenzen stehen im [Debug-Bericht](slice-1-menubar-debug-2026-10-09.md).
Der Nutzer-Screenshot und die anschließende manuelle Prüfung bestätigen die
bedienbare App unabhängig von dieser Einschränkung der Automatisierung.

Belege unter `build/local-validation-20261009/`: `process-inspection.log`,
`window-inspection.log`, `displays.log`, `menubar.png`.
Der Nutzer lieferte anschließend einen Screenshot der geöffneten Statusansicht.
Er ist samt SHA-256-Beleg unter `build/debug-menubar-20261009/user-status-view.png`
und `user-status-view.json` gesichert. Der erneute Versuch der UI-Steuerung,
die nun geöffnete App zu erfassen, endet weiterhin mit `timeoutReached`.
Die fehlenden Bediennachweise wurden deshalb als konkrete manuelle Prüfschritte
an den Nutzer gegeben: zweimal Aktualisieren, Beenden, Neustart und Öffnen
ohne Freigabedialog. Der Nutzer bestätigte danach wörtlich:
**„Alle drei Schritte funktionieren.“** Dies ist ein manueller Nachweis durch
den Nutzer, kein erfolgreicher automatisierter UI-Lauf. Ein neuer Prozess-PID
nach dem Beenden wurde nicht separat erfasst; das Verschwinden des Symbols
und die erfolgreiche Wiederöffnung sind manuell bestätigt. Die Bestätigung
ist zusätzlich unter `build/debug-menubar-20261009/user-ui-confirmation.json`
gesichert.

## Quelltextprüfung und Compound Engineering

Die Composition Root erzeugt genau einen MainActor-StatusModel mit den beiden
injizierbaren Services. Der native PermissionReader liest ausschließlich
`AVCaptureDevice.authorizationStatus(for: .audio)`. Systemaudio bleibt
notVerified, Aufnahme notImplemented. StatusView verdrahtet Aktualisieren und
`NSApplication.shared.terminate(nil)`; kein Capture-/Permission-Request-Pfad
ist vorhanden. Das bestätigt den Quellvertrag, ersetzt jedoch keine UI-Abnahme.

Compound Engineering 3.24.0 wurde während dieser Sitzung lokal verfügbar.
Die Arbeits-/Review-/Compounding-Skill-Anweisungen wurden gelesen; es wurde
kein externer Implementierungs- oder Review-Prozess und keine Cloud-Ausführung
gestartet. Die lokale Konfiguration deaktiviert diese Routen. Die UI-Abnahme
wurde mit Screenshot und manueller Nutzerbestätigung abgeschlossen; es wird
kein erfolgreicher automatisierter UI-Lauf oder formaler ce-code-review-
Receipt behauptet. Die verifizierte Build-Umgebungs-Erkenntnis ist separat
unter [docs/solutions](../solutions/build-errors/2026-10-09-xcode-sandbox-macros.md)
festgehalten; keine neue Verhaltensimplementierung und keine neuen Tests waren
für die unveränderte Übernahme erforderlich.

## Abnahmeentscheidung

**Slice 1 ist lokal abgenommen.** Der native Debug-Build und 9/9 tatsächlich
ausgeführte XCTest-Tests sind bestanden. Prozessstart und Accessory-Modus wurden
nativ geprüft; Symbol und Statusansicht sind im Nutzer-Screenshot nachgewiesen.
Zweimaliges Aktualisieren, Beenden, Neustart und erneutes Öffnen ohne
Freigabedialog sind durch die ausdrückliche Nutzerbestätigung bestanden.

Die optionalen realen Mikrofonzustände „erlaubt“, „abgelehnt“ und „eingeschränkt“
bleiben nicht geprüft; deren Mapping und erneutes Einlesen sind durch injizierte
XCTest-Werte abgedeckt. Es wurde keine OS-Freigabe verändert und kein TCC-Reset
ausgeführt. Ein tatsächlicher Lauf auf macOS 14 wurde nicht durchgeführt.

Die Voraussetzung für eine spätere Slice-2-Planung ist damit erfüllt. Auf den
aktuellen Nutzerauftrag hin endet die Arbeit mit Slice 1; Slice 2 wurde nicht
geplant oder implementiert.
