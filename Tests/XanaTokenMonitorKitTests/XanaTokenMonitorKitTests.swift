import XCTest
@testable import XanaTokenMonitorKit

final class XanaTokenMonitorKitTests: XCTestCase {
    func testCodexUsageParsing() throws {
        let response = """
        {"id":0,"result":{"userAgent":"test"}}
        {"id":1,"result":{"account":{"type":"chatgpt","email":"test@example.com","planType":"pro"},"requiresOpenaiAuth":true}}
        {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":60,"windowDurationMins":10080,"resetsAt":1800604800},"planType":"pro"},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}}
        {"id":3,"result":{"summary":{"currentStreakDays":4,"lifetimeTokens":1234567,"longestRunningTurnSec":900,"longestStreakDays":8,"peakDailyTokens":250000},"dailyUsageBuckets":[{"startDate":"2026-08-11","tokens":10000}]}}
        """
        let timestamp = Date(timeIntervalSince1970: 1_799_000_000)
        let balance = try CodexProvider.parseBalance(from: Data(response.utf8), timestamp: timestamp)

        XCTAssertEqual(balance.amount, 0.25, accuracy: 0.0001)
        XCTAssertEqual(balance.currency, "used_percent")
        XCTAssertEqual(balance.timestamp, timestamp)
        XCTAssertEqual(balance.details?["plan"], "Pro")
        XCTAssertEqual(balance.details?["lifetime_tokens"], "1234567")
        XCTAssertEqual(balance.details?["peak_daily_tokens"], "250000")
        XCTAssertEqual(balance.details?["current_streak_days"], "4")
        XCTAssertEqual(balance.details?["quotas_count"], "2")
        XCTAssertEqual(balance.details?["quota_0_name"], "5h")
        XCTAssertEqual(balance.details?["quota_0_durationMins"], "300")
        XCTAssertEqual(balance.details?["quota_0_percentage"], "25")
        XCTAssertEqual(balance.details?["quota_0_percentage_mode"], "used")
        XCTAssertEqual(balance.details?["quota_0_nextResetTime"], "1800000000000")
        XCTAssertEqual(balance.details?["quota_1_name"], "周")
        XCTAssertEqual(balance.details?["quota_1_durationMins"], "10080")
        XCTAssertEqual(balance.details?["quota_1_percentage"], "60")
        XCTAssertEqual(balance.details?["quota_1_percentage_mode"], "used")
        XCTAssertEqual(balance.details?["quota_1_nextResetTime"], "1800604800000")
    }

    func testCodexProviderCodableRoundTrip() throws {
        let provider = CodexProvider(id: UUID())
        let encoded = try JSONEncoder().encode(AnyCodableProvider(provider))
        let decoded = try JSONDecoder().decode(AnyCodableProvider.self, from: encoded)
        let codexProvider = try XCTUnwrap(decoded.provider as? CodexProvider)

        XCTAssertEqual(codexProvider.id, provider.id)
        XCTAssertEqual(codexProvider.name, "OpenAI Codex")
        XCTAssertEqual(codexProvider.apiKey, "")
    }

    #if os(macOS)
    func testCodexProviderFetchesLocalUsage() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CODEX_INTEGRATION_TEST"] == "1")
        let balance = try await CodexProvider(id: UUID()).fetchBalance()

