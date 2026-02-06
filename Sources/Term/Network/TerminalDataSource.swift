import Foundation

// MARK: - Terminal Data Source Protocol

/// Abstraction over data transport (local PTY or remote WebSocket).
/// InputHandler and TerminalPaneView use this instead of PTYManager directly.
public protocol TerminalDataSource: AnyObject {
    var delegate: TerminalDataSourceDelegate? { get set }
    var connectionState: ConnectionState { get }
    var cols: Int { get }
    var rows: Int { get }

    func start()
    func stop()
    func write(_ data: Data)
    func write(_ string: String)
    func sendKey(_ key: TerminalKey, modifiers: TerminalModifiers)
    func resize(cols: Int, rows: Int)
}

// MARK: - Delegate

public protocol TerminalDataSourceDelegate: AnyObject {
    /// Received output data (ANSI bytes) to feed into TerminalEmulator
    func dataSource(_ source: TerminalDataSource, didReceiveData data: Data)

    /// Connection/process ended
    func dataSource(_ source: TerminalDataSource, didDisconnect reason: DisconnectReason)
}

// MARK: - Connection State

public enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

// MARK: - Disconnect Reason

public enum DisconnectReason {
    case processExited(Int32)
    case networkError(Error)
    case authExpired
    case serverClosed
    case userRequested
}
