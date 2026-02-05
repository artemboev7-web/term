import Foundation
import Darwin

// MARK: - PTY Delegate

public protocol PTYManagerDelegate: AnyObject {
    /// Received data from PTY
    func ptyManager(_ manager: PTYManager, didReceiveData data: Data)

    /// Process terminated
    func ptyManager(_ manager: PTYManager, processTerminated exitCode: Int32)
}

// MARK: - PTY Manager

/// Manages pseudo-terminal and child process using Foundation Process
public final class PTYManager {
    public weak var delegate: PTYManagerDelegate?

    /// Master file descriptor
    private var masterFD: Int32 = -1

    /// File handle for reading from master
    private var masterReadHandle: FileHandle?

    /// Child process
    private var process: Process?

    /// Is running
    public private(set) var isRunning: Bool = false

    /// Terminal size
    public private(set) var cols: Int = 80
    public private(set) var rows: Int = 24

    /// Shell path
    private let shell: String

    /// Working directory
    private let workingDirectory: String?

    /// Environment variables
    private var environment: [String: String]

    // MARK: - Initialization

    public init(
        shell: String = "/bin/zsh",
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) {
        self.shell = shell
        self.workingDirectory = workingDirectory

        // Build default environment
        var env: [String: String] = [:]

        // Copy current environment
        for (key, value) in ProcessInfo.processInfo.environment {
            env[key] = value
        }

        // Override with provided environment
        if let provided = environment {
            for (key, value) in provided {
                env[key] = value
            }
        }

        // Set terminal type
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"

        self.environment = env
    }

    deinit {
        stop()
    }

    // MARK: - Start/Stop

    public func start() -> Bool {
        guard !isRunning else { return true }

        // Create PTY pair using posix_openpt
        guard createPTY() else {
            return false
        }

        // Start shell process
        guard startProcess() else {
            closePTY()
            return false
        }

        // Start reading from master
        startReading()

        isRunning = true
        return true
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        // Terminate process
        if let process = process, process.isRunning {
            process.terminate()
        }
        process = nil

        // Close master
        closePTY()
    }

    // MARK: - I/O

    public func write(_ data: Data) {
        guard masterFD >= 0, !data.isEmpty else { return }

        data.withUnsafeBytes { buffer in
            if let ptr = buffer.baseAddress {
                _ = Darwin.write(masterFD, ptr, data.count)
            }
        }
    }

    public func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            write(data)
        }
    }

    // MARK: - Resize

    public func resize(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows

        guard masterFD >= 0 else { return }

        var size = winsize()
        size.ws_col = UInt16(cols)
        size.ws_row = UInt16(rows)
        size.ws_xpixel = 0
        size.ws_ypixel = 0

        _ = ioctl(masterFD, TIOCSWINSZ, &size)
    }

    // MARK: - PTY Creation

    private func createPTY() -> Bool {
        // Open master pseudo-terminal
        masterFD = posix_openpt(O_RDWR | O_NOCTTY)
        guard masterFD >= 0 else {
            return false
        }

        // Grant access to slave
        guard grantpt(masterFD) == 0 else {
            closePTY()
            return false
        }

        // Unlock slave
        guard unlockpt(masterFD) == 0 else {
            closePTY()
            return false
        }

        // Set initial size
        var size = winsize()
        size.ws_col = UInt16(cols)
        size.ws_row = UInt16(rows)
        _ = ioctl(masterFD, TIOCSWINSZ, &size)

        return true
    }

    private func closePTY() {
        masterReadHandle = nil

        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
    }

    // MARK: - Process

    private func startProcess() -> Bool {
        // Get slave device path
        guard let slavePath = ptsname(masterFD).map({ String(cString: $0) }) else {
            return false
        }

        // Open slave for process
        let slaveFD = open(slavePath, O_RDWR)
        guard slaveFD >= 0 else {
            return false
        }

        // Create file handles for slave
        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)

        // Create process
        let proc = Process()

        // Set executable
        proc.executableURL = URL(fileURLWithPath: shell)

        // Login shell argument
        proc.arguments = ["-l"]  // Login shell

        // Set working directory
        if let dir = workingDirectory {
            proc.currentDirectoryURL = URL(fileURLWithPath: dir)
        } else if let home = environment["HOME"] {
            proc.currentDirectoryURL = URL(fileURLWithPath: home)
        }

        // Set environment
        proc.environment = environment

        // Connect to PTY slave
        proc.standardInput = slaveHandle
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle

        // Set up termination handler
        proc.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.handleProcessTermination(exitCode: process.terminationStatus)
            }
        }

        // Start process
        do {
            try proc.run()
            self.process = proc
            return true
        } catch {
            close(slaveFD)
            return false
        }
    }

    private func handleProcessTermination(exitCode: Int32) {
        isRunning = false
        delegate?.ptyManager(self, processTerminated: exitCode)
    }

    // MARK: - Reading

    private func startReading() {
        let handle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: false)
        masterReadHandle = handle

        // Read in background
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            if !data.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.ptyManager(self, didReceiveData: data)
                }
            }
        }
    }
}

