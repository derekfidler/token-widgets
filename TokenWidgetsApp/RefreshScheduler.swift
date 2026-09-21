import Foundation
import WidgetKit

@MainActor
final class RefreshScheduler: ObservableObject {
    static let shared = RefreshScheduler()

    @Published private(set) var snapshot: UsageSnapshot = UsageCache.load()
    @Published private(set) var isRefreshing = false

    private var timer: Timer?
    var intervalMinutes: Double {
        get { AppSettings.refreshIntervalMinutes }
        set {
            AppSettings.refreshIntervalMinutes = newValue
            scheduleTimer()
        }
    }

    private init() {
        scheduleTimer()
        Task { await refresh() }
    }

    func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: intervalMinutes * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        // A timer tick can race a user-initiated refresh. Avoid duplicate requests and
        // out-of-order snapshots when the first refresh takes longer than expected.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let updated = await UsageRefreshCoordinator.fetchSnapshot(previous: snapshot)
        snapshot = updated
        UsageCache.save(updated)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
