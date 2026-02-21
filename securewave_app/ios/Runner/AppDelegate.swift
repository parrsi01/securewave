import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "securewave/vpn", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "isAvailable":
          if let error = SecureWaveVPNManager.shared.availabilityError() {
            result(FlutterError(code: "vpn_unavailable", message: error.localizedDescription, details: nil))
          } else {
            result(true)
          }
        case "getStatus":
          result(SecureWaveVPNManager.shared.statusString())
        case "getCapabilities":
          result(SecureWaveVPNManager.shared.capabilitiesPayload())
        case "connect":
          guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "invalid_profile", message: "Missing VPN arguments.", details: nil))
            return
          }
          let protocolName = (args["protocol"] as? String ?? "wireguard").lowercased()
          if protocolName != "wireguard" {
            result(FlutterError(code: "protocol_unavailable", message: "iOS runtime currently supports WireGuard only.", details: nil))
            return
          }

          let profile = args["profile"] as? [String: Any]
          let configFromProfile = profile?["wireguard_config"] as? String
          let config = (args["config"] as? String) ?? configFromProfile ?? ""
          if config.isEmpty {
            result(FlutterError(code: "invalid_config", message: "Missing WireGuard configuration.", details: nil))
            return
          }
          SecureWaveVPNManager.shared.connect(config: config) { error in
            if let error = error {
              result(FlutterError(code: "vpn_connect_failed", message: error.localizedDescription, details: nil))
            } else {
              result(nil)
            }
          }
        case "disconnect":
          SecureWaveVPNManager.shared.disconnect {
            result(nil)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
