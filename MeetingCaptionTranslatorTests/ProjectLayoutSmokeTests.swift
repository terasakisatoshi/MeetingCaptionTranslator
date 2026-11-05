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

    func test_project_takes_sources_from_the_folders_without_listing_each_file() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: root.appendingPathComponent("MeetingCaptionTranslator.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertTrue(project.contains("isa = PBXFileSystemSynchronizedRootGroup;"))
        XCTAssertFalse(project.contains("ContentView.swift"), "A source file is still listed by name")
        XCTAssertFalse(project.contains("ProjectLayoutSmokeTests.swift"), "A test file is still listed by name")
    }
}
