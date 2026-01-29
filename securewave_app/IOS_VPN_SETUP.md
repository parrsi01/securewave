# iOS VPN Setup (Xcode Required)

This repo includes the Packet Tunnel extension and native VPN bridge,
but you must finish configuration in Xcode on macOS.

## Steps

1. Open `securewave_app/ios/Runner.xcworkspace` in Xcode.
   - The build includes a workspace guard that fails if `Runner.xcodeproj` is opened directly.
2. Select the **Runner** target:
   - Set your Apple Team.
   - Confirm the bundle identifier you intend to use.
3. Select the **PacketTunnel** target:
   - Set the same Apple Team.
   - Enable the **Network Extensions** capability.
4. Wait for Swift Package resolution:
   - The project references WireGuardKit from
     `https://github.com/WireGuard/wireguard-apple`.
5. Plug in a physical iPhone and build/run **Runner**.

## Notes

- iOS simulators cannot start VPN tunnels.
- You must have an Apple Developer account to sign a Network Extension.
- The app passes a full WireGuard config string to the tunnel provider.
