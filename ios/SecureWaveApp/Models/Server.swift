import Foundation

struct Server: Identifiable, Decodable, Hashable {
    let id: String
    let location: String
    let region: String?
    let latencyMs: Double?
    let bandwidthMbps: Double?

    enum CodingKeys: String, CodingKey {
        case id = "server_id"
        case location
        case region
        case latencyMs = "latency_ms"
        case bandwidthMbps = "bandwidth_mbps"
    }
}
