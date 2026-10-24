import Foundation
import ScreenCaptureKit
import Testing
@testable import ShareXMacCore

@Suite("Single frame capture lifecycle")
struct CaptureStreamLifecycleTests {
    @Test("cancellation before installation never starts a stream")
    func cancelledBeforeInstall() async {
        let queue = DispatchQueue(label: "capture-test.pre-cancel")
        let driver = TestStreamDriver()
        let lifecycle = CaptureStreamLifecycle<Int>(driver: driver, queue: queue)
        lifecycle.cancel()
        await #expect(throws: CancellationError.self) { try await lifecycle.capture() }
        #expect(queue.sync { driver.events }.isEmpty)
    }

    @Test("cancellation during start waits for start completion before stopping")
    func cancellationDuringStart() async throws {
        let queue = DispatchQueue(label: "capture-test.start-cancel")
        let driver = TestStreamDriver()
        let lifecycle = CaptureStreamLifecycle<Int>(driver: driver, queue: queue)
        let task = Task { try await lifecycle.capture() }
        try await waitForStart(driver, queue)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(queue.sync { driver.events } == ["install", "start"])
        queue.sync { driver.completeStart(nil) }
        queue.sync {}
        #expect(queue.sync { driver.events } == ["install", "start", "stop"])
        queue.sync { driver.completeStop() }
        queue.sync {}
        #expect(queue.sync { driver.events } == ["install", "start", "stop", "remove"])
    }

    @Test("timeout returns without a frame and late start success still tears down")
    func timeoutDuringStart() async throws {
        let queue = DispatchQueue(label: "capture-test.timeout")
        let driver = TestStreamDriver()
        let lifecycle = CaptureStreamLifecycle<Int>(driver: driver, queue: queue, timeout: 0.05)
        await #expect(throws: CaptureStreamLifecycleError.timedOut) { try await lifecycle.capture() }
        queue.sync { driver.completeStart(nil) }
        queue.sync {}
        queue.sync { driver.completeStop() }
        queue.sync {}
        #expect(queue.sync { driver.events } == ["install", "start", "stop", "remove"])
    }

    @Test("start errors remove output and propagate the original error")
    func startFailure() async throws {
        let queue = DispatchQueue(label: "capture-test.start-error")
        let driver = TestStreamDriver()
        let lifecycle = CaptureStreamLifecycle<Int>(driver: driver, queue: queue)
        let task = Task { try await lifecycle.capture() }
        try await waitForStart(driver, queue)
        queue.sync { driver.completeStart(TestFailure()) }
        await #expect(throws: TestFailure.self) { try await task.value }
        #expect(queue.sync { driver.events } == ["install", "start", "remove"])
    }

    @Test("one frame wins over a later delegate error and removes output once")
    func singleTerminalResult() async throws {
        let queue = DispatchQueue(label: "capture-test.frame")
        let driver = TestStreamDriver()
        let lifecycle = CaptureStreamLifecycle<Int>(driver: driver, queue: queue)
        let task = Task { try await lifecycle.capture() }
        try await waitForStart(driver, queue)
        queue.sync { driver.completeStart(nil) }
        lifecycle.receive(.success(42))
        lifecycle.receive(.failure(TestFailure()))
        #expect(try await task.value == 42)
        queue.sync { driver.completeStop() }
        queue.sync {}
        #expect(queue.sync { driver.events } == ["install", "start", "stop", "remove"])
    }

    @Test("delegate errors terminate an active capture and stop the stream")
    func delegateFailure() async throws {
        let queue = DispatchQueue(label: "capture-test.delegate-error")
        let driver = TestStreamDriver()
        let lifecycle = CaptureStreamLifecycle<Int>(driver: driver, queue: queue)
        let task = Task { try await lifecycle.capture() }
        try await waitForStart(driver, queue)
        queue.sync { driver.completeStart(nil) }
        lifecycle.receive(.failure(TestFailure()))
        await #expect(throws: TestFailure.self) { try await task.value }
        queue.sync { driver.completeStop() }
        queue.sync {}
        #expect(queue.sync { driver.events } == ["install", "start", "stop", "remove"])
    }

    @Test("no-frame timeout stops an active stream and removes output even without a stop acknowledgment")
    func timeoutAfterStart() async throws {
        let queue = DispatchQueue(label: "capture-test.active-timeout")
        let driver = TestStreamDriver()
        let lifecycle = CaptureStreamLifecycle<Int>(driver: driver, queue: queue, timeout: 0.03)
        let task = Task { try await lifecycle.capture() }
        try await waitForStart(driver, queue)
        queue.sync { driver.completeStart(nil) }
        await #expect(throws: CaptureStreamLifecycleError.timedOut) { try await task.value }
        for _ in 0..<1_000 {
            if queue.sync(execute: { driver.events.contains("remove") }) { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(queue.sync { driver.events } == ["install", "start", "stop", "remove"])
        // An acknowledgment arriving after fallback cleanup cannot remove twice.
        queue.sync { driver.completeStop() }
        queue.sync {}
        #expect(queue.sync { driver.events.filter { $0 == "remove" }.count } == 1)
    }

    @Test("only complete frames are captured while transition statuses wait")
    func frameStatuses() {
        #expect(ScreenCaptureFrameDisposition(status: .complete) == .capture)
        for status: SCFrameStatus in [.started, .idle, .blank, .suspended] {
            #expect(ScreenCaptureFrameDisposition(status: status) == .wait)
        }
        #expect(ScreenCaptureFrameDisposition(status: .stopped) == .fail)
    }

    private func waitForStart(_ driver: TestStreamDriver, _ queue: DispatchQueue) async throws {
        for _ in 0..<1_000 {
            if queue.sync(execute: { driver.events.contains("start") }) { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw TestFailure()
    }
}

private struct TestFailure: Error {}

// All state is owned by the injected serial queue, including test inspection.
private final class TestStreamDriver: CaptureStreamDriver, @unchecked Sendable {
    var events: [String] = []
    private var startCompletion: (@Sendable (Error?) -> Void)?
    private var stopCompletion: (@Sendable () -> Void)?

    func install() throws { events.append("install") }
    func start(completion: @escaping @Sendable (Error?) -> Void) {
        events.append("start")
        startCompletion = completion
    }
    func stop(completion: @escaping @Sendable () -> Void) {
        events.append("stop")
        stopCompletion = completion
    }
    func remove() { events.append("remove") }
    func completeStart(_ error: Error?) { startCompletion?(error); startCompletion = nil }
    func completeStop() { stopCompletion?(); stopCompletion = nil }
}
