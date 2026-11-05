import XCTest
@testable import MeetingCaptionTranslator

final class SentenceBufferTests: XCTestCase {
    func test_text_without_a_sentence_end_is_held() {
        var buffer = SentenceBuffer()

        XCTAssertEqual(buffer.append("今日は会議で"), [])
        XCTAssertEqual(buffer.pending, "今日は会議で")
    }

    func test_fragments_are_released_together_at_the_japanese_full_stop() {
        var buffer = SentenceBuffer()

        _ = buffer.append("今日は会議で")

        XCTAssertEqual(buffer.append("新しい案を説明します。"), ["今日は会議で新しい案を説明します。"])
        XCTAssertEqual(buffer.pending, "")
    }

    func test_english_fragments_are_joined_with_a_space_and_released_at_the_period() {
        var buffer = SentenceBuffer()

        _ = buffer.append("Thank you for")

        XCTAssertEqual(buffer.append("joining the meeting today."), ["Thank you for joining the meeting today."])
    }

    func test_each_sentence_is_released_separately_and_the_rest_is_held() {
        var buffer = SentenceBuffer()

        XCTAssertEqual(
            buffer.append("Let's begin. 始めましょう。それでは"),
            ["Let's begin.", "始めましょう。"]
        )
        XCTAssertEqual(buffer.pending, "それでは")
    }

    func test_a_period_inside_a_number_does_not_end_a_sentence() {
        var buffer = SentenceBuffer()

        XCTAssertEqual(buffer.append("Version 3.5 is"), [])
        XCTAssertEqual(buffer.pending, "Version 3.5 is")
    }

    func test_question_and_exclamation_marks_end_a_sentence() {
        var buffer = SentenceBuffer()

        XCTAssertEqual(buffer.append("Ready? はい！"), ["Ready?", "はい！"])
    }

    func test_flush_releases_held_text_once() {
        var buffer = SentenceBuffer()
        _ = buffer.append("それでは")

        XCTAssertEqual(buffer.flush(), "それでは")
        XCTAssertNil(buffer.flush())
    }
}
