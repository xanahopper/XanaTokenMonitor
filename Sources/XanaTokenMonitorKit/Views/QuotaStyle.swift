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

struct RefreshFeedbackIcon: View {
    let isRefreshing: Bool
    let result: BalanceRefreshResult
    var size: CGFloat = 11

    var body: some View {
        Group {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            } else {
                switch result {
                case .none:
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.primary)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .partialFailure:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                case .failure:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
        }
        .font(.system(size: size, weight: .medium))
        .animation(.easeInOut(duration: 0.15), value: isRefreshing)
        .animation(.easeInOut(duration: 0.15), value: result)
    }
}

/// 每套主题同时定义额度色与空槽色，避免冷色填充和统一灰底混在一起。
enum QuotaColorTheme: String, CaseIterable, Identifiable {
    static let storageKey = "quotaColorTheme"

    case classic
    case minimal
    case calm
    case cyber
    case arctic
    case cream
    case ocean
    case sunset
    case forest
    case morandi

    var id: Self { self }

    var name: String {
        switch self {
        case .classic: return "默认"
        case .minimal: return "极简"
        case .calm: return "宁静"
        case .cyber: return "赛博"
        case .arctic: return "极光"
        case .cream: return "奶油"
        case .ocean: return "深海"
        case .sunset: return "落日"
        case .forest: return "森林"
        case .morandi: return "莫兰迪"
        }
    }

    var description: String {
        switch self {
        case .classic: return "清晰的状态色"
        case .minimal: return "克制的石墨灰"
        case .calm: return "柔和的冷色调"
        case .cyber: return "明亮的霓虹色"
        case .arctic: return "冰川与北境极光"
        case .cream: return "温柔的甜点粉彩"
        case .ocean: return "青绿到靛蓝渐变"
        case .sunset: return "金黄、橙与玫红"
        case .forest: return "苔绿、麦穗与赤土"
        case .morandi: return "低饱和自然色"
        }
    }

    static var selected: QuotaColorTheme {
        let rawValue = UserDefaults.standard.string(forKey: storageKey)
        return rawValue.flatMap(QuotaColorTheme.init(rawValue:)) ?? .classic
    }
}

enum QuotaPalette {
    typealias RGB = (r: Double, g: Double, b: Double)

    private struct Definition {
        let high: RGB
        let middle: RGB
        let low: RGB
        let trackLight: RGB
        let trackDark: RGB
    }

    static func rgb(
        remainingPercent: Double,
        theme: QuotaColorTheme = .selected
    ) -> (r: Double, g: Double, b: Double) {
        let colors = anchors(for: theme)
        let remaining = min(100, max(0, remainingPercent))
        switch remaining {
        case 75...100:
            return lerp(colors.high, colors.middle, (100 - remaining) / 25)
        case 20..<75:
            return lerp(colors.middle, colors.low, (75 - remaining) / 55)
        default:
            return colors.low
        }
    }

    static func remainingColor(
        remainingPercent: Double,
        theme: QuotaColorTheme = .selected
    ) -> Color {
        let c = rgb(remainingPercent: remainingPercent, theme: theme)
        return Color(red: c.r / 255, green: c.g / 255, blue: c.b / 255)
    }

    static func trackRGB(
        theme: QuotaColorTheme = .selected,
        darkAppearance: Bool
    ) -> RGB {
        let colors = definition(for: theme)
        return darkAppearance ? colors.trackDark : colors.trackLight
    }

    static func trackColor(
        theme: QuotaColorTheme = .selected,
        colorScheme: ColorScheme
    ) -> Color {
        let c = trackRGB(theme: theme, darkAppearance: colorScheme == .dark)
        return Color(red: c.r / 255, green: c.g / 255, blue: c.b / 255)
    }

    /// 与 remainingColor 同色的十六进制值(供 Widget 等跨进程读取)。
    static func hexString(
        remainingPercent: Double,
        theme: QuotaColorTheme = .selected
    ) -> String {
        let c = rgb(remainingPercent: remainingPercent, theme: theme)
        return String(format: "#%02X%02X%02X", Int(c.r.rounded()), Int(c.g.rounded()), Int(c.b.rounded()))
    }

    static func trackHexString(
        theme: QuotaColorTheme = .selected,
        darkAppearance: Bool
    ) -> String {
        let c = trackRGB(theme: theme, darkAppearance: darkAppearance)
        return String(format: "#%02X%02X%02X", Int(c.r.rounded()), Int(c.g.rounded()), Int(c.b.rounded()))
    }

    private static func anchors(for theme: QuotaColorTheme) -> (high: RGB, middle: RGB, low: RGB) {
        let colors = definition(for: theme)
        return (colors.high, colors.middle, colors.low)
    }

