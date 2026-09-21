import Foundation

/// Reads personal-plan rate limits (the same ones Codex CLI reads) via chatgpt.com's
/// internal `wham/usage` endpoint. Unofficial, but its request/response shape is
/// well-documented by Codex CLI's own source, unlike the Claude equivalent.
///
/// Flow: exchange the NextAuth session cookie for a short-lived bearer access token via
/// `/api/auth/session`, then call `backend-api/wham/usage` with that token.
struct ChatGPTPersonalFetcher: ProductUsageFetcher {
    func fetch() async throws -> ProductUsage {
        guard let cookie = CredentialStore.get(.chatgptSessionCookie), !cookie.isEmpty else {
            throw FetcherError.notConfigured
        }

        let credentials = try await resolveCredentials(cookie: cookie)
        let data = try await fetchUsage(credentials: credentials)
        return try Self.parseUsage(data)
    }

    static func parseUsage(_ data: Data, now: Date = Date()) throws -> ProductUsage {
        let usage = try JSONDecoder().decodeDetailed(WhamUsageResponse.self, from: data)

        var windows: [RateLimitWindow] = []
        if let primary = usage.rate_limit?.primary_window {
            windows.append(primary.asWindow())
        }
        if let secondary = usage.rate_limit?.secondary_window {
            windows.append(secondary.asWindow())
        }
        guard !windows.isEmpty else {
            throw FetcherError.unexpectedResponse("Usage endpoint returned no rate-limit windows")
        }

        return ProductUsage(
            productName: "ChatGPT / Codex",
            mode: .percentLimits,
            rateLimitWindows: windows,
            spend: nil,
            lastUpdated: now,
            errorMessage: nil
        )
    }

    private func resolveCredentials(cookie: String) async throws -> SessionCredentials {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/api/auth/session")!)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        let (data, response) = try await NetworkRequest.data(for: request)
        try HTTPStatus.check(response)

        struct Session: Decodable {
            struct Account: Decodable { let id: String? }
            let accessToken: String?
            let account: Account?
        }
        let session = try JSONDecoder().decodeDetailed(Session.self, from: data)
        guard let token = session.accessToken, !token.isEmpty else {
            throw FetcherError.unauthorized
        }
        if let expiration = Self.expiration(fromJWT: token), expiration <= Date() {
            throw FetcherError.unauthorized
        }
        // Codex routes requests with the namespaced JWT workspace claim. The session
        // object's account field is undocumented and may identify something else.
        let accountID = Self.accountID(fromJWT: token) ?? session.account?.id
        return SessionCredentials(accessToken: token, accountID: accountID)
    }

    private func fetchUsage(credentials: SessionCredentials) async throws -> Data {
        do {
            return try await performUsageRequest(credentials: credentials, includeAccountID: true)
        } catch FetcherError.unauthorized where credentials.accountID != nil {
            // Some personal accounts reject an explicit workspace route even though the
            // same bearer token succeeds against its default route. Workspace accounts,
            // meanwhile, require the header. Try each legitimate route exactly once.
            do {
                return try await performUsageRequest(credentials: credentials, includeAccountID: false)
            } catch FetcherError.unauthorized {
                throw FetcherError.usageUnauthorized
            }
        } catch FetcherError.unauthorized {
            throw FetcherError.usageUnauthorized
        }
    }

    private func performUsageRequest(
        credentials: SessionCredentials,
        includeAccountID: Bool
    ) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("TokenWidgets/1.0", forHTTPHeaderField: "User-Agent")
        if includeAccountID, let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (data, response) = try await NetworkRequest.data(for: request)
        try HTTPStatus.check(response)
        return data
    }

    static func accountID(fromJWT token: String) -> String? {
        guard let data = jwtPayload(token) else { return nil }

        struct Claims: Decodable {
            struct Auth: Decodable { let chatgpt_account_id: String? }
            let auth: Auth?

            enum CodingKeys: String, CodingKey {
                case auth = "https://api.openai.com/auth"
            }
        }

        guard let accountID = (try? JSONDecoder().decode(Claims.self, from: data))?.auth?.chatgpt_account_id,
              !accountID.isEmpty,
              accountID.trimmingCharacters(in: .whitespacesAndNewlines) == accountID else { return nil }
        return accountID
    }

    static func expiration(fromJWT token: String) -> Date? {
        guard let data = jwtPayload(token) else { return nil }
        struct Claims: Decodable { let exp: TimeInterval? }
        guard let seconds = (try? JSONDecoder().decode(Claims.self, from: data))?.exp else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func jwtPayload(_ token: String) -> Data? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload.append(String(repeating: "=", count: (4 - payload.count % 4) % 4))
        return Data(base64Encoded: payload)
    }
}

private struct SessionCredentials {
    let accessToken: String
    let accountID: String?
}

private struct WhamUsageResponse: Decodable {
    let rate_limit: RateLimit?

    struct RateLimit: Decodable {
        let primary_window: Window?
        let secondary_window: Window?
    }

    struct Window: Decodable {
        let used_percent: Double
        let limit_window_seconds: Double
        let reset_at: Double // epoch seconds

        func asWindow() -> RateLimitWindow {
            RateLimitWindow(
                label: Self.label(forSeconds: limit_window_seconds),
                percentRemaining: min(100, max(0, 100 - used_percent)),
                resetsAt: Date(timeIntervalSince1970: reset_at)
            )
        }

        static func label(forSeconds seconds: Double) -> String {
            switch seconds {
            case ..<(6 * 3600): return "5-hour limit"
            case ..<(2 * 24 * 3600): return "Daily limit"
            case ..<(9 * 24 * 3600): return "Weekly limit"
            default: return "Limit"
            }
        }
    }
}
