import Foundation
import ScreenCaptureKit

@MainActor
final class SystemAudioCaptureService: NSObject, SCStreamOutput, SCStreamDelegate {
    private let permissionService = PermissionService()
    private let sampleQueue = DispatchQueue(label: "atelierarith.live-caption-translator.capture")

    private var shareableContent: SCShareableContent?
    private var displaysByID: [String: SCDisplay] = [:]
    private var stream: SCStream?
    nonisolated(unsafe) private var inputHandler: (@Sendable (CMSampleBuffer) -> Void)?
    nonisolated(unsafe) private var errorHandler: (@MainActor @Sendable (String) -> Void)?

    func refreshDisplays() async throws -> [CaptureTarget] {
        let content = try await SCShareableContent.current
        shareableContent = content

        let targets = content.displays.enumerated().map { index, display in
            let identifier = String(display.displayID)
            displaysByID[identifier] = display
            return CaptureTarget(
                id: identifier,
                title: "Display \(index + 1)",
                subtitle: "\(display.width) x \(display.height)",
                kind: .display
            )
        }

        return targets
    }

    func startCapture(
        targetID: String,
        inputHandler: @escaping @Sendable (CMSampleBuffer) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        guard permissionService.requestScreenRecordingAccessIfNeeded() else {
            throw PermissionError.screenRecordingDenied
        }

        if displaysByID[targetID] == nil {
            _ = try await refreshDisplays()
        }

        guard let display = displaysByID[targetID] else {
            throw AudioBufferConversionError.unsupportedFormat
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3
        configuration.width = 2
        configuration.height = 2
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        self.stream = stream
        self.inputHandler = inputHandler
        self.errorHandler = errorHandler
    }

    func stopCapture() async {
        if let stream {
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .audio)
        }

        stream = nil
        inputHandler = nil
        errorHandler = nil
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else {
            return
        }

        inputHandler?(sampleBuffer)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            errorHandler?(error.localizedDescription)
        }
    }
}
