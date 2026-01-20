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
        case "connect":
          guard let args = call.arguments as? [String: Any],
                let config = args["config"] as? String,
                !config.isEmpty else {
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
