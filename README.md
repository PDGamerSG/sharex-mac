# ShareX Mac

ShareX Mac is an unofficial, native macOS menu-bar app for screenshots and offline text recognition. Capture a screen, region, or window, copy the image or recognized text, and find saved screenshots in local image history. Screenshots and OCR stay on your Mac.

[Download the latest release](https://github.com/PDGamerSG/sharex-mac/releases/latest) · [Download the app ZIP](https://github.com/PDGamerSG/sharex-mac/releases/latest/download/ShareXMac-universal.zip)

## Install

Requires **macOS 13 or newer**. The universal app supports **Apple Silicon and Intel** Macs.

1. Download `ShareXMac-universal.zip` from [Releases](https://github.com/PDGamerSG/sharex-mac/releases).
2. Extract the ZIP and move **ShareX Mac.app** to **Applications**. Quit an older running copy before replacing it.
3. Open the app and choose your screenshot folder. Its controls live in the menu bar.
4. Allow ShareX Mac in **System Settings → Privacy & Security → Screen Recording** (called **Screen & System Audio Recording** on some macOS versions), then reopen the app if requested. macOS requires this permission for still screenshots.

The app is ad-hoc signed and is not Apple-notarized. If macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway** after attempting to open it.

## Default shortcuts

- **Option-P (⌥P):** select a region to capture.
- **Shift-P (⇧P):** select a region to recognize text.
- **Escape:** cancel a region/window selection or capture countdown.

Global shortcuts work while the app is running. In **Settings → Hotkeys**, record a replacement, clear a binding, or choose **Reset all shortcuts** to restore these defaults. Other actions start unassigned. Existing installations keep their saved bindings; use Reset all shortcuts to adopt the new defaults.

## Features

### Screenshots

- Capture all connected displays in one image, a selected region, or a window chosen with the pointer.
- Select across displays, including layouts with different Retina scales.
- Save lossless PNG files in monthly subfolders of your chosen folder, such as `~/Pictures/ShareX/2026-11`, with collision-safe filenames. Folders follow the capture's local month and year and are created as needed; existing screenshots stay in place.
- Keep full pixel resolution, or choose 75% or 50% dimensions for smaller files and clipboard images.
- Copy each successful screenshot to the clipboard automatically, with an option to disable copying.
- Include or hide the cursor and set a capture delay from 0 to 60 seconds with a cancellable countdown.
- See a brief “Screenshot taken” confirmation with **Open Folder** to reveal the saved image in Finder.

### Offline OCR

- Recognize text in a selected region or a screenshot from Image History using Apple Vision.
- Keep OCR captures at full resolution regardless of screenshot output size.
- Edit the result, switch between multiline and single-line text, retry recognition, and copy the text.
- Use automatic language detection or select supported languages, enable language correction, and choose a recognition scale from 1× to 4×.

### Image history

- Browse a local thumbnail grid with filenames, dimensions, and capture dates.
- Search filenames and refresh the list, including missing-file status.
- Preview, open, reveal in Finder, copy the image, copy its path, or run OCR.
- Delete a screenshot and its history entry after confirmation.
- Keep screenshot metadata in a local SQLite database.

### Shortcuts and settings

- Configure global shortcuts for full-screen capture, region capture, window capture, OCR, Image History, and Settings.
- Record single keys or combinations using Command, Control, Option, or Shift, including Option-F9. Playback, volume, and brightness keys can be recorded directly in media mode; these shortcuts may need Accessibility access, with a link to the setting shown if registration fails. Record the keys exactly as you will use them. Holding Fn (Globe) records the standard function key instead.
- Detect duplicate assignments and display macOS registration errors; show configured shortcuts in the menu bar.
- Save preferences and screenshot-folder access across restarts.
- Check screenshot-folder and history-database status and open macOS permission settings.
- Enable launch at login and start hidden in the menu bar.

The app is local-only, with no accounts, uploads, or network services. This focused implementation does not include screen recording, image editing/annotation, or ShareX workflow automation. See [NOTICE](NOTICE) and [LICENSE](LICENSE) for attribution and GPLv3 licensing.

## Build and test

Development requires Swift 6 and the macOS SDK. Run the test suite with:

```sh
swift test --build-system native
```

Build the executable with `swift build --build-system native --product ShareXMac`. To stage a signed or ad-hoc universal bundle, run `scripts/build-release.sh --dry-run` first, then run it on a machine with the required macOS SDK, `iconutil`, signing identity, and (for notarization) a configured `notarytool` keychain profile. The script builds arm64 and x86_64 separately using macOS 13 triples and combines them with `lipo`.

Manual acceptance checks are listed in [docs/testing/macOS-manual-matrix.md](docs/testing/macOS-manual-matrix.md).
