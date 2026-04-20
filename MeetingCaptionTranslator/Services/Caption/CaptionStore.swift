import Foundation

struct CaptionStore {
    private var maximumVisibleLines: Int
    private let maximumStoredLines: Int
    private var storedLines: [CaptionLine] = []

    var visibleLines: [CaptionLine] {
        Array(storedLines.suffix(maximumVisibleLines))
    }

    var historyLines: [CaptionLine] {
        storedLines
    }

    init(maximumVisibleLines: Int, maximumStoredLines: Int = 500) {
        self.maximumVisibleLines = max(1, maximumVisibleLines)
        self.maximumStoredLines = max(1, maximumStoredLines)
    }

    @discardableResult
    mutating func ingest(
        sourceText: String,
        translatedText: String?,
        state: CaptionLineState,
        at date: Date = Date()
    ) -> CaptionLine {
        let nextLine: CaptionLine

        if let current = storedLines.last, current.state == .partial {
            nextLine = current.updating(sourceText: sourceText, translatedText: translatedText, state: state)
            storedLines[storedLines.index(before: storedLines.endIndex)] = nextLine
        } else {
            nextLine = CaptionLine(
                id: UUID(),
                sourceText: sourceText,
                translatedText: translatedText,
                state: state,
                createdAt: date
            )
            storedLines.append(nextLine)
        }

        if storedLines.count > maximumStoredLines {
            storedLines = Array(storedLines.suffix(maximumStoredLines))
        }

        return nextLine
    }

    mutating func reset() {
        storedLines = []
    }

    mutating func updateMaximumVisibleLines(_ maximumVisibleLines: Int) {
        self.maximumVisibleLines = max(1, maximumVisibleLines)
    }
}
