# ShareX Linux Variant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Linux `ShareXLinux` variant with GTK controls, Wayland/X11 capture adapters, offline Tesseract OCR, local history, settings, clipboard support, and X11 shortcut integration while preserving the current macOS target.

**Architecture:** The manifest selects macOS or Linux targets at evaluation time. Linux behavior lives in a Foundation-only `ShareXLinuxCore` library, a small C GTK bridge, and a Swift controller. External desktop commands are invoked with structured `Process` arguments. Linux tests cover models, process command construction, PNG metadata, persistence, atomic file naming, and history without requiring a graphical session.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation, SQLite3, GTK 3 C API, `grim`, `slurp`, `gnome-screenshot`, ImageMagick `import`, `tesseract`, `wl-copy`, `xclip`, `xbindkeys`, XDG Base Directory conventions.

**Spec:** `docs/superpowers/specs/2026-11-24-sharex-linux-port-design.md`

## Global Constraints

- macOS deployment target and existing macOS sources remain unchanged.
- Linux uses only local APIs and allow-listed executable arguments.
- Linux supports Wayland and X11 capture paths with explicit missing-tool errors.
- No shell interpolation is used for user-controlled paths or settings.
- A history row is inserted only after an atomic PNG publish succeeds.
- Linux tests must run without a graphical session.
- Linux GTK runtime and helper dependencies are documented and checked at startup.
- Existing uncommitted macOS shortcut changes are preserved and never reverted.

### Task 1: Add platform-selected package targets and Linux test harness

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CSQLite/module.modulemap`
- Create: `Sources/ShareXLinuxCore/Placeholder.swift`
- Create: `Sources/ShareXLinux/main.swift`
- Create: `Tests/ShareXLinuxTests/LinuxPackageTests.swift`

**Interfaces:**
- macOS manifest branch produces the current targets.
- Linux manifest branch produces `ShareXLinuxCore`, `ShareXLinux`, `CSQLite`, and Linux tests.
- Linux executable accepts `--help` and `--action <name>`.

- [ ] Add a platform-conditional manifest while preserving the current macOS dependency and test targets.
- [ ] Add a Linux placeholder executable and a test that invokes its help/action parser.
- [ ] Run `swift test --build-system native` on macOS and verify the existing suite still builds.
- [ ] Run Linux-target tests in CI configuration or a Linux toolchain and verify the new target graph resolves.

### Task 2: Implement Linux models, XDG paths, and settings persistence

**Files:**
- Create: `Sources/ShareXLinuxCore/LinuxModels.swift`
- Create: `Sources/ShareXLinuxCore/LinuxPaths.swift`
- Create: `Sources/ShareXLinuxCore/LinuxSettingsStore.swift`
- Create: `Tests/ShareXLinuxTests/LinuxModelsTests.swift`
- Create: `Tests/ShareXLinuxTests/LinuxSettingsStoreTests.swift`

**Interfaces:**
- `LinuxCaptureMode`: `fullscreen`, `region`, `window`, `ocrRegion`.
- `LinuxCaptureSettings`: cursor, delay, clipboard, screenshot folder.
- `LinuxAppSettings): capture, OCR languages, hotkeys, start-hidden.
- `LinuxPaths.configurationFile(defaults:) -> URL`.
- `LinuxSettingsStore.load() -> LinuxAppSettings` and `save(_:) throws`.

- [ ] Write failing tests for delay normalization, stable raw values, default shortcut data, XDG path overrides, missing settings, and round-trip persistence.
- [ ] Run the focused Linux tests and verify they fail for the expected missing symbols.
- [ ] Implement Codable models, XDG environment resolution, atomic JSON writes, and legacy-safe defaults.
- [ ] Run the focused tests and then all Linux tests.

### Task 3: Implement safe process execution and desktop capability detection

