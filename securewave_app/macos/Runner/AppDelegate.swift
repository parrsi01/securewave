import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let bridgeChannelNames = [
    "securewave/vpn",
    "securewave/vpn_platform_bridge",
  ]

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      for channelName in bridgeChannelNames {
        let channel = FlutterMethodChannel(
          name: channelName,
          binaryMessenger: controller.engine.binaryMessenger
        )
        channel.setMethodCallHandler { call, result in
          switch call.method {
          case "isAvailable":
            SecureWaveVPNManager.shared.isAvailable { available, _ in
              result(available)
            }
          case "diagnostics":
            SecureWaveVPNManager.shared.diagnostics { payload in
              result(payload)
            }
          case "status":
            SecureWaveVPNManager.shared.status { payload in
              result(payload)
            }
          case "connect", "connectWireGuard", "startVPN":
            guard let args = call.arguments as? [String: Any] else {
              result(
                FlutterError(
                  code: "invalid_profile",
                  message: "Missing VPN bridge arguments.",
                  details: nil
                )
              )
              return
            }
            SecureWaveVPNManager.shared.startVPN(arguments: args) { error in
              if let error {
                result(Self.flutterError(from: error))
              } else {
                result(nil)
              }
            }
          case "disconnect", "stopVPN":
            SecureWaveVPNManager.shared.disconnect { error in
              if let error {
                result(Self.flutterError(from: error))
              } else {
                result(nil)
              }
            }
          default:
            result(FlutterMethodNotImplemented)
          }
        }
      }
    }
  }

  private static func flutterError(from error: Error) -> FlutterError {
    let nsError = error as NSError
    let code = (nsError.userInfo["SecureWaveErrorCode"] as? String) ?? "vpn_connect_failed"
    return FlutterError(
      code: code,
      message: nsError.localizedDescription,
      details: nil
    )
  }
}
