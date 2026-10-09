# DictationBar

Native macOS-Menüleisten-App für persönliches Diktat und Meeting-Aufnahmen. Das [PRD](docs/requirements/2026-10-07-prd-draft.md) beschreibt das Zielprodukt.

Slice 1 enthält das App-Grundgerüst: Mikrofon-Berechtigungsstatus, ausdrücklich ungeprüften Systemaudio-Status, noch unverfügbare Aufnahme, Statusaktualisierung und Beenden. Es gibt noch keine Aufnahme, Dateiablage oder Transkription.

Die Projektdateien wurden in der Linux-Cloud statisch geprüft. **Native Kompilierung, XCTest und echte UI-Abnahme stehen noch aus.** Die [Prüfdokumentation](docs/validation/slice-1.md) hält den Stand fest.

## Auf dem Mac öffnen

Voraussetzung ist vollständiges Xcode als aktives Entwicklerverzeichnis. Für den vorhandenen Mac sind macOS 15.7.3, Apple Silicon und Xcode 26.3 angegeben. Das Projekt verwendet macOS 14.0 als Deploymentziel und Swift im Sprachmodus 5.

Im Terminal in den lokalen Repository-Ordner wechseln und ausführen:

```bash
xcodebuild -version
open DictationBar.xcodeproj
```

In Xcode das Schema **DictationBar** und **My Mac** wählen. **⌘R** startet die App; **⌘U** führt die Tests aus. Das Waveform-Symbol erscheint in der Menüleiste, ohne Dock-Eintrag. Ein Klick öffnet die Statusansicht.

Ein kostenpflichtiges Developer-Team ist für diesen lokalen Build nicht vorgesehen: App und Testbundle verwenden Ad-hoc-Signierung. Kein iOS-Simulator und keine zusätzlichen Projektgeneratoren sind erforderlich.

## Build und Tests protokollieren

Der folgende Block ist für den angegebenen Apple-Silicon-Mac vorgesehen. Er läuft im Repository-Ordner, beendet sich bei Fehlern und erhält für jeden Prüflauf einen eigenen Protokollordner. Das Ergebnis-Bundle wird nicht überschrieben.

```bash
bash <<'SH'
set -euo pipefail
mkdir -p build
CHECK_DIR="$(mktemp -d build/slice1-XXXXXX)"
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

Die Testsuite enthält **9 XCTest-Methoden** in drei Klassen. Die Zusammenfassung muss tatsächlich ausgeführte Tests ohne Fehler zeigen; null Tests sind keine erfolgreiche Abnahme. Die Tests injizieren Mikrofonwerte, ohne macOS-Freigaben zu verändern. Sie ersetzen keine Prüfung der echten Berechtigungsabfrage und Oberfläche.

Danach die [manuellen Prüfschritte](docs/validation/slice-1.md#native-ui-prüfung) durchführen. Bei einem Build- oder Testfehler das entsprechende Protokoll zur Auswertung bereitstellen; die App gilt bis dahin nicht als abgenommen.

## Projekt und Arbeitsweise

- [Plan für Slice 1](docs/plans/2026-10-07-1640-feat-dictationbar-slice-one-plan.md)
- [Architekturentscheidung](docs/decisions/001-native-shell-and-services.md)
- [Prüfstand und offene Abnahme](docs/validation/slice-1.md)

Compound Engineering wird für Planen, Umsetzen, Review und dokumentierte Erkenntnisse verwendet. Die Plugin-Installation gehört zur veröffentlichten Cloud-Umgebung; die App benötigt das Plugin nicht zur Laufzeit. Die vorhandene `.compound-engineering/config.example.yaml` bleibt ein Beispiel, keine aktive Checkout-Konfiguration.

Weitere Slices beginnen erst nach der nativen Abnahme dieses App-Grundgerüsts.
