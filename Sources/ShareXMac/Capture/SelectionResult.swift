import AppKit

/// Every display completes the same result, at most once.
@MainActor
final class SelectionResult<Value: Sendable> {
    private var continuation: CheckedContinuation<Value?, Never>?
    private var finished = false
    private var result: Value?

    func wait() async -> Value? {
        if Task.isCancelled { finish(nil) }
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if finished { continuation.resume(returning: result) }
                else { self.continuation = continuation }
            }
        }, onCancel: {
            Task { @MainActor in self.finish(nil) }
        })
    }

    func finish(_ result: Value?) {
        guard !finished else { return }
        finished = true
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}
