# DictationBar

Native macOS-Menüleisten-App für persönliches Diktat und Meeting-Aufnahmen. Das [PRD](docs/requirements/2026-10-07-prd-draft.md) beschreibt das Zielprodukt.

Slice 2 implementiert den BYOK-Diktierablauf: ausgewähltes Mikrofon, globale Aufnahme-Taste, dauerhafte WAV, Mistral Voxtral, Einfügen und History. Der native Build und **106/106 XCTest-Tests** bestehen lokal. Am 09.10.2026 hat der Nutzer ein echtes Mikrofon-Diktat mit Voxtral und Einfügen in TextEdit bestätigt ([Prüfbericht](docs/validation/slice-2-claude-session-2026-10-09.md)). **Safari-, Browser-Audio-, Bluetooth- und Beenden-Abnahmen sind noch offen.** Der [Slice-2-Prüfbericht](docs/validation/slice-2-local-2026-10-09.md) trennt Tests von echten Bediennachweisen. Browser-Audiohinweis, bewusste Browser-Aufnahme, sofortiger Bluetooth-Mikrofonwechsel und ein einstellbares Tastenkürzel sind ergänzt; deren echte Geräte-/UI-Abnahme steht noch aus. Das vollständige Code-Review ist abgeschlossen; die belegten Codefehler wurden korrigiert.

Die Dateien aus dem Slice-1-Export sind jetzt im aktiven lokalen Projektordner `DictationBar` zusammengeführt und gesichert. **Slice 1 ist am 09.10.2026 lokal abgenommen: nativer Debug-Build und 9/9 XCTest-Tests bestanden, Menüleisten-Ansicht per Screenshot nachgewiesen, Aktualisieren, Beenden und Neustart vom Nutzer erfolgreich geprüft.** Der [lokale Prüfbericht](docs/validation/slice-1-local-2026-10-09.md) hält Nachweise und Grenzen fest. Der [ursprüngliche Cloud-Prüfstand](docs/validation/slice-1.md) bleibt als historische Dokumentation erhalten.

## Gebaute App direkt starten

Die genutzte App liegt unter `/Applications/DictationBar.app` und hat Dock-Symbol, Hauptfenster
und das Waveform-Symbol in der Menüleiste. Bei voller Menüleiste bleibt sie über Dock oder
Spotlight erreichbar. Der Debug-Build unter `build/DerivedData` dient als Test-Host; der
App-Verweis `DictationBar.app` im Projektordner führt dorthin.

## Einrichten und diktieren

1. Waveform-Symbol öffnen und **Einstellungen …** wählen.
2. Aufnahmeordner und manuelles Mikrofon wählen. Bei aktivierter Bluetooth-Bevorzugung verwendet die App ein verfügbares Bluetooth-Mikrofon automatisch; ein Quellenverlust unterbricht die Aufnahme mit Sicherung.
3. Eigenen Mistral-Key im geschützten Feld speichern. Der Key liegt in `~/Library/Application Support/DictationBar/mistral-api-key`, nur für den eigenen Benutzer lesbar (0600), und kann über die App geändert, entfernt und mit **Key bei Mistral prüfen** gegen Mistral getestet werden. Kein Schlüsselbund, keine Passwortabfrage. Den Key nicht in Chat, Quellcode oder Protokolle kopieren.
4. **Mikrofon freigeben** und **Einfügen erlauben …** verwenden. Wenn macOS eine Einstellung verlangt, DictationBar dort freigeben; den angezeigten Hinweis beachten.
5. Cursor in ein geeignetes Eingabefeld setzen. **Ctrl–Option–Leertaste** ist die Vorgabe. Unter **Einstellungen → Tastenkürzel → Tastenkürzel ändern** lässt sich beispielsweise **Option–R** einstellen. Das konfigurierte Kürzel startet; dasselbe Kürzel oder **Escape** beendet die Aufnahme normal. Start und Stop sind auch im Menü möglich.

