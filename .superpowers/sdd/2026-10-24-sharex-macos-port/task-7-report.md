# Task 7 report: offline Vision OCR

## Implementation

- Added `VisionOCRService` with accurate, local `VNRecognizeTextRequest` revision 3 recognition, supported-language discovery, explicit language validation, language correction from the existing `OCRSettings`, and multiline/single-line output. Both the settings-based interface and the plan's language/scale convenience interface are available. The existing `OCRSettings` declaration was reused without modification.
- Added a pure deterministic text-ordering helper. It orders normalized Vision observations from top to bottom, groups observations on the same row using a stable row anchor, orders each row left to right, ignores whitespace-only observations, and uses text as a final geometry tie-breaker. Single-line formatting collapses whitespace.
- Added scale normalization to 1...4 and a 64-million-pixel preparation limit (256 MB for an RGBA bitmap, not a total process memory guarantee). Overflow/invalid input is rejected before bitmap allocation. Nonfinite scale values use 1×. Recognition runs on a background queue; cancellation completes the awaiting task and invokes `VNRequest.cancel()` for an installed request. The lock prevents duplicate continuation completion during cancellation/result races.
- Added an AppKit `OCRWindow` hosting a native SwiftUI result view. The result is editable, can be displayed/copied in single-line form without rerunning recognition, and has loading, actionable error, no-text, retry, and copy states. Closing the window cancels recognition; request identifiers prevent stale results from overwriting a later retry. The controller exposes `onClose` for root AppCoordinator retention cleanup.
- Added permission-free pure tests plus actual Vision integration tests using a white AppKit bitmap with large monospaced multiline text, with exact text/order assertions at both 1× and 2× scale. Integration coverage also includes supported languages, invalid languages, blank images, and already-cancelled tasks.

## TDD / verification history

- `swift build --build-system native --target ShareXMacCoreTests`: observed missing `VisionOCRService`, `OCRError`, and `OCRTextLine` before implementation as expected; concurrent root view-model tests also referenced not-yet-created symbols. Log: `/tmp/sharex-task7-red.log`.
- `swift test --build-system native --filter OCR`: first implementation run stopped on concurrent missing `HistoryViewModel` / `SettingsViewModel` symbols. Log: `/tmp/sharex-task7-focused.log`.
- The same focused command after those models arrived ran 10 tests: all pure tests, language discovery, invalid-language validation, and cancellation passed. The original proportional-font fixture exposed a real OCR transcription ambiguity (`Hello world` recognized as `Hello worla`). The rendered fixture was strengthened with 52-point medium monospaced text and clear FIRST/SECOND/THIRD LINE strings; exact assertions were retained. Log: `/tmp/sharex-task7-focused2.log`.
- Another focused attempt stopped on concurrent `GlobalHotkeyManager` nonisolated-deinit/Sendable errors, without OCR compilation errors. Log: `/tmp/sharex-task7-focused3.log`.
- `swiftc -typecheck -swift-version 6 -target arm64-apple-macos13.0 -I .build/arm64-apple-macosx/debug/Modules Sources/ShareXMac/OCR/OCRWindow.swift`: passed independently while root app dependencies were being added.

Final focused/full/build results are recorded below after the shared workspace compiles.

## Final focused verification

The root agent ran this coordinated shared-workspace command after the pending app/core types arrived:

`swift test --build-system native --filter 'CaptureMetadataTests|CaptureCoordinatorTests|OCRVisionIntegrationTests|HistoryViewModelTests|SettingsViewModelTests|HotkeyBindingTests|GlobalHotkeyManagerTests'`

Result: **exit 0, all 25 selected tests passed**. Log: `/tmp/sharex-focused-green.log`. The five OCR integration tests passed: supported languages, invalid-language errors, already-cancelled work, no text in a blank image, and exact 1× multiline / 2× single-line text recognition. The exact fixture test completed in 0.391 seconds in this warm run. The six pure OCR helper tests had already passed in `/tmp/sharex-task7-focused2.log` and were unchanged afterward.

`git diff --check` passed. The OCR window also passed the separate macOS 13-target typecheck noted above; the coordinated test build compiled the app with the final window implementation. The root agent is running the full suite and final app build after the concurrent task commits, so those integration-wide results will be recorded in the root report.

## Validation limits

OCR accuracy depends on image quality and the installed Vision models. The generated high-contrast test is an actual local Vision inference test, not a mocked recognizer. A cold inference on this development host initially took about 60 seconds; the final warm integration run was under half a second. No Screen Recording or Accessibility permission is required for these OCR tests. The window's editing/toggle/copy interactions have been compiled but still need a manual app interaction check. Automated cancellation coverage currently exercises cancellation before recognition begins; the in-progress cancellation implementation is synchronized and calls Vision's cancel API, but has no dedicated injected in-flight race test.
