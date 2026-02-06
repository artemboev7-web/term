import Foundation
import Security

// MARK: - Auth Manager

/// Manages authentication state, token storage in Keychain, and auto-refresh
final class AuthManager {
    static let shared = AuthManager()

    private let keychainService = "tech.codeboev.term"
    private let tokenKey = "auth_token"
    private let refreshTokenKey = "refresh_token"
    private let serverURLKey = "server_url"

    /// Current auth token (in memory for fast access)
    private(set) var authToken: String?

    /// Current refresh token
    private(set) var refreshToken: String?

    /// Current user info
    private(set) var currentUser: UserInfo?

    /// Server URL
    var serverURL: String {
        get { UserDefaults.standard.string(forKey: serverURLKey) ?? "https://codeboev.tech" }
        set { UserDefaults.standard.set(newValue, forKey: serverURLKey) }
    }

    private init() {
        // Load tokens from Keychain on init
        authToken = loadFromKeychain(key: tokenKey)
        refreshToken = loadFromKeychain(key: refreshTokenKey)
    }

    // MARK: - Public API

    /// Whether we have a saved session (token exists)
    var hasValidSession: Bool {
        return authToken != nil
    }

    /// Login with username and password
    func login(username: String, password: String) async throws -> UserInfo {
        let url = URL(string: "\(serverURL)/api/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["username": username, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw AuthError.invalidCredentials
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(APIError.self, from: data) {
                throw AuthError.serverError(errorResponse.message)
            }
            throw AuthError.serverError("HTTP \(httpResponse.statusCode)")
        }

        // Extract auth_token from Set-Cookie header (server uses cookie-based auth)
        if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            for cookie in cookies {
                if cookie.name == "auth_token" {
                    authToken = cookie.value
                    saveToKeychain(key: tokenKey, value: cookie.value)
                }
                if cookie.name == "refresh_token" {
                    self.refreshToken = cookie.value
                    saveToKeychain(key: refreshTokenKey, value: cookie.value)
                }
            }
        }

        // Also try to decode from JSON response body
        let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
        if authToken == nil {
            authToken = loginResponse.token
            saveToKeychain(key: tokenKey, value: loginResponse.token)
        }
        if let rt = loginResponse.refreshToken, refreshToken == nil {
            refreshToken = rt
            saveToKeychain(key: refreshTokenKey, value: rt)
        }

        currentUser = loginResponse.user
        return loginResponse.user
    }

    /// Verify current token is valid
    func verify() async -> Bool {
        guard let token = authToken else { return false }

        let url = URL(string: "\(serverURL)/api/auth/verify")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            let verifyResponse = try JSONDecoder().decode(AuthVerifyResponse.self, from: data)
            if verifyResponse.valid, let user = verifyResponse.user {
                currentUser = user
            }
            return verifyResponse.valid
        } catch {
            return false
        }
    }

    /// Refresh access token using refresh token
    func refreshAccessToken() async throws {
        guard let rt = refreshToken else {
            throw AuthError.noRefreshToken
        }

        let url = URL(string: "\(serverURL)/api/auth/refresh")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["refreshToken": rt]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.refreshFailed
        }

        // Extract new token from cookies
        if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            for cookie in cookies {
                if cookie.name == "auth_token" {
                    authToken = cookie.value
                    saveToKeychain(key: tokenKey, value: cookie.value)
                }
            }
        }

        // Also try JSON body
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = json["token"] as? String {
            authToken = token
            saveToKeychain(key: tokenKey, value: token)
        }
    }

    /// Logout — clear all tokens
    func logout() {
        authToken = nil
        refreshToken = nil
        currentUser = nil
        deleteFromKeychain(key: tokenKey)
        deleteFromKeychain(key: refreshTokenKey)

        // Clear cookies
        if let url = URL(string: serverURL) {
            if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
                for cookie in cookies {
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
            }
        }
    }

    // MARK: - Keychain

    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidCredentials
    case networkError
    case serverError(String)
    case noRefreshToken
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Invalid username or password"
        case .networkError: return "Network error"
        case .serverError(let msg): return msg
        case .noRefreshToken: return "No refresh token"
        case .refreshFailed: return "Token refresh failed"
        }
    }
}
