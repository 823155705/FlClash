import AppKit
import SwiftUI

struct TrayPanelView: View {
    @ObservedObject var store: TrayPanelStore
    let onAction: (String, [String: Any]) -> Void
    var onContentHeight: ((CGFloat) -> Void)? = nil

    @Namespace private var modePillNamespace

    private var state: TrayPanelState { store.state }
    private var theme: TrayPanelTheme { state.theme }
    private var labels: TrayPanelLabels { state.labels }
    private var shortcuts: TrayPanelShortcuts { state.shortcuts }

    private var filteredGroups: [(group: TrayPanelGroup, proxies: [TrayPanelProxy], forceExpand: Bool)] {
        let query = store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return state.groups.map { ($0, $0.proxies, false) }
        }
        return state.groups.compactMap { group in
            let groupMatches = group.name.lowercased().contains(query)
            let matchingProxies = group.proxies.filter {
                $0.name.lowercased().contains(query) || $0.type.lowercased().contains(query)
            }
            if !matchingProxies.isEmpty {
                return (group, matchingProxies, true)
            }
            if groupMatches {
                return (group, group.proxies, false)
            }
            return nil
        }
    }

    private var maxGroupsScrollHeight: CGFloat {
        let chromeOverhead: CGFloat = store.isSearchVisible ? 316 : 280
        return max(110, store.maxPanelHeight - chromeOverhead)
    }

    private var statusDotColor: Color {
        if !state.isStart {
            return theme.color(theme.onSurfaceVariant).opacity(0.45)
        }
        return state.suspended ? theme.color(theme.warning) : theme.color(theme.success)
    }

    private enum PanelLayout {
        static let panelWidth: CGFloat = 348
        static let outerPadding: CGFloat = 14
        static let contentWidth: CGFloat = panelWidth - outerPadding * 2
        static let scrollbarGutterWidth: CGFloat = outerPadding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerSection
                .padding(.horizontal, PanelLayout.outerPadding)
            outboundModeSection
                .padding(.horizontal, PanelLayout.outerPadding)
            quickTogglesSection
                .padding(.horizontal, PanelLayout.outerPadding)
            if !state.groups.isEmpty {
                proxiesSection
            }
            Rectangle()
                .fill(theme.color(theme.hairline))
                .frame(height: 0.75)
                .padding(.horizontal, PanelLayout.outerPadding)
            footerSection
                .padding(.horizontal, PanelLayout.outerPadding)
        }
        .padding(.vertical, PanelLayout.outerPadding)
        .frame(width: PanelLayout.panelWidth)
        .overlay(
            GeometryReader { geo in
                Color.clear
                    .preference(key: TrayPanelContentHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(TrayPanelContentHeightKey.self) { height in
            onContentHeight?(height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusDotColor.opacity(0.22))
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(labels.appName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.color(theme.onSurface))
                        .lineLimit(1)

                    if state.safeMode {
                        Text(labels.safeMode)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(theme.color(theme.warning))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(theme.color(theme.warning).opacity(0.14))
                            )
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .semibold))
                        Text(store.traffic.up)
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text(store.traffic.down)
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    }
                }
                .foregroundColor(theme.color(theme.onSurfaceVariant))
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                PanelIconButton(
                    systemName: state.isStart ? "pause.fill" : "play.fill",
                    tooltip: formatTooltip(
                        state.isStart ? labels.stop : labels.start,
                        shortcut: shortcuts.toggleRunning
                    ),
                    background: state.isStart
                        ? theme.color(theme.primary).opacity(0.16)
                        : theme.color(theme.cardBg),
                    foreground: state.isStart
                        ? theme.color(theme.primary)
                        : theme.color(theme.onSurface),
                    hoverBackground: state.isStart
                        ? theme.color(theme.primary).opacity(0.24)
                        : theme.color(theme.blockBg)
                ) {
                    onAction("toggleRunning", [:])
                }

                PanelIconButton(
                    systemName: "macwindow",
                    tooltip: formatTooltip(labels.showWindow, shortcut: shortcuts.showWindow),
                    background: theme.color(theme.cardBg),
                    foreground: theme.color(theme.onSurfaceVariant),
                    hoverBackground: theme.color(theme.blockBg)
                ) {
                    onAction("showWindow", [:])
                }

                PanelIconButton(
                    systemName: "power",
                    tooltip: formatTooltip(labels.exit, shortcut: shortcuts.exit),
                    background: theme.color(theme.cardBg),
                    foreground: theme.color(theme.onSurfaceVariant),
                    hoverBackground: theme.color(theme.error).opacity(0.16),
                    hoverForeground: theme.color(theme.error)
                ) {
                    onAction("quit", [:])
                }
            }
        }
    }

    private var outboundModeSection: some View {
        HStack(spacing: 4) {
            modeSegment(
                key: "rule",
                title: labels.modeRule,
                icon: "point.topleft.down.curvedto.point.bottomright.up",
                shortcut: shortcuts.modeRule
            )
            modeSegment(
                key: "global",
                title: labels.modeGlobal,
                icon: "globe",
                shortcut: shortcuts.modeGlobal
            )
            modeSegment(
                key: "direct",
                title: labels.modeDirect,
                icon: "paperplane.fill",
                shortcut: shortcuts.modeDirect
            )
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(theme.color(theme.insetBg))
        )
        .animation(.easeInOut(duration: 0.18), value: state.mode)
    }

    private func modeSegment(
        key: String,
        title: String,
        icon: String,
        shortcut: String
    ) -> some View {
        let isActive = state.mode == key
        return Button {
            if !isActive {
                onAction("setMode", ["mode": key])
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6.5)
            .foregroundColor(
                isActive ? theme.color(theme.onPrimary) : theme.color(theme.onSurfaceVariant)
            )
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.color(theme.primary))
                        .matchedGeometryEffect(id: "modeActivePill", in: modePillNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(formatTooltip(title, shortcut: shortcut))
    }

    private var quickTogglesSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                QuickToggleCard(
                    icon: "shield.lefthalf.filled",
                    title: labels.tun,
                    shortcut: shortcuts.tun,
                    isActive: state.tunEnable,
                    isEnabled: state.isStart,
                    theme: theme
                ) {
                    onAction("toggleTun", [:])
                }

                QuickToggleCard(
                    icon: "network",
                    title: labels.systemProxy,
                    shortcut: shortcuts.systemProxy,
                    isActive: state.systemProxy,
                    isEnabled: state.isStart,
                    theme: theme
                ) {
                    onAction("toggleSystemProxy", [:])
                }
            }

            HStack(spacing: 6) {
                CompactPillToggle(
                    icon: "speedometer",
                    title: labels.speedStatistics,
                    isActive: state.showTrayTitle,
                    theme: theme
                ) {
                    onAction("toggleSpeedStatistics", [:])
                }

                CompactPillToggle(
                    icon: "circle.lefthalf.filled",
                    title: labels.monochromeIcon,
                    isActive: state.monochromeTrayIcon,
                    theme: theme
                ) {
                    onAction("toggleMonochromeIcon", [:])
                }

                CompactPillToggle(
                    icon: "sunrise.fill",
                    title: labels.autoLaunch,
                    isActive: state.autoLaunch,
                    theme: theme
                ) {
                    onAction("toggleAutoLaunch", [:])
                }
            }
        }
    }

    private var proxiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(labels.proxies)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.color(theme.onSurfaceVariant))

                Text(verbatim: "\(filteredGroups.count)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundColor(theme.color(theme.onSurfaceVariant))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(theme.color(theme.insetBg))
                    )

                Spacer()

                PanelIconButton(
                    systemName: "magnifyingglass",
                    tooltip: labels.search,
                    size: 24,
                    cornerRadius: 8,
                    iconSize: 11,
                    background: store.isSearchVisible
                        ? theme.color(theme.primary).opacity(0.16)
                        : theme.color(theme.cardBg),
                    foreground: store.isSearchVisible
                        ? theme.color(theme.primary)
                        : theme.color(theme.onSurfaceVariant),
                    hoverBackground: store.isSearchVisible
                        ? theme.color(theme.primary).opacity(0.24)
                        : theme.color(theme.blockBg)
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        store.toggleSearch()
                    }
                }

                Button {
                    if !state.testingAll {
                        onAction("testAllDelays", [:])
                    }
                } label: {
                    Group {
                        if state.testingAll {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.68)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                    }
                    .frame(width: 24, height: 24)
                    .foregroundColor(theme.color(theme.onSurfaceVariant))
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.color(theme.cardBg))
                    )
                }
                .buttonStyle(.plain)
                .help(formatTooltip(labels.testAllDelays, shortcut: shortcuts.testAllDelays))
            }
            .padding(.horizontal, PanelLayout.outerPadding)

            if store.isSearchVisible {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(theme.color(theme.onSurfaceVariant))

                    TextField(labels.search, text: $store.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(theme.color(theme.onSurface))

                    if !store.searchQuery.isEmpty {
                        Button {
                            store.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(theme.color(theme.onSurfaceVariant))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.color(theme.insetBg))
                )
                .padding(.horizontal, PanelLayout.outerPadding)
            }

            if filteredGroups.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18))
                        .foregroundColor(theme.color(theme.onSurfaceVariant).opacity(0.6))
                    Text(labels.noProxies)
                        .font(.system(size: 12))
                        .foregroundColor(theme.color(theme.onSurfaceVariant))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, PanelLayout.outerPadding)
            } else {
                FittingGroupsScrollView(
                    contentWidth: PanelLayout.contentWidth,
                    gutterWidth: PanelLayout.scrollbarGutterWidth,
                    maxHeight: maxGroupsScrollHeight,
                    thumbColor: theme.nsColor(theme.onSurfaceVariant)
                ) {
                    VStack(spacing: 8) {
                        ForEach(filteredGroups, id: \.group.id) { entry in
                            ProxyGroupCard(
                                group: entry.group,
                                proxies: entry.proxies,
                                isExpanded: entry.forceExpand || store.expandedGroupNames.contains(entry.group.name),
                                theme: theme,
                                labels: labels,
                                onToggleExpand: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        store.toggleGroup(entry.group.name)
                                    }
                                },
                                onTestDelay: {
                                    onAction("testGroupDelay", ["groupName": entry.group.name])
                                },
                                onSelectProxy: { proxyName in
                                    onAction(
                                        "selectProxy",
                                        ["groupName": entry.group.name, "proxyName": proxyName]
                                    )
                                }
                            )
                        }
                    }
                    .frame(width: PanelLayout.contentWidth, alignment: .top)
                }
                .padding(.leading, PanelLayout.outerPadding)
                .frame(width: PanelLayout.panelWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footerSection: some View {
        HStack(spacing: 8) {
            Button {
                store.triggerCopiedFeedback()
                onAction("copyEnv", [:])
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: store.copiedFeedback ? "checkmark" : "terminal")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(verbatim: "\(labels.copyEnvVar) :\(state.port)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .lineLimit(1)
                    if !shortcuts.copyEnv.isEmpty && !store.copiedFeedback {
                        ShortcutBadge(text: shortcuts.copyEnv, theme: theme, tinted: false)
                    }
                }
                .foregroundColor(
                    store.copiedFeedback
                        ? theme.color(theme.success)
                        : theme.color(theme.onSurfaceVariant)
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            store.copiedFeedback
                                ? theme.color(theme.success).opacity(0.16)
                                : theme.color(theme.cardBg)
                        )
                )
            }
            .buttonStyle(.plain)
            .help(formatTooltip(labels.copyEnvVar, shortcut: shortcuts.copyEnv))

            Spacer()

            Button {
                onAction("showWindow", [:])
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(labels.showWindow)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if !shortcuts.showWindow.isEmpty {
                        ShortcutBadge(text: shortcuts.showWindow, theme: theme, tinted: true)
                    }
                }
                .foregroundColor(theme.color(theme.primary))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.color(theme.primary).opacity(0.16))
                )
            }
            .buttonStyle(.plain)
            .help(formatTooltip(labels.showWindow, shortcut: shortcuts.showWindow))
        }
    }
}

