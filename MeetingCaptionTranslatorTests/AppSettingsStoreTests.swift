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
            isClickThroughEnabled: true,
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
}
