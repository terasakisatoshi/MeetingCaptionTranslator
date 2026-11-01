import AVFoundation
import CoreMedia
import XCTest
@testable import MeetingCaptionTranslator

@MainActor
final class AppViewModelTests: XCTestCase {
    func test_prepareAppleSpeechModel_showsProgressAndUsesSelectedLanguage() async {
        var requestedLocale: String?
        var continuation: CheckedContinuation<Void, Never>?
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            appleSpeechModelPreparer: { locale in
                requestedLocale = locale.identifier
                await withCheckedContinuation { continuation = $0 }
            }
        )
        viewModel.updateLanguagePair(.japaneseToEnglish)
        viewModel.prepareAppleSpeechModel()
        XCTAssertTrue(viewModel.isPreparingAppleSpeechModel)
        viewModel.updateLanguagePair(.englishToJapanese)
        viewModel.start()
        XCTAssertEqual(viewModel.languagePair, .japaneseToEnglish)
        XCTAssertEqual(viewModel.appState, .idle)
        await waitUntil { continuation != nil }
        XCTAssertEqual(requestedLocale, "ja-JP")
        continuation?.resume()
        await waitUntil { !viewModel.isPreparingAppleSpeechModel }
        XCTAssertEqual(viewModel.appleSpeechModelMessage, "Apple Speech model is ready.")
    }

    func test_prepareAppleSpeechModel_reportsFailureAndAllowsRetry() async {
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            appleSpeechModelPreparer: { _ in throw TestError.message("Download failed") }
        )
        viewModel.prepareAppleSpeechModel()
        await waitUntil { !viewModel.isPreparingAppleSpeechModel }
        XCTAssertEqual(viewModel.errorMessage, "Download failed")
        XCTAssertNil(viewModel.appleSpeechModelMessage)
    }

    func test_microphoneTap_acceptsAudioFromBackgroundQueue() async throws {
        let received = expectation(description: "microphone frame received")
        let callback = MicrophoneCaptureService.makeTapHandler { frame in
            XCTAssertEqual(frame.buffer.frameLength, 8)
            received.fulfill()
        }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8))
        buffer.frameLength = 8
        let frame = CapturedAudioFrame(buffer: buffer, when: .zero)
        DispatchQueue.global().async {
            callback(frame.buffer, AVAudioTime(hostTime: mach_absolute_time()))
        }
        await fulfillment(of: [received], timeout: 2)
    }

    func test_microphoneSelection_updatesCaptureDeviceAndCanReturnToDefault() {
        let microphone = MicrophoneCaptureService()
        let viewModel = AppViewModel(settingsStore: makeSettingsStore(), microphoneCaptureService: microphone)

        viewModel.updateMicrophoneDevice("usb-device")
        XCTAssertEqual(viewModel.selectedMicrophoneID, "usb-device")
        XCTAssertEqual(microphone.selectedDeviceID, "usb-device")

        viewModel.updateMicrophoneDevice("")
        XCTAssertEqual(viewModel.selectedMicrophoneID, "")
        XCTAssertNil(microphone.selectedDeviceID)
    }

    func test_initialize_showsOverlay() async {
        let captureService = FakeCaptureService()
        let overlayWindowManager = FakeOverlayWindowManager()
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            captureService: captureService,
            overlayWindowManagerFactory: { _, _ in overlayWindowManager }
        )

        viewModel.initialize()
        await Task.yield()

        XCTAssertTrue(overlayWindowManager.didShow)
    }

    func test_initialize_setsFixedSystemAudioDescription() async {
        let captureService = FakeCaptureService()
        let overlayWindowManager = FakeOverlayWindowManager()
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            captureService: captureService,
            overlayWindowManagerFactory: { _, _ in overlayWindowManager }
        )

        viewModel.initialize()
        await Task.yield()

        XCTAssertEqual(viewModel.selectedTargetDescription, "Mac System Audio")
    }

    func test_start_usesOnlySelectedMicrophoneCapture() async {
        let system = RecordingCaptureService()
        let microphone = RecordingCaptureService()
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            captureService: system,
            microphoneCaptureService: microphone,
            transcriptionServiceFactory: { _ in RecordingTranscriptionService() },
            translationServiceFactory: { _ in RecordingTranslationService() }
        )
        viewModel.updateAudioInput(.microphone)
        viewModel.start()
        await waitUntil { microphone.didEnterStartCapture }
        XCTAssertTrue(microphone.didEnterStartCapture)
        XCTAssertFalse(system.didEnterStartCapture)
        viewModel.updateAudioInput(.systemAudio)
        XCTAssertEqual(viewModel.audioInput, .microphone)
        viewModel.stop()
        await waitUntil { microphone.didStopCapture }
        XCTAssertTrue(microphone.didStopCapture)
    }

    func test_start_surfacesSystemAudioPermissionMessage_whenCaptureStartFails() async {
        let captureService = FakeCaptureService(startError: PermissionError.systemAudioRecordingDenied)
        let transcriptionService = RecordingTranscriptionService()
        let translationService = RecordingTranslationService()
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            captureService: captureService,
            transcriptionServiceFactory: { _ in transcriptionService },
            translationServiceFactory: { _ in translationService },
            overlayWindowManagerFactory: { _, _ in FakeOverlayWindowManager() }
        )

        viewModel.start()
        await waitUntil {
            viewModel.appState == .error(.systemAudioCaptureUnavailable) &&
            viewModel.errorMessage == "System Audio Recording permission is required"
        }

        XCTAssertEqual(viewModel.errorMessage, "System Audio Recording permission is required")
    }

    func test_start_surfacesDetailedCoreAudioMessage_whenCaptureStartFails() async {
        let captureService = FakeCaptureService(
            startError: CoreAudioTapError.osStatus(42, context: "start io")
        )
        let transcriptionService = RecordingTranscriptionService()
        let translationService = RecordingTranslationService()
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            captureService: captureService,
            transcriptionServiceFactory: { _ in transcriptionService },
            translationServiceFactory: { _ in translationService },
            overlayWindowManagerFactory: { _, _ in FakeOverlayWindowManager() }
        )

        viewModel.start()
        await waitUntil {
            viewModel.appState == .error(.systemAudioCaptureUnavailable) &&
            viewModel.errorMessage == "Core Audio failed to start io (OSStatus 42 / 0x0000002A)"
        }

        XCTAssertEqual(viewModel.appState, .error(.systemAudioCaptureUnavailable))
        XCTAssertEqual(
            viewModel.errorMessage,
            "Core Audio failed to start io (OSStatus 42 / 0x0000002A)"
        )
    }

    func test_start_preparesPipelineBeforeStartingCapture() async {
        let captureService = RecordingCaptureService()
        let transcriptionService = RecordingTranscriptionService()
        let translationService = RecordingTranslationService()
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            captureService: captureService,
            transcriptionServiceFactory: { _ in transcriptionService },
            translationServiceFactory: { _ in translationService },
            overlayWindowManagerFactory: { _, _ in FakeOverlayWindowManager() }
        )

        viewModel.start()
        await waitUntil { captureService.didEnterStartCapture }

        XCTAssertTrue(translationService.didPrepare)
        let didStartTranscription = await transcriptionService.didStart
        XCTAssertTrue(didStartTranscription)
        XCTAssertTrue(captureService.didEnterStartCapture)
    }

    func test_start_usesSelectedLanguagePairForSpeechAndTranslation() async throws {
        let store = makeSettingsStore()
        var settings = store.load()
        settings.languagePair = .japaneseToEnglish
        try store.save(settings)

        let captureService = RecordingCaptureService()
        let transcriptionService = RecordingTranscriptionService()
        let translationService = RecordingTranslationService()
        var requestedLocale: Locale?
        var requestedLanguagePair: CaptionLanguagePair?
        let viewModel = AppViewModel(
            settingsStore: store,
            captureService: captureService,
            transcriptionServiceFactory: { locale in
                requestedLocale = locale
                return transcriptionService
            },
            translationServiceFactory: { languagePair in
                requestedLanguagePair = languagePair
                return translationService
            },
            overlayWindowManagerFactory: { _, _ in FakeOverlayWindowManager() }
        )

        viewModel.start()
        await waitUntil { captureService.didEnterStartCapture }

        XCTAssertEqual(requestedLocale?.identifier, "ja-JP")
        XCTAssertEqual(requestedLanguagePair, .japaneseToEnglish)
    }

    func test_stop_preventsStaleStartFromOverwritingIdleState() async {
        let captureService = DeferredCaptureService()
        let transcriptionService = RecordingTranscriptionService()
        let translationService = RecordingTranslationService()
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            captureService: captureService,
            transcriptionServiceFactory: { _ in transcriptionService },
            translationServiceFactory: { _ in translationService },
            overlayWindowManagerFactory: { _, _ in FakeOverlayWindowManager() }
        )

        viewModel.start()
        await waitUntil { captureService.didEnterStartCapture }

        viewModel.stop()
        XCTAssertEqual(viewModel.appState, .idle)
        XCTAssertNil(viewModel.errorMessage)

        captureService.finishStartCapture()
        await waitUntil { captureService.didFinishStartCapture }

        XCTAssertEqual(viewModel.appState, .idle)
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_start_surfacesAsyncTranscriptionFailure_whenSpeechPipelineFailsAfterCaptureStarts() async {
        let captureService = RecordingCaptureService()
        let transcriptionService = RuntimeFailingTranscriptionService()
        let translationService = RecordingTranslationService()
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            captureService: captureService,
            transcriptionServiceFactory: { _ in transcriptionService },
            translationServiceFactory: { _ in translationService },
            overlayWindowManagerFactory: { _, _ in FakeOverlayWindowManager() }
        )

        viewModel.start()
        await waitUntil { captureService.didEnterStartCapture }
        await transcriptionService.reportRuntimeFailure(TestError.message("Speech pipeline disconnected"))
        await waitUntil { viewModel.appState == .error(.transcriptionUnavailable) }

        XCTAssertEqual(viewModel.errorMessage, "Speech pipeline disconnected")
        XCTAssertTrue(captureService.didStopCapture)
        let didStopTranscription = await transcriptionService.didStop
        XCTAssertTrue(didStopTranscription)
    }

    func test_start_updatesDiagnostics_whenFramesAndTranscriptEventsFlow() async {
        let captureService = EmittingCaptureService()
        let transcriptionService = EmittingTranscriptionService()
        let translationService = RecordingTranslationService()
        let viewModel = AppViewModel(
            settingsStore: makeSettingsStore(),
            captureService: captureService,
            transcriptionServiceFactory: { _ in transcriptionService },
            translationServiceFactory: { _ in translationService },
            overlayWindowManagerFactory: { _, _ in FakeOverlayWindowManager() }
        )

        viewModel.start()
        await waitUntil { captureService.didEnterStartCapture }

        captureService.emitFrame(Self.makeCapturedAudioFrame())
        await waitUntil { viewModel.diagnosticsText.contains("Frames received: 1") }

        await transcriptionService.emit(
            TranscriptEvent(sourceText: "hello", state: .partial)
        )
        await waitUntil { viewModel.diagnosticsText.contains("Transcript events: 1") }

        XCTAssertTrue(viewModel.diagnosticsText.contains("Last transcript: partial"))
    }

    func test_updateOverlayAppearance_persistsSettingsAndUpdatesViewModel() throws {
        let store = makeSettingsStore()
        let viewModel = AppViewModel(
            settingsStore: store,
            captureService: FakeCaptureService(),
            overlayWindowManagerFactory: { _, _ in FakeOverlayWindowManager() }
        )

        viewModel.updateOverlayOpacity(0.58)
        viewModel.updateOverlayWidth(1180)
        viewModel.updateOverlayHeight(1080)
        viewModel.updateOverlayFontSize(24)

        XCTAssertEqual(viewModel.overlayViewModel.overlayOpacity, 0.58)
        XCTAssertEqual(viewModel.overlayViewModel.overlayWidth, 1180)
        XCTAssertEqual(viewModel.overlayViewModel.overlayHeight, 1080)
        XCTAssertEqual(viewModel.overlayViewModel.fontSize, 24)
        XCTAssertEqual(
            viewModel.overlayViewModel.maximumVisibleLines,
            AppSettings.derivedMaximumVisibleLines(overlayHeight: 1080, fontSize: 24)
        )

        let restored = store.load()
        XCTAssertEqual(restored.overlayOpacity, 0.58)
        XCTAssertEqual(restored.overlayWidth, 1180)
        XCTAssertEqual(restored.overlayHeight, 1080)
        XCTAssertEqual(restored.fontSize, 24)
        XCTAssertEqual(
            restored.maximumVisibleLines,
            AppSettings.derivedMaximumVisibleLines(overlayHeight: 1080, fontSize: 24)
        )
    }

    func test_updateLanguagePair_persistsSelectionWhileIdle() {
        let store = makeSettingsStore()
        let viewModel = AppViewModel(
            settingsStore: store,
            captureService: FakeCaptureService(),
            overlayWindowManagerFactory: { _, _ in FakeOverlayWindowManager() }
        )

        viewModel.updateLanguagePair(.japaneseToEnglish)

        XCTAssertEqual(viewModel.languagePair, .japaneseToEnglish)
        XCTAssertEqual(store.load().languagePair, .japaneseToEnglish)
    }

    func test_updateLanguagePair_ignoresSelectionWhileRunning() async throws {
        let store = makeSettingsStore()
        let captureService = RecordingCaptureService()
        let transcriptionService = RecordingTranscriptionService()
        let translationService = RecordingTranslationService()
        let viewModel = AppViewModel(
            settingsStore: store,
            captureService: captureService,
            transcriptionServiceFactory: { _ in transcriptionService },
            translationServiceFactory: { _ in translationService },
            overlayWindowManagerFactory: { _, _ in FakeOverlayWindowManager() }
        )

        viewModel.start()
        await waitUntil { captureService.didEnterStartCapture }

        viewModel.updateLanguagePair(.japaneseToEnglish)

        XCTAssertEqual(viewModel.languagePair, .englishToJapanese)
        XCTAssertEqual(store.load().languagePair, .englishToJapanese)
    }

    func test_initialize_persistsManualOverlayResize() async {
        let overlayWindowManager = FakeOverlayWindowManager()
        let store = makeSettingsStore()
        let viewModel = AppViewModel(
            settingsStore: store,
            captureService: FakeCaptureService(),
            overlayWindowManagerFactory: { _, onSizeChange in
                overlayWindowManager.onSizeChange = onSizeChange
                return overlayWindowManager
            }
        )

        viewModel.initialize()
        overlayWindowManager.simulateResize(to: CGSize(width: 1260, height: 360))
        await Task.yield()

        XCTAssertEqual(viewModel.overlayViewModel.overlayWidth, 1260)
        XCTAssertEqual(viewModel.overlayViewModel.overlayHeight, 360)
        XCTAssertEqual(store.load().overlayWidth, 1260)
        XCTAssertEqual(store.load().overlayHeight, 360)
    }

    private func makeSettingsStore() -> AppSettingsStore {
        let suiteName = "AppViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettingsStore(userDefaults: defaults)
    }

    private static func makeCapturedAudioFrame() -> CapturedAudioFrame {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
        buffer.frameLength = 480
        return CapturedAudioFrame(buffer: buffer, when: .zero)
    }

    private func waitUntil(
        _ condition: @MainActor @escaping () -> Bool,
        iterations: Int = 50,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<iterations {
            if condition() {
                return
            }

            await Task.yield()
        }

        XCTFail("Timed out waiting for condition", file: file, line: line)
    }
}

