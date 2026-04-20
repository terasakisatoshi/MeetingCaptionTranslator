import AVFoundation
import CoreMedia
import XCTest
@testable import MeetingCaptionTranslator

@MainActor
final class AppViewModelTests: XCTestCase {
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
