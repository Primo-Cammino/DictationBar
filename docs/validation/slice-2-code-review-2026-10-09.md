## Code Review Results

**Scope:** local-aligned, base `313d97e` -> local working tree; 44 changed files at dispatch, plus two regression-test files added during apply. No PR or remote.
**Intent:** Native BYOK dictation with chosen microphone, durable WAV/history, Mistral Voxtral, one paste into the current eligible field, and safe Quit/relaunch. Explicit approved Slice-2 plan.
**Mode:** markdown local-apply. Pre-review tree was dirty; fixes remain uncommitted.

**Reviewers:** correctness, security, adversarial, testing, maintainability, reliability, swift-ios, project-standards, learnings-researcher.

- Testing: new asynchronous pipeline, persistence and OS adapters require failure evidence.
- Maintainability: new service boundaries and shared state must remain understandable.
- Reliability: WAV/journal checkpoints and Quit can lose data if callbacks cross operation boundaries.
- Swift/macOS: AVFoundation, Carbon, AX, Keychain and application termination are native integration points.
- Project standards: root AGENTS.md governs every changed file and requires local execution and preserved originals.
- Learnings: the Xcode sandbox lesson applies to native verification.
- Adversarial: in-process fallback; external cross-model review is disabled by project config and the user's local-only instruction.

### Applied

| # | File (current fix location) | Fix | Reviewer / Confidence |
|---|---|---|---|
| 1 | `DictationBar/Services/NativeTextInsertionService.swift:106` | Focus after AX attribute collection is rechecked; posting rejects a changed foreground process. Timing boundary still needs native QA. | adversarial / 75 |
| 2 | `DictationBar/State/DictationModel.swift:265` | Invalid zero-frame capture preserves original bytes and a failed entry without a permanent start/Quit gate. Local metadata failure still blocks. Quit ordering needs native QA. | correctness / 75 |
| 3 | `DictationBar/Services/MistralTranscriptionService.swift:23` | Temporary-file cleanup is installed before multipart construction; output/input close on setup failures. | reliability / 100 |
| 4 | `DictationBar/Services/RecordingStore.swift:141` | Durable staging ownership prevents startup rename of a valid WAV rejected during reservation. Missing ownership markers are handled conservatively. | adversarial / 100 |
| 5 | `DictationBarTests/NativeHTTPTransportTests.swift:40` | Real loopback HTTP tests cover redirect refusal, cancellation and declared/streamed 4 MiB limits; service tests cover multipart cleanup. | testing / 75 |
| 6 | `DictationBarTests/APIKeyStoreTests.swift:19` | A successful existing-item update replaces the old key without creating another item. | testing / 75 |

Validation: complete native suite 56 -> 69 passed, zero failures/skips; separate native build exit 0; git diff --check clean. No repository linter is configured. Two initial local HTTP-fixture failures were corrected and their evidence retained. The isolated three-test transport rerun and full suite passed.

Fixes #1, #2 and #4 affect timing, termination and file ownership. Unit evidence covers the modeled failures; real native microphone, focus/paste and Quit behavior still require acceptance. The original finding details and before/apply diffs are preserved in the local run artifacts.

The apply diff was self-reviewed against pre-apply.tar.gz. Cleanup remains owned by the existing multipart helper; ownership is persisted by RecordingStore and carried into the session snapshot. Native AX test seams preserve the default reader and avoid external target contents. No duplicate policy helper or abandoned implementation was added.

### Requirements Completeness

The checklist below evaluates whether planned code appears in the change, not whether live native behavior is accepted. All OS/runtime evidence remains subject to the native matrix.

