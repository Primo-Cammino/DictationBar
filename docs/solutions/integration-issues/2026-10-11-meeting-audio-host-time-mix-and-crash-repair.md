---
title: "Systemton und Mikrofon über Host-Zeit mischen und unfertige WAVs nach Absturz reparieren"
date: "2026-10-11"
last_updated: "2026-10-11"
category: integration-issues
module: DictationBar
component: meeting-recording
problem_type: integration_issue
symptoms:
  - "Zwei Quellen (ScreenCaptureKit, AVCaptureSession) mit eigenen Uhren laufen auseinander"
  - "Nach 'Sofort beenden' fehlt der WAV-Header, die Datei ist nicht abspielbar"
root_cause: independent_clocks_and_unfinished_header
resolution_type: code_fix
severity: high
tags: [screencapturekit, avfoundation, mixing, wav, crash-recovery, meeting]
---

## Mischen

- Jede Quelle rechnet ihren Puffer-Zeitstempel mit `CMSyncConvertTime` auf die Host-Uhr um
  (`CMSampleBuffer.hostSeconds(from:)`, Quelle: `synchronizationClock` des Streams bzw. der Session).
- `MeetingMixer` legt beide Quellen auf eine 48-kHz-Achse ab dem ersten Puffer. Abweichungen
  bis 20 ms bleiben lückenlos, darüber wird Stille eingefügt oder Überlappung verworfen. Das
  fängt auch die Drift der Uhren ab (Test mit 100 ppm über zehn Minuten).
- Eine Quelle, die 0,5 s hinter der **neuesten Quelle** liegt, gilt als still und hält die andere
  nicht auf. Gemessen wird an der Datenzeit, nicht an der Wanduhr. Mit der Wanduhr würde eine
  blockierte Aufnahme-Warteschlange beide Quellen als still werten und den Rückstau einer Quelle
  verwerfen (Code-Review 20261011-meeting-a1).
- Summe × 0,7, hart begrenzt auf −1 dBFS, mono PCM16.

## Absturz und Stromausfall

- `PCMRecordingWriter` schreibt einen 44-Byte-Header und ruft alle 480.000 Frames (10 s)
  `synchronize()` auf. Das ist `fsync`. Gegen Stromausfall wäre `F_FULLFSYNC` stärker, ist aber nicht umgesetzt.
- `RecordingStore.recover()` repariert vor der Prüfung den Header aus der Dateilänge. Das gilt nur für
  das eigene 44-Byte-Layout, die Datei wird auf ganze Frames gekürzt, und der Header wird nur geschrieben,
  wenn er abweicht.
- Am echten Mac bestätigt: Nach „Sofort beenden“ mitten im Meeting und Neustart ist die WAV
  in der History und abspielbar (11.10.2026).
