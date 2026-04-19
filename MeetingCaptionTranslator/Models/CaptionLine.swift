import Foundation

enum CaptionLineState: Equatable, Codable, Sendable {
    case partial
    case final
}

struct CaptionLine: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceText: String
    let translatedText: String?
    let state: CaptionLineState
    let createdAt: Date

    func updating(sourceText: String, translatedText: String?, state: CaptionLineState) -> CaptionLine {
        CaptionLine(
            id: id,
            sourceText: sourceText,
            translatedText: translatedText,
            state: state,
            createdAt: createdAt
        )
    }
}
