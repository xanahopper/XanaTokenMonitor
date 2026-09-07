import Foundation

protocol ModelProvider: Identifiable, Sendable {
    var id: UUID { get }
    var name: String { get }
    var apiKey: String { get set }
    var baseURL: String { get }
    func fetchBalance() async throws -> Balance
}

struct Balance: Codable, Sendable {
    let amount: Double
    let currency: String
    let timestamp: Date
    let details: [String: String]?
    
    init(amount: Double, currency: String, timestamp: Date, details: [String: String]? = nil) {
        self.amount = amount
        self.currency = currency
        self.timestamp = timestamp
        self.details = details
    }
}

struct CodexProvider: ModelProvider {
    let id: UUID
    var name: String = "OpenAI Codex"
    var apiKey: String = ""
    var baseURL: String = "Local ChatGPT auth"

    func fetchBalance() async throws -> Balance {
        #if os(macOS)
        return try await Task.detached(priority: .utility) {
            let output = try Self.runCodexAppServer()
            return try Self.parseBalance(from: output)
        }.value
        #else
        throw CodexProviderError.unsupportedPlatform
        #endif
    }

    static func parseBalance(from output: Data, timestamp: Date = Date()) throws -> Balance {
        var account: CodexAccount?
        var rateLimits: CodexRateLimitsResponse?
        var usage: CodexUsageResponse?
        var rpcErrors: [Int: String] = [:]

        for line in output.split(separator: 0x0A) {
            let data = Data(line)
            guard let envelope = try? JSONDecoder().decode(CodexRPCEnvelope.self, from: data) else {
                continue
            }
            if let error = envelope.error, let id = envelope.id {
                rpcErrors[id] = error.message
                continue
            }
            guard let id = envelope.id, let result = envelope.result else { continue }

            switch id {
            case 1:
                account = try? JSONDecoder().decode(CodexAccountResponse.self, from: result).account
            case 2:
                rateLimits = try? JSONDecoder().decode(CodexRateLimitsResponse.self, from: result)
            case 3:
                usage = try? JSONDecoder().decode(CodexUsageResponse.self, from: result)
            default:
                break
            }
        }

        if let error = rpcErrors[1] {
            throw CodexProviderError.rpcError(error)
        }
        if let error = rpcErrors[0] {
            throw CodexProviderError.rpcError(error)
        }
        guard let account else {
            throw CodexProviderError.notLoggedIn
        }
        guard account.type == "chatgpt" else {
            throw CodexProviderError.chatGPTLoginRequired
        }
        guard rateLimits != nil || usage != nil else {
            throw CodexProviderError.rpcError(rpcErrors[2] ?? rpcErrors[3] ?? "Codex returned no usage data.")
        }

        return makeBalance(account: account, rateLimits: rateLimits, usage: usage, timestamp: timestamp)
    }

    private static func makeBalance(
        account: CodexAccount,
        rateLimits: CodexRateLimitsResponse?,
        usage: CodexUsageResponse?,
        timestamp: Date
    ) -> Balance {
        var details: [String: String] = [:]
        if let planType = account.planType {
            details["plan"] = planType.capitalized
        }
        if let lifetimeTokens = usage?.summary.lifetimeTokens {
            details["lifetime_tokens"] = String(lifetimeTokens)
        }
        if let peakDailyTokens = usage?.summary.peakDailyTokens {
            details["peak_daily_tokens"] = String(peakDailyTokens)
        }
        if let currentStreakDays = usage?.summary.currentStreakDays {
            details["current_streak_days"] = String(currentStreakDays)
        }

        let windows = [rateLimits?.rateLimits.primary, rateLimits?.rateLimits.secondary].compactMap { $0 }
        details["quotas_count"] = String(windows.count)
        for (index, window) in windows.enumerated() {
            let prefix = "quota_\(index)_"
            let used = max(0, min(100, window.usedPercent))
            details[prefix + "name"] = quotaName(for: window.windowDurationMins, index: index)
            details[prefix + "percentage"] = String(used)
            details[prefix + "percentage_mode"] = "used"
            details[prefix + "usage"] = String(window.usedPercent)
            if let durationMins = window.windowDurationMins, durationMins > 0 {
                details[prefix + "durationMins"] = String(durationMins)
            }
            if let resetsAt = window.resetsAt {
                details[prefix + "nextResetTime"] = String(resetsAt * 1_000)
                if index == 0 {
                    details["primary_nextResetTime"] = String(resetsAt * 1_000)
                }
            }
        }

        if let primary = windows.first {
            let used = max(0, min(100, primary.usedPercent))
            return Balance(amount: Double(used) / 100, currency: "used_percent", timestamp: timestamp, details: details)
        }

        return Balance(
            amount: Double(usage?.summary.lifetimeTokens ?? 0),
            currency: "tokens",
            timestamp: timestamp,
            details: details
        )
    }