**Files:**
- Create: `Sources/ShareXLinuxCore/LinuxProcessRunner.swift`
- Create: `Sources/ShareXLinuxCore/LinuxDesktopEnvironment.swift`
- Create: `Tests/ShareXLinuxTests/LinuxProcessRunnerTests.swift`
- Create: `Tests/ShareXLinuxTests/LinuxDesktopEnvironmentTests.swift`

**Interfaces:**
- `LinuxProcessRunner.run(executable:arguments:environment:) async throws -> LinuxProcessResult`.
- `LinuxProcessRunner.which(_:) -> URL?`.
- `LinuxDesktopEnvironment.detect(environment:which:) -> LinuxDesktopEnvironment`.
- `LinuxDesktopEnvironment.capturePlan(for:) -> LinuxCapturePlan`.

- [ ] Write failing tests that verify argument arrays remain separate, non-zero exits surface stderr, cancellation terminates the child, and Wayland/X11 selection is deterministic.
- [ ] Run focused tests and verify the expected failures.
- [ ] Implement the runner with `Process`, pipes, cancellation handling, and an injectable executable resolver.
- [ ] Implement helper detection and capture-plan selection for `grim`, `slurp`, `gnome-screenshot`, `import`, `xdotool`, `tesseract`, and clipboard tools.
- [ ] Run focused and full Linux tests.

### Task 4: Implement Linux capture, PNG metadata, and atomic file writing

**Files:**
- Create: `Sources/ShareXLinuxCore/LinuxCaptureService.swift`
- Create: `Sources/ShareXLinuxCore/LinuxPNGMetadata.swift`
- Create: `Sources/ShareXLinuxCore/LinuxCaptureFileWriter.swift`
- Create: `Tests/ShareXLinuxTests/LinuxCaptureServiceTests.swift`
- Create: `Tests/ShareXLinuxTests/LinuxPNGMetadataTests.swift`
- Create: `Tests/ShareXLinuxTests/LinuxCaptureFileWriterTests.swift`

**Interfaces:**
- `LinuxCaptureService.capture(mode:settings:temporaryDirectory:) async throws -> LinuxCapturedImage`.
- `LinuxCapturedImage.path`, `width`, `height`, optional window metadata.
- `LinuxPNGMetadata.read(url:) throws -> LinuxImageSize`.
- `LinuxCaptureFileWriter.writePNG(from:to:date:) throws -> URL`.

- [ ] Write failing tests for exact Wayland/X11 command construction, cursor flags, region geometry handling, PNG dimension parsing, monthly folders, collisions, and temporary-file cleanup.
- [ ] Run focused tests and verify the expected failures.
- [ ] Implement backend command plans and structured process execution. Use `grim -g` plus `slurp` on Wayland, and `gnome-screenshot` or `import` on X11.
- [ ] Implement PNG header parsing and exclusive atomic publication with numeric suffixes.
- [ ] Run focused and full Linux tests.

### Task 5: Implement SQLite history and clipboard/OCR adapters

**Files:**
- Create: `Sources/ShareXLinuxCore/LinuxScreenshotStore.swift`
- Create: `Sources/ShareXLinuxCore/LinuxClipboardService.swift`
- Create: `Sources/ShareXLinuxCore/LinuxOCRService.swift`
- Create: `Tests/ShareXLinuxTests/LinuxScreenshotStoreTests.swift`
- Create: `Tests/ShareXLinuxTests/LinuxOCRServiceTests.swift`
- Create: `Tests/ShareXLinuxTests/LinuxClipboardServiceTests.swift`

**Interfaces:**
- `LinuxScreenshotStore.insert(_:) throws`, `list(search:) throws`, `delete(id:removeFile:) throws`.
- `LinuxOCRService.languages() async throws -> [String]` and `recognize(image:languages:) async throws -> String`.
- `LinuxClipboardService.copyImage(url:) async`, `copyText(_:) async`.

