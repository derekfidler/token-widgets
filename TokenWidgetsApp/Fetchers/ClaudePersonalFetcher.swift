import Foundation

/// Reads usage from claude.ai's internal per-org usage endpoint, authenticated with your
/// browser session cookie. There is no public API for this.
///
/// The same endpoint returns two different shapes depending on account type: personal
/// Pro/Max accounts get `five_hour`/`seven_day` rate-limit windows; org/Enterprise-style
/// accounts (confirmed via a real captured response) instead get a `spend` object with a
/// dollar amount used/limit. This fetcher auto-detects which shape it got, so no separate
/// Analytics API key is needed for the dollar-spend case.
struct ClaudePersonalFetcher: ProductUsageFetcher {
    func fetch() async throws -> ProductUsage {
        guard let cookie = CredentialStore.get(.claudeSessionCookie), !cookie.isEmpty else {
            throw FetcherError.notConfigured
        }

        let orgId = try await resolveOrgId(cookie: cookie)
        let data = try await fetchUsage(orgId: orgId, cookie: cookie)
        return try Self.parseUsage(data)
    }

    static func parseUsage(_ data: Data, now: Date = Date()) throws -> ProductUsage {
        let usage = try DateDecoding.iso8601WithFractionalSeconds.decodeDetailed(UsageResponse.self, from: data)

        var windows: [RateLimitWindow] = []
        if let fiveHour = usage.five_hour {
            windows.append(fiveHour.asWindow(label: "5-hour limit"))
        }
        if let sevenDay = usage.seven_day {
            windows.append(sevenDay.asWindow(label: "Weekly limit"))
        }
        if !windows.isEmpty {
            return ProductUsage(
                productName: "Claude",
                mode: .percentLimits,
                rateLimitWindows: windows,
                spend: nil,
                lastUpdated: now,
                errorMessage: nil
            )
        }

        if let spend = usage.spend {
            return ProductUsage(
                productName: "Claude",
                mode: .spend,
                rateLimitWindows: [],
                spend: SpendSummary(amountSpentUSD: spend.used.value, periodLabel: "This month"),
                lastUpdated: now,
                errorMessage: nil
            )
        }

        throw FetcherError.unexpectedResponse("Usage endpoint returned neither rate-limit windows nor a spend summary")
    }

    private func resolveOrgId(cookie: String) async throws -> String {
        if let override = CredentialStore.get(.claudeOrgId), !override.isEmpty {
            return override
        }
        var request = URLRequest(url: URL(string: "https://claude.ai/api/organizations")!)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        let (data, response) = try await NetworkRequest.data(for: request)
        try HTTPStatus.check(response)

        struct Org: Decodable { let uuid: String }
        let orgs = try JSONDecoder().decodeDetailed([Org].self, from: data)
        guard let first = orgs.first else {
            throw FetcherError.unexpectedResponse("No organizations returned for this account")
        }
        return first.uuid
    }

    private func fetchUsage(orgId: String, cookie: String) async throws -> Data {
        let path = CredentialStore.get(.claudeUsageEndpointOverride).flatMap { $0.isEmpty ? nil : $0 }
            ?? "/api/organizations/\(orgId)/usage"
        guard let url = URL(string: "https://claude.ai\(path)") else {
            throw FetcherError.unexpectedResponse("Invalid usage endpoint override")
        }
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        let (data, response) = try await NetworkRequest.data(for: request)
        try HTTPStatus.check(response)
        return data
    }
}

/// Fields are at the top level (no "raw_limits" wrapper, despite public reports suggesting one).
private struct UsageResponse: Decodable {
    let five_hour: RateLimitWindowRaw?
    let seven_day: RateLimitWindowRaw?
    let spend: SpendInfo?
}

private struct RateLimitWindowRaw: Decodable {
    let remaining_tokens: Double
    let total_tokens: Double
    let reset_at: Date

    func asWindow(label: String) -> RateLimitWindow {
        let percent = total_tokens > 0
            ? min(100, max(0, (remaining_tokens / total_tokens) * 100))
            : 0
        return RateLimitWindow(label: label, percentRemaining: percent, resetsAt: reset_at)
    }
}

private struct SpendInfo: Decodable {
    let used: MoneyAmount
}

private struct MoneyAmount: Decodable {
    let amount_minor: Int
    let exponent: Int

    var value: Double {
        Double(amount_minor) / pow(10, Double(exponent))
    }
}
