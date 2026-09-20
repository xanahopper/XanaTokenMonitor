import AppKit
import SwiftUI
import XanaTokenMonitorKit

@main
struct XanaTokenMonitorMacOSApp: App {
    @NSApplicationDelegateAdaptor(MainAppDelegate.self) private var appDelegate
    @State private var providerManager = ProviderManager()
    @AppStorage(QuotaColorTheme.storageKey) private var quotaColorThemeRawValue = QuotaColorTheme.classic.rawValue

    var body: some Scene {
        WindowGroup {
            ProviderListView(providerManager: providerManager)
                .frame(minWidth: 680, minHeight: 420)
                .modifier(MainWindowLifecycle())
        }
        .defaultSize(width: 720, height: 460)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarQuotaPanel(providerManager: providerManager)
        } label: {
            let quotaGroups = providerManager.providers
                .compactMap { provider -> [(label: String, value: Double)]? in
                    guard let balance = providerManager.balances[provider.id] else { return nil }
                    let items = QuotaDisplay.quotas(for: balance).compactMap { quota -> (String, Double)? in
                        guard let value = quota.remainingPercent else { return nil }
                        return (quota.name, value)
                    }
                    return items.isEmpty ? nil : Array(items.prefix(2))
                }

            if quotaGroups.isEmpty {
                Image(systemName: "gauge.with.needle")
            } else {
                Image(nsImage: Self.statusBarImage(
                    groups: quotaGroups,
                    theme: QuotaColorTheme(rawValue: quotaColorThemeRawValue) ?? .classic
                ))
            }
        }
        .menuBarExtraStyle(.window)
    }

/// 状态栏图标:每个提供方一组竖条(每根对应一个配额周期,高度 = 剩余百分比),
/// 组间用细分隔线隔开。
    private static func statusBarImage(
        groups: [[(label: String, value: Double)]],
        theme: QuotaColorTheme
    ) -> NSImage {
        let barWidth: CGFloat = 3.5
        let columnGap: CGFloat = 4 // 列间距(容纳标签小字)
        let groupGap: CGFloat = 9 // 组间距(含分隔线)
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 15
        let textHeight: CGFloat = 8
        let pad: CGFloat = 1 // 描边会超出条体半线宽,留边距避免被画布裁剪

        let font = NSFont.systemFont(ofSize: 6.5, weight: .medium)
        let measurementAttrs: [NSAttributedString.Key: Any] = [.font: font]

        // 预排列宽:每列取「条宽 / 标签宽」较大者
        var columns: [[(width: CGFloat, label: String, labelWidth: CGFloat, value: Double)]] = []
        var contentWidth: CGFloat = 0
        for (groupIndex, group) in groups.enumerated() {
            if groupIndex > 0 { contentWidth += groupGap }
            var cols: [(width: CGFloat, label: String, labelWidth: CGFloat, value: Double)] = []
            for (barIndex, item) in group.enumerated() {
                if barIndex > 0 { contentWidth += columnGap }
                let labelWidth = (item.label as NSString).size(withAttributes: measurementAttrs).width
                let columnWidth = max(barWidth, min(labelWidth, 14))
                cols.append((columnWidth, item.label, labelWidth, item.value))
                contentWidth += columnWidth
            }
            columns.append(cols)
        }

        let pointSize = NSSize(
            width: max(16, contentWidth) + pad * 2,
            height: textHeight + 1.5 + maxHeight + pad * 2
        )

        // 菜单栏明暗可由壁纸/全屏空间决定,与应用的深浅色外观不一定相同。
        // 延迟到 NSStatusBarButton 真正绘制时再解析语义色,才能匹配当前菜单栏。
        let image = NSImage(size: pointSize, flipped: false) { _ in
            let outlineColor = NSColor.labelColor.withAlphaComponent(0.75)
            let resolvedLabel = NSColor.labelColor.usingColorSpace(.deviceRGB)
            let labelBrightness = resolvedLabel.map {
                ($0.redComponent + $0.greenComponent + $0.blueComponent) / 3
            } ?? 0
            let trackRGB = QuotaPalette.trackRGB(
                theme: theme,
                darkAppearance: labelBrightness > 0.5
            )
            let trackColor = NSColor(
                red: trackRGB.r / 255,
                green: trackRGB.g / 255,
                blue: trackRGB.b / 255,
                alpha: 1
            )
            let dividerColor = NSColor.labelColor.withAlphaComponent(0.35)
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.8)
            ]

            var x: CGFloat = pad
            for (groupIndex, cols) in columns.enumerated() {
                if groupIndex > 0 {
                    // 组间细分隔线
                    dividerColor.setFill()
                    NSBezierPath(
                        roundedRect: NSRect(x: x + groupGap / 2 - 0.5, y: textHeight + 1.5, width: 1, height: maxHeight - 2),
                        xRadius: 0.5,
                        yRadius: 0.5
                    ).fill()
                    x += groupGap
                }

                for col in cols {
                    let center = x + col.width / 2
                    let clamped = min(100, max(0, col.value))
                    let fillHeight = minHeight + (maxHeight - minHeight) * CGFloat(clamped) / 100
                    let barBottom = textHeight + 1.5

                    let track = NSBezierPath(
                        roundedRect: NSRect(x: center - barWidth / 2, y: barBottom, width: barWidth, height: maxHeight),
                        xRadius: barWidth / 2,
                        yRadius: barWidth / 2
                    )

                    trackColor.setFill()
                    track.fill()

                    let rgb = QuotaPalette.rgb(remainingPercent: clamped, theme: theme)
                    NSColor(red: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255, alpha: 1).setFill()
                    NSBezierPath(
                        roundedRect: NSRect(x: center - barWidth / 2, y: barBottom, width: barWidth, height: fillHeight),
                        xRadius: barWidth / 2,
                        yRadius: barWidth / 2
                    ).fill()

                    outlineColor.setStroke()
                    track.lineWidth = 0.75
                    track.stroke()

                    if !col.label.isEmpty {
                        NSAttributedString(string: col.label, attributes: textAttrs)
                            .draw(at: NSPoint(x: center - col.labelWidth / 2, y: 0.5))
                    }

                    x += col.width
                }
            }

            return true
        }
        image.cacheMode = .never
        image.isTemplate = false
        return image
    }

}

