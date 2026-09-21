import SwiftUI

@main
struct TokenWidgetsApp: App {
    @StateObject private var scheduler = RefreshScheduler.shared

    init() {
        LoginItemManager.registerIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra("Token Widgets", systemImage: "gauge.with.dots.needle.50percent") {
            MenuBarContentView()
                .environmentObject(scheduler)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(scheduler)
        }
    }
}
