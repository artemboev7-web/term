import Foundation

// MARK: - API Client

/// HTTP client for codeboev.tech REST API
final class APIClient {
    static let shared = APIClient()

    private var baseURL: String { AuthManager.shared.serverURL }

    private init() {}

    // MARK: - Projects

    /// Get list of projects accessible to the user
    func getProjects() async throws -> [Project] {
        let data = try await get("/api/projects")
        return try JSONDecoder().decode([Project].self, from: data)
    }

    // MARK: - Sessions

    /// Create a new session for a project
    func createSession(
        projectPath: String,
        provider: String = "claude",
        model: String = "sonnet",
        mode: String = "terminal"
    ) async throws -> SessionResponse {
        let body: [String: Any] = [
            "name": "Term Remote",
            "project_path": projectPath,
            "provider": provider,
            "model": model,
            "mode": mode,
        ]
        let data = try await post("/api/sessions", body: body)
        return try JSONDecoder().decode(SessionResponse.self, from: data)
    }

    /// Get session info
    func getSession(id: String) async throws -> SessionResponse {
        let data = try await get("/api/sessions/\(id)")
        return try JSONDecoder().decode(SessionResponse.self, from: data)
    }

    /// Get sessions list
    func getSessions(projectPath: String? = nil) async throws -> [SessionResponse] {
        var path = "/api/sessions"
        if let pp = projectPath {
            path += "?project_path=\(pp.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pp)"
        }
        let data = try await get(path)
        return try JSONDecoder().decode([SessionResponse].self, from: data)
    }

    // MARK: - HTTP Helpers

    private func get(_ path: String) async throws -> Data {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeaders(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    private func addAuthHeaders(_ request: inout URLRequest) {
        if let token = AuthManager.shared.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIClientError.unauthorized
        case 403:
            throw APIClientError.forbidden
        case 404:
            throw APIClientError.notFound
        default:
            if let errorResponse = try? JSONDecoder().decode(APIError.self, from: data) {
                throw APIClientError.serverError(errorResponse.message)
            }
            throw APIClientError.serverError("HTTP \(httpResponse.statusCode)")
        }
    }
}

// MARK: - API Client Errors

enum APIClientError: LocalizedError {
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .unauthorized: return "Authentication required"
        case .forbidden: return "Access denied"
        case .notFound: return "Not found"
        case .serverError(let msg): return msg
        }
    }
}
