import AppKit
import Foundation
import QuartzCore
import SwiftUI

struct TrayPanelTheme: Equatable {
    let isDark: Bool
    let pureBlack: Bool
    let glassTint: Int64
    let cardBg: Int64
    let blockBg: Int64
    let insetBg: Int64
    let hairline: Int64
    let primary: Int64
    let onPrimary: Int64
    let onSurface: Int64
    let onSurfaceVariant: Int64
    let success: Int64
    let warning: Int64
    let error: Int64
    let onError: Int64

    static let fallback = TrayPanelTheme(
        isDark: true,
        pureBlack: false,
        glassTint: 0x9E262629,
        cardBg: 0xFF212124,
        blockBg: 0xFF2B2B2E,
        insetBg: 0xFF36363A,
        hairline: 0x24F5F5F7,
        primary: 0xFF4DA3FF,
        onPrimary: 0xFF00315B,
        onSurface: 0xFFF5F5F7,
        onSurfaceVariant: 0xFFB0B0B6,
        success: 0xFF81C784,
        warning: 0xFFFFB74D,
        error: 0xFFF2B8B5,
        onError: 0xFF601410
    )

    init(
        isDark: Bool,
        pureBlack: Bool,
        glassTint: Int64,
        cardBg: Int64,
        blockBg: Int64,
        insetBg: Int64,
        hairline: Int64,
        primary: Int64,
        onPrimary: Int64,
        onSurface: Int64,
        onSurfaceVariant: Int64,
        success: Int64,
        warning: Int64,
        error: Int64,
        onError: Int64
    ) {
        self.isDark = isDark
        self.pureBlack = pureBlack
        self.glassTint = glassTint
        self.cardBg = cardBg
        self.blockBg = blockBg
        self.insetBg = insetBg
        self.hairline = hairline
        self.primary = primary
        self.onPrimary = onPrimary
        self.onSurface = onSurface
        self.onSurfaceVariant = onSurfaceVariant
        self.success = success
        self.warning = warning
        self.error = error
        self.onError = onError
    }

    init(from dict: [String: Any], fallback: TrayPanelTheme = .fallback) {
        self.isDark = dict["isDark"] as? Bool ?? fallback.isDark
        self.pureBlack = dict["pureBlack"] as? Bool ?? fallback.pureBlack
        self.glassTint = Self.argb(dict, "glassTint", fallback.glassTint)
        self.cardBg = Self.argb(dict, "cardBg", fallback.cardBg)
        self.blockBg = Self.argb(dict, "blockBg", fallback.blockBg)
        self.insetBg = Self.argb(dict, "insetBg", fallback.insetBg)
        self.hairline = Self.argb(dict, "hairline", fallback.hairline)
        self.primary = Self.argb(dict, "primary", fallback.primary)
        self.onPrimary = Self.argb(dict, "onPrimary", fallback.onPrimary)
        self.onSurface = Self.argb(dict, "onSurface", fallback.onSurface)
        self.onSurfaceVariant = Self.argb(dict, "onSurfaceVariant", fallback.onSurfaceVariant)
        self.success = Self.argb(dict, "success", fallback.success)
        self.warning = Self.argb(dict, "warning", fallback.warning)
        self.error = Self.argb(dict, "error", fallback.error)
        self.onError = Self.argb(dict, "onError", fallback.onError)
    }

    private static func argb(_ dict: [String: Any], _ key: String, _ fallback: Int64) -> Int64 {
        (dict[key] as? NSNumber)?.int64Value ?? fallback
    }

