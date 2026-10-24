# macOS manual verification matrix

Automated tests cover the core models, SQLite migration, compositor, writer, capture lifecycle, Vision OCR, and Carbon registration. Run the following on physical macOS 13+ hardware with the signed app bundle.

| Area | Check | Expected result |
| --- | --- | --- |
| Build | Open the app bundle on arm64 and Intel Macs | Menu-bar app launches without a Dock window; universal binary reports both architectures with `lipo -info` |
| Permission | Deny Screen Recording, invoke a capture, then open the provided System Settings button | No partial file/history row; actionable permission guidance appears |
| Folder | First launch and a stale/moved bookmark | Folder picker suggests `~/Pictures/ShareX`; a security-scoped bookmark is saved and refreshed; cancellation leaves capture unavailable |
| Full screen | Connect two displays with different scales and negative origins; invoke full-screen capture | One PNG contains every display in the correct arrangement and pixel scale |
| Cursor/delay | Enable cursor and use 0, 1, and 60 second delays; press Escape during countdown | Cursor setting is reflected; countdown is cancellable; history stores cursor/delay metadata |
| Clipboard | Capture full screen, a region, and a window with clipboard copy enabled; paste into an image-capable app; disable the setting and repeat | The captured PNG is pasted automatically when enabled; disabling the setting leaves the existing pasteboard unchanged |
| Confirmation | Capture a full screen, region, and window | A non-interactive “Screenshot taken” confirmation appears in the bottom-right corner for about three seconds after the PNG is saved |
| Quality | Capture at Full resolution, then repeat at 75% and 50% | Full resolution preserves captured pixel dimensions and lossless PNG output; reduced settings scale the saved and clipboard image dimensions; OCR remains full resolution |
| Region | Drag on each display, including a cross-display area; press Escape | Frozen desktop is shown; crop maps to the saved image; Escape creates no file or row |
| Window | Invoke window capture and click a visible app window on each display | Picker highlights windows, excludes ShareX Mac, and saves the selected window with title/application metadata |
| OCR | Invoke OCR region capture and run OCR from image history; edit and copy text | Vision recognizes offline, preserves reading order, supports single-line output, and Copy puts editable text on the pasteboard |
| History | Search, preview, open, reveal, copy path, OCR, delete, and remove a file externally | List and thumbnail grid share the same rows; missing files remain visible; delete confirmation is required |
| Hotkeys | Record all seven actions, duplicate a combination, clear/reset, restart, and press shortcuts globally | Valid bindings persist and dispatch; duplicate/conflicting bindings report the action; clear/reset releases Carbon handles; configured shortcuts are shown beside menu-bar actions and the Hotkeys tab is grouped into Capture and App navigation |
| Settings | Toggle cursor/delay/OCR language/scale/correction, launch-at-login, and start hidden | Values persist across restart; unsupported permission/login states show the provided guidance |
| Scope audit | Inspect menu and Settings | No recording, upload, workflow, tools/editor, last-region, auto-capture, destination, after-capture, debug, donate, follow, discard, or about UI |

Record OS version, Mac model, display arrangement, permission state, and any failed row when reporting results. A GUI session is required for these checks; the package test suite cannot validate ScreenCaptureKit TCC prompts or physical pointer/keyboard interaction.
