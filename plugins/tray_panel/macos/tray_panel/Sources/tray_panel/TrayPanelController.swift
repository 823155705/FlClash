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

private final class TrayPanelContainerView: NSView {
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        applyClipping()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        applyClipping()
    }

    private func applyClipping() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }
}

private final class TrayPanelBorderView: NSView {
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        applyStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        applyStyle()
    }

    private func applyStyle() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.75
    }
}

private extension TrayPanelTheme {
    func nsColor(_ argb: Int64) -> NSColor {
        let value = UInt32(truncatingIfNeeded: argb)
        let alpha = CGFloat((value >> 24) & 0xFF) / 255.0
        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

final class TrayPanelController: NSObject, NSWindowDelegate {
    private static let panelWidth: CGFloat = 348
    private static let maxHeightCap: CGFloat = 600
    private static let minHeightFloor: CGFloat = 210
    private static let cornerRadius: CGFloat = 22

    let store = TrayPanelStore()

    private let onVisibilityChanged: (Bool) -> Void
    private let onAction: (String, [String: Any]) -> Void

    private var panel: TrayFloatingPanel?
    private var containerView: TrayPanelContainerView?
    private var visualEffectView: NSVisualEffectView?
    private var tintView: NSView?
    private var borderView: TrayPanelBorderView?
    private var hostingView: NSHostingView<TrayPanelView>?

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var resizeScheduled = false
    private var measuredContentHeight: CGFloat = TrayPanelController.minHeightFloor
    private var targetPanelFrame: NSRect?
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

    private func resolveStatusButton() -> NSStatusBarButton? {
        let contentClass: AnyClass? = NSClassFromString("FlClashTrayContentView")
        for window in NSApp.windows {
            guard let root = window.contentView else {
                continue
            }
            if let button = findStatusBarButton(in: root, contentClass: contentClass) {
                return button
            }
        }
        return nil
    }

    private func findStatusBarButton(in view: NSView, contentClass: AnyClass?) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton {
            if let contentClass = contentClass {
                if containsView(ofClass: contentClass, in: button) {
                    return button
                }
            } else {
                return button
            }
        }
        for subview in view.subviews {
            if let button = findStatusBarButton(in: subview, contentClass: contentClass) {
                return button
            }
        }
        return nil
    }

    private func containsView(ofClass targetClass: AnyClass, in view: NSView) -> Bool {
        if view.isKind(of: targetClass) {
            return true
        }
        for subview in view.subviews {
            if containsView(ofClass: targetClass, in: subview) {
                return true
            }
        }
        return false
    }

    func updateState(_ dict: [String: Any]) {
        store.updateState(from: dict)
        applyAppearance()
        if isVisible {
            repositionPanel(animated: true)
        }
    }

    func updateTraffic(_ dict: [String: Any]) {
        store.updateTraffic(from: dict)
    }

    @discardableResult
    func open() -> Bool {
        guard let button = resolveStatusButton(), button.window != nil else {
            return false
        }
        if isVisible {
            repositionPanel(animated: false)
            panel?.makeKeyAndOrderFront(nil)
            return true
        }

        ensurePanel()
        guard let panel = panel else {
            return false
        }

        updateMaxPanelHeight(for: button)
        applyAppearance()
        repositionPanel(animated: false)

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }

        installObservers()
        button.highlight(true)
        onVisibilityChanged(true)
        return true
    }

