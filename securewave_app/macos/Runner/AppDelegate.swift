import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let channelName = "securewave/vpn"
  private let macosUnavailableMessage =
    "macOS VPN in SecureWave requires a signed Network Extension integration. " +
    "This build does not include a Packet Tunnel or NEVPNManager entitlements."

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
        let args = call.arguments as? [String: Any]
        let protocolId = (args?["protocol"] as? String ?? "").lowercased()

        switch call.method {
        case "isAvailable":
          result(false)
        case "getStatus":
          result("disconnected")
        case "getCapabilities":
          result([
            "wireguard": false,
            "openvpn": false,
            "ikev2": false,
            "windows_thread_safe": false,
            "android_vpnservice_based": false,
            "macos_entitlements_ready": false,
            "macos_entitlement_warning": self.macosUnavailableMessage,
            "openvpn_install_hint":
              "OpenVPN on macOS requires a signed Network Extension/Packet Tunnel integration.",
            "ikev2_install_hint":
              "IKEv2 on macOS requires NEVPNManager entitlements and signed provisioning.",
          ])
        case "connect":
          let protocolMessage: String
          if protocolId == "openvpn" {
            protocolMessage =
              "OpenVPN is unavailable on this macOS build. A signed Packet Tunnel/Network Extension target is required."
          } else if protocolId == "ikev2" || protocolId == "ipsec" {
            protocolMessage =
              "IKEv2 is unavailable on this macOS build. NEVPNManager entitlements and signing are required."
          } else {
            protocolMessage = self.macosUnavailableMessage
          }
          result(FlutterError(
            code: "protocol_unavailable",
            message: protocolMessage,
            details: ["platform": "macos", "configured": false, "protocol": protocolId]
          ))
        case "disconnect":
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
