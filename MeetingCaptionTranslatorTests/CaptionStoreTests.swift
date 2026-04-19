import XCTest
@testable import MeetingCaptionTranslator

final class CaptionStoreTests: XCTestCase {
    func test_store_appends_new_partial_line() {
        var store = CaptionStore(maximumVisibleLines: 3)

        store.ingest(sourceText: "hello", translatedText: nil, state: .partial, at: .distantPast)

        XCTAssertEqual(store.visibleLines.count, 1)
        XCTAssertEqual(store.visibleLines[0].sourceText, "hello")
        XCTAssertEqual(store.visibleLines[0].state, .partial)
    }

    func test_store_replaces_existing_partial_line() {
        var store = CaptionStore(maximumVisibleLines: 3)

        let first = store.ingest(sourceText: "hello", translatedText: nil, state: .partial, at: .distantPast)
        let second = store.ingest(sourceText: "hello world", translatedText: "こんにちは", state: .partial, at: .now)

        XCTAssertEqual(store.visibleLines.count, 1)
        XCTAssertEqual(store.visibleLines[0].id, first.id)
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(store.visibleLines[0].sourceText, "hello world")
        XCTAssertEqual(store.visibleLines[0].translatedText, "こんにちは")
    }

    func test_store_finalizes_partial_line_in_place() {
        var store = CaptionStore(maximumVisibleLines: 3)

        let first = store.ingest(sourceText: "hello", translatedText: nil, state: .partial, at: .distantPast)
        let finalized = store.ingest(sourceText: "hello world", translatedText: "こんにちは", state: .final, at: .now)

        XCTAssertEqual(store.visibleLines.count, 1)
        XCTAssertEqual(finalized.id, first.id)
        XCTAssertEqual(store.visibleLines[0].state, .final)
        XCTAssertEqual(store.visibleLines[0].translatedText, "こんにちは")
    }

    func test_store_trims_old_lines_to_maximum() {
        var store = CaptionStore(maximumVisibleLines: 3)

        _ = store.ingest(sourceText: "one", translatedText: "1", state: .final, at: .distantPast)
        _ = store.ingest(sourceText: "two", translatedText: "2", state: .final, at: .distantPast)
        _ = store.ingest(sourceText: "three", translatedText: "3", state: .final, at: .distantPast)
        _ = store.ingest(sourceText: "four", translatedText: "4", state: .final, at: .distantPast)

        XCTAssertEqual(store.visibleLines.map(\.sourceText), ["two", "three", "four"])
    }
}