- R1: met in code -- Menu, Settings and History windows.
- R2: met in code -- Explicit microphone selection and capture ID.
- R3: met in code -- Folder bookmark save/load.
- R4: met in code -- Global Control-Option-Space.
- R5: met in code -- Toggle stop and Escape normal stop.
- R6: met in code -- Menu start/stop.
- R7: met in code -- Distinct visible processing phases.
- R8: met in code -- Single-operation gate, no queue.
- R9: met in code -- Validated PCM WAV and exclusive finalization.
- R10: met in code -- Explicit Keychain save/update/remove.
- R11: met in code -- Saved WAV -> Voxtral transcription.
- R12: met in code -- Completion-time target snapshots and focus recheck.
- R13: met in code -- At-most-once Cmd-V claim.
- R14: met in code -- Persistent text and insertion outcome.
- R15: met in code -- Explicit History copy.
- R16: met in code -- Newest-first dated/duration/file/status history.
- R17: met in code -- Atomic per-entry journal and local recovery.
- R18: met in code -- Manual history retry without paste.
- R19: met in code -- Capture Quit local checkpoint / failure refusal.
- R20: met in code -- HTTP Quit invalidation and saved WAV.
- R21: met in code -- Passive startup / isolated test profile.
- R22: met in code -- Explicit permissions and user messages.
- R23: met in code -- Interruption/device-loss handling without fallback.
- R24: met in code -- Preserved audio/text and typed errors.
- R25: met in code -- Immutable session configuration snapshot.
- R26: met in code -- Local build/test/review, no publishing.
- R27: met in code -- Own Mistral key; no account/subscription/bundled key.
- R28: met in code -- Clipboard replacement without restore.
- U1: met in code and automated checks -- state/runtime; native evidence where required remains pending.
- U2: met in code and automated checks -- journal/folder/history; native evidence where required remains pending.
- U3: met in code and automated checks -- selected-microphone capture; native evidence where required remains pending.
- U4: met in code and automated checks -- Keychain/Mistral; native evidence where required remains pending.
- U5: met in code and automated checks -- shortcut/current-target insertion; native evidence where required remains pending.
- U6: met in code and automated checks -- pipeline/recovery/termination; native evidence where required remains pending.
- U7: met in code and automated checks -- German native controls; native evidence where required remains pending.
- U8: partially addressed -- README and truthful validation report exist; required real audio/Voxtral/paste, Escape, focus switch, history and Quit/relaunch evidence is pending. This is the intentionally remaining acceptance stage, not a claim of completed scope.

### Actionable Findings

Remaining actionable code findings: none. All six independently validated findings were applied and verified. Native acceptance remains a blocking verification gate, recorded in [the validation report](slice-2-local-2026-10-09.md).

### Learnings & Past Solutions

- Known Pattern: [Xcode sandbox macros](../solutions/build-errors/2026-10-09-xcode-sandbox-macros.md). Native Xcode access outside the agent sandbox is needed without changing app target security. This verification used that local route; the earlier research note's pending-build statement is superseded by the final executed evidence.

### Coverage

- Eight structured reviewers plus one prose learnings reviewer collected terminal outcomes; no failed or timed-out reviewers. No lifecycle cleanup API is exposed by this harness.
- Cross-model outcome: not run, explicitly off; local adversarial lens completed.
- Six source findings hydrated from full artifacts. No malformed findings/returns, quote-gate demotions, confidence suppressions, settlement reversals, semantic merges or soft-bucket demotions.
- One independent validator batch: #1-#6 validated; zero drops, zero degraded validations and zero cross-model shortcut skips.
- Six fixes applied. Additional successful/failed local transcript-commit and repeated-Quit tests close the cited termination coverage gap.
- Original native HTTP and Keychain update test gaps closed. Exact 3600-second/500 MB boundary tests remain a narrow unexecuted limit check; no live giant-audio upload is required.
- Native acceptance pending: real microphone/WAV, Voxtral, Escape, TextEdit/Safari focus/paste, history/copy/retry and Quit/relaunch. macOS-14 runtime, external-device availability and reproducible denial states are not established.
- Residual timing boundary: AX validation and global event delivery cannot be atomic; a focus change after the last check remains possible under the approved KTD7. The corrected within-snapshot stale-focus defect is separate.
- Local evidence: `build/slice2-code-review-20261009/`, `build/slice2-final-tests-20261009/`, `build/slice2-final-build-20261009/`.

---

### Verdict

**Not ready for Slice-2 acceptance.** Code review fixes and automated verification are complete. Real native acceptance is still required; start with Settings and one TextEdit dictation, then execute the remaining native matrix. No push, commit, publication or Slice-2 completion is claimed.

Actionable findings: none. Required next gate: real native acceptance as documented in the validation report.