    private static func quotaName(for durationMinutes: Int64?, index: Int) -> String {
        guard let durationMinutes, durationMinutes > 0 else {
            return index == 0 ? "主要额度" : "额度\(index + 1)"
        }
        if durationMinutes % (24 * 60) == 0 {
            let days = durationMinutes / (24 * 60)
            // 常见的 7 天窗口按中文习惯显示为「周」
            return days == 7 ? "周" : "\(days)d"
        }
        if durationMinutes % 60 == 0 {
            return "\(durationMinutes / 60)h"
        }
        return "\(durationMinutes)m"
    }

    #if os(macOS)
    private static func runCodexAppServer() throws -> Data {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errorOutput = Pipe()
        let collector = CodexOutputCollector()

        process.executableURL = try codexExecutableURL()
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                collector.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            throw CodexProviderError.processFailed(error.localizedDescription)
        }

        let initializeRequest = #"{"id":0,"method":"initialize","params":{"clientInfo":{"name":"xana_token_monitor","title":"Xana Token Monitor","version":"1.0.0"}}}"# + "\n"
        input.fileHandleForWriting.write(Data(initializeRequest.utf8))

        guard collector.initialized.wait(timeout: .now() + 5) == .success else {
            output.fileHandleForReading.readabilityHandler = nil
            process.terminate()
            throw CodexProviderError.timedOut
        }

        let accountRequests = [
            #"{"method":"initialized"}"#,
            #"{"id":1,"method":"account/read","params":{"refreshToken":true}}"#,
            #"{"id":2,"method":"account/rateLimits/read"}"#,
            #"{"id":3,"method":"account/usage/read"}"#
        ].joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(accountRequests.utf8))

        guard collector.accountResponses.wait(timeout: .now() + 20) == .success else {
            output.fileHandleForReading.readabilityHandler = nil
            process.terminate()
            let errorData = errorOutput.fileHandleForReading.availableData
            if !errorData.isEmpty,
               let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                throw CodexProviderError.processFailed(message)
            }
            throw CodexProviderError.timedOut
        }

        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
        return collector.snapshot()
    }

    private static func codexExecutableURL() throws -> URL {
        let fixedPaths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/codex" }
        for path in fixedPaths + pathCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw CodexProviderError.codexNotFound
    }
    #endif
}

#if os(macOS)
private final class CodexOutputCollector: @unchecked Sendable {
    let initialized = DispatchSemaphore(value: 0)
    let accountResponses = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var allData = Data()
    private var pendingData = Data()
    private var responseIDs: Set<Int> = []
    private var didSignalInitialized = false
    private var didSignalAccountResponses = false

    func append(_ data: Data) {
        lock.lock()
        allData.append(data)
        pendingData.append(data)

        while let newline = pendingData.firstRange(of: Data([0x0A])) {
            let line = pendingData[..<newline.lowerBound]
            pendingData.removeSubrange(...newline.lowerBound)
            if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
               let id = object["id"] as? NSNumber {
                responseIDs.insert(id.intValue)
            }
        }

        let shouldSignalInitialized = responseIDs.contains(0) && !didSignalInitialized
        if shouldSignalInitialized {
            didSignalInitialized = true
        }
        let shouldSignalAccountResponses = [1, 2, 3].allSatisfy(responseIDs.contains) && !didSignalAccountResponses
        if shouldSignalAccountResponses {
            didSignalAccountResponses = true
        }
        lock.unlock()

        if shouldSignalInitialized {
            initialized.signal()
        }
        if shouldSignalAccountResponses {
            accountResponses.signal()
        }
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return allData
    }
}
#endif

