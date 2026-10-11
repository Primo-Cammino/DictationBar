---
title: "Schwebendes Statusfenster über Vollbild-Apps, ohne Fokus zu stehlen"
date: "2026-10-11"
last_updated: "2026-10-11"
category: integration-issues
module: DictationBar
component: status-panel
problem_type: integration_issue
symptoms:
  - "Menüleisten-Symbol ist verdeckt; man sieht nicht, ob Aufnahme oder Transkription läuft"
  - "Ein normales Fenster stiehlt dem Zielfeld den Fokus, Einfügen landet falsch"
root_cause: window_level_and_activation
resolution_type: code_fix
severity: medium
tags: [appkit, nspanel, full-screen, focus, status-panel]
---

## Lösung

`NSPanel` mit `[.borderless, .nonactivatingPanel]`, `level = .screenSaver`,
`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, `hidesOnDeactivate = false`,
gezeigt mit `orderFrontRegardless()`. Ein `NSHostingView`, der `acceptsFirstMouse` mit true
beantwortet, sorgt dafür, dass der Stopp-Knopf schon beim ersten Klick wirkt.

Am echten Mac bestätigt (11.10.2026): Das Fenster liegt über einer Vollbild-App, die App behält
ihr Dock-Symbol. `LSUIElement` war nicht nötig (Plan KTD9).

## Fallstricke

- Das Fenster entsteht in `AppDelegate`, nicht im SwiftUI-`SceneBuilder`. Ein `if` dort lässt
  den Compiler abstürzen ([SceneBuilder](../build-errors/2026-10-09-scenebuilder-if-compiler-crash.md)).
- `withObservationTracking`: Alle beobachteten Eigenschaften vor `||` lesen. Kurzschluss-
  Auswertung registriert sonst nur die erste, und Hinweise vergrößern das Fenster nicht (Fix `145bf7a`).
- Ohne angeschlossenen Bildschirm nicht auf `NSScreen.screens[0]` zugreifen.
