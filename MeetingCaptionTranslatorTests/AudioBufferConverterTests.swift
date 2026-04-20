import AVFoundation
import XCTest
@testable import MeetingCaptionTranslator

final class AudioBufferConverterTests: XCTestCase {
    func test_convert_returnsSameBuffer_whenFormatsAlreadyMatch() throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64)!
        buffer.frameLength = 64

        let result = try AudioBufferConverter().convert(buffer, to: format)

        XCTAssertTrue(result === buffer)
    }

    func test_convert_reusesConverterAcrossSmallSequentialBuffers() throws {
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: true
        )!
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let converter = AudioBufferConverter()

        let first = try converter.convert(makeBuffer(frameLength: 16, format: inputFormat), to: targetFormat)
        let second = try converter.convert(makeBuffer(frameLength: 16, format: inputFormat), to: targetFormat)

        XCTAssertEqual(first.frameLength, 0)
        XCTAssertGreaterThan(second.frameLength, 0)
    }

    private func makeBuffer(
        frameLength: AVAudioFrameCount,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength)!
        buffer.frameLength = frameLength

        if format.isInterleaved, let channelData = buffer.floatChannelData {
            let sampleCount = Int(frameLength) * Int(format.channelCount)
            for index in 0..<sampleCount {
                channelData[0][index] = index.isMultiple(of: 11) ? 0.25 : 0
            }
        } else if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                for index in 0..<Int(frameLength) {
                    channelData[channel][index] = index.isMultiple(of: 11) ? 0.25 : 0
                }
            }
        }

        return buffer
    }
}
