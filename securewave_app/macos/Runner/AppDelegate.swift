import Cocoa
import FlutterMacOS
import Darwin

@main
class AppDelegate: FlutterAppDelegate {
  private let vpnChannelName = "securewave/vpn"
  private let trafficChannelName = "securewave/traffic_stats"
  private let tunnelStatusChannelName = "securewave/tunnel_status"

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }

    let messenger = controller.engine.binaryMessenger

    let vpnChannel = FlutterMethodChannel(name: vpnChannelName, binaryMessenger: messenger)
    vpnChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        result(false)
      case "connect", "disconnect":
        result(
          FlutterError(
            code: "vpn_not_configured",
            message: "Native VPN not configured for macOS. See MACOS_VPN_SETUP.md for integration steps.",
            details: ["platform": "macos", "configured": false]
          )
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let trafficChannel = FlutterMethodChannel(name: trafficChannelName, binaryMessenger: messenger)
    trafficChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getTrafficStats":
        result(self?.trafficStatsPayload() ?? ["rxBytes": 0, "txBytes": 0])
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let tunnelStatusChannel = FlutterMethodChannel(
      name: tunnelStatusChannelName,
      binaryMessenger: messenger
    )
    tunnelStatusChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getTunnelStatus":
        result(self?.tunnelStatusPayload() ?? [
          "status": "DISCONNECTED",
          "interfaceName": NSNull(),
          "interfaceOk": false,
          "routingOk": false,
          "details": "No macOS tunnel status available."
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func tunnelStatusPayload() -> [String: Any] {
    let stats = activeTunnelInterfaceStats()
    let routeInterface = defaultRouteInterface()
    let interfaceOk = stats != nil
    let routingOk = interfaceOk && routeInterface == stats?.name

    return [
      "status": interfaceOk ? "CONNECTED" : "DISCONNECTED",
      "interfaceName": stats?.name as Any,
      "interfaceOk": interfaceOk,
      "routingOk": routingOk,
      "connectedSince": NSNull(),
      "lastError": NSNull(),
      "details": interfaceOk
        ? "Detected tunnel interface \(stats?.name ?? "unknown")."
        : "No active utun or WireGuard interface detected."
    ]
  }

  private func trafficStatsPayload() -> [String: Any] {
    let stats = activeTunnelInterfaceStats()
    return [
      "rxBytes": stats?.rxBytes ?? 0,
      "txBytes": stats?.txBytes ?? 0,
      "interfaceName": stats?.name as Any,
      "countersAvailable": stats != nil,
      "details": stats == nil ? "Native traffic counters unavailable." : "Traffic counters captured from \(stats?.name ?? "tunnel")."
    ]
  }

  private func defaultRouteInterface() -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/route")
    process.arguments = ["-n", "get", "default"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
      try process.run()
      process.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      guard let output = String(data: data, encoding: .utf8) else {
        return nil
      }
      for line in output.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("interface:") {
          return trimmed.replacingOccurrences(of: "interface:", with: "")
            .trimmingCharacters(in: .whitespaces)
        }
      }
    } catch {
      return nil
    }
    return nil
  }

  private func activeTunnelInterfaceStats() -> (name: String, rxBytes: Int64, txBytes: Int64)? {
    var pointer: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&pointer) == 0, let first = pointer else {
      return nil
    }
    defer { freeifaddrs(pointer) }

    var candidate: (name: String, rxBytes: Int64, txBytes: Int64)?
    var cursor: UnsafeMutablePointer<ifaddrs>? = first

    while let current = cursor {
      let interface = current.pointee
      let name = String(cString: interface.ifa_name)
      let isTunnel = name.hasPrefix("utun") || name.hasPrefix("wg") || name.hasPrefix("tun")
      if isTunnel,
         let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
        candidate = (
          name: name,
          rxBytes: Int64(data.ifi_ibytes),
          txBytes: Int64(data.ifi_obytes)
        )
      }
      cursor = interface.ifa_next
    }

    return candidate
  }
}
