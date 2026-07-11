import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let channelName = "securewave/vpn"

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.engine.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "isAvailable":
          result(false)
        case "getStatus":
          result(["status": "disconnected"])
        case "getTrafficStats":
          result([
            "rx_bytes": 0,
            "tx_bytes": 0,
            "counters_available": false,
            "unavailable_reason": "macOS Network Extension runtime is not implemented in this build."
          ])
        case "connect":
          result(FlutterError(code: "vpn_not_configured",
                              message: "VPN unavailable on macOS (yet). This build does not include a Network Extension tunnel provider. See MACOS_VPN_SETUP.md for integration steps.",
                              details: ["platform": "macos", "configured": false]))
        case "disconnect":
          result(FlutterError(code: "vpn_not_configured",
                              message: "VPN unavailable on macOS (yet). This build does not include a Network Extension tunnel provider. See MACOS_VPN_SETUP.md for integration steps.",
                              details: ["platform": "macos", "configured": false]))
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
