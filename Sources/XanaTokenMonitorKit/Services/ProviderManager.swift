import Foundation
import Combine

@Observable
@MainActor
class ProviderManager {
    var providers: [any ModelProvider] = []
    var balances: [UUID: Balance] = [:]
    var errors: [UUID: Error] = [:]
    var providerNames: [UUID: String] = [:]
    var pollingInterval: TimeInterval = 300 // 5 minutes
    private var pollingTask: Task<Void, Never>?
    
    init() {
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
        saveProviders()
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
        
        for (id, result) in results {
            switch result {
            case .success(let balance):
                balances[id] = balance
                errors.removeValue(forKey: id)
            case .failure(let error):
                errors[id] = error
            }
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
