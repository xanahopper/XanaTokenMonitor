import Foundation
import Combine
import Security

enum APIKeyStore {
    private static let service = "com.xana.XanaTokenMonitor.api-keys"

    enum StoreError: LocalizedError {
        case keychain(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                return "Keychain operation failed (status \(status))."
            case .invalidData:
                return "The stored API key could not be decoded."
            }
        }
    }

    static func save(_ apiKey: String, for providerID: UUID) throws {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedKey.isEmpty {
            try delete(for: providerID)
            return
        }

        let query = query(for: providerID)
        let data = Data(normalizedKey.utf8)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw StoreError.keychain(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw StoreError.keychain(updateStatus)
        }
    }

    static func load(for providerID: UUID) throws -> String? {
        var result: CFTypeRef?
        var lookup = query(for: providerID)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw StoreError.keychain(status)
        }
        guard let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            throw StoreError.invalidData
        }
        return apiKey
    }

    static func delete(for providerID: UUID) throws {
        let status = SecItemDelete(query(for: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }

    private static func query(for providerID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID.uuidString
        ]
    }
}

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
        do {
            try APIKeyStore.delete(for: id)
        } catch {
            NSLog("ProviderManager: failed to delete API key from Keychain: %@", error.localizedDescription)
        }
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
        for provider in providers {
            do {
                try APIKeyStore.save(provider.apiKey, for: provider.id)
            } catch {
                // Never fall back to persisting the key in UserDefaults.
                NSLog("ProviderManager: failed to save API key to Keychain: %@", error.localizedDescription)
            }
        }

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

        var needsRewrite = false
        providers = decoded.map { storedProvider in
            var provider = storedProvider.provider
            let legacyKey = provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                if let keychainKey = try APIKeyStore.load(for: provider.id) {
                    provider.apiKey = keychainKey
                    needsRewrite = needsRewrite || !legacyKey.isEmpty
                } else if !legacyKey.isEmpty {
                    // Migrate credentials written by versions that used UserDefaults.
                    try APIKeyStore.save(legacyKey, for: provider.id)
                    provider.apiKey = legacyKey
                    needsRewrite = true
                } else {
                    provider.apiKey = ""
                }
            } catch {
                // Keep the legacy value in memory for this session, but do not rewrite
                // the preferences until the credential can be stored securely.
                NSLog("ProviderManager: failed to migrate API key to Keychain: %@", error.localizedDescription)
            }

            return provider
        }

        if let storedNames = UserDefaults.standard.dictionary(forKey: "providerNames") as? [String: String] {
            var names: [UUID: String] = [:]
            for (key, value) in storedNames {
                if let id = UUID(uuidString: key) {
                    names[id] = value
                }
            }
            providerNames = names
        }

        if needsRewrite {
            saveProviders()
        }
    }
}

private struct StoredProviderConfiguration: Codable {
    let id: UUID
    let name: String
    let baseURL: String
    let legacyAPIKey: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKey
    }

    init(id: UUID, name: String, baseURL: String, legacyAPIKey: String? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.legacyAPIKey = legacyAPIKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        // Read this only to migrate configurations created before Keychain storage.
        legacyAPIKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
        // Deliberately omit apiKey. Credentials belong in Keychain only.
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
        let type: String
        if provider is CodexProvider {
            type = "codex"
        } else if provider is OpenAIProvider {
            type = "openai"
        } else if provider is AnthropicProvider {
            type = "anthropic"
        } else if provider is KimiCodingProvider {
            type = "kimi-coding"
        } else if provider is ZhipuAIProvider {
            type = "zhipuai"
        } else if provider is MiMoProvider {
            type = "mimo"
        } else {
            throw EncodingError.invalidValue(
                provider,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unknown provider type")
            )
        }

        try container.encode(type, forKey: .type)
        let configuration = StoredProviderConfiguration(
            id: provider.id,
            name: provider.name,
            baseURL: provider.baseURL
        )
        let data = try JSONEncoder().encode(configuration)
        try container.encode(data, forKey: .data)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let data = try container.decode(Data.self, forKey: .data)
        let configuration = try JSONDecoder().decode(StoredProviderConfiguration.self, from: data)
        let apiKey = configuration.legacyAPIKey ?? ""
        
        switch type {
        case "codex":
            provider = CodexProvider(id: configuration.id, name: configuration.name, apiKey: apiKey, baseURL: configuration.baseURL)
        case "openai":
            provider = OpenAIProvider(id: configuration.id, name: configuration.name, apiKey: apiKey, baseURL: configuration.baseURL)
        case "anthropic":
            provider = AnthropicProvider(id: configuration.id, name: configuration.name, apiKey: apiKey, baseURL: configuration.baseURL)
        case "kimi-coding":
            provider = KimiCodingProvider(id: configuration.id, name: configuration.name, apiKey: apiKey, baseURL: configuration.baseURL)
        case "zhipuai":
            provider = ZhipuAIProvider(id: configuration.id, name: configuration.name, apiKey: apiKey, baseURL: configuration.baseURL)
        case "mimo":
            provider = MiMoProvider(id: configuration.id, name: configuration.name, apiKey: apiKey, baseURL: configuration.baseURL)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown provider type")
        }
    }
}
