// SecureWaveAPIClient.swift
// Shared Apple API client for SecureWave VPN.
// Used by both the iOS/macOS host apps and the macOS standalone client.
//
// Security guarantees:
// - HTTPS only. HTTP URLs are rejected at call site.
// - Certificate validation uses the default URLSession trust chain (no bypass).
// - Auth token stored in Keychain (kSecClassGenericPassword), never in UserDefaults.
// - No secrets hardcoded. Bundle ID is the Keychain service discriminator.

import Foundation
import Security

// MARK: - Models

public struct SWServer: Codable, Identifiable {
    public let id: String
    public let name: String
    public let city: String
    public let country: String
    public let region: String
    public let hostAddress: String
    public let latencyMs: Int?
    public let isOnline: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, city, country, region
        case hostAddress = "host_address"
        case latencyMs = "latency_ms"
        case isOnline = "is_online"
    }
}

public struct SWVPNConfig: Codable {
    public let protocol_: String
    public let serverPublicKey: String
    public let clientPrivateKey: String
    public let clientPublicKey: String
    public let addressCidr: String
    public let endpointHost: String
    public let endpointPort: Int
    public let dns: [String]
    public let allowedIps: [String]
    public let keepaliveSeconds: Int
    public let presharedKey: String?

    enum CodingKeys: String, CodingKey {
        case protocol_ = "protocol"
        case serverPublicKey = "server_public_key"
        case clientPrivateKey = "client_private_key"
        case clientPublicKey = "client_public_key"
        case addressCidr = "address_cidr"
        case endpointHost = "endpoint_host"
        case endpointPort = "endpoint_port"
        case dns
        case allowedIps = "allowed_ips"
        case keepaliveSeconds = "keepalive_seconds"
        case presharedKey = "preshared_key"
    }
}

public struct SWLoginResponse: Codable {
    public let accessToken: String
    public let tokenType: String
    public let userId: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case userId = "user_id"
    }
}

public enum SWAPIError: Error, LocalizedError {
    case insecureURL(String)
    case unauthenticated
    case httpError(Int, String)
    case decodingError(Error)
    case networkError(Error)
    case noData

    public var errorDescription: String? {
        switch self {
        case .insecureURL(let url):
            return "Rejected insecure URL: \(url). Only HTTPS is permitted."
        case .unauthenticated:
            return "Not authenticated. Please log in."
        case .httpError(let code, let message):
            return "Server returned \(code): \(message)"
        case .decodingError(let error):
            return "Response decoding failed: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .noData:
            return "Server returned an empty response."
        }
    }
}

// MARK: - Keychain Token Store

private enum SWKeychainStore {
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.securewave.app"
    }
    private static let account = "securewave.auth_token"

    static func save(token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        // Delete existing entry first, then add.
        SecItemDelete(query as CFDictionary)
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    static func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - API Client

public final class SecureWaveAPIClient {
    public static let shared = SecureWaveAPIClient()

    private let baseURL: URL
    private let session: URLSession

    /// Token is read-only publicly; writing goes through login/logout.
    public var isAuthenticated: Bool {
        SWKeychainStore.load() != nil
    }

    public init(
        baseURLString: String = "https://securewaveapp.com/api",
        urlSession: URLSession = .shared
    ) {
        guard let url = URL(string: baseURLString), url.scheme == "https" else {
            // Hard crash at init time if an HTTP URL is supplied — this is a
            // programmer error, not a runtime condition.
            fatalError("SecureWaveAPIClient requires an HTTPS base URL. Got: \(baseURLString)")
        }
        self.baseURL = url
        self.session = urlSession
    }

    // MARK: - Auth

    /// Log in with username/password. Stores the token in Keychain on success.
    public func login(username: String, password: String) async throws -> SWLoginResponse {
        let body: [String: String] = ["username": username, "password": password]
        let response: SWLoginResponse = try await post(path: "/auth/login", body: body, authenticated: false)
        SWKeychainStore.save(token: response.accessToken)
        return response
    }

    /// Remove the stored Keychain token.
    public func logout() {
        SWKeychainStore.delete()
    }

    // MARK: - Servers

    /// Fetch available server locations.
    public func servers() async throws -> [SWServer] {
        try await get(path: "/vpn/servers")
    }

    // MARK: - VPN Config

    /// Fetch a WireGuard configuration for the given server.
    public func vpnConfig(serverId: String, protocol vpnProtocol: String = "wireguard") async throws -> SWVPNConfig {
        try await get(path: "/vpn/connect/\(serverId)?protocol=\(vpnProtocol)")
    }

    // MARK: - HTTP Primitives

    private func get<T: Decodable>(path: String) async throws -> T {
        let url = try secureURL(for: path)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        try attachAuthHeader(to: &request)
        return try await execute(request)
    }

    private func post<Body: Encodable, T: Decodable>(
        path: String,
        body: Body,
        authenticated: Bool = true
    ) async throws -> T {
        let url = try secureURL(for: path)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        if authenticated {
            try attachAuthHeader(to: &request)
        }
        return try await execute(request)
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SWAPIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SWAPIError.noData
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            if http.statusCode == 401 {
                SWKeychainStore.delete() // Token expired — clear it.
                throw SWAPIError.unauthenticated
            }
            throw SWAPIError.httpError(http.statusCode, message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SWAPIError.decodingError(error)
        }
    }

    private func secureURL(for path: String) throws -> URL {
        let fullString = baseURL.absoluteString + path
        guard let url = URL(string: fullString), url.scheme == "https" else {
            throw SWAPIError.insecureURL(fullString)
        }
        return url
    }

    private func attachAuthHeader(to request: inout URLRequest) throws {
        guard let token = SWKeychainStore.load() else {
            throw SWAPIError.unauthenticated
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}
