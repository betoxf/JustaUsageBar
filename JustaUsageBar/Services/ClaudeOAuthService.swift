//
//  ClaudeOAuthService.swift
//  JustaUsageBar
//
//  Reads Claude CLI OAuth credentials and fetches usage via OAuth API
//

import Foundation
import Security

final class ClaudeOAuthService {
    static let shared = ClaudeOAuthService()

    private let oauthClientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"
    private let usageEndpoint = "https://api.anthropic.com/api/oauth/usage"

    private var cachedCredentials: OAuthCredentials?
    private var lastCredentialCheck: Date?
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    struct OAuthCredentials {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date?
        var scopes: [String]
    }

    private init() {}

    // MARK: - Credential Discovery

    func loadCredentials() -> OAuthCredentials? {
        // Return cache if fresh
        if let cached = cachedCredentials,
           let lastCheck = lastCredentialCheck,
           Date().timeIntervalSince(lastCheck) < cacheTTL {
            return cached
        }

        // 1. Try credentials file (~/.claude/.credentials.json)
        if let creds = readCredentialsFile() {
            cachedCredentials = creds
            lastCredentialCheck = Date()
            return creds
        }

        // 2. Try Keychain (Claude CLI's entry)
        if let creds = readFromKeychain() {
            cachedCredentials = creds
            lastCredentialCheck = Date()
            return creds
        }

        return nil
    }

    var hasCredentials: Bool {
        loadCredentials() != nil
    }

    func clearCache() {
        cachedCredentials = nil
        lastCredentialCheck = nil
    }

    // MARK: - Read from ~/.claude/.credentials.json

    private func readCredentialsFile() -> OAuthCredentials? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let credPath = homeDir.appendingPathComponent(".claude/.credentials.json")

        guard FileManager.default.fileExists(atPath: credPath.path),
              let data = try? Data(contentsOf: credPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String else {
            return nil
        }

        let refreshToken = oauth["refreshToken"] as? String
        var expiresAt: Date?
        if let expiresMs = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: expiresMs / 1000.0)
        }
        let scopes = oauth["scopes"] as? [String] ?? []

        return OAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scopes: scopes
        )
    }

    // MARK: - Read from Keychain (Claude CLI)

    private func readFromKeychain() -> OAuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String else {
            return nil
        }

        let refreshToken = oauth["refreshToken"] as? String
        var expiresAt: Date?
        if let expiresMs = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: expiresMs / 1000.0)
        }
        let scopes = oauth["scopes"] as? [String] ?? []

        return OAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scopes: scopes
        )
    }

    // MARK: - Fetch Usage via OAuth

    func fetchUsage() async throws -> UsageData {
        guard var creds = loadCredentials() else {
            throw APIError.noCredentials
        }

        // Check if token needs refresh
        if let expiresAt = creds.expiresAt, expiresAt < Date() {
            if let refreshToken = creds.refreshToken {
                creds = try await refreshAccessToken(refreshToken: refreshToken)
                cachedCredentials = creds
                lastCredentialCheck = Date()
            } else {
                clearCache()
                throw APIError.unauthorized
            }
        }

        guard let url = URL(string: usageEndpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/1.0.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown(0)
        }

        if let jsonString = String(data: data, encoding: .utf8) {
            print("OAuth API Response (\(httpResponse.statusCode)): \(jsonString.prefix(500))")
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseOAuthUsageResponse(data)
        case 401, 403:
            // Try refresh once
            if let refreshToken = creds.refreshToken {
                do {
                    let newCreds = try await refreshAccessToken(refreshToken: refreshToken)
                    cachedCredentials = newCreds
                    lastCredentialCheck = Date()

                    var retryRequest = request
                    retryRequest.setValue("Bearer \(newCreds.accessToken)", forHTTPHeaderField: "Authorization")
                    let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
                    guard let retryHttp = retryResponse as? HTTPURLResponse, retryHttp.statusCode == 200 else {
                        clearCache()
                        throw APIError.unauthorized
                    }
                    return try parseOAuthUsageResponse(retryData)
                } catch {
                    clearCache()
                    throw APIError.unauthorized
                }
            }
            clearCache()
            throw APIError.unauthorized
        default:
            throw APIError.unknown(httpResponse.statusCode)
        }
    }

    // MARK: - Token Refresh

    private func refreshAccessToken(refreshToken: String) async throws -> OAuthCredentials {
        guard let url = URL(string: tokenEndpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: oauthClientId)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.unauthorized
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw APIError.decodingError(NSError(domain: "OAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid refresh response"]))
        }

        let newRefreshToken = json["refresh_token"] as? String ?? refreshToken
        var expiresAt: Date?
        if let expiresIn = json["expires_in"] as? Double {
            expiresAt = Date().addingTimeInterval(expiresIn)
        }

        return OAuthCredentials(
            accessToken: accessToken,
            refreshToken: newRefreshToken,
            expiresAt: expiresAt,
            scopes: cachedCredentials?.scopes ?? []
        )
    }

    // MARK: - Parse Response

    private func parseOAuthUsageResponse(_ data: Data) throws -> UsageData {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError(NSError(domain: "JSON", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"]))
        }

        var usageData = UsageData()

        if let fiveHour = json["five_hour"] as? [String: Any] {
            if let utilization = fiveHour["utilization"] as? Double {
                usageData.fiveHourUsed = Int(utilization)
                usageData.fiveHourLimit = 100
            }
            if let resetsAt = fiveHour["resets_at"] as? String {
                usageData.fiveHourResetAt = parseDate(resetsAt)
            }
        }

        if let sevenDay = json["seven_day"] as? [String: Any] {
            if let utilization = sevenDay["utilization"] as? Double {
                usageData.weeklyUsed = Int(utilization)
                usageData.weeklyLimit = 100
            }
            if let resetsAt = sevenDay["resets_at"] as? String {
                usageData.weeklyResetAt = parseDate(resetsAt)
            }
        }

        return usageData
    }

    private func parseDate(_ string: String) -> Date? {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601.date(from: string) { return date }
        iso8601.formatOptions = [.withInternetDateTime]
        return iso8601.date(from: string)
    }
}
