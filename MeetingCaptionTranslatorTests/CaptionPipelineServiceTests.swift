import XCTest
@testable import MeetingCaptionTranslator

@MainActor
final class CaptionPipelineServiceTests: XCTestCase {
    func test_partial_transcript_updates_visible_lines_without_translation() async {
        let service = CaptionPipelineService(maximumVisibleLines: 4) { _ in
            XCTFail("translation should not run for partial transcripts")
            return ""
        }

        await service.handleTranscript(.init(sourceText: "hello", state: .partial))

        XCTAssertEqual(service.visibleLines.count, 1)
        XCTAssertEqual(service.visibleLines[0].sourceText, "hello")
        XCTAssertNil(service.visibleLines[0].translatedText)
        XCTAssertEqual(service.appState, .transcribing)
    }

    func test_final_transcript_applies_translation() async {
        let service = CaptionPipelineService(maximumVisibleLines: 4) { sourceText in
            XCTAssertEqual(sourceText, "hello world.")
            return "こんにちは"
        }

        await service.handleTranscript(.init(sourceText: "hello world.", state: .final))

        XCTAssertEqual(service.visibleLines.count, 1)
        XCTAssertEqual(service.visibleLines[0].sourceText, "hello world.")
        XCTAssertEqual(service.visibleLines[0].translatedText, "こんにちは")
        XCTAssertEqual(service.visibleLines[0].state, .final)
        XCTAssertEqual(service.appState, .transcribing)
    }

    func test_translation_failure_falls_back_to_english_only() async {
        let service = CaptionPipelineService(maximumVisibleLines: 4) { _ in
            throw AppError.translationUnavailable
        }

        await service.handleTranscript(.init(sourceText: "system audio.", state: .final))

        XCTAssertEqual(service.visibleLines.count, 1)
        XCTAssertEqual(service.visibleLines[0].sourceText, "system audio.")
        XCTAssertNil(service.visibleLines[0].translatedText)
        XCTAssertEqual(service.appState, .degraded(reason: .translationUnavailable))
    }

    func test_stop_clears_transient_state() async {
        let service = CaptionPipelineService(maximumVisibleLines: 4) { _ in
            "こんにちは"
        }

        await service.handleTranscript(.init(sourceText: "hello", state: .partial))
        service.stop()

        XCTAssertTrue(service.visibleLines.isEmpty)
        XCTAssertEqual(service.appState, .idle)
    }

    func test_pipeline_preserves_history_beyond_visible_limit() async {
        let service = CaptionPipelineService(maximumVisibleLines: 2) { sourceText in
            "ja:\(sourceText)"
        }

        await service.handleTranscript(.init(sourceText: "one.", state: .final))
        await service.handleTranscript(.init(sourceText: "two.", state: .final))
        await service.handleTranscript(.init(sourceText: "three.", state: .final))

        XCTAssertEqual(service.historyLines.map(\.sourceText), ["one.", "two.", "three."])
        XCTAssertEqual(service.visibleLines.map(\.sourceText), ["two.", "three."])
    }

    func test_final_fragment_without_a_sentence_end_waits_untranslated() async {
        let service = CaptionPipelineService(maximumVisibleLines: 4, flushSleep: { _ in try await Task.sleep(for: .seconds(60)) }) { _ in
            XCTFail("a fragment should not be translated before its sentence ends")
            return ""
        }

        await service.handleTranscript(.init(sourceText: "今日は会議で", state: .final))

        XCTAssertEqual(service.visibleLines.count, 1)
        XCTAssertEqual(service.visibleLines[0].sourceText, "今日は会議で")
        XCTAssertNil(service.visibleLines[0].translatedText)
        XCTAssertEqual(service.visibleLines[0].state, .partial)
        service.stop()
    }

    func test_fragments_are_translated_together_when_the_sentence_ends() async {
        var translated: [String] = []
        let service = CaptionPipelineService(maximumVisibleLines: 4, flushSleep: { _ in try await Task.sleep(for: .seconds(60)) }) { text in
            translated.append(text)
            return "en:\(text)"
        }

        await service.handleTranscript(.init(sourceText: "今日は会議で", state: .final))
        await service.handleTranscript(.init(sourceText: "新しい案を説明します。", state: .final))

        XCTAssertEqual(translated, ["今日は会議で新しい案を説明します。"])
        XCTAssertEqual(service.historyLines.map(\.sourceText), ["今日は会議で新しい案を説明します。"])
        XCTAssertEqual(service.historyLines.map(\.state), [.final])
        service.stop()
    }

