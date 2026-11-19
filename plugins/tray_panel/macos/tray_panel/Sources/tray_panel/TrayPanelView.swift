import AppKit
import SwiftUI

struct TrayPanelView: View {
    @ObservedObject var store: TrayPanelStore
    let onAction: (String, [String: Any]) -> Void

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerSection
            outboundModeSection
            quickTogglesSection
            if !state.groups.isEmpty {
                proxiesSection
                    .transition(.opacity)
            }
            Rectangle()
                .fill(theme.color(theme.hairline))
                .frame(height: 0.75)
            footerSection
        }
        .padding(14)
        .frame(width: 348)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(theme.color(theme.glassTint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(theme.color(theme.hairline), lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(Color.clear)
        .fixedSize(horizontal: false, vertical: true)
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

                Text("\(filteredGroups.count)")
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
            } else {
                FittingGroupsScrollView(maxHeight: maxGroupsScrollHeight) {
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
                    .frame(width: 320, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    Text("\(labels.copyEnvVar) :\(state.port)")
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

                        if !group.type.isEmpty {
                            Text(group.type)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(theme.color(theme.onSurfaceVariant))
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

private final class FlippedGroupsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class BoundedGroupsScrollView<Content: View>: NSScrollView {
    let hostingView: NSHostingView<Content>
    private let documentContainer = FlippedGroupsDocumentView()
    var maxHeight: CGFloat {
        didSet {
            if abs(oldValue - maxHeight) > 0.5 {
                invalidateIntrinsicContentSize()
            }
        }
    }

    init(rootView: Content, maxHeight: CGFloat) {
        self.hostingView = NSHostingView(rootView: rootView)
        self.maxHeight = maxHeight
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        documentContainer.translatesAutoresizingMaskIntoConstraints = true
        documentContainer.autoresizingMask = [.width]
        documentContainer.frame = NSRect(x: 0, y: 0, width: 320, height: 44)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        documentContainer.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: documentContainer.topAnchor),
        ])
        documentView = documentContainer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let width = contentSize.width > 1 ? contentSize.width : (bounds.width > 1 ? bounds.width : 320)
        if abs(documentContainer.frame.width - width) > 0.5 {
            documentContainer.frame.size.width = width
        }
        hostingView.layoutSubtreeIfNeeded()
        let fitted = ceil(hostingView.fittingSize.height)
        return NSSize(width: width, height: min(max(fitted, 44), maxHeight))
    }

    override func layout() {
        super.layout()
        let width = contentSize.width > 1 ? contentSize.width : (bounds.width > 1 ? bounds.width : 320)
        if abs(documentContainer.frame.width - width) > 0.5 {
            documentContainer.frame.size.width = width
        }
        hostingView.layoutSubtreeIfNeeded()
        let fitted = ceil(hostingView.fittingSize.height)
        let targetDocHeight = max(fitted, contentSize.height)
        if abs(documentContainer.frame.height - targetDocHeight) > 0.5 {
            documentContainer.frame.size.height = targetDocHeight
        }
    }
}

private struct FittingGroupsScrollView<Content: View>: NSViewRepresentable {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> BoundedGroupsScrollView<Content> {
        BoundedGroupsScrollView(rootView: content(), maxHeight: maxHeight)
    }

    func updateNSView(_ nsView: BoundedGroupsScrollView<Content>, context: Context) {
        nsView.maxHeight = maxHeight
        nsView.hostingView.rootView = content()
        nsView.hostingView.layoutSubtreeIfNeeded()
        nsView.invalidateIntrinsicContentSize()
        nsView.needsLayout = true
        let visibleHeight = nsView.contentView.bounds.height
        let docHeight = ceil(nsView.hostingView.fittingSize.height)
        let maxOffset = max(0, docHeight - visibleHeight)
        if nsView.contentView.bounds.origin.y > maxOffset {
            nsView.contentView.scroll(to: NSPoint(x: 0, y: maxOffset))
            nsView.reflectScrolledClipView(nsView.contentView)
        }
    }
}