    private static func definition(for theme: QuotaColorTheme) -> Definition {
        switch theme {
        case .classic:
            return Definition(
                high: (50, 215, 75),
                middle: (255, 214, 10),
                low: (255, 69, 58),
                trackLight: (231, 232, 235),
                trackDark: (56, 58, 64)
            )
        case .minimal:
            return Definition(
                high: (174, 183, 192),
                middle: (113, 123, 133),
                low: (61, 68, 75),
                trackLight: (236, 239, 241),
                trackDark: (37, 40, 44)
            )
        case .calm:
            return Definition(
                high: (91, 200, 184),
                middle: (100, 164, 218),
                low: (125, 117, 189),
                trackLight: (231, 236, 242),
                trackDark: (39, 50, 63)
            )
        case .cyber:
            return Definition(
                high: (0, 245, 212),
                middle: (122, 92, 255),
                low: (255, 43, 214),
                trackLight: (239, 232, 247),
                trackDark: (38, 29, 53)
            )
        case .arctic:
            return Definition(
                high: (163, 190, 140),
                middle: (136, 192, 208),
                low: (191, 97, 106),
                trackLight: (229, 233, 240),
                trackDark: (52, 59, 73)
            )
        case .cream:
            return Definition(
                high: (166, 209, 137),
                middle: (229, 200, 144),
                low: (231, 130, 132),
                trackLight: (239, 230, 226),
                trackDark: (54, 50, 63)
            )
        case .ocean:
            return Definition(
                high: (20, 184, 166),
                middle: (14, 165, 233),
                low: (79, 70, 229),
                trackLight: (224, 240, 242),
                trackDark: (25, 55, 64)
            )
        case .sunset:
            return Definition(
                high: (250, 204, 21),
                middle: (251, 146, 60),
                low: (225, 29, 72),
                trackLight: (245, 224, 218),
                trackDark: (74, 47, 52)
            )
        case .forest:
            return Definition(
                high: (77, 124, 15),
                middle: (202, 138, 4),
                low: (154, 52, 18),
                trackLight: (228, 235, 225),
                trackDark: (38, 58, 46)
            )
        case .morandi:
            return Definition(
                high: (122, 151, 132),
                middle: (184, 165, 140),
                low: (176, 121, 121),
                trackLight: (235, 229, 226),
                trackDark: (63, 56, 60)
            )
        }
    }

    private static func lerp(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }
}

/// 紧凑的剩余额度进度条:填充比例 = 剩余百分比,颜色随剩余量变化。
struct QuotaBar: View {
    let remainingPercent: Double
    var height: CGFloat = 5
    /// 按额度日分配后的可用下限(0...1),画一根细竖线标记
    var marker: Double? = nil
    var animatesChanges = true
    var themeOverride: QuotaColorTheme?
    @AppStorage(QuotaColorTheme.storageKey) private var selectedThemeRawValue = QuotaColorTheme.classic.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(QuotaPalette.trackColor(
                        theme: resolvedTheme,
                        colorScheme: colorScheme
                    ))

                Capsule()
                    .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)

                Capsule()
                    .fill(QuotaPalette.remainingColor(
                        remainingPercent: remainingPercent,
                        theme: resolvedTheme
                    ))
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
        .animation(animatesChanges ? .easeInOut(duration: 0.25) : nil, value: remainingPercent)
    }

    private var resolvedTheme: QuotaColorTheme {
        themeOverride ?? QuotaColorTheme(rawValue: selectedThemeRawValue) ?? .classic
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

    /// 按「额度日」均分后，当前已经可以使用到的剩余额度下限(0...1)。
    ///
    /// 长窗口以接口返回的重置时刻作为每天的额度边界。每到一个新额度日，
    /// 一次性放出当天份额，随后保持不变直到次日同一时刻。例如周三 10:00
    /// 重置的周额度，会在周二 10:00 把刻度降到 0，表示最后一天可以用完。
    /// 小时窗口不画刻度。
    static func timeMarker(
        _ info: QuotaInfo,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double? {
        guard let durationMins = info.durationMins, durationMins >= 1440,
              let resetDate = info.resetDate else { return nil }
        guard now < resetDate else { return nil }

        let quotaDayCount = max(1, Int((durationMins / 1440).rounded()))
        guard let periodStart = calendar.date(
            byAdding: .day,
            value: -quotaDayCount,
            to: resetDate
        ) else { return nil }
        if now < periodStart { return 1 }

        let remainingWholeDays = (1..<quotaDayCount).reduce(into: 0) { count, dayOffset in
            guard let boundary = calendar.date(
                byAdding: .day,
                value: -dayOffset,
                to: resetDate
            ) else { return }
            if boundary > now {
                count += 1
            }
        }
        return Double(remainingWholeDays) / Double(quotaDayCount)
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
