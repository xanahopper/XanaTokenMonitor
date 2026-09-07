#if os(macOS)
import AppKit
import SwiftUI

@MainActor
enum MainWindowOpener {
    /// 启动时被隐藏的主窗口由此唤起;窗口已被真正关闭(实例释放)时回退到 URL 重开。
    static func open() {
        if let window = MainWindowTracker.window {
            MainWindowTracker.show(window)
        } else if let url = URL(string: "xana-token-monitor://main") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 追踪 WindowGroup 的主窗口:启动时隐藏它以实现纯菜单栏模式,打开时再恢复。
@MainActor
enum MainWindowTracker {
    static weak var window: NSWindow?
    static var didHideInitialWindow = false

    static func hideForLaunch(_ window: NSWindow) {
        self.window = window
        didHideInitialWindow = true
        NSApp.setActivationPolicy(.accessory)
        window.orderOut(nil)

        // SwiftUI 可能在内容布局完成后才展示窗口,下一拍再确认一次
        DispatchQueue.main.async { [weak window] in
            MainActor.assumeIsolated {
                if let window, window.isVisible {
                    window.orderOut(nil)
                }
            }
        }
    }

    static func show(_ window: NSWindow) {
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// 状态栏图标点击后弹出的紧凑面板:提供方名称为小节头,下方逐行列出配额,小节间用分隔线。
struct MenuBarQuotaPanel: View {
    let providerManager: ProviderManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if providerManager.providers.isEmpty {
                Text("尚未添加提供方")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(providerManager.providers.enumerated()), id: \.element.id) { index, provider in
                    section(
                        provider: provider,
                        balance: providerManager.balances[provider.id],
                        error: providerManager.errors[provider.id]
                    )

                    if index < providerManager.providers.count - 1 {
                        Divider()
                            .padding(.vertical, 5)
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 0) {
                Spacer()
                controlButton("plus", help: "添加提供方") {
                    MainWindowOpener.open()
                    PanelActions.showAddProvider = true
                }
                Spacer()
                controlButton("gearshape", help: "打开配置窗口") {
                    MainWindowOpener.open()
                }
                Spacer()
                controlButton("arrow.clockwise", help: "刷新全部") {
                    Task { await providerManager.fetchAllBalances() }
                }
                Spacer()
                controlButton("power", help: "退出") {
                    NSApp.terminate(nil)
                }
                Spacer()
            }
            .frame(height: 22)
        }
        .padding(10)
        .frame(width: 272)
        .task {
            if providerManager.balances.isEmpty {
                await providerManager.fetchAllBalances()
            }
        }
    }

    /// 单个提供方小节:名称 + 更新时间一行,配额逐行排布
    @ViewBuilder
    private func section(provider: any ModelProvider, balance: Balance?, error: Error?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Group {
                    if let brand = ProviderIcon.brandImage(for: provider) {
                        brand.resizable().scaledToFit()
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: ProviderIcon.symbolName(for: provider))
                            .font(.system(size: 9))
                            .foregroundColor(ProviderIcon.color(for: provider))
                    }
                }
                .frame(width: 12, height: 12)

                Text(providerManager.providerNames[provider.id] ?? provider.name)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

            }
            .padding(.bottom, 1)

            if let balance {
                let quotas = QuotaDisplay.quotas(for: balance)
                if !quotas.isEmpty {
                    ForEach(quotas) { quota in
                        quotaLine(quota)
                    }
                } else {
                    Text(QuotaDisplay.balanceText(balance))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let resetTimeString = balance.details?["primary_nextResetTime"],
                       let resetTimestamp = Int64(resetTimeString) {
                        let resetDate = Date(timeIntervalSince1970: TimeInterval(resetTimestamp) / 1000)
                        Text("重置: \(QuotaDisplay.resetText(resetDate, quotaName: balance.details?["period"]))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else if let error {
                Text(error.localizedDescription)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(1)
            } else {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(height: 12)
            }
        }
        .padding(.vertical, 1)
    }

    private func quotaLine(_ quota: QuotaDisplay.QuotaInfo) -> some View {
        HStack(spacing: 8) {
            Text(quota.name)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 24, alignment: .leading)

            if let remaining = quota.remainingPercent {
                QuotaBar(remainingPercent: remaining, height: 5, marker: QuotaDisplay.timeMarker(quota))
                    .frame(maxWidth: .infinity)

                Text("\(Int(remaining.rounded()))%")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .frame(width: 28, alignment: .trailing)

                Text(quota.resetDate.map { QuotaDisplay.resetText($0, quotaName: quota.name) } ?? "")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 64, alignment: .trailing)

                Text(quota.resetDate.map { QuotaDisplay.countdownText($0) } ?? "")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 42, alignment: .trailing)
            } else {
                Spacer(minLength: 0)
            }
        }
        // 统一行高,保证各行进度条垂直对齐
        .frame(height: 14)
    }

    private func controlButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .frame(width: 38, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
#endif
