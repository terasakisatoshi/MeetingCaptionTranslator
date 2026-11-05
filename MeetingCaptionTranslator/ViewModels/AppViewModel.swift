import AVFoundation
import Combine
import Foundation
import Speech

protocol AppViewModelTranscriptionServicing: Sendable {
    func start(
        eventHandler: @escaping @Sendable (TranscriptEvent) async -> Void,
        errorHandler: @escaping @Sendable (Error) async -> Void
    ) async throws
    func append(frame: CapturedAudioFrame) async
    func stop() async
}

@MainActor
protocol AppViewModelTranslationServicing: AnyObject {
    func prepare() async throws
    func translate(_ text: String) async throws -> String
}

@MainActor
protocol AppViewModelCaptionPipelineServicing: AnyObject {
    var visibleLines: [CaptionLine] { get }
    var historyLines: [CaptionLine] { get }
    var appState: AppState { get }
    func handleTranscript(_ event: TranscriptEvent) async
    func stop()
    func updateMaximumVisibleLines(_ maximumVisibleLines: Int)
}

private final class LiveTranscriptionServiceAdapter: AppViewModelTranscriptionServicing, @unchecked Sendable {
    private let service: LiveTranscriptionService

    init(locale: Locale) {
        service = LiveTranscriptionService(locale: locale)
    }

    func start(
        eventHandler: @escaping @Sendable (TranscriptEvent) async -> Void,
        errorHandler: @escaping @Sendable (Error) async -> Void
    ) async throws {
        try await service.start(eventHandler: eventHandler, errorHandler: errorHandler)
    }

    func append(frame: CapturedAudioFrame) async {
        await service.append(frame: frame)
    }

    func stop() async {
        await service.stop()
    }
}

@MainActor
private final class AppleTranslationServiceAdapter: AppViewModelTranslationServicing {
    private let service: AppleTranslationService

    init(languagePair: CaptionLanguagePair) {
        service = AppleTranslationService(languagePair: languagePair)
    }

    func prepare() async throws {
        try await service.prepare()
    }

    func translate(_ text: String) async throws -> String {
        try await service.translate(text)
    }
}

@MainActor
private final class CaptionPipelineServiceAdapter: AppViewModelCaptionPipelineServicing {
    private let service: CaptionPipelineService

    init(maximumVisibleLines: Int, translator: @escaping (String) async throws -> String) {
        service = CaptionPipelineService(maximumVisibleLines: maximumVisibleLines, translator: translator)
    }

    var visibleLines: [CaptionLine] {
        service.visibleLines
    }

    var historyLines: [CaptionLine] {
        service.historyLines
    }

    var appState: AppState {
        service.appState
    }

    func handleTranscript(_ event: TranscriptEvent) async {
        await service.handleTranscript(event)
    }

    func stop() {
        service.stop()
    }

    func updateMaximumVisibleLines(_ maximumVisibleLines: Int) {
        service.updateMaximumVisibleLines(maximumVisibleLines)
    }
}

enum AudioInput: String, CaseIterable, Identifiable {
    case systemAudio, microphone
    var id: Self { self }
    var title: String { self == .systemAudio ? "Mac System Audio" : "Microphone" }
}

