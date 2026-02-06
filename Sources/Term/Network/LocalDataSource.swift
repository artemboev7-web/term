import Foundation

// MARK: - Local Data Source

/// Wraps PTYManager to conform to TerminalDataSource.
/// Used in local terminal mode (no network).
public final class LocalDataSource: TerminalDataSource, PTYManagerDelegate {
    public weak var delegate: TerminalDataSourceDelegate?

    public private(set) var connectionState: ConnectionState = .disconnected

    public var cols: Int { ptyManager.cols }
    public var rows: Int { ptyManager.rows }

    private let ptyManager: PTYManager

    public init(ptyManager: PTYManager) {
        self.ptyManager = ptyManager
        self.ptyManager.delegate = self
    }

    // MARK: - TerminalDataSource

    public func start() {
        connectionState = .connecting
        if ptyManager.start() {
            connectionState = .connected
        } else {
            connectionState = .disconnected
        }
    }

    public func stop() {
        ptyManager.stop()
        connectionState = .disconnected
    }

    public func write(_ data: Data) {
        ptyManager.write(data)
    }

    public func write(_ string: String) {
        ptyManager.write(string)
    }

    public func sendKey(_ key: TerminalKey, modifiers: TerminalModifiers) {
        ptyManager.sendKey(key, modifiers: modifiers)
    }

    public func resize(cols: Int, rows: Int) {
        ptyManager.resize(cols: cols, rows: rows)
    }

    // MARK: - PTYManagerDelegate

    public func ptyManager(_ manager: PTYManager, didReceiveData data: Data) {
        delegate?.dataSource(self, didReceiveData: data)
    }

    public func ptyManager(_ manager: PTYManager, processTerminated exitCode: Int32) {
        connectionState = .disconnected
        delegate?.dataSource(self, didDisconnect: .processExited(exitCode))
    }
}
