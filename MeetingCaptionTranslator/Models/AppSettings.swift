import Foundation

enum TranscriptionEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple, haas
    var id: Self { self }
    var title: String { self == .apple ? "Apple Speech" : "Haas-ja (speech.cpp)" }
}

struct AppSettings: Codable, Equatable, Sendable {
    var overlayOpacity: Double
    var fontSize: Double
    var maximumVisibleLines: Int
    var overlayWidth: Double
    var overlayHeight: Double
    var languagePair: CaptionLanguagePair
    var transcriptionEngine: TranscriptionEngine = .apple

    static let overlayOpacityRange: ClosedRange<Double> = 0.2...0.9
    static let overlayWidthRange: ClosedRange<Double> = 640...1600
    static let overlayHeightRange: ClosedRange<Double> = 180...1440
    static let fontSizeRange: ClosedRange<Double> = 18...56

    static let defaultValue = AppSettings(
        overlayOpacity: 0.58,
        fontSize: 24,
        maximumVisibleLines: 4,
        overlayWidth: 960,
        overlayHeight: 220,
        languagePair: .defaultPair
    )

    init(
        overlayOpacity: Double,
        fontSize: Double,
        maximumVisibleLines: Int,
        overlayWidth: Double,
        overlayHeight: Double,
        languagePair: CaptionLanguagePair
    ) {
        let clampedOpacity = Self.clamp(overlayOpacity, to: Self.overlayOpacityRange)
        let clampedFontSize = Self.clamp(fontSize, to: Self.fontSizeRange)
        let clampedWidth = Self.clamp(overlayWidth, to: Self.overlayWidthRange)
        let clampedHeight = Self.clamp(overlayHeight, to: Self.overlayHeightRange)

        self.overlayOpacity = clampedOpacity
        self.fontSize = clampedFontSize
        self.maximumVisibleLines = max(
            1,
            Self.derivedMaximumVisibleLines(
                overlayHeight: clampedHeight,
                fontSize: clampedFontSize
            )
        )
        self.overlayWidth = clampedWidth
        self.overlayHeight = clampedHeight
        self.languagePair = languagePair
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            overlayOpacity: try container.decodeIfPresent(Double.self, forKey: .overlayOpacity) ?? Self.defaultValue.overlayOpacity,
            fontSize: try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? Self.defaultValue.fontSize,
            maximumVisibleLines: try container.decodeIfPresent(Int.self, forKey: .maximumVisibleLines) ?? Self.defaultValue.maximumVisibleLines,
            overlayWidth: try container.decodeIfPresent(Double.self, forKey: .overlayWidth) ?? Self.defaultValue.overlayWidth,
            overlayHeight: try container.decodeIfPresent(Double.self, forKey: .overlayHeight) ?? Self.defaultValue.overlayHeight,
            languagePair: try container.decodeIfPresent(CaptionLanguagePair.self, forKey: .languagePair) ?? Self.defaultValue.languagePair
        )
        transcriptionEngine = try container.decodeIfPresent(TranscriptionEngine.self, forKey: .transcriptionEngine) ?? .apple
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(overlayOpacity, forKey: .overlayOpacity)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(maximumVisibleLines, forKey: .maximumVisibleLines)
        try container.encode(overlayWidth, forKey: .overlayWidth)
        try container.encode(overlayHeight, forKey: .overlayHeight)
        try container.encode(languagePair, forKey: .languagePair)
        try container.encode(transcriptionEngine, forKey: .transcriptionEngine)
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    static func derivedMaximumVisibleLines(
        overlayHeight: Double,
        fontSize: Double
    ) -> Int {
        let estimatedRowHeight = max(44, (fontSize * 2.0) + 4)
        return max(1, Int(floor(overlayHeight / estimatedRowHeight)))
    }

    private enum CodingKeys: String, CodingKey {
        case overlayOpacity
        case fontSize
        case maximumVisibleLines
        case overlayWidth
        case overlayHeight
        case languagePair
        case transcriptionEngine
    }
}