    func close() {
        let wasVisible = isVisible
        removeObservers()
        targetPanelFrame = nil
        panel?.orderOut(nil)
        resolveStatusButton()?.highlight(false)
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
        containerView = nil
        visualEffectView = nil
        tintView = nil
        borderView = nil
        hostingView = nil
        measuredContentHeight = Self.minHeightFloor
        targetPanelFrame = nil
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

        let container = TrayPanelContainerView(cornerRadius: Self.cornerRadius)

        let effectView = NSVisualEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
        effectView.layer?.cornerRadius = Self.cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        effectView.maskImage = Self.makeContinuousMaskImage(cornerRadius: Self.cornerRadius)

        let tint = NSView()
        tint.translatesAutoresizingMaskIntoConstraints = false
        tint.wantsLayer = true

        let border = TrayPanelBorderView(cornerRadius: Self.cornerRadius)
        border.translatesAutoresizingMaskIntoConstraints = false

        let rootView = TrayPanelView(
            store: store,
            onAction: { [weak self] action, payload in
                self?.onAction(action, payload)
            },
            onContentHeight: { [weak self] height in
                self?.handleContentHeightChanged(height)
            }
        )
        let host = NSHostingView(rootView: rootView)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor

        effectView.addSubview(tint)
        effectView.addSubview(host)
        container.addSubview(effectView)
        container.addSubview(border)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            tint.topAnchor.constraint(equalTo: effectView.topAnchor),
            tint.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            border.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            border.topAnchor.constraint(equalTo: container.topAnchor),
            border.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            host.topAnchor.constraint(equalTo: effectView.topAnchor),
            host.heightAnchor.constraint(equalToConstant: Self.maxHeightCap + 100),
        ])

        createdPanel.contentView = container
        self.panel = createdPanel
        self.containerView = container
        self.visualEffectView = effectView
        self.tintView = tint
        self.borderView = border
        self.hostingView = host
    }

    private static func makeContinuousMaskImage(cornerRadius: CGFloat) -> NSImage {
        // Keep the full continuous squircle lead-in (~1.53x radius) intact inside the 9-slice caps.
        let inset = ceil(cornerRadius * 1.6)
        let side = inset * 2 + 2
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }
            let maskLayer = CALayer()
            maskLayer.frame = rect
            maskLayer.backgroundColor = NSColor.black.cgColor
            maskLayer.cornerRadius = cornerRadius
            maskLayer.cornerCurve = .continuous
            maskLayer.masksToBounds = true
            maskLayer.render(in: context)
            return true
        }
        image.capInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        image.resizingMode = .stretch
        return image
    }

    private func applyAppearance() {
        let theme = store.state.theme
        let name: NSAppearance.Name = theme.isDark ? .darkAqua : .aqua
        let appearance = NSAppearance(named: name)
        panel?.appearance = appearance
        containerView?.appearance = appearance
        visualEffectView?.appearance = appearance
        tintView?.layer?.backgroundColor = theme.nsColor(theme.glassTint).cgColor
        borderView?.layer?.borderColor = theme.nsColor(theme.hairline).cgColor
    }

    private func handleContentHeightChanged(_ height: CGFloat) {
        guard height > 0, abs(measuredContentHeight - height) > 0.5 else {
            return
        }
        measuredContentHeight = height
        scheduleResize()
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
                self.repositionPanel(animated: true)
            }
        }
    }

    private func repositionPanel(animated: Bool = false) {
        guard let panel = panel,
              let hostingView = hostingView,
              let button = resolveStatusButton(),
              let buttonWindow = button.window else {
            return
        }

        updateMaxPanelHeight(for: button)
        hostingView.layoutSubtreeIfNeeded()
        let panelHeight = min(store.maxPanelHeight, max(Self.minHeightFloor, measuredContentHeight))

        let screen = buttonWindow.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonScreenRect = buttonWindow.convertToScreen(buttonRectInWindow)

        var x = buttonScreenRect.midX - Self.panelWidth / 2
        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - Self.panelWidth - 8))
        let topY = min(buttonScreenRect.minY, visibleFrame.maxY) - 6
        let y = max(visibleFrame.minY + 8, topY - panelHeight)

        let nextFrame = NSRect(x: round(x), y: round(y), width: Self.panelWidth, height: round(panelHeight))
        if animated, let target = targetPanelFrame, framesMatch(target, nextFrame) {
            return
        }
        if !framesMatch(panel.frame, nextFrame) {
            targetPanelFrame = nextFrame
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(nextFrame, display: true)
                }, completionHandler: { [weak self] in
                    guard let self = self else {
                        return
                    }
                    if let target = self.targetPanelFrame, self.framesMatch(target, nextFrame) {
                        self.targetPanelFrame = nil
                        self.panel?.invalidateShadow()
                    }
                })
            } else {
                targetPanelFrame = nil
                panel.setFrame(nextFrame, display: true)
                panel.invalidateShadow()
            }
        }
    }

    private func framesMatch(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= 0.5
            && abs(lhs.origin.y - rhs.origin.y) <= 0.5
            && abs(lhs.size.width - rhs.size.width) <= 0.5
            && abs(lhs.size.height - rhs.size.height) <= 0.5
    }

    private func isPointInStatusButton(_ screenPoint: NSPoint) -> Bool {
        guard let button = resolveStatusButton(), let buttonWindow = button.window else {
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
