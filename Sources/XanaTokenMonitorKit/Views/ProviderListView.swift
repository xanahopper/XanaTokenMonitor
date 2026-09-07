import SwiftUI

struct ProviderListView: View {
    private let providerManager: ProviderManager
    @State private var showingAddProvider = false

    @MainActor
    init(providerManager: ProviderManager) {
        self.providerManager = providerManager
    }

    var body: some View {
        // 面板「添加提供方」按钮的请求(读取以建立观察,变更会触发刷新)
        let wantsAddFromPanel = PanelActions.showAddProvider

        NavigationStack {
            #if os(macOS)
            VStack(spacing: 0) {
                header
                Divider()
                mainContent
            }
            #else
            mainContent
                .navigationTitle("Token Monitor")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showingAddProvider = true }) {
                            Label("Add Provider", systemImage: "plus")
                        }
                    }

                    #if os(iOS)
                    if !providerManager.providers.isEmpty {
                        ToolbarItem(placement: .navigationBarLeading) {
                            EditButton()
                        }
                    }
                    #endif

                    #if os(watchOS)
                    ToolbarItem(placement: .bottomBar) {
                        Button(action: {
                            Task { await providerManager.fetchAllBalances() }
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    #endif
                }
            #endif
        }
        .sheet(isPresented: Binding(
            get: { showingAddProvider || wantsAddFromPanel },
            set: { newValue in
                showingAddProvider = newValue
                if !newValue { PanelActions.showAddProvider = false }
            }
        )) {
            AddProviderView(providerManager: providerManager)
        }
        .task {
            providerManager.startPolling()
        }
    }

    private var mainContent: some View {
        Group {
            if providerManager.providers.isEmpty {
                emptyStateView
            } else {
                providerList
            }
        }
    }

    /// 配置窗口的自绘顶栏(配合 hiddenTitleBar 使用)
    private var header: some View {
        HStack(spacing: 10) {
            Text("Token Monitor")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                Task { await providerManager.fetchAllBalances() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("刷新全部")

            Button {
                showingAddProvider = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("添加提供方")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Providers", systemImage: "network.slash")
        } description: {
            Text("Add an AI provider to monitor token usage and balances.")
        } actions: {
            Button("Add Provider") {
                showingAddProvider = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var providerList: some View {
        #if os(macOS)
        List {
            ForEach(providerManager.providers, id: \.id) { provider in
                ProviderConfigRow(
                    provider: provider,
                    displayName: providerManager.providerNames[provider.id],
                    onRename: { providerManager.renameProvider(id: provider.id, to: $0) },
                    onDelete: { providerManager.removeProvider(id: provider.id) }
                )
            }
        }
        .listStyle(.inset)
        #else
        List {
            ForEach(providerManager.providers, id: \.id) { provider in
                ProviderRowView(
                    provider: provider,
                    displayName: providerManager.providerNames[provider.id],
                    balance: providerManager.balances[provider.id],
                    error: providerManager.errors[provider.id]
                )
                .contextMenu {
                    Button(role: .destructive) {
                        providerManager.removeProvider(id: provider.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
            .onDelete { indexSet in
                indexSet.forEach { index in
                    let provider = providerManager.providers[index]
                    providerManager.removeProvider(id: provider.id)
                }
            }
        }
        .listStyle(.insetGrouped)
        #endif
    }
}

/// macOS 配置窗口的行:品牌图标 + 名称(可改名)+ 类型 + 删除按钮,不展示额度数据。
struct ProviderConfigRow: View {
    let provider: any ModelProvider
    let displayName: String?
    var onRename: ((String) -> Void)?
    var onDelete: (() -> Void)?

    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            brandIcon

            VStack(alignment: .leading, spacing: 1) {
                if isEditingName {
                    TextField("账户名称", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .focused($nameFieldFocused)
                        .onSubmit(commitRename)
                        #if os(macOS)
                        .onExitCommand { isEditingName = false }
                        #endif
                } else {
                    Text(displayName ?? provider.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        #if os(macOS)
                        .onTapGesture(count: 2) { beginRename() }
                        #endif
                }

                Text(provider.name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if onRename != nil {
                Button {
                    beginRename()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("重命名账户")
            }

            if onDelete != nil {
                Button {
                    onDelete?()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("删除")
            }
        }
        .padding(.vertical, 2)
    }

    private var brandIcon: some View {
        Group {
            if let brand = ProviderIcon.brandImage(for: provider) {
                brand
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: ProviderIcon.symbolName(for: provider))
                    .foregroundColor(ProviderIcon.color(for: provider))
                    .font(.title3)
            }
        }
        .frame(width: 30, height: 30)
    }

    private func beginRename() {
        draftName = displayName ?? provider.name
        isEditingName = true
        DispatchQueue.main.async {
            nameFieldFocused = true
        }
    }

    private func commitRename() {
        guard isEditingName else { return }
        onRename?(draftName)
        isEditingName = false
    }
}

struct ProviderRowView: View {
    let provider: any ModelProvider
    var displayName: String?
    let balance: Balance?
    let error: Error?
    var onRename: ((String) -> Void)? = nil

    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        #if os(macOS)
        HStack(spacing: 10) {
            providerIcon
            providerTitle

            balanceView
                .frame(minWidth: 230, idealWidth: 300, maxWidth: 330)
        }
        .padding(.vertical, 4)
        #else
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                providerIcon
                providerTitle
            }
            balanceView
        }
        #endif
    }

    private var providerTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if isEditingName {
                    TextField("账户名称", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .focused($nameFieldFocused)
                        .onSubmit(commitRename)
                        #if os(macOS)
                        .onExitCommand { isEditingName = false }
                        #endif
                } else {
                    Text(displayName ?? provider.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        #if os(macOS)
                        .onTapGesture(count: 2) { beginRename() }
                        #endif
                }

                Spacer(minLength: 4)

                if let balance {
                    Text("更新于 \(QuotaDisplay.relativeUpdateText(balance.timestamp))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if onRename != nil {
                    Button {
                        beginRename()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("重命名账户")
                }
            }

            if displayName != nil, !isEditingName {
                // 自定义了账户名时,第二行标注提供方类型以便区分
                Text(provider.name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private func beginRename() {
        draftName = displayName ?? provider.name
        isEditingName = true
        DispatchQueue.main.async {
            nameFieldFocused = true
        }
    }

    private func commitRename() {
        guard isEditingName else { return }
        onRename?(draftName)
        isEditingName = false
    }

    private var providerIcon: some View {
        Group {
            if let brand = ProviderIcon.brandImage(for: provider) {
                brand
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: ProviderIcon.symbolName(for: provider))
                    .foregroundColor(ProviderIcon.color(for: provider))
                    .font(.title3)
            }
        }
            .frame(width: 32, height: 32)
            #if os(iOS)
            .background(Color(uiColor: .systemBackground))
            #elseif os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
            #else
            .background(Color.clear)
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    #if os(iOS)
                    .stroke(Color(uiColor: .systemGray4), lineWidth: 1)
                    #elseif os(macOS)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    #else
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    #endif
            )
    }

    @ViewBuilder
    private var balanceView: some View {
        if let balance = balance {
            VStack(alignment: .leading, spacing: 5) {
                let quotas = QuotaDisplay.quotas(for: balance)
                if !quotas.isEmpty {
                    // 多配额按等宽列排布,进度条上下对齐
                    #if os(macOS)
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(quotas) { quotaColumnView($0) }
                    }
                    #else
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(quotas) { quotaColumnView($0) }
                    }
                    #endif
                } else {
                    singleQuotaView(balance)
                }
            }
        } else if let error = error {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)

                Text(error.localizedDescription)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        } else {
            ProgressView()
                .scaleEffect(0.7)
        }
    }

    /// 单个配额列:名称 / 百分比 + 重置时间 / 进度条,宽度与相邻列一致以保证对齐。
    private func quotaColumnView(_ quota: QuotaDisplay.QuotaInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(quota.name)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let remaining = quota.remainingPercent {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(remaining.rounded()))%")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundColor(.primary)

                    Spacer(minLength: 4)

                    if let resetDate = quota.resetDate {
                        Text(QuotaDisplay.resetText(resetDate, quotaName: quota.name))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                QuotaBar(remainingPercent: remaining, marker: QuotaDisplay.timeMarker(quota))

                if let resetDate = quota.resetDate {
                    Text("\(QuotaDisplay.countdownText(resetDate))后重置")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(" ")
                        .font(.caption2)
                }
            } else {
                Text("—")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func singleQuotaView(_ balance: Balance) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if balance.currency == "percent" || balance.currency == "used_percent" {
                let remainingPercent = min(100, max(0, (1 - balance.amount) * 100))
                HStack(spacing: 8) {
                    QuotaBar(remainingPercent: remainingPercent)

                    Text("\(Int(remainingPercent.rounded()))%")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundColor(.primary)
                        .fixedSize()
                }
            } else {
                Text(QuotaDisplay.balanceText(balance))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundColor(QuotaDisplay.balanceColor(for: balance))
                    .lineLimit(1)
            }

            if let resetTimeString = balance.details?["primary_nextResetTime"],
               let resetTimestamp = Int64(resetTimeString) {
                let resetDate = Date(timeIntervalSince1970: TimeInterval(resetTimestamp) / 1000)
                Text("重置: \(QuotaDisplay.resetText(resetDate, quotaName: balance.details?["period"])) · \(QuotaDisplay.countdownText(resetDate))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct AddProviderView: View {
    @Environment(\.dismiss) var dismiss
    #if os(macOS)
    @State private var providerType: ProviderType = .codex
    #else
    @State private var providerType: ProviderType = .openAIAPI
    #endif
    @State private var providerName = ""
    @State private var apiKey = ""
    @State private var isKeyVisible = false
    @State private var isValidating = false
    @State private var showError = false
    @State private var errorMessage = ""
    let providerManager: ProviderManager
    
    enum ProviderType: String, CaseIterable {
        case codex = "OpenAI Codex"
        case openAIAPI = "OpenAI API"
        case anthropic = "Anthropic"
        case zhipuai = "ZhipuAI"
        case kimiCoding = "Kimi for Coding"
        case mimo = "Xiaomi MiMo"
        
        var description: String {
            switch self {
            case .codex: return "Use local ChatGPT login"
            case .openAIAPI: return "Platform API token usage"
            case .anthropic: return "Claude models"
            case .zhipuai: return "GLM models (bigmodel.cn)"
            case .kimiCoding: return "Kimi Coding Plan quota"
            case .mimo: return "MiMo models (xiaomimimo.com)"
            }
        }
        
        var icon: String {
            switch self {
            case .codex: return "terminal.fill"
            case .openAIAPI: return "brain.head.profile"
            case .anthropic: return "ant.circle.fill"
            case .zhipuai: return "z.circle.fill"
            case .kimiCoding: return "moon.stars.fill"
            case .mimo: return "m.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .codex, .openAIAPI: return .green
            case .anthropic: return .orange
            case .zhipuai: return .blue
            case .kimiCoding: return .purple
            case .mimo: return .orange
            }
        }

        var brandAsset: String? {
            switch self {
            case .codex, .openAIAPI: return "brand-openai"
            case .anthropic: return "brand-anthropic"
            case .kimiCoding: return "brand-kimi"
            case .zhipuai: return "brand-zhipu"
            case .mimo: return "brand-xiaomi"
            }
        }

        static var availableCases: [ProviderType] {
            #if os(macOS)
            return allCases
            #else
            return allCases.filter { $0 != .codex }
            #endif
        }

        var requiresAPIKey: Bool {
            self != .codex
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Account Name Section
                Section {
                    TextField("Account Name (optional)", text: $providerName)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Account Name")
                } footer: {
                    Text("Optional name to distinguish multiple accounts of the same provider.")
                }
                
                // Provider Selection Section
                Section {
                    ForEach(ProviderType.availableCases, id: \.self) { type in
                        Button {
                            providerType = type
                        } label: {
                            HStack(spacing: 16) {
                                Group {
                                    if let brandAsset = type.brandAsset,
                                       let brand = ProviderIcon.brandImage(named: brandAsset) {
                                        brand.resizable().scaledToFit()
                                            .frame(width: 28, height: 28)
                                    } else {
                                        Image(systemName: type.icon)
                                            .foregroundColor(type.color)
                                    }
                                }
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(type.color.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.rawValue)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text(type.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if providerType == type {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Provider")
                } footer: {
                    Text("Select the AI provider you want to monitor.")
                }
                
                // API Key Section
                Section {
                    if providerType == .codex {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.title2)
                                .foregroundColor(.green)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Uses your local Codex login")
                                    .font(.headline)
                                Text("No API key is required. Codex manages and refreshes the ChatGPT authentication.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        HStack(spacing: 12) {
                        if isKeyVisible {
                            TextField("API Key", text: $apiKey)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                        } else {
                            SecureField("API Key", text: $apiKey)
                        }
                        
                        Button {
                            isKeyVisible.toggle()
                        } label: {
                            Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    if providerType == .zhipuai {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter your ZhipuAI API key from bigmodel.cn")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Link("Get API Key", destination: URL(string: "https://open.bigmodel.cn/usercenter/apikeys")!)
                                .font(.caption)
                        }
                    } else if providerType == .kimiCoding {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter the API key from your Kimi Code console. Coding Plan usage is separate from the Moonshot platform balance.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Link("Get API Key", destination: URL(string: "https://www.kimi.com/code/console")!)
                                .font(.caption)
                        }
                    } else if providerType == .openAIAPI {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter an OpenAI Admin API key. Standard project API keys cannot read organization usage.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Link("Manage Admin API Keys", destination: URL(string: "https://platform.openai.com/settings/organization/admin-keys")!)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text(providerType == .codex ? "Requires Codex CLI signed in with ChatGPT on this Mac." : "Your API key is stored on this device.")
                }
                
                // Validation Status Section
                if isValidating {
                    Section {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Validating provider…")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Add Button Section
                #if !os(macOS)
                Section {
                    addProviderButton
                }
                #endif
            }
            #if os(macOS)
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                macOSActionBar
            }
            #endif
            .navigationTitle("Add Provider")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if !os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                #endif
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 560, idealHeight: 660)
        #endif
    }

    private var addProviderButton: some View {
        Button(action: addProvider) {
            HStack(spacing: 10) {
                if isValidating {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isValidating ? "Validating…" : "Add Provider")
                    .fontWeight(.semibold)
            }
            #if !os(macOS)
            .frame(maxWidth: .infinity, minHeight: 44)
            #endif
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled((providerType.requiresAPIKey && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || isValidating)
    }

    #if os(macOS)
    private var macOSActionBar: some View {
        HStack(spacing: 12) {
            Text("Select a provider and enter its credentials to continue.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer(minLength: 24)

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.large)

            addProviderButton
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
    #endif
    
    private func addProvider() {
        isValidating = true
        
        Task {
            do {
                let provider: any ModelProvider
                switch providerType {
                case .codex:
                    provider = CodexProvider(id: UUID())
                case .openAIAPI:
                    provider = OpenAIProvider(id: UUID(), apiKey: apiKey)
                case .anthropic:
                    provider = AnthropicProvider(id: UUID(), apiKey: apiKey)
                case .zhipuai:
                    provider = ZhipuAIProvider(id: UUID(), apiKey: apiKey)
                case .kimiCoding:
                    provider = KimiCodingProvider(id: UUID(), apiKey: apiKey)
                case .mimo:
                    provider = MiMoProvider(id: UUID(), apiKey: apiKey)
                }
                
                // Test the API key by fetching balance
                let balance = try await provider.fetchBalance()

                await MainActor.run {
                    providerManager.addProvider(provider, name: providerName.isEmpty ? nil : providerName)
                    providerManager.balances[provider.id] = balance
                    isValidating = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to add provider: \(error.localizedDescription)"
                    showError = true
                    isValidating = false
                }
            }
        }
    }
}
