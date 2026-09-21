import Foundation

protocol ProductUsageFetcher {
    func fetch() async throws -> ProductUsage
}

enum FetcherError: LocalizedError {
    case notConfigured
    case unauthorized
    case usageUnauthorized
    case rateLimited(String?)
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Not configured"
        case .unauthorized: return "Session expired — reconnect"
        case .usageUnauthorized: return "Usage access was rejected — reconnect or check the selected workspace"
        case .rateLimited(let retryAfter):
            if let retryAfter { return "Rate limited — retry after \(retryAfter)" }
            return "Rate limited — try again later"
        case .unexpectedResponse(let detail): return detail
        }
    }
}

enum NetworkRequest {
    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await URLSession.shared.data(for: request)
    }
}

extension JSONDecoder {
    /// Like `decode`, but reports the precise schema mismatch. Never include raw response
    /// bodies here: the session endpoint contains short-lived bearer credentials, and these
    /// errors are persisted to the shared diagnostic log and usage cache.
    func decodeDetailed<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decode(type, from: data)
        } catch let error as DecodingError {
            throw FetcherError.unexpectedResponse("\(error.shortDescription) (\(data.count)-byte response)")
        }
    }
}

private extension DecodingError {
    var shortDescription: String {
        switch self {
        case .keyNotFound(let key, let context):
            return "Missing field \"\(key.stringValue)\" at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let context):
            return "Wrong type for \(context.codingPath.map(\.stringValue).joined(separator: ".")): expected \(type)"
        case .valueNotFound(let type, let context):
            return "Null value for \(context.codingPath.map(\.stringValue).joined(separator: ".")): expected \(type)"
        case .dataCorrupted(let context):
            return "Response wasn't valid JSON: \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error"
        }
    }
}

enum HTTPStatus {
    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw FetcherError.unauthorized
        }
        if http.statusCode == 429 {
            throw FetcherError.rateLimited(http.value(forHTTPHeaderField: "Retry-After"))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FetcherError.unexpectedResponse("HTTP \(http.statusCode)")
        }
    }
}

enum DateDecoding {
    /// claude.ai's internal API returns timestamps like "2026-07-15T14:14:00.000Z".
    static var iso8601WithFractionalSeconds: JSONDecoder {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = withFraction.date(from: value) ?? withoutFraction.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
        }
        return decoder
    }
}

/// Decides, per product, which fetcher applies based on which credentials are present.
/// Enterprise (API-key) credentials take priority if both are somehow configured.
enum UsageRefreshCoordinator {
    /// On a failed fetch, falls back to `previous`'s values (with the error attached)
    /// so the widget keeps showing last-known-good data instead of going blank.
    static func fetchSnapshot(previous: UsageSnapshot) async -> UsageSnapshot {
        async let claude = fetchClaude(previous: previous.claude)
        async let chatgpt = fetchChatGPT(previous: previous.chatgpt)
        return await UsageSnapshot(claude: claude, chatgpt: chatgpt)
    }

    private static func fetchClaude(previous: ProductUsage) async -> ProductUsage {
        let mode = AppSettings.claudeAccountMode
            ?? (CredentialStore.has(.claudeAnalyticsApiKey) ? .enterprise : .personal)
        if mode == .enterprise, CredentialStore.has(.claudeAnalyticsApiKey) {
            return await run(ClaudeEnterpriseFetcher(), previous: previous)
        }
        if mode == .personal, CredentialStore.has(.claudeSessionCookie) {
            return await run(ClaudePersonalFetcher(), previous: previous)
        }
        return .unconfigured("Claude")
    }

    private static func fetchChatGPT(previous: ProductUsage) async -> ProductUsage {
        let mode = AppSettings.chatgptAccountMode
            ?? (CredentialStore.has(.openaiAdminApiKey) ? .enterprise : .personal)
        if mode == .enterprise, CredentialStore.has(.openaiAdminApiKey) {
            return await run(ChatGPTEnterpriseFetcher(), previous: previous)
        }
        if mode == .personal, CredentialStore.has(.chatgptSessionCookie) {
            return await run(ChatGPTPersonalFetcher(), previous: previous)
        }
        return .unconfigured("ChatGPT / Codex")
    }

    private static func run(_ fetcher: ProductUsageFetcher, previous: ProductUsage) async -> ProductUsage {
        do {
            let result = try await fetcher.fetch()
            await DebugLog.shared.append("[\(previous.productName)] OK: \(result.mode) \(result.rateLimitWindows.count) windows")
            return result
        } catch {
            await DebugLog.shared.append("[\(previous.productName)] ERROR: \(error.localizedDescription)")
            guard previous.mode != .unavailable else {
                return ProductUsage(
                    productName: previous.productName,
                    mode: .unavailable,
                    rateLimitWindows: [],
                    spend: nil,
                    lastUpdated: Date(),
                    errorMessage: error.localizedDescription
                )
            }
            // Keep the last-good values on screen; just surface the error and leave lastUpdated as-is
            // so the widget can indicate the data is stale.
            return ProductUsage(
                productName: previous.productName,
                mode: previous.mode,
                rateLimitWindows: previous.rateLimitWindows,
                spend: previous.spend,
                lastUpdated: previous.lastUpdated,
                errorMessage: error.localizedDescription
            )
        }
    }
}
