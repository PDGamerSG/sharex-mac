# ShareX macOS Focused Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS 13+ menu-bar screenshot utility with all-display, region, and window capture; offline OCR; local screenshot history; application settings; and configurable global hotkeys.

**Architecture:** SwiftUI supplies the settings, OCR, history, and image-history views while AppKit owns the menu-bar lifecycle and capture panels. ScreenCaptureKit, Vision, Carbon Event Hot Keys, SQLite3, UserDefaults, and security-scoped bookmarks provide the platform services. A core library contains pure models and stores so behavior can be tested with `swift test` without UI automation.

**Tech Stack:** Swift 6.4, Swift Package Manager, SwiftUI, AppKit, ScreenCaptureKit, Vision, Carbon, SQLite3, XCTest/Swift Testing, macOS 13 minimum, universal arm64/x86_64 build.

**Spec:** `docs/superpowers/specs/2026-10-24-sharex-macos-port-design.md`

## Global Constraints

- macOS deployment target is 13.0 or newer.
- The app is local-only; no uploader, network service, workflow, or telemetry dependency is allowed.
- Full-screen capture produces one image containing all connected displays.
- Region capture is a drag selection over the frozen all-display image.
- Window capture uses a click-to-select picker.
- Capture settings include cursor visibility and a 0–60 second delay.
- Successful captures save PNG files and create local history records.
- OCR uses Vision offline and supports region and image-history input.
- History and image history are local views over one SQLite capture store.
- Global hotkeys are configurable, persisted, conflict-checked, and registered through Carbon Event Hot Keys.
- All reused ShareX code or assets retain GPLv3 notices and attribution.

---

### Task 1: Create the Swift package and tested domain foundation

**Files:**
- Create: `Package.swift`
- Create: `Sources/ShareXMacCore/Capture/CaptureMode.swift`
- Create: `Sources/ShareXMacCore/Capture/CaptureSettings.swift`
- Create: `Sources/ShareXMacCore/History/CaptureRecord.swift`
- Create: `Sources/ShareXMacCore/Hotkeys/HotkeyAction.swift`
- Create: `Sources/ShareXMacCore/Settings/AppSettings.swift`
- Create: `Tests/ShareXMacCoreTests/DomainTests.swift`
- Create: `README.md`

**Interfaces:**
- `CaptureMode`: `fullscreen`, `region`, `window`, `ocrRegion`.
- `CaptureSettings`: value type with `showCursor`, `delaySeconds`, and normalized delay.
- `CaptureRecord`: `Codable`, `Identifiable` metadata model with UUID, timestamp, mode, path, width, height, optional window title, and optional application name.
- `HotkeyAction`: stable raw-string actions for the seven configurable commands.
- `AppSettings`: `Codable` settings model with capture, OCR, folder bookmark data, and hotkey bindings.

- [ ] Write failing tests for delay normalization, stable mode/action raw values, record Codable round-trip, and default settings.
- [ ] Run `swift test` and confirm the new tests fail because the package and types do not exist.
- [ ] Implement the smallest package, models, and defaults that satisfy the tests.
- [ ] Run `swift test` and confirm all domain tests pass.
- [ ] Commit with `feat: create macOS core package and domain models`.

### Task 2: Add settings persistence and folder access

