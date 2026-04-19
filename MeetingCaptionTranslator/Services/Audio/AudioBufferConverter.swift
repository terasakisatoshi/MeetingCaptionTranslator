@preconcurrency import AVFoundation
import CoreMedia
import Foundation

enum AudioBufferConversionError: Error {
    case unsupportedFormat
    case coreMedia(OSStatus)
    case bufferCreationFailed
}

final class AudioBufferConverter {
    private final class ConversionSource: @unchecked Sendable {
        private let lock = NSLock()
        private let buffer: AVAudioPCMBuffer
        private var isConsumed = false

        init(buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }

        func nextBuffer() -> AVAudioPCMBuffer? {
            lock.lock()
            defer { lock.unlock() }

            guard !isConsumed else {
                return nil
            }

            isConsumed = true
            return buffer
        }
    }

    func pcmBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
            let format = AVAudioFormat(streamDescription: streamDescriptionPointer)
        else {
            throw AudioBufferConversionError.unsupportedFormat
        }

        let audioBufferListPointer = allocateAudioBufferList(maximumBuffers: Int(format.channelCount))
        var blockBuffer: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferListPointer.unsafeMutablePointer,
            bufferListSize: audioBufferListPointer.allocatedSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            audioBufferListPointer.deallocate()
            throw AudioBufferConversionError.coreMedia(status)
        }

        guard
            let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                bufferListNoCopy: audioBufferListPointer.unsafePointer,
                deallocator: { _ in
                    _ = blockBuffer
                    audioBufferListPointer.deallocate()
                }
            )
        else {
            audioBufferListPointer.deallocate()
            throw AudioBufferConversionError.bufferCreationFailed
        }

        pcmBuffer.frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        return pcmBuffer
    }

    func convert(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard !matches(buffer.format, targetFormat) else {
            return buffer
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            throw AudioBufferConversionError.unsupportedFormat
        }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            throw AudioBufferConversionError.bufferCreationFailed
        }

        var conversionError: NSError?
        let source = ConversionSource(buffer: buffer)

        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            guard let sourceBuffer = source.nextBuffer() else {
                outStatus.pointee = .noDataNow
                return nil
            }

            outStatus.pointee = .haveData
            return sourceBuffer
        }

        guard status != .error else {
            throw conversionError ?? AudioBufferConversionError.bufferCreationFailed
        }

        return outputBuffer
    }

    private func matches(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.commonFormat == rhs.commonFormat &&
            lhs.channelCount == rhs.channelCount &&
            lhs.sampleRate == rhs.sampleRate &&
            lhs.isInterleaved == rhs.isInterleaved
    }

    private func allocateAudioBufferList(maximumBuffers: Int) -> (unsafeMutablePointer: UnsafeMutablePointer<AudioBufferList>, unsafePointer: UnsafePointer<AudioBufferList>, allocatedSize: Int, deallocate: () -> Void) {
        let allocatedSize = MemoryLayout<AudioBufferList>.size + max(0, maximumBuffers - 1) * MemoryLayout<AudioBuffer>.size
        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: allocatedSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        rawPointer.initializeMemory(as: UInt8.self, repeating: 0, count: allocatedSize)

        let bufferListPointer = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)

        return (
            unsafeMutablePointer: bufferListPointer,
            unsafePointer: UnsafePointer(bufferListPointer),
            allocatedSize: allocatedSize,
            deallocate: {
                rawPointer.deallocate()
            }
        )
    }
}