enum CodexProviderError: LocalizedError {
    case unsupportedPlatform
    case codexNotFound
    case notLoggedIn
    case chatGPTLoginRequired
    case timedOut
    case processFailed(String)
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Local Codex authentication is only available on macOS."
        case .codexNotFound:
            return "Codex CLI was not found. Install Codex and sign in with ChatGPT first."
        case .notLoggedIn:
            return "Codex is not signed in. Run ‘codex login’ first."
        case .chatGPTLoginRequired:
            return "Codex is not using ChatGPT authentication. Sign in to Codex with ChatGPT first."
        case .timedOut:
            return "Codex usage query timed out."
        case .processFailed(let message):
            return "Could not start Codex: \(message)"
        case .rpcError(let message):
            return "Codex usage query failed: \(message)"
        }
    }
}

private struct CodexRPCEnvelope: Decodable {
    let id: Int?
    let result: Data?
    let error: CodexRPCError?

    enum CodingKeys: String, CodingKey { case id, result, error }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        error = try container.decodeIfPresent(CodexRPCError.self, forKey: .error)
        if container.contains(.result) {
            result = try JSONEncoder().encode(container.decode(JSONValue.self, forKey: .result))
        } else {
            result = nil
        }
    }
}

private struct CodexRPCError: Decodable { let message: String }

private enum JSONValue: Codable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private struct CodexAccountResponse: Decodable { let account: CodexAccount? }
private struct CodexAccount: Decodable { let type: String; let planType: String? }
private struct CodexRateLimitsResponse: Decodable { let rateLimits: CodexRateLimitSnapshot }
private struct CodexRateLimitSnapshot: Decodable {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
}
private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int64?
    let resetsAt: Int64?
}
private struct CodexUsageResponse: Decodable { let summary: CodexUsageSummary }
private struct CodexUsageSummary: Decodable {
    let currentStreakDays: Int64?
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
}

struct OpenAIProvider: ModelProvider {
    let id: UUID
    var name: String = "OpenAI"
    var apiKey: String
    var baseURL: String = "https://api.openai.com/v1"

    func fetchBalance() async throws -> Balance {
        let timestamp = Date()
        let periodStart = Self.startOfCurrentMonth(containing: timestamp)
        var summary = OpenAIUsageSummary()
        var page: String?
        var seenPages: Set<String> = []

        repeat {
            let request = try makeUsageRequest(
                startTime: periodStart,
                endTime: timestamp,
                page: page
            )
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAIProviderError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw OpenAIProviderError.httpError(
                    statusCode: httpResponse.statusCode,
                    message: Self.errorMessage(from: data)
                )
            }

            let usagePage = try Self.parseUsagePage(from: data)
            summary.add(usagePage.summary)
            if usagePage.hasMore {
                guard
                    let nextPage = usagePage.nextPage,
                    !nextPage.isEmpty,
                    seenPages.insert(nextPage).inserted
                else {
                    throw OpenAIProviderError.invalidPayload
                }
                page = nextPage
            } else {
                page = nil
            }
        } while page != nil

