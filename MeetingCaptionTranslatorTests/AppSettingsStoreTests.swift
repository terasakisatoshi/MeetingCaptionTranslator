import XCTest
@testable import MeetingCaptionTranslator

final class AppSettingsStoreTests: XCTestCase {
    func test_store_round_trips_settings() throws {
        let suiteName = "AppSettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(userDefaults: defaults)
        let settings = AppSettings(
            overlayOpacity: 0.72,
            fontSize: 28,
            maximumVisibleLines: 5,
            overlayWidth: 1120,
            overlayHeight: 320,
            languagePair: .defaultPair
        )

        try store.save(settings)
        let restored = try XCTUnwrap(store.load())

        XCTAssertEqual(restored, settings)
    }

    func test_store_returns_defaults_when_nothing_saved() {
        let suiteName = "AppSettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.load(), .defaultValue)
    }

    func test_store_loads_legacy_settings_without_overlay_size_fields() throws {
        let suiteName = "AppSettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let legacyPayload = """
        {
          "overlayOpacity": 0.7,
          "fontSize": 26,
          "maximumVisibleLines": 5,
          "isClickThroughEnabled": true,
          "languagePair": {
            "sourceLanguage": "en",
            "targetLanguage": "ja"
          }
        }
        """
        defaults.set(try XCTUnwrap(legacyPayload.data(using: .utf8)), forKey: "app_settings")

        let restored = AppSettingsStore(userDefaults: defaults).load()

        XCTAssertEqual(restored.overlayOpacity, 0.7)
        XCTAssertEqual(restored.fontSize, 26)
        XCTAssertEqual(restored.overlayWidth, AppSettings.defaultValue.overlayWidth)
        XCTAssertEqual(restored.overlayHeight, AppSettings.defaultValue.overlayHeight)
        XCTAssertEqual(
            restored.maximumVisibleLines,
            AppSettings.derivedMaximumVisibleLines(
                overlayHeight: AppSettings.defaultValue.overlayHeight,
                fontSize: 26
            )
        )
        XCTAssertEqual(restored.languagePair, .defaultPair)
    }
}
