---
title: "TextEdit liefert kein AXEnabled: strenge Zielprüfung lehnt jedes Einfügen ab"
date: "2026-10-09"
last_updated: "2026-10-09"
category: integration-issues
module: DictationBar
component: text-insertion
problem_type: integration_issue
symptoms:
  - "History: 'Kein geeignetes Ziel – Text kopierbar' trotz erlaubter Bedienungshilfen"
  - "insertion: unavailable bei stabilem Caret in TextEdit"
root_cause: missing_ax_attribute
resolution_type: code_fix
severity: high
tags: [accessibility, axuielement, textedit, insertion, diagnostics]
---

## Problem

`AXTargetReader.snapshot` verlangte `kAXEnabledAttribute as? Bool == true`. TextEdits `AXTextArea`
(NSTextView) stellt `AXEnabled` gar nicht bereit. Damit war jedes TextEdit-Ziel „ungeeignet“.

## Lösung

Nur ein ausdrückliches `false` gilt als deaktiviert. Rolle, Passwortfeld, setzbarer `AXValue`,
lesbare Auswahl, stabiler Fokus und Readback bleiben unverändert streng.
Test: `NativeFocusTests.testMissingEnabledAttributeIsEligibleButExplicitlyDisabledIsNot`.

## Diagnose

Jede Ablehnung schreibt einen festen Grund ins Unified Log, nie Feldinhalte oder Titel:

```sh
/usr/bin/log show --last 30m --style compact --predicate 'subsystem == "com.primocammino.DictationBar"'
```

In zsh ist `log` ein Builtin; immer `/usr/bin/log` verwenden, sonst kommt keine oder eine
irreführende Ausgabe. Einträge aus Testläufen stammen von Test-Host-PIDs und sind keine Nutzerdiktate.