private func formatTooltip(_ title: String, shortcut: String) -> String {
    shortcut.isEmpty ? title : "\(title)  \(shortcut)"
}

private struct ShortcutBadge: View {
    let text: String
    let theme: TrayPanelTheme
    let tinted: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
            .foregroundColor(
                tinted ? theme.color(theme.primary).opacity(0.85) : theme.color(theme.onSurfaceVariant)
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        tinted
                            ? theme.color(theme.primary).opacity(0.14)
                            : theme.color(theme.insetBg)
                    )
            )
            .lineLimit(1)
    }
}

private struct PanelIconButton: View {
    let systemName: String
    let tooltip: String
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 9
    var iconSize: CGFloat = 12
    let background: Color
    let foreground: Color
    let hoverBackground: Color
    var hoverForeground: Color?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(isHovered ? (hoverForeground ?? foreground) : foreground)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovered ? hoverBackground : background)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip)
    }
}

private struct QuickToggleCard: View {
    let icon: String
    let title: String
    let shortcut: String
    let isActive: Bool
    let isEnabled: Bool
    let theme: TrayPanelTheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            if isEnabled {
                action()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(
                        isActive ? theme.color(theme.primary) : theme.color(theme.onSurfaceVariant)
                    )
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                isActive
                                    ? theme.color(theme.primary).opacity(0.14)
                                    : theme.color(theme.blockBg)
                            )
                    )

                Text(title)
                    .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                    .foregroundColor(
                        isActive ? theme.color(theme.primary) : theme.color(theme.onSurfaceVariant)
                    )
                    .lineLimit(1)

                Spacer(minLength: 2)

                if !shortcut.isEmpty {
                    ShortcutBadge(text: shortcut, theme: theme, tinted: isActive)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isActive
                            ? theme.color(theme.primary).opacity(0.16)
                            : (isHovered && isEnabled
                                ? theme.color(theme.blockBg)
                                : theme.color(theme.cardBg))
                    )
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(formatTooltip(title, shortcut: shortcut))
    }
}

