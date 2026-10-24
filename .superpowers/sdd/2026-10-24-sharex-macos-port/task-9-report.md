# Task 9 — configurable global hotkeys

Implemented the seven stable actions using Carbon Event Hot Keys, with a main-actor manager and an action callback. No event taps, Accessibility APIs, or global event monitors are used.

## Changes

- Split `HotkeyBinding` into its own file. New persistence stores physical Carbon key codes and modifier flags; legacy `key`/`modifiers` JSON and the string initializer remain supported, including command/cmd, option/alt, control/ctrl, and modifier-symbol aliases.
- Reject duplicate physical shortcuts, unknown legacy keys/modifiers, unsupported flags/keycodes, and shortcuts without Command, Control, or Option. Empty bindings remain valid and code zero remains a valid bound key.
- Validate before replacing an existing registration set. Carbon registration failures populate per-action `registrationErrors` and aggregate `registrationError`, while unaffected shortcuts remain registered.
- Unregister Carbon handles on clear, reset, replacement, and resource destruction. Dispatch only successfully registered action IDs.
- Add `HotkeySettingsView(settingsModel:manager:)` with a native AppKit key recorder, per-action Clear, Reset Shortcuts, duplicate/validation feedback, and per-action macOS conflict messages.
- Recording temporarily releases hotkeys. An app-local key-down monitor records Command menu equivalents; completion, cancellation, focus loss, window resign, and view removal restore persisted registrations. Escape cancels; unmodified Delete clears.
- Reset retains the existing all-unassigned defaults. UI explains that reset clears all seven shortcuts, avoiding unsolicited reservation of system shortcuts.

## Verification

Test-first evidence:

1. Wrote the modern-keycode decode test against the original binding implementation. `swift test --scratch-path /tmp/sharex-hotkeys-build --filter HotkeyBindingTests` built and failed as expected: modern JSON decoded to nil, losing the physical key. This was a behavioral red failure, not a compile failure.
2. Added tests for legacy alias migration/duplicate rejection, clear/reset, physical key zero and AppSettings Codable round trips, invalid bindings, partial registration failure, preserving working registrations on invalid replacement, and release/re-register before adding the implementation. Added the native Carbon integration test afterward to characterize real API conflict/release and callback behavior. The expanded binding tests initially also demonstrated the missing API at compile time (`/tmp/sharex-hotkeys-red.log`).
3. `swift test --scratch-path /tmp/sharex-hotkeys-build --filter 'HotkeyBindingTests|GlobalHotkeyManagerTests'` passed all **9 tests** (0 failures). The native integration test registered Hyper+F19, verified a real duplicate Carbon registration fails, sent a targeted Carbon hotkey event through the installed callback, released registration, and verified another manager can register it. `/tmp/sharex-hotkeys-green.log` contains the final focused run.
4. `swift build --scratch-path /tmp/sharex-hotkeys-build` passed for the complete app (3.05 seconds), including the recorder UI. `/tmp/sharex-hotkeys-final-build.log` contains the result.
5. The root agent also reported its focused integration batch passed **25 tests** (`/tmp/sharex-focused-green.log`); full-suite regression verification remains owned by the root agent after task commits.
6. `git diff --check` passed.

The default SDK 27 introduces a same-name SwiftUI State macro whose plugin is missing in Command Line Tools. The recorder uses the root agent's `ViewState` alias to select the existing SwiftUI property wrapper while retaining the macOS 13 target. No SDK change is required.

Existing warnings remain from the deprecated swift-testing package, Command Line Tools linker search paths, and an AppCoordinator capture warning outside this task's scope.

## Interfaces and integration

`GlobalHotkeyManager(actionHandler:)` is main-actor isolated. `register([HotkeyAction: HotkeyBinding]) throws` throws validation errors; operating-system registration errors are collected per binding, without aborting other registrations. `unregisterAll()` releases handles and clears errors. The root agent owns startup registration and settings subscriptions.

No AppSettings, AppCoordinator, menu, or other settings UI source was edited by this task.

## Limits

Physical keyboard interaction with the visible recorder and actual OS-delivered hotkey presses remain manual smoke checks. Automated native verification covers Carbon registration/conflict/release and installed callback dispatch using a Carbon event, without synthesizing hardware input. Shortcut labels currently use stable ANSI-position names rather than translating labels to the active keyboard layout; physical codes remain correct across restarts.