Nach dem Stop sichert die App eine PCM16-Mono-WAV mit 48 kHz im gewählten Ordner. Anschließend sendet sie diese Aufnahme mit dem eigenen Key an Mistral (`voxtral-mini-latest`). Ein Ergebnis wird höchstens einmal per Cmd-V in das beim Abschluss geeignete fokussierte Feld eingefügt. Während der Verarbeitung startet kein zweiter Auftrag.

Dieser Einfügeversuch nutzt die Zwischenablage nur kurz: Danach steht der vorherige Inhalt mit allen Formaten wieder darin, außer du hast in der Zwischenzeit selbst etwas kopiert. Das Transkript ist für Clipboard-Verläufe als flüchtig markiert. Sichere Felder, eigene App-Felder, nicht editierbare oder nicht verlässlich lesbare Felder werden abgewiesen. Mit echten Diktaten geprüft: TextEdit, Microsoft Edge (Adressleiste), Google Docs in Edge und iTerm; eine allgemeine Unterstützung aller Programme ist nicht nachgewiesen. Accessibility-Prüfung und Tastenevent sind auf macOS nicht atomar: ein Fokuswechsel unmittelbar nach der letzten Prüfung bleibt eine zeitliche Grenze.

## History, Fehler und Beenden

**History …** zeigt neueste Aufnahmen zuerst mit Datum, Dauer, WAV-Dateiname, Status und Text. **Kopieren** übernimmt nur den Text des gewählten Eintrags; manuelles Einfügen übernimmt der Nutzer. Fehlt ein Ergebnis, startet **Erneut transkribieren** einen bewussten Mistral-Auftrag. Dieses History-Ergebnis wird niemals automatisch eingefügt.

Audio und History bleiben auch nach erfolgreichem Einfügen erhalten. Ein fehlender Key oder Netzwerkfehler löscht keine WAV. Bei einem lokalen Speicherfehler bleibt eine Sicherungsaktion verfügbar; neue Aufnahmen werden bis zur Klärung zurückgehalten. Eine bestätigte Aufnahme ohne gültige Audioframes bleibt als Fehler mit erhaltener Ausgangsdatei sichtbar und sperrt nach gesicherter Fehlermeldung keine weiteren Aufnahmen.

Beim normalen **Beenden** während einer Aufnahme stoppt die App und sichert lokal; sie wartet dabei nicht auf Transkription. Ein lokaler Sicherungsfehler hält die App offen. Beenden während HTTP bricht den Auftrag ab; nach Neustart kann er bewusst aus der History wiederholt werden. Beim Start erfolgen keine Aufnahme, Freigabeabfrage oder Online-Wiederaufnahme.

Ordner und manuelle Geräteauswahl gelten ab der nächsten Aufnahme. Ist Bluetooth-Bevorzugung für die laufende Aufnahme aktiv, wird ein neu verfügbares Bluetooth-Mikrofon sofort übernommen; dieselbe WAV enthält Audio vor und nach dem Wechsel. Die aktive Quelle wird angezeigt. WAVs liegen im ausdrücklich gewählten Ordner; Konfiguration und einzelne History-JSONs liegen unter `~/Library/Application Support/DictationBar/`. Es gibt in Slice 2 keine Lösch- oder Wiedergabefunktion; WAVs lassen sich außerhalb der App prüfen.

## Auf dem Mac öffnen

Voraussetzung ist vollständiges Xcode als aktives Entwicklerverzeichnis. Für den vorhandenen Mac sind macOS 15.7.3, Apple Silicon und Xcode 26.3 angegeben. Das Projekt verwendet macOS 14.0 als Deploymentziel und Swift im Sprachmodus 5.

Im Terminal in den lokalen Repository-Ordner wechseln und ausführen:

```bash
xcodebuild -version
open DictationBar.xcodeproj
```

In Xcode das Schema **DictationBar** und **My Mac** wählen. **⌘R** startet die App; **⌘U** führt die Tests aus. Die App öffnet ihr Hauptfenster mit Dock-Eintrag; das Waveform-Symbol in der Menüleiste öffnet dieselbe Statusansicht.