        return Self.makeBalance(
            summary: summary,
            timestamp: timestamp,
            periodStart: periodStart
        )
    }

    func makeUsageRequest(
        startTime: Date,
        endTime: Date,
        page: String? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(string: "\(baseURL)/organization/usage/completions") else {
            throw OpenAIProviderError.invalidURL
        }

        var queryItems = [
            URLQueryItem(name: "start_time", value: String(Int64(startTime.timeIntervalSince1970))),
            URLQueryItem(name: "end_time", value: String(Int64(endTime.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]
        if let page, !page.isEmpty {
            queryItems.append(URLQueryItem(name: "page", value: page))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw OpenAIProviderError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func parseBalance(
        from data: Data,
        timestamp: Date = Date(),
        periodStart: Date? = nil
    ) throws -> Balance {
        let page = try parseUsagePage(from: data)
        return makeBalance(
            summary: page.summary,
            timestamp: timestamp,
            periodStart: periodStart ?? startOfCurrentMonth(containing: timestamp)
        )
    }

    private static func parseUsagePage(from data: Data) throws -> OpenAIUsagePage {
        do {
            let response = try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)
            var summary = OpenAIUsageSummary()
            for bucket in response.data {
                for result in bucket.results {
                    summary.inputTokens += result.inputTokens ?? 0
                    summary.outputTokens += result.outputTokens ?? 0
                    summary.cachedInputTokens += result.inputCachedTokens ?? 0
                    summary.inputAudioTokens += result.inputAudioTokens ?? 0
                    summary.outputAudioTokens += result.outputAudioTokens ?? 0
                    summary.requests += result.numModelRequests ?? 0
                }
            }
            return OpenAIUsagePage(
                summary: summary,
                hasMore: response.hasMore,
                nextPage: response.nextPage
            )
        } catch {
            throw OpenAIProviderError.invalidPayload
        }
    }

    private static func makeBalance(
        summary: OpenAIUsageSummary,
        timestamp: Date,
        periodStart: Date
    ) -> Balance {
        let totalTokens = summary.inputTokens + summary.outputTokens
        let details = [
            "period": "本月",
            "period_start": String(Int64(periodStart.timeIntervalSince1970 * 1_000)),
            "input_tokens": formattedNumber(summary.inputTokens),
            "output_tokens": formattedNumber(summary.outputTokens),
            "cached_input_tokens": formattedNumber(summary.cachedInputTokens),
            "input_audio_tokens": formattedNumber(summary.inputAudioTokens),
            "output_audio_tokens": formattedNumber(summary.outputAudioTokens),
            "requests": formattedNumber(summary.requests)
        ]
        return Balance(
            amount: totalTokens,
            currency: "tokens",
            timestamp: timestamp,
            details: details
        )
    }

    private static func startOfCurrentMonth(containing date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private static func errorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return nil
        }
        return message
    }

    private static func formattedNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int64(value))
        }
        return String(value)
    }
}

enum OpenAIProviderError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidPayload
    case httpError(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid OpenAI usage URL."
        case .invalidResponse:
            return "OpenAI returned an invalid response."
        case .invalidPayload:
            return "OpenAI returned an unsupported usage response."
        case .httpError(let statusCode, let message):
            if let message, !message.isEmpty {
                return "OpenAI API error \(statusCode): \(message)"
            }
            return "OpenAI API error \(statusCode)."
        }
    }
}

enum ProviderIntegrationError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let provider):
            return provider + " quota monitoring is not available in this release."
        }
    }
}

private struct OpenAIUsageResponse: Decodable {
    let data: [OpenAIUsageBucket]
    let hasMore: Bool
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

private struct OpenAIUsageBucket: Decodable {
    let results: [OpenAIUsageResult]
}

private struct OpenAIUsageResult: Decodable {
    let inputTokens: Double?
    let outputTokens: Double?
    let inputCachedTokens: Double?
    let inputAudioTokens: Double?
    let outputAudioTokens: Double?
    let numModelRequests: Double?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case inputCachedTokens = "input_cached_tokens"
        case inputAudioTokens = "input_audio_tokens"
        case outputAudioTokens = "output_audio_tokens"
        case numModelRequests = "num_model_requests"
    }
}

private struct OpenAIUsageSummary {
    var inputTokens: Double = 0
    var outputTokens: Double = 0
    var cachedInputTokens: Double = 0
    var inputAudioTokens: Double = 0
    var outputAudioTokens: Double = 0
    var requests: Double = 0

    mutating func add(_ other: OpenAIUsageSummary) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cachedInputTokens += other.cachedInputTokens
        inputAudioTokens += other.inputAudioTokens
        outputAudioTokens += other.outputAudioTokens
        requests += other.requests
    }
}

private struct OpenAIUsagePage {
    let summary: OpenAIUsageSummary
    let hasMore: Bool
    let nextPage: String?
}

struct AnthropicProvider: ModelProvider {
    let id: UUID
    var name: String = "Anthropic"
    var apiKey: String
    var baseURL: String = "https://api.anthropic.com"
    
    func fetchBalance() async throws -> Balance {
        throw ProviderIntegrationError.unavailable(name)
    }
}

struct KimiCodingProvider: ModelProvider {
    let id: UUID
    var name: String = "Kimi for Coding"
    var apiKey: String
    var baseURL: String = "https://api.kimi.com/coding/v1"
    
    func fetchBalance() async throws -> Balance {
        let (data, response) = try await URLSession.shared.data(for: makeUsageRequest())
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return try Self.parseBalance(from: data)
    }
    
