import Foundation

// Translates each text in the direction its own language calls for.
@MainActor
final class BidirectionalTranslationService: AppViewModelTranslationServicing {
    private let services: [CaptionLanguagePair: any AppViewModelTranslationServicing]

    init(makeService: @MainActor (CaptionLanguagePair) -> any AppViewModelTranslationServicing) {
        services = [
            .englishToJapanese: makeService(.englishToJapanese),
            .japaneseToEnglish: makeService(.japaneseToEnglish)
        ]
    }

    func prepare() async throws {
        for service in services.values {
            try await service.prepare()
        }
    }

    func translate(_ text: String) async throws -> String {
        let direction = CaptionLanguagePair.translationDirection(forSourceText: text)
        guard let service = services[direction] else {
            throw AppError.translationUnavailable
        }
        return try await service.translate(text)
    }
}
