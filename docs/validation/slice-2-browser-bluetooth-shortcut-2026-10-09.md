# Slice 2: Browser, Bluetooth und Shortcut – lokaler Prüfstand

**Finaler Build erfolgreich; 104 Tests bestanden, 0 Fehler, 0 übersprungen. Vollständiges Code-Review abgeschlossen, Codefehler korrigiert; reale Abnahme offen.**

Neuester Nachweis: [Review-Korrekturen](slice-2-review-fixes-2026-10-09.md). Die unten beschriebenen 85 Tests sind der historische Stand vor diesen Korrekturen.

## Umfang und Sicherung

Arbeitsordner `DictationBar`, Branch `feat/local-slice1-validation`, HEAD `313d97e`; Änderungen bleiben lokal und uncommitted. Sicherung vor Umsetzung: `.local-backups/browser-bluetooth-implementation-5_0tf2md/before.tar.gz`, Git-Status und SHA256-Inventar daneben. Vorhandene Originale, Git-Metadaten und Dokumente bleiben erhalten. Kein Remote, Push oder externe Review-/Implementierungsroute.

Implementiert: passive Browser-Output-Metadaten-Erkennung ab macOS 14.2 und schwebender Hinweis; explizite Browser-Audioaufnahme via ScreenCaptureKit, lokale WAV/History ohne automatischen Mistral-Auftrag oder Paste; automatische Bluetooth-Auswahl und sofortiger laufender Quellenwechsel; gemeinsame PCM16-Mono48k-Schreibstrecke; konfigurierbares globales Tastenkürzel in Einstellungen, beispielsweise Option-R. Escape bleibt Stop. Quelle und konfiguriertes Kürzel erscheinen im Menü. Neue optionale Konfigurationsfelder behalten alte JSONs bei; History enthält eine optionale Browser-Quellbezeichnung.

## Nachweise

| Prüfung | Ergebnis | Evidenz |
|---|---|---|
| API-Proof vor Produktionsänderung | Compile-Red: fehlende Switch-APIs | `build/browser-bluetooth-red/` |
| Erster Gesamt-Testlauf | 85 Tests; 1 WAV-Dauerfehler | `build/browser-bluetooth-first/` |
| Zweiter Testversuch | Buildfehler importierter Carbon-Typ | `build/browser-bluetooth-second/` |
| Dritter Gesamt-Testlauf | Exit0, 85 bestanden, 0 Fehler/Skips | `build/browser-bluetooth-third/tests.log`, `tests.xcresult`, `test-summary.json` |
| Separater nativer Debug-Build | Exit0, BUILD SUCCEEDED | `build/browser-bluetooth-native/build.log`, `build.exitcode` |
| Quellinventar | SHA256 aller App-/Test-/Projektdateien | `build/browser-bluetooth-third/source-sha256.json` |
| Whitespace | `git diff --check HEAD` erfolgreich | lokaler Command-Exit0 |
| Regulärer Neustart | alte PID66088 regulär beendet, neu PID76290 | `open` Exit0 und Prozesspfad bestätigt |

85 Tests umfassen die vorherigen 69 plus 6 echte AVAudioConverter/WAV-Tests, 5 Routing-/Browser-Pipeline-Tests, 1 RecordingService-Switch-Test und 4 Shortcut-Modell-/Event-Tests. PCM-Test bestätigt unterschiedliche 48k/16k-Segmente und beide Inhalte in einer WAV. Der zuerst beobachtete 2-ms-Resampler-EOS-Anhang wurde auf Quellendauer begrenzt, ohne die Assertion zu lockern. Carbon-Layout-Typ wurde auf die tatsächliche Swift-Importform korrigiert. Verbleibende Xcode-Meldung: AppIntents-Metadatenextraktion mangels Abhängigkeit ausgelassen. Keine Swift-Compilerwarnung im finalen Lauf. Kein Lint-Runner konfiguriert; Compiler und Whitespace-Check ausgeführt.

XCTest verwendet isolierte Test-Komposition: keine produktiven Mikrofon-/Browser-Aufnahmen, Keychain-Abfragen oder Mistral-Aufträge. Die PCM-Konversion läuft real auf synthetischen Puffern; Mikrofonwechsel und Browser-Pipeline benutzen kontrollierte Doubles und beweisen keine Geräte-/ScreenCaptureKit-Laufzeitabnahme.

