import Foundation

// Holds recognized fragments until a sentence ends, so a sentence split by a pause is translated whole.
struct SentenceBuffer {
    private(set) var pending = ""

    // Returns the sentences completed by `text`, in order, and keeps the unfinished rest.
    mutating func append(_ text: String) -> [String] {
        pending = Self.join(pending, text.trimmingCharacters(in: .whitespacesAndNewlines))
        var sentences: [String] = []
        var start = pending.startIndex
        var index = pending.startIndex
        while index < pending.endIndex {
            let next = pending.index(after: index)
            if Self.endsSentence(pending[index], followedBy: next < pending.endIndex ? pending[next] : nil) {
                let sentence = pending[start..<next].trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
                start = next
            }
            index = next
        }
        pending = pending[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        return sentences
    }

    // Releases the unfinished text, for when no sentence end is coming.
    mutating func flush() -> String? {
        defer { pending = "" }
        return pending.isEmpty ? nil : pending
    }

    // The held text followed by text not yet final, as one caption.
    func joined(with text: String) -> String {
        Self.join(pending, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func endsSentence(_ character: Character, followedBy next: Character?) -> Bool {
        switch character {
        case "。", "．", "？", "！", "?", "!":
            return true
        case ".":
            // "3.5" or "e.g" continue the sentence; a period ends one only before a space or the end.
            return next.map(\.isWhitespace) ?? true
        default:
            return false
        }
    }

    // Japanese is written without spaces between words; Latin-script fragments need one.
    private static func join(_ head: String, _ tail: String) -> String {
        guard let last = head.last, let first = tail.first else { return head + tail }
        return isCJK(last) || isCJK(first) ? head + tail : head + " " + tail
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.value >= 0x2E80 }
    }
}
