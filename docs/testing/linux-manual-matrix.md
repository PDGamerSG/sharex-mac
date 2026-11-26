# ShareX Linux manual acceptance matrix

Run these checks on each supported desktop session. The automated Linux suite covers the Foundation core without a graphical session.

| Area | Wayland | X11 | Expected result |
| --- | --- | --- | --- |
| Launch | GNOME, KDE, Sway, or Hyprland | GNOME, KDE, XFCE, or another X11 session | The GTK window opens and the application ID is `io.github.PDGamerSG.ShareXLinux`. |
| Full-screen capture | `grim` or the Screenshot portal | `maim`, `gnome-screenshot`, or ImageMagick | A PNG is saved in the configured monthly folder and appears in Image History. |
| Region capture | `slurp` plus `grim`, or the Screenshot portal | `maim` or `gnome-screenshot` | The selected rectangle is captured. Escape or closing the picker leaves no history row. |
| Window capture | Sway/Hyprland window list plus `slurp`, or the portal | `maim`, or ImageMagick with `xdotool` | The selected window is captured without switching to a freehand region. |
| Cursor setting | `grim` honors the setting. Portal behavior follows the desktop policy. | `maim` and `gnome-screenshot` honor the setting. | The cursor is present only when enabled where the backend supports the option. |
| Delay and cancellation | Set a delay, then cancel the countdown | Set a delay, then cancel the countdown | The app returns to the main window and does not create a file or history row. |
| Clipboard image | `wl-copy` | `xclip` | A successful capture is available as `image/png` in the clipboard. Disable the setting and verify the existing clipboard remains unchanged. |
| OCR | Tesseract with installed language data | Tesseract with installed language data | OCR runs offline, opens an editable result, and copies non-empty text. Retry and single-line mode work. |
| OCR capture resolution | Any screenshot resolution | Any screenshot resolution | OCR source pixels remain full resolution even when regular screenshots use 75% or 50%. |
| History | Browse, search, preview, copy, reveal, OCR, delete | Browse, search, preview, copy, reveal, OCR, delete | Missing files are marked. Delete removes the image and row after confirmation. |
| Settings | Change folder, delay, resolution, OCR, and shortcuts | Change folder, delay, resolution, OCR, and shortcuts | Settings survive restart and remain under the XDG configuration/data directories. |
| Shortcuts | GlobalShortcuts portal, with compositor setup guidance when unavailable | Keybinder3 | Multiple bindings per action work. Duplicate bindings are rejected independently. |
| Start at login | Enable Launch at login and Start hidden | Enable Launch at login and Start hidden | The XDG autostart entry starts the app and honors the hidden setting. |
| Missing dependency | Temporarily hide `grim`, `slurp`, `tesseract`, or `wl-copy` | Temporarily hide `maim`, `xdotool`, `tesseract`, or `xclip` | The status/error message names the missing package or helper and leaves existing files/history intact. |
| Multi-display | Two displays with different scales | Two displays with different layouts | Full-screen capture includes all active displays where the backend supports it. |

## Paths to inspect

- Settings: `$XDG_CONFIG_HOME/sharex/sharex-linux.json`, defaulting to `~/.config/sharex/sharex-linux.json`.
- History: `$XDG_DATA_HOME/sharex/history.sqlite`, defaulting to `~/.local/share/sharex/history.sqlite`.
- Screenshots: the configured folder, defaulting to `~/Pictures/ShareX`.
- Autostart: `$XDG_CONFIG_HOME/autostart/io.github.PDGamerSG.ShareXLinux.desktop`.
