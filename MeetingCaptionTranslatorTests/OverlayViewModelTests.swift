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
            fontSize: 24,
            maximumVisibleLines: 1,
            overlayWidth: 1280,
            overlayHeight: 1_080,
            languagePair: .defaultPair
        )

        viewModel.apply(settings: updatedSettings)

        XCTAssertEqual(viewModel.overlayOpacity, 0.65)
        XCTAssertEqual(viewModel.fontSize, 24)
        XCTAssertEqual(viewModel.overlayWidth, 1280)
        XCTAssertEqual(viewModel.overlayHeight, 1_080)
        XCTAssertEqual(
            viewModel.maximumVisibleLines,
            AppSettings.derivedMaximumVisibleLines(overlayHeight: 1_080, fontSize: 24)
        )
    }

    func test_view_model_renders_full_history_not_just_visible_line_limit() {
        let settings = AppSettings(
            overlayOpacity: 0.58,
            fontSize: 24,
            maximumVisibleLines: 1,
            overlayWidth: 960,
            overlayHeight: 220,
            languagePair: .defaultPair
        )
        let viewModel = OverlayViewModel(settings: settings)
        let lines = [
            CaptionLine(
                id: UUID(),
                sourceText: "first",
                translatedText: "1",
                state: .final,
                createdAt: .distantPast
            ),
            CaptionLine(
                id: UUID(),
                sourceText: "second",
                translatedText: "2",
                state: .final,
                createdAt: .now
            )
        ]

        viewModel.render(lines: lines, appState: .capturing)

        XCTAssertEqual(viewModel.rows.map(\.sourceText), ["first", "second"])
    }
}
