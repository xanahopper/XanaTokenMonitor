import SwiftUI
#if os(macOS)
import AppKit
typealias ProviderIconPlatformImage = NSImage
#else
import UIKit
typealias ProviderIconPlatformImage = UIImage
#endif

/// 面板与主窗口之间的轻量动作通道
@MainActor
enum PanelActions {
    /// 面板请求主窗口展示「添加提供方」
    static var showAddProvider = false
}

/// 按剩余额度百分比取色:剩余 100% 绿、75% 黄、20% 以下红,区间内用鲜艳锚点色做 RGB 线性过渡。
enum QuotaPalette {
    private static let green = (r: 50.0, g: 215.0, b: 75.0)
    private static let yellow = (r: 255.0, g: 214.0, b: 10.0)
    private static let red = (r: 255.0, g: 69.0, b: 58.0)

    static func rgb(remainingPercent: Double) -> (r: Double, g: Double, b: Double) {
        let remaining = min(100, max(0, remainingPercent))
        switch remaining {
        case 75...100:
            return lerp(green, yellow, (100 - remaining) / 25)
        case 20..<75:
            return lerp(yellow, red, (75 - remaining) / 55)
        default:
            return red
        }
    }

    static func remainingColor(remainingPercent: Double) -> Color {
        let c = rgb(remainingPercent: remainingPercent)
        return Color(red: c.r / 255, green: c.g / 255, blue: c.b / 255)
    }

    /// 与 remainingColor 同色的十六进制值(供 Widget 等跨进程读取)。
    static func hexString(remainingPercent: Double) -> String {
        let c = rgb(remainingPercent: remainingPercent)
        return String(format: "#%02X%02X%02X", Int(c.r.rounded()), Int(c.g.rounded()), Int(c.b.rounded()))
    }

    private static func lerp(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double), _ t: Double) -> (r: Double, g: Double, b: Double) {
        (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }
}

/// 紧凑的剩余额度进度条:填充比例 = 剩余百分比,颜色随剩余量变化。
struct QuotaBar: View {
    let remainingPercent: Double
    var height: CGFloat = 5
    /// 「按时间匀速使用」的期望位置(0...1),画一根细竖线标记
    var marker: Double? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))

                Capsule()
                    .fill(QuotaPalette.remainingColor(remainingPercent: remainingPercent))
                    .frame(width: fillWidth(total: proxy.size.width))

                if let marker {
                    Rectangle()
                        .fill(Color.primary.opacity(0.45))
                        .frame(width: 1)
                        .offset(x: min(1, max(0, marker)) * proxy.size.width - 0.5)
                }
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.25), value: remainingPercent)
    }

    private func fillWidth(total: CGFloat) -> CGFloat {
        guard remainingPercent > 0 else { return 0 }
        return min(total, max(height, total * remainingPercent / 100))
    }
}

/// 从 Balance 中提取配额信息与展示文案,供主列表、菜单栏面板与 Widget 快照共用。
enum QuotaDisplay {
    struct QuotaInfo: Identifiable {
        let index: Int
        let name: String
        let remainingPercent: Double?
        let resetDate: Date?
        let durationMins: Double?

        var id: Int { index }
    }

    /// details 中的 percentage 为「已用」口径,这里统一换算为「剩余」。
    static func quotas(for balance: Balance) -> [QuotaInfo] {
        guard let details = balance.details,
              let countString = details["quotas_count"],
              let count = Int(countString), count > 0 else { return [] }

        return (0..<min(count, 3)).map { index in
            let prefix = "quota_\(index)_"
            let used = details[prefix + "percentage"].flatMap(Int.init)
            let remaining = used.map { Double(min(100, max(0, 100 - $0))) }
            let resetDate = details[prefix + "nextResetTime"]
                .flatMap(Int64.init)
                .map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
            let name = details[prefix + "name"] ?? fallbackQuotaName(details: details, prefix: prefix, index: index)
            let durationMins = details[prefix + "durationMins"].flatMap(Double.init)
                ?? fallbackDurationMins(fromName: name)
            return QuotaInfo(index: index, name: name, remainingPercent: remaining, resetDate: resetDate, durationMins: durationMins)
        }
    }

    /// 从配额名称推断窗口时长(分钟),供详情缺失时兜底:周 → 10080,`5h` → 300
    static func fallbackDurationMins(fromName name: String) -> Double? {
        let lower = name.lowercased()
        if lower.contains("周") || lower.contains("week") { return 10080 }
        if lower.hasSuffix("h"), let hours = Double(lower.dropLast()) { return hours * 60 }
        if lower.hasSuffix("d"), let days = Double(lower.dropLast()) { return days * 1440 }
        return nil
    }

    /// 未写入 name 时的兜底(兼容旧数据):智谱 unit 3 = 小时、6 = 周。
    private static func fallbackQuotaName(details: [String: String], prefix: String, index: Int) -> String {
        if let unit = details[prefix + "unit"], let number = details[prefix + "number"] {
            switch unit {
            case "3": return "\(number)h"
            case "6": return "周"
            default: break
            }
        }
        return "配额\(index + 1)"
    }

    /// 所有配额中最低的剩余百分比(最紧的那条),无百分比口径时返回 nil。
    static func worstRemainingPercent(_ balance: Balance) -> Double? {
        switch balance.currency {
        case "percent", "used_percent":
            return min(100, max(0, (1 - balance.amount) * 100))
        default:
            let remaining = quotas(for: balance).compactMap(\.remainingPercent)
            return remaining.min()
        }
    }

