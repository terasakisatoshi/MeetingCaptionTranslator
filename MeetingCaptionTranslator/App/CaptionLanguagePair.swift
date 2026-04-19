import Foundation

struct CaptionLanguagePair: Codable, Equatable, Sendable {
    let sourceLanguage: String
    let targetLanguage: String

    static let defaultPair = CaptionLanguagePair(sourceLanguage: "en", targetLanguage: "ja")
}
