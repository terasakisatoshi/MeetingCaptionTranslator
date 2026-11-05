import Foundation

struct CaptionLanguagePair: Codable, Equatable, Sendable, Hashable, Identifiable {
    let sourceLanguage: String
    let targetLanguage: String
    let speechLocaleIdentifier: String
    let displayTitle: String

    var id: String {
        "\(sourceLanguage)-\(targetLanguage)"
    }

    static let englishToJapanese = CaptionLanguagePair(
        sourceLanguage: "en",
        targetLanguage: "ja",
        speechLocaleIdentifier: "en-US",
        displayTitle: "English -> Japanese"
    )

    static let japaneseToEnglish = CaptionLanguagePair(
        sourceLanguage: "ja",
        targetLanguage: "en",
        speechLocaleIdentifier: "ja-JP",
        displayTitle: "Japanese -> English"
    )

    // Each utterance is translated in the direction its own text calls for.
    static let auto = CaptionLanguagePair(
        sourceLanguage: "auto",
        targetLanguage: "auto",
        speechLocaleIdentifier: "en-US",
        displayTitle: "Auto (EN <-> JA)"
    )

    static let supportedPairs: [CaptionLanguagePair] = [
        .englishToJapanese,
        .japaneseToEnglish,
        .auto
    ]

    var isAutomatic: Bool {
        sourceLanguage == "auto"
    }

    // Kana or kanji anywhere marks the text as Japanese: English transcripts do not contain them,
    // while Japanese ones often carry Latin-script names and terms.
    static func translationDirection(forSourceText text: String) -> CaptionLanguagePair {
        let isJapanese = text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value)
        }
        return isJapanese ? .japaneseToEnglish : .englishToJapanese
    }

    static let defaultPair = englishToJapanese

    init(
        sourceLanguage: String,
        targetLanguage: String,
        speechLocaleIdentifier: String,
        displayTitle: String
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.speechLocaleIdentifier = speechLocaleIdentifier
        self.displayTitle = displayTitle
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceLanguage = try container.decode(String.self, forKey: .sourceLanguage)
        let targetLanguage = try container.decode(String.self, forKey: .targetLanguage)

        if let supportedPair = Self.supportedPairs.first(where: {
            $0.sourceLanguage == sourceLanguage && $0.targetLanguage == targetLanguage
        }) {
            self = supportedPair
            return
        }

        self.init(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            speechLocaleIdentifier: try container.decodeIfPresent(String.self, forKey: .speechLocaleIdentifier) ?? Locale.current.identifier,
            displayTitle: try container.decodeIfPresent(String.self, forKey: .displayTitle) ?? "\(sourceLanguage) -> \(targetLanguage)"
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceLanguage, forKey: .sourceLanguage)
        try container.encode(targetLanguage, forKey: .targetLanguage)
        try container.encode(speechLocaleIdentifier, forKey: .speechLocaleIdentifier)
        try container.encode(displayTitle, forKey: .displayTitle)
    }

    private enum CodingKeys: String, CodingKey {
        case sourceLanguage
        case targetLanguage
        case speechLocaleIdentifier
        case displayTitle
    }
}
