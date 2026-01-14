# SecureWave iOS App (Xcode Setup)

This folder contains SwiftUI source files for an iOS client. Create an Xcode project and drop these files in:

1) Open Xcode → File → New → Project → iOS App.
2) Product name: SecureWave, Interface: SwiftUI, Language: Swift.
3) Replace the generated `ContentView.swift` and `SecureWaveApp.swift` with the files in `ios/SecureWaveApp/`.
4) Add all files under `ios/SecureWaveApp/` to the Xcode project (Models, Services, Views).
5) Update the API base URL in `ios/SecureWaveApp/Services/APIClient.swift`.

Notes:
- WireGuard on iOS requires the Network Extension entitlement and an Apple Developer account.
- The `VPNService` here is a placeholder. It shows where WireGuard integration should be added.
- Until the native VPN is implemented, use the website QR/config flow for real connectivity.
