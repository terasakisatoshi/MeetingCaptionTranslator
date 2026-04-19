import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var overlayOpacity: Double
    var fontSize: Double
    var maximumVisibleLines: Int
    var isClickThroughEnabled: Bool
    var languagePair: CaptionLanguagePair

    static let defaultValue = AppSettings(
        overlayOpacity: 0.82,
        fontSize: 24,
        maximumVisibleLines: 4,
        isClickThroughEnabled: true,
        languagePair: .defaultPair
    )
}
