import Foundation

struct CaptionStore {
    private let maximumVisibleLines: Int
    private(set) var visibleLines: [CaptionLine] = []

    init(maximumVisibleLines: Int) {
        self.maximumVisibleLines = max(1, maximumVisibleLines)
    }

    @discardableResult
    mutating func ingest(
        sourceText: String,
        translatedText: String?,
        state: CaptionLineState,
        at date: Date = Date()
    ) -> CaptionLine {
        let nextLine: CaptionLine

        if let current = visibleLines.last, current.state == .partial {
            nextLine = current.updating(sourceText: sourceText, translatedText: translatedText, state: state)
            visibleLines[visibleLines.index(before: visibleLines.endIndex)] = nextLine
        } else {
            nextLine = CaptionLine(
                id: UUID(),
                sourceText: sourceText,
                translatedText: translatedText,
                state: state,
                createdAt: date
            )
            visibleLines.append(nextLine)
        }

        if visibleLines.count > maximumVisibleLines {
            visibleLines = Array(visibleLines.suffix(maximumVisibleLines))
        }

        return nextLine
    }

    mutating func reset() {
        visibleLines = []
    }
}