        XCTAssertFalse(balance.currency.isEmpty)
        XCTAssertGreaterThanOrEqual(balance.amount, 0)
    }
    #endif

    func testOpenAIUsageRequest() throws {
        let provider = OpenAIProvider(id: UUID(), apiKey: "  admin-key\n")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = Date(timeIntervalSince1970: 1_800_003_600)
        let request = try provider.makeUsageRequest(startTime: start, endTime: end, page: "next page")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "api.openai.com")
        XCTAssertEqual(components.path, "/v1/organization/usage/completions")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-key")
        XCTAssertEqual(query["start_time"]!, "1800000000")
        XCTAssertEqual(query["end_time"]!, "1800003600")
        XCTAssertEqual(query["bucket_width"]!, "1d")
        XCTAssertEqual(query["limit"]!, "31")
        XCTAssertEqual(query["page"]!, "next page")
    }

    func testOpenAIUsageParsing() throws {
        let response = """
        {
          "object": "page",
          "data": [
            {
              "object": "bucket",
              "start_time": 1800000000,
              "end_time": 1800086400,
              "results": [
                {
                  "object": "organization.usage.completions.result",
                  "input_tokens": 1200,
                  "output_tokens": 300,
                  "input_cached_tokens": 400,
                  "input_audio_tokens": 20,
                  "output_audio_tokens": 10,
                  "num_model_requests": 5
                },
                {
                  "object": "organization.usage.completions.result",
                  "input_tokens": 800,
                  "output_tokens": 200,
                  "num_model_requests": 3
                }
              ]
            }
          ],
          "has_more": false,
          "next_page": null
        }
        """
        let timestamp = Date(timeIntervalSince1970: 1_800_086_400)
        let periodStart = Date(timeIntervalSince1970: 1_800_000_000)
        let balance = try OpenAIProvider.parseBalance(
            from: Data(response.utf8),
            timestamp: timestamp,
            periodStart: periodStart
        )

        XCTAssertEqual(balance.amount, 2500)
        XCTAssertEqual(balance.currency, "tokens")
        XCTAssertEqual(balance.timestamp, timestamp)
        XCTAssertEqual(balance.details?["period"], "本月")
        XCTAssertEqual(balance.details?["period_start"], "1800000000000")
        XCTAssertEqual(balance.details?["input_tokens"], "2000")
        XCTAssertEqual(balance.details?["output_tokens"], "500")
        XCTAssertEqual(balance.details?["cached_input_tokens"], "400")
        XCTAssertEqual(balance.details?["input_audio_tokens"], "20")
        XCTAssertEqual(balance.details?["output_audio_tokens"], "10")
        XCTAssertEqual(balance.details?["requests"], "8")
    }

    func testOpenAIProviderCodableRoundTrip() throws {
        let provider = OpenAIProvider(id: UUID(), apiKey: "admin-key")
        let encoded = try JSONEncoder().encode(AnyCodableProvider(provider))
        let decoded = try JSONDecoder().decode(AnyCodableProvider.self, from: encoded)
        let openAIProvider = try XCTUnwrap(decoded.provider as? OpenAIProvider)

        XCTAssertEqual(openAIProvider.id, provider.id)
        XCTAssertEqual(openAIProvider.apiKey, provider.apiKey)
        XCTAssertEqual(openAIProvider.baseURL, provider.baseURL)
    }

    func testKimiCodingUsageRequest() throws {
        let provider = KimiCodingProvider(id: UUID(), apiKey: "  test-key\n")
        let request = provider.makeUsageRequest()
        
        XCTAssertEqual(request.url?.absoluteString, "https://api.kimi.com/coding/v1/usages")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }
    
    func testKimiCodingUsageParsing() throws {
        let response = """
        {
          "usage": {
            "limit": 1000,
            "used": 250,
            "remaining": 750,
            "reset_at": 1800000000
          },
          "limits": [
            {
              "detail": {
                "limit": "100",
                "used": 40,
                "remaining": "60"
              },
              "window": {
                "duration": 300,
                "timeUnit": "MINUTE"
              },
              "resetTime": 1800003600000
            }
          ]
        }
        """
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let balance = try KimiCodingProvider.parseBalance(from: Data(response.utf8), timestamp: timestamp)
        
        XCTAssertEqual(balance.amount, 0.4, accuracy: 0.0001)
        XCTAssertEqual(balance.currency, "used_percent")
        XCTAssertEqual(balance.timestamp, timestamp)
        XCTAssertEqual(balance.details?["quotas_count"], "2")
        XCTAssertEqual(balance.details?["quota_0_name"], "5h")
        XCTAssertEqual(balance.details?["quota_0_durationMins"], "300")
        XCTAssertEqual(balance.details?["quota_0_percentage"], "40")
        XCTAssertEqual(balance.details?["quota_0_percentage_mode"], "used")
        XCTAssertEqual(balance.details?["quota_0_nextResetTime"], "1800003600000")
        XCTAssertEqual(balance.details?["quota_1_name"], "周")
        XCTAssertEqual(balance.details?["quota_1_durationMins"], "10080")
        XCTAssertEqual(balance.details?["quota_1_percentage"], "25")
        XCTAssertEqual(balance.details?["quota_1_percentage_mode"], "used")
        XCTAssertEqual(balance.details?["quota_1_nextResetTime"], "1800000000000")
    }
    
    func testKimiCodingUsageInfersRemainingAndParsesISOReset() throws {
        let response = """
        {
          "usage": {
            "limit": 200,
            "used": 50,
            "resetAt": "2027-01-15T10:30:00Z"
          },
          "limits": []
        }
        """
        let balance = try KimiCodingProvider.parseBalance(from: Data(response.utf8))
        
        XCTAssertEqual(balance.amount, 0.25, accuracy: 0.0001)
        XCTAssertEqual(balance.currency, "used_percent")
        XCTAssertEqual(balance.details?["quota_0_percentage"], "25")
        XCTAssertEqual(balance.details?["quota_0_percentage_mode"], "used")
        XCTAssertEqual(balance.details?["quota_0_remaining"], "150")
        XCTAssertEqual(balance.details?["quota_0_nextResetTime"], "1800009000000")
    }
    
    func testKimiCodingProviderCodableRoundTrip() throws {
        let provider = KimiCodingProvider(id: UUID(), apiKey: "test-key")
        let encoded = try JSONEncoder().encode(AnyCodableProvider(provider))
        let decoded = try JSONDecoder().decode(AnyCodableProvider.self, from: encoded)
        let kimiProvider = try XCTUnwrap(decoded.provider as? KimiCodingProvider)
        
        XCTAssertEqual(kimiProvider.id, provider.id)
        XCTAssertEqual(kimiProvider.apiKey, provider.apiKey)
        XCTAssertEqual(kimiProvider.baseURL, provider.baseURL)
    }

    func testZhipuUsageRequestUsesOfficialHostAndTrimmedAuthorization() throws {
        let provider = ZhipuAIProvider(
            id: UUID(),
            apiKey: "  test-key\n",
            baseURL: "https://bigmodel.cn"
        )
        let request = provider.makeUsageRequest()

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://open.bigmodel.cn/api/monitor/usage/quota/limit"
        )
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-key")
    }

    func testZhipuUsagePercentageMatchesConsumedPercentage() throws {
        let response = """
        {
          "code": 200,
          "msg": "操作成功",
          "success": true,
          "data": {
            "level": "max",
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "percentage": 64,
                "nextResetTime": 1800000000000
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 6,
                "number": 1,
                "percentage": 25,
                "nextResetTime": 1800604800000
              }
            ]
          }
        }
        """
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let balance = try ZhipuAIProvider.parseBalance(
            from: Data(response.utf8),
            timestamp: timestamp
        )

        XCTAssertEqual(balance.amount, 0.64, accuracy: 0.0001)
        XCTAssertEqual(balance.currency, "used_percent")
        XCTAssertEqual(balance.timestamp, timestamp)
        XCTAssertEqual(balance.details?["plan"], "MAX")
        XCTAssertEqual(balance.details?["quotas_count"], "2")
        XCTAssertEqual(balance.details?["quota_0_percentage"], "64")
        XCTAssertEqual(balance.details?["quota_0_percentage_mode"], "used")
        XCTAssertEqual(balance.details?["quota_1_percentage"], "25")
        XCTAssertEqual(balance.details?["quota_1_percentage_mode"], "used")
    }
}
