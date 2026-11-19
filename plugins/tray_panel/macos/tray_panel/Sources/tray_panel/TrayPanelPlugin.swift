import Cocoa
import FlutterMacOS

public class TrayPanelPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel!
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
        let channel = FlutterMethodChannel(name: "tray_panel", binaryMessenger: registrar.messenger)
        let instance = TrayPanelPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
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
}
