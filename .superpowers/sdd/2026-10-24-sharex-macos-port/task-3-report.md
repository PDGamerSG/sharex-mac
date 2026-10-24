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
