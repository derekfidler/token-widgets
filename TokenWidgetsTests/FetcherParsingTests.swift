import XCTest
@testable import TokenWidgets

final class FetcherParsingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testClaudePersonalRateLimitsAreParsedAndClamped() throws {
        let data = Data(#"""
        {
          "five_hour": {"remaining_tokens": 120, "total_tokens": 100, "reset_at": "2027-01-15T12:00:00.000Z"},
          "seven_day": {"remaining_tokens": -5, "total_tokens": 100, "reset_at": "2027-01-20T12:00:00Z"}
        }
        """#.utf8)

        let usage = try ClaudePersonalFetcher.parseUsage(data, now: now)

        XCTAssertEqual(usage.mode, .percentLimits)
        XCTAssertEqual(usage.rateLimitWindows.map(\.percentRemaining), [100, 0])
        XCTAssertEqual(usage.lastUpdated, now)
    }

    func testClaudePersonalSpendIsConvertedFromMinorUnits() throws {
        let data = Data(#"{"spend":{"used":{"amount_minor":12345,"exponent":2}}}"#.utf8)

        let usage = try ClaudePersonalFetcher.parseUsage(data, now: now)

        XCTAssertEqual(usage.mode, .spend)
        XCTAssertEqual(usage.spend!.amountSpentUSD, 123.45, accuracy: 0.0001)
    }

    func testChatGPTPersonalWindowsAreParsedAndClamped() throws {
        let data = Data(#"""
        {
          "rate_limit": {
            "primary_window": {"used_percent": 40, "limit_window_seconds": 18000, "reset_at": 1800001000},
            "secondary_window": {"used_percent": 140, "limit_window_seconds": 604800, "reset_at": 1800002000}
          }
        }
        """#.utf8)

        let usage = try ChatGPTPersonalFetcher.parseUsage(data, now: now)

        XCTAssertEqual(usage.rateLimitWindows.map(\.label), ["5-hour limit", "Weekly limit"])
        XCTAssertEqual(usage.rateLimitWindows.map(\.percentRemaining), [60, 0])
    }

    func testClaudeEnterpriseCostUsesDecimalCents() throws {
        let data = Data(#"""
        {
          "data": [{"results": [{"amount": "123.78912"}, {"amount": "76.21088"}]}],
          "has_more": false,
          "next_page": null
        }
        """#.utf8)

        XCTAssertEqual(try ClaudeEnterpriseFetcher.parseAmountUSD(data), 2.0, accuracy: 0.000_001)
    }

    func testOpenAICostIgnoresNullAndNonUSDAmounts() throws {
        let data = Data(#"""
        {
          "data": [{"results": [
            {"amount": {"value": 1.25, "currency": "usd"}},
            {"amount": null},
            {"amount": {"value": 3.0, "currency": "eur"}}
          ]}],
          "has_more": false,
          "next_page": null
        }
        """#.utf8)

        XCTAssertEqual(try ChatGPTEnterpriseFetcher.parseAmountUSD(data), 1.25, accuracy: 0.000_001)
    }

    func testChatGPTAccountIDIsReadFromNamespacedJWTClaim() throws {
        let payload = Data(#"{"exp":1900000000,"https://api.openai.com/auth":{"chatgpt_account_id":"account-123"}}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(payload).signature"

        XCTAssertEqual(ChatGPTPersonalFetcher.accountID(fromJWT: token), "account-123")
        XCTAssertEqual(
            ChatGPTPersonalFetcher.expiration(fromJWT: token),
            Date(timeIntervalSince1970: 1_900_000_000)
        )
        XCTAssertNil(ChatGPTPersonalFetcher.accountID(fromJWT: "not-a-jwt"))
        XCTAssertNil(ChatGPTPersonalFetcher.expiration(fromJWT: "not-a-jwt"))
    }

    func testHTTPStatusMapsAuthenticationAndRateLimitErrors() throws {
        let url = URL(string: "https://example.com")!
        let unauthorized = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try HTTPStatus.check(unauthorized)) { error in
            guard case FetcherError.unauthorized = error else {
                return XCTFail("Expected unauthorized, got \(error)")
            }
        }

        let rateLimited = HTTPURLResponse(
            url: url,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "60"]
        )!
        XCTAssertThrowsError(try HTTPStatus.check(rateLimited)) { error in
            guard case FetcherError.rateLimited(let retryAfter) = error else {
                return XCTFail("Expected rateLimited, got \(error)")
            }
            XCTAssertEqual(retryAfter, "60")
        }
    }

    func testDetailedDecodeNeverLeaksResponseContents() {
        struct Expected: Decodable { let required: String }
        let secret = "secret-access-token-value"
        let data = Data("{\"accessToken\":\"\(secret)\"}".utf8)

        XCTAssertThrowsError(try JSONDecoder().decodeDetailed(Expected.self, from: data)) { error in
            XCTAssertFalse(error.localizedDescription.contains(secret))
            XCTAssertTrue(error.localizedDescription.contains("Missing field"))
        }
    }

    func testStalenessUsesRefreshIntervalWithThirtyMinuteFloor() {
        let previousInterval = AppSettings.refreshIntervalMinutes
        defer { AppSettings.refreshIntervalMinutes = previousInterval }
        let usage = ProductUsage(
            productName: "Claude",
            mode: .spend,
            rateLimitWindows: [],
            spend: SpendSummary(amountSpentUSD: 1, periodLabel: "This month"),
            lastUpdated: now.addingTimeInterval(-31 * 60),
            errorMessage: nil
        )

        AppSettings.refreshIntervalMinutes = 15
        XCTAssertTrue(AppSettings.isStale(usage, now: now))
        AppSettings.refreshIntervalMinutes = 60
        XCTAssertFalse(AppSettings.isStale(usage, now: now))
    }
}
