# Task 4 report: ScreenCaptureKit capture service

Implemented display/window capture and pure capture utilities.

## Changes

- Added `DisplayCompositor` with logical display frame/origin and backing-scale aware pixel-space composition.
- Added `CaptureFileWriter` with timestamped `ShareX_yyyy-MM-dd_HH-mm-ss.png` names, numeric collision suffixes, temporary PNG encoding, and atomic same-volume move.
- Added `ScreenCaptureService` using ScreenCaptureKit shareable display/window content and one-frame async stream output, with cursor configuration and display scale discovery.
- Added focused compositor and writer tests covering mixed scales/negative origins, collision suffixes, PNG readability, and temporary-file cleanup.

## TDD and verification

1. Initial focused test run after adding tests, before production files:
   `swift test --filter 'DisplayCompositorTests|CaptureFileWriterTests'`
   Failed at compile time with missing `DisplayCompositor` symbols as expected.
2. Focused tests after implementation:
   `swift test --filter 'DisplayCompositorTests|CaptureFileWriterTests'`
   Passed: 3 tests.
3. Full test suite:
   `swift test`
   Passed: 30 tests.
4. Package build:
   `swift build`
   Passed.

The compiler/linker emitted existing SDK search-path warnings for CommandLineTools framework paths and Swift Testing deprecation warnings; they did not affect results.

## Review fix round

Addressed the Task 4 review with the following changes:

- Replaced the detached startup task with `CaptureStreamLifecycle`, which owns all stream operations and terminal state on one serial queue. The ScreenCaptureKit driver uses completion handlers so startup cannot be overtaken by teardown. Cancellation before continuation installation does not start a stream; cancellation/timeout during startup returns promptly and stops/removes output when the outstanding start completes. Start failures remove output, delegate failures terminate the await, and a ten-second no-frame deadline prevents indefinite capture waits. Stop acknowledgments and fallback cleanup remove output once.
- Added permission-free injected lifecycle tests for cancellation before installation, cancellation during startup, startup errors, delegate errors, exactly one terminal result, no-frame timeout, late startup success, missing stop acknowledgment, and late acknowledgment after cleanup. Added SCFrameStatus handling: complete frames are captured; started/idle/blank/suspended statuses wait for a complete frame; stopped or malformed/invalid samples terminate with an error.
- Window captures use `SCContentFilter.pointPixelScale` on macOS 14+ and active display backing scale on macOS 13. Display scale discovery now uses `CGDisplayMode.pixelWidth / width`: this host reports logical `CGDisplayPixelsWide` values even in Retina modes.
- Replaced the process-only writer lock and `FileManager.moveItem` publication with `renamex_np(..., RENAME_EXCL)`. A complete same-directory temporary PNG is published atomically without overwriting a destination, including another process's winner or a dangling symlink. Only the kernel's `EEXIST` is treated as a naming collision; other failures propagate. Temporary cleanup covers encode and publication errors. The formatter is local to each call.
- Corrected compositor Y placement from CG top-left logical frames to CGContext coordinates using `bounds.maxY - display.frame.maxY`. Expanded mixed-scale/origin and gap assertions, and added a labeled 2×2 source pattern to detect internal image inversion.

### Verification commands and results

- `swift build --build-system native --target ShareXMacCoreTests` before adding the lifecycle implementation: failed with missing `CaptureStreamDriver` / `CaptureStreamLifecycle` symbols, as expected (log `/tmp/sharex-task4-test-target-red.log`).
- The same test-target build before implementing exclusive publication: failed with `CaptureFileWriter` having no member `moveExclusively`, as expected (log `/tmp/sharex-task4-publish-red.log`).
- `swift test --filter 'CaptureStreamLifecycleTests|CaptureFileWriterTests|DisplayCompositorTests'` before correcting compositor Y: failed with five top-left placement expectations while the other focused tests passed (log `/tmp/sharex-task4-default-tests.log`).
- The same focused command after the Y fix: **14 tests passed** (log `/tmp/sharex-task4-focused-green.log`).
- `swift test --build-system native --filter 'CaptureStreamLifecycleTests|CaptureFileWriterTests|DisplayCompositorTests'` after adding the final timeout/status cases: **16 tests passed** (log `/tmp/sharex-task4-native-focused.log`).
- `swift -e 'import CoreGraphics; let id = CGMainDisplayID(); let mode = CGDisplayCopyDisplayMode(id); print("display logical bounds:", CGDisplayBounds(id)); print("CGDisplayPixelsWide:", CGDisplayPixelsWide(id)); print("mode width/pixelWidth:", mode?.width as Any, mode?.pixelWidth as Any)'`: reported logical width **1728**, CGDisplayPixelsWide **1728**, mode width/pixelWidth **1728 / 3456**, reproducing why the previous scale discovery incorrectly yielded 1×.
- `swift test --build-system native`: final Task 4 production and test files compiled, but the full rebuild was blocked by concurrently added Task 6 `CaptureCoordinatorTests.swift` referencing not-yet-implemented `CaptureCoordinator` and `CapturedImage` symbols (log `/tmp/sharex-task4-full.log`). No Task 6 files were modified in this fix round.
- `swift test --build-system native --skip-build`: the most recently built complete test executable ran **49 tests successfully** (log `/tmp/sharex-task4-last-built-suite.log`). This executable predates the concurrently added Task 6 tests; this is not a claim that those new tests pass.
- `swift build --build-system native`: **passed**, including the final Retina scale discovery fix (log `/tmp/sharex-task4-build-final.log`).
- `git diff --check`: **passed**.

### Remaining validation limits

Real ScreenCaptureKit capture still needs an interactive Screen Recording permission grant and manual validation on macOS 13 plus a mixed-scale desktop. Automated tests exercise the shared lifecycle using injected drivers and frame status decisions without requesting that permission. The full current-suite rebuild must be repeated after the concurrent Task 6 implementation is available. If ScreenCaptureKit never acknowledges an outstanding start at all, the caller still times out; teardown is retained and runs when that callback arrives, avoiding a stop/start race.

### Final full-suite verification after concurrent Task 6 production files arrived

`swift test --build-system native` rebuilt the current source tree and **all 55 tests passed**, including all 16 Task 4 focused tests and the new coordinator tests (log `/tmp/sharex-task4-full-final.log`). This resolves the transient full-suite compilation limitation noted above. The interactive Screen Recording/macOS 13 hardware validation limits remain.
