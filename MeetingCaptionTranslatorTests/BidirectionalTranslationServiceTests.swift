import XCTest
@testable import MeetingCaptionTranslator

@MainActor
final class BidirectionalTranslationServiceTests: XCTestCase {
    func test_prepare_prepares_both_directions() async throws {
        var services: [DirectionTaggingTranslationService] = []
        let service = BidirectionalTranslationService { pair in
            let directed = DirectionTaggingTranslationService(pair: pair)
            services.append(directed)
            return directed
        }

        try await service.prepare()

        XCTAssertEqual(Set(services.map(\.pair)), [.englishToJapanese, .japaneseToEnglish])
        XCTAssertTrue(services.allSatisfy(\.didPrepare))
    }

    func test_english_text_is_translated_english_to_japanese() async throws {
        let service = BidirectionalTranslationService { DirectionTaggingTranslationService(pair: $0) }

        let translated = try await service.translate("Let's get started.")

        XCTAssertEqual(translated, "en-ja:Let's get started.")
    }

    func test_japanese_text_is_translated_japanese_to_english() async throws {
        let service = BidirectionalTranslationService { DirectionTaggingTranslationService(pair: $0) }

        let translated = try await service.translate("始めましょう。")

        XCTAssertEqual(translated, "ja-en:始めましょう。")
    }
}

@MainActor
private final class DirectionTaggingTranslationService: AppViewModelTranslationServicing {
    let pair: CaptionLanguagePair
    private(set) var didPrepare = false

    init(pair: CaptionLanguagePair) {
        self.pair = pair
    }

    func prepare() async throws {
        didPrepare = true
    }

    func translate(_ text: String) async throws -> String {
        "\(pair.id):\(text)"
    }
}