    func color(_ argb: Int64) -> Color {
        let value = UInt32(truncatingIfNeeded: argb)
        let alpha = Double((value >> 24) & 0xFF) / 255.0
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct TrayPanelLabels: Equatable {
    let appName: String
    let showWindow: String
    let start: String
    let stop: String
    let modeRule: String
    let modeGlobal: String
    let modeDirect: String
    let tun: String
    let systemProxy: String
    let speedStatistics: String
    let monochromeIcon: String
    let autoLaunch: String
    let proxies: String
    let search: String
    let testAllDelays: String
    let delayTest: String
    let timeout: String
    let delayFailed: String
    let copyEnvVar: String
    let exit: String
    let noProxies: String
    let safeMode: String

    static let fallback = TrayPanelLabels(
        appName: "FlClash",
        showWindow: "Show",
        start: "Start",
        stop: "Stop",
        modeRule: "Rule",
        modeGlobal: "Global",
        modeDirect: "Direct",
        tun: "TUN",
        systemProxy: "System Proxy",
        speedStatistics: "Speed",
        monochromeIcon: "Monochrome",
        autoLaunch: "Auto Launch",
        proxies: "Proxies",
        search: "Search",
        testAllDelays: "Test All Delays",
        delayTest: "Delay Test",
        timeout: "Timeout",
        delayFailed: "Failed",
        copyEnvVar: "Copy Env",
        exit: "Exit",
        noProxies: "No proxies",
        safeMode: "Safe Mode"
    )

    init(
        appName: String,
        showWindow: String,
        start: String,
        stop: String,
        modeRule: String,
        modeGlobal: String,
        modeDirect: String,
        tun: String,
        systemProxy: String,
        speedStatistics: String,
        monochromeIcon: String,
        autoLaunch: String,
        proxies: String,
        search: String,
        testAllDelays: String,
        delayTest: String,
        timeout: String,
        delayFailed: String,
        copyEnvVar: String,
        exit: String,
        noProxies: String,
        safeMode: String
    ) {
        self.appName = appName
        self.showWindow = showWindow
        self.start = start
        self.stop = stop
        self.modeRule = modeRule
        self.modeGlobal = modeGlobal
        self.modeDirect = modeDirect
        self.tun = tun
        self.systemProxy = systemProxy
        self.speedStatistics = speedStatistics
        self.monochromeIcon = monochromeIcon
        self.autoLaunch = autoLaunch
        self.proxies = proxies
        self.search = search
        self.testAllDelays = testAllDelays
        self.delayTest = delayTest
        self.timeout = timeout
        self.delayFailed = delayFailed
        self.copyEnvVar = copyEnvVar
        self.exit = exit
        self.noProxies = noProxies
        self.safeMode = safeMode
    }

    init(from dict: [String: Any], fallback: TrayPanelLabels = .fallback) {
        self.appName = dict["appName"] as? String ?? fallback.appName
        self.showWindow = dict["showWindow"] as? String ?? fallback.showWindow
        self.start = dict["start"] as? String ?? fallback.start
        self.stop = dict["stop"] as? String ?? fallback.stop
        self.modeRule = dict["modeRule"] as? String ?? fallback.modeRule
        self.modeGlobal = dict["modeGlobal"] as? String ?? fallback.modeGlobal
        self.modeDirect = dict["modeDirect"] as? String ?? fallback.modeDirect
        self.tun = dict["tun"] as? String ?? fallback.tun
        self.systemProxy = dict["systemProxy"] as? String ?? fallback.systemProxy
        self.speedStatistics = dict["speedStatistics"] as? String ?? fallback.speedStatistics
        self.monochromeIcon = dict["monochromeIcon"] as? String ?? fallback.monochromeIcon
        self.autoLaunch = dict["autoLaunch"] as? String ?? fallback.autoLaunch
        self.proxies = dict["proxies"] as? String ?? fallback.proxies
        self.search = dict["search"] as? String ?? fallback.search
        self.testAllDelays = dict["testAllDelays"] as? String ?? fallback.testAllDelays
        self.delayTest = dict["delayTest"] as? String ?? fallback.delayTest
        self.timeout = dict["timeout"] as? String ?? fallback.timeout
        self.delayFailed = dict["delayFailed"] as? String ?? fallback.delayFailed
        self.copyEnvVar = dict["copyEnvVar"] as? String ?? fallback.copyEnvVar
        self.exit = dict["exit"] as? String ?? fallback.exit
        self.noProxies = dict["noProxies"] as? String ?? fallback.noProxies
        self.safeMode = dict["safeMode"] as? String ?? fallback.safeMode
    }
}

struct TrayPanelShortcuts: Equatable {
    let showWindow: String
    let toggleRunning: String
    let modeRule: String
    let modeGlobal: String
    let modeDirect: String
    let testAllDelays: String
    let tun: String
    let systemProxy: String
    let copyEnv: String
    let exit: String

    static let empty = TrayPanelShortcuts(
        showWindow: "",
        toggleRunning: "",
        modeRule: "",
        modeGlobal: "",
        modeDirect: "",
        testAllDelays: "",
        tun: "",
        systemProxy: "",
        copyEnv: "",
        exit: ""
    )

    init(
        showWindow: String,
        toggleRunning: String,
        modeRule: String,
        modeGlobal: String,
        modeDirect: String,
        testAllDelays: String,
        tun: String,
        systemProxy: String,
        copyEnv: String,
        exit: String
    ) {
        self.showWindow = showWindow
        self.toggleRunning = toggleRunning
        self.modeRule = modeRule
        self.modeGlobal = modeGlobal
        self.modeDirect = modeDirect
        self.testAllDelays = testAllDelays
        self.tun = tun
        self.systemProxy = systemProxy
        self.copyEnv = copyEnv
        self.exit = exit
    }

    init(from dict: [String: Any], fallback: TrayPanelShortcuts = .empty) {
        self.showWindow = dict["showWindow"] as? String ?? fallback.showWindow
        self.toggleRunning = dict["toggleRunning"] as? String ?? fallback.toggleRunning
        self.modeRule = dict["modeRule"] as? String ?? fallback.modeRule
        self.modeGlobal = dict["modeGlobal"] as? String ?? fallback.modeGlobal
        self.modeDirect = dict["modeDirect"] as? String ?? fallback.modeDirect
        self.testAllDelays = dict["testAllDelays"] as? String ?? fallback.testAllDelays
        self.tun = dict["tun"] as? String ?? fallback.tun
        self.systemProxy = dict["systemProxy"] as? String ?? fallback.systemProxy
        self.copyEnv = dict["copyEnv"] as? String ?? fallback.copyEnv
        self.exit = dict["exit"] as? String ?? fallback.exit
    }
}

struct TrayPanelProxy: Identifiable, Equatable {
    let name: String
    let type: String
    let delay: Int?
    let testing: Bool
    let selected: Bool

    var id: String { name }

    init(
        name: String,
        type: String,
        delay: Int?,
        testing: Bool,
        selected: Bool
    ) {
        self.name = name
        self.type = type
        self.delay = delay
        self.testing = testing
        self.selected = selected
    }

    init(from dict: [String: Any]) {
        self.name = dict["name"] as? String ?? ""
        self.type = dict["type"] as? String ?? ""
        self.delay = (dict["delay"] as? NSNumber)?.intValue
        self.testing = dict["testing"] as? Bool ?? false
        self.selected = dict["selected"] as? Bool ?? false
    }
}

struct TrayPanelGroup: Identifiable, Equatable {
    let name: String
    let type: String
    let selectedProxyName: String
    let selectedDelay: Int?
    let testing: Bool
    let proxies: [TrayPanelProxy]

    var id: String { name }

    init(
        name: String,
        type: String,
        selectedProxyName: String,
        selectedDelay: Int?,
        testing: Bool,
        proxies: [TrayPanelProxy]
    ) {
        self.name = name
        self.type = type
        self.selectedProxyName = selectedProxyName
        self.selectedDelay = selectedDelay
        self.testing = testing
        self.proxies = proxies
    }

    init(from dict: [String: Any]) {
        self.name = dict["name"] as? String ?? ""
        self.type = dict["type"] as? String ?? ""
        self.selectedProxyName = dict["selectedProxyName"] as? String ?? ""
        self.selectedDelay = (dict["selectedDelay"] as? NSNumber)?.intValue
        self.testing = dict["testing"] as? Bool ?? false
        let rawProxies = dict["proxies"] as? [[String: Any]] ?? []
        self.proxies = rawProxies.map(TrayPanelProxy.init(from:))
    }
}

struct TrayPanelState: Equatable {
    let isStart: Bool
    let suspended: Bool
    let safeMode: Bool
    let mode: String
    let tunEnable: Bool
    let systemProxy: Bool
    let showTrayTitle: Bool
    let monochromeTrayIcon: Bool
    let autoLaunch: Bool
    let port: Int
    let testingAll: Bool
    let theme: TrayPanelTheme
    let labels: TrayPanelLabels
    let shortcuts: TrayPanelShortcuts
    let groups: [TrayPanelGroup]

    static let fallback = TrayPanelState(
        isStart: false,
        suspended: false,
        safeMode: false,
        mode: "rule",
        tunEnable: false,
        systemProxy: false,
        showTrayTitle: false,
        monochromeTrayIcon: true,
        autoLaunch: false,
        port: 7890,
        testingAll: false,
        theme: .fallback,
        labels: .fallback,
        shortcuts: .empty,
        groups: []
    )

    init(
        isStart: Bool,
        suspended: Bool,
        safeMode: Bool,
        mode: String,
        tunEnable: Bool,
        systemProxy: Bool,
        showTrayTitle: Bool,
        monochromeTrayIcon: Bool,
        autoLaunch: Bool,
        port: Int,
        testingAll: Bool,
        theme: TrayPanelTheme,
        labels: TrayPanelLabels,
        shortcuts: TrayPanelShortcuts,
        groups: [TrayPanelGroup]
    ) {
        self.isStart = isStart
        self.suspended = suspended
        self.safeMode = safeMode
        self.mode = mode
        self.tunEnable = tunEnable
        self.systemProxy = systemProxy
        self.showTrayTitle = showTrayTitle
        self.monochromeTrayIcon = monochromeTrayIcon
        self.autoLaunch = autoLaunch
        self.port = port
        self.testingAll = testingAll
        self.theme = theme
        self.labels = labels
        self.shortcuts = shortcuts
        self.groups = groups
    }

    init(from dict: [String: Any]) {
        self.isStart = dict["isStart"] as? Bool ?? false
        self.suspended = dict["suspended"] as? Bool ?? false
        self.safeMode = dict["safeMode"] as? Bool ?? false
        self.mode = dict["mode"] as? String ?? "rule"
        self.tunEnable = dict["tunEnable"] as? Bool ?? false
        self.systemProxy = dict["systemProxy"] as? Bool ?? false
        self.showTrayTitle = dict["showTrayTitle"] as? Bool ?? false
        self.monochromeTrayIcon = dict["monochromeTrayIcon"] as? Bool ?? true
        self.autoLaunch = dict["autoLaunch"] as? Bool ?? false
        self.port = (dict["port"] as? NSNumber)?.intValue ?? 7890
        self.testingAll = dict["testingAll"] as? Bool ?? false
        if let rawTheme = dict["theme"] as? [String: Any] {
            self.theme = TrayPanelTheme(from: rawTheme)
        } else {
            self.theme = .fallback
        }
        if let rawLabels = dict["labels"] as? [String: Any] {
            self.labels = TrayPanelLabels(from: rawLabels)
        } else {
            self.labels = .fallback
        }
        if let rawShortcuts = dict["shortcuts"] as? [String: Any] {
            self.shortcuts = TrayPanelShortcuts(from: rawShortcuts)
        } else {
            self.shortcuts = .empty
        }
        let rawGroups = dict["groups"] as? [[String: Any]] ?? []
        self.groups = rawGroups.map(TrayPanelGroup.init(from:))
    }
}

struct TrayPanelTraffic: Equatable {
    let up: String
    let down: String

    static let empty = TrayPanelTraffic(up: "0 B/s", down: "0 B/s")

    init(up: String, down: String) {
        self.up = up
        self.down = down
    }

    init(from dict: [String: Any]) {
        self.up = dict["up"] as? String ?? "0 B/s"
        self.down = dict["down"] as? String ?? "0 B/s"
    }
}

struct UnfoldSpringState {
    // Matches prism_ui UnfoldMotion (iOS UICollectionView outline disclosure).
    static let mass: Double = 1.0
    static let stiffness: Double = 631.65
    static let damping: Double = 50.27
    static let distanceTolerance: Double = 1e-3
    static let velocityTolerance: Double = 0.03

    private static let root: Double = sqrt(damping * damping - 4.0 * mass * stiffness)
    private static let r1: Double = (-damping + root) / (2.0 * mass)
    private static let r2: Double = (-damping - root) / (2.0 * mass)

    var target: Double
    var startTime: CFTimeInterval
    var c1: Double
    var c2: Double
    var value: Double
    var velocity: Double

    init(from startValue: Double, velocity startVelocity: Double, target: Double, at now: CFTimeInterval) {
        self.target = target
        self.startTime = now
        let y0 = startValue - target
        self.c2 = (startVelocity - Self.r1 * y0) / (Self.r2 - Self.r1)
        self.c1 = y0 - self.c2
        self.value = startValue
        self.velocity = startVelocity
    }

    var clampedProgress: CGFloat {
        CGFloat(min(max(value, 0.0), 1.0))
    }

    mutating func step(at now: CFTimeInterval) -> Bool {
        let elapsed = max(0.0, now - startTime)
        let e1 = exp(Self.r1 * elapsed)
        let e2 = exp(Self.r2 * elapsed)
        let displacement = c1 * e1 + c2 * e2
        let nextVelocity = c1 * Self.r1 * e1 + c2 * Self.r2 * e2
        if elapsed >= 1.5
            || (abs(displacement) <= Self.distanceTolerance && abs(nextVelocity) <= Self.velocityTolerance)
        {
            value = target
            velocity = 0.0
            return true
        }
        value = target + displacement
        velocity = nextVelocity
        return false
    }
}

private final class UnfoldFrameTicker: NSObject {
    var onTick: ((CFTimeInterval) -> Void)?

    private weak var displayWindow: NSWindow?
    private var displayLink: AnyObject?
    private var fallbackTimer: Timer?

    deinit {
        stop()
    }

    func attach(window: NSWindow?) {
        displayWindow = window
    }

    var isRunning: Bool {
        displayLink != nil || fallbackTimer != nil
    }

    func start() {
        guard !isRunning else {
            return
        }
        if #available(macOS 14.0, *) {
            if let link = displayWindow?.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
                ?? NSScreen.main?.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
            {
                link.add(to: .main, forMode: .common)
                displayLink = link
                return
            }
        }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.onTick?(CACurrentMediaTime())
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    func stop() {
        if #available(macOS 14.0, *), let link = displayLink as? CADisplayLink {
            link.invalidate()
        }
        displayLink = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    @objc private func handleDisplayLink(_ sender: AnyObject) {
        onTick?(CACurrentMediaTime())
    }
}

final class TrayPanelStore: ObservableObject {
    @Published private(set) var state: TrayPanelState = .fallback
    @Published private(set) var traffic: TrayPanelTraffic = .empty
    @Published var expandedGroupNames: Set<String> = []
    @Published private(set) var groupUnfoldProgress: [String: CGFloat] = [:]
    @Published var isSearchVisible: Bool = false
    @Published var searchQuery: String = ""
    @Published private(set) var copiedFeedback: Bool = false
    @Published var maxPanelHeight: CGFloat = 600

    var onUnfoldAnimationSettled: (() -> Void)?

    private var copiedResetWorkItem: DispatchWorkItem?
    private var unfoldSprings: [String: UnfoldSpringState] = [:]
    private let unfoldTicker = UnfoldFrameTicker()

    init() {
        unfoldTicker.onTick = { [weak self] now in
            self?.stepUnfoldAnimations(at: now)
        }
    }

    deinit {
        unfoldTicker.stop()
    }

    var isAnyGroupUnfolding: Bool {
        !unfoldSprings.isEmpty
    }

    func attachDisplayWindow(_ window: NSWindow?) {
        unfoldTicker.attach(window: window)
    }

    func unfoldState(for groupName: String, forceExpand: Bool) -> (progress: CGFloat, isAnimating: Bool) {
        if forceExpand {
            return (1, false)
        }
        if let spring = unfoldSprings[groupName] {
            return (spring.clampedProgress, true)
        }
        return (expandedGroupNames.contains(groupName) ? 1 : 0, false)
    }

    func updateState(from dict: [String: Any]) {
        let next = TrayPanelState(from: dict)
        guard next != state else {
            return
        }
        state = next
        let validNames = Set(next.groups.map(\.name))
        expandedGroupNames.formIntersection(validNames)
        pruneUnfoldSprings(validNames: validNames)
    }

    func updateTraffic(from dict: [String: Any]) {
        traffic = TrayPanelTraffic(from: dict)
    }

    func toggleGroup(
        _ name: String,
        animate: Bool? = nil,
        at now: CFTimeInterval = CACurrentMediaTime(),
        autoTick: Bool = true
    ) {
        let willExpand: Bool
        if expandedGroupNames.contains(name) {
            expandedGroupNames.remove(name)
            willExpand = false
        } else {
            expandedGroupNames.insert(name)
            willExpand = true
        }

        let shouldAnimate = animate ?? !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard shouldAnimate else {
            unfoldSprings.removeValue(forKey: name)
            groupUnfoldProgress.removeValue(forKey: name)
            if unfoldSprings.isEmpty {
                unfoldTicker.stop()
            }
            return
        }

        let target = willExpand ? 1.0 : 0.0
        var startValue = willExpand ? 0.0 : 1.0
        var startVelocity = 0.0
        if var existing = unfoldSprings[name] {
            _ = existing.step(at: now)
            startValue = existing.value
            startVelocity = existing.velocity
        }

        let spring = UnfoldSpringState(
            from: startValue,
            velocity: startVelocity,
            target: target,
            at: now
        )
        unfoldSprings[name] = spring
        groupUnfoldProgress[name] = spring.clampedProgress
        if autoTick {
            unfoldTicker.start()
        }
    }

    func stepUnfoldAnimations(at now: CFTimeInterval = CACurrentMediaTime()) {
        guard !unfoldSprings.isEmpty else {
            unfoldTicker.stop()
            return
        }

        var nextProgress = groupUnfoldProgress
        var settledNames: [String] = []
        for name in Array(unfoldSprings.keys) {
            guard var spring = unfoldSprings[name] else {
                continue
            }
            let done = spring.step(at: now)
            if done {
                settledNames.append(name)
            } else {
                unfoldSprings[name] = spring
                nextProgress[name] = spring.clampedProgress
            }
        }
        for name in settledNames {
            unfoldSprings.removeValue(forKey: name)
            nextProgress.removeValue(forKey: name)
        }
        groupUnfoldProgress = nextProgress

        if unfoldSprings.isEmpty {
            unfoldTicker.stop()
            onUnfoldAnimationSettled?()
        }
    }

    func snapUnfoldAnimations() {
        let hadActive = !unfoldSprings.isEmpty
        unfoldTicker.stop()
        unfoldSprings.removeAll()
        if !groupUnfoldProgress.isEmpty {
            groupUnfoldProgress.removeAll()
        }
        if hadActive {
            onUnfoldAnimationSettled?()
        }
    }

    func toggleSearch() {
        isSearchVisible.toggle()
        if !isSearchVisible {
            searchQuery = ""
        }
    }

    func triggerCopiedFeedback() {
        copiedResetWorkItem?.cancel()
        copiedFeedback = true
        let workItem = DispatchWorkItem { [weak self] in
            self?.copiedFeedback = false
        }
        copiedResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    func reset() {
        copiedResetWorkItem?.cancel()
        copiedResetWorkItem = nil
        copiedFeedback = false
        isSearchVisible = false
        searchQuery = ""
        expandedGroupNames.removeAll()
        unfoldTicker.stop()
        unfoldSprings.removeAll()
        groupUnfoldProgress.removeAll()
        state = .fallback
        traffic = .empty
    }

    private func pruneUnfoldSprings(validNames: Set<String>) {
        guard !unfoldSprings.isEmpty else {
            return
        }
        unfoldSprings = unfoldSprings.filter { validNames.contains($0.key) }
        groupUnfoldProgress = groupUnfoldProgress.filter { validNames.contains($0.key) }
        if unfoldSprings.isEmpty {
            unfoldTicker.stop()
            onUnfoldAnimationSettled?()
        }
    }
}
