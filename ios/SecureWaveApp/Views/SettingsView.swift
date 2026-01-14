import SwiftUI

struct SettingsView: View {
    @AppStorage("preferred_country") private var preferredCountry = "auto"
    @AppStorage("preferred_region") private var preferredRegion = "auto"
    @AppStorage("auto_connect") private var autoConnect = false
    @AppStorage("always_on") private var alwaysOn = false
    @AppStorage("kill_switch") private var killSwitch = true
    @AppStorage("split_tunneling") private var splitTunneling = false
    @AppStorage("protocol") private var protocolName = "wireguard"
    @AppStorage("dns_provider") private var dnsProvider = "cloudflare"

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Quick Preferences")) {
                    Picker("Preferred Country", selection: $preferredCountry) {
                        Text("Auto").tag("auto")
                        Text("United States").tag("us")
                        Text("United Kingdom").tag("uk")
                        Text("Germany").tag("de")
                        Text("Netherlands").tag("nl")
                        Text("Singapore").tag("sg")
                    }
                    Picker("Preferred Region", selection: $preferredRegion) {
                        Text("Auto").tag("auto")
                        Text("North America").tag("north_america")
                        Text("Europe").tag("europe")
                        Text("Asia Pacific").tag("asia_pacific")
                    }
                }

                Section(header: Text("Connection")) {
                    Toggle("Auto-connect on launch", isOn: $autoConnect)
                    Toggle("Always-on VPN", isOn: $alwaysOn)
                    Toggle("Kill switch", isOn: $killSwitch)
                    Toggle("Split tunneling", isOn: $splitTunneling)
                }

                Section(header: Text("Protocol & DNS")) {
                    Picker("Protocol", selection: $protocolName) {
                        Text("WireGuard (Recommended)").tag("wireguard")
                        Text("OpenVPN (Coming soon)").tag("openvpn")
                        Text("IKEv2 (Coming soon)").tag("ikev2")
                    }
                    Picker("DNS Provider", selection: $dnsProvider) {
                        Text("Cloudflare").tag("cloudflare")
                        Text("Quad9").tag("quad9")
                        Text("Custom").tag("custom")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