@MainActor
private final class FakeCaptureService: CaptureServicing {
    private let startError: Error?

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func startCapture(
        inputHandler: @escaping @Sendable (CapturedAudioFrame) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        if let startError {
            throw startError
        }
    }

    func stopCapture() async {
    }
}

@MainActor
private final class RecordingCaptureService: CaptureServicing {
    private(set) var didEnterStartCapture = false
    private(set) var didStopCapture = false

    func startCapture(
        inputHandler: @escaping @Sendable (CapturedAudioFrame) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        didEnterStartCapture = true
    }

    func stopCapture() async {
        didStopCapture = true
    }
}

@MainActor
private final class EmittingCaptureService: CaptureServicing {
    private(set) var didEnterStartCapture = false
    private var inputHandler: (@Sendable (CapturedAudioFrame) -> Void)?

    func startCapture(
        inputHandler: @escaping @Sendable (CapturedAudioFrame) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        didEnterStartCapture = true
        self.inputHandler = inputHandler
    }

    func emitFrame(_ frame: CapturedAudioFrame) {
        inputHandler?(frame)
    }

    func stopCapture() async {
    }
}

@MainActor
private final class DeferredCaptureService: CaptureServicing {
    private(set) var didEnterStartCapture = false
    private(set) var didFinishStartCapture = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    func startCapture(
        inputHandler: @escaping @Sendable (CapturedAudioFrame) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        didEnterStartCapture = true
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
        errorHandler("stale start")
        didFinishStartCapture = true
    }