struct MicrophoneDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var appState: AppState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var diagnosticsText = AppViewModel.makeDiagnosticsText(
        capturedFrameCount: 0,
        transcriptEventCount: 0,
        lastTranscriptState: nil
    )
    @Published private(set) var audioInput: AudioInput = .systemAudio
    @Published private(set) var microphoneDevices: [MicrophoneDevice] = []
    @Published private(set) var selectedMicrophoneID: String = ""
    var selectedTargetDescription: String { audioInput.title }
    @Published private(set) var transcriptionEngine: TranscriptionEngine
    @Published private(set) var isPreparingAppleSpeechModel = false
    @Published private(set) var appleSpeechModelMessage: String?
    @Published private(set) var languagePair: CaptionLanguagePair

    let overlayViewModel: OverlayViewModel

    private let appleSpeechModelPreparer: @MainActor (Locale) async throws -> Void
    private let settingsStore: AppSettingsStore
    private let systemCaptureService: any CaptureServicing
    private let microphoneCaptureService: any CaptureServicing
    private var captureService: any CaptureServicing { audioInput == .systemAudio ? systemCaptureService : microphoneCaptureService }
    private let transcriptionServiceFactory: @MainActor (Locale) -> any AppViewModelTranscriptionServicing
    private let speechWorkerTranscriptionServiceFactory: @MainActor (CaptionLanguagePair) -> any AppViewModelTranscriptionServicing
    private let translationServiceFactory: @MainActor (CaptionLanguagePair) -> any AppViewModelTranslationServicing
    private let captionPipelineServiceFactory: @MainActor (Int, @escaping (String) async throws -> String) -> any AppViewModelCaptionPipelineServicing
    private let overlayWindowManagerFactory: @MainActor (OverlayViewModel, @escaping @MainActor (CGSize) -> Void) -> any OverlayWindowManaging
    private var transcriptionService: (any AppViewModelTranscriptionServicing)?
    private var translationService: (any AppViewModelTranslationServicing)?
    private var captionPipelineService: (any AppViewModelCaptionPipelineServicing)?
    private var overlayWindowManager: (any OverlayWindowManaging)?
    private var frameRelay: CapturedFrameRelay?
    private var settings: AppSettings
    private var lifecycleToken: Int = 0
    private var capturedFrameCount = 0
    private var transcriptEventCount = 0
    private var lastTranscriptState: CaptionLineState?

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        appleSpeechModelPreparer: @escaping @MainActor (Locale) async throws -> Void = { locale in
            _ = try await SpeechTranscriberPreparation(requestedLocale: locale, preset: .timeIndexedProgressiveTranscription).prepare()
        },
        captureService: any CaptureServicing = SystemPlaybackCaptureService(),
        microphoneCaptureService: any CaptureServicing = MicrophoneCaptureService(),
        transcriptionServiceFactory: @escaping @MainActor (Locale) -> any AppViewModelTranscriptionServicing = { (locale: Locale) -> any AppViewModelTranscriptionServicing in
            LiveTranscriptionServiceAdapter(locale: locale)
        },
        speechWorkerTranscriptionServiceFactory: @escaping @MainActor (CaptionLanguagePair) -> any AppViewModelTranscriptionServicing = { (languagePair: CaptionLanguagePair) -> any AppViewModelTranscriptionServicing in
            HaasTranscriptionService(languagePair: languagePair)
        },
        translationServiceFactory: @escaping @MainActor (CaptionLanguagePair) -> any AppViewModelTranslationServicing = { (languagePair: CaptionLanguagePair) -> any AppViewModelTranslationServicing in
            AppleTranslationServiceAdapter(languagePair: languagePair)
        },
        captionPipelineServiceFactory: @escaping @MainActor (Int, @escaping (String) async throws -> String) -> any AppViewModelCaptionPipelineServicing = { (maximumVisibleLines: Int, translator: @escaping (String) async throws -> String) -> any AppViewModelCaptionPipelineServicing in
            CaptionPipelineServiceAdapter(maximumVisibleLines: maximumVisibleLines, translator: translator)
        },
        overlayWindowManagerFactory: @escaping @MainActor (OverlayViewModel, @escaping @MainActor (CGSize) -> Void) -> any OverlayWindowManaging = { viewModel, onSizeChange in
            OverlayWindowManager(viewModel: viewModel, onSizeChange: onSizeChange)
        }
    ) {
        self.appleSpeechModelPreparer = appleSpeechModelPreparer
        self.settingsStore = settingsStore
        self.systemCaptureService = captureService
        self.microphoneCaptureService = microphoneCaptureService
        self.transcriptionServiceFactory = transcriptionServiceFactory
        self.speechWorkerTranscriptionServiceFactory = speechWorkerTranscriptionServiceFactory
        self.translationServiceFactory = translationServiceFactory
        self.captionPipelineServiceFactory = captionPipelineServiceFactory
        self.overlayWindowManagerFactory = overlayWindowManagerFactory
        let loadedSettings = settingsStore.load()
        settings = loadedSettings
        languagePair = loadedSettings.languagePair
        transcriptionEngine = loadedSettings.transcriptionEngine
        overlayViewModel = OverlayViewModel(settings: settings)
    }

    func refreshMicrophoneDevices() {
        microphoneDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices.map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    func updateMicrophoneDevice(_ id: String) {
        guard !appState.isRunning, appState != .preparing else { return }
        selectedMicrophoneID = id
        (microphoneCaptureService as? MicrophoneCaptureService)?.selectedDeviceID = id.isEmpty ? nil : id
    }

    func initialize() {
        refreshMicrophoneDevices()
        if overlayWindowManager == nil {
            overlayWindowManager = overlayWindowManagerFactory(overlayViewModel) { [weak self] size in
                self?.handleOverlayWindowResized(to: size)
            }
            overlayWindowManager?.show()
        }
    }

    func start() {
        guard !appState.isRunning, appState != .preparing, !isPreparingAppleSpeechModel else { return }
        lifecycleToken &+= 1
        let token = lifecycleToken
        appState = .preparing
        Task {
            await startCapture(token: token)
        }
    }

    func prepareAppleSpeechModel() {
        guard transcriptionEngine == .apple, !appState.isRunning,
              appState != .preparing, !isPreparingAppleSpeechModel else { return }
        let locale = Locale(identifier: languagePair.speechLocaleIdentifier)
        isPreparingAppleSpeechModel = true
        appleSpeechModelMessage = nil
        errorMessage = nil
        Task {
            do {
                try await appleSpeechModelPreparer(locale)
                appleSpeechModelMessage = "Apple Speech model is ready."
            } catch {
                errorMessage = error.localizedDescription
            }
            isPreparingAppleSpeechModel = false
        }
    }

    func stop() {
        lifecycleToken &+= 1
        let captureService = captureService
        let transcriptionService = transcriptionService
        let captionPipelineService = captionPipelineService
        let frameRelay = frameRelay
        self.transcriptionService = nil
        translationService = nil
        self.captionPipelineService = nil
        self.frameRelay = nil
        errorMessage = nil
        appState = .idle
        overlayViewModel.render(lines: [], appState: .idle)

        Task {
            await stopCapture(
            captureService: captureService,
                frameRelay: frameRelay,
                transcriptionService: transcriptionService,
                captionPipelineService: captionPipelineService
            )
        }
    }

    func updateOverlayWidth(_ width: Double) {
        settings.overlayWidth = AppSettings.clamp(width, to: AppSettings.overlayWidthRange)
        overlayViewModel.apply(settings: settings)
        try? settingsStore.save(settings)
    }

    func updateOverlayOpacity(_ opacity: Double) {
        settings.overlayOpacity = AppSettings.clamp(opacity, to: AppSettings.overlayOpacityRange)
        overlayViewModel.apply(settings: settings)
        try? settingsStore.save(settings)
    }

    func updateOverlayHeight(_ height: Double) {
        settings.overlayHeight = AppSettings.clamp(height, to: AppSettings.overlayHeightRange)
        settings.maximumVisibleLines = AppSettings.derivedMaximumVisibleLines(
            overlayHeight: settings.overlayHeight,
            fontSize: settings.fontSize
        )
        captionPipelineService?.updateMaximumVisibleLines(settings.maximumVisibleLines)
        overlayViewModel.apply(settings: settings)
        if let captionPipelineService {
            overlayViewModel.render(lines: captionPipelineService.historyLines, appState: appState)
        }
        try? settingsStore.save(settings)
    }

    func updateOverlayFontSize(_ fontSize: Double) {
        settings.fontSize = AppSettings.clamp(fontSize, to: AppSettings.fontSizeRange)
        settings.maximumVisibleLines = AppSettings.derivedMaximumVisibleLines(
            overlayHeight: settings.overlayHeight,
            fontSize: settings.fontSize
        )
        captionPipelineService?.updateMaximumVisibleLines(settings.maximumVisibleLines)
        overlayViewModel.apply(settings: settings)
        if let captionPipelineService {
            overlayViewModel.render(lines: captionPipelineService.historyLines, appState: appState)
        }
        try? settingsStore.save(settings)
    }

    func updateAudioInput(_ input: AudioInput) {
        guard !appState.isRunning, appState != .preparing else { return }
        audioInput = input
    }

    func updateTranscriptionEngine(_ engine: TranscriptionEngine) {
        guard !appState.isRunning, appState != .preparing, !isPreparingAppleSpeechModel else { return }
        // Apple Speech hears one fixed language, so it cannot serve the automatic direction.
        guard !(languagePair.isAutomatic && engine == .apple) else { return }
        appleSpeechModelMessage = nil
        transcriptionEngine = engine
        settings.transcriptionEngine = engine
        try? settingsStore.save(settings)
    }

    func updateLanguagePair(_ languagePair: CaptionLanguagePair) {
        guard !appState.isRunning, appState != .preparing, !isPreparingAppleSpeechModel else {
            return
        }

        appleSpeechModelMessage = nil
        settings.languagePair = languagePair
        self.languagePair = languagePair
        if languagePair.isAutomatic {
            transcriptionEngine = .haas
            settings.transcriptionEngine = .haas
        }
        try? settingsStore.save(settings)
    }

    private func handleOverlayWindowResized(to size: CGSize) {
        settings.overlayWidth = AppSettings.clamp(size.width, to: AppSettings.overlayWidthRange)
        settings.overlayHeight = AppSettings.clamp(size.height, to: AppSettings.overlayHeightRange)
        settings.maximumVisibleLines = AppSettings.derivedMaximumVisibleLines(
            overlayHeight: settings.overlayHeight,
            fontSize: settings.fontSize
        )
        captionPipelineService?.updateMaximumVisibleLines(settings.maximumVisibleLines)
        overlayViewModel.apply(settings: settings)
        if let captionPipelineService {
            overlayViewModel.render(lines: captionPipelineService.historyLines, appState: appState)
        }
        try? settingsStore.save(settings)
    }

    private func startCapture(token: Int) async {
        guard isCurrent(token: token) else {
            return
        }

        resetDiagnostics()
        errorMessage = nil
        appState = .preparing
        overlayViewModel.render(lines: [], appState: appState)

        let captureService = captureService
        let transcriptionService: any AppViewModelTranscriptionServicing
        if transcriptionEngine == .haas {
            transcriptionService = speechWorkerTranscriptionServiceFactory(languagePair)
        } else {
            transcriptionService = transcriptionServiceFactory(Locale(identifier: settings.languagePair.speechLocaleIdentifier))
        }
        let translationService: any AppViewModelTranslationServicing = languagePair.isAutomatic
            ? BidirectionalTranslationService(makeService: translationServiceFactory)
            : translationServiceFactory(settings.languagePair)
        var captionPipelineService: (any AppViewModelCaptionPipelineServicing)?
        var frameRelay: CapturedFrameRelay?

        do {
            try await translationService.prepare()
            guard isCurrent(token: token) else {
                await stopCapture(
                    captureService: captureService,
                    frameRelay: frameRelay,
                    transcriptionService: transcriptionService,
                    captionPipelineService: captionPipelineService
                )
                return
            }

            self.transcriptionService = transcriptionService
            try await transcriptionService.start(
                eventHandler: { [weak self] event in
                    guard let self else {
                        return
                    }

                    await self.handleTranscriptEvent(event, token: token)
                },
                errorHandler: { [weak self] error in
                    await self?.handleTranscriptionFailure(error, token: token)
                }
            )

            guard isCurrent(token: token) else {
                await stopCapture(
                    captureService: captureService,
                    frameRelay: frameRelay,
                    transcriptionService: transcriptionService,
                    captionPipelineService: captionPipelineService
                )
                return
            }

            captionPipelineService = captionPipelineServiceFactory(
                settings.maximumVisibleLines,
                { text in
                    try await translationService.translate(text)
                }
            )

            let diagnosticsReporter = CapturedFrameDiagnosticsReporter(
                viewModel: self,
                token: token
            )
            frameRelay = CapturedFrameRelay { [transcriptionService] frame in
                await transcriptionService.append(frame: frame)
            }

            self.transcriptionService = transcriptionService
            self.translationService = translationService
            self.captionPipelineService = captionPipelineService
            self.frameRelay = frameRelay

            try await captureService.startCapture(
                inputHandler: { [frameRelay, diagnosticsReporter] frame in
                    diagnosticsReporter.recordFrame()
                    frameRelay?.enqueue(frame)
                },
                errorHandler: { [weak self] message in
                    guard let self, self.isCurrent(token: token) else {
                        return
                    }

                    self.errorMessage = message
                    self.appState = .error(self.audioInput == .microphone ? .microphoneCaptureUnavailable : .systemAudioCaptureUnavailable)
                }
            )

            guard isCurrent(token: token) else {
                await stopCapture(
                    captureService: captureService,
                    frameRelay: frameRelay,
                    transcriptionService: transcriptionService,
                    captionPipelineService: captionPipelineService
                )
                return
            }

            appState = .capturing
            overlayViewModel.render(lines: [], appState: appState)
        } catch PermissionError.systemAudioRecordingDenied {
            self.frameRelay = nil
            await stopCapture(
            captureService: captureService,
                frameRelay: frameRelay,
                transcriptionService: transcriptionService,
                captionPipelineService: captionPipelineService
            )

            guard isCurrent(token: token) else {
                return
            }

            appState = .error(.systemAudioCaptureUnavailable)
            errorMessage = "System Audio Recording permission is required"
        } catch PermissionError.microphoneDenied {
            self.frameRelay = nil
            await stopCapture(
                captureService: captureService,
                frameRelay: frameRelay,
                transcriptionService: transcriptionService,
                captionPipelineService: captionPipelineService
            )
            guard isCurrent(token: token) else { return }
            appState = .error(.microphoneCaptureUnavailable)
            errorMessage = "Microphone permission is required"
        } catch LiveTranscriptionError.speechNotAuthorized {
            self.frameRelay = nil
            await stopCapture(
            captureService: captureService,
                frameRelay: frameRelay,
                transcriptionService: transcriptionService,
                captionPipelineService: captionPipelineService
            )

            guard isCurrent(token: token) else {
                return
            }

            appState = .error(.transcriptionUnavailable)
            errorMessage = "Speech Recognition permission is required"
        } catch {
            self.frameRelay = nil
            await stopCapture(
            captureService: captureService,
                frameRelay: frameRelay,
                transcriptionService: transcriptionService,
                captionPipelineService: captionPipelineService
            )

            guard isCurrent(token: token) else {
                return
            }

            if error is MicrophoneCaptureError {
                appState = .error(.microphoneCaptureUnavailable)
            } else if error is CoreAudioTapError {
                appState = .error(.systemAudioCaptureUnavailable)
            } else if error is LiveTranscriptionError || error is SpeechTranscriberPreparationError || error is HaasTranscriptionError {
                appState = .error(.transcriptionUnavailable)
            } else {
                appState = .error(.translationUnavailable)
            }
            errorMessage = error.localizedDescription
        }
    }

    private func stopCapture(
        captureService: any CaptureServicing,
        frameRelay: CapturedFrameRelay?,
        transcriptionService: (any AppViewModelTranscriptionServicing)?,
        captionPipelineService: (any AppViewModelCaptionPipelineServicing)?
    ) async {
        await captureService.stopCapture()
        await frameRelay?.stop()
        await transcriptionService?.stop()
        captionPipelineService?.stop()
    }

    private func handleTranscriptEvent(_ event: TranscriptEvent, token: Int) async {
        guard isCurrent(token: token), let captionPipelineService else {
            return
        }

        recordTranscriptEvent(event)
        await captionPipelineService.handleTranscript(event)
        guard isCurrent(token: token) else {
            return
        }

        appState = captionPipelineService.appState
        overlayViewModel.render(lines: captionPipelineService.historyLines, appState: appState)
    }

    private func handleTranscriptionFailure(_ error: Error, token: Int) async {
        guard isCurrent(token: token) else {
            return
        }

        let captureService = captureService
        let frameRelay = self.frameRelay
        let transcriptionService = self.transcriptionService
        let captionPipelineService = self.captionPipelineService
        self.frameRelay = nil
        self.transcriptionService = nil
        translationService = nil
        self.captionPipelineService = nil

        await stopCapture(
            captureService: captureService,
            frameRelay: frameRelay,
            transcriptionService: transcriptionService,
            captionPipelineService: captionPipelineService
        )

        guard isCurrent(token: token) else {
            return
        }

        appState = .error(.transcriptionUnavailable)
        errorMessage = error.localizedDescription
        overlayViewModel.render(lines: [], appState: appState)
    }

    private func isCurrent(token: Int) -> Bool {
        lifecycleToken == token
    }

    private func resetDiagnostics() {
        capturedFrameCount = 0
        transcriptEventCount = 0
        lastTranscriptState = nil
        diagnosticsText = Self.makeDiagnosticsText(
            capturedFrameCount: capturedFrameCount,
            transcriptEventCount: transcriptEventCount,
            lastTranscriptState: lastTranscriptState
        )
    }

    fileprivate func setCapturedFrameCount(_ count: Int, token: Int) {
        guard isCurrent(token: token), count > capturedFrameCount else {
            return
        }

        capturedFrameCount = count
        diagnosticsText = Self.makeDiagnosticsText(
            capturedFrameCount: capturedFrameCount,
            transcriptEventCount: transcriptEventCount,
            lastTranscriptState: lastTranscriptState
        )
    }

    private func recordTranscriptEvent(_ event: TranscriptEvent) {
        transcriptEventCount += 1
        lastTranscriptState = event.state
        diagnosticsText = Self.makeDiagnosticsText(
            capturedFrameCount: capturedFrameCount,
            transcriptEventCount: transcriptEventCount,
            lastTranscriptState: lastTranscriptState
        )
    }

    private static func makeDiagnosticsText(
        capturedFrameCount: Int,
        transcriptEventCount: Int,
        lastTranscriptState: CaptionLineState?
    ) -> String {
        let lastTranscriptDescription = switch lastTranscriptState {
        case .partial?:
            "partial"
        case .final?:
            "final"
        case nil:
            "none"
        }

        return """
        Frames received: \(capturedFrameCount)
        Transcript events: \(transcriptEventCount)
        Last transcript: \(lastTranscriptDescription)
        """
    }
}

private final class CapturedFrameDiagnosticsReporter: @unchecked Sendable {
    private weak var viewModel: AppViewModel?
    private let token: Int
    private let publishInterval: Int
    private let lock = NSLock()
    private var count = 0

    init(viewModel: AppViewModel, token: Int, publishInterval: Int = 25) {
        self.viewModel = viewModel
        self.token = token
        self.publishInterval = publishInterval
    }

    func recordFrame() {
        let snapshot: Int
        let shouldPublish: Bool

        lock.lock()
        count += 1
        snapshot = count
        shouldPublish = snapshot == 1 || snapshot.isMultiple(of: publishInterval)
        lock.unlock()

        guard shouldPublish else {
            return
        }

        Task { @MainActor [weak viewModel] in
            viewModel?.setCapturedFrameCount(snapshot, token: token)
        }
    }
}