    static func balanceText(_ balance: Balance) -> String {
        switch balance.currency {
        case "tokens":
            return "\(Int(balance.amount).formatted()) tokens"
        case "percent", "used_percent":
            return "\(Int((min(100, max(0, (1 - balance.amount) * 100))).rounded()))%"
        case "quota":
            return "\(balance.amount.formatted()) quota"
        default:
            return balance.amount.formatted(.currency(code: balance.currency))
        }
    }

    static func balanceColor(for balance: Balance) -> Color {
        switch balance.currency {
        case "tokens":
            if balance.amount > 1_000_000 {
                return .green
            } else if balance.amount > 100_000 {
                return .orange
            } else {
                return .red
            }
        case "percent", "used_percent":
            return QuotaPalette.remainingColor(remainingPercent: (1 - balance.amount) * 100)
        default:
            return balance.amount > 0 ? .green : .red
        }
    }

    /// 「按时间匀速使用」时剩余应处的位置(0...1)。
    /// 仅天级及以上的长窗口提供(周/7d),小时窗口不画刻度。
    static func timeMarker(_ info: QuotaInfo, now: Date = Date()) -> Double? {
        guard let durationMins = info.durationMins, durationMins >= 1440,
              let resetDate = info.resetDate else { return nil }
        let totalSeconds = durationMins * 60
        let remainingTime = resetDate.timeIntervalSince(now)
        guard totalSeconds > 0, remainingTime > 0 else { return nil }
        return min(1, max(0, remainingTime / totalSeconds))
    }

    /// 重置时间:周/天级窗口显示「X月X日 HH:mm」,小时级窗口只显示「HH:mm」,均为中文格式。
    static func resetText(_ date: Date, quotaName: String? = nil) -> String {
        let components = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date)
        let time = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
        if isLongWindow(quotaName) {
            return String(format: "%d月%d日 ", components.month ?? 0, components.day ?? 0) + time
        }
        return time
    }

    private static func isLongWindow(_ name: String?) -> Bool {
        guard let name else { return false }
        return name.contains("周") || name.contains("天") || name.contains("月")
            || name.contains("d") || name.contains("D")
    }

    /// 中文相对时间:刚刚 / X分钟前 / X小时前 / X天前。
    static func relativeUpdateText(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(seconds / 60)分钟前" }
        if seconds < 86400 { return "\(seconds / 3600)小时前" }
        return "\(seconds / 86400)天前"
    }

    /// 距离重置的倒计时:3天9时 / 2时18分 / 45分;已过重置点显示「即将重置」。
    static func countdownText(_ date: Date, now: Date = Date()) -> String {
        let totalMinutes = Int(date.timeIntervalSince(now) / 60)
        if totalMinutes <= 0 { return "即将重置" }
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)天\(hours)时" }
        if hours > 0 { return "\(hours)时\(minutes)分" }
        return "\(minutes)分钟"
    }
}

enum ProviderIcon {
    /// 各提供方的品牌图标(打包在 Resources/brand 下),无品牌的回退 SF Symbol
    static func brandAssetName(for provider: any ModelProvider) -> String? {
        if provider is CodexProvider || provider is OpenAIProvider {
            return "brand-openai"
        } else if provider is AnthropicProvider {
            return "brand-anthropic"
        } else if provider is KimiCodingProvider {
            return "brand-kimi"
        } else if provider is ZhipuAIProvider {
            return "brand-zhipu"
        } else if provider is MiMoProvider {
            return "brand-xiaomi"
        }
        return nil
    }

    static func brandImage(for provider: any ModelProvider) -> Image? {
        guard let name = brandAssetName(for: provider) else { return nil }
        return brandImage(named: name)
    }

    static func brandImage(named assetName: String) -> Image? {
        guard let image = loadPlatformImage(named: assetName) else { return nil }
        #if os(macOS)
        return Image(nsImage: image)
        #else
        return Image(uiImage: image)
        #endif
    }

    /// 图标以 base64 内嵌在 BrandIcons.swift 中,不依赖任何打包形态的资源路径。
    private static func loadPlatformImage(named name: String) -> ProviderIconPlatformImage? {
        guard let data = BrandIconData.data(forAsset: name), !data.isEmpty else { return nil }
        #if os(macOS)
        return NSImage(data: data)
        #else
        return UIImage(data: data)
        #endif
    }

    static func symbolName(for provider: any ModelProvider) -> String {
        if provider is CodexProvider {
            return "terminal.fill"
        } else if provider is OpenAIProvider {
            return "brain.head.profile"
        } else if provider is AnthropicProvider {
            return "ant.circle.fill"
        } else if provider is KimiCodingProvider {
            return "moon.stars.fill"
        } else if provider is ZhipuAIProvider {
            return "z.circle.fill"
        } else if provider is MiMoProvider {
            return "m.circle.fill"
        }
        return "cpu.fill"
    }

    static func color(for provider: any ModelProvider) -> Color {
        if provider is CodexProvider || provider is OpenAIProvider {
            return .green
        } else if provider is AnthropicProvider || provider is MiMoProvider {
            return .orange
        } else if provider is KimiCodingProvider {
            return .purple
        } else if provider is ZhipuAIProvider {
            return .blue
        }
        return .gray
    }
}
