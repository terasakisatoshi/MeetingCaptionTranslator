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
}
