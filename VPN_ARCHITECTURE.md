# SecureWave VPN — Architecture Reference

## End-to-End Data Flow

```
User action: tap "Connect"
       │
       ▼
Flutter UI (Dart)
  VpnStateNotifier._startConnect()
  → resolves VpnProtocol.auto  →  effective = wireguard (or fallback)
       │
       ▼
ChannelVpnService.connect(protocol: .wireGuard, server: …)
  → builds argument map (endpointHost, clientPrivateKey, allowedIps, …)
  → MethodChannel.invokeMethod("connectWireGuard", args)
       │
       ▼  [platform channel XPC boundary]
       │
       ▼
iOS: AppDelegate.swift → SecureWaveVPNManager.connectWireGuard(arguments:)
macOS: MainFlutterWindow.swift → SecureWaveVPNManager.connectWireGuard(arguments:)
       │
       ▼
SecureWaveVPNManager (VPNManager.swift)
  1. Parse + validate SecureWaveWireGuardRequest
  2. NETunnelProviderManager.loadAllFromPreferences()
  3. Build NETunnelProviderProtocol with providerConfiguration dict
  4. saveToPreferences() → loadFromPreferences()
  5. session.startVPNTunnel()
       │
       ▼  [XPC: nesessionmanager spawns extension process]
       │
       ▼
PacketTunnelProvider.startTunnel()   (runs in extension sandbox)
  1. Read providerConfiguration["wgQuickConfig"]
  2. TunnelConfiguration(fromWgQuickConfig:)  ← WireGuardKit parse
  3. WireGuardAdapter.start(tunnelConfiguration:)
  4. Creates utun interface, applies Noise handshake
  5. Calls completionHandler(nil) on success
  6. Writes "connected" state to App Group UserDefaults
       │
       ▼  [kernel network stack]
       │
       ▼
utun0  (WireGuard virtual interface)
  AllowedIPs = 0.0.0.0/0, ::/0  ← full-tunnel route
  Endpoint = <server_ip>:51820   ← UDP to gateway
       │
       ▼  [encrypted UDP datagrams: ChaCha20-Poly1305]
       │
       ▼
SecureWave Gateway (Hetzner VPS)
  de-fra-1: 157.x.x.x:51820  (Frankfurt)
  de-nue-1: 162.x.x.x:51820  (Nuremberg)
  wg0 interface — peer table lookup by public key
       │
       ▼
Internet (traffic exits from gateway IP)
```

## Network Routing Flow (full tunnel)

```
Device (10.0.0.2/32)
  ├── 10.0.0.1/32  →  wg0  (server gateway IP inside tunnel)
  └── 0.0.0.0/0   →  wg0  (all other traffic)

  DNS: 1.1.1.1, 1.0.0.1  (set via NEDNSSettings, resolved through tunnel)

Gateway (de-fra-1 / de-nue-1)
  ├── WireGuard peer table: client public key → allowed 10.0.0.2/32
  ├── ip rule: table 51820  (policy routing, Table=off avoids default table clash)
  ├── ip route: via gateway in table 51820
  └── iptables MASQUERADE: 10.8.0.0/24 → eth0 (NAT to public IP)
```

## Key Exchange (Noise_IKpsk2)

```
Client                           Server
  │                                │
  │──── Initiator handshake ──────▶│  (Curve25519 ephemeral + static)
  │◀─── Responder handshake ───────│
  │                                │
  ┌──────────────── Derived session keys ─────────────────┐
  │  Initiator→Responder: ChaCha20-Poly1305 key           │
  │  Responder→Initiator: ChaCha20-Poly1305 key           │
  └───────────────────────────────────────────────────────┘
  │── Encrypted data packets ─────▶│
```

Keys rotate every 180 seconds (or 2^64 bytes — whichever comes first).
The private key is generated on-device and never transmitted.

## Security Model

| Layer | Mechanism | Notes |
|---|---|---|
| Transport encryption | ChaCha20-Poly1305 | Authenticated encryption, 256-bit key |
| Key exchange | Curve25519 ECDH | Forward secrecy; keys rotate every 180s |
| API authentication | JWT Bearer token | Stored in Keychain; HTTPS only |
| Keychain storage | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | Not backed up to iCloud |
| Extension process | App sandbox + entitlement gate | Cannot access arbitrary device data |
| Certificate validation | iOS/macOS default trust store | No bypass, no custom CA pinning |
| DNS | Tunnel DNS (1.1.1.1 via wg0) | Prevents DNS leaks on full-tunnel config |

## Component Responsibilities

| Component | Location | Responsibility |
|---|---|---|
| `SecureWaveAPIClient.swift` | `apple/shared/api_client/` | HTTPS, JWT, Keychain auth token |
| `VPNConfiguration.swift` | `apple/shared/config/` | Config model, wg-quick renderer, NESettings builder |
| `VPNProfileManager.swift` | `apple/shared/vpn_profile_manager/` | NETunnelProviderManager lifecycle, SwiftUI state |
| `PacketTunnelProvider.swift` | `securewave_app/ios/PacketTunnel/` | WireGuardKit tunnel, status persistence |
| `VPNManager.swift` | `securewave_app/ios/Runner/` | Flutter ↔ NE bridge, argument parsing |
| `AppDelegate.swift` | `securewave_app/ios/Runner/` | MethodChannel registration |
| `vpn_service.dart` | `lib/core/services/` | Protocol resolution, channel invocation |
| `vpn_state.dart` | `lib/core/state/` | State machine, timeout guards, reconnect loop |
| Backend `routes/vpn.py` | `routes/vpn.py` | Peer registration, config generation |

## State Machine (simplified)

```
disconnected
    │ connect()
    ▼
connecting  ──── timeout (45s) ──▶  error → disconnected
    │ tunnel up
    ▼
connected
    │ disconnect() / tunnel drops
    ▼
disconnecting
    │ adapter stopped
    ▼
disconnected
```

State is authoritative in `VpnStateNotifier` (Dart). The extension
writes a shadow copy to App Group UserDefaults so the host process
can observe tunnel state across process restarts.

## Multi-Protocol Support

| Protocol | iOS | macOS (Flutter) | macOS (native) | Linux | Android | Windows |
|---|---|---|---|---|---|---|
| WireGuard | WireGuardKit | WireGuardKit | WireGuardKit | wg-quick | GoBackend | wireguard.exe |
| OpenVPN | — | — | — | openvpn | — | — |
| IKEv2 | — | — | — | strongswan | — | — |

`VpnProtocol.auto` is resolved to the best available protocol before
`connect()` is called. It never reaches the native layer unresolved.
