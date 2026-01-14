import Foundation

struct VPNSettings: Codable {
    var preferredCountry: String = "auto"
    var preferredRegion: String = "auto"
    var autoConnect: Bool = false
    var alwaysOn: Bool = false
    var killSwitch: Bool = true
    var splitTunneling: Bool = false
    var protocolName: String = "wireguard"
    var dnsProvider: String = "cloudflare"
}
