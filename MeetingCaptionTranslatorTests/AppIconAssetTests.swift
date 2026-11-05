import XCTest

final class AppIconAssetTests: XCTestCase {
    func test_appIconAssetCatalog_containsRequiredMacIconImages() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appIconURL = root.appendingPathComponent("MeetingCaptionTranslator/Resources/Assets.xcassets/AppIcon.appiconset")
        let contentsURL = appIconURL.appendingPathComponent("Contents.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: contentsURL.path))

        let data = try Data(contentsOf: contentsURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let images = try XCTUnwrap(json?["images"] as? [[String: String]])

        let filenames = Set(images.compactMap { $0["filename"] })
        let expectedFilenames: Set<String> = [
            "app-icon-16.png",
            "app-icon-32.png",
            "app-icon-64.png",
            "app-icon-128.png",
            "app-icon-256.png",
            "app-icon-512.png",
            "app-icon-1024.png",
        ]

        XCTAssertEqual(filenames, expectedFilenames)

        for filename in expectedFilenames {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: appIconURL.appendingPathComponent(filename).path),
                "Expected app icon image missing: \(filename)"
            )
        }
    }

    func test_project_configuresAppIconName() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: root.appendingPathComponent("MeetingCaptionTranslator.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertTrue(project.contains("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;"))
    }
}