    func makeUsageRequest() -> URLRequest {
        let url = URL(string: "\(baseURL)/usages")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    
    static func parseBalance(from data: Data, timestamp: Date = Date()) throws -> Balance {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        
        var quotas: [KimiCodingQuota] = []
        if let limits = payload["limits"] as? [Any] {
            for (index, value) in limits.enumerated() {
                guard let item = value as? [String: Any] else { continue }
                let detail = item["detail"] as? [String: Any] ?? item
                let window = item["window"] as? [String: Any] ?? [:]
                let name = limitName(item: item, detail: detail, window: window, index: index)
                if let quota = quota(from: detail, fallback: item, window: window, defaultName: name, timestamp: timestamp) {
                    quotas.append(quota)
                }
            }
        }

        if let usage = payload["usage"] as? [String: Any],
           let quota = quota(from: usage, defaultName: "周", timestamp: timestamp) {
            quotas.append(quota)
        }
        
        guard let primaryQuota = quotas.first else {
            throw URLError(.cannotParseResponse)
        }
        
        var details: [String: String] = ["quotas_count": String(quotas.count)]
        for (index, quota) in quotas.enumerated() {
            let prefix = "quota_\(index)_"
            details[prefix + "name"] = quota.name
            if let limit = quota.limit {
                details[prefix + "limit"] = formattedNumber(limit)
            }
            if let used = quota.used {
                details[prefix + "usage"] = formattedNumber(used)
            }
            if let remaining = quota.remaining {
                details[prefix + "remaining"] = formattedNumber(remaining)
            }
            if let percentage = quota.usedPercentage {
                details[prefix + "percentage"] = String(Int(percentage.rounded()))
                details[prefix + "percentage_mode"] = "used"
            }
            if let resetTimestamp = quota.resetTimestampMillis {
                details[prefix + "nextResetTime"] = String(resetTimestamp)
            }
            let durationMins = quota.durationMins
                ?? QuotaDisplay.fallbackDurationMins(fromName: quota.name)
            if let durationMins {
                details[prefix + "durationMins"] = String(Int(durationMins))
            }
        }
        
        if let resetTimestamp = primaryQuota.resetTimestampMillis {
            details["primary_nextResetTime"] = String(resetTimestamp)
        }
        
        if let percentage = primaryQuota.usedPercentage {
            return Balance(
                amount: percentage / 100,
                currency: "used_percent",
                timestamp: timestamp,
                details: details
            )
        }
        
        return Balance(
            amount: primaryQuota.remaining ?? 0,
            currency: "quota",
            timestamp: timestamp,
            details: details
        )
    }
    
    private static func quota(
        from data: [String: Any],
        fallback: [String: Any]? = nil,
        window: [String: Any] = [:],
        defaultName: String,
        timestamp: Date
    ) -> KimiCodingQuota? {
        let limit = numberValue(data["limit"])
        var used = numberValue(data["used"])
        var remaining = numberValue(data["remaining"])
        
        if used == nil, let limit, let remaining {
            used = limit - remaining
        }
        if remaining == nil, let limit, let used {
            remaining = limit - used
        }
        guard limit != nil || used != nil || remaining != nil else {
            return nil
        }
        
        let usedPercentage: Double?
        if let limit, limit > 0 {
            if let used {
                usedPercentage = min(100, max(0, used / limit * 100))
            } else if let remaining {
                usedPercentage = min(100, max(0, (limit - remaining) / limit * 100))
            } else {
                usedPercentage = nil
            }
        } else {
            usedPercentage = nil
        }
        
        return KimiCodingQuota(
            name: stringValue(data["name"]) ?? stringValue(data["title"]) ?? defaultName,
            limit: limit,
            used: used,
            remaining: remaining,
            usedPercentage: usedPercentage,
            resetTimestampMillis: resetTimestamp(in: data, relativeTo: timestamp)
                ?? fallback.flatMap { resetTimestamp(in: $0, relativeTo: timestamp) },
            durationMins: windowDurationMins(data: data, fallback: fallback)
                ?? windowDurationMins(data: window, fallback: nil)
        )
    }
    
    /// 窗口时长(分钟),按 timeUnit 换算
    private static func windowDurationMins(data: [String: Any], fallback: [String: Any]?) -> Double? {
        for source in [data, fallback ?? [:]] {
            let duration = numberValue(source["duration"])
            let timeUnit = (stringValue(source["timeUnit"]) ?? "").uppercased()
            guard let duration, duration > 0 else { continue }
            if timeUnit.contains("MINUTE") { return duration }
            if timeUnit.contains("HOUR") { return duration * 60 }
            if timeUnit.contains("DAY") { return duration * 1440 }
            if timeUnit.contains("WEEK") { return duration * 10080 }
        }
        return nil
    }

    private static func limitName(
        item: [String: Any],
        detail: [String: Any],
        window: [String: Any],
        index: Int
    ) -> String {
        for value in [item["name"], detail["name"], item["title"], detail["title"], item["scope"], detail["scope"]] {
            if let name = stringValue(value) {
                return name
            }
        }
        
        let duration = numberValue(window["duration"])
            ?? numberValue(item["duration"])
            ?? numberValue(detail["duration"])
        let timeUnit = (
            stringValue(window["timeUnit"])
                ?? stringValue(item["timeUnit"])
                ?? stringValue(detail["timeUnit"])
                ?? ""
        ).uppercased()
        
        guard let duration, duration > 0 else {
            return "配额\(index + 1)"
        }
        if timeUnit.contains("MINUTE") {
            if duration >= 60, duration.truncatingRemainder(dividingBy: 60) == 0 {
                return "\(formattedNumber(duration / 60))h"
            }
            return "\(formattedNumber(duration))m"
        }
        if timeUnit.contains("HOUR") {
            return "\(formattedNumber(duration))h"
        }
        if timeUnit.contains("DAY") {
            return "\(formattedNumber(duration))d"
        }
        return "\(formattedNumber(duration))s"
    }
    
    private static func resetTimestamp(in data: [String: Any], relativeTo timestamp: Date) -> Int64? {
        for key in ["reset_at", "resetAt", "reset_time", "resetTime"] {
            guard let value = data[key] else { continue }
            if let rawTimestamp = numberValue(value), rawTimestamp.isFinite {
                let milliseconds = rawTimestamp < 1_000_000_000_000 ? rawTimestamp * 1_000 : rawTimestamp
                return Int64(milliseconds)
            }
            if let dateString = stringValue(value), let date = iso8601Date(from: dateString) {
                return Int64(date.timeIntervalSince1970 * 1_000)
            }
        }
        
        for key in ["reset_in", "resetIn", "ttl", "window"] {
            if let seconds = numberValue(data[key]), seconds > 0 {
                return Int64(timestamp.addingTimeInterval(seconds).timeIntervalSince1970 * 1_000)
            }
        }
        return nil
    }
    
    private static func iso8601Date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    
    private static func numberValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
    
    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private static func formattedNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int64(value))
        }
        return String(value)
    }
}

