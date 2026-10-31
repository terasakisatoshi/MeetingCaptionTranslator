import AVFoundation
import CoreMedia
import CoreAudio
import AudioToolbox

enum MicrophoneCaptureError: LocalizedError {
    case unavailable

    var errorDescription: String? { "Microphone input is unavailable" }
}

@MainActor
final class MicrophoneCaptureService: CaptureServicing {
    private var engine: AVAudioEngine?
    var selectedDeviceID: String?

    func startCapture(
        inputHandler: @escaping @Sendable (CapturedAudioFrame) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw PermissionError.microphoneDenied
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let selectedDeviceID {
            guard let deviceID = Self.deviceID(for: selectedDeviceID), let audioUnit = input.audioUnit else {
                throw MicrophoneCaptureError.unavailable
            }
            var device = deviceID
            let status = AudioUnitSetProperty(
                audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &device, UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else { throw MicrophoneCaptureError.unavailable }
        }
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

    private static func deviceID(for uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !devices.isEmpty else { return nil }
        let status = devices.withUnsafeMutableBufferPointer {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { return nil }
        for device in devices {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var deviceUID: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            if AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &deviceUID) == noErr,
               deviceUID as String == uid {
                return device
            }
        }
        return nil
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
