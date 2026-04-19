import AVFoundation
import CoreMedia
import Foundation
import Speech

enum LiveTranscriptionError: Error {
    case speechNotAuthorized
    case transcriberUnavailable
}

struct CapturedAudioSample: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer
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

    init(locale: Locale) {
        self.locale = locale
    }

    func start(eventHandler: @escaping @Sendable (TranscriptEvent) async -> Void) async throws {
        let authorizationStatus = await permissionService.requestSpeechAuthorization()
        guard authorizationStatus == .authorized else {
            throw LiveTranscriptionError.speechNotAuthorized
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        let compatibleFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        try await analyzer.prepareToAnalyze(in: compatibleFormat)

        let stream = AsyncStream(AnalyzerInput.self) { continuation in
            self.continuation = continuation
        }

        self.eventHandler = eventHandler
        self.analyzer = analyzer
        self.transcriber = transcriber
        targetFormat = compatibleFormat

        analysisTask = Task {
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
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
            }
        }
    }

    func append(sample: CapturedAudioSample) async {
        guard let continuation else {
            return
        }

        do {
            let sampleBuffer = sample.sampleBuffer
            let buffer = try audioBufferConverter.pcmBuffer(from: sampleBuffer)
            let inputBuffer: AVAudioPCMBuffer

            if let targetFormat {
                inputBuffer = try audioBufferConverter.convert(buffer, to: targetFormat)
            } else {
                inputBuffer = buffer
            }

            let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            continuation.yield(AnalyzerInput(buffer: inputBuffer, bufferStartTime: presentationTimeStamp))
        } catch {
        }
    }

    func stop() async {
        continuation?.finish()

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
    }
}