**Files:**
- Create: `Sources/ShareXMacCore/Settings/SettingsStore.swift`
- Create: `Sources/ShareXMacCore/Settings/FolderBookmarkStore.swift`
- Create: `Tests/ShareXMacCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- `SettingsStore.load() -> AppSettings` and `save(_:) throws`.
- `FolderBookmarkStore.makeBookmark(for:) throws -> Data` and `resolve(_:) throws -> URL`.
- Both stores accept injectable `UserDefaults`/file URLs for tests.

- [ ] Write failing tests for missing-settings defaults, persisted settings reload, and bookmark round-trip in a temporary directory.
- [ ] Run the focused tests and confirm the expected failures.
- [ ] Implement atomic JSON settings persistence and security-scoped bookmark encoding/decoding.
- [ ] Run focused tests, then the full `swift test` suite.
- [ ] Commit with `feat: persist app settings and screenshot folder access`.

### Task 3: Implement history storage

**Files:**
- Create: `Sources/ShareXMacCore/History/ScreenshotStore.swift`
- Create: `Sources/ShareXMacCore/History/SQLiteScreenshotStore.swift`
- Create: `Tests/ShareXMacCoreTests/SQLiteScreenshotStoreTests.swift`

**Interfaces:**
- `ScreenshotStore` exposes `insert(_:)`, `list(search:)`, `delete(id:removeFile:)`, and `record(for:)`.
- `SQLiteScreenshotStore` owns schema creation, parameter binding, date encoding, and missing-file detection.

- [ ] Write failing tests for schema creation, insert/list ordering, filename search, missing-file state, and deleting a row.
- [ ] Run the focused tests and confirm they fail before implementation.
- [ ] Implement SQLite3 access behind an actor and use bound parameters for every value.
- [ ] Run focused tests and full `swift test`.
- [ ] Commit with `feat: add local SQLite screenshot history`.

### Task 4: Build the ScreenCaptureKit capture service

**Files:**
- Create: `Sources/ShareXMacCore/Capture/ScreenCaptureService.swift`
- Create: `Sources/ShareXMacCore/Capture/DisplayCompositor.swift`
- Create: `Sources/ShareXMacCore/Capture/CaptureFileWriter.swift`
- Create: `Tests/ShareXMacCoreTests/DisplayCompositorTests.swift`
- Create: `Tests/ShareXMacCoreTests/CaptureFileWriterTests.swift`

**Interfaces:**
- `ScreenCaptureService.captureAllDisplays(showCursor:) async throws -> CGImage`.
- `ScreenCaptureService.captureWindow(_:, showCursor:) async throws -> CGImage`.
- `DisplayCompositor.composite(_:) -> CGImage` preserves logical display origins and backing scales.
- `CaptureFileWriter.writePNG(_:to:date:) throws -> URL` performs collision-safe atomic writes.

- [ ] Write failing compositor tests for mixed display scales/origins and writer tests for collision suffixes and atomic output.
- [ ] Run focused tests and confirm the expected failures.
- [ ] Implement display discovery, per-display screenshot capture, pixel-space composition, window capture, and PNG writing.
- [ ] Run focused tests and full `swift test`.
- [ ] Commit with `feat: capture displays and windows with ScreenCaptureKit`.

### Task 5: Add AppKit region and window selection panels

**Files:**
- Create: `Sources/ShareXMacCore/Capture/RegionSelectionModel.swift`
- Create: `Sources/ShareXMac/Capture/RegionSelectionPanel.swift`
- Create: `Sources/ShareXMac/Capture/WindowPickerPanel.swift`
- Create: `Tests/ShareXMacCoreTests/RegionSelectionModelTests.swift`

**Interfaces:**
- `RegionSelectionModel.selection(start:end:in:) -> CGRect?` normalizes and clamps rectangles.
- `RegionSelectionPanel.select(image:screenBounds:) async -> CGRect?` returns `nil` on Escape.
- `WindowPickerPanel.selectWindow() async -> SCWindow?` returns `nil` on Escape/cancel.

- [ ] Write failing geometry tests for normalized, clamped, and zero-area selections.
- [ ] Run the focused tests and confirm failure.
- [ ] Implement the transparent cross-display AppKit panel, pointer highlight, click selection, and Escape cancellation.
- [ ] Run geometry tests and compile the app target.
- [ ] Commit with `feat: add region and window picker overlays`.

### Task 6: Wire the capture coordinator and menu-bar app

**Files:**
- Create: `Sources/ShareXMacCore/Capture/CaptureCoordinator.swift`
- Create: `Sources/ShareXMac/App/ShareXMacApp.swift`
- Create: `Sources/ShareXMac/App/AppCoordinator.swift`
- Create: `Sources/ShareXMac/App/MenuBarController.swift`
- Create: `Tests/ShareXMacCoreTests/CaptureCoordinatorTests.swift`

**Interfaces:**
- `CaptureCoordinator.capture(_ mode: CaptureMode) async -> Result<CaptureRecord, CaptureError>`.
- The coordinator applies delay, checks permission, invokes the correct capture/picker service, writes the PNG, and inserts history only after a successful write.
- The menu exposes only the approved capture, OCR, history, image-history, settings, and quit commands.

- [ ] Write failing coordinator tests for delay normalization, write failure not creating history, and successful record creation.
- [ ] Run focused tests and confirm failure.
- [ ] Implement the coordinator, permission gate, menu-bar lifecycle, and command routing.
- [ ] Run the full test suite and `swift build`.
- [ ] Commit with `feat: wire capture flows into the menu bar app`.

### Task 7: Implement Vision OCR

**Files:**
- Create: `Sources/ShareXMacCore/OCR/VisionOCRService.swift`
- Create: `Sources/ShareXMacCore/OCR/OCRSettings.swift`
- Create: `Sources/ShareXMac/OCR/OCRWindow.swift`
- Create: `Tests/ShareXMacCoreTests/OCRTextOrderingTests.swift`

**Interfaces:**
- `VisionOCRService.supportedLanguages() throws -> [String]`.
- `VisionOCRService.recognize(image:language:scale:singleLine:) async throws -> String`.
- OCR preprocessing and line ordering remain pure helpers covered by tests.

- [ ] Write failing text-ordering tests for multiline, single-line, and empty recognition results.
- [ ] Run focused tests and confirm failure.
- [ ] Implement Vision recognition, language validation, scaling, line ordering, editable result UI, and copy action.
- [ ] Run OCR tests, full `swift test`, and `swift build`.
- [ ] Commit with `feat: add offline Vision OCR`.

### Task 8: Add history and settings UI

**Files:**
- Create: `Sources/ShareXMac/History/HistoryView.swift`
- Create: `Sources/ShareXMac/History/ImageHistoryView.swift`
- Create: `Sources/ShareXMac/Settings/SettingsView.swift`
- Create: `Sources/ShareXMac/Settings/HotkeySettingsView.swift`

**Interfaces:**
- Views consume `ScreenshotStore`, `SettingsStore`, and coordinator actions through injected protocols.
- History actions are limited to preview/open/reveal/copy-path/OCR/delete.
- Settings expose only approved capture, OCR, storage, permission, and launch controls.

- [ ] Add view-model tests for search, missing-file display, delete confirmation, and settings updates.
- [ ] Run focused tests and confirm failure.
- [ ] Implement the SwiftUI views and connect them to the app coordinator.
- [ ] Run full tests and build the executable target.
- [ ] Commit with `feat: add local history and application settings UI`.

### Task 9: Implement configurable global hotkeys

**Files:**
- Create: `Sources/ShareXMacCore/Hotkeys/GlobalHotkeyManager.swift`
- Create: `Sources/ShareXMacCore/Hotkeys/HotkeyBinding.swift`
- Create: `Tests/ShareXMacCoreTests/HotkeyBindingTests.swift`

**Interfaces:**
- `GlobalHotkeyManager.register(_:) throws`, `unregisterAll()`, and `registrationError`.
- `HotkeyBinding` stores Carbon key code plus modifier flags and validates duplicate actions/bindings.

- [ ] Write failing tests for duplicate detection, clear/reset behavior, and stable Codable bindings.
- [ ] Run focused tests and confirm failure.
- [ ] Implement Carbon registration callbacks, conflict reporting, and menu action dispatch.
- [ ] Run full tests and build.
- [ ] Commit with `feat: add configurable global hotkeys`.

### Task 10: Package, audit removed scope, and release

**Files:**
- Create: `Resources/ShareXMac.entitlements`
- Create: `scripts/build-release.sh`
- Create: `docs/testing/macOS-manual-matrix.md`
- Modify: `README.md`

- [ ] Add entitlements, signing/notarization instructions, and universal build script.
- [ ] Add the manual test matrix for permissions, multiple displays, Retina scaling, cursor/delay, region/window cancellation, OCR, history, and hotkey conflicts.
- [ ] Search the source and menu definitions for every removed feature and delete accidental references.
- [ ] Run `swift test`, `swift build -c release`, and the release script in dry-run mode.
- [ ] Commit with `chore: package and audit the macOS release`.

