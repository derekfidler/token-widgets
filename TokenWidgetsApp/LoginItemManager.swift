import ServiceManagement

enum LoginItemManager {
    private static let configuredKey = "launchAtLoginConfigured"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func registerIfNeeded() {
        guard !AppGroup.defaults.bool(forKey: configuredKey) else { return }
        AppGroup.defaults.set(true, forKey: configuredKey)
        do {
            if !isEnabled { try SMAppService.mainApp.register() }
        } catch {
            print("Failed to register as a login item: \(error)")
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        AppGroup.defaults.set(true, forKey: configuredKey)
        if enabled {
            if !isEnabled { try SMAppService.mainApp.register() }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}
