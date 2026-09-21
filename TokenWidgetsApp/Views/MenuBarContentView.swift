import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @EnvironmentObject private var scheduler: RefreshScheduler
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Token Widgets")
                .font(.headline)

            usageRow(scheduler.snapshot.claude)
            usageRow(scheduler.snapshot.chatgpt)

            Divider()

            Button {
                Task { await scheduler.refresh() }
            } label: {
                HStack {
                    Text("Refresh Now")
                    if scheduler.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(scheduler.isRefreshing)

            Button("Settings…") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Quit Token Widgets") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    @ViewBuilder
    private func usageRow(_ usage: ProductUsage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(usage.productName)
                .font(.subheadline).bold()

            switch usage.mode {
            case .unavailable:
                Text(usage.errorMessage ?? "Not configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .spend:
                if let spend = usage.spend {
                    Text("$\(spend.amountSpentUSD, specifier: "%.2f") \(spend.periodLabel)")
                        .font(.caption)
                }
            case .percentLimits:
                ForEach(usage.rateLimitWindows) { window in
                    Text("\(window.label): \(Int(window.percentRemaining))% left")
                        .font(.caption)
                }
            }

            if usage.mode != .unavailable, usage.lastUpdated != .distantPast {
                Text("Updated \(usage.lastUpdated, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(AppSettings.isStale(usage) ? .orange : .secondary)
            }

            if let error = usage.errorMessage, usage.mode != .unavailable {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }
}
