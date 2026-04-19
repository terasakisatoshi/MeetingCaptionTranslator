import XCTest
@testable import MeetingCaptionTranslator

final class CoreModelTests: XCTestCase {
    func test_caption_language_pair_defaults_to_english_to_japanese() {
        XCTAssertEqual(CaptionLanguagePair.defaultPair.sourceLanguage, "en")
        XCTAssertEqual(CaptionLanguagePair.defaultPair.targetLanguage, "ja")
    }

    func test_caption_line_can_apply_partial_update() {
        let line = CaptionLine(
            id: UUID(),
            sourceText: "hello",
            translatedText: nil,
            state: .partial,
            createdAt: .distantPast
        )

        let updated = line.updating(sourceText: "hello world", translatedText: "こんにちは", state: .partial)

        XCTAssertEqual(updated.sourceText, "hello world")
        XCTAssertEqual(updated.translatedText, "こんにちは")
        XCTAssertEqual(updated.state, .partial)
        XCTAssertEqual(updated.id, line.id)
    }

    func test_app_state_exposes_degraded_translation_mode() {
        let state = AppState.degraded(reason: .translationUnavailable)

        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.statusText, "Translation unavailable")
    }
}
