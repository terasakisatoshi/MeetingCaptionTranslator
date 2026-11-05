import Foundation

@MainActor
final class CaptionPipelineService {
    // How long unfinished text waits for its sentence to end before it is translated anyway.
    static let flushDelay: Duration = .seconds(2)

    private var captionStore: CaptionStore
    private let translator: (String) async throws -> String
    private let flushSleep: @MainActor (Duration) async throws -> Void
    private var sentenceBuffer = SentenceBuffer()
    private var flushTask: Task<Void, Never>?
    // Transcripts and flushes run one at a time, in arrival order, so a translation that finishes
    // late cannot land after, or overwrite, the lines of a newer transcript.
    private var lastOperation: Task<Void, Never>?
    private var generation = 0

    private(set) var visibleLines: [CaptionLine] = []
    private(set) var historyLines: [CaptionLine] = []
    private(set) var appState: AppState = .idle

    // Called when lines change outside `handleTranscript`, after a quiet-period flush.
    var onUpdate: (@MainActor () -> Void)?

    init(
        maximumVisibleLines: Int,
        flushSleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        translator: @escaping (String) async throws -> String
    ) {
        captionStore = CaptionStore(maximumVisibleLines: maximumVisibleLines)
        self.flushSleep = flushSleep
        self.translator = translator
    }

    func handleTranscript(_ event: TranscriptEvent) async {
        flushTask?.cancel()
        flushTask = nil
        await enqueue { pipeline in
            await pipeline.process(event)
        }
    }

    private func enqueue(_ operation: @escaping @MainActor (CaptionPipelineService) async -> Void) async {
        let previous = lastOperation
        let generation = generation
        let task = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == generation else { return }
            await operation(self)
        }
        lastOperation = task
        await task.value
    }

    private func process(_ event: TranscriptEvent) async {
        appState = .transcribing

        switch event.state {
        case .partial:
            captionStore.ingest(
                sourceText: sentenceBuffer.joined(with: event.sourceText),
                translatedText: nil,
                state: .partial
            )
        case .final:
            let sentences = sentenceBuffer.append(event.sourceText)
            let rest = sentenceBuffer.pending
            for sentence in sentences {
                await translateAndIngest(sentence)
            }
            if !rest.isEmpty {
                captionStore.ingest(sourceText: rest, translatedText: nil, state: .partial)
                scheduleFlush()
            }
        }

        publishLines()
    }

    func stop() {
        flushTask?.cancel()
        flushTask = nil
        generation += 1
        lastOperation = nil
        sentenceBuffer = SentenceBuffer()
        captionStore.reset()
        visibleLines = []
        historyLines = []
        appState = .idle
    }

    func updateMaximumVisibleLines(_ maximumVisibleLines: Int) {
        captionStore.updateMaximumVisibleLines(maximumVisibleLines)
        publishLines()
    }

    private func scheduleFlush() {
        flushTask = Task { [weak self, flushSleep] in
            do {
                try await flushSleep(Self.flushDelay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.flushTask = nil
            await self.enqueue { pipeline in
                guard let text = pipeline.sentenceBuffer.flush() else { return }
                await pipeline.translateAndIngest(text)
                pipeline.publishLines()
                pipeline.onUpdate?()
            }
        }
    }

    private func translateAndIngest(_ text: String) async {
        do {
            let translatedText = try await translator(text)
            captionStore.ingest(sourceText: text, translatedText: translatedText, state: .final)
        } catch let error as AppError {
            captionStore.ingest(sourceText: text, translatedText: nil, state: .final)
            appState = .degraded(reason: error)
        } catch {
            captionStore.ingest(sourceText: text, translatedText: nil, state: .final)
            appState = .degraded(reason: .translationUnavailable)
        }
    }

    private func publishLines() {
        visibleLines = captionStore.visibleLines
        historyLines = captionStore.historyLines
    }
}
