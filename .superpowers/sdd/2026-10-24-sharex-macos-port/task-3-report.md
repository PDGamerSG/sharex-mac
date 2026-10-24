# Task 3 report

Implemented local SQLite screenshot history storage.

## Commands and results

- `swift test --filter SQLiteScreenshotStoreTests` (before implementation): failed as expected against the initial stub, with schema, persistence, search, missing-file, and duplicate-ID assertions failing.
- `swift test --filter SQLiteScreenshotStoreTests`: passed, 8 tests.
- `swift test`: passed, 23 tests.

## Implementation

- Added `ScreenshotStore` and `ScreenshotHistoryEntry`.
- Added actor-backed `SQLiteScreenshotStore` with schema creation, bound SQLite parameters, ISO-independent Unix date encoding, newest-first ordering, literal case-insensitive filename search, missing-file detection at read time, row/file deletion, and duplicate-ID errors.
- Added focused integration tests covering schema creation, metadata persistence, ordering, search, missing files, deletion, and SQL-special search input.

SQLite emitted the existing environment linker search-path warnings for CommandLineTools; tests still completed successfully.

## Review fixes

- `list` and `record(for:)` now distinguish `SQLITE_DONE` from SQLite read errors and throw on failures.
- Added actor-isolated `close()` for explicit SQLite connection shutdown; operations after close report a closed database error.
- Filename matching now loads rows and performs Unicode-aware, filename-only matching in Swift.
- File deletion tolerates only missing-file errors and propagates other filesystem failures.
- Added Unicode filename, equal-timestamp ordering, and close lifecycle tests.

Fix verification:

- `swift test --filter SQLiteScreenshotStoreTests`: 11 tests passed.
- `swift test`: 26 tests passed.

## Review round 2 fix

- Added privately owned `SQLiteConnectionHolder` marked `@unchecked Sendable`; its deinitializer closes the native handle automatically.
- Explicit actor `close()` delegates to the holder and remains idempotent; all operations reject after closure.
- Added deterministic holder deinitialization coverage.

Verification:

- `swift test --filter SQLiteScreenshotStoreTests`: 12 tests passed.
- `swift test`: 27 tests passed.