// MARK: - Terminal Key Encoding

/// Terminal key codes
public enum TerminalKey {
    case char(Character)
    case up, down, left, right
    case home, end
    case pageUp, pageDown
    case insert, delete
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case tab, backspace, enter, escape
}

/// Modifier flags
public struct TerminalModifiers: OptionSet {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let shift   = TerminalModifiers(rawValue: 1 << 0)
    public static let control = TerminalModifiers(rawValue: 1 << 1)
    public static let alt     = TerminalModifiers(rawValue: 1 << 2)
    public static let meta    = TerminalModifiers(rawValue: 1 << 3)
}

extension PTYManager {
    /// Send a key press with modifiers
    public func sendKey(_ key: TerminalKey, modifiers: TerminalModifiers = []) {
        let sequence = encodeKey(key, modifiers: modifiers)
        write(sequence)
    }

    private func encodeKey(_ key: TerminalKey, modifiers: TerminalModifiers) -> String {
        switch key {
        case .char(let ch):
            if modifiers.contains(.control) {
                // Control character
                let scalar = ch.unicodeScalars.first!
                if scalar.value >= 0x40 && scalar.value < 0x80 {
                    let ctrl = Character(UnicodeScalar(scalar.value & 0x1F)!)
                    if modifiers.contains(.alt) {
                        return "\u{1B}\(ctrl)"
                    }
                    return String(ctrl)
                }
            }
            if modifiers.contains(.alt) {
                return "\u{1B}\(ch)"
            }
            return String(ch)

        case .up:
            return modifiers.isEmpty ? "\u{1B}[A" : "\u{1B}[1;\(modifierCode(modifiers))A"
        case .down:
            return modifiers.isEmpty ? "\u{1B}[B" : "\u{1B}[1;\(modifierCode(modifiers))B"
        case .right:
            return modifiers.isEmpty ? "\u{1B}[C" : "\u{1B}[1;\(modifierCode(modifiers))C"
        case .left:
            return modifiers.isEmpty ? "\u{1B}[D" : "\u{1B}[1;\(modifierCode(modifiers))D"

        case .home:
            return modifiers.isEmpty ? "\u{1B}[H" : "\u{1B}[1;\(modifierCode(modifiers))H"
        case .end:
            return modifiers.isEmpty ? "\u{1B}[F" : "\u{1B}[1;\(modifierCode(modifiers))F"

        case .pageUp:
            return modifiers.isEmpty ? "\u{1B}[5~" : "\u{1B}[5;\(modifierCode(modifiers))~"
        case .pageDown:
            return modifiers.isEmpty ? "\u{1B}[6~" : "\u{1B}[6;\(modifierCode(modifiers))~"

        case .insert:
            return "\u{1B}[2~"
        case .delete:
            return modifiers.isEmpty ? "\u{1B}[3~" : "\u{1B}[3;\(modifierCode(modifiers))~"

        case .f1:  return modifiers.isEmpty ? "\u{1B}OP" : "\u{1B}[1;\(modifierCode(modifiers))P"
        case .f2:  return modifiers.isEmpty ? "\u{1B}OQ" : "\u{1B}[1;\(modifierCode(modifiers))Q"
        case .f3:  return modifiers.isEmpty ? "\u{1B}OR" : "\u{1B}[1;\(modifierCode(modifiers))R"
        case .f4:  return modifiers.isEmpty ? "\u{1B}OS" : "\u{1B}[1;\(modifierCode(modifiers))S"
        case .f5:  return "\u{1B}[15~"
        case .f6:  return "\u{1B}[17~"
        case .f7:  return "\u{1B}[18~"
        case .f8:  return "\u{1B}[19~"
        case .f9:  return "\u{1B}[20~"
        case .f10: return "\u{1B}[21~"
        case .f11: return "\u{1B}[23~"
        case .f12: return "\u{1B}[24~"

        case .tab:
            return modifiers.contains(.shift) ? "\u{1B}[Z" : "\t"
        case .backspace:
            return modifiers.contains(.alt) ? "\u{1B}\u{7F}" : "\u{7F}"
        case .enter:
            return "\r"
        case .escape:
            return "\u{1B}"
        }
    }

    private func modifierCode(_ modifiers: TerminalModifiers) -> Int {
        var code = 1
        if modifiers.contains(.shift) { code += 1 }
        if modifiers.contains(.alt) { code += 2 }
        if modifiers.contains(.control) { code += 4 }
        return code
    }
}