    func finishStartCapture() {
        startContinuation?.resume()
        startContinuation = nil
    }

    func stopCapture() async {
    }
}

private actor RecordingTranscriptionService: AppViewModelTranscriptionServicing {
    private(set) var didStart = false
    private(set) var didStop = false

    func start(
        eventHandler: @escaping @Sendable (TranscriptEvent) async -> Void,
        errorHandler: @escaping @Sendable (Error) async -> Void
    ) async throws {
        didStart = true
    }

    func append(frame: CapturedAudioFrame) async {
    }

    func stop() async {
        didStop = true
    }
}

private actor RuntimeFailingTranscriptionService: AppViewModelTranscriptionServicing {
    private var runtimeErrorHandler: (@Sendable (Error) async -> Void)?
    private(set) var didStop = false

    func start(
        eventHandler: @escaping @Sendable (TranscriptEvent) async -> Void,
        errorHandler: @escaping @Sendable (Error) async -> Void
    ) async throws {
        runtimeErrorHandler = errorHandler
    }

    func reportRuntimeFailure(_ error: Error) async {
        await runtimeErrorHandler?(error)
    }

    func append(frame: CapturedAudioFrame) async {
    }

    func stop() async {
        didStop = true
    }
}

private actor EmittingTranscriptionService: AppViewModelTranscriptionServicing {
    private var eventHandler: (@Sendable (TranscriptEvent) async -> Void)?

    func start(
        eventHandler: @escaping @Sendable (TranscriptEvent) async -> Void,
        errorHandler: @escaping @Sendable (Error) async -> Void
    ) async throws {
        self.eventHandler = eventHandler
    }

    func emit(_ event: TranscriptEvent) async {
        await eventHandler?(event)
    }

    func append(frame: CapturedAudioFrame) async {
    }

    func stop() async {
    }
}

@MainActor
private final class RecordingTranslationService: AppViewModelTranslationServicing {
    private(set) var didPrepare = false

    func prepare() async throws {
        didPrepare = true
    }

    func translate(_ text: String) async throws -> String {
        text
    }
}

private enum TestError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            message
        }
    }
}

@MainActor
private final class FakeOverlayWindowManager: OverlayWindowManaging {
    private(set) var didShow = false
    var onSizeChange: (@MainActor (CGSize) -> Void)?

    func show() {
        didShow = true
    }

    func simulateResize(to size: CGSize) {
        onSizeChange?(size)
    }
}