private struct CompactPillToggle: View {
    let icon: String
    let title: String
    let isActive: Bool
    let theme: TrayPanelTheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: isActive ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(
                isActive ? theme.color(theme.primary) : theme.color(theme.onSurfaceVariant)
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isActive
                            ? theme.color(theme.primary).opacity(0.16)
                            : (isHovered ? theme.color(theme.blockBg) : theme.color(theme.cardBg))
                    )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(title)
    }
}

private struct ProxyGroupCard: View {
    let group: TrayPanelGroup
    let proxies: [TrayPanelProxy]
    let isExpanded: Bool
    let theme: TrayPanelTheme
    let labels: TrayPanelLabels
    let onToggleExpand: () -> Void
    let onTestDelay: () -> Void
    let onSelectProxy: (String) -> Void

    @State private var isHeaderHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(group.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(theme.color(theme.onSurface))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if !group.type.isEmpty {
                            Text(group.type)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(theme.color(theme.onSurfaceVariant))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(theme.color(theme.insetBg))
                                )
                        }
                    }

                    Text(group.selectedProxyName.isEmpty ? "-" : group.selectedProxyName)
                        .font(.system(size: 11))
                        .foregroundColor(theme.color(theme.onSurfaceVariant))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                DelayBadge(
                    delay: group.selectedDelay,
                    testing: group.testing,
                    theme: theme,
                    timeoutLabel: labels.timeout,
                    failedLabel: labels.delayFailed
                )

                Button {
                    if !group.testing {
                        onTestDelay()
                    }
                } label: {
                    Group {
                        if group.testing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.62)
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(theme.color(theme.onSurfaceVariant))
                        }
                    }
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(theme.color(theme.blockBg))
                    )
                }
                .buttonStyle(.plain)
                .help(labels.delayTest)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.color(theme.onSurfaceVariant))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.18), value: isExpanded)
                    .frame(width: 14)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggleExpand)
            .onHover { hovering in
                isHeaderHovered = hovering
            }

            if isExpanded {
                let columns = [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                ]
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(proxies) { proxy in
                        ProxyNodeTile(
                            proxy: proxy,
                            theme: theme,
                            timeoutLabel: labels.timeout,
                            failedLabel: labels.delayFailed
                        ) {
                            onSelectProxy(proxy.name)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isHeaderHovered && !isExpanded
                        ? theme.color(theme.blockBg)
                        : theme.color(theme.cardBg)
                )
        )
    }
}

