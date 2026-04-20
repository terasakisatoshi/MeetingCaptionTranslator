import XCTest

final class InfoPlistMetadataTests: XCTestCase {
    func test_infoPlist_containsAudioCaptureUsageDescription() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = root.appendingPathComponent("MeetingCaptionTranslator/Resources/Info.plist")
        let plist = NSDictionary(contentsOf: infoPlistURL)

        XCTAssertEqual(
            plist?["NSAudioCaptureUsageDescription"] as? String,
            "This app captures Mac playback audio to transcribe live captions."
        )
    }

    func test_generatorSeedInfoPlist_containsAudioCaptureUsageDescription() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let generatorURL = root.appendingPathComponent("tools/generate_project.rb")
        let generator = try String(contentsOf: generatorURL)

        XCTAssertTrue(generator.contains("<key>NSAudioCaptureUsageDescription</key>"))
        XCTAssertTrue(generator.contains("This app captures Mac playback audio to transcribe live captions."))
    }
}
