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

    func test_app_state_exposes_system_audio_capture_error_status() {
        let state = AppState.error(.systemAudioCaptureUnavailable)

        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(state.statusText, "System audio capture unavailable")
    }

    func test_app_state_exposes_transcription_error_status() {
        let state = AppState.error(.transcriptionUnavailable)

        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(state.statusText, "Transcription unavailable")
    }

    func test_default_settings_include_overlay_size_defaults() {
        XCTAssertEqual(AppSettings.defaultValue.overlayWidth, 960)
        XCTAssertEqual(AppSettings.defaultValue.overlayHeight, 220)
    }

    func test_app_settings_clamps_overlay_height_to_extended_maximum() {
        let settings = AppSettings(
            overlayOpacity: 0.58,
            fontSize: 24,
            maximumVisibleLines: 4,
            overlayWidth: 960,
            overlayHeight: 2_000,
            languagePair: .defaultPair
        )

        XCTAssertEqual(settings.overlayHeight, 1_440)
    }

    func test_app_settings_derives_visible_line_limit_from_overlay_height_and_font_size() {
        let settings = AppSettings(
            overlayOpacity: 0.58,
            fontSize: 24,
            maximumVisibleLines: 1,
            overlayWidth: 960,
            overlayHeight: 1_080,
            languagePair: .defaultPair
        )

        XCTAssertEqual(
            settings.maximumVisibleLines,
            AppSettings.derivedMaximumVisibleLines(overlayHeight: 1_080, fontSize: 24)
        )
        XCTAssertGreaterThan(settings.maximumVisibleLines, AppSettings.defaultValue.maximumVisibleLines)
    }
}
