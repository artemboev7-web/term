import Foundation

// MARK: - WebSocket Data Source

/// Remote terminal data source that connects to codeboev.tech via WebSocket.
/// Conforms to TerminalDataSource — drop-in replacement for LocalDataSource.
public final class WebSocketDataSource: TerminalDataSource {
    public weak var delegate: TerminalDataSourceDelegate?

    public private(set) var connectionState: ConnectionState = .disconnected {
        didSet {
            guard connectionState != oldValue else { return }
            delegate?.dataSource(self, didChangeState: connectionState)
            NotificationCenter.default.post(name: .connectionStateChanged, object: self, userInfo: ["state": connectionState])
        }
    }
    public private(set) var cols: Int = 80
    public private(set) var rows: Int = 24

    private let serverURL: String
    private let sessionId: String
    private let authToken: String

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pingTimer: Timer?

    // Reconnect state
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private var reconnectTimer: Timer?
    private var shouldReconnect = true

    // MARK: - Init

    public init(serverURL: String, sessionId: String, authToken: String) {
        self.serverURL = serverURL
        self.sessionId = sessionId
        self.authToken = authToken
    }

    deinit {
        shouldReconnect = false
        stop()
    }

    // MARK: - TerminalDataSource

    public func start() {
        shouldReconnect = true
        connect()
    }

    public func stop() {
        shouldReconnect = false
        connectionState = .disconnected

        pingTimer?.invalidate()
        pingTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil

        // Detach before closing
        if let task = webSocketTask {
            sendDetach()
            task.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
        }

        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    public func write(_ data: Data) {
        // Convert bytes to base64 for safe JSON transport
        let base64 = data.base64EncodedString()
        sendJSON(WSSessionTerminalInput(sessionId: sessionId, data: base64))
    }

    public func write(_ string: String) {
        sendJSON(WSSessionTerminalInput(sessionId: sessionId, data: string))
    }

    public func sendKey(_ key: TerminalKey, modifiers: TerminalModifiers) {
        // Encode key to escape sequence (same logic as PTYManager)
        let sequence = encodeKey(key, modifiers: modifiers)
        write(sequence)
    }

    public func resize(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        sendJSON(WSSessionTerminalResize(sessionId: sessionId, cols: cols, rows: rows))
    }

    // MARK: - Connection

    private func connect() {
        // Build WebSocket URL
        let wsURL: String
        if serverURL.hasPrefix("https://") {
            wsURL = serverURL.replacingOccurrences(of: "https://", with: "wss://") + "/ws"
        } else if serverURL.hasPrefix("http://") {
            wsURL = serverURL.replacingOccurrences(of: "http://", with: "ws://") + "/ws"
        } else {
            wsURL = "wss://\(serverURL)/ws"
        }

        guard let url = URL(string: wsURL) else {
            logError("Invalid WebSocket URL: \(wsURL)", context: "WebSocket")
            connectionState = .disconnected
            return
        }

        connectionState = reconnectAttempts > 0 ? .reconnecting : .connecting
        logInfo("Connecting to \(wsURL) (attempt \(reconnectAttempts + 1))", context: "WebSocket")

        // Create URL request with cookie for auto-auth
        var request = URLRequest(url: url)
        request.setValue("auth_token=\(authToken)", forHTTPHeaderField: "Cookie")

        let session = URLSession(configuration: .default)
        urlSession = session

        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        // Start receiving messages
        receiveMessage()

        // Send explicit auth message as backup
        sendJSON(WSAuthMessage(token: authToken))
    }

    private func reconnect() {
        guard shouldReconnect, reconnectAttempts < maxReconnectAttempts else {
            logError("Max reconnect attempts reached", context: "WebSocket")
            connectionState = .disconnected
            delegate?.dataSource(self, didDisconnect: .networkError(
                NSError(domain: "WebSocket", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max reconnect attempts reached"])
            ))
            return
        }

        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Exponential backoff, max 30s
        connectionState = .reconnecting

        logInfo("Reconnecting in \(delay)s (attempt \(reconnectAttempts))", context: "WebSocket")

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }

    // MARK: - Send

    private func sendJSON<T: Encodable>(_ message: T) {
        guard let task = webSocketTask else { return }

        do {
            let data = try JSONEncoder().encode(message)
            guard let string = String(data: data, encoding: .utf8) else { return }
            task.send(.string(string)) { [weak self] error in
                if let error = error {
                    logError("Send error: \(error.localizedDescription)", context: "WebSocket")
                    self?.handleDisconnect(error: error)
                }
            }
        } catch {
            logError("JSON encode error: \(error.localizedDescription)", context: "WebSocket")
        }
    }

    private func sendDetach() {
        sendJSON(WSSessionTerminalDetach(sessionId: sessionId))
    }

    private func sendAttach() {
        logInfo("Attaching to session \(sessionId) (\(cols)x\(rows))", context: "WebSocket")
        sendJSON(WSSessionTerminalAttach(sessionId: sessionId, cols: cols, rows: rows))
    }

    // MARK: - Receive

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue receiving
                self.receiveMessage()

            case .failure(let error):
                logError("Receive error: \(error.localizedDescription)", context: "WebSocket")
                self.handleDisconnect(error: error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let jsonString: String
        switch message {
        case .string(let text):
            jsonString = text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else { return }
            jsonString = text
        @unknown default:
            return
        }

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return
        }

        let msg = WSIncomingMessage(json: json)

        DispatchQueue.main.async { [weak self] in
            self?.processMessage(msg)
        }
    }

    private func processMessage(_ msg: WSIncomingMessage) {
        switch msg {
        case .authenticated:
            logInfo("Authenticated, attaching to session", context: "WebSocket")
            connectionState = .connected
            reconnectAttempts = 0
            startPingTimer()
            sendAttach()

        case .sessionTerminalAttached(_, let scrollback, _):
            logInfo("Terminal attached, scrollback: \(scrollback?.count ?? 0) bytes", context: "WebSocket")

            // Feed scrollback content to restore terminal state
            if let scrollback = scrollback, !scrollback.isEmpty {
                if let data = scrollback.data(using: .utf8) {
                    delegate?.dataSource(self, didReceiveData: data)
                }
            }

        case .sessionTerminalOutput(_, let data):
            // Terminal output — feed to TerminalEmulator
            // Data can be either plain text or base64
            if let rawData = Data(base64Encoded: data) {
                delegate?.dataSource(self, didReceiveData: rawData)
            } else if let rawData = data.data(using: .utf8) {
                delegate?.dataSource(self, didReceiveData: rawData)
            }

        case .sessionTerminalError(_, let error):
            logError("Session terminal error: \(error)", context: "WebSocket")

        case .sessionTerminalDetached:
            logInfo("Session terminal detached", context: "WebSocket")

        case .error(let message, let code):
            logError("Server error [\(code ?? "unknown")]: \(message)", context: "WebSocket")
            if code == "AUTH_REQUIRED" || code == "AUTH_FAILED" {
                connectionState = .disconnected
                delegate?.dataSource(self, didDisconnect: .authExpired)
            }

        case .serverShutdown:
            logWarning("Server shutting down", context: "WebSocket")
            reconnect()

        case .pong:
            break

        case .unknown:
            break
        }
    }

    // MARK: - Disconnect Handling

    private func handleDisconnect(error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.shouldReconnect else { return }
            self.pingTimer?.invalidate()
            self.pingTimer = nil
            self.webSocketTask = nil
            self.reconnect()
        }
    }

