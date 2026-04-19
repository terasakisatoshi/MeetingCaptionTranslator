import XCTest
@testable import MeetingCaptionTranslator

@MainActor
final class OverlayViewModelTests: XCTestCase {
    func test_view_model_renders_caption_lines_into_rows() {
        let viewModel = OverlayViewModel(settings: .defaultValue)
        let lines = [
            CaptionLine(
                id: UUID(),
                sourceText: "good morning",
                translatedText: "おはようございます",
                state: .final,
                createdAt: .distantPast
            )
        ]

        viewModel.render(lines: lines, appState: .capturing)

        XCTAssertEqual(viewModel.rows.count, 1)
        XCTAssertEqual(viewModel.rows[0].sourceText, "good morning")
        XCTAssertEqual(viewModel.rows[0].translatedText, "おはようございます")
        XCTAssertEqual(viewModel.statusText, "Capturing")
    }

    func test_view_model_preserves_english_when_translation_is_missing_in_degraded_mode() {
        let viewModel = OverlayViewModel(settings: .defaultValue)
        let lines = [
            CaptionLine(
                id: UUID(),
                sourceText: "we are live",
                translatedText: nil,
                state: .partial,
                createdAt: .distantPast
            )
        ]

        viewModel.render(lines: lines, appState: .degraded(reason: .translationUnavailable))

        XCTAssertEqual(viewModel.rows.count, 1)
        XCTAssertEqual(viewModel.rows[0].sourceText, "we are live")
        XCTAssertNil(viewModel.rows[0].translatedText)
        XCTAssertEqual(viewModel.statusText, "Translation unavailable")
    }

    func test_view_model_applies_overlay_settings() {
        let viewModel = OverlayViewModel(settings: .defaultValue)
        let updatedSettings = AppSettings(
            overlayOpacity: 0.65,
            fontSize: 30,
            maximumVisibleLines: 6,
            isClickThroughEnabled: false,
            languagePair: .defaultPair
        )

        viewModel.apply(settings: updatedSettings)

        XCTAssertEqual(viewModel.overlayOpacity, 0.65)
        XCTAssertEqual(viewModel.fontSize, 30)
        XCTAssertFalse(viewModel.isClickThroughEnabled)
        XCTAssertEqual(viewModel.maximumVisibleLines, 6)
    }
}
