import Foundation
import Combine

struct QuotaHistoryValue: Codable, Sendable, Equatable, Identifiable {
    let index: Int
    let name: String
    let remainingPercent: Double
    let resetDate: Date?

    var id: Int { index }
}

struct QuotaHistorySample: Codable, Sendable, Equatable, Identifiable {
    let timestamp: Date
    let quotas: [QuotaHistoryValue]

    var id: Date { timestamp }

    init?(balance: Balance) {
        let values = QuotaDisplay.quotas(for: balance).compactMap { quota -> QuotaHistoryValue? in
            guard let remainingPercent = quota.remainingPercent else { return nil }
            return QuotaHistoryValue(
                index: quota.index,
                name: quota.name,
                remainingPercent: remainingPercent,
                resetDate: quota.resetDate
            )
        }
        guard !values.isEmpty else { return nil }
        timestamp = balance.timestamp
        quotas = values
    }
}

struct QuotaHistoryStore {
    static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60
    static let mergeInterval: TimeInterval = 60

    let fileURL: URL

    static var appDefault: QuotaHistoryStore {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return QuotaHistoryStore(
            fileURL: baseURL
                .appendingPathComponent("XanaTokenMonitor", isDirectory: true)
                .appendingPathComponent("quota-history.json")
        )
    }

    func load() -> [UUID: [QuotaHistorySample]] {
        guard let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode([String: [QuotaHistorySample]].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: archive.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value.sorted { $0.timestamp < $1.timestamp }) }
        })
    }

    func save(_ history: [UUID: [QuotaHistorySample]]) {
        let archive = Dictionary(uniqueKeysWithValues: history.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(archive) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 历史记录是辅助信息，写盘失败不影响实时额度刷新。
        }
    }

    static func appending(
        _ sample: QuotaHistorySample,
        to samples: [QuotaHistorySample],
        now: Date
    ) -> [QuotaHistorySample] {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        var retained = samples.filter { $0.timestamp >= cutoff }

        if let last = retained.last,
           abs(sample.timestamp.timeIntervalSince(last.timestamp)) < mergeInterval {
            retained[retained.count - 1] = sample
        } else {
            retained.append(sample)
        }
        retained.sort { $0.timestamp < $1.timestamp }
        return retained
    }
}

@Observable
@MainActor
class ProviderManager {
    var providers: [any ModelProvider] = []
    var balances: [UUID: Balance] = [:]
    var errors: [UUID: Error] = [:]
    var providerNames: [UUID: String] = [:]
    private(set) var quotaHistory: [UUID: [QuotaHistorySample]]
    var pollingInterval: TimeInterval = 300 // 5 minutes
    private var pollingTask: Task<Void, Never>?
    private let historyStore: QuotaHistoryStore
    
    init(historyStore: QuotaHistoryStore = .appDefault) {
        self.historyStore = historyStore
        quotaHistory = historyStore.load()
        loadProviders()
    }
    
    func addProvider(_ provider: any ModelProvider, name: String? = nil) {
        providers.append(provider)
        providerNames[provider.id] = name ?? provider.name
        saveProviders()
        WidgetSnapshot.push(providers: providers, balances: balances, displayNames: providerNames)
    }

    func renameProvider(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            providerNames.removeValue(forKey: id)
        } else {
            providerNames[id] = trimmed
        }
        saveProviders()
        WidgetSnapshot.push(providers: providers, balances: balances, displayNames: providerNames)
    }

    func removeProvider(id: UUID) {
        providers.removeAll { $0.id == id }
        balances.removeValue(forKey: id)
        errors.removeValue(forKey: id)
        providerNames.removeValue(forKey: id)
        quotaHistory.removeValue(forKey: id)
        saveProviders()
        historyStore.save(quotaHistory)
        WidgetSnapshot.push(providers: providers, balances: balances, displayNames: providerNames)
    }
    
    func fetchAllBalances() async {
        let providersCopy = providers
        var results: [(UUID, Result<Balance, Error>)] = []
        
        await withTaskGroup(of: (UUID, Result<Balance, Error>).self) { group in
            for provider in providersCopy {
                group.addTask {
                    do {
                        let balance = try await provider.fetchBalance()
                        return (provider.id, .success(balance))
                    } catch {
                        return (provider.id, .failure(error))
                    }
                }
            }
            
            for await result in group {
                results.append(result)
            }
        }
        
        let historyNow = Date()
        var didChangeHistory = false
        for (id, result) in results {
            switch result {
            case .success(let balance):
                balances[id] = balance
                errors.removeValue(forKey: id)
                if let sample = QuotaHistorySample(balance: balance) {
                    quotaHistory[id] = QuotaHistoryStore.appending(
                        sample,
                        to: quotaHistory[id] ?? [],
                        now: historyNow
                    )
                    didChangeHistory = true
                }
            case .failure(let error):
                errors[id] = error
            }
        }

        if didChangeHistory {
            historyStore.save(quotaHistory)
        }

        WidgetSnapshot.push(providers: providers, balances: balances, displayNames: providerNames)
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchAllBalances()
                let interval = self?.pollingInterval ?? 300
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }
    
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
    
    private func saveProviders() {
        if let encoded = try? JSONEncoder().encode(providers.map { AnyCodableProvider($0) }) {
            UserDefaults.standard.set(encoded, forKey: "savedProviders")
        }
        let names = Dictionary(uniqueKeysWithValues: providerNames.map { ($0.key.uuidString, $0.value) })
        UserDefaults.standard.set(names, forKey: "providerNames")
    }

    private func loadProviders() {
        guard let data = UserDefaults.standard.data(forKey: "savedProviders"),
              let decoded = try? JSONDecoder().decode([AnyCodableProvider].self, from: data) else {
            return
        }
        providers = decoded.map { $0.provider }

        if let storedNames = UserDefaults.standard.dictionary(forKey: "providerNames") as? [String: String] {
            var names: [UUID: String] = [:]
            for (key, value) in storedNames {
                if let id = UUID(uuidString: key) {
                    names[id] = value
                }
            }
            providerNames = names
        }
    }
}

struct AnyCodableProvider: Codable {
    let provider: any ModelProvider
    
    init(_ provider: any ModelProvider) {
        self.provider = provider
    }
    
    enum CodingKeys: String, CodingKey {
        case type, data
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if provider is CodexProvider {
            try container.encode("codex", forKey: .type)
        } else if provider is OpenAIProvider {
            try container.encode("openai", forKey: .type)
        } else if provider is AnthropicProvider {
            try container.encode("anthropic", forKey: .type)
        } else if provider is KimiCodingProvider {
            try container.encode("kimi-coding", forKey: .type)
        } else if provider is ZhipuAIProvider {
            try container.encode("zhipuai", forKey: .type)
        } else if provider is MiMoProvider {
            try container.encode("mimo", forKey: .type)
        }
        let data = try JSONEncoder().encode(provider)
        try container.encode(data, forKey: .data)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let data = try container.decode(Data.self, forKey: .data)
        
        switch type {
        case "codex":
            provider = try JSONDecoder().decode(CodexProvider.self, from: data)
        case "openai":
            provider = try JSONDecoder().decode(OpenAIProvider.self, from: data)
        case "anthropic":
            provider = try JSONDecoder().decode(AnthropicProvider.self, from: data)
        case "kimi-coding":
            provider = try JSONDecoder().decode(KimiCodingProvider.self, from: data)
        case "zhipuai":
            provider = try JSONDecoder().decode(ZhipuAIProvider.self, from: data)
        case "mimo":
            provider = try JSONDecoder().decode(MiMoProvider.self, from: data)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown provider type")
        }
    }
}
