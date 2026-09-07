import SwiftUI
import XanaTokenMonitorKit

@main
struct XanaTokenMonitorMacOSApp: App {
    @State private var providerManager = ProviderManager()
    @AppStorage(QuotaColorTheme.storageKey) private var quotaColorThemeRawValue = QuotaColorTheme.classic.rawValue

    var body: some Scene {
        WindowGroup {
            ProviderListView(providerManager: providerManager)
                .frame(minWidth: 420, minHeight: 300)
                .modifier(MainWindowLifecycle())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 520, height: 380)
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

/// 主窗口生命周期:窗口挂载时同步接管;首次挂载立即隐藏(纯菜单栏模式),
/// 之后每次新窗口出现都恢复常规模式并前置。
struct MainWindowLifecycle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DockIconSync())
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
