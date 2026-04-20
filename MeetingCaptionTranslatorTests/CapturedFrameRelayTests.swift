import AVFoundation
import CoreMedia
import XCTest
@testable import MeetingCaptionTranslator

final class CapturedFrameRelayTests: XCTestCase {
    func test_enqueue_processesFramesInOrder() async {
        let recorder = RecordedFrameSink()
        let relay = CapturedFrameRelay { frame in
            await recorder.record(seconds: CMTimeGetSeconds(frame.when))
        }

        relay.enqueue(Self.makeFrame(seconds: 0.0))
        relay.enqueue(Self.makeFrame(seconds: 1.0))
        relay.enqueue(Self.makeFrame(seconds: 2.0))

        await waitUntil { await recorder.count == 3 }
        let recordedValues = await recorder.snapshot()
        XCTAssertEqual(recordedValues, [0.0, 1.0, 2.0])

        await relay.stop()
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool,
        iterations: Int = 50,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<iterations {
            if await condition() {
                return
            }

            await Task.yield()
        }

        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    private static func makeFrame(seconds: Double) -> CapturedAudioFrame {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
        buffer.frameLength = 480
        return CapturedAudioFrame(
            buffer: buffer,
            when: CMTime(seconds: seconds, preferredTimescale: 48_000)
        )
    }
}

private actor RecordedFrameSink {
    private var values: [Double] = []

    func record(seconds: Double) {
        values.append(seconds)
    }

    var count: Int {
        values.count
    }

    func snapshot() -> [Double] {
        values
    }
}
