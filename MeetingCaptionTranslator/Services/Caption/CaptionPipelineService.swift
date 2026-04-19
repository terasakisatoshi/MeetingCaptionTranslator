import Foundation

@MainActor
final class CaptionPipelineService {
    private var captionStore: CaptionStore
    private let translator: (String) async throws -> String

    private(set) var visibleLines: [CaptionLine] = []
    private(set) var appState: AppState = .idle

    init(
        maximumVisibleLines: Int,
        translator: @escaping (String) async throws -> String
    ) {
        captionStore = CaptionStore(maximumVisibleLines: maximumVisibleLines)
        self.translator = translator
    }

    func handleTranscript(_ event: TranscriptEvent) async {
        appState = .transcribing

        switch event.state {
        case .partial:
            captionStore.ingest(
                sourceText: event.sourceText,
                translatedText: nil,
                state: .partial
            )
        case .final:
            do {
                let translatedText = try await translator(event.sourceText)
                captionStore.ingest(
                    sourceText: event.sourceText,
                    translatedText: translatedText,
                    state: .final
                )
            } catch let error as AppError {
                captionStore.ingest(
                    sourceText: event.sourceText,
                    translatedText: nil,
                    state: .final
                )
                appState = .degraded(reason: error)
            } catch {
                captionStore.ingest(
                    sourceText: event.sourceText,
                    translatedText: nil,
                    state: .final
                )
                appState = .degraded(reason: .translationUnavailable)
            }
        }

        visibleLines = captionStore.visibleLines
    }

    func stop() {
        captionStore.reset()
        visibleLines = []
        appState = .idle
    }
}
