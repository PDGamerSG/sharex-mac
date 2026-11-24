# ShareX Linux Variant Design

**Date:** 2026-11-24  
**Status:** Approved for implementation from the project owner's cross-platform request

## Goal

Add a Linux variant of ShareX Mac that keeps the existing macOS menu-bar application and provides the same local screenshot, OCR, history, settings, and shortcut workflow on common Linux desktops.

## Product boundary

The macOS target remains the existing native AppKit, ScreenCaptureKit, Vision, Carbon, and SwiftUI application. Linux is a separate executable named `ShareXLinux` in the same Swift package. Both variants save local PNG captures, maintain local SQLite history, run offline OCR, copy results to the clipboard, and expose capture/settings actions from a desktop UI.

The Linux target supports Ubuntu-class distributions with GTK 3 development/runtime packages. It detects Wayland and X11 at runtime. Wayland capture uses `grim` and `slurp`, while X11 capture uses `gnome-screenshot` when available and falls back to ImageMagick `import`. Window capture on X11 uses `xdotool` plus `import`. The app reports missing tools with an actionable setup message.

The initial Linux release does not include video recording, uploads, annotation, workflows, or network services. It also does not fabricate a universal Wayland global-hotkey API. X11 hotkeys are registered through `xbindkeys` when installed. On Wayland, the app exposes its actions through the GTK window and records the shortcut instructions needed for the compositor's global shortcut settings.

## Package architecture

`Package.swift` selects platform-specific targets at manifest-evaluation time.

- On macOS it keeps the existing `ShareXMacCore`, `ShareXMac`, and test targets unchanged.
- On Linux it exposes `ShareXLinuxCore`, `ShareXLinux`, `ShareXLinuxGTK`, and Linux tests.
- Linux uses a `CSQLite` system-library target linked with `sqlite3`.
- `ShareXLinuxGTK` is a small C bridge linked with GTK 3. The bridge owns GTK object lifetimes and emits action callbacks into Swift, keeping the Linux application logic testable without requiring a display in unit tests.

## Linux core behavior

`ShareXLinuxCore` contains Foundation-only models and services.

- `LinuxCaptureMode`, `LinuxCaptureSettings`, `LinuxOCRSettings`, `LinuxHotkeyBinding`, and `LinuxAppSettings` are Codable value types.
- `LinuxSettingsStore` stores JSON under `XDG_CONFIG_HOME/sharex/sharex-linux.json`, defaulting to `~/.config/sharex/sharex-linux.json`.
- `LinuxScreenshotStore` uses SQLite with the same capture metadata fields as macOS and marks missing files in history.
- `LinuxCaptureService` executes a fixed allow-listed set of desktop tools through `Process`. Arguments are passed as arrays and never assembled into a shell command.
- Fullscreen capture writes a temporary PNG, region capture uses `slurp` or an X11 selection tool, and window capture uses the desktop-specific window picker.
- `LinuxPNGMetadata` reads PNG dimensions from the file header, so no image framework is required for metadata or tests.
- `LinuxCaptureFileWriter` moves a completed temporary file into a monthly directory with collision-safe names.
- `LinuxOCRService` invokes `tesseract` with a language list discovered from `tesseract --list-langs`. It returns text through stdout and never sends images over the network.
- `LinuxClipboardService` uses `wl-copy` on Wayland and `xclip` on X11. It preserves the existing clipboard when a required helper is missing or a command fails.
- `LinuxHotkeyRegistrar` writes a private `xbindkeys` configuration and owns the helper process on X11. Wayland returns a capability status with compositor setup guidance.
- All process execution has exit-code, stdout, stderr, cancellation, and missing-executable errors.

## GTK application

The C bridge provides:

- A main window with the capture actions, OCR action, image history, settings, status text, and quit action.
- A settings dialog with screenshot folder, cursor visibility, delay, clipboard-copy, and start-hidden controls.
- A history dialog populated from the SQLite store with open, reveal, copy path, OCR, and delete actions.
- A text result dialog for OCR with editable multiline text, retry, and copy actions.
- Native GTK cancellation and close callbacks.

Swift `LinuxAppController` owns settings, capture, OCR, history, clipboard, and hotkey services. GTK callbacks only send action identifiers and return user input. The controller performs all file and process work outside the GTK bridge and updates status text on the main thread.

## Data flow

1. The GTK action callback sends a stable action identifier to `LinuxAppController`.
2. The controller checks settings and desktop capabilities.
3. A cancellable delay runs before desktop freeze.
4. The capture service writes a temporary PNG and returns its path and metadata.
5. The file writer atomically publishes the monthly PNG.
6. The controller copies the canonical PNG when enabled, inserts the history row, and updates the GTK status.
7. OCR reads the stored PNG through Tesseract, shows editable text, and copies successful results.
8. History actions operate on the SQLite row and the canonical path.

A failed capture or file write creates no history row. A successful file write followed by a history error reports the saved path and leaves the file available for recovery.

## Distribution

- Add `scripts/build-linux.sh` for release builds and dependency checks.
- Add `packaging/linux/sharex.desktop`, `packaging/linux/install.sh`, and an XDG autostart file.
- Document Ubuntu and Fedora package names, Wayland/X11 helper requirements, and the Linux commands in `README.md`.
- Add a Linux manual acceptance matrix covering Wayland and X11, multiple displays, region/window cancellation, OCR, clipboard, history, settings persistence, and missing dependency messages.

## Compatibility

Existing macOS source files, tests, and user settings remain in place. The Linux settings and history paths are separate to avoid interpreting security-scoped macOS bookmark data on Linux. The Linux target reuses the same raw capture mode names and metadata field names so future cross-platform migration can be deliberate.

## Licensing

The repository's existing GPLv3 and NOTICE files continue to cover the new target. The GTK bridge and Linux adapters are authored in this repository. No third-party source is copied into the project.