    // MARK: - Ping

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.webSocketTask?.sendPing { error in
                if let error = error {
                    logError("Ping failed: \(error.localizedDescription)", context: "WebSocket")
                    self?.handleDisconnect(error: error)
                }
            }
        }
    }

    // MARK: - Key Encoding (mirrors PTYManager.encodeKey)

    private func encodeKey(_ key: TerminalKey, modifiers: TerminalModifiers) -> String {
        switch key {
        case .char(let ch):
            if modifiers.contains(.control) {
                let scalar = ch.unicodeScalars.first!
                if scalar.value >= 0x40 && scalar.value < 0x80 {
                    let ctrl = Character(UnicodeScalar(scalar.value & 0x1F)!)
                    if modifiers.contains(.alt) { return "\u{1B}\(ctrl)" }
                    return String(ctrl)
                }
            }
            if modifiers.contains(.alt) { return "\u{1B}\(ch)" }
            return String(ch)

        case .up:    return modifiers.isEmpty ? "\u{1B}[A" : "\u{1B}[1;\(modCode(modifiers))A"
        case .down:  return modifiers.isEmpty ? "\u{1B}[B" : "\u{1B}[1;\(modCode(modifiers))B"
        case .right: return modifiers.isEmpty ? "\u{1B}[C" : "\u{1B}[1;\(modCode(modifiers))C"
        case .left:  return modifiers.isEmpty ? "\u{1B}[D" : "\u{1B}[1;\(modCode(modifiers))D"
        case .home:  return modifiers.isEmpty ? "\u{1B}[H" : "\u{1B}[1;\(modCode(modifiers))H"
        case .end:   return modifiers.isEmpty ? "\u{1B}[F" : "\u{1B}[1;\(modCode(modifiers))F"
        case .pageUp:   return modifiers.isEmpty ? "\u{1B}[5~" : "\u{1B}[5;\(modCode(modifiers))~"
        case .pageDown: return modifiers.isEmpty ? "\u{1B}[6~" : "\u{1B}[6;\(modCode(modifiers))~"
        case .insert: return "\u{1B}[2~"
        case .delete: return modifiers.isEmpty ? "\u{1B}[3~" : "\u{1B}[3;\(modCode(modifiers))~"
        case .f1:  return modifiers.isEmpty ? "\u{1B}OP" : "\u{1B}[1;\(modCode(modifiers))P"
        case .f2:  return modifiers.isEmpty ? "\u{1B}OQ" : "\u{1B}[1;\(modCode(modifiers))Q"
        case .f3:  return modifiers.isEmpty ? "\u{1B}OR" : "\u{1B}[1;\(modCode(modifiers))R"
        case .f4:  return modifiers.isEmpty ? "\u{1B}OS" : "\u{1B}[1;\(modCode(modifiers))S"
        case .f5:  return "\u{1B}[15~"
        case .f6:  return "\u{1B}[17~"
        case .f7:  return "\u{1B}[18~"
        case .f8:  return "\u{1B}[19~"
        case .f9:  return "\u{1B}[20~"
        case .f10: return "\u{1B}[21~"
        case .f11: return "\u{1B}[23~"
        case .f12: return "\u{1B}[24~"
        case .tab:       return modifiers.contains(.shift) ? "\u{1B}[Z" : "\t"
        case .backspace: return modifiers.contains(.alt) ? "\u{1B}\u{7F}" : "\u{7F}"
        case .enter:     return "\r"
        case .escape:    return "\u{1B}"
        }
    }

    private func modCode(_ modifiers: TerminalModifiers) -> Int {
        var code = 1
        if modifiers.contains(.shift) { code += 1 }
        if modifiers.contains(.alt) { code += 2 }
        if modifiers.contains(.control) { code += 4 }
        return code
    }
}
