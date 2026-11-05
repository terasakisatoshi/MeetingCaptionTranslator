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
        appState = .transcribing
        flushTask?.cancel()
        flushTask = nil

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
            guard !Task.isCancelled, let self, let text = self.sentenceBuffer.flush() else { return }
            self.flushTask = nil
            await self.translateAndIngest(text)
            self.publishLines()
            self.onUpdate?()
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
