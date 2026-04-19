import Foundation

enum AppError: Error, Equatable, Sendable {
    case translationUnavailable

    var userFacingMessage: String {
        switch self {
        case .translationUnavailable:
            "Translation unavailable"
        }
    }
}
