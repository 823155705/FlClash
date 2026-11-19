import AppKit
import SwiftUI

private final class TrayFloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private final class TrayPanelHostingView<Content: View>: NSHostingView<Content> {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

final class TrayPanelController: NSObject, NSWindowDelegate {
    private static let panelWidth: CGFloat = 348
    private static let maxHeightCap: CGFloat = 600
    private static let minHeightFloor: CGFloat = 210
    private static let cornerRadius: CGFloat = 20

    let store = TrayPanelStore()

    private let onVisibilityChanged: (Bool) -> Void
    private let onAction: (String, [String: Any]) -> Void

    private weak var statusItem: TrayStatusItem?
    private var panel: TrayFloatingPanel?
    private var visualEffectView: NSVisualEffectView?
    private var hostingView: TrayPanelHostingView<TrayPanelView>?

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var resizeScheduled = false
    private var lastUnexpectedStatusCloseUptime: TimeInterval = 0

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    init(
        onVisibilityChanged: @escaping (Bool) -> Void,
        onAction: @escaping (String, [String: Any]) -> Void
    ) {
        self.onVisibilityChanged = onVisibilityChanged
        self.onAction = onAction
        super.init()
    }

    deinit {
        removeObservers()
    }

    func attach(statusItem: TrayStatusItem?) {
        self.statusItem = statusItem
    }

    func updateState(_ dict: [String: Any]) {
        store.updateState(from: dict)
        applyAppearance()
        if isVisible {
            scheduleResize()
        }
    }

    func updateTraffic(_ dict: [String: Any]) {
        store.updateTraffic(from: dict)
    }

    @discardableResult
    func open() -> Bool {
        guard let button = statusItem?.anchorButton, button.window != nil else {
            return false
        }
        if isVisible {
            repositionPanel()
            panel?.makeKeyAndOrderFront(nil)
            return true
        }

        ensurePanel()
        guard let panel = panel else {
            return false
        }

        updateMaxPanelHeight(for: button)
        applyAppearance()
        repositionPanel()

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }

        installObservers()
        statusItem?.setHighlighted(true)
        onVisibilityChanged(true)
        return true
    }

    func close() {
        let wasVisible = isVisible
        removeObservers()
        panel?.orderOut(nil)
        statusItem?.setHighlighted(false)
        if wasVisible {
            onVisibilityChanged(false)
        }
    }

    @discardableResult
    func toggle() -> Bool {
        if isVisible {
            close()
            return true
        }
        // Ignore a status-button mouseDown arriving right after an unexpected resign-close.
        if ProcessInfo.processInfo.systemUptime - lastUnexpectedStatusCloseUptime < 0.06 {
            lastUnexpectedStatusCloseUptime = 0
            return true
        }
        return open()
    }

    func dispose() {
        close()
        panel?.delegate = nil
        panel?.contentView = nil
        panel = nil
        visualEffectView = nil
        hostingView = nil
        statusItem = nil
        store.reset()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isVisible else {
            return
        }
        if isStatusButtonInteraction() {
            return
        }
        if isPointInStatusButton(NSEvent.mouseLocation) {
            lastUnexpectedStatusCloseUptime = ProcessInfo.processInfo.systemUptime
        }
        close()
    }

    private func isStatusButtonInteraction() -> Bool {
        guard isPointInStatusButton(NSEvent.mouseLocation) else {
            return false
        }
        if NSEvent.pressedMouseButtons != 0 {
            return true
        }
        guard let event = NSApp.currentEvent else {
            return false
        }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return true
        default:
            return false
        }
    }

    private func ensurePanel() {
        if panel != nil {
            return
        }

        let createdPanel = TrayFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        createdPanel.delegate = self
        createdPanel.isFloatingPanel = true
        createdPanel.level = .statusBar
        createdPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        createdPanel.backgroundColor = .clear
        createdPanel.isOpaque = false
        createdPanel.hasShadow = true
        createdPanel.hidesOnDeactivate = false
        createdPanel.isMovable = false
        createdPanel.onCancel = { [weak self] in
            self?.close()
        }

        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = Self.cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true

        let rootView = TrayPanelView(store: store) { [weak self] action, payload in
            self?.onAction(action, payload)
        }
        let host = TrayPanelHostingView(rootView: rootView)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.onLayout = { [weak self] in
            self?.scheduleResize()
        }

        effectView.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            host.topAnchor.constraint(equalTo: effectView.topAnchor),
            host.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        createdPanel.contentView = effectView
        self.panel = createdPanel
        self.visualEffectView = effectView
        self.hostingView = host
    }

    private func applyAppearance() {
        let name: NSAppearance.Name = store.state.theme.isDark ? .darkAqua : .aqua
        let appearance = NSAppearance(named: name)
        panel?.appearance = appearance
        visualEffectView?.appearance = appearance
    }

    private func updateMaxPanelHeight(for button: NSStatusBarButton) {
        let screen = button.window?.screen ?? NSScreen.main
        let visibleHeight = screen?.visibleFrame.height ?? 800
        store.maxPanelHeight = min(Self.maxHeightCap, max(Self.minHeightFloor, visibleHeight - 24))
    }

    private func scheduleResize() {
        guard !resizeScheduled, isVisible else {
            return
        }
        resizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }
            self.resizeScheduled = false
            if self.isVisible {
                self.repositionPanel()
            }
        }
    }

    private func repositionPanel() {
        guard let panel = panel,
              let hostingView = hostingView,
              let button = statusItem?.anchorButton,
              let buttonWindow = button.window else {
            return
        }

        updateMaxPanelHeight(for: button)
        hostingView.layoutSubtreeIfNeeded()
        let fittedHeight = hostingView.fittingSize.height
        let panelHeight = min(store.maxPanelHeight, max(Self.minHeightFloor, fittedHeight))

        let screen = buttonWindow.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonScreenRect = buttonWindow.convertToScreen(buttonRectInWindow)

        var x = buttonScreenRect.midX - Self.panelWidth / 2
        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - Self.panelWidth - 8))
        let topY = min(buttonScreenRect.minY, visibleFrame.maxY) - 6
        let y = max(visibleFrame.minY + 8, topY - panelHeight)

        let nextFrame = NSRect(x: round(x), y: round(y), width: Self.panelWidth, height: round(panelHeight))
        if abs(panel.frame.origin.x - nextFrame.origin.x) > 0.5
            || abs(panel.frame.origin.y - nextFrame.origin.y) > 0.5
            || abs(panel.frame.size.width - nextFrame.size.width) > 0.5
            || abs(panel.frame.size.height - nextFrame.size.height) > 0.5 {
            panel.setFrame(nextFrame, display: true)
        }
    }

    private func isPointInStatusButton(_ screenPoint: NSPoint) -> Bool {
        guard let button = statusItem?.anchorButton, let buttonWindow = button.window else {
            return false
        }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(rectInWindow)
        return screenRect.contains(screenPoint)
    }

    private func installObservers() {
        removeObservers()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self = self, !self.isPointInStatusButton(NSEvent.mouseLocation) else {
                return
            }
            self.close()
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self = self, let panel = self.panel, panel.isVisible else {
                return event
            }
            if event.window === panel {
                return event
            }
            if self.isPointInStatusButton(NSEvent.mouseLocation) {
                return event
            }
            self.close()
            return event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else {
                return event
            }
            if event.keyCode == 53 {
                self.close()
                return nil
            }
            return event
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.close()
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.close()
        }
    }

    private func removeObservers() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceObserver = nil
        }
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
    }
}
