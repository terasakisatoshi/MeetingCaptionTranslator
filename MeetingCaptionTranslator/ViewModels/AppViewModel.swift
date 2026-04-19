import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var appState: AppState = .idle
    @Published private(set) var availableTargets: [CaptureTarget] = []
    @Published var selectedTargetID: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedTargetDescription = "No source selected"

    let overlayViewModel: OverlayViewModel

    private let settingsStore: AppSettingsStore
    private let captureService = SystemAudioCaptureService()
    private var transcriptionService: LiveTranscriptionService?
    private var translationService: AppleTranslationService?
    private var captionPipelineService: CaptionPipelineService?
    private var overlayWindowManager: OverlayWindowManager?
    private var settings: AppSettings

    init(settingsStore: AppSettingsStore = AppSettingsStore()) {
        self.settingsStore = settingsStore
        settings = settingsStore.load()
        overlayViewModel = OverlayViewModel(settings: settings)
    }

    func initialize() {
        if overlayWindowManager == nil {
            overlayWindowManager = OverlayWindowManager(viewModel: overlayViewModel)
            overlayWindowManager?.show()
        }

        Task {
            await refreshTargets()
        }
    }

    func refreshTargets() async {
        do {
            let targets = try await captureService.refreshDisplays()
            availableTargets = targets

            if selectedTargetID == nil {
                selectedTargetID = targets.first?.id
            }

            updateSelectedTargetDescription()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start() {
        Task {
            await startCapture()
        }
    }

    func stop() {
        Task {
            await stopCapture()
        }
    }

    func updateOverlayClickThrough(_ enabled: Bool) {
        settings.isClickThroughEnabled = enabled
        overlayViewModel.apply(settings: settings)
        try? settingsStore.save(settings)
    }

    private func startCapture() async {
        guard let targetID = selectedTargetID else {
            errorMessage = "Select a display first"
            return
        }

        errorMessage = nil
        appState = .preparing
        overlayViewModel.render(lines: [], appState: appState)

        do {
            let transcriptionService = LiveTranscriptionService(locale: Locale(identifier: "en-US"))
            let translationService = AppleTranslationService(languagePair: settings.languagePair)

            try await translationService.prepare()

            let pipeline = CaptionPipelineService(
                maximumVisibleLines: settings.maximumVisibleLines,
                translator: { text in
                    try await translationService.translate(text)
                }
            )

            try await transcriptionService.start { [weak self] event in
                guard let self else {
                    return
                }

                await self.handleTranscriptEvent(event)
            }

            try await captureService.startCapture(
                targetID: targetID,
                inputHandler: { [weak transcriptionService] sampleBuffer in
                    guard let transcriptionService else {
                        return
                    }

                    let sample = CapturedAudioSample(sampleBuffer: sampleBuffer)
                    Task {
                        await transcriptionService.append(sample: sample)
                    }
                },
                errorHandler: { [weak self] message in
                    self?.errorMessage = message
                    self?.appState = .error(.translationUnavailable)
                }
            )

            self.transcriptionService = transcriptionService
            self.translationService = translationService
            captionPipelineService = pipeline
            appState = .capturing
            overlayViewModel.render(lines: [], appState: appState)
        } catch PermissionError.screenRecordingDenied {
            appState = .error(.translationUnavailable)
            errorMessage = "Screen Recording permission is required"
        } catch LiveTranscriptionError.speechNotAuthorized {
            appState = .error(.translationUnavailable)
            errorMessage = "Speech Recognition permission is required"
        } catch {
            appState = .error(.translationUnavailable)
            errorMessage = error.localizedDescription
        }
    }

    private func stopCapture() async {
        await captureService.stopCapture()
        await transcriptionService?.stop()

        captionPipelineService?.stop()
        appState = .idle
        overlayViewModel.render(lines: [], appState: .idle)
    }

    private func handleTranscriptEvent(_ event: TranscriptEvent) async {
        guard let captionPipelineService else {
            return
        }

        await captionPipelineService.handleTranscript(event)
        appState = captionPipelineService.appState
        overlayViewModel.render(lines: captionPipelineService.visibleLines, appState: appState)
    }

    private func updateSelectedTargetDescription() {
        selectedTargetDescription = availableTargets.first(where: { $0.id == selectedTargetID })?.title ?? "No source selected"
    }
}
