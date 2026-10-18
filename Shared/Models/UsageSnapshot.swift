import Foundation

/// How a product's usage should be rendered: as rolling rate-limit windows
/// (personal Pro/Max-style plans) or as a dollar amount spent (enterprise/team plans).
enum UsageMode: String, Codable {
    case percentLimits
    case spend
    case unavailable
}

struct RateLimitWindow: Codable, Identifiable, Hashable {
    var id: String { label }
    let label: String
    /// 0...100, percent of the window still available.
    let percentRemaining: Double
    let resetsAt: Date
}

struct SpendSummary: Codable, Hashable {
    let amountSpentUSD: Double
    let periodLabel: String
}

struct ProductUsage: Codable, Hashable {
    let productName: String
    let mode: UsageMode
    let rateLimitWindows: [RateLimitWindow]
    let spend: SpendSummary?
    let lastUpdated: Date
    let errorMessage: String?
    // Optional so caches written by older versions continue to decode.
    var reconnectRequired: Bool? = nil

    var needsReconnect: Bool {
        reconnectRequired ?? (errorMessage == "Session expired — reconnect"
            || errorMessage == "Usage access was rejected — reconnect or check the selected workspace")
    }

    var isVisibleInCompactWidget: Bool {
        mode != .unavailable || needsReconnect
    }

    static func unconfigured(_ productName: String) -> ProductUsage {
        ProductUsage(
            productName: productName,
            mode: .unavailable,
            rateLimitWindows: [],
            spend: nil,
            lastUpdated: .distantPast,
            errorMessage: "Not configured"
        )
    }
}

struct UsageSnapshot: Codable, Hashable {
    var claude: ProductUsage
    var chatgpt: ProductUsage

    static let placeholder = UsageSnapshot(
        claude: .unconfigured("Claude"),
        chatgpt: .unconfigured("ChatGPT / Codex")
    )
}
