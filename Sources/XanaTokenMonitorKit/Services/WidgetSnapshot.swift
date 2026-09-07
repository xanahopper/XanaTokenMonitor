import Foundation
import WidgetKit

/// 把全部提供方的余额快照写入 App Group,供桌面小组件读取,并触发时间线刷新。
enum WidgetSnapshot {
    static let suiteName = "group.com.xana.token-monitor"

    struct Item: Codable {
        let id: String
        let name: String
        let text: String
        let percent: Double?   // 剩余 0...1,无百分比口径时为 nil
        let color: String      // #RRGGBB
        let trackLightColor: String? // 亮色外观下的空槽色
        let trackDarkColor: String?  // 暗色外观下的空槽色
        let asset: String?     // 品牌图标资源名(brand-*)
        let resetAbsolute: String? // 最近一次重置的绝对时间文案
        let resetIn: String?       // 距离该重置的倒计时文案
    }

    static func push(providers: [any ModelProvider], balances: [UUID: Balance], displayNames: [UUID: String]) {
        let now = Date()
        let items: [Item] = providers.compactMap { provider in
            guard let balance = balances[provider.id] else { return nil }

            // 所有配额中最近的一次未来重置
            var nextReset: (date: Date, name: String)? = nil
            for quota in QuotaDisplay.quotas(for: balance) {
                guard let date = quota.resetDate, date > now else { continue }
                if nextReset == nil || date < nextReset!.date {
                    nextReset = (date, quota.name)
                }
            }

            return Item(
                id: provider.id.uuidString,
                name: displayNames[provider.id] ?? provider.name,
                text: QuotaDisplay.balanceText(balance),
                percent: QuotaDisplay.worstRemainingPercent(balance).map { $0 / 100 },
                color: QuotaPalette.hexString(remainingPercent: QuotaDisplay.worstRemainingPercent(balance) ?? 100),
                trackLightColor: QuotaPalette.trackHexString(darkAppearance: false),
                trackDarkColor: QuotaPalette.trackHexString(darkAppearance: true),
                asset: ProviderIcon.brandAssetName(for: provider),
                resetAbsolute: nextReset.map { QuotaDisplay.resetText($0.date, quotaName: $0.name) },
                resetIn: nextReset.map { QuotaDisplay.countdownText($0.date) }
            )
        }

        guard let data = try? JSONEncoder().encode(items) else { return }
        // 主 App 带 app-group entitlement 后,suite 读写会由 cfprefsd 路由到
        // Group Container,与沙盒小组件同源;UserDefaults 是官方推荐通道。
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(data, forKey: "widgetProvidersData")

        #if os(macOS)
        // 同时把 JSON/plist 落到容器目录,直读文件的通道作为兜底
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: suiteName
        ) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(suiteName)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            try data.write(to: container.appendingPathComponent("widget_data.json"))
            try (["widgetProvidersData": data] as NSDictionary)
                .write(to: container.appendingPathComponent("Library/Preferences/\(suiteName).plist"))
        } catch {
            NSLog("WidgetSnapshot: write group container failed: \(error.localizedDescription)")
        }
        #endif

        reloadTimelines()
    }


    private static func reloadTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
