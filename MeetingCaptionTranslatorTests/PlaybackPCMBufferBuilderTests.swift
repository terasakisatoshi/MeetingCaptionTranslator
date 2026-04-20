import AVFoundation
import CoreAudio
import XCTest
@testable import MeetingCaptionTranslator

final class PlaybackPCMBufferBuilderTests: XCTestCase {
    func test_makeBuffer_copiesFloatStereoDataIntoOwnedPCMBuffer() throws {
        let asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        let samples: [Float] = [0.25, -0.25, 0.5, -0.5]
        let pcm = try samples.withUnsafeBytes { rawBuffer -> AVAudioPCMBuffer in
            var audioBuffer = AudioBuffer(
                mNumberChannels: 2,
                mDataByteSize: UInt32(rawBuffer.count),
                mData: UnsafeMutableRawPointer(mutating: rawBuffer.baseAddress)
            )
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)

            return try PlaybackPCMBufferBuilder().makeBuffer(
                from: &list,
                format: asbd,
                frameCount: 2
            )
        }

        XCTAssertEqual(pcm.frameLength, 2)
        XCTAssertEqual(pcm.format.sampleRate, 48_000)

        let destination = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
        let copiedSamples = destination[0].mData!.assumingMemoryBound(to: Float.self)

        XCTAssertEqual(copiedSamples[0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(copiedSamples[1], -0.25, accuracy: 0.0001)
        XCTAssertEqual(copiedSamples[2], 0.5, accuracy: 0.0001)
        XCTAssertEqual(copiedSamples[3], -0.5, accuracy: 0.0001)
    }

    func test_copyByteCount_limitsToDestinationBufferSize() {
        XCTAssertEqual(
            PlaybackPCMBufferBuilder.copyByteCount(
                sourceByteCount: 32,
                destinationByteCount: 16
            ),
            16
        )
        XCTAssertEqual(
            PlaybackPCMBufferBuilder.copyByteCount(
                sourceByteCount: 8,
                destinationByteCount: 16
            ),
            8
        )
    }
}