Ein kostenpflichtiges Developer-Team ist für diesen lokalen Build nicht vorgesehen. Die App wird mit dem lokalen, selbst signierten Zertifikat **DictationBar Local Signing** aus dem Anmelde-Schlüsselbund signiert, damit Bedienungshilfen- und Mikrofonfreigaben über Builds hinweg gültig bleiben ([Hintergrund](docs/solutions/integration-issues/2026-10-09-adhoc-signing-resets-tcc-and-keychain.md)); das Testbundle bleibt ad-hoc signiert.

In den Programme-Ordner installieren (laufende App vorher beenden, vorhandene Version vorher sichern):

```bash
xcodebuild -project DictationBar.xcodeproj -scheme DictationBar -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-install build
ditto build/DerivedData-install/Build/Products/Release/DictationBar.app /Applications/DictationBar.app
``` Kein iOS-Simulator und keine zusätzlichen Projektgeneratoren sind erforderlich.

## Build und Tests protokollieren

Der folgende Block ist für den angegebenen Apple-Silicon-Mac vorgesehen. Er läuft im Repository-Ordner, beendet sich bei Fehlern und erhält für jeden Prüflauf einen eigenen Protokollordner. Das Ergebnis-Bundle wird nicht überschrieben.

```bash
bash <<'SH'
set -euo pipefail
mkdir -p build
CHECK_DIR="$(mktemp -d build/slice2-XXXXXX)"
{
  sw_vers
  uname -m
  xcodebuild -version
  xcrun swift --version
  xcrun --sdk macosx --show-sdk-version
} | tee "$CHECK_DIR/environment.log"

xcodebuild -list -project DictationBar.xcodeproj \
  2>&1 | tee "$CHECK_DIR/schemes.log"

xcodebuild -project DictationBar.xcodeproj -scheme DictationBar \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData build \
  2>&1 | tee "$CHECK_DIR/build.log"

xcodebuild -project DictationBar.xcodeproj -scheme DictationBar \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "$CHECK_DIR/tests.xcresult" test \
  2>&1 | tee "$CHECK_DIR/tests.log"

xcrun xcresulttool get test-results summary \
  --path "$CHECK_DIR/tests.xcresult" \
  | tee "$CHECK_DIR/test-summary.json"

open build/DerivedData/Build/Products/Debug/DictationBar.app
printf 'Prüfprotokolle: %s\n' "$CHECK_DIR"
SH
```

Die Testsuite enthält aktuell **106 XCTest-Methoden**, einschließlich der neun ursprünglichen Slice-1-Tests. Die Zusammenfassung muss tatsächlich ausgeführte Tests ohne Fehler zeigen; null Tests sind keine erfolgreiche Abnahme. Das Test-Schema verwendet `DICTATIONBAR_RUNTIME=testing`: keine produktiven Mikrofon-, Key-Speicher- oder Mistral-Zugriffe beim Start. Transporttests senden ausschließlich neutrale Fixture-Daten an `127.0.0.1`. Die Tests ersetzen keine echte Aufnahme- oder Einfügeprüfung.

