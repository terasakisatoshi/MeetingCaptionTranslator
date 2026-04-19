import XCTest

final class ProjectLayoutSmokeTests: XCTestCase {
    func test_expected_seed_files_exist() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let requiredPaths = [
            "MeetingCaptionTranslator/App/MeetingCaptionTranslatorApp.swift",
            "MeetingCaptionTranslator/App/ContentView.swift",
            "MeetingCaptionTranslator/Resources/Info.plist",
        ]

        for path in requiredPaths {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "Expected file missing: \(path)"
            )
        }
    }
}
