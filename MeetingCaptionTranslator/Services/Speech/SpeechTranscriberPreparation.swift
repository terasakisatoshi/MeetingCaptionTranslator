import Foundation
import Speech

enum SpeechAssetAvailability: Equatable {
    case unsupported
    case supported
    case downloading
    case installed
}

enum SpeechTranscriberPreparationError: Error, Equatable, LocalizedError {
    case unsupportedLocale(String)
    case assetsUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let localeIdentifier):
            "Speech transcription is unavailable for locale \(localeIdentifier)"
        case .assetsUnavailable(let localeIdentifier):
            "Speech transcription assets are unavailable for locale \(localeIdentifier)"
        }
    }
}

protocol SpeechAssetInstallationRequesting: AnyObject {
    func downloadAndInstall() async throws
}

protocol SpeechTranscriberPreparationBacking: AnyObject {
    func supportedLocale(equivalentTo locale: Locale) async -> Locale?
    func reserve(locale: Locale) async throws
    func assetStatus(for locale: Locale, preset: SpeechTranscriber.Preset) async -> SpeechAssetAvailability
    func assetInstallationRequest(
        for locale: Locale,
        preset: SpeechTranscriber.Preset
    ) async throws -> (any SpeechAssetInstallationRequesting)?
}

struct SpeechTranscriberPreparation {
    let requestedLocale: Locale
    let preset: SpeechTranscriber.Preset
    private let backend: any SpeechTranscriberPreparationBacking

    init(
        requestedLocale: Locale,
        preset: SpeechTranscriber.Preset,
        backend: any SpeechTranscriberPreparationBacking = DefaultSpeechTranscriberPreparationBackend()
    ) {
        self.requestedLocale = requestedLocale
        self.preset = preset
        self.backend = backend
    }

    func prepare() async throws -> Locale {
        guard let resolvedLocale = await backend.supportedLocale(equivalentTo: requestedLocale) else {
            throw SpeechTranscriberPreparationError.unsupportedLocale(requestedLocale.identifier)
        }

        try await backend.reserve(locale: resolvedLocale)

        switch await backend.assetStatus(for: resolvedLocale, preset: preset) {
        case .installed:
            return resolvedLocale
        case .supported, .downloading:
            guard let installationRequest = try await backend.assetInstallationRequest(
                for: resolvedLocale,
                preset: preset
            ) else {
                throw SpeechTranscriberPreparationError.assetsUnavailable(resolvedLocale.identifier)
            }

            try await installationRequest.downloadAndInstall()
            return resolvedLocale
        case .unsupported:
            throw SpeechTranscriberPreparationError.assetsUnavailable(resolvedLocale.identifier)
        }
    }
}

final class DefaultSpeechTranscriberPreparationBackend: SpeechTranscriberPreparationBacking {
    func supportedLocale(equivalentTo locale: Locale) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }

    func reserve(locale: Locale) async throws {
        _ = try await AssetInventory.reserve(locale: locale)
    }

    func assetStatus(for locale: Locale, preset: SpeechTranscriber.Preset) async -> SpeechAssetAvailability {
        let transcriber = SpeechTranscriber(locale: locale, preset: preset)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .unsupported:
            return .unsupported
        case .supported:
            return .supported
        case .downloading:
            return .downloading
        case .installed:
            return .installed
        @unknown default:
            return .unsupported
        }
    }

    func assetInstallationRequest(
        for locale: Locale,
        preset: SpeechTranscriber.Preset
    ) async throws -> (any SpeechAssetInstallationRequesting)? {
        let transcriber = SpeechTranscriber(locale: locale, preset: preset)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return nil
        }

        return DefaultSpeechAssetInstallationRequest(request: request)
    }
}

private final class DefaultSpeechAssetInstallationRequest: SpeechAssetInstallationRequesting {
    private let request: AssetInstallationRequest

    init(request: AssetInstallationRequest) {
        self.request = request
    }

    func downloadAndInstall() async throws {
        try await request.downloadAndInstall()
    }
}
