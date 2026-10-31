import XCTest
@testable import MeetingCaptionTranslator

final class HaasSegmenterTests: XCTestCase {
    func test_silence_ends_a_voiced_utterance_and_ignores_silence() {
        var segmenter = HaasSegmenter(sampleRate: 1000)
        XCTAssertTrue(segmenter.append(Array(repeating: 0, count: 1000)).isEmpty)
        XCTAssertTrue(segmenter.append(Array(repeating: 0.2, count: 500)).isEmpty)
        let segments = segmenter.append(Array(repeating: 0, count: 800))
        XCTAssertEqual(segments.count, 1)
        XCTAssertGreaterThanOrEqual(segments[0].count, 500)
    }
}
