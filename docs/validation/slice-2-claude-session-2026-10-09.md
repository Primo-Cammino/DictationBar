# Slice 2: Fortsetzung in Claude Code, 09.10.2026

Fortsetzung der Codex-Übergabe. Umgebung: Apple Silicon, macOS 15.7.3, Xcode 26.3,
Projekt-Deploymentziel macOS 14, Branch `feat/local-slice1-validation`, HEAD `313d97e`
plus uncommittete Slice-2-Änderungen. Alles lokal, keine Pushes oder Uploads.

## Nutzerentscheidungen dieser Sitzung

- **API-Key nicht im Schlüsselbund.** Nach kurzem Zurücknehmen endgültig entschieden: lokale App,
  widerrufbarer Key, Schlüsselbund-Abfragen stören. Ersetzt R10 und die Keychain-Zeile der
  Definition of Done im [Slice-2-Plan](../plans/2026-10-09-1016-feat-slice2-byok-dictation-plan.md).
- **Feste lokale Signierung** mit selbst signiertem Zertifikat statt Ad-hoc (Option 1).
- **Installation in `/Applications`** für die genutzte App.
- History: kopieren statt erneut transkribieren, wo Text vorhanden ist; Finder-Knopf je Eintrag.

## Änderungen

| Bereich | Änderung |
| --- | --- |
| `App/DictationBarApp.swift` | `if` im `SceneBuilder` entfernt (Compiler-Absturz), Hauptfenster immer deklariert |
| `project.pbxproj` | App-Target Debug/Release signiert mit `DictationBar Local Signing` |
| `Services/APIKeyStore.swift`, `App/DictationRuntime.swift` | `FileKeyStore`: `~/Library/Application Support/DictationBar/mistral-api-key`, Datei 0600, Ordner 0700. `NativeKeychainStore` bleibt unverdrahtet im Repo |
| `Services/MistralTranscriptionService.swift`, `UI/SettingsView.swift` | „Key bei Mistral prüfen“: `GET /v1/models` ohne Audio, Redirects abgelehnt, HTTP-Status angezeigt |
| `Services/NativePermissionReader.swift`, `Permissions.swift` | Systemaudio zeigt echten Status der Bildschirm-/Systemaudio-Freigabe (`CGPreflightScreenCaptureAccess`) statt Platzhalter |
| `Services/NativeTextInsertionService.swift` | Fehlendes `AXEnabled` gilt als aktiv; nur ausdrückliches `false` lehnt ab. Ablehnungsgründe als feste Texte im Unified Log (`com.primocammino.DictationBar`, Kategorie `insertion`) |
| `UI/HistoryView.swift` | Native Liste mit Tagesabschnitten, Transkript im Vordergrund, ruhige Metadaten, Kopieren mit Rückmeldung, Finder-Knopf, Kontextmenü |

Nicht unterstützt: Migration des alten Keychain-Eintrags (`com.primocammino.DictationBar.mistral`).
Er bleibt unangetastet; der Key wurde einmal neu in der App eingegeben.

## Läufe

Alle Läufe über `build/review-fixes-progress/run_check.py` (Debug, `build/DerivedData`) bzw. Release nach
`build/DerivedData-install`. Ergebnisordner unter `build/`.

| Lauf | Art | Exit | Ergebnis |
| --- | --- | --- | --- |
| `claude-scene-fix-test-1` | test | 0 | 104/104 bestanden |
| `claude-scene-fix-build-1` | build | 0 | 0 Swift-Warnungen |
| `claude-local-signing-build-1` | build | 0 | signiert mit lokalem Zertifikat |
| `claude-local-signing-test-1` | test | 0 | 104/104 |
| `claude-file-keystore-test-1` / `-build-1` | test / build | 0 / 0 | 105/105 |
| `claude-sysaudio-test-1` | test | 0 | 105/105 |
| `claude-insertion-diag-test-1` | test | 0 | 106/106 |
| `claude-history-ui-test-1`, `claude-history-finder-test-1` | test | 0 | 106/106 |
| `claude-separator-test-1` | test | 0 | 106/106 |
| `claude-install-release-1` bis `-4` | Release-Build | 0 | installiert nach `/Applications`, vorherige Bundles unter `.local-backups/app-install-*` |

Signaturanforderung der installierten App:
`identifier "com.primocammino.DictationBar" and certificate leaf = H"0a74ed143fccd5fb2fac0a26c1fbd1adbf815371"`.

## Native Nachweise (vom Nutzer bedient)

- Einfüge-Freigaben „Bedienungshilfen: erlaubt · Tastaturereignisse: erlaubt“ und Mikrofon „Erlaubt“
  per Screenshot, nach Entfernen des alten Ad-hoc-Eintrags in den Bedienungshilfen.
- Diktat 21:24 mit Datei-Key: von Voxtral transkribiert, Einfügen in TextEdit noch abgelehnt
  („Kein geeignetes Ziel“).
- Diktat 21:35 nach dem `AXEnabled`-Fix: Text in TextEdit eingefügt, vom Nutzer bestätigt; History zeigt
  „Eingefügt“. Unified Log desselben Prozesses: dreimal „AXEnabled fehlt, Feld gilt als aktiv“
  (Snapshot, Fokus-Gegenprüfung, Readback), keine Ablehnung.
- History-Ansicht vom Nutzer per Screenshot gesichtet; uneinheitliche Trennlinien behoben (nicht erneut gesichtet).
- Einfügen vom Nutzer bestätigt in: Microsoft Edge (Adressleiste, Screenshot), Google Docs in Edge,
  iTerm. Edge ersetzt auf Nutzerwunsch Safari als geprüften Browser.

## Noch offen

- Einfügen in Safari (vom Nutzer nicht benötigt); Toggle und Escape bei Fremd-App-Fokus.
- Kein geeignetes Ziel / Fokuswechsel mit Kopieren aus der History; History-Retry ohne Paste.
- Beenden während Aufnahme und HTTP; bewusste Wiederaufnahme.
- Browser-Hinweis, Systemaudio-Freigabe und hörbare Browser-Aufnahme.
- Bluetooth-Headset mit sofortigem Wechsel während der Aufnahme.
- „Key bei Mistral prüfen“ mit echtem Key nicht separat gesichtet (Transkription mit Datei-Key belegt).
