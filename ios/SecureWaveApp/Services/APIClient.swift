import Foundation

final class APIClient {
    static let shared = APIClient()
    private init() {}

    var baseURL = URL(string: "https://securewave.example.com")!

    func login(email: String, password: String) async throws -> String {
        let endpoint = baseURL.appendingPathComponent("/api/auth/login")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let token = decoded?["access_token"] as? String
        guard let token else { throw URLError(.userAuthenticationRequired) }
        return token
    }

    func register(email: String, password: String) async throws -> String {
        let endpoint = baseURL.appendingPathComponent("/api/auth/register")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let token = decoded?["access_token"] as? String
        guard let token else { throw URLError(.userAuthenticationRequired) }
        return token
    }

    func fetchServers(token: String) async throws -> [Server] {
        let endpoint = baseURL.appendingPathComponent("/api/optimizer/servers")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode([String: [Server]].self, from: data)
        return decoded["servers"] ?? []
    }

    func connectVPN(token: String, serverId: String?) async throws -> [String: Any] {
        let endpoint = baseURL.appendingPathComponent("/api/vpn/connect")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let serverId {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["server_id": serverId])
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return decoded ?? [:]
    }

    func disconnectVPN(token: String, connectionId: Int?) async throws {
        let endpoint = baseURL.appendingPathComponent("/api/vpn/disconnect")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let connectionId {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["connection_id": connectionId])
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}
