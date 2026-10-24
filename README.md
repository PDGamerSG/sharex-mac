# ShareX Mac

ShareX Mac is an unofficial, local-only native macOS 13+ menu-bar screenshot utility. It keeps the requested ShareX subset: all-display, region, and click-to-select window screenshots; configurable global hotkeys; offline Vision OCR; a screenshot folder; local SQLite history and image history; and focused capture/OCR/settings controls.

It copies each successful screenshot to the clipboard by default; this can be disabled in Capture settings. It deliberately has no screen recording, uploads, workflows, tools/editor, last-region or auto-capture modes, destinations, after-capture tasks, debug/donate/follow/about pages, or network services. See [NOTICE](NOTICE) and [LICENSE](LICENSE) for attribution and licensing.

The package requires Swift 6 and macOS 13 or newer. Run the test suite with:

```sh
swift test --build-system native
```

Build the executable with `swift build --build-system native --product ShareXMac`. To stage a signed or ad-hoc universal bundle, run `scripts/build-release.sh --dry-run` first, then run it on a machine with the required macOS SDK, `iconutil`, signing identity, and (for notarization) a configured `notarytool` keychain profile. The script builds arm64 and x86_64 separately using macOS 13 triples and combines them with `lipo`.

Screen Recording permission is required by macOS for still screen/window capture. The app gives a direct Privacy & Security link and stores screenshots only in the chosen folder; no capture leaves the device.

Manual acceptance checks are listed in [docs/testing/macOS-manual-matrix.md](docs/testing/macOS-manual-matrix.md).
