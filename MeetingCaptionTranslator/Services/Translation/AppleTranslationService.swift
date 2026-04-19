import Foundation
@preconcurrency import Translation

@MainActor
final class AppleTranslationService {
    private let session: TranslationSession

    init(languagePair: CaptionLanguagePair) {
        let sourceLanguage = Locale.Language(identifier: languagePair.sourceLanguage)
        let targetLanguage = Locale.Language(identifier: languagePair.targetLanguage)
        if #available(macOS 26.4, *) {
            session = TranslationSession(
                installedSource: sourceLanguage,
                target: targetLanguage,
                preferredStrategy: .lowLatency
            )
        } else {
            session = TranslationSession(
                installedSource: sourceLanguage,
                target: targetLanguage
            )
        }
    }

    func prepare() async throws {
        try await session.prepareTranslation()
    }

    func translate(_ text: String) async throws -> String {
        let response = try await session.translate(text)
        return response.targetText
    }
}
