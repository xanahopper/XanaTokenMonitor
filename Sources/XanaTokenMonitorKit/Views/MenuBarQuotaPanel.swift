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
    @State private var hoveredProviderID: UUID?
    @State private var menuWindow: NSWindow?
    @State private var menuContentFrame: NSRect?
    @State private var historyRange: QuotaHistoryRange = .day

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
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                hoveredProviderID == provider.id
                                    ? Color.accentColor.opacity(0.13)
                                    : Color.clear
                            )
                    )
                    .onHover { isHovering in
                        if isHovering {
                            showDetail(for: provider)
                        }
                    }

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
                refreshButton {
                    Task { await providerManager.fetchAllBalances() }
                }
                Spacer()
                controlButton("power", help: "退出") {
                    NSApp.terminate(nil)
                }
                Spacer()
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    hideDetail()
                }
            }
        }
        .padding(10)
        .frame(width: 272)
        .background(
            MenuBarWindowAccessor { window, contentFrame in
                menuWindow = window
                menuContentFrame = contentFrame
                if let provider = providerManager.providers.first(where: { $0.id == hoveredProviderID }) {
                    showDetail(for: provider)
                }
            }
        )
        .task {
            if providerManager.shouldRefreshBalances() {
                await providerManager.fetchAllBalances()
            }
        }
        .onAppear {
            hideDetail()
        }
        .onDisappear {
            hideDetail()
        }
    }

    private func showDetail(for provider: any ModelProvider) {
        hoveredProviderID = provider.id
        guard let menuWindow, let menuContentFrame else { return }
        QuotaDetailPanelController.shared.show(
            content: AnyView(historyPanel(provider: provider)),
            relativeTo: menuWindow,
            alignedTo: menuContentFrame
        )
    }

    private func hideDetail() {
        hoveredProviderID = nil
        QuotaDetailPanelController.shared.hide()
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

                Spacer(minLength: 4)

                if providerManager.refreshingProviderIDs.contains(provider.id) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                        .frame(width: 12, height: 12)
                        .help("正在刷新")
                } else if let error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                        .help("刷新失败：\(error.localizedDescription)")
                }
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

    private func historyPanel(provider: any ModelProvider) -> some View {
        let allSamples = providerManager.quotaHistory[provider.id] ?? []
        let now = Date()
        let historyInterval = historyRange.interval(containing: now)
        let samples = allSamples.filter { historyInterval.contains($0.timestamp) }
        let quotas = providerManager.balances[provider.id].map(QuotaDisplay.quotas(for:)) ?? []

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if let brand = ProviderIcon.brandImage(for: provider) {
                    brand.resizable().scaledToFit()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: ProviderIcon.symbolName(for: provider))
                        .font(.system(size: 13))
                        .foregroundColor(ProviderIcon.color(for: provider))
                        .frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(providerManager.providerNames[provider.id] ?? provider.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("当前额度与\(historyRange.subtitle)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 2) {
                    ForEach(QuotaHistoryRange.allCases) { range in
                        Button {
                            historyRange = range
                        } label: {
                            Text(range.title)
                                .font(.system(size: 9, weight: historyRange == range ? .semibold : .regular))
                                .foregroundColor(historyRange == range ? .primary : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(historyRange == range ? Color.secondary.opacity(0.18) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                )
            }

            Divider()

            if quotas.isEmpty {
                Text("暂无可记录的百分比额度")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
            } else {
                VStack(spacing: 8) {
                    ForEach(quotas) { quota in
                        historyQuotaRow(
                            quota,
                            samples: samples,
                            historyInterval: historyInterval,
                            range: historyRange
                        )
                    }
                }
            }

            if let latest = samples.last {
                Text("共 \(samples.count) 次 · \(QuotaDisplay.relativeUpdateText(latest.timestamp))更新")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            } else {
                Text("正在积累记录")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(width: 280, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.secondary.opacity(0.22), lineWidth: 0.5)
        )
    }

    private func historyQuotaRow(
        _ quota: QuotaDisplay.QuotaInfo,
        samples: [QuotaHistorySample],
        historyInterval: DateInterval,
        range: QuotaHistoryRange
    ) -> some View {
        let points = samples.compactMap { sample -> (Date, Double)? in
            guard let value = sample.quotas.first(where: { $0.index == quota.index }) else { return nil }
            return (sample.timestamp, value.remainingPercent)
        }

        return VStack(alignment: .leading, spacing: 6) {
            if let remaining = quota.remainingPercent {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(quota.name)
                        .font(.system(size: 12, weight: .semibold))

                    Spacer()

                    Text("\(Int(remaining.rounded()))%")
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundColor(.primary)
                }

                QuotaBar(
                    remainingPercent: remaining,
                    height: 7,
                    marker: QuotaDisplay.timeMarker(quota),
                    animatesChanges: false
                )

                HStack(spacing: 5) {
                    if let resetDate = quota.resetDate {
                        Text("重置 \(QuotaDisplay.resetText(resetDate, quotaName: quota.name))")
                        Spacer(minLength: 4)
                        Text("\(QuotaDisplay.countdownText(resetDate))后")
                    } else {
                        Text("未提供重置时间")
                    }
                }
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            }

            HStack {
                Text(range.trendTitle)
                Spacer()
                Text("\(points.count) 个采样")
            }
            .font(.system(size: 9))
            .foregroundColor(.secondary)

            QuotaHistorySparkline(
                points: points,
                startDate: historyInterval.start,
                endDate: historyInterval.end
            )
                .frame(height: 58)

            HStack(spacing: 0) {
                Text(range.axisLabels(for: historyInterval).start)
                Spacer()
                Text(range.axisLabels(for: historyInterval).middle)
                Spacer()
                Text(range.axisLabels(for: historyInterval).end)
            }
            .font(.system(size: 8))
            .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.secondary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
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

    private func refreshButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RefreshFeedbackIcon(
                isRefreshing: providerManager.isRefreshing,
                result: providerManager.lastRefreshResult,
                size: 10
            )
            .frame(width: 38, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!providerManager.isRefreshing)
        .help(refreshHelp)
        .accessibilityLabel(refreshHelp)
    }

    private var refreshHelp: String {
        if providerManager.isRefreshing { return "正在刷新全部提供方" }
        switch providerManager.lastRefreshResult {
        case .none: return "刷新全部"
        case .success: return "刷新完成"
        case .partialFailure: return "部分提供方刷新失败"
        case .failure: return "刷新失败"
        }
    }
}

private enum QuotaHistoryRange: String, CaseIterable, Identifiable {
    case day
    case week

    var id: Self { self }
    var title: String { self == .day ? "当天" : "当周" }
    var subtitle: String { self == .day ? "当天趋势" : "当周趋势" }
    var trendTitle: String { self == .day ? "当天趋势" : "当周趋势" }

    func interval(containing date: Date, calendar: Calendar = .autoupdatingCurrent) -> DateInterval {
        switch self {
        case .day:
            return calendar.dateInterval(of: .day, for: date)
                ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 60 * 60)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)
                ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 24 * 60 * 60)
        }
    }

    func axisLabels(for interval: DateInterval) -> (start: String, middle: String, end: String) {
        switch self {
        case .day:
            return ("00:00", "12:00", "24:00")
        case .week:
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate("Md")
            return (
                formatter.string(from: interval.start),
                formatter.string(from: interval.start.addingTimeInterval(interval.duration / 2)),
                formatter.string(from: interval.end)
            )
        }
    }
}

