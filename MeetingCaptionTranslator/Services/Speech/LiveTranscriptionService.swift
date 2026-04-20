import AVFoundation
import Foundation
import Speech

enum LiveTranscriptionError: Error, LocalizedError {
    case speechNotAuthorized
    case transcriberUnavailable

    var errorDescription: String? {
        switch self {
        case .speechNotAuthorized:
            "Speech Recognition permission is required"
        case .transcriberUnavailable:
            "Speech transcription is unavailable"
        }
    }
}

actor LiveTranscriptionService {
    private let permissionService = PermissionService()
    private let locale: Locale
    private let audioBufferConverter = AudioBufferConverter()

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var targetFormat: AVAudioFormat?
    private var eventHandler: (@Sendable (TranscriptEvent) async -> Void)?
    private var runtimeErrorHandler: (@Sendable (Error) async -> Void)?
    private var inputClock = AnalyzerInputClock()
    private var didReportRuntimeFailure = false
    private var pendingConvertedFrameStartTime: CMTime?

    init(locale: Locale) {
        self.locale = locale
    }

    func start(
        eventHandler: @escaping @Sendable (TranscriptEvent) async -> Void,
        errorHandler: @escaping @Sendable (Error) async -> Void
    ) async throws {
        let authorizationStatus = await permissionService.requestSpeechAuthorization()
        guard authorizationStatus == .authorized else {
            throw LiveTranscriptionError.speechNotAuthorized
        }

        let resolvedLocale = try await SpeechTranscriberPreparation(
            requestedLocale: locale,
            preset: .timeIndexedProgressiveTranscription
        ).prepare()
        let transcriber = SpeechTranscriber(
            locale: resolvedLocale,
            preset: .timeIndexedProgressiveTranscription
        )
        let compatibleFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        try await analyzer.prepareToAnalyze(in: compatibleFormat)

        let stream = AsyncStream(AnalyzerInput.self) { continuation in
            self.continuation = continuation
        }

        self.eventHandler = eventHandler
        runtimeErrorHandler = errorHandler
        self.analyzer = analyzer
        self.transcriber = transcriber
        targetFormat = compatibleFormat
        inputClock = AnalyzerInputClock()
        didReportRuntimeFailure = false
        pendingConvertedFrameStartTime = nil
        audioBufferConverter.reset()

        analysisTask = Task {
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                await self.reportRuntimeFailure(error)
            }
        }

        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let transcript = TranscriptEvent(
                        sourceText: String(result.text.characters),
                        state: result.isFinal ? .final : .partial
                    )
                    await eventHandler(transcript)
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                await self.reportRuntimeFailure(error)
            }
        }
    }

    func append(frame: CapturedAudioFrame) async {
        guard let continuation else {
            return
        }

        do {
            let inputBuffer: AVAudioPCMBuffer
            let requestedStartTime = pendingConvertedFrameStartTime ?? frame.when

            if let targetFormat {
                inputBuffer = try audioBufferConverter.convert(frame.buffer, to: targetFormat)
            } else {
                inputBuffer = frame.buffer
            }

            guard inputBuffer.frameLength > 0 else {
                if pendingConvertedFrameStartTime == nil {
                    pendingConvertedFrameStartTime = frame.when
                }
                return
            }

            pendingConvertedFrameStartTime = nil

            let normalizedStartTime = inputClock.normalizedStartTime(
                requestedStartTime: requestedStartTime,
                frameLength: inputBuffer.frameLength,
                sampleRate: inputBuffer.format.sampleRate
            )
            continuation.yield(AnalyzerInput(buffer: inputBuffer, bufferStartTime: normalizedStartTime))
        } catch {
            await reportRuntimeFailure(error)
        }
    }

    func stop() async {
        continuation?.finish()
        runtimeErrorHandler = nil
        didReportRuntimeFailure = false

        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }

        resultsTask?.cancel()
        analysisTask?.cancel()

        analyzer = nil
        transcriber = nil
        continuation = nil
        analysisTask = nil
        resultsTask = nil
        targetFormat = nil
        eventHandler = nil
        inputClock = AnalyzerInputClock()
        pendingConvertedFrameStartTime = nil
        audioBufferConverter.reset()
    }

    private func reportRuntimeFailure(_ error: Error) async {
        guard !didReportRuntimeFailure else {
            return
        }

        didReportRuntimeFailure = true
        guard let runtimeErrorHandler else {
            return
        }

        await runtimeErrorHandler(error)
    }
}
