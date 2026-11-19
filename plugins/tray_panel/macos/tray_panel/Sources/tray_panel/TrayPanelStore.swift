import Foundation
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

final class TrayPanelStore: ObservableObject {
    @Published private(set) var state: TrayPanelState = .fallback
    @Published private(set) var traffic: TrayPanelTraffic = .empty
    @Published var expandedGroupNames: Set<String> = []
    @Published var isSearchVisible: Bool = false
    @Published var searchQuery: String = ""
    @Published private(set) var copiedFeedback: Bool = false
    @Published var maxPanelHeight: CGFloat = 600

    private var copiedResetWorkItem: DispatchWorkItem?

    func updateState(from dict: [String: Any]) {
        let next = TrayPanelState(from: dict)
        guard next != state else {
            return
        }
        state = next
        let validNames = Set(next.groups.map(\.name))
        expandedGroupNames.formIntersection(validNames)
    }

    func updateTraffic(from dict: [String: Any]) {
        traffic = TrayPanelTraffic(from: dict)
    }

    func toggleGroup(_ name: String) {
        if expandedGroupNames.contains(name) {
            expandedGroupNames.remove(name)
        } else {
            expandedGroupNames.insert(name)
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
        state = .fallback
        traffic = .empty
    }
}