@MainActor
private final class QuotaDetailPanelController {
    static let shared = QuotaDetailPanelController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private weak var parentWindow: NSWindow?

    func show(content: AnyView, relativeTo parent: NSWindow, alignedTo anchor: NSRect) {
        let panel = panel ?? makePanel()
        let hostingView = hostingView ?? NSHostingView(rootView: content)
        hostingView.rootView = content
        panel.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let size = NSSize(width: 280, height: ceil(max(1, fittingSize.height)))
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)

        if parentWindow !== parent {
            if let parentWindow, let panel = self.panel {
                parentWindow.removeChildWindow(panel)
            }
            parent.addChildWindow(panel, ordered: .above)
            parentWindow = parent
        }

        position(panel, size: size, relativeTo: parent, alignedTo: anchor)
        panel.orderFront(nil)
        self.panel = panel
        self.hostingView = hostingView
    }

    func hide() {
        if let parentWindow, let panel {
            parentWindow.removeChildWindow(panel)
        }
        panel?.orderOut(nil)
        parentWindow = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 1),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.level = .popUpMenu
        return panel
    }

    private func position(
        _ panel: NSPanel,
        size: NSSize,
        relativeTo parent: NSWindow,
        alignedTo anchor: NSRect
    ) {
        let visibleFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
        let gap: CGFloat = 6
        var origin = NSPoint(
            x: anchor.maxX + gap,
            y: anchor.maxY - size.height
        )

        if origin.x + size.width > visibleFrame.maxX {
            origin.x = anchor.minX - size.width - gap
        }
        origin.x = min(max(origin.x, visibleFrame.minX + gap), visibleFrame.maxX - size.width - gap)
        origin.y = min(max(origin.y, visibleFrame.minY + gap), visibleFrame.maxY - size.height - gap)
        panel.setFrameOrigin(origin)
    }
}

