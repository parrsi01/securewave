import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let bridgeChannelNames = [
    "securewave/vpn",
    "securewave/vpn_platform_bridge",
  ]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      for channelName in bridgeChannelNames {
        let channel = FlutterMethodChannel(
          name: channelName,
          binaryMessenger: controller.binaryMessenger
        )
        channel.setMethodCallHandler { call, result in
          self.handleVPNMethodCall(call, result: result)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleVPNMethodCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
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
    case "connectWireGuard", "startVPN":
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
      SecureWaveVPNManager.shared.stopVPN { error in
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
