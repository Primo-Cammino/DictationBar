---
title: "Lokaler Xcode-Build: Agent-Sandbox blockiert Swift-Makros"
date: "2026-10-09"
last_updated: "2026-10-09"
category: build-errors
module: DictationBar
component: tooling
problem_type: build_error
symptoms:
  - "sandbox-exec: sandbox_apply: Operation not permitted"
  - "Debug-Build beendet sich in der Agent-Sandbox mit Exit-Code 65"
root_cause: missing_permission
resolution_type: environment_setup
severity: medium
tags: [xcode, swift-macros, sandbox, native-validation]
---

# Symptom

Der erste lokale Debug-Build mit Xcode 26.3 meldete
`sandbox-exec: sandbox_apply: Operation not permitted` beim Kompilieren der
App und des mit `@Observable` annotierten StatusModel. Exit-Code: 65.
Zusätzlich waren Xcode-Cache- und Simulator-Dienste in der Agent-Sandbox
unzugänglich. Diese Meldungen stammen vom Prüfkontext.

# Lösung und Nachweis

Denselben nativen macOS-Build lokal außerhalb der Agent-Sandbox ausführen.
Projekt, Deploymentziel, Swift-Sprachmodus und Makros unverändert lassen.
Der Wiederholungslauf war erfolgreich (Exit-Code 0). Anschließend liefen
alle neun XCTest-Tests erfolgreich auf macOS 15.7.3 / arm64.

Auch `xcresulttool get test-results summary` benötigte diesen Ausführungskontext,
weil Apple einen `TestReport`-Cache außerhalb des Projektordners anlegt.
Die resultierende Zusammenfassung bestätigt 9 Tests, 9 bestanden, 0 Fehler,
0 übersprungen.

Der erfolgreiche Befehl verwendete unverändert diese Projektparameter:

```bash
xcodebuild -project DictationBar.xcodeproj -scheme DictationBar \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData build
```

Der Unterschied war allein die Ausführung außerhalb der Agent-Sandbox mit
freigegebenem lokalem Xcode-Zugriff. Die Compiler-Erweiterungen dürfen ihre
eigene Sandbox verwenden; die vorherige geschachtelte Sandbox-Ausführung
war im eingeschränkten Agent-Kontext untersagt.

# Wiederverwendung

Build-/Testlogs und Exit-Codes in einem neuen lokalen Prüfverzeichnis sichern.
Sandbox-Fehler getrennt von Swift-Typ-, Link- oder Testfehlern behandeln.
Keine Sicherheitsoptionen des App-Projekts zur Umgehung der Agent-Sandbox ändern.
Keine neuen Plugin- oder Projektgenerator-Abhängigkeiten dafür einführen.

Evidenz: `build/local-validation-20261009/build.log`, `build-native.log`,
`tests.log`, `tests.xcresult`, `test-summary.json` im aktiven Projektordner.
