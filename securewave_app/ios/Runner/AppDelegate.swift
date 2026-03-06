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
      let messenger = controller.binaryMessenger

      let vpnChannel = FlutterMethodChannel(name: "securewave/vpn", binaryMessenger: messenger)
      vpnChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "isAvailable":
          result(true)
        case "connect":
          guard let args = call.arguments as? [String: Any],
                let config = args["config"] as? String,
                !config.isEmpty else {
            result(FlutterError(code: "invalid_config", message: "Missing WireGuard configuration.", details: nil))
            return
          }
          SecureWaveVPNManager.shared.connect(config: config) { error in
            if let error {
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

      let trafficChannel = FlutterMethodChannel(name: "securewave/traffic_stats", binaryMessenger: messenger)
      trafficChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "getTrafficStats":
          SecureWaveVPNManager.shared.trafficStats { payload in
            result(payload)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let tunnelStatusChannel = FlutterMethodChannel(
        name: "securewave/tunnel_status",
        binaryMessenger: messenger
      )
      tunnelStatusChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "getTunnelStatus":
          SecureWaveVPNManager.shared.tunnelStatus { payload in
            result(payload)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
