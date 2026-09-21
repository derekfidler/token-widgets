import Foundation

enum AccountMode: String, Codable {
    case personal
    case enterprise
}

enum AppSettings {
    private static let refreshIntervalKey = "refreshIntervalMinutes"
    private static let claudeModeKey = "claudeAccountMode"
    private static let chatgptModeKey = "chatgptAccountMode"

    static var refreshIntervalMinutes: Double {
        get {
            let stored = AppGroup.defaults.double(forKey: refreshIntervalKey)
            return stored > 0 ? stored : 15
        }
        set {
            AppGroup.defaults.set(min(60, max(5, newValue)), forKey: refreshIntervalKey)
        }
    }

    static func isStale(_ usage: ProductUsage, now: Date = Date()) -> Bool {
        guard usage.mode != .unavailable, usage.lastUpdated != .distantPast else { return true }
        let threshold = max(30, refreshIntervalMinutes * 2) * 60
        return now.timeIntervalSince(usage.lastUpdated) > threshold
    }

    static var claudeAccountMode: AccountMode? {
        get { mode(forKey: claudeModeKey) }
        set { setMode(newValue, forKey: claudeModeKey) }
    }

    static var chatgptAccountMode: AccountMode? {
        get { mode(forKey: chatgptModeKey) }
        set { setMode(newValue, forKey: chatgptModeKey) }
    }

    private static func mode(forKey key: String) -> AccountMode? {
        AppGroup.defaults.string(forKey: key).flatMap(AccountMode.init(rawValue:))
    }

    private static func setMode(_ mode: AccountMode?, forKey key: String) {
        if let mode {
            AppGroup.defaults.set(mode.rawValue, forKey: key)
        } else {
            AppGroup.defaults.removeObject(forKey: key)
        }
    }
}
