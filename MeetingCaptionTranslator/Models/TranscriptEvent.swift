import Foundation

struct TranscriptEvent: Equatable, Sendable {
    let sourceText: String
    let state: CaptionLineState
}