private struct ProxyNodeTile: View {
    let proxy: TrayPanelProxy
    let theme: TrayPanelTheme
    let timeoutLabel: String
    let failedLabel: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(proxy.name)
                        .font(.system(size: 11.5, weight: proxy.selected ? .semibold : .medium))
                        .foregroundColor(
                            proxy.selected
                                ? theme.color(theme.primary)
                                : theme.color(theme.onSurface)
                        )
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if proxy.selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(theme.color(theme.primary))
                    }
                }

                HStack(spacing: 4) {
                    Text(proxy.type)
                        .font(.system(size: 9.5))
                        .foregroundColor(theme.color(theme.onSurfaceVariant))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    DelayBadge(
                        delay: proxy.delay,
                        testing: proxy.testing,
                        theme: theme,
                        timeoutLabel: timeoutLabel,
                        failedLabel: failedLabel,
                        compact: true
                    )
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        proxy.selected
                            ? theme.color(theme.primary).opacity(0.14)
                            : (isHovered
                                ? theme.color(theme.insetBg)
                                : theme.color(theme.blockBg))
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(proxy.name)
    }
}

private struct DelayBadge: View {
    let delay: Int?
    let testing: Bool
    let theme: TrayPanelTheme
    let timeoutLabel: String
    let failedLabel: String
    var compact: Bool = false