private final class MainAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenuLocalization.apply()
        DispatchQueue.main.async {
            MainMenuLocalization.apply()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainMenuLocalization.apply()
    }
}

private enum MainMenuLocalization {
    private static let appName = "XanaTokenMonitor"

    private static let translations: [String: String] = [
        "File": "文件",
        "Edit": "编辑",
        "View": "显示",
        "Window": "窗口",
        "Help": "帮助",
        "About": "关于",
        "Services": "服务",
        "Hide": "隐藏",
        "Hide Others": "隐藏其他",
        "Show All": "全部显示",
        "Quit": "退出",
        "Undo": "撤销",
        "Redo": "重做",
        "Cut": "剪切",
        "Copy": "拷贝",
        "Paste": "粘贴",
        "Paste and Match Style": "粘贴并匹配样式",
        "Delete": "删除",
        "Select All": "全选",
        "Find": "查找",
        "Spelling and Grammar": "拼写和语法",
        "Substitutions": "替换",
        "Transformations": "转换",
        "Speech": "语音",
        "Start Speaking": "开始朗读",
        "Stop Speaking": "停止朗读",
        "Enter Full Screen": "进入全屏",
        "Exit Full Screen": "退出全屏",
        "Minimize": "最小化",
        "Zoom": "缩放",
        "Bring All to Front": "将全部置于最前",
        "Show Tab Bar": "显示标签页栏",
        "Show All Tabs": "显示所有标签页",
        "Close Window": "关闭窗口",
        "Close": "关闭",
        "Next Window": "下一个窗口",
        "Previous Window": "上一个窗口",
        "Show Toolbar": "显示工具栏",
        "Hide Toolbar": "隐藏工具栏",
        "Customize Toolbar…": "自定义工具栏…",
        "Settings…": "设置…",
        "Preferences…": "设置…"
    ]

    static func apply() {
        guard let mainMenu = NSApp.mainMenu else { return }

        guard let appMenuItem = mainMenu.items.first else { return }
        let editMenuItem = mainMenu.items.first {
            $0.title == "Edit" || $0.title == "编辑"
        }

        // 这是一个菜单栏工具和单窗口设置页,保留应用菜单与编辑菜单即可。
        // 编辑菜单仍然服务于设置页里的文本框,其余系统菜单没有实际内容。
        let itemsToKeep = [appMenuItem, editMenuItem].compactMap { $0 }
        for item in mainMenu.items where !itemsToKeep.contains(where: { $0 === item }) {
            mainMenu.removeItem(item)
        }

        appMenuItem.title = appName
        if let submenu = appMenuItem.submenu {
            localize(submenu)
        }

        if let editMenuItem {
            editMenuItem.title = "编辑"
            if let submenu = editMenuItem.submenu {
                localize(submenu)
            }
        }
    }

    private static func localize(_ menu: NSMenu) {
        for item in menu.items {
            item.title = localizedItemTitle(item.title)
            if let submenu = item.submenu {
                localize(submenu)
            }
        }
    }

    private static func localizedItemTitle(_ title: String) -> String {
        if let translation = translations[title] {
            return translation
        }

        if title.hasPrefix("About ") {
            return "关于 \(appName)"
        }
        if title.hasPrefix("Hide ") {
            return "隐藏 \(appName)"
        }
        if title.hasPrefix("Quit ") {
            return "退出 \(appName)"
        }
        return title
    }
}

/// 主窗口生命周期:窗口挂载时同步接管;首次挂载立即隐藏(纯菜单栏模式),
/// 之后每次新窗口出现都恢复常规模式并前置。
struct MainWindowLifecycle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DockIconSync())
            .onAppear {
                MainMenuLocalization.apply()
            }
            .onOpenURL { _ in
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

private struct DockIconSync: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = DockIconSyncView()
        view.onAttachedToWindow = { window in
            context.coordinator.attach(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    final class Coordinator {
        private weak var attachedWindow: NSWindow?
        private var closeObserver: NSObjectProtocol?

        func attach(_ window: NSWindow) {
            guard attachedWindow !== window else { return }
            attachedWindow = window
            MainWindowTracker.window = window
            observeClose(of: window)

            if MainWindowTracker.didHideInitialWindow {
                MainWindowTracker.show(window)
            } else {
                MainWindowTracker.hideForLaunch(window)
            }
        }

        private func observeClose(of window: NSWindow) {
            guard closeObserver == nil else { return }
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    NSApp.setActivationPolicy(.accessory)
                    self?.closeObserver = nil
                }
            }
        }

        deinit {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
        }
    }
}

private final class DockIconSyncView: NSView {
    var onAttachedToWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onAttachedToWindow?(window)
        }
    }
}
