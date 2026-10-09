---
title: "Ad-hoc-Signierung: Freigaben und Schlüsselbund-Zugriff gehen bei jedem Build verloren"
date: "2026-10-09"
last_updated: "2026-10-09"
category: integration-issues
module: DictationBar
component: code-signing
problem_type: integration_issue
symptoms:
  - "Bedienungshilfen-Schalter steht auf an, App meldet trotzdem 'Bedienungshilfen: fehlen'"
  - "Einfügen liefert nach Neustart mit neuem Build 'Kein geeignetes Ziel'"
  - "Schlüsselbund fragt nach jedem Build erneut nach dem Passwort"
root_cause: unstable_code_signature
resolution_type: environment_setup
severity: high
tags: [tcc, accessibility, keychain, codesign, adhoc, native-validation]
---

## Problem

Mit `CODE_SIGN_IDENTITY = "-"` ist die designierte Anforderung der App ihr `cdhash`. Jeder Build
ändert ihn. TCC (Bedienungshilfen, Mikrofon) und Schlüsselbund-ACLs binden ihre Freigabe an
diese Anforderung. Der Schalter in den Systemeinstellungen bleibt sichtbar an, gilt aber nicht
mehr für die neue Binärdatei.

## Lösung

Lokales, selbst signiertes Code-Signing-Zertifikat „DictationBar Local Signing“ im
Anmelde-Schlüsselbund (LibreSSL `/usr/bin/openssl`, EKU `codeSigning`, Import mit
`-T /usr/bin/codesign`). Vertrauenseinstellung ist für `codesign` und Xcode nicht nötig.
Danach lautet die Anforderung `identifier "com.primocammino.DictationBar" and certificate leaf = H"…"`
und bleibt über Builds und Kopien (`/Applications`) stabil.

Einmalig nach dem Umstieg: alten Eintrag in den Bedienungshilfen mit „−“ entfernen, App neu
hinzufügen; Mikrofon wird erneut angefragt.

## Prüfen

```sh
codesign -d -r- /Applications/DictationBar.app
security find-identity -p codesigning   # zeigt CSSMERR_TP_NOT_TRUSTED, funktioniert trotzdem
```

Nur für die persönliche lokale Nutzung; für Weitergabe oder App Store ungeeignet.
