import Foundation

enum AppState: Equatable, Sendable {
    case idle
    case preparing
    case capturing
    case transcribing
    case degraded(reason: AppError)
    case error(AppError)

    var isRunning: Bool {
        switch self {
        case .capturing, .transcribing, .degraded:
            true
        case .idle, .preparing, .error:
            false
        }
    }

    var statusText: String {
        switch self {
        case .idle:
            "Idle"
        case .preparing:
            "Preparing"
        case .capturing:
            "Capturing"
        case .transcribing:
            "Transcribing"
        case .degraded(let reason), .error(let reason):
            reason.userFacingMessage
        }
    }
}