    var body: some View {
        if testing {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(compact ? 0.55 : 0.62)
                .frame(width: 14, height: 14)
        } else if let delay = delay {
            let color = delayColor(for: delay)
            let text = delayText(for: delay)
            Text(text)
                .font(.system(size: compact ? 9.5 : 10, weight: .semibold).monospacedDigit())
                .foregroundColor(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, compact ? 4 : 6)
                .padding(.vertical, 1.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(color.opacity(0.14))
                )
        }
    }

    private func delayText(for value: Int) -> String {
        if value == -1 {
            return timeoutLabel
        }
        if value < -1 {
            return failedLabel
        }
        return "\(value) ms"
    }

    private func delayColor(for value: Int) -> Color {
        if value < 0 {
            return theme.color(theme.error)
        }
        if value < 600 {
            return theme.color(theme.success)
        }
        return theme.color(theme.warning)
    }
}

private struct TrayPanelContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 210
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private final class FlippedGroupsDocumentView: NSView {
    var onLayout: (() -> Void)?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        onLayout?()
    }
}

private final class GroupsScrollbarView: NSView {
    private static let trackInsetY: CGFloat = 6
    private static let minThumbHeight: CGFloat = 24
    private static let minOverscrollThumbHeight: CGFloat = 18
    private static let idleThumbWidth: CGFloat = 4
    private static let activeThumbWidth: CGFloat = 6

    var thumbColor: NSColor {
        didSet {
            applyColors()
        }
    }
    var onScrollTo: ((CGFloat) -> Void)?
    var onScrollWheel: ((NSEvent) -> Void)?

    private let trackLayer = CALayer()
    private let thumbLayer = CALayer()
    private var trackingAreaRef: NSTrackingArea?
    private var viewportHeight: CGFloat = 0
    private var contentHeight: CGFloat = 0
    private var scrollOffset: CGFloat = 0
    private var isHovered = false
    private var isDragging = false
    private var isScrolling = false
    private var dragStartY: CGFloat = 0
    private var dragStartOffset: CGFloat = 0
    private var scrollFadeWorkItem: DispatchWorkItem?

    override var isFlipped: Bool { true }

    init(thumbColor: NSColor) {
        self.thumbColor = thumbColor
        super.init(frame: .zero)
        wantsLayer = true
        ensureLayers()
        applyColors()
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        scrollFadeWorkItem?.cancel()
    }

    private var scrollableDistance: CGFloat {
        max(0, contentHeight - viewportHeight)
    }

    private var isScrollable: Bool {
        scrollableDistance > 0.5 && viewportHeight > 1
    }

    private func ensureLayers() {
        wantsLayer = true
        guard let rootLayer = layer else {
            return
        }
        rootLayer.masksToBounds = false
        if trackLayer.superlayer == nil {
            trackLayer.opacity = 0
            rootLayer.addSublayer(trackLayer)
        }
        if thumbLayer.superlayer == nil {
            thumbLayer.opacity = 0
            rootLayer.addSublayer(thumbLayer)
        }
    }

