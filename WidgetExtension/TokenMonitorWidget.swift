import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 数据读取

struct WidgetProviderItem: Codable, Identifiable {
    let id: String
    let name: String
    let text: String
    let percent: Double?   // 剩余 0...1
    let color: String      // #RRGGBB
    let asset: String?     // 品牌图标资源名(brand-*)
    let resetAbsolute: String?
    let resetIn: String?

    var resetLine: String? {
        [resetAbsolute, resetIn].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

enum WidgetStore {
    static let suiteName = "group.com.xana.token-monitor"

    static func loadItems() -> [WidgetProviderItem] {
        // 第一优先:直读容器里的 JSON 文件,绕开 cfprefsd 对外部写入的缓存
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) {
            let jsonURL = container.appendingPathComponent("widget_data.json")
            if let data = try? Data(contentsOf: jsonURL),
               let items = try? JSONDecoder().decode([WidgetProviderItem].self, from: data) {
                return items
            }
        }

        let defaults = UserDefaults(suiteName: suiteName)
        if let data = defaults?.data(forKey: "widgetProvidersData"),
           let items = try? JSONDecoder().decode([WidgetProviderItem].self, from: data) {
            return items
        }

        // 兜底:直接读 Group Container 里的 plist
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appendingPathComponent("Library/Preferences/\(suiteName).plist"),
           let dict = NSDictionary(contentsOf: container),
           let data = dict["widgetProvidersData"] as? Data,
           let items = try? JSONDecoder().decode([WidgetProviderItem].self, from: data) {
            return items
        }

        return []
    }

    static func itemColor(_ hex: String) -> Color {
        Color(hex: hex) ?? .gray
    }
}

// MARK: - 小组件配置(编辑小组件时选择提供方)

struct ProviderEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "提供方")
    typealias DefaultQuery = ProviderEntityQuery
    static var defaultQuery: ProviderEntityQuery { ProviderEntityQuery() }

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

struct ProviderEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProviderEntity] {
        WidgetStore.loadItems().filter { identifiers.contains($0.id) }
            .map { ProviderEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [ProviderEntity] {
        WidgetStore.loadItems().map { ProviderEntity(id: $0.id, name: $0.name) }
    }

    func defaultResult() async -> ProviderEntity? {
        WidgetStore.loadItems().first.map { ProviderEntity(id: $0.id, name: $0.name) }
    }
}

struct SelectProviderIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择提供方"
    static let description = IntentDescription("选择小组件展示的提供方,中尺寸会展示全部")

    @Parameter(title: "提供方")
    var target: ProviderEntity?
}

// MARK: - 时间线

struct ProviderEntry: TimelineEntry {
    let date: Date
    let items: [WidgetProviderItem]
    let timeText: String
}

struct ProviderTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = SelectProviderIntent
    typealias Entry = ProviderEntry

    func placeholder(in context: Context) -> ProviderEntry {
        sampleEntry()
    }

    func snapshot(for configuration: SelectProviderIntent, in context: Context) async -> ProviderEntry {
        makeEntry(configuration: configuration, family: context.family)
    }

    func timeline(for configuration: SelectProviderIntent, in context: Context) async -> Timeline<ProviderEntry> {
        let entry = makeEntry(configuration: configuration, family: context.family)
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func sampleEntry() -> ProviderEntry {
        ProviderEntry(
            date: Date(),
            items: [
                WidgetProviderItem(id: "1", name: "ZhipuAI", text: "96%", percent: 0.96, color: "#32D74B",
                                   asset: nil, resetAbsolute: "15:49", resetIn: "2时18分"),
                WidgetProviderItem(id: "2", name: "Kimi", text: "88%", percent: 0.88, color: "#FFD60A",
                                   asset: nil, resetAbsolute: "9月8日 14:31", resetIn: "1天3时")
            ],
            timeText: "12:00"
        )
    }

    private func makeEntry(configuration: SelectProviderIntent, family: WidgetFamily) -> ProviderEntry {
        let all = WidgetStore.loadItems()
        var items = all
        if family == .systemSmall {
            let selected = all.first { $0.id == configuration.target?.id } ?? all.first
            items = selected.map { [$0] } ?? []
        } else {
            items = Array(all.prefix(4))
        }

        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return ProviderEntry(
            date: Date(),
            items: items,
            timeText: String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
        )
    }
}

// MARK: - 视图

struct TokenMonitorWidgetEntryView: View {
    var entry: ProviderEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumView
            } else {
                singleView(item: entry.items.first)
            }
        }
        .padding(12)
    }

    /// 中尺寸:多行,每行一个提供方
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 7) {
            if entry.items.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(entry.items) { item in
                    HStack(spacing: 7) {
                        itemIcon(item)

                        Text(item.name)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        if let percent = item.percent {
                            MiniBar(percent: percent, color: WidgetStore.itemColor(item.color))
                                .frame(width: 52)

                            Text("\(Int((percent * 100).rounded()))%")
                                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                .foregroundColor(.primary)
                                .frame(width: 26, alignment: .trailing)
                        } else {
                            Text(item.text)
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }

                        if let reset = item.resetLine {
                            Text(reset)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .frame(width: 88, alignment: .trailing)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Text(entry.timeText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    /// 小尺寸:单个提供方
    private func singleView(item: WidgetProviderItem?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let item {
                    itemIcon(item)
                }

                Text(item?.name ?? "No Provider")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Text(entry.timeText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let item {
                if let percent = item.percent {
                    Text("\(Int((percent * 100).rounded()))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .monospacedDigit()

                    MiniBar(percent: percent, color: WidgetStore.itemColor(item.color))
                } else {
                    Text(item.text)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                if let reset = item.resetLine {
                    Text(reset)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func itemIcon(_ item: WidgetProviderItem) -> some View {
        Group {
            if let asset = item.asset, let brand = WidgetBrandIcon.image(named: asset) {
                brand
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 11, height: 11)
    }
}

/// 迷你进度条(Widget 扩展内不依赖主工程)
struct MiniBar: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))

                Capsule()
                    .fill(color)
                    .frame(width: max(3, proxy.size.width * min(1, max(0, percent))))
            }
        }
    }
}

struct TokenMonitorWidget: Widget {
    let kind: String = "TokenMonitorWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectProviderIntent.self, provider: ProviderTimelineProvider()) { entry in
            TokenMonitorWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Token Monitor")
        .description("Monitor your AI provider token usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// Color 扩展，支持十六进制字符串
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

@main
struct TokenMonitorWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenMonitorWidget()
    }
}
