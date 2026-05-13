import Foundation

#if SWIFT_PACKAGE
import MatrixNewsCore
#endif

final class PreferenceSyncStore {
    private enum Key {
        static let settings = "matrix-news.viewer-settings"
        static let preferences = "matrix-news.user-preferences"
    }

    private let ubiquitousStore = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    func loadSettings() -> ViewerSettings {
        load(ViewerSettings.self, key: Key.settings) ?? .default
    }

    func saveSettings(_ settings: ViewerSettings) {
        save(settings, key: Key.settings)
    }

    func loadPreferences() -> UserPreferences {
        load(UserPreferences.self, key: Key.preferences) ?? .empty
    }

    func savePreferences(_ preferences: UserPreferences) {
        save(preferences, key: Key.preferences)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        ubiquitousStore.synchronize()

        if let data = ubiquitousStore.data(forKey: key),
           let decoded = try? JSONDecoder.matrixNews.decode(T.self, from: data) {
            return decoded
        }

        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder.matrixNews.decode(T.self, from: data) {
            return decoded
        }

        return nil
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder.matrixNews.encode(value) else { return }
        ubiquitousStore.set(data, forKey: key)
        ubiquitousStore.synchronize()
        defaults.set(data, forKey: key)
    }
}