    private func applyColors() {
        let base = thumbColor.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.backgroundColor = base
        thumbLayer.backgroundColor = base
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func layout() {
        super.layout()
        ensureLayers()
        updateThumbLayout(animated: false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isScrollable else {
            return nil
        }
        return super.hitTest(point)
    }

    func updateMetrics(viewportHeight: CGFloat, contentHeight: CGFloat, scrollOffset: CGFloat) {
        self.viewportHeight = viewportHeight
        self.contentHeight = contentHeight
        self.scrollOffset = scrollOffset

        let shouldShow = isScrollable
        isHidden = !shouldShow
        if !shouldShow {
            scrollFadeWorkItem?.cancel()
            isHovered = false
            isDragging = false
            isScrolling = false
            updateAppearance(animated: false)
            return
        }

        ensureLayers()
        updateThumbLayout(animated: false)
        updateAppearance(animated: false)
    }

    func noteScrollActivity() {
        guard isScrollable else {
            return
        }
        scrollFadeWorkItem?.cancel()
        if !isScrolling {
            isScrolling = true
            updateAppearance(animated: true)
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else {
                return
            }
            self.isScrolling = false
            self.updateAppearance(animated: true)
        }
        scrollFadeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: workItem)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isScrollable else {
            return
        }
        isHovered = true
        updateThumbLayout(animated: true)
        updateAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isDragging {
            updateThumbLayout(animated: true)
            updateAppearance(animated: true)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isScrollable else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let metrics = computeThumbGeometry()
        let usableTrack = max(1, metrics.trackHeight - metrics.thumbHeight)
        isDragging = true

        if point.y >= metrics.thumbY - 4 && point.y <= metrics.thumbY + metrics.thumbHeight + 4 {
            dragStartY = point.y
            dragStartOffset = min(max(scrollOffset, 0), scrollableDistance)
        } else {
            let clampedTop = min(
                max(point.y - metrics.thumbHeight / 2, metrics.trackTop),
                metrics.trackTop + usableTrack
            )
            let targetOffset = ((clampedTop - metrics.trackTop) / usableTrack) * scrollableDistance
            dragStartY = point.y
            dragStartOffset = targetOffset
            onScrollTo?(targetOffset)
        }
        updateThumbLayout(animated: true)
        updateAppearance(animated: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, isScrollable else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let metrics = computeThumbGeometry()
        let usableTrack = max(1, metrics.trackHeight - metrics.thumbHeight)
        let deltaY = point.y - dragStartY
        let nextOffset = min(
            max(dragStartOffset + (deltaY / usableTrack) * scrollableDistance, 0),
            scrollableDistance
        )
        onScrollTo?(nextOffset)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else {
            return
        }
        isDragging = false
        let point = convert(event.locationInWindow, from: nil)
        isHovered = bounds.contains(point)
        updateThumbLayout(animated: true)
        updateAppearance(animated: true)
    }

    override func scrollWheel(with event: NSEvent) {
        onScrollWheel?(event)
    }

    private func computeThumbGeometry() -> (trackTop: CGFloat, trackHeight: CGFloat, thumbY: CGFloat, thumbHeight: CGFloat) {
        let trackTop = Self.trackInsetY
        let trackHeight = max(0, bounds.height - Self.trackInsetY * 2)
        guard trackHeight > 0, scrollableDistance > 0.5 else {
            return (trackTop, trackHeight, trackTop, 0)
        }
        let visibleRatio = min(1, viewportHeight / max(contentHeight, 1))
        let baseHeight = max(Self.minThumbHeight, min(trackHeight, trackHeight * visibleRatio))
        if scrollOffset < 0 {
            let thumbHeight = max(Self.minOverscrollThumbHeight, baseHeight - (-scrollOffset) * 0.45)
            return (trackTop, trackHeight, trackTop, thumbHeight)
        }
        if scrollOffset > scrollableDistance {
            let overscroll = scrollOffset - scrollableDistance
            let thumbHeight = max(Self.minOverscrollThumbHeight, baseHeight - overscroll * 0.45)
            return (trackTop, trackHeight, trackTop + trackHeight - thumbHeight, thumbHeight)
        }
        let progress = scrollOffset / scrollableDistance
        let thumbY = trackTop + progress * (trackHeight - baseHeight)
        return (trackTop, trackHeight, thumbY, baseHeight)
    }

    private func updateThumbLayout(animated: Bool) {
        guard let rootLayer = layer, isScrollable else {
            return
        }
        let metrics = computeThumbGeometry()
        let width = (isHovered || isDragging) ? Self.activeThumbWidth : Self.idleThumbWidth
        let thumbX = round((bounds.width - width) * 0.5 * 2) / 2
        let trackX = round((bounds.width - Self.activeThumbWidth) * 0.5 * 2) / 2

        let flipped = rootLayer.isGeometryFlipped
        let thumbFrameY = flipped ? metrics.thumbY : (bounds.height - metrics.thumbY - metrics.thumbHeight)
        let trackFrameY = flipped ? metrics.trackTop : (bounds.height - metrics.trackTop - metrics.trackHeight)

        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.14)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        trackLayer.frame = CGRect(
            x: trackX,
            y: trackFrameY,
            width: Self.activeThumbWidth,
            height: metrics.trackHeight
        )
        trackLayer.cornerRadius = Self.activeThumbWidth * 0.5
        thumbLayer.frame = CGRect(
            x: thumbX,
            y: thumbFrameY,
            width: width,
            height: metrics.thumbHeight
        )
        thumbLayer.cornerRadius = width * 0.5
        CATransaction.commit()
    }

    private func updateAppearance(animated: Bool) {
        let thumbOpacity: Float
        if !isScrollable {
            thumbOpacity = 0
        } else if isDragging {
            thumbOpacity = 0.72
        } else if isHovered {
            thumbOpacity = 0.56
        } else if isScrolling {
            thumbOpacity = 0.48
        } else {
            thumbOpacity = 0.26
        }
        let trackOpacity: Float = (isScrollable && (isHovered || isDragging)) ? 0.12 : 0

        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.16)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        thumbLayer.opacity = thumbOpacity
        trackLayer.opacity = trackOpacity
        CATransaction.commit()
    }
}

private final class BoundedGroupsScrollView<Content: View>: NSView {
    let scrollView = NSScrollView()
    let hostingView: NSHostingView<Content>
    private let documentContainer = FlippedGroupsDocumentView()
    private let scrollbarView: GroupsScrollbarView
    private let contentWidth: CGFloat
    private let gutterWidth: CGFloat
    private var boundsObserver: NSObjectProtocol?
    private var liveScrollObserver: NSObjectProtocol?
    private var lastObservedOffset: CGFloat = 0
    private var isSyncingDocument = false

