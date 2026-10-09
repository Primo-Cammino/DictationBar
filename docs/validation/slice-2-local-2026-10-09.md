# Slice 2: lokale Umsetzung und Prüfstand vom 09.10.2026

**Aktueller Stand: nativer Build erfolgreich, 104/104 XCTest-Tests bestanden. Vollständiges Code-Review abgeschlossen und Codefehler korrigiert; echte Diktier-/Geräte-Abnahme offen. Slice 2 ist nicht abgenommen.**

Die folgenden 69-Test-Nachweise bleiben als vorheriger Stand erhalten. Den aktuellen Quellstand dokumentiert [Erweiterungsprüfung](slice-2-browser-bluetooth-shortcut-2026-10-09.md).

## Umgebung und Quellstand

- Aktives Projekt: `DictationBar`; kein zweiter Arbeitsordner.
- macOS 15.7.3 (24G419), Apple Silicon arm64, Xcode 26.3 (17C529), Swift 6.2.4 im Projekt-Sprachmodus 5; Deploymentziel macOS 14.
- Branch `feat/local-slice1-validation`, Ausgangs-HEAD `313d97e`. Slice-2-Änderungen liegen lokal und uncommitted vor; kein Remote, Push oder Projekt-Upload.
- Plan: [Slice 2](../plans/2026-10-09-1016-feat-slice2-byok-dictation-plan.md), unverändert als Autorität. U1–U7 implementiert; U8 dokumentiert, reale Abnahme noch ausstehend.
- Vor der Umsetzung: `.local-backups/slice2-implementation-vtby1q_v/`; weitere Originale und Zusammenführungs-Backups erhalten. Review-Korrekturen haben zusätzlich ein `pre-apply.tar.gz` im lokalen Review-Evidenzordner.
- Exakte Hashes der geprüften App-/Test-/Projektdateien: `build/slice2-final-tests-20261009/source-sha256.json`. Git-Metadaten und vorhandene Dokumente wurden erhalten.

## Build und XCTest

```sh
xcodebuild -project DictationBar.xcodeproj -scheme DictationBar -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build
xcodebuild -project DictationBar.xcodeproj -scheme DictationBar -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -resultBundlePath build/slice2-final-tests-20261009/tests.xcresult test
xcrun xcresulttool get test-results summary --path build/slice2-final-tests-20261009/tests.xcresult
```

| Prüfung | Ergebnis | Lokale Evidenz |
|---|---|---|
| Separater finaler Debug-Build | Exit 0, BUILD SUCCEEDED | `build/slice2-final-build-20261009/build.log`, `build.exitcode` |
| Vollständige finale XCTest-Suite | Exit 0; 69 bestanden, 0 fehlgeschlagen, 0 übersprungen | `build/slice2-final-tests-20261009/tests.log`, `tests.exitcode`, `tests.xcresult`, `test-summary.json` |
| HTTP-Transport gezielt | Exit 0; 3 Tests bestanden | `build/slice2-http-fixed-20261009/` |
| Vor dem Review | Exit 0; 56 Tests bestanden | `build/slice2-review-tests-20261009/` |
| Erster Review-Fix-Lauf | Exit 65; 66 Tests, 2 Fehler in neuer HTTP-Fixture | `build/slice2-review-fixes-20261009/` |
| Erste HTTP-Fixture-Korrektur | Exit 65; 3 Tests, 1 Fehler in Fixture | `build/slice2-http-fix-20261009/` |

Die Fixture schloss anfangs unvollständige HTTP-Antworten und erzeugte einen TCP-Abbruch, bevor die Antwortgrößenprüfung griff. Der lokale Server liest jetzt den Upload und liefert eine vollständige deklarierte Antwort beziehungsweise korrekt gerahmte Chunks. Beide Größenfälle bestehen. Fehlgeschlagene Läufe bleiben als Evidenz erhalten.

Der separate Build wurde nach dem finalen Testlauf ausgeführt. Im XCTest-Build steht eine Xcode-Meldung zur übersprungenen AppIntents-Metadatenextraktion, da keine AppIntents-Abhängigkeit vorhanden ist. Das Projekt verwendet keine AppIntents-Funktion.

