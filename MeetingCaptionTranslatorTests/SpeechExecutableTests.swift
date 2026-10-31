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
}
