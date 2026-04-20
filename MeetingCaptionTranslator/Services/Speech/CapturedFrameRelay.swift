import Foundation

final class CapturedFrameRelay: @unchecked Sendable {
    private let continuation: AsyncStream<CapturedAudioFrame>.Continuation
    private let processingTask: Task<Void, Never>
    private let lock = NSLock()
    private var isStopped = false

    init(processor: @escaping @Sendable (CapturedAudioFrame) async -> Void) {
        var streamContinuation: AsyncStream<CapturedAudioFrame>.Continuation?
        let stream = AsyncStream(CapturedAudioFrame.self) { continuation in
            streamContinuation = continuation
        }

        continuation = streamContinuation!
        processingTask = Task {
            for await frame in stream {
                await processor(frame)
            }
        }
    }

    func enqueue(_ frame: CapturedAudioFrame) {
        guard !isCurrentlyStopped() else {
            return
        }

        continuation.yield(frame)
    }

    func stop() async {
        guard markStoppedIfNeeded() else {
            return
        }

        continuation.finish()
        await processingTask.value
    }

    private func isCurrentlyStopped() -> Bool {
        lock.lock()
        let isStopped = isStopped
        lock.unlock()
        return isStopped
    }

    private func markStoppedIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isStopped else {
            return false
        }

        isStopped = true
        return true
    }
}