private struct KimiCodingQuota {
    let name: String
    let limit: Double?
    let used: Double?
    let remaining: Double?
    let usedPercentage: Double?
    let resetTimestampMillis: Int64?
    let durationMins: Double?
}

struct ZhipuAIProvider: ModelProvider {
    let id: UUID
    var name: String = "ZhipuAI"
    var apiKey: String
    var baseURL: String = "https://open.bigmodel.cn"
    
    func fetchBalance() async throws -> Balance {
        let (data, response) = try await URLSession.shared.data(for: makeUsageRequest())

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try Self.parseBalance(from: data)
    }

    func makeUsageRequest() -> URLRequest {
        // Older saved providers used bigmodel.cn. Query the documented platform
        // host directly so the request does not depend on a redirect.
        let requestBaseURL = baseURL == "https://bigmodel.cn"
            ? "https://open.bigmodel.cn"
            : baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(requestBaseURL)/api/monitor/usage/quota/limit")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("zh-CN,zh", forHTTPHeaderField: "Accept-Language")
        return request
    }

    static func parseBalance(from data: Data, timestamp: Date = Date()) throws -> Balance {
        let quotaResponse = try JSONDecoder().decode(ZhipuAIQuotaResponse.self, from: data)
        
        guard quotaResponse.code == 200, quotaResponse.success else {
            throw URLError(.cannotParseResponse)
        }
        
        // 安全解包 data
        guard let data = quotaResponse.data else {
            return Balance(amount: 0, currency: "used_percent", timestamp: timestamp)
        }
        
        // 收集所有配额信息
        var details: [String: String] = [:]
        var primaryUsedPercentage: Int?
        var primaryResetTime: Int64?

        if let level = data.level, !level.isEmpty {
            details["plan"] = level.uppercased()
        }
        
        let tokensLimits = data.limits.filter { $0.type == "TOKENS_LIMIT" }
        
        // 收集每个配额的信息
        for (index, limit) in tokensLimits.enumerated() {
            let prefix = "quota_\(index)_"
            details[prefix + "name"] = quotaName(unit: limit.unit, number: limit.number, index: index)

            if let unit = limit.unit {
                details[prefix + "unit"] = String(unit)
                // 实测:unit 3 = 小时窗口(number 为小时数),unit 6 = 周窗口
                switch unit {
                case 3: details[prefix + "durationMins"] = String((limit.number ?? 0) * 60)
                case 6: details[prefix + "durationMins"] = String(7 * 24 * 60)
                default: break
                }
            }
            if let number = limit.number {
                details[prefix + "number"] = String(number)
            }
            if let percentage = limit.percentage {
                // The quota endpoint and the official usage plugin expose this
                // value as consumed usage, matching the control panel.
                details[prefix + "percentage"] = String(percentage)
                details[prefix + "percentage_mode"] = "used"
                // 选择第一个有百分比的配额作为主要显示
                if primaryUsedPercentage == nil {
                    primaryUsedPercentage = percentage
                }
            }
            if let nextResetTime = limit.nextResetTime {
                details[prefix + "nextResetTime"] = String(nextResetTime)
                // 选择第一个有重置时间的配额作为主要显示
                if primaryResetTime == nil {
                    primaryResetTime = nextResetTime
                }
            }
            if let usage = limit.usage {
                details[prefix + "usage"] = String(usage)
            }
            if let currentValue = limit.currentValue {
                details[prefix + "currentValue"] = String(currentValue)
            }
            if let remaining = limit.remaining {
                details[prefix + "remaining"] = String(remaining)
            }
        }
        
        // 添加配额数量信息
        details["quotas_count"] = String(tokensLimits.count)
        
        // 添加主要配额的重置时间
        if let resetTime = primaryResetTime {
            details["primary_nextResetTime"] = String(resetTime)
        }
        
        // 优先选择有 remaining 字段的条目作为主要显示
        if let limitWithRemaining = tokensLimits.first(where: { $0.remaining != nil }),
           let remaining = limitWithRemaining.remaining {
            return Balance(amount: Double(remaining), currency: "tokens", timestamp: timestamp, details: details)
        }
        
        // 如果没有 remaining，选择有 percentage 字段的条目作为主要显示
        if let percentage = primaryUsedPercentage {
            return Balance(
                amount: Double(percentage) / 100.0,
                currency: "used_percent",
                timestamp: timestamp,
                details: details
            )
        }
        
        // 如果都没有，返回 0
        return Balance(amount: 0, currency: "used_percent", timestamp: timestamp, details: details)
    }

