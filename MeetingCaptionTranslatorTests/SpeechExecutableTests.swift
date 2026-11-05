import XCTest
@testable import MeetingCaptionTranslator

final class SpeechExecutableTests: XCTestCase {
    func test_prefers_bundled_worker_over_system_installations() {
        let path = HaasTranscriptionService.executablePath(
            bundledPath: "/app/speech", home: "/home/user", isExecutable: { _ in true }
        )
        XCTAssertEqual(path, "/app/speech")
    }

    func test_falls_back_when_bundled_worker_is_missing() {
        let path = HaasTranscriptionService.executablePath(
            bundledPath: "/app/speech", home: "/home/user", isExecutable: { $0 == "/home/user/.local/bin/speech" }
        )
        XCTAssertEqual(path, "/home/user/.local/bin/speech")
    }

    func test_worker_runs_qwen3_asr_without_a_fixed_language_in_auto_mode() {
        XCTAssertEqual(
            HaasTranscriptionService.workerArguments(for: .auto),
            ["worker", "qwen3-asr-0.6b"]
        )
    }

    func test_worker_keeps_a_fixed_language_for_fixed_directions() {
        XCTAssertEqual(
            HaasTranscriptionService.workerArguments(for: .englishToJapanese),
            ["worker", "qwen3-asr-0.6b", "--language", "en"]
        )
        XCTAssertEqual(
            HaasTranscriptionService.workerArguments(for: .japaneseToEnglish),
            ["worker", "haas-ja-v1.0"]
        )
    }
}
