import Foundation

enum CaptureTargetKind: String, Codable, Equatable, Sendable {
    case display
}

struct CaptureTarget: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let kind: CaptureTargetKind
}
