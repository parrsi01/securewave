import Foundation

final class VPNService {
    static let shared = VPNService()
    private init() {}

    func connect(using configText: String) async throws {
        // TODO: Integrate WireGuardKit / Network Extension for real tunnel start.
        // Placeholder for now.
        _ = configText
    }

    func disconnect() async throws {
        // TODO: Stop WireGuard tunnel via Network Extension.
    }
}
