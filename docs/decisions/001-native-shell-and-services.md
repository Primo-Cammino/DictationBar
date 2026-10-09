# ADR 001: Native Menüleisten-App und passive Statusdienste

Datum: 2026-10-07. Implementiert für Slice 1; native Abnahme offen.

Das Repository hatte kein App-Projekt. Slice 1 benötigt eine startbare Menüleisten-App und ehrliche Berechtigungsanzeigen, ohne Aufnahme oder automatische Freigabedialoge. Grundlage sind PRD §§4–7 und die Entscheidungen KTD1–KTD5 im [Plan](../plans/2026-10-07-1640-feat-dictationbar-slice-one-plan.md).

## Entscheidung

Ein eingechecktes `DictationBar.xcodeproj` enthält das macOS-App-Target, ein gehostetes XCTest-Target und das geteilte Schema `DictationBar`. Ad-hoc-Signierung und die feste Bundle-ID `com.primocammino.DictationBar` unterstützen lokale Prüfungen ohne bezahltes Developer-Team. Deploymentziel ist macOS 14.0. Ein paralleles SwiftPM-Projekt oder ein Projektgenerator würde die Buildbeschreibung verdoppeln und die Apple-Frameworks trotzdem nicht auf Linux prüfbar machen.

`DictationBarApp` hält einen `StatusModel` in SwiftUI-State. Der MainActor-isolierte, beobachtbare Zustand erhält zwei schmale Dienste: `PermissionReading` und `AudioAvailabilityProviding`. Die Statusansicht zeigt denselben Zustand bei wiederholtem Öffnen; „Status aktualisieren“ liest neue Werte. Die Protokolle erlauben Tests ohne OS-Freigabeänderungen. Eine DI-Bibliothek, globale Service-Instanzen oder eine Aufnahme-Zustandsmaschine sind dafür nicht nötig.

Der native PermissionReader fragt ausschließlich `AVCaptureDevice.authorizationStatus(for: .audio)` ab. Er unterscheidet die vier bekannten Mikrofonzustände und behandelt unbekannte Rohwerte konservativ. Eine injizierbare Statusprobe lässt die Produktionszuordnung direkt testen. Kein Geräte-Input, Capture-Session oder Permission-Request wird angelegt.

Systemaudio bleibt „Noch nicht geprüft“. Bildschirmzugriff über `CGPreflightScreenCaptureAccess` wäre kein verlässlicher Nachweis einer separaten Audiofreigabe. Die echte Systemaudio-Freigabe wird mit ihrem Aufnahmeablauf in Slice 3 umgesetzt.

Der Audio-Dienst meldet ausschließlich „Noch nicht verfügbar“. Die Oberfläche bietet daher keinen Aufnahmebeginn an, auch bei erlaubtem Mikrofon. Aufnahmefunktionen und gezielte Freigabeaktionen entstehen erst in ihrem jeweiligen Slice.

## Folgen und Grenzen

Die Cloud kann Dateireferenzen, Projekt-/Plist-Syntax und Swift-Grammatik prüfen. Typprüfung, Linking, lokale Signierung, XCTest, macOS-TCC und Menüleisten-Verhalten erfordern den echten Mac. Der [Prüfbericht](../validation/slice-1.md) trennt diese Nachweise.

Die API-Recherche verwendete Apple-Deklarationen aus einem SDK-15.5-Archiv. Die verwendeten APIs müssen zusätzlich im installierten Xcode-SDK gebaut und geprüft werden. Ein erfolgreicher Lauf auf macOS 15.7.3 bestätigt keinen Lauf auf macOS 14.

Es werden keine Audiodaten, Dateien oder Schlüssel verarbeitet. Audioformate, Ordnerwahl, Keychain, Voxtral und Einfügen bleiben Gegenstand der Folgeslices. Die App ist in diesem Slice für lokale Nutzung ohne App-Store-Verteilung vorgesehen.
