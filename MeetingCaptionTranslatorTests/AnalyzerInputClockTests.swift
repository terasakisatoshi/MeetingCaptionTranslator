import AVFoundation
import CoreMedia
import XCTest
@testable import MeetingCaptionTranslator

final class AnalyzerInputClockTests: XCTestCase {
    func test_normalizedStartTime_preservesStrictlyIncreasingInputTimes() {
        var clock = AnalyzerInputClock()

        let first = clock.normalizedStartTime(
            requestedStartTime: CMTime(seconds: 0.25, preferredTimescale: 48_000),
            frameLength: 480,
            sampleRate: 48_000
        )
        let second = clock.normalizedStartTime(
            requestedStartTime: CMTime(seconds: 0.50, preferredTimescale: 48_000),
            frameLength: 480,
            sampleRate: 48_000
        )

        XCTAssertEqual(first, CMTime(seconds: 0.25, preferredTimescale: 48_000))
        XCTAssertEqual(second, CMTime(seconds: 0.50, preferredTimescale: 48_000))
    }

    func test_normalizedStartTime_clampsOverlappingInputToPreviousBufferEnd() {
        var clock = AnalyzerInputClock()

        _ = clock.normalizedStartTime(
            requestedStartTime: .zero,
            frameLength: 480,
            sampleRate: 48_000
        )
        let second = clock.normalizedStartTime(
            requestedStartTime: CMTime(seconds: 0.005, preferredTimescale: 48_000),
            frameLength: 480,
            sampleRate: 48_000
        )

        XCTAssertEqual(second, CMTime(value: 480, timescale: 48_000))
    }

    func test_normalizedStartTime_usesSampleAccurateBufferDuration() {
        var clock = AnalyzerInputClock()

        _ = clock.normalizedStartTime(
            requestedStartTime: .zero,
            frameLength: 64,
            sampleRate: 48_000
        )
        let second = clock.normalizedStartTime(
            requestedStartTime: .zero,
            frameLength: 64,
            sampleRate: 48_000
        )

        XCTAssertEqual(second, CMTime(value: 64, timescale: 48_000))
    }
}
