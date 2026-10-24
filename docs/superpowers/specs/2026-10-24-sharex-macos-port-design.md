# ShareX macOS Focused Port Design

**Date:** 2026-10-24  
**Status:** Approved for implementation by the project owner

## Goal

Build a small, local-only macOS screenshot utility based on the requested subset of ShareX. It must capture all connected displays as one full-screen image, capture a selected region, capture a selected window, run offline OCR, persist screenshots and local history, and expose configurable global hotkeys and application settings.

## Product boundary

The first release targets macOS 13 or newer and ships as a universal Apple Silicon/Intel menu-bar application. It has no account, network, upload, workflow, screen-recording, annotation, or general-purpose tools functionality. A successful capture has one fixed outcome: save a PNG in the configured screenshot folder and record it in local history. OCR can copy recognized text because copying the OCR result is part of the OCR feature.

The full-screen action captures every display currently connected and composites them into one image using their logical positions and backing scale factors. Region capture freezes the same desktop image and crops a dragged rectangle. Window capture opens a picker that highlights windows under the pointer and captures the clicked window. `Esc` cancels an in-progress selection; there is no last-region or discard workflow.

## Platform architecture

- **SwiftUI:** settings, OCR result, history table, and image-history grid.
- **AppKit:** menu-bar status item, full-screen selection panels, pointer/window highlighting, and application lifecycle.
- **ScreenCaptureKit:** display and window screenshots, cursor inclusion, and shareable-window discovery.
- **Vision:** offline text recognition and supported-language discovery.
- **Carbon Event Hot Keys:** global shortcut registration without an Accessibility event tap.
- **SQLite3:** local capture metadata and history. PNG files remain in the user-selected screenshot folder; thumbnails are derived from those files.
- **UserDefaults plus security-scoped bookmarks:** settings and persistent access to a user-selected folder.

The code is divided into `Capture`, `OCR`, `History`, `Hotkeys`, `Settings`, and `App` modules. A `CaptureCoordinator` owns the capture state machine and writes through a `ScreenshotStore` actor. UI code never writes files or registers Carbon callbacks directly.

## Capture behavior

Capture settings are global for all capture modes:

- `showCursor: Bool`, default `false`.
- `delaySeconds: Double`, default `0`, constrained to `0...60`.
- `screenshotFolderBookmark`, defaulting to a first-run folder selection with `~/Pictures/ShareX` as the suggested location.

Delay occurs before the desktop is frozen. A small cancellable countdown is shown while the delay is active. Cursor inclusion is requested from ScreenCaptureKit at the capture point, so the final cursor position is deterministic.

PNG names use `ShareX_yyyy-MM-dd_HH-mm-ss.png` with a numeric suffix when the timestamp collides. Writes use a temporary file followed by an atomic move. A failed write produces no history record.

## OCR behavior

The OCR shortcut starts the region selector, and the OCR window can also load an image from image history. Vision uses accurate recognition, language correction, supported-language discovery, and a configurable scale factor. Results preserve line order and can be rendered as multiline or single-line text. The result is editable and copyable. No OCR service links or network calls are included.

## History behavior

One SQLite `captures` table backs both retained views. Each row contains a UUID, capture date, mode, file path, pixel dimensions, display/window metadata when available, and cursor/delay settings used for the capture. History shows a chronological metadata list; image history shows a thumbnail grid. Both support preview, open, reveal in Finder, copy path, OCR, and deleting the file plus row. Missing files remain visible with a missing-file state.

## Settings and hotkeys

Settings are limited to capture options, OCR options, screenshot-folder access, history database status, launch-at-login/start-hidden, and Screen Recording permission guidance. The menu contains only capture modes, OCR, history, image history, settings, and quit.

Hotkeys are configurable for full-screen capture, region capture, window picker, OCR region capture, history, image history, and settings. The editor records key combinations, rejects duplicates, reports registration failures, supports clear/reset, and persists through restarts.

## Removed scope

The macOS app contains no screen recording, GIF capture, last region, auto capture, uploading, workflows, tools section, image editor, annotation, after-capture tasks, after-upload/after-flow tasks, destinations, destination settings, custom uploader, debug UI, donate/follow links, discard workflow, or about page.

## Permissions and failure handling

The app detects Screen Recording permission before attempting capture and provides a direct button to macOS Privacy settings. It excludes its own windows from the window picker. Permission denial, closed windows, stale folder bookmarks, missing history files, invalid shortcuts, and OCR failures are surfaced as actionable in-app errors without crashing or creating partial records.

## Licensing

The upstream ShareX repository is GPLv3. Any code or assets copied from ShareX must preserve GPLv3 notices and attribution, and the resulting derivative must remain GPLv3-compatible. Native macOS implementation code will be authored in this repository and will not carry unused Windows-only dependencies.