private struct MenuBarWindowAccessor: NSViewRepresentable {
    let resolve: (NSWindow?, NSRect?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { resolveWindow(for: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { resolveWindow(for: nsView) }
    }

    private func resolveWindow(for view: NSView) {
        guard let window = view.window else {
            resolve(nil, nil)
            return
        }
        let frameInWindow = view.convert(view.bounds, to: nil)
        resolve(window, window.convertToScreen(frameInWindow))
    }
}

private struct QuotaHistorySparkline: View {
    let points: [(Date, Double)]
    let startDate: Date
    let endDate: Date
    @State private var hoverX: CGFloat?
    @AppStorage(QuotaColorTheme.storageKey) private var selectedThemeRawValue = QuotaColorTheme.classic.rawValue

    var body: some View {
        GeometryReader { geometry in
            let orderedPoints = points.sorted { $0.0 < $1.0 }
            let selectedPoint = hoverX.flatMap {
                nearestPoint(to: $0, width: geometry.size.width, in: orderedPoints)
            }

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    guard let first = orderedPoints.first, let last = orderedPoints.last else { return }

                    if orderedPoints.count == 1 {
                        let center = position(first, in: size)
                        context.fill(
                            Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)),
                            with: .color(QuotaPalette.remainingColor(
                                remainingPercent: first.1,
                                theme: selectedTheme
                            ))
                        )
                    } else {
                        var path = Path()
                        path.move(to: position(first, in: size))
                        for point in orderedPoints.dropFirst() {
                            path.addLine(to: position(point, in: size))
                        }
                        context.stroke(
                            path,
                            with: .color(QuotaPalette.remainingColor(
                                remainingPercent: last.1,
                                theme: selectedTheme
                            )),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                    }

                    if let selectedPoint {
                        let selectedPosition = position(selectedPoint, in: size)
                        var guide = Path()
                        guide.move(to: CGPoint(x: selectedPosition.x, y: 0))
                        guide.addLine(to: CGPoint(x: selectedPosition.x, y: size.height))
                        context.stroke(
                            guide,
                            with: .color(Color.secondary.opacity(0.55)),
                            style: StrokeStyle(lineWidth: 0.75, dash: [2, 2])
                        )

                        let marker = Path(ellipseIn: CGRect(
                            x: selectedPosition.x - 3,
                            y: selectedPosition.y - 3,
                            width: 6,
                            height: 6
                        ))
                        context.fill(marker, with: .color(Color(nsColor: .controlBackgroundColor)))
                        context.stroke(
                            marker,
                            with: .color(QuotaPalette.remainingColor(
                                remainingPercent: selectedPoint.1,
                                theme: selectedTheme
                            )),
                            lineWidth: 1.5
                        )
                    }
                }

                if let selectedPoint {
                    Text(tooltipText(for: selectedPoint))
                        .font(.system(size: 8, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.black.opacity(0.78))
                        )
                        .fixedSize()
                        .position(
                            x: tooltipX(for: selectedPoint, width: geometry.size.width),
                            y: 10
                        )
                        .allowsHitTesting(false)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverX = location.x
                        case .ended:
                            hoverX = nil
                        }
                    }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var selectedTheme: QuotaColorTheme {
        QuotaColorTheme(rawValue: selectedThemeRawValue) ?? .classic
    }

    private func position(_ point: (Date, Double), in size: CGSize) -> CGPoint {
        let horizontalInset: CGFloat = 3
        let verticalInset: CGFloat = 3
        let timeSpan = max(1, endDate.timeIntervalSince(startDate))
        let timeProgress = min(
            1,
            max(0, point.0.timeIntervalSince(startDate) / timeSpan)
        )
        let plotWidth = max(0, size.width - horizontalInset * 2)
        let plotHeight = max(0, size.height - verticalInset * 2)
        let percent = min(100, max(0, point.1))
        return CGPoint(
            x: horizontalInset + CGFloat(timeProgress) * plotWidth,
            y: verticalInset + (1 - percent / 100) * plotHeight
        )
    }

    private func nearestPoint(
        to x: CGFloat,
        width: CGFloat,
        in orderedPoints: [(Date, Double)]
    ) -> (Date, Double)? {
        guard !orderedPoints.isEmpty else { return nil }
        let horizontalInset: CGFloat = 3
        let plotWidth = max(1, width - horizontalInset * 2)
        let progress = Double(min(1, max(0, (x - horizontalInset) / plotWidth)))
        let targetDate = startDate.addingTimeInterval(endDate.timeIntervalSince(startDate) * progress)
        return orderedPoints.min {
            abs($0.0.timeIntervalSince(targetDate)) < abs($1.0.timeIntervalSince(targetDate))
        }
    }

    private func tooltipX(for point: (Date, Double), width: CGFloat) -> CGFloat {
        let pointX = position(point, in: CGSize(width: width, height: 58)).x
        return min(max(pointX, 48), max(48, width - 48))
    }

    private func tooltipText(for point: (Date, Double)) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MdHm")
        return "\(Int(point.1.rounded()))% · \(formatter.string(from: point.0))"
    }
}
#endif
