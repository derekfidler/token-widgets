import Foundation

enum AppGroup {
    /// A Team-ID-prefixed group works for macOS-only apps without requiring the
    /// group to be authorized by an embedded provisioning profile. This keeps
    /// local Developer ID/development builds and their extensions in the same
    /// protected container on macOS 15 and later.
    static let identifier = "ESYNZ5PVA4.dev.flatpay.tokenwidgets"

    static var defaults: UserDefaults {
        guard let d = UserDefaults(suiteName: identifier) else {
            fatalError("Could not open app group UserDefaults suite \(identifier). Check the App Groups entitlement matches on both targets.")
        }
        return d
    }
}
