import CoreAudio
import CoreMedia
import Foundation

private final class SystemPlaybackIOProcContext {
    let bufferBuilder: PlaybackPCMBufferBuilder
    let tapFormat: AudioStreamBasicDescription
    let inputHandler: @Sendable (CapturedAudioFrame) -> Void

    init(
        bufferBuilder: PlaybackPCMBufferBuilder,
        tapFormat: AudioStreamBasicDescription,
        inputHandler: @escaping @Sendable (CapturedAudioFrame) -> Void
    ) {
        self.bufferBuilder = bufferBuilder
        self.tapFormat = tapFormat
        self.inputHandler = inputHandler
    }
}

private func systemPlaybackCaptureIOProc(
    _ inDevice: AudioObjectID,
    _ inNow: UnsafePointer<AudioTimeStamp>,
    _ inInputData: UnsafePointer<AudioBufferList>,
    _ inInputTime: UnsafePointer<AudioTimeStamp>,
    _ outOutputData: UnsafeMutablePointer<AudioBufferList>,
    _ inOutputTime: UnsafePointer<AudioTimeStamp>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let inClientData else {
        return noErr
    }

    let callbackContext = Unmanaged<SystemPlaybackIOProcContext>.fromOpaque(inClientData).takeUnretainedValue()
    let frameCount = systemPlaybackCaptureFrameCount(
        from: inInputData,
        bytesPerFrame: callbackContext.tapFormat.mBytesPerFrame
    )
    guard frameCount > 0,
          let pcmBuffer = try? callbackContext.bufferBuilder.makeBuffer(
              from: inInputData,
              format: callbackContext.tapFormat,
              frameCount: frameCount
          )
    else {
        return noErr
    }

    let when = systemPlaybackCaptureTimestamp(
        from: inInputTime.pointee,
        sampleRate: callbackContext.tapFormat.mSampleRate
    )
    callbackContext.inputHandler(CapturedAudioFrame(buffer: pcmBuffer, when: when))
    return noErr
}

private func releaseSystemPlaybackIOProcContext(_ callbackContext: UnsafeMutableRawPointer) {
    Unmanaged<SystemPlaybackIOProcContext>.fromOpaque(callbackContext).release()
}

private func systemPlaybackCaptureFrameCount(
    from bufferList: UnsafePointer<AudioBufferList>,
    bytesPerFrame: UInt32
) -> UInt32 {
    guard bytesPerFrame > 0 else {
        return 0
    }

    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
    var maximumFrameCount: UInt32 = 0

    for buffer in buffers {
        maximumFrameCount = max(maximumFrameCount, buffer.mDataByteSize / bytesPerFrame)
    }

    return maximumFrameCount
}

private func systemPlaybackCaptureTimestamp(
    from audioTimeStamp: AudioTimeStamp,
    sampleRate: Float64
) -> CMTime {
    let sampleTimeValidFlag = AudioTimeStampFlags(rawValue: 1 << 0)
    let hostTimeValidFlag = AudioTimeStampFlags(rawValue: 1 << 1)

    if audioTimeStamp.mFlags.contains(sampleTimeValidFlag), sampleRate > 0 {
        return CMTime(
            seconds: audioTimeStamp.mSampleTime / sampleRate,
            preferredTimescale: 600
        )
    }

    if audioTimeStamp.mFlags.contains(hostTimeValidFlag) {
        return CMClockMakeHostTimeFromSystemUnits(audioTimeStamp.mHostTime)
    }

    return .zero
}

@MainActor
final class SystemPlaybackCaptureService: CaptureServicing {
    private static let tapActivationPollLimit = 20
    private static let tapActivationPollIntervalNanoseconds: UInt64 = 50_000_000

    private let hardware: any CoreAudioPlaybackHardware
    private let configuration: CoreAudioTapConfiguration
    private let bufferBuilder: PlaybackPCMBufferBuilder

    private var tapID: AudioObjectID?
    private var aggregateDeviceID: AudioObjectID?
    private var ioProcID: AudioDeviceIOProcID?
    private var callbackContext: UnsafeMutableRawPointer?

    init(
        hardware: any CoreAudioPlaybackHardware = DefaultCoreAudioPlaybackHardware(),
        configuration: CoreAudioTapConfiguration = .defaultConfiguration(),
        bufferBuilder: PlaybackPCMBufferBuilder = PlaybackPCMBufferBuilder()
    ) {
        self.hardware = hardware
        self.configuration = configuration
        self.bufferBuilder = bufferBuilder
    }

