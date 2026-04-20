import Combine
import Foundation

struct OverlayRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceText: String
    let translatedText: String?
    let state: CaptionLineState
}

@MainActor
final class OverlayViewModel: ObservableObject {
    @Published private(set) var rows: [OverlayRow] = []
    @Published private(set) var overlayOpacity: Double
    @Published private(set) var fontSize: Double
    @Published private(set) var overlayWidth: Double
    @Published private(set) var overlayHeight: Double
    @Published private(set) var maximumVisibleLines: Int
    @Published private(set) var statusText: String

    init(settings: AppSettings, statusText: String = AppState.idle.statusText) {
        overlayOpacity = settings.overlayOpacity
        fontSize = settings.fontSize
        overlayWidth = settings.overlayWidth
        overlayHeight = settings.overlayHeight
        maximumVisibleLines = settings.maximumVisibleLines
        self.statusText = statusText
    }

    func apply(settings: AppSettings) {
        overlayOpacity = settings.overlayOpacity
        fontSize = settings.fontSize
        overlayWidth = settings.overlayWidth
        overlayHeight = settings.overlayHeight
        maximumVisibleLines = settings.maximumVisibleLines
    }

    func render(lines: [CaptionLine], appState: AppState) {
        rows = lines.map { line in
            OverlayRow(
                id: line.id,
                sourceText: line.sourceText,
                translatedText: line.translatedText,
                state: line.state
            )
        }
        statusText = appState.statusText
    }
}