Tests werden über das geteilte Test-Schema mit `DICTATIONBAR_RUNTIME=testing` ausgeführt. Die neun ursprünglichen Slice-1-Tests bleiben enthalten. Kein produktiver Mikrofon-, Keychain- oder Mistral-Auftrag wurde durch XCTest gestartet. Die native HTTP-Fixture bindet ausschließlich an `127.0.0.1` und verwendet synthetische Daten und einen synthetischen Header. Xcode/XCTest und xcresulttool wurden mit dem nötigen lokalen Sandbox-Zugriff ausgeführt; die Target-Sicherheit wurde dafür nicht verändert.

Die Suite prüft unter anderem Journal vor Capture, kollisionsfreie Dateien, Wiederherstellung, WAV-Validierung, Mikrofon- und Ordnersnapshots, Shortcut-Wiederholungen, Escape als normalen Stop, passive Initialisierung, Keychain-Add/Update/Remove, Multipart, HTTP-Weiterleitungsverweigerung, Antwortgrenzen, Abbruch, Busy-Gate, dauerhaften Text vor Paste, höchstens einen Paste, Fokusänderung während AX-Abfragen, UTF-16-Auswahl sowie Beenden während Capture, HTTP, lokaler Textsicherung und Einfügen. Diese Tests ersetzen keine echte Geräte- oder Ziel-App-Prüfung.

## Lokaler Code-Review

[Review-Bericht](slice-2-code-review-2026-10-09.md): acht Code-Reviewer, ein Learnings-Reviewer und eine unabhängige Validierungsrunde. Externe Cross-Model-Routen waren gemäß Projektkonfiguration ausgeschaltet. Sechs belegte Punkte wurden lokal korrigiert und mit dem finalen Testlauf geprüft:

1. Fokus nach AX-Attributabfragen erneut prüfen und vor dem Tastenevent einen geänderten Vordergrundprozess abweisen.
2. Bestätigt gestoppte Aufnahme ohne gültige Audioframes als Fehler sichern; Originaldatei erhalten und keine dauerhafte Start-/Quit-Sperre erzeugen.
3. Temporäre Multipart-Datei und Handles auch bei fehlender Eingabedatei aufräumen.
4. Erfolgreiche Staging-Reservierung dauerhaft markieren; bei vorheriger Dateikollision keine fremde WAV nach Neustart verschieben.
5. Native HTTP-Abbruch-, Weiterleitungs- und Antwortgrößenpfade sowie Multipart-Aufräumen testen.
6. Änderung eines bestehenden Keychain-Items statt nur Neuanlage testen.

Die Fixes betreffen Timing, Beenden und Dateizuordnung. Grüne Tests belegen die modellierten Fälle; reale macOS-Ereignisse, Audio und Mistral stehen noch zur Prüfung an. Ein Fokuswechsel nach der letzten Prüfung und vor der Eventzustellung ist weiterhin eine macOS-Grenze des bestätigten Ansatzes.

## Native Prüfung

Die korrigierte App wurde nach regulärem Beenden der vorherigen Instanz gestartet. `open` war erfolgreich; der gestartete Prozess war PID 66088 unter `build/DerivedData/Build/Products/Debug/DictationBar.app/Contents/MacOS/DictationBar`. Das belegt den Prozessstart, keine erfolgreiche Aufnahme oder sichtbare UI-Abnahme.

Die native UI-Steuerung antwortete bei drei `getApp`-Versuchen mit `timeoutReached`. Der Ersatzweg über System Events scheiterte an fehlender Hilfszugriffs-Berechtigung (`-1728`). Es wurden keine globalen TCC-Resets durchgeführt. Die konkrete Einrichtung und der erste TextEdit-Test wurden dem Nutzer gestellt; eine Bestätigung des Diktierdurchlaufs liegt noch nicht vor. Der Nutzer hat anschließend gewählten Ordner, Mikrofon und eingegebenen Mistral-Key bestätigt. Der Settings-Screenshot zeigt die ausgewählte MacBook-Pro-Mikrofonquelle und den WAV-Ordner; erfolgreiche Freigaben, Keychain-Speicherung und Audio/Transkription/Einfügen sind damit noch nicht nachgewiesen.

