import Speech
import XCTest
@testable import MeetingCaptionTranslator

final class SpeechTranscriberPreparationTests: XCTestCase {
    func test_prepare_throwsForUnsupportedLocale() async {
        let backend = FakeSpeechTranscriberPreparationBackend()
        let preparation = SpeechTranscriberPreparation(
            requestedLocale: Locale(identifier: "en-US"),
            preset: .timeIndexedProgressiveTranscription,
            backend: backend
        )

        await XCTAssertThrowsErrorAsync(try await preparation.prepare()) { error in
            XCTAssertEqual(
                error as? SpeechTranscriberPreparationError,
                .unsupportedLocale("en-US")
            )
        }
    }

    func test_prepare_reservesLocaleAndReturnsResolvedLocaleWhenAssetsInstalled() async throws {
        let backend = FakeSpeechTranscriberPreparationBackend(
            resolvedLocale: Locale(identifier: "en_US"),
            assetStatus: .installed
        )
        let preparation = SpeechTranscriberPreparation(
            requestedLocale: Locale(identifier: "en-US"),
            preset: .timeIndexedProgressiveTranscription,
            backend: backend
        )

        let resolvedLocale = try await preparation.prepare()

        XCTAssertEqual(resolvedLocale.identifier, "en_US")
        XCTAssertEqual(backend.recordedOperations, ["resolve", "reserve:en_US", "status:en_US"])
    }

    func test_prepare_downloadsAssetsWhenAvailableButNotInstalled() async throws {
        let backend = FakeSpeechTranscriberPreparationBackend(
            resolvedLocale: Locale(identifier: "en_US"),
            assetStatus: .supported
        )
        let preparation = SpeechTranscriberPreparation(
            requestedLocale: Locale(identifier: "en-US"),
            preset: .timeIndexedProgressiveTranscription,
            backend: backend
        )

        _ = try await preparation.prepare()

        XCTAssertEqual(
            backend.recordedOperations,
            ["resolve", "reserve:en_US", "status:en_US", "installationRequest:en_US", "download"]
        )
    }

    func test_prepare_throwsWhenAssetsNeedInstallButNoRequestIsAvailable() async {
        let backend = FakeSpeechTranscriberPreparationBackend(
            resolvedLocale: Locale(identifier: "en_US"),
            assetStatus: .supported,
            installationRequest: nil
        )
        let preparation = SpeechTranscriberPreparation(
            requestedLocale: Locale(identifier: "en-US"),
            preset: .timeIndexedProgressiveTranscription,
            backend: backend
        )

        await XCTAssertThrowsErrorAsync(try await preparation.prepare()) { error in
            XCTAssertEqual(
                error as? SpeechTranscriberPreparationError,
                .assetsUnavailable("en_US")
            )
        }
    }
}

private final class FakeSpeechTranscriberPreparationBackend: SpeechTranscriberPreparationBacking {
    private let resolvedLocale: Locale?
    private let assetStatus: SpeechAssetAvailability
    private let installationRequest: FakeSpeechAssetInstallationRequest?

    private(set) var recordedOperations: [String] = []

    init(
        resolvedLocale: Locale? = nil,
        assetStatus: SpeechAssetAvailability = .unsupported,
        installationRequest: FakeSpeechAssetInstallationRequest? = FakeSpeechAssetInstallationRequest()
    ) {
        self.resolvedLocale = resolvedLocale
        self.assetStatus = assetStatus
        self.installationRequest = installationRequest
    }

    func supportedLocale(equivalentTo locale: Locale) async -> Locale? {
        recordedOperations.append("resolve")
        return resolvedLocale
    }

    func reserve(locale: Locale) async throws {
        recordedOperations.append("reserve:\(locale.identifier)")
    }

    func assetStatus(for locale: Locale, preset: SpeechTranscriber.Preset) async -> SpeechAssetAvailability {
        recordedOperations.append("status:\(locale.identifier)")
        return assetStatus
    }

    func assetInstallationRequest(
        for locale: Locale,
        preset: SpeechTranscriber.Preset
    ) async throws -> (any SpeechAssetInstallationRequesting)? {
        recordedOperations.append("installationRequest:\(locale.identifier)")
        installationRequest?.onDownload = { [weak self] in
            self?.recordedOperations.append("download")
        }
        return installationRequest
    }
}

private final class FakeSpeechAssetInstallationRequest: SpeechAssetInstallationRequesting {
    var onDownload: (() -> Void)?

    func downloadAndInstall() async throws {
        onDownload?()
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
