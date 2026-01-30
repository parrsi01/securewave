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
        case "connect":
          result(FlutterError(code: "vpn_not_configured",
                              message: "Native VPN not configured for macOS. See MACOS_VPN_SETUP.md for integration steps.",
                              details: ["platform": "macos", "configured": false]))
        case "disconnect":
          result(FlutterError(code: "vpn_not_configured",
                              message: "Native VPN not configured for macOS. See MACOS_VPN_SETUP.md for integration steps.",
                              details: ["platform": "macos", "configured": false]))
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