    /// 实测配额接口:unit 3 = 小时窗口(number 为小时数),unit 6 = 周窗口。
    private static func quotaName(unit: Int?, number: Int?, index: Int) -> String {
        switch unit {
        case 3: return "\(number ?? 0)h"
        case 6: return "周"
        default: return "配额\(index + 1)"
        }
    }
}
struct MiMoProvider: ModelProvider {
    let id: UUID
    var name: String = "Xiaomi MiMo"
    var apiKey: String
    var baseURL: String = "https://api.xiaomimimo.com/v1"
    
    func fetchBalance() async throws -> Balance {
        throw ProviderIntegrationError.unavailable(name)
    }
}

// 智谱AI配额查询响应模型
struct ZhipuAIQuotaResponse: Codable {
    let code: Int
    let msg: String
    let data: ZhipuAIQuotaData?
    let success: Bool
}

struct ZhipuAIQuotaData: Codable {
    let limits: [ZhipuAIQuotaLimit]
    let level: String?
}

struct ZhipuAIQuotaLimit: Codable {
    let type: String
    let unit: Int?
    let number: Int?
    let usage: Int?
    let currentValue: Int?
    let remaining: Int?
    let percentage: Int?
    let nextResetTime: Int64?
    let usageDetails: [ZhipuAIUsageDetail]?
}

struct ZhipuAIUsageDetail: Codable {
    let modelCode: String
    let usage: Int
}