    func startCapture(
        inputHandler: @escaping @Sendable (CapturedAudioFrame) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        var createdTapID: AudioObjectID?
        var createdAggregateDeviceID: AudioObjectID?
        var createdIOProcID: AudioDeviceIOProcID?
        var createdCallbackContext: UnsafeMutableRawPointer?

        do {
            try hardware.destroyAggregateDevices(uidPrefix: CoreAudioTapConfiguration.aggregateDeviceUIDPrefix)

            let tapID = try hardware.createTap(description: configuration.tapDescription)
            createdTapID = tapID

            let tapFormat = try hardware.tapFormat(for: tapID)
            let defaultOutputDeviceUID = try hardware.defaultOutputDeviceUID()
            let tapUID = try hardware.tapUID(for: tapID)
            let aggregateDeviceID = try hardware.createAggregateDevice(
                description: configuration.aggregateDeviceDescription(
                    mainSubDeviceUID: defaultOutputDeviceUID,
                    tapUID: tapUID
                )
            )
            createdAggregateDeviceID = aggregateDeviceID

            try await waitForAggregateActivation(onAggregateDevice: aggregateDeviceID)

            let callbackContext = SystemPlaybackIOProcContext(
                bufferBuilder: bufferBuilder,
                tapFormat: tapFormat,
                inputHandler: inputHandler
            )
            let callbackContextPointer = Unmanaged.passRetained(callbackContext).toOpaque()
            createdCallbackContext = callbackContextPointer
            let ioProcID = try hardware.createIOProcID(
                deviceID: aggregateDeviceID,
                ioProc: systemPlaybackCaptureIOProc,
                clientData: callbackContextPointer
            )
            createdIOProcID = ioProcID

            try hardware.start(deviceID: aggregateDeviceID, ioProcID: ioProcID)

            self.tapID = tapID
            self.aggregateDeviceID = aggregateDeviceID
            self.ioProcID = ioProcID
            self.callbackContext = callbackContextPointer
        } catch CoreAudioTapError.permissionDenied {
            cleanup(
                ioProcID: createdIOProcID,
                aggregateDeviceID: createdAggregateDeviceID,
                tapID: createdTapID,
                callbackContext: createdCallbackContext
            )
            throw PermissionError.systemAudioRecordingDenied
        } catch {
            cleanup(
                ioProcID: createdIOProcID,
                aggregateDeviceID: createdAggregateDeviceID,
                tapID: createdTapID,
                callbackContext: createdCallbackContext
            )
            errorHandler(error.localizedDescription)
            throw error
        }
    }

    func stopCapture() async {
        cleanup(
            ioProcID: ioProcID,
            aggregateDeviceID: aggregateDeviceID,
            tapID: tapID,
            callbackContext: callbackContext
        )
        tapID = nil
        aggregateDeviceID = nil
        ioProcID = nil
        callbackContext = nil
    }

    private func cleanup(
        ioProcID: AudioDeviceIOProcID?,
        aggregateDeviceID: AudioObjectID?,
        tapID: AudioObjectID?,
        callbackContext: UnsafeMutableRawPointer?
    ) {
        if let ioProcID, let aggregateDeviceID {
            hardware.stop(deviceID: aggregateDeviceID, ioProcID: ioProcID)
            hardware.destroyIOProcID(ioProcID, deviceID: aggregateDeviceID)
        }

        if let callbackContext {
            releaseSystemPlaybackIOProcContext(callbackContext)
        }

        if let aggregateDeviceID {
            hardware.destroyAggregateDevice(aggregateDeviceID)
        }

        if let tapID {
            hardware.destroyTap(tapID)
        }
    }

    private func waitForAggregateActivation(onAggregateDevice deviceID: AudioObjectID) async throws {
        for attempt in 0..<Self.tapActivationPollLimit {
            let activeSubDeviceCount = try hardware.activeSubDeviceCount(onAggregateDevice: deviceID)
            let activeSubTapCount = try hardware.activeSubTapCount(onAggregateDevice: deviceID)
            if activeSubDeviceCount > 0, activeSubTapCount > 0 {
                return
            }

            if attempt < Self.tapActivationPollLimit - 1 {
                try await Task.sleep(nanoseconds: Self.tapActivationPollIntervalNanoseconds)
            }
        }
    }
}