- [ ] Write failing tests for schema creation, ordered/searchable history, missing-file state, delete behavior, Tesseract language parsing, and clipboard command selection.
- [ ] Run focused tests and verify the expected failures.
- [ ] Implement parameterized SQLite access, Tesseract process integration, and Wayland/X11 clipboard selection.
- [ ] Run focused and full Linux tests.

### Task 6: Add X11 hotkeys and GTK bridge

**Files:**
- Create: `Sources/ShareXLinuxCore/LinuxHotkeyRegistrar.swift`
- Create: `Sources/ShareXLinuxGTK/include/sharex_gtk.h`
- Create: `Sources/ShareXLinuxGTK/sharex_gtk.c`
- Create: `Sources/ShareXLinuxGTK/module.modulemap`
- Create: `Tests/ShareXLinuxTests/LinuxHotkeyRegistrarTests.swift`

**Interfaces:**
- `LinuxHotkeyRegistrar.register(_:executable:) throws`, `stop()`, `status`.
- C bridge callbacks use `sharex_gtk_run`, `sharex_gtk_set_status`, `sharex_gtk_show_text`, `sharex_gtk_show_settings`, and `sharex_gtk_show_history`.

- [ ] Write failing registrar tests for generated xbindkeys syntax, cleanup, and Wayland capability guidance.
- [ ] Run focused tests and verify failure.
- [ ] Implement the private xbindkeys process and safe config file lifecycle.
- [ ] Implement the GTK window, settings dialog, history dialog, and editable OCR result dialog with stable action callbacks.
- [ ] Run Linux tests and compile the GTK C target on a Linux toolchain.

### Task 7: Wire the Linux controller and executable

**Files:**
- Create: `Sources/ShareXLinux/LinuxAppController.swift`
- Modify: `Sources/ShareXLinux/main.swift`
- Create: `Tests/ShareXLinuxTests/LinuxAppControllerTests.swift`

**Interfaces:**
- `LinuxAppController.perform(_:) async`.
- `LinuxAppController.start() throws` and `stop()`.
- `LinuxActionParser.parse(arguments:) -> LinuxCLIAction`.

- [ ] Write failing controller tests for delay, capture success, write failure without history, OCR copy, history delete, and dependency errors.
- [ ] Run focused tests and verify failure.
- [ ] Implement controller coordination, GTK callback routing, XDG paths, status reporting, and `--action` support for hotkeys.
- [ ] Run full Linux tests and build the executable.

### Task 8: Add packaging, documentation, and verification

**Files:**
- Create: `scripts/build-linux.sh`
- Create: `packaging/linux/sharex.desktop`
- Create: `packaging/linux/sharex-autostart.desktop`
- Create: `packaging/linux/install.sh`
- Create: `docs/testing/linux-manual-matrix.md`
- Modify: `README.md`
- Create: `.github/workflows/linux.yml`

**Interfaces:**
- `scripts/build-linux.sh --check-dependencies` reports missing runtime/build tools.
- `scripts/build-linux.sh --release` emits a Linux executable and desktop files.
- The installer places the executable, desktop file, and optional autostart entry under XDG paths.

- [ ] Add dependency checks and release packaging without requiring root.
- [ ] Document Wayland and X11 setup, fallback behavior, settings paths, and recovery steps.
- [ ] Add CI that installs Swift, GTK, SQLite, Tesseract, and helper packages and runs Linux tests/build.
- [ ] Run macOS `swift test --build-system native` and `swift build --build-system native --product ShareXMac`.
- [ ] Run Linux tests/build in CI or an available Linux toolchain, run shell syntax checks, and inspect `git diff --check`.

## Verification checklist

- [ ] Existing macOS tests and target still build.
- [ ] Linux core tests pass without a display.
- [ ] Linux GTK target compiles with documented packages.
- [ ] Capture failures do not create history rows.
- [ ] Settings and history stay under XDG paths.
- [ ] Wayland and X11 helper errors are actionable.
- [ ] No shell interpolation or network dependency is introduced.

