import Cocoa
import FlutterMacOS

public class TrayPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel!
    private var statusItem: TrayStatusItem?
    private var menu: TrayMenu?
    private lazy var panelController = TrayPanelController(
        onVisibilityChanged: { [weak self] visible in
            self?.channel.invokeMethod("onPanelVisibilityChanged", arguments: ["visible": visible])
        },
        onAction: { [weak self] action, payload in
            self?.channel.invokeMethod(
                "onPanelAction",
                arguments: [
                    "action": action,
                    "payload": payload,
                ]
            )
        }
    )

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "tray", binaryMessenger: registrar.messenger)
        let instance = TrayPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "show":
            result(show(call.arguments as? [String: Any]))
        case "setTitle":
            result(setTitle(call.arguments as? [String: Any]))
        case "hide":
            hide()
            result(true)
        case "openMenu":
            result(openMenu())
        case "setPanelState":
            result(setPanelState(call.arguments as? [String: Any]))
        case "setPanelTraffic":
            result(setPanelTraffic(call.arguments as? [String: Any]))
        case "openPanel":
            result(panelController.open())
        case "closePanel":
            panelController.close()
            result(true)
        case "togglePanel":
            result(panelController.toggle())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func show(_ arguments: [String: Any]?) -> Bool {
        guard let arguments = arguments else {
            return false
        }

        guard let item = statusItem ?? makeStatusItem() else {
            return false
        }
        panelController.attach(statusItem: item)

        if let icon = arguments["icon"] as? [String: Any] {
            guard let image = makeImage(icon) else {
                return false
            }
            item.setImage(image, position: icon["position"] as? String ?? "leading")
        }

        item.setTitle(arguments["title"] as? String ?? "")

        if let items = arguments["menu"] as? [[String: Any]] {
            menu = TrayMenu(
                items: items,
                onSelect: { [weak self] id in
                    self?.channel.invokeMethod("onMenuItemSelected", arguments: ["id": id])
                },
                onClose: { [weak self] in
                    self?.statusItem?.closeMenu()
                }
            )
        }

        return true
    }

    private func setTitle(_ arguments: [String: Any]?) -> Bool {
        guard let statusItem = statusItem else {
            return false
        }
        statusItem.setTitle(arguments?["title"] as? String ?? "")
        return true
    }

    private func setPanelState(_ arguments: [String: Any]?) -> Bool {
        guard let arguments = arguments else {
            return false
        }
        panelController.updateState(arguments)
        return true
    }

    private func setPanelTraffic(_ arguments: [String: Any]?) -> Bool {
        guard let arguments = arguments else {
            return false
        }
        panelController.updateTraffic(arguments)
        return true
    }

    private func hide() {
        panelController.dispose()
        statusItem?.remove()
        statusItem = nil
        menu = nil
    }

    private func openMenu() -> Bool {
        guard let statusItem = statusItem, let menu = menu else {
            return false
        }
        if panelController.isVisible {
            panelController.close()
        }
        statusItem.openMenu(menu)
        return true
    }

    private func makeStatusItem() -> TrayStatusItem? {
        guard let item = TrayStatusItem(
            onIconActivated: { [weak self] in
                self?.channel.invokeMethod("onIconActivated", arguments: nil)
            },
            onMenuRequested: { [weak self] in
                self?.channel.invokeMethod("onMenuRequested", arguments: nil)
            }
        ) else {
            return nil
        }
        statusItem = item
        panelController.attach(statusItem: item)
        return item
    }

    private func makeImage(_ icon: [String: Any]) -> NSImage? {
        let size = icon["size"] as? Int ?? 18
        let pointSize = NSSize(width: size, height: size)
        let image = NSImage(size: pointSize)
        for rep in icon["reps"] as? [[String: Any]] ?? [] {
            guard let encoded = rep["bytes"] as? String,
                  let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
                  let bitmap = NSBitmapImageRep(data: data) else {
                continue
            }
            bitmap.size = pointSize
            image.addRepresentation(bitmap)
        }
        guard !image.representations.isEmpty else {
            return nil
        }
        image.isTemplate = icon["isTemplate"] as? Bool ?? false
        return image
    }
}
