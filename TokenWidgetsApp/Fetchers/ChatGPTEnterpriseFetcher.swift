import Foundation

/// Reads month-to-date org spend via OpenAI's documented Costs API
/// (GET https://api.openai.com/v1/organization/costs), using an Admin API key.
struct ChatGPTEnterpriseFetcher: ProductUsageFetcher {
    func fetch() async throws -> ProductUsage {
        guard let apiKey = CredentialStore.get(.openaiAdminApiKey), !apiKey.isEmpty else {
            throw FetcherError.notConfigured
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        var components = URLComponents(string: "https://api.openai.com/v1/organization/costs")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(Int(startOfMonth.timeIntervalSince1970))),
            URLQueryItem(name: "end_time", value: String(Int(now.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await NetworkRequest.data(for: request)
        try HTTPStatus.check(response)

        let total = try Self.parseAmountUSD(data)

        return ProductUsage(
            productName: "ChatGPT / Codex",
            mode: .spend,
            rateLimitWindows: [],
            spend: SpendSummary(amountSpentUSD: total, periodLabel: "This month"),
            lastUpdated: Date(),
            errorMessage: nil
        )
    }

    static func parseAmountUSD(_ data: Data) throws -> Double {
        let decoded = try JSONDecoder().decodeDetailed(CostsResponse.self, from: data)
        return decoded.data
            .flatMap(\.results)
            .compactMap(\.amount)
            .filter { $0.currency.caseInsensitiveCompare("usd") == .orderedSame }
            .compactMap(\.value)
            .reduce(0, +)
    }
}

private struct CostsResponse: Decodable {
    let data: [Bucket]

    struct Bucket: Decodable {
        let results: [Result]
    }

    struct Result: Decodable {
        let amount: Amount?
    }

    struct Amount: Decodable {
        let value: Double?
        let currency: String
    }
}