## Review

`ce-work` und `ce-simplify-code` angewendet. Die erste Simplify-Runde lieferte sechs angewendete Verbesserungen; der damalige Lauf mit 85 Tests bleibt erhalten.

`ce-code-review mode:agent base:HEAD` wurde nach dem anfänglichen Nutzungslimit im selben Run erfolgreich wiederaufgenommen: `/private/tmp/compound-engineering-501/ce-code-review/20261009-150419-836c3b5a`. Zehn Reviewer und ein unabhängiger Validator wurden terminal gesammelt; Receipt `status: complete`, Verdict vor Korrekturen „Not ready“. Die anfänglichen Failed-Receipts bleiben erhalten. Kein externer Peer.

Vier bestätigte Findings wurden in zwei seriellen Dateigruppen bearbeitet: Browser-Stopp/Driver-Tests und Model-Registrierung/Reparatur. Findings #1–#3 sind korrigiert und geprüft. #4 hat jetzt acht direkte Produktionsdriver-Tests mit realem PCM-Writer; sein echter Browser-Aufnahmenachweis bleibt offen. Eine zweite Simplify-Runde auf dem Fix-Diff hat eine deterministische Testverbesserung angewendet. Final 104/104 Tests und separater nativer Build erfolgreich, keine Swift-Compilerwarnung. Details und bewusst verworfene Vereinfachung im [Fix-Bericht](slice-2-review-fixes-2026-10-09.md).

## Noch echte Bediennachweise

1. **Tastenkürzel:** Einstellungen öffnen, „Tastenkürzel ändern“, Option-R drücken. In neutralem TextEdit-Feld starten/stoppen; Escape und Konfliktmeldung prüfen. Neustart muss gewähltes Kürzel behalten.
2. **Diktat:** echte Mikrofonfreigabe, hörbare WAV, BYOK-Voxtral-Text, genau eine Einfügung und History/Kopieren. Eingetragener Key und ausgewählter Ordner sind Nutzerangaben, keine Erfolgsnachweise.
3. **Bluetooth:** erst MacBook-Aufnahme, Headset verbinden, angezeigte und hörbare Quelle wechseln ohne Stop/Start; WAV enthält beide Abschnitte. Verlust sichert und unterbricht. Mehrere Geräte und Opt-out prüfen.
4. **Browser:** Audio im Browser abspielen. Hinweis sichtbar; Schließen nimmt nichts auf. Neue Episode und „Aufnehmen“: gezielte OS-Freigabe, hörbare Browser-WAV in History, kein automatischer Upload/Paste. Andere Tabs sind Teil der Browser-Quelle. Metadaten-Erkennung ist kein Amplituden-/Meeting-Nachweis; Browser-Helper-Zuordnung, stille aktive Streams und echte Erkennung müssen geprüft werden.
5. Übrige Matrix aus dem [bestehenden Slice2-Bericht](slice-2-local-2026-10-09.md#native-prüfung) abschließen: Fokuswechsel, Busy, Fehler/Retry und sichere Terminierung.

Der UI-Zugriff wurde nach der Kontingent-Erholung und nach Neustart erneut versucht: `cua.getApp` für die laufende DictationBar endet weiterhin mit `timeoutReached`; Finder lässt sich über dasselbe Werkzeug lesen. Die App läuft laut Prozesspfad als PID85520. Das ist eine konkrete Grenze der automatisierten Menüleisten-Prüfung, kein aktueller Kontingentfehler. Kein TCC-Reset und kein API-Key gelesen. Die manuelle Frage nach dem echten TextEdit-Diktiernachweis ist gestellt; eine Antwort steht aus. Prozessstart ersetzt keine sichtbare Abnahme. macOS14-Laufzeit bleibt ungeprüft.

## Entscheidung

Lokal implementiert und automatisiert geprüft; **Slice2 nicht abgenommen**. Das vollständige Review ist abgeschlossen; die realen Bedien-/Audio-/Voxtral-Nachweise fehlen. Kein Commit/Push/PR vorgenommen; Ziel bleibt unvollständig und wird nicht als erreicht markiert.
