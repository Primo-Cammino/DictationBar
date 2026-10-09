# Slice 1: Prüfstand

Datum: 2026-10-07. **Implementierung zur nativen Prüfung vorbereitet; Slice noch nicht abgenommen.**

Geprüfter Umfang: App- und Testdateien dieses Arbeitsstands auf `feat/dictationbar-slice-one`, bezogen auf den [Slice-1-Plan](../plans/2026-10-07-1640-feat-dictationbar-slice-one-plan.md). Vor jedem nativen Lauf den geprüften Commit und gegebenenfalls den lokalen Diff festhalten.

## Cloud-Prüfungen

Die Implementierung entstand auf Debian/Linux ohne Swift-Compiler, Xcode oder Apple-SDKs.

| Check | Ergebnis | Aussagegrenze |
|---|---|---|
| OpenStep-Parser für `project.pbxproj` | Bestanden | Projektdatei ist parsebar; keine Xcode-Buildbestätigung |
| Projektobjekte, Zielabhängigkeit und Quelldateien | Bestanden | Alle referenzierten Objekte und Quellen existieren; 6 App- und 3 Testquelldateien den Targets zugeordnet |
| Geteiltes Schema als XML | Bestanden | Referenziert beide Targets und ein aktiviertes XCTest-Testable |
| `Info.plist` als Property List | Bestanden | `LSUIElement` ist aktiviert |
| Swift-Grammatik mit Tree-sitter | Bestanden | 9 Dateien ohne Grammatikfehler; keine Typprüfung oder Kompilierung |
| Quelltextprüfung auf aktive Capture-/Request-Pfade | Bestanden | Keine Aufnahme- oder Freigabeanforderung im App-Quelltext; einzige OS-Abfrage ist passiver Mikrofonstatus |
| Native Builds, XCTest und UI | Nicht ausgeführt | Linux stellt die benötigte macOS-Laufzeit nicht bereit |

Die Parser wurden ausschließlich unter `/tmp` als Prüfwerkzeuge installiert; sie sind keine Projektabhängigkeiten.

## Automatisierte native Tests

Die XCTest-Dateien wurden vor der jeweiligen Service-/Modellimplementierung geschrieben. Ein erwarteter roter Testlauf wurde **nicht beobachtet**, weil der native Runner fehlte. Auch ein grüner XCTest-Lauf wird hier nicht behauptet.

| Testklasse | Methoden | Vertragsnachweis | Laufstatus |
|---|---:|---|---|
| PermissionMappingTests | 4 | Mikrofonwerte einschließlich unbekannter Werte, ehrliche Systemaudio-Anzeige, erneut gelesener Status; R4/R5, AE2 | Offen |
| AudioAvailabilityTests | 1 | Noch nicht implementierte Aufnahme mit explizitem Grund; R3 | Offen |
| StatusModelTests | 4 | Initialisierung, externe Statusänderung, wiederholte Aktualisierung, unterscheidbare Ablehnung/Einschränkung; R3–R6, AE2/AE3 | Offen |

Diese Tests injizieren Statuswerte. Die echte OS-Probe sowie die App-Komposition benötigen die folgende Geräteprüfung.

## Native UI-Prüfung

Bekannter Ziel-Mac laut Nutzer: macOS 15.7.3, `arm64`, ausgewähltes Xcode 26.3, Build 17C529. Build-, Test- und Startbefehle stehen im [README](../../README.md#build-und-tests-protokollieren).

Vor dem Lauf bereits laufende DictationBar-Instanzen über „Beenden“ schließen. Die feste Bundle-ID beibehalten; keine globalen TCC-Resets ausführen. Die App löst in Slice 1 absichtlich keine Freigabeanforderung aus. Auf einem frischen System muss ein erlaubter Mikrofonzustand deshalb nicht reproduzierbar sein.

| Schritt | Erwartung | Beobachtung |
|---|---|---|
| Schema auflisten, Debug bauen | Schema/Targets vorhanden, Build erfolgreich, App-Bundle erzeugt; R7 | Offen |
| XCTest ausführen | 9 Tests tatsächlich ausgeführt, keine Fehler; R7 | Offen |
| App-Bundle starten | Menüleisten-Symbol, kein Dock-Eintrag, kein Freigabedialog; AE1 | Offen |
| Symbol anklicken | Statusoberfläche mit Mikrofon, Systemaudio, Aufnahme und beiden Bedienaktionen; AE1 | Offen |
| Statusanzeige lesen | Mikrofon entspricht dem beobachtbaren OS-Status; Systemaudio „Noch nicht geprüft“, Aufnahme „Noch nicht verfügbar“; AE2 | Offen |
| Mehrfach öffnen/schließen und aktualisieren | Keine Aufnahme, kein Freigabedialog; R4 | Offen |
| Falls die App in den Systemeinstellungen bereits aufgeführt ist: Mikrofonfreigabe extern ändern und aktualisieren | Sichtbarer Status entspricht der passiven OS-Abfrage; AE3. Falls macOS einen Neustart verlangt, diesen dokumentieren und neu prüfen | Offen; nur soweit reproduzierbar |
| „Beenden“ auswählen | Prozess und Symbol verschwinden; AE4 | Offen |
| Erneut aus dem App-Bundle starten | Symbol und Oberfläche funktionieren weiterhin ohne Dialog; AE4 | Offen |

Ein Screenshot der geöffneten Statusansicht und die Beobachtung zu Launch/Beenden werden nach dem tatsächlichen Lauf ergänzt. Ein Quelltext-Review ersetzt diese Evidenz nicht.

Unzugängliche Mikrofonzustände bleiben als „nicht geprüft“ dokumentiert. Der vorhandene Mac kann keinen tatsächlichen Lauf auf macOS 14 nachweisen; dieser zusätzliche Lauf ist optional.

## Abnahme

R1–R8 und AE1–AE4 sind erst nach erfolgreichem Pflicht-Build, tatsächlich ausgeführtem XCTest und realer UI-Prüfung abgenommen. Bis dahin bleiben U1–U4 in ihrer nativen Verifikation offen. Folgeslices beginnen gemäß PRD §8 erst nach dieser Abnahme.
