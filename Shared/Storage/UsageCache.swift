import Foundation

/// Shared cache the host app writes to and the widget extension reads from.
/// The widget never makes network calls itself — it only ever reads what's here.
enum UsageCache {
    private static let key = "usageSnapshot.v1"

    static func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }

    static func load() -> UsageSnapshot {
        guard let data = AppGroup.defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) else {
            return .placeholder
        }
        return snapshot
    }
}