    var maxHeight: CGFloat {
        didSet {
            if abs(oldValue - maxHeight) > 0.5 {
                invalidateIntrinsicContentSize()
            }
        }
    }

    init(
        rootView: Content,
        contentWidth: CGFloat,
        gutterWidth: CGFloat,
        maxHeight: CGFloat,
        thumbColor: NSColor
    ) {
        self.hostingView = NSHostingView(rootView: rootView)
        self.contentWidth = contentWidth
        self.gutterWidth = gutterWidth
        self.maxHeight = maxHeight
        self.scrollbarView = GroupsScrollbarView(thumbColor: thumbColor)
        super.init(frame: NSRect(x: 0, y: 0, width: contentWidth + gutterWidth, height: 44))

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 44)
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 14
        scrollView.layer?.cornerCurve = .continuous
        scrollView.layer?.masksToBounds = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        // Hide AppKit's scroller so legacy/overlay styles cannot clip or overlap cards;
        // scrollbarView renders in the outer margin gutter instead.
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.postsBoundsChangedNotifications = true

        documentContainer.translatesAutoresizingMaskIntoConstraints = true
        documentContainer.autoresizingMask = [.width]
        documentContainer.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 44)
        documentContainer.onLayout = { [weak self] in
            self?.handleDocumentLayout()
        }

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        documentContainer.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: documentContainer.topAnchor),
        ])
        scrollView.documentView = documentContainer

        scrollbarView.frame = NSRect(x: contentWidth, y: 0, width: gutterWidth, height: 44)
        scrollbarView.onScrollTo = { [weak self] offset in
            self?.scrollToOffset(offset)
        }
        scrollbarView.onScrollWheel = { [weak self] event in
            self?.scrollView.scrollWheel(with: event)
        }

        addSubview(scrollView)
        addSubview(scrollbarView)

        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.handleClipBoundsChanged()
        }
        liveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.syncScrollbar(userScrolled: true)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let observer = boundsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = liveScrollObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var totalWidth: CGFloat {
        contentWidth + gutterWidth
    }

    var measuredContentHeight: CGFloat {
        max(ceil(hostingView.fittingSize.height), 44)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: totalWidth, height: min(measuredContentHeight, maxHeight))
    }

    func updateThumbColor(_ color: NSColor) {
        scrollbarView.thumbColor = color
    }

    override func layout() {
        super.layout()
        let viewportWidth = max(1, min(contentWidth, bounds.width - gutterWidth))
        let targetScrollFrame = NSRect(x: 0, y: 0, width: viewportWidth, height: bounds.height)
        if scrollView.frame != targetScrollFrame {
            scrollView.frame = targetScrollFrame
        }
        let targetBarFrame = NSRect(
            x: viewportWidth,
            y: 0,
            width: max(0, bounds.width - viewportWidth),
            height: bounds.height
        )
        if scrollbarView.frame != targetBarFrame {
            scrollbarView.frame = targetBarFrame
        }
        syncDocumentSize()
    }

    private func handleDocumentLayout() {
        guard !isSyncingDocument else {
            return
        }
        let previousHeight = documentContainer.frame.height
        syncDocumentSize()
        if abs(documentContainer.frame.height - previousHeight) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }

    func syncDocumentSize() {
        guard !isSyncingDocument else {
            return
        }
        isSyncingDocument = true
        defer { isSyncingDocument = false }

        let width = scrollView.contentSize.width > 1 ? scrollView.contentSize.width : contentWidth
        if abs(documentContainer.frame.width - width) > 0.5 {
            documentContainer.frame.size.width = width
        }
        let fitted = ceil(hostingView.fittingSize.height)
        let targetDocHeight = max(fitted, scrollView.contentSize.height)
        if abs(documentContainer.frame.height - targetDocHeight) > 0.5 {
            documentContainer.frame.size.height = targetDocHeight
        }
        syncScrollbar(userScrolled: false)
    }

    func clampScrollOffsetIfNeeded() {
        let visibleHeight = scrollView.contentView.bounds.height
        let docHeight = ceil(hostingView.fittingSize.height)
        let maxOffset = max(0, docHeight - visibleHeight)
        if scrollView.contentView.bounds.origin.y > maxOffset {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxOffset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        syncScrollbar(userScrolled: false)
    }

    private func scrollToOffset(_ offset: CGFloat) {
        let visibleHeight = scrollView.contentView.bounds.height
        let docHeight = ceil(hostingView.fittingSize.height)
        let maxOffset = max(0, docHeight - visibleHeight)
        let clamped = min(max(offset, 0), maxOffset)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clamped))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        syncScrollbar(userScrolled: true)
    }

    private func handleClipBoundsChanged() {
        let currentOffset = scrollView.contentView.bounds.origin.y
        let moved = abs(currentOffset - lastObservedOffset) > 0.25
        lastObservedOffset = currentOffset
        syncScrollbar(userScrolled: moved)
    }

    private func syncScrollbar(userScrolled: Bool) {
        let visibleHeight = scrollView.contentView.bounds.height
        let docHeight = ceil(hostingView.fittingSize.height)
        let offset = scrollView.contentView.bounds.origin.y
        scrollbarView.updateMetrics(
            viewportHeight: visibleHeight,
            contentHeight: docHeight,
            scrollOffset: offset
        )
        if userScrolled {
            scrollbarView.noteScrollActivity()
        }
    }
}

private struct FittingGroupsScrollView<Content: View>: NSViewRepresentable {
    let contentWidth: CGFloat
    let gutterWidth: CGFloat
    let maxHeight: CGFloat
    let thumbColor: NSColor
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> BoundedGroupsScrollView<Content> {
        BoundedGroupsScrollView(
            rootView: content(),
            contentWidth: contentWidth,
            gutterWidth: gutterWidth,
            maxHeight: maxHeight,
            thumbColor: thumbColor
        )
    }

    func updateNSView(_ nsView: BoundedGroupsScrollView<Content>, context: Context) {
        nsView.maxHeight = maxHeight
        nsView.updateThumbColor(thumbColor)
        nsView.hostingView.rootView = content()
        nsView.syncDocumentSize()
        nsView.invalidateIntrinsicContentSize()
        nsView.needsLayout = true
        nsView.clampScrollOffsetIfNeeded()
    }

    @available(macOS 13.0, *)
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: BoundedGroupsScrollView<Content>,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? nsView.totalWidth
        return CGSize(width: width, height: min(nsView.measuredContentHeight, maxHeight))
    }
}
