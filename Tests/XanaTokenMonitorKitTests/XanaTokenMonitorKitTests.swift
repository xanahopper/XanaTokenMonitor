import XCTest
#if os(macOS)
import ServiceManagement
#endif
@testable import XanaTokenMonitorKit

final class XanaTokenMonitorKitTests: XCTestCase {
    #if os(macOS)
    func testRecentSevenDayHistoryRangeIsRollingAndEndsAtNow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 14,
            hour: 16,
            minute: 30
        )))

        let interval = QuotaHistoryRange.recentSevenDays.interval(
            containing: now,
            calendar: calendar
        )

        XCTAssertEqual(interval.end, now)
        XCTAssertEqual(interval.start, calendar.date(byAdding: .day, value: -7, to: now))
        XCTAssertEqual(QuotaHistoryRange.recentSevenDays.title, "近 7 天")
        XCTAssertEqual(QuotaHistoryRange.recentSevenDays.trendTitle, "近 7 天趋势")
        XCTAssertEqual(QuotaHistoryRange.recentSevenDays.axisLabels(for: interval).end, "现在")
    }
    #endif

    #if os(macOS)
    @MainActor
    func testLaunchAtLoginTreatsEnabledAndPendingApprovalAsRegistered() {
        XCTAssertTrue(LaunchAtLoginSettings.isRegistered(.enabled))
        XCTAssertTrue(LaunchAtLoginSettings.isRegistered(.requiresApproval))
        XCTAssertFalse(LaunchAtLoginSettings.isRegistered(.notRegistered))
        XCTAssertFalse(LaunchAtLoginSettings.isRegistered(.notFound))
    }
    #endif

    @MainActor
    func testPanelAddProviderPresentationStateIsObservableAndDismissible() {
        let panelActions = PanelActions.shared
        panelActions.showAddProvider = false
        let stateChanged = expectation(description: "Panel presentation state changed")

        withObservationTracking {
            _ = panelActions.showAddProvider
        } onChange: {
            stateChanged.fulfill()
        }

        panelActions.showAddProvider = true
        wait(for: [stateChanged], timeout: 0.1)

        panelActions.showAddProvider = false
        XCTAssertFalse(panelActions.showAddProvider)
    }

    func testAPIKeyArchiveCombinesProvidersAndOmitsBlankValues() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "3FD8AF88-E380-40B7-A819-7743846342C1"))
        let secondID = try XCTUnwrap(UUID(uuidString: "D13032D0-917A-407D-BB8B-F0731F58B600"))
        let blankID = try XCTUnwrap(UUID(uuidString: "CAAC6702-E2B5-4179-B29E-10AFA76F5412"))

        let data = try XCTUnwrap(APIKeyStore.encode([
            firstID: "  first-key\n",
            secondID: "second-key",
            blankID: " \n\t"
        ]))
        let decoded = try APIKeyStore.decode(data)

        XCTAssertEqual(decoded, [
            firstID: "first-key",
            secondID: "second-key"
        ])
        XCTAssertNil(try APIKeyStore.encode([blankID: "  "]))
    }

    func testQuotaColorThemesKeepClassicDefaultAndProvideDistinctPalettes() {
        XCTAssertEqual(QuotaColorTheme.allCases.count, 10)
        XCTAssertEqual(
            QuotaPalette.hexString(remainingPercent: 100, theme: .classic),
            "#32D74B"
        )

        let themeColors = Set(QuotaColorTheme.allCases.map {
            QuotaPalette.hexString(remainingPercent: 60, theme: $0)
        })
        XCTAssertEqual(themeColors.count, QuotaColorTheme.allCases.count)
    }

    func testQuotaBarShapesExposeThreeAppearanceOptionsWithSquareDefault() {
        XCTAssertEqual(QuotaBarShape.allCases, [.pill, .softSquare, .square])
        XCTAssertEqual(QuotaBarShape.square.name, "直角")
        XCTAssertEqual(QuotaBarShape.square.description, "完全直角")
        XCTAssertEqual(QuotaBarShape.storageKey, "quotaBarShape")
    }

    func testQuotaPercentTextPreservesLowRemainingValues() {
        XCTAssertEqual(QuotaDisplay.percentText(0), "0%")
        XCTAssertEqual(QuotaDisplay.percentText(0.4), "<1%")
        XCTAssertEqual(QuotaDisplay.percentText(3.26), "3.3%")
        XCTAssertEqual(QuotaDisplay.percentText(10), "10%")
        XCTAssertEqual(QuotaDisplay.percentText(42.4), "42%")
    }

    func testEveryQuotaThemeHasDistinctTracksWithVisibleFillContrast() {
        let lightTracks = Set(QuotaColorTheme.allCases.map {
            QuotaPalette.trackHexString(theme: $0, darkAppearance: false)
        })
        let darkTracks = Set(QuotaColorTheme.allCases.map {
            QuotaPalette.trackHexString(theme: $0, darkAppearance: true)
        })

        XCTAssertEqual(lightTracks.count, QuotaColorTheme.allCases.count)
        XCTAssertEqual(darkTracks.count, QuotaColorTheme.allCases.count)

        for theme in QuotaColorTheme.allCases {
            for darkAppearance in [false, true] {
                let track = QuotaPalette.trackRGB(theme: theme, darkAppearance: darkAppearance)
                for remainingPercent in [10.0, 60.0, 100.0] {
                    let fill = QuotaPalette.rgb(
                        remainingPercent: remainingPercent,
                        theme: theme
                    )
                    let distance = sqrt(
                        pow(fill.r - track.r, 2)
                        + pow(fill.g - track.g, 2)
                        + pow(fill.b - track.b, 2)
                    )
                    XCTAssertGreaterThan(
                        distance,
                        40,
                        "\(theme.name) 的填充色和空槽色过于接近"
                    )
                }
            }
        }
    }

    func testQuotaHistoryMergesRapidRefreshesAndDropsExpiredSamples() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expired = try historySample(
            timestamp: now.addingTimeInterval(-QuotaHistoryStore.retentionInterval - 1),
            remainingPercent: 90
        )
        let recent = try historySample(
            timestamp: now.addingTimeInterval(-300),
            remainingPercent: 80
        )
        let rapidRefresh = try historySample(
            timestamp: now.addingTimeInterval(-270),
            remainingPercent: 75
        )

        let result = QuotaHistoryStore.appending(
            rapidRefresh,
            to: [expired, recent],
            now: now
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].quotas[0].remainingPercent, 75)
        XCTAssertEqual(result[0].timestamp, rapidRefresh.timestamp)
    }

    @MainActor
    func testRefreshReportsPartialFailureAndKeepsStaleBalance() async {
        let successfulID = UUID()
        let failedID = UUID()
        let staleBalance = Balance(
            amount: 42,
            currency: "tokens",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let refreshedBalance = Balance(
            amount: 84,
            currency: "tokens",
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let manager = ProviderManager(historyStore: temporaryHistoryStore())
        manager.providers = [
            RefreshStubProvider(id: successfulID, balance: refreshedBalance),
            RefreshStubProvider(id: failedID, shouldFail: true)
        ]
        manager.balances[failedID] = staleBalance

        await manager.fetchAllBalances()

        XCTAssertFalse(manager.isRefreshing)
        XCTAssertTrue(manager.refreshingProviderIDs.isEmpty)
        XCTAssertEqual(manager.lastRefreshResult, .partialFailure)
        XCTAssertEqual(manager.balances[successfulID]?.amount, 84)
        XCTAssertEqual(manager.balances[failedID]?.timestamp, staleBalance.timestamp)
        XCTAssertNotNil(manager.errors[failedID])
        XCTAssertNotNil(manager.lastRefreshCompletedAt)
    }

    @MainActor
    func testShouldRefreshBalancesWhenDataIsMissingOrStale() {
        let providerID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let manager = ProviderManager(historyStore: temporaryHistoryStore())
        manager.providers = [RefreshStubProvider(id: providerID)]

        XCTAssertTrue(manager.shouldRefreshBalances(maxAge: 60, now: now))

        manager.balances[providerID] = Balance(
            amount: 42,
            currency: "tokens",
            timestamp: now.addingTimeInterval(-59)
        )
        XCTAssertFalse(manager.shouldRefreshBalances(maxAge: 60, now: now))

        manager.balances[providerID] = Balance(
            amount: 42,
            currency: "tokens",
            timestamp: now.addingTimeInterval(-60)
        )
        XCTAssertTrue(manager.shouldRefreshBalances(maxAge: 60, now: now))
    }

    func testWeeklyQuotaMarkerAllocatesOneWholeShareAtEachResetBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let resetDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 9,
            hour: 10
        )))
        let quota = QuotaDisplay.QuotaInfo(
            index: 0,
            name: "周",
            remainingPercent: 50,
            resetDate: resetDate,
            durationMins: 7 * 24 * 60
        )

        let mondayEvening = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 7,
            hour: 17
        )))
        let tuesdayBeforeBoundary = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 8,
            hour: 9
        )))
        let tuesdayAfterBoundary = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 8,
            hour: 10
        )))

        XCTAssertEqual(try XCTUnwrap(QuotaDisplay.timeMarker(quota, now: mondayEvening, calendar: calendar)), 1.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(QuotaDisplay.timeMarker(quota, now: tuesdayBeforeBoundary, calendar: calendar)), 1.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(QuotaDisplay.timeMarker(quota, now: tuesdayAfterBoundary, calendar: calendar)), 0, accuracy: 0.0001)
    }

    func testWeeklyQuotaMarkerAllocatesFirstDayAtPeriodStart() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let resetDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 9,
            hour: 10
        )))
        let quota = QuotaDisplay.QuotaInfo(
            index: 0,
            name: "周",
            remainingPercent: 50,
            resetDate: resetDate,
            durationMins: 7 * 24 * 60
        )
        let beforePeriod = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 2,
            hour: 9
        )))
        let periodStart = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 2,
            hour: 10
        )))

        XCTAssertEqual(try XCTUnwrap(QuotaDisplay.timeMarker(quota, now: beforePeriod, calendar: calendar)), 1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(QuotaDisplay.timeMarker(quota, now: periodStart, calendar: calendar)), 6.0 / 7.0, accuracy: 0.0001)
    }

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

    func testUnavailableProvidersDoNotReturnPlaceholderBalances() async {
        await XCTAssertThrowsErrorAsync {
            _ = try await AnthropicProvider(id: UUID(), apiKey: "fixture-key").fetchBalance()
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await MiMoProvider(id: UUID(), apiKey: "fixture-key").fetchBalance()
        }
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
        let encodedText = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let decoded = try JSONDecoder().decode(AnyCodableProvider.self, from: encoded)
        let openAIProvider = try XCTUnwrap(decoded.provider as? OpenAIProvider)

        XCTAssertFalse(encodedText.contains("admin-key"))
        XCTAssertFalse(encodedText.contains("apiKey"))
        XCTAssertEqual(openAIProvider.id, provider.id)
        XCTAssertEqual(openAIProvider.apiKey, "")
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
        let encodedText = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let decoded = try JSONDecoder().decode(AnyCodableProvider.self, from: encoded)
        let kimiProvider = try XCTUnwrap(decoded.provider as? KimiCodingProvider)
        
        XCTAssertFalse(encodedText.contains("test-key"))
        XCTAssertFalse(encodedText.contains("apiKey"))
        XCTAssertEqual(kimiProvider.id, provider.id)
        XCTAssertEqual(kimiProvider.apiKey, "")
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

    private func historySample(
        timestamp: Date,
        remainingPercent: Int
    ) throws -> QuotaHistorySample {
        let usedPercent = 100 - remainingPercent
        return try XCTUnwrap(QuotaHistorySample(balance: Balance(
            amount: Double(usedPercent) / 100,
            currency: "used_percent",
            timestamp: timestamp,
            details: [
                "quotas_count": "1",
                "quota_0_name": "周",
                "quota_0_percentage": String(usedPercent),
                "quota_0_durationMins": "10080"
            ]
        )))
    }

    private func temporaryHistoryStore() -> QuotaHistoryStore {
        QuotaHistoryStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("xana-token-monitor-tests-\(UUID().uuidString).json")
        )
    }
}

private struct RefreshStubProvider: ModelProvider {
    let id: UUID
    var name = "Refresh Stub"
    var apiKey = ""
    var baseURL = "local"
    var balance: Balance?
    var shouldFail = false

    func fetchBalance() async throws -> Balance {
        if shouldFail {
            throw RefreshStubError.expectedFailure
        }
        return balance ?? Balance(amount: 0, currency: "tokens", timestamp: Date())
    }
}

private enum RefreshStubError: Error {
    case expectedFailure
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync(
        _ expression: @escaping () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected an error", file: file, line: line)
        } catch {
            // Expected.
        }
    }
}
