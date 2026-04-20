import AVFoundation
import CoreAudio
import Foundation

enum PlaybackPCMBufferBuilderError: Error {
    case unsupportedFormat
    case bufferCreationFailed
}

final class PlaybackPCMBufferBuilder {
    static func copyByteCount(sourceByteCount: Int, destinationByteCount: Int) -> Int {
        min(sourceByteCount, destinationByteCount)
    }

    func makeBuffer(
        from bufferList: UnsafePointer<AudioBufferList>,
        format: AudioStreamBasicDescription,
        frameCount: UInt32
    ) throws -> AVAudioPCMBuffer {
        let avFormat: AVAudioFormat? = withUnsafePointer(to: format) {
            AVAudioFormat(streamDescription: $0)
        }

        guard let avFormat else {
            throw PlaybackPCMBufferBuilderError.unsupportedFormat
        }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: avFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            throw PlaybackPCMBufferBuilderError.bufferCreationFailed
        }

        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        let source = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList)
        )
        let destination = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)

        for index in 0..<min(source.count, destination.count) {
            guard let sourceData = source[index].mData,
                  let destinationData = destination[index].mData
            else {
                continue
            }

            let copyByteCount = Self.copyByteCount(
                sourceByteCount: Int(source[index].mDataByteSize),
                destinationByteCount: Int(destination[index].mDataByteSize)
            )

            memcpy(destinationData, sourceData, copyByteCount)
        }

        return pcmBuffer
    }
}