    func test_each_sentence_in_one_utterance_becomes_its_own_line() async {
        let service = CaptionPipelineService(maximumVisibleLines: 4, flushSleep: { _ in try await Task.sleep(for: .seconds(60)) }) { text in
            "t:\(text)"
        }

        await service.handleTranscript(.init(sourceText: "Let's begin. 始めましょう。それでは", state: .final))

        XCTAssertEqual(service.historyLines.map(\.sourceText), ["Let's begin.", "始めましょう。", "それでは"])
        XCTAssertEqual(service.historyLines.map(\.translatedText), ["t:Let's begin.", "t:始めましょう。", nil])
        service.stop()
    }

    func test_partial_transcript_is_shown_after_held_text() async {
        let service = CaptionPipelineService(maximumVisibleLines: 4, flushSleep: { _ in try await Task.sleep(for: .seconds(60)) }) { _ in "" }

        await service.handleTranscript(.init(sourceText: "Thank you for", state: .final))
        await service.handleTranscript(.init(sourceText: "joining", state: .partial))

        XCTAssertEqual(service.visibleLines.map(\.sourceText), ["Thank you for joining"])
        service.stop()
    }

    func test_held_text_is_translated_after_a_quiet_period() async {
        let sleeper = ManualSleeper()
        var updates = 0
        let service = CaptionPipelineService(maximumVisibleLines: 4, flushSleep: sleeper.sleep) { text in
            "en:\(text)"
        }
        service.onUpdate = { updates += 1 }

        await service.handleTranscript(.init(sourceText: "それでは", state: .final))
        await sleeper.waitForSleep()
        sleeper.wake()
        for _ in 0..<50 where service.visibleLines.first?.state != .final { await Task.yield() }

        XCTAssertEqual(service.visibleLines.map(\.sourceText), ["それでは"])
        XCTAssertEqual(service.visibleLines.map(\.translatedText), ["en:それでは"])
        XCTAssertEqual(service.visibleLines.map(\.state), [.final])
        XCTAssertEqual(updates, 1)
    }

    func test_new_transcript_postpones_the_quiet_period_flush() async {
        let sleeper = ManualSleeper()
        var translated: [String] = []
        let service = CaptionPipelineService(maximumVisibleLines: 4, flushSleep: sleeper.sleep) { text in
            translated.append(text)
            return text
        }

        await service.handleTranscript(.init(sourceText: "今日は会議で", state: .final))
        await sleeper.waitForSleep()
        await service.handleTranscript(.init(sourceText: "新しい案を", state: .final))
        sleeper.wake()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(translated, [])
        service.stop()
    }
}

extension CaptionPipelineServiceTests {
    func test_flushed_fragment_keeps_its_place_when_translation_finishes_after_a_newer_sentence() async {
        let sleeper = ManualSleeper()
        let translator = HeldTranslator(held: "First fragment")
        let service = CaptionPipelineService(maximumVisibleLines: 4, flushSleep: sleeper.sleep, translator: translator.translate)

        await service.handleTranscript(.init(sourceText: "First fragment", state: .final))
        await sleeper.waitForSleep()
        sleeper.wake()
        await translator.waitUntilHeld()
        let newer = Task { await service.handleTranscript(.init(sourceText: "Second sentence.", state: .final)) }
        for _ in 0..<20 { await Task.yield() }
        translator.release()
        await newer.value
        for _ in 0..<50 where service.historyLines.count < 2 { await Task.yield() }

        XCTAssertEqual(service.historyLines.map(\.sourceText), ["First fragment", "Second sentence."])
        XCTAssertEqual(service.historyLines.map(\.state), [.final, .final])
    }
}

@MainActor
private final class HeldTranslator {
    private let held: String
    private var continuation: CheckedContinuation<Void, Never>?
    private var isHeld = false

    init(held: String) {
        self.held = held
    }

    var translate: (String) async throws -> String {
        { [self] text in
            if text == held {
                isHeld = true
                await withCheckedContinuation { continuation = $0 }
            }
            return "t:\(text)"
        }
    }

    func waitUntilHeld() async {
        for _ in 0..<50 where !isHeld { await Task.yield() }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class ManualSleeper {
    private var continuations: [CheckedContinuation<Void, Error>] = []

    var sleep: @MainActor (Duration) async throws -> Void {
        { [self] _ in
            try await withCheckedThrowingContinuation { continuations.append($0) }
            try Task.checkCancellation()
        }
    }

    func waitForSleep() async {
        for _ in 0..<50 where continuations.isEmpty { await Task.yield() }
    }

    // Ends the oldest sleep, leaving any timer started after it waiting.
    func wake() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}
