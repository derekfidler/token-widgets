import Foundation

/// Reads month-to-date spend for a Claude Enterprise organization via Anthropic's
/// documented Analytics API (https://platform.claude.com/docs/en/api/admin/analytics),
/// using an Analytics API key (not an Admin API key — those are for Claude Console/Platform
/// orgs, which use a different endpoint family under /v1/organizations/cost_report).
struct ClaudeEnterpriseFetcher: ProductUsageFetcher {
    func fetch() async throws -> ProductUsage {
        guard let apiKey = CredentialStore.get(.claudeAnalyticsApiKey), !apiKey.isEmpty else {
            throw FetcherError.notConfigured
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/analytics/cost_report")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: Self.iso8601.string(from: startOfMonth)),
            URLQueryItem(name: "ending_at", value: Self.iso8601.string(from: now)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")

        let (data, response) = try await NetworkRequest.data(for: request)
        try HTTPStatus.check(response)

        let amount = try Self.parseAmountUSD(data)

        return ProductUsage(
            productName: "Claude",
            mode: .spend,
            rateLimitWindows: [],
            spend: SpendSummary(amountSpentUSD: amount, periodLabel: "This month"),
            lastUpdated: Date(),
            errorMessage: nil
        )
    }

    static func parseAmountUSD(_ data: Data) throws -> Double {
        let decoded = try JSONDecoder().decodeDetailed(CostReportResponse.self, from: data)
        // Analytics API amounts are decimal strings in the smallest currency unit (cents).
        let totalCents = decoded.data
            .flatMap(\.results)
            .compactMap { Decimal(string: $0.amount, locale: Locale(identifier: "en_US_POSIX")) }
            .reduce(Decimal.zero, +)
        return NSDecimalNumber(decimal: totalCents / 100).doubleValue
    }

    private static var iso8601: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }
}

private struct CostReportResponse: Decodable {
    let data: [Bucket]

    struct Bucket: Decodable {
        let results: [Result]
    }

    struct Result: Decodable {
        let amount: String
    }
}
