import AVFoundation
import CoreMedia

enum MicrophoneCaptureError: LocalizedError {
    case unavailable

    var errorDescription: String? { "Microphone input is unavailable" }
}

@MainActor
final class MicrophoneCaptureService: CaptureServicing {
    private var engine: AVAudioEngine?

    func startCapture(
        inputHandler: @escaping @Sendable (CapturedAudioFrame) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw PermissionError.microphoneDenied
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MicrophoneCaptureError.unavailable
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTapHandler(inputHandler))
        do {
            try engine.start()
            self.engine = engine
        } catch {
            input.removeTap(onBus: 0)
            throw MicrophoneCaptureError.unavailable
        }
    }

    nonisolated static func makeTapHandler(
        _ inputHandler: @escaping @Sendable (CapturedAudioFrame) -> Void
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { @Sendable buffer, time in
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
            copy.frameLength = buffer.frameLength
            let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for (src, dst) in zip(source, destination) {
                if let srcData = src.mData, let dstData = dst.mData {
                    memcpy(dstData, srcData, Int(src.mDataByteSize))
                }
            }
            let when = time.isHostTimeValid ? CMClockMakeHostTimeFromSystemUnits(time.hostTime) : .invalid
            inputHandler(CapturedAudioFrame(buffer: copy, when: when))
        }
    }

    func stopCapture() async {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }
}
