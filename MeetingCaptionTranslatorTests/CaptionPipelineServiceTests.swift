import XCTest
@testable import MeetingCaptionTranslator

@MainActor
final class CaptionPipelineServiceTests: XCTestCase {
    func test_partial_transcript_updates_visible_lines_without_translation() async {
        let service = CaptionPipelineService(maximumVisibleLines: 4) { _ in
            XCTFail("translation should not run for partial transcripts")
            return ""
        }

        await service.handleTranscript(.init(sourceText: "hello", state: .partial))

        XCTAssertEqual(service.visibleLines.count, 1)
        XCTAssertEqual(service.visibleLines[0].sourceText, "hello")
        XCTAssertNil(service.visibleLines[0].translatedText)
        XCTAssertEqual(service.appState, .transcribing)
    }

    func test_final_transcript_applies_translation() async {
        let service = CaptionPipelineService(maximumVisibleLines: 4) { sourceText in
            XCTAssertEqual(sourceText, "hello world")
            return "こんにちは"
        }

        await service.handleTranscript(.init(sourceText: "hello world", state: .final))

        XCTAssertEqual(service.visibleLines.count, 1)
        XCTAssertEqual(service.visibleLines[0].sourceText, "hello world")
        XCTAssertEqual(service.visibleLines[0].translatedText, "こんにちは")
        XCTAssertEqual(service.visibleLines[0].state, .final)
        XCTAssertEqual(service.appState, .transcribing)
    }

    func test_translation_failure_falls_back_to_english_only() async {
        let service = CaptionPipelineService(maximumVisibleLines: 4) { _ in
            throw AppError.translationUnavailable
        }

        await service.handleTranscript(.init(sourceText: "system audio", state: .final))

        XCTAssertEqual(service.visibleLines.count, 1)
        XCTAssertEqual(service.visibleLines[0].sourceText, "system audio")
        XCTAssertNil(service.visibleLines[0].translatedText)
        XCTAssertEqual(service.appState, .degraded(reason: .translationUnavailable))
    }

    func test_stop_clears_transient_state() async {
        let service = CaptionPipelineService(maximumVisibleLines: 4) { _ in
            "こんにちは"
        }

        await service.handleTranscript(.init(sourceText: "hello", state: .partial))
        service.stop()

        XCTAssertTrue(service.visibleLines.isEmpty)
        XCTAssertEqual(service.appState, .idle)
    }
}