| Szenario aus dem Plan | Native Evidenz / Stand |
|---|---|
| Start/Toggle, gewähltes Mikrofon, hörbare PCM-WAV und ein Paste | Offen |
| Escape: normaler Stop; außerhalb Capture unverändert | Offen |
| Fokus von TextEdit zu Safari-Textarea vor Ergebnis wechseln | Offen |
| Markierten Text mit Umlaut/Emoji ersetzen, einmal Paste, Undo | Offen |
| Kein Ziel: History und explizites Kopieren | Offen |
| Fehlende Einfügefreigabe / ungeeignetes Feld | Offen |
| Busy: wiederholtes Shortcut während Speicherung/HTTP | Offen |
| Fehlender/falscher Key, unterbrochenes Netz, bewusstes Retry | Offen |
| History-Retry ohne automatisches Einfügen | Offen |
| Quit während Capture und HTTP, Neustart, WAV/History erhalten | Offen; nur regulärer Instanzwechsel und Prozessstart nachgewiesen |
| Kontrollierter Schreibfehler hält App offen | Offen |
| Verlust eines externen Mikrofons | Offen; verfügbare Hardware noch nicht festgestellt |
| Passiver Startup und echte Mikrofon-Freigabe/Verweigerung | Offen; bisher nur isoliert automatisiert geprüft |
| Ordnerwechsel während Aufnahme und nach Neustart | Offen |
| Key ändern/entfernen, Neustart, keine Geheimnisse in Artefakten | Echte Keychain-Bedienung offen; Test-Spy-Add/Update/Remove geprüft |
| Clipboard enthält anschließend Transkript / ausgewählter History-Text | Offen |

macOS-14-Laufzeit wurde nicht geprüft. Der Build auf macOS 15 mit Deploymentziel 14 ist keine macOS-14-Laufzeitabnahme. TextEdit und Safari sind vorgesehene Prüffelder, bisher keine nativ bestätigten Ziel-Apps. Es wurde durch den Agenten noch kein Live-Mistral-Diktat ausgelöst, kein API-Key gelesen und kein tatsächliches Transkript in Logs oder Screenshots übernommen. Die versionierbare Dateiliste enthält keine Audiodatei.

### Nächste Bedienprüfung

1. Ordner, Mikrofon und eingegebener Key sind vom Nutzer bestätigt. Noch prüfen: erfolgreiche Key-Speicherung sowie Mikrofon- und Einfügefreigaben. Der Screenshot zeigt aktuell das MacBook-Pro-Mikrofon. Automatischer Bluetooth-Wechsel ist inzwischen implementiert und automatisiert geprüft; reale Geräteprüfung fehlt.
2. Leeres TextEdit-Dokument fokussieren. **Ctrl–Option–Leertaste**, „Das ist mein erster Test.“ sprechen, dasselbe Kürzel erneut drücken. Genau eine Einfügung und den History-Eintrag prüfen. Die WAV anschließend außerhalb der App anhören.
3. Danach Escape, Wechsel zu Safari, kein geeignetes Ziel, History-Kopieren/Retry und Beenden während Aufnahme/HTTP mit kurzen neutralen Testaufnahmen prüfen. Ergebnisse je Matrixzeile ergänzen.

## Abnahmeentscheidung

Build und automatisierte Tests sind bestanden. Die Kernnachweise mit echtem Audio, Voxtral, Paste, Escape, Fokuswechsel, History und Quit/Neustart fehlen noch. Slice 2 bleibt deshalb **nicht abgenommen**; das Gesamtziel wird nicht als vollständig erledigt markiert.


## Neue Produktanforderungen nach der Umsetzung

Browser-Audiohinweis und automatische Bluetooth-Mikrofonwahl sind im [PRD, Abschnitt 11](../requirements/2026-10-07-prd-draft.md#11-ergänzungen-browser-aufnahmehinweis-und-bluetooth-mikrofon) erfasst. Es handelt sich um neue Anforderungen, nicht um bestandene Tests oder unveränderte Zusagen des bisher geprüften Codes. Der Nutzer hat den sofortigen Bluetooth-Mikrofonwechsel auch während laufender Aufnahme bestätigt (BT3); vorhandenes Audio muss erhalten bleiben. Die Erweiterung ist inzwischen implementiert. 104 Tests und nativer Build bestehen; das vollständige Review ist abgeschlossen, Codefehler sind korrigiert. Reale Prüfung bleibt offen; siehe [Review-Korrekturen](slice-2-review-fixes-2026-10-09.md).
