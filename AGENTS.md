# Lokale Entwicklung von DictationBar

Der aktive Projektordner ist `DictationBar`.
Der frühere Nachbarordner `speeechless_macos` liegt vollständig unter
`.local-backups/consolidation-20261009-edo8hg4j/extracted-slice-1/`.
Er und das erhaltene Slice-1-ZIP sind Ausgangssicherungen. Es gibt nur einen
aktiven Entwicklungsordner; keine Arbeit in Sicherungskopien.

## Arbeitsweise

- Entwicklung, Build, XCTest und App-Prüfung ausschließlich auf dem lokalen Mac.
  Keine Cloud-Ausführung der Entwicklung, Projekt-Uploads, Veröffentlichungen
  oder Remote-Pushes. Die gewählte Mistral-Transkription ist eine Online-
  Produktfunktion mit dem eigenen Key des Nutzers; sie ist kein Cloud-Build
  oder Upload des Projekts.
- Compound Engineering als Ablauf: Anforderungen lesen, kleinen Slice planen,
  umsetzen, passende Tests ausführen, echte App prüfen, Review durchführen und
  Erkenntnisse unter `docs/solutions/` dokumentieren.
- Das lokale Compound-Engineering-Plugin verwenden. Version 3.24.0 wurde während
  der Sitzung installiert und anschließend unter dem Codex-Plugin-Cache gefunden.
  Native macOS-Prüfung verwenden; der iOS-Simulator-Skill ersetzt sie nicht.
- `docs/solutions/` enthält recherchierte Lösungen nach Kategorien mit YAML-
  Frontmatter (`module`, `tags`, `problem_type`); relevant für spätere
  Implementierung, Fehlersuche und Entscheidungen im dokumentierten Bereich.
- Produktquelle: `docs/requirements/2026-10-07-prd-draft.md`. Für Slice 2 gilt
  zusätzlich `docs/plans/2026-10-09-1016-feat-slice2-byok-dictation-plan.md`; bei Konflikten hat der dort bestätigte
  Diktierablauf Vorrang. Importierte Pläne sind historischer Projektkontext. Die aktuelle Nutzeranweisung hat Vorrang,
  insbesondere vor deren früherer Cloud-Ausführung und Abnahme-Zuständigkeit.
- Keine vorhandenen Dateien, Dokumente oder Git-Metadaten löschen. Vor einer
  Zusammenführung vollständige Sicherungen und SHA-256-Inventare erstellen.
  `.local-backups/` und `build/` bleiben lokal und unversioniert.
- Vorhandene Git-Historie erhalten. Im leeren Ausgangsordner und im Slice-1-Export
  wurde keine `.git` gefunden; eine Cloud-Historie oder einen Commit nicht erfinden.
  Das neue lokale Repository begann mit Import-Commit `313d97e` auf
  `feat/local-slice1-validation`; dieser Commit ist keine wiederhergestellte
  Cloud-Historie. Es ist kein Remote eingerichtet.
- Slice 2 erst nach erfolgreichem nativen Build, neun tatsächlich bestandenen
  XCTest-Tests und dokumentierter realer Menüleisten-Abnahme beginnen.
- Keine globalen TCC-Resets und keine automatischen Permission-Requests in Slice 1.
  Nicht reproduzierbare OS-Berechtigungszustände ausdrücklich kennzeichnen.

## Lokale Prüfung

Geteiltes Schema `DictationBar`, macOS-Ziel `platform=macOS,arch=arm64`, Debug,
Derived Data unter `build/DerivedData`. Neue XCTest-Ergebnisbundles immer mit
eigenem Pfad unter `build/` erzeugen. Exit-Codes, Umgebung, Quellstand und echte
Testanzahl festhalten. Xcode-Makros und XCTest können Ausführung außerhalb der
Agent-Sandbox benötigen; das App-Projekt dafür nicht verändern.

Aktueller Prüfbericht: `docs/validation/meeting-recording-2026-10-11.md`.
