import SwiftUI
import WidgetKit

struct TokenWidgetsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: UsageSnapshot

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        default:
            VStack(alignment: .leading, spacing: 10) {
                ProductCard(usage: snapshot.claude, maxWindows: 2)
                Divider()
                ProductCard(usage: snapshot.chatgpt, maxWindows: 2)
            }
        }
    }

    /// Both products side-by-side (compact) when both are connected; otherwise show
    /// whichever one is configured with full detail instead of wasting half the space.
    @ViewBuilder
    private var smallView: some View {
        let claudeActive = snapshot.claude.mode != .unavailable
        let chatgptActive = snapshot.chatgpt.mode != .unavailable

        if claudeActive && chatgptActive {
            VStack(alignment: .leading, spacing: 10) {
                CompactRow(usage: snapshot.claude)
                Divider()
                CompactRow(usage: snapshot.chatgpt)
            }
        } else if claudeActive {
            ProductCard(usage: snapshot.claude, maxWindows: 2)
        } else if chatgptActive {
            ProductCard(usage: snapshot.chatgpt, maxWindows: 2)
        } else {
            ProductCard(usage: snapshot.claude, maxWindows: 1)
        }
    }
}

private struct CompactRow: View {
    let usage: ProductUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(shortName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            switch usage.mode {
            case .unavailable:
                Text("—")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

            case .spend:
                if let spend = usage.spend {
                    Text(spend.amountSpentUSD, format: .currency(code: "USD"))
                        .font(.system(size: 16, weight: .bold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }

            case .percentLimits:
                if let window = preferredWindow {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(window.label)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text("\(Int(window.percentRemaining))% left")
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    LimitProgressBar(percentRemaining: window.percentRemaining)
                    Text("Resets \(window.resetsAt, style: .relative)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shortName: String {
        usage.productName == "ChatGPT / Codex" ? "ChatGPT" : usage.productName
    }

    /// Weekly limits are the most useful long-horizon signal in the compact widget.
    /// Fall back to the final available window when a provider uses different labels.
    private var preferredWindow: RateLimitWindow? {
        usage.rateLimitWindows.first {
            $0.label.localizedCaseInsensitiveContains("weekly")
        } ?? usage.rateLimitWindows.last
    }
}

private struct ProductCard: View {
    let usage: ProductUsage
    let maxWindows: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(usage.productName)
                .font(.system(size: 13, weight: .semibold))

            switch usage.mode {
            case .unavailable:
                Text(usage.errorMessage ?? "Not configured")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

            case .spend:
                if let spend = usage.spend {
                    Text(spend.amountSpentUSD, format: .currency(code: "USD"))
                        .font(.system(size: 22, weight: .bold))
                    Text(spend.periodLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

            case .percentLimits:
                ForEach(usage.rateLimitWindows.prefix(maxWindows)) { window in
                    RateLimitRow(window: window)
                }
            }

            if usage.mode != .unavailable, usage.lastUpdated != .distantPast {
                Text("Updated \(usage.lastUpdated, style: .relative)")
                    .font(.system(size: 9))
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var statusColor: Color {
        usage.errorMessage != nil || AppSettings.isStale(usage) ? .orange : .secondary
    }
}

private struct RateLimitRow: View {
    let window: RateLimitWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.percentRemaining))% left")
                    .font(.system(size: 11, weight: .medium))
            }
            LimitProgressBar(percentRemaining: window.percentRemaining)
            Text("Resets \(window.resetsAt, style: .relative)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct LimitProgressBar: View {
    let percentRemaining: Double

    private var fraction: Double {
        min(1, max(0, percentRemaining / 100))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.22))
                Capsule()
                    .fill(percentRemaining < 15 ? Color.red : Color.primary)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage remaining")
        .accessibilityValue("\(Int(percentRemaining)) percent")
    }
}
