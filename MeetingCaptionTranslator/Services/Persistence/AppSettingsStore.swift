import Foundation

struct AppSettingsStore {
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let key = "app_settings"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func save(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        userDefaults.set(data, forKey: key)
    }

    func load() -> AppSettings {
        guard let data = userDefaults.data(forKey: key) else {
            return .defaultValue
        }

        return (try? decoder.decode(AppSettings.self, from: data)) ?? .defaultValue
    }
}
