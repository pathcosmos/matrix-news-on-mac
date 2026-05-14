import Foundation

#if SWIFT_PACKAGE
import MatrixNewsCore
#endif

@MainActor
final class PreferenceSyncStore {
    private enum Key {
        static let settings = "matrix-news.viewer-settings"
        static let preferences = "matrix-news.user-preferences"
    }

    private static let flushDelay: Duration = .milliseconds(500)

    private let ubiquitousStore = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    private var cachedSettings: ViewerSettings?
    private var cachedPreferences: UserPreferences?
    private var lastPersistedSettingsHash: Int?
    private var lastPersistedPreferencesHash: Int?
    private var flushTask: Task<Void, Never>?

    func loadSettings() -> ViewerSettings {
        if let cached = cachedSettings { return cached }
        let value = decode(ViewerSettings.self, key: Key.settings) ?? .default
        cachedSettings = value
        return value
    }

    func saveSettings(_ settings: ViewerSettings) {
        cachedSettings = settings
        scheduleFlush()
    }

    func loadPreferences() -> UserPreferences {
        if let cached = cachedPreferences { return cached }
        let value = decode(UserPreferences.self, key: Key.preferences) ?? .empty
        cachedPreferences = value
        return value
    }

    func savePreferences(_ preferences: UserPreferences) {
        cachedPreferences = preferences
        scheduleFlush()
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
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

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flushDelay)
            guard !Task.isCancelled else { return }
            self?.flushPending()
        }
    }

    private func flushPending() {
        if let settings = cachedSettings,
           let data = try? JSONEncoder.matrixNews.encode(settings) {
            let hash = data.hashValue
            if hash != lastPersistedSettingsHash {
                ubiquitousStore.set(data, forKey: Key.settings)
                defaults.set(data, forKey: Key.settings)
                lastPersistedSettingsHash = hash
            }
        }
        if let preferences = cachedPreferences,
           let data = try? JSONEncoder.matrixNews.encode(preferences) {
            let hash = data.hashValue
            if hash != lastPersistedPreferencesHash {
                ubiquitousStore.set(data, forKey: Key.preferences)
                defaults.set(data, forKey: Key.preferences)
                lastPersistedPreferencesHash = hash
            }
        }
    }
}
