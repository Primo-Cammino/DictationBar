---
title: "Systemaudio-Freigabe bleibt mit lokalem Zertifikat über Neubauten erhalten"
date: "2026-10-11"
last_updated: "2026-10-11"
category: integration-issues
module: DictationBar
component: screencapturekit
problem_type: integration_issue
symptoms:
  - "Sorge: jede neue Release-Version fragt erneut nach Bildschirm- & Systemaudioaufnahme"
root_cause: unstable_code_signature
resolution_type: environment_setup
severity: medium
tags: [tcc, screencapturekit, screen-recording, codesign, meeting]
---

## Beobachtung

Die Freigabe „Bildschirm- & Systemaudioaufnahme“ für ScreenCaptureKit hängt wie Mikrofon und
Bedienungshilfen an der designierten Anforderung der App. Mit dem lokalen Zertifikat
„DictationBar Local Signing“ (siehe
[Ad-hoc-Signierung](2026-10-09-adhoc-signing-resets-tcc-and-keychain.md)) bleibt diese stabil.

Am 11.10.2026 wurde nach dem Neubau `8c7c32b` die alte App ersetzt und ein Meeting gestartet. macOS
fragte nicht erneut, und die Aufnahme lief sofort.

## Regeln

- Signaturidentität und Bundle-ID nicht ändern, sonst ist die Freigabe weg.
- Die App fragt erst beim Meeting-Start mit `CGPreflightScreenCaptureAccess()`, sonst mit
  `CGRequestScreenCaptureAccess()`. Fehlt die Freigabe, öffnet der Hinweis im Statusfenster
  `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.
- Keine globalen TCC-Resets (AGENTS.md).
