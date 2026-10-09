---
title: "SceneBuilder mit normalem if: Swift-Compiler stürzt ab statt Fehler zu melden"
date: "2026-10-09"
last_updated: "2026-10-09"
category: build-errors
module: DictationBar
component: app-scene
problem_type: build_error
symptoms:
  - "DictationBarApp.swift: error: failed to produce diagnostic for expression; please submit a bug report"
  - "xcodebuild Exit 65, 0 ausgeführte Tests"
root_cause: unsupported_result_builder_construct
resolution_type: code_fix
severity: medium
tags: [swiftui, scenebuilder, compiler, xcode]
---

## Problem

`var body: some Scene` enthielt `if profile == .production { WindowGroup … }`. Laut SDK-Interface ist
`SceneBuilder.buildOptional` für normale Bedingungen gesperrt
(„if statements in a SceneBuilder can only be used with #available clauses“). Der Compiler meldet das
nicht, sondern bricht mit „failed to produce diagnostic“ ab.

## Lösung

Scenes unbedingt deklarieren; Unterschiede zwischen Profilen im Inhalt oder im `AppDelegate` lösen.
Im SceneBuilder nur `if #available` verwenden.