Danach die [native Slice-2-Prüfung](docs/validation/slice-2-local-2026-10-09.md#native-prüfung) durchführen. Bei einem Build- oder Testfehler das entsprechende Protokoll zur Auswertung bereitstellen; die App gilt bis dahin nicht als abgenommen.

## Projekt und Arbeitsweise

- [Plan für Slice 1](docs/plans/2026-10-07-1640-feat-dictationbar-slice-one-plan.md)
- [Architekturentscheidung](docs/decisions/001-native-shell-and-services.md)
- [Historischer Cloud-Prüfstand](docs/validation/slice-1.md)
- [Lokale Zusammenführung](docs/plans/2026-10-09-local-consolidation-validation-plan.md)
- [Native Prüfung vom 09.10.2026](docs/validation/slice-1-local-2026-10-09.md)

Compound Engineering wird lokal für Planen, Umsetzen, Review und dokumentierte Erkenntnisse verwendet. Das Plugin 3.24.0 wurde während der lokalen Sitzung verfügbar; die App benötigt es nicht zur Laufzeit. [AGENTS.md](AGENTS.md) beschreibt den lokalen Ablauf. Die lokale CE-Konfiguration schaltet externe Implementierungs- und Review-Routen aus. Die im Cloud-README erwähnte Beispielkonfiguration war im gelieferten ZIP nicht enthalten.

Beide gelieferten Ordner enthielten keine Git-Metadaten. Das neue lokale Repository beginnt mit dem Slice-1-Import auf `feat/local-slice1-validation`; ein Remote ist nicht eingerichtet. Ausgangsstände samt ZIP liegen unter `.local-backups/consolidation-20261009-edo8hg4j/`. Der zweite, früher daneben liegende Projektordner wurde vollständig nach `.local-backups/consolidation-20261009-edo8hg4j/extracted-slice-1/` verschoben und erneut per SHA-256 geprüft. Unter `dev/projects` bleibt damit nur `spechless_macos` als Arbeitsordner dieses Projekts. Das ursprüngliche ZIP bleibt ebenfalls erhalten; keine Datei wurde gelöscht.

Die lokale Slice-1-Abnahme ist abgeschlossen. Der geprüfte [technische Plan für Slice 2](docs/plans/2026-10-09-1016-feat-slice2-byok-dictation-plan.md) beschreibt den vollständigen BYOK-Diktierablauf mit Voxtral und History in acht Umsetzungseinheiten. U1–U7 sind umgesetzt und automatisiert geprüft. U8 ist dokumentiert, aber die reale native Abnahme bleibt offen; Slice 2 ist damit noch nicht abgenommen.


## Neue Anforderungen vom 09.10.2026

Der Nutzer verlangt zusätzlich einen schwebenden Aufnahmehinweis bei Browser-Audio und die automatische Verwendung seines Bluetooth-Kopfhörermikrofons. [PRD, Abschnitt 11](docs/requirements/2026-10-07-prd-draft.md#11-ergänzungen-browser-aufnahmehinweis-und-bluetooth-mikrofon) hält dies fest. Die Ergänzungen sind lokal implementiert und Bestandteil der 104 bestandenen Tests. Bei mehreren Headsets gilt: gewähltes Bluetooth-Mikrofon, danach macOS-Standard-Bluetooth-Mikrofon, danach stabile Geräte-ID. Die automatische Bevorzugung lässt sich ausschalten. Ein fehlgeschlagener Wechsel erhält die ursprüngliche Quelle, sofern verfügbar; Geräteverlust sichert und unterbricht.

Ab macOS 14.2 liest der Browser-Hinweis Metadaten aktiver Browser-Audiostreams. Er ist keine Meeting-Erkennung und kein Lautstärkennachweis; native Browser-Zuordnung und Fehlalarme sind noch zu prüfen. Schließen unterdrückt den Hinweis bis zum Ende dieser Audio-Episode. „Aufnehmen“ fordert bei Bedarf gezielt die macOS-Freigabe an und erfasst Audio des gewählten Browser-Prozesses inklusive anderer Tabs. Die WAV wird lokal in der History gespeichert; es gibt keinen automatischen Upload oder Paste. Eine bewusste History-Transkription nutzt weiterhin BYOK.

Das vollständige Compound-Code-Review ist nach Wiederaufnahme abgeschlossen. Drei Codefehler wurden lokal korrigiert; direkte Browser-Treibertests ergänzen die zuvor nur simulierte Pipeline. Der finale Build wurde regulär neu gestartet (PID 85520). Das belegt keinen Bediennachweis. [Review-Korrekturen und Nachweise](docs/validation/slice-2-review-fixes-2026-10-09.md). Details: [Erweiterungsprüfung](docs/validation/slice-2-browser-bluetooth-shortcut-2026-10-09.md).
