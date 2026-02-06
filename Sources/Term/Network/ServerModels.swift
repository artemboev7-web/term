import Foundation

// MARK: - Server API Models

/// Login response from POST /api/auth/login
struct LoginResponse: Codable {
    let token: String
    let refreshToken: String?
    let user: UserInfo
}

/// User info
struct UserInfo: Codable {
    let id: String?
    let username: String
    let role: String?
}

/// Auth verify response from GET /api/auth/verify
struct AuthVerifyResponse: Codable {
    let valid: Bool
    let user: UserInfo?
}

/// Project from GET /api/projects
struct Project: Codable {
    let path: String
    let name: String
    let gitBranch: String?
    let lastCommit: String?

    enum CodingKeys: String, CodingKey {
        case path, name
        case gitBranch = "git_branch"
        case lastCommit = "last_commit"
    }

    /// Display name (last path component)
    var displayName: String {
        name.isEmpty ? (path as NSString).lastPathComponent : name
    }
}

/// Session creation response from POST /api/sessions
struct SessionResponse: Codable {
    let id: String
    let name: String?
    let provider: String?
    let model: String?
    let mode: String?
}

/// Error response from API
struct APIError: Codable {
    let message: String
    let code: String?
}

// MARK: - WebSocket Messages

/// Message sent to server
struct WSOutgoingMessage: Encodable {
    let type: String
    // Additional fields are added per-message type
}

/// Auth message
struct WSAuthMessage: Encodable {
    let type = "auth"
    let token: String
}

/// Session terminal attach
struct WSSessionTerminalAttach: Encodable {
    let type = "session-terminal-attach"
    let sessionId: String
    let cols: Int
    let rows: Int
}

/// Session terminal input
struct WSSessionTerminalInput: Encodable {
    let type = "session-terminal-input"
    let sessionId: String
    let data: String
}

/// Session terminal resize
struct WSSessionTerminalResize: Encodable {
    let type = "session-terminal-resize"
    let sessionId: String
    let cols: Int
    let rows: Int
}

/// Session terminal detach
struct WSSessionTerminalDetach: Encodable {
    let type = "session-terminal-detach"
    let sessionId: String
}

// MARK: - Incoming WS Message Types

/// Parsed incoming WebSocket message
enum WSIncomingMessage {
    case authenticated(version: String?)
    case sessionTerminalAttached(sessionId: String, scrollback: String?, mode: String?)
    case sessionTerminalOutput(sessionId: String, data: String)
    case sessionTerminalError(sessionId: String, error: String)
    case sessionTerminalDetached(sessionId: String)
    case error(message: String, code: String?)
    case pong
    case serverShutdown
    case unknown(type: String)

    init(json: [String: Any]) {
        guard let type = json["type"] as? String else {
            self = .unknown(type: "nil")
            return
        }

        switch type {
        case "authenticated":
            self = .authenticated(version: json["version"] as? String)

        case "session-terminal-attached":
            self = .sessionTerminalAttached(
                sessionId: json["sessionId"] as? String ?? "",
                scrollback: json["scrollback"] as? String,
                mode: json["mode"] as? String
            )

        case "session-terminal-output":
            self = .sessionTerminalOutput(
                sessionId: json["sessionId"] as? String ?? "",
                data: json["data"] as? String ?? ""
            )

        case "session-terminal-error":
            self = .sessionTerminalError(
                sessionId: json["sessionId"] as? String ?? "",
                error: json["error"] as? String ?? "Unknown error"
            )

        case "session-terminal-detached":
            self = .sessionTerminalDetached(
                sessionId: json["sessionId"] as? String ?? ""
            )

        case "error":
            self = .error(
                message: json["message"] as? String ?? "Unknown error",
                code: json["code"] as? String
            )

        case "pong":
            self = .pong

        case "server-shutdown":
            self = .serverShutdown

        default:
            self = .unknown(type: type)
        }
    }
}
