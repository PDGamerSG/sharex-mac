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
