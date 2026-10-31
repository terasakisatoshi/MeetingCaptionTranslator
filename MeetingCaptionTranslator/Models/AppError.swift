import Foundation

enum AppError: Error, Equatable, Sendable {
    case systemAudioCaptureUnavailable
    case microphoneCaptureUnavailable
    case transcriptionUnavailable
    case translationUnavailable

    var userFacingMessage: String {
        switch self {
        case .systemAudioCaptureUnavailable:
            "System audio capture unavailable"
        case .microphoneCaptureUnavailable:
            "Microphone capture unavailable"
        case .transcriptionUnavailable:
            "Transcription unavailable"
        case .translationUnavailable:
            "Translation unavailable"
        }
    }
}
