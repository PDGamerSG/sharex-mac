import Foundation

/// The owner invokes every driver method on one serial queue. Completion
/// handlers may arrive on any queue; they only enqueue state transitions.
protocol CaptureStreamDriver: AnyObject, Sendable {
    func install() throws
    func start(completion: @escaping @Sendable (Error?) -> Void)
    func stop(completion: @escaping @Sendable () -> Void)
    func remove()
}

enum CaptureStreamLifecycleError: Error, Equatable, LocalizedError {
    case timedOut

    var errorDescription: String? { "No screenshot frame arrived before the capture timed out." }
}

/// Queue ownership covers both the continuation and the stream operations.
/// In particular, teardown cannot overtake an outstanding start operation.
final class CaptureStreamLifecycle<Value: Sendable>: @unchecked Sendable {
    private let driver: any CaptureStreamDriver
    private let queue: DispatchQueue
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var installed = false
    private var starting = false
    private var started = false
    private var stopping = false
    private var deadline: DispatchWorkItem?

    init(driver: any CaptureStreamDriver, queue: DispatchQueue, timeout: TimeInterval = 10) {
        self.driver = driver
        self.queue = queue
        self.timeout = timeout
    }

    func capture() async throws -> Value {
        try await withTaskCancellationHandler {
            let cancelled = Task.isCancelled
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if cancelled { self.finish(.failure(CancellationError())) }
                    if let result = self.result {
                        continuation.resume(with: result)
                        return
                    }
                    self.continuation = continuation
                    self.begin()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        receive(.failure(CancellationError()))
    }

    func receive(_ result: Result<Value, Error>) {
        queue.async { self.finish(result) }
    }

    private func begin() {
        do {
            try driver.install()
            installed = true
        } catch {
            finish(.failure(error))
            return
        }
        let deadline = DispatchWorkItem { [weak self] in
            self?.finish(.failure(CaptureStreamLifecycleError.timedOut))
        }
        self.deadline = deadline
        queue.asyncAfter(deadline: .now() + timeout, execute: deadline)
        starting = true
        driver.start { error in
            self.queue.async {
                self.starting = false
                if let error {
                    self.finish(.failure(error))
                    // Even if cancellation already won, failed start still
                    // releases the installed output.
                    self.removeOutput()
                } else {
                    self.started = true
                    self.tearDownIfReady()
                }
            }
        }
    }

    private func finish(_ result: Result<Value, Error>) {
        guard self.result == nil else { return }
        self.result = result
        deadline?.cancel()
        deadline = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
        tearDownIfReady()
    }

    private func tearDownIfReady() {
        guard result != nil, installed, !starting, !stopping else { return }
        guard started else { removeOutput(); return }
        stopping = true
        driver.stop {
            self.queue.async { self.removeOutput() }
        }
        // The result already reached the caller. Do not retain an output
        // indefinitely if the platform fails to acknowledge stopCapture.
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.removeOutput()
        }
    }

    private func removeOutput() {
        guard installed else { return }
        installed = false
        driver.remove()
    }
}
