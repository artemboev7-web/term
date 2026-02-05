import Foundation

// MARK: - PTY Delegate

public protocol PTYManagerDelegate: AnyObject {
    /// Received data from PTY
    func ptyManager(_ manager: PTYManager, didReceiveData data: Data)

    /// Process terminated
    func ptyManager(_ manager: PTYManager, processTerminated exitCode: Int32)
}

// MARK: - PTY Manager

/// Manages pseudo-terminal and child process
public final class PTYManager {
    public weak var delegate: PTYManagerDelegate?

    /// Master file descriptor
    private var masterFD: Int32 = -1

    /// Slave file descriptor
    private var slaveFD: Int32 = -1

    /// Child process PID
    private var childPID: pid_t = 0

    /// Read source for dispatch
    private var readSource: DispatchSourceRead?

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
    private let environment: [String: String]

    // MARK: - Initialization

    public init(
        shell: String = "/bin/zsh",
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) {
        self.shell = shell
        self.workingDirectory = workingDirectory

        // Build environment
        var env: [String: String] = [:]

        // Copy current environment
        for (key, value) in ProcessInfo.processInfo.environment {
            env[key] = value
        }

        // Set terminal type
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"

        // Override with custom environment
        if let custom = environment {
            for (key, value) in custom {
                env[key] = value
            }
        }

        self.environment = env
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Start the PTY and shell process
    public func start() -> Bool {
        guard !isRunning else { return true }

        // Open PTY
        guard openPTY() else {
            logError("Failed to open PTY", context: "PTY")
            return false
        }

        // Fork and exec
        guard forkAndExec() else {
            logError("Failed to fork", context: "PTY")
            closePTY()
            return false
        }

        // Setup read handler
        setupReadHandler()

        isRunning = true
        logInfo("PTY started: shell=\(shell), pid=\(childPID)", context: "PTY")
        return true
    }

    /// Stop the PTY and kill process
    public func stop() {
        guard isRunning else { return }

        // Cancel read source
        readSource?.cancel()
        readSource = nil

        // Kill child process
        if childPID > 0 {
            kill(childPID, SIGTERM)
            var status: Int32 = 0
            waitpid(childPID, &status, 0)
            childPID = 0
        }

        // Close PTY
        closePTY()

        isRunning = false
        logInfo("PTY stopped", context: "PTY")
    }

    // MARK: - I/O

    /// Write data to PTY
    public func write(_ data: Data) {
        guard isRunning && masterFD >= 0 else { return }

        data.withUnsafeBytes { ptr in
            guard let bytes = ptr.baseAddress else { return }
            _ = Darwin.write(masterFD, bytes, data.count)
        }
    }

    /// Write string to PTY
    public func write(_ string: String) {
        write(Data(string.utf8))
    }

    /// Send special key
    public func sendKey(_ key: TerminalKey, modifiers: TerminalModifiers = []) {
        let data = key.escapeSequence(modifiers: modifiers, applicationCursor: false)
        write(data)
    }

    // MARK: - Resize

    /// Resize the PTY
    public func resize(cols: Int, rows: Int) {
        guard masterFD >= 0 else { return }

        self.cols = cols
        self.rows = rows

        var size = winsize()
        size.ws_col = UInt16(cols)
        size.ws_row = UInt16(rows)
        size.ws_xpixel = 0
        size.ws_ypixel = 0

        _ = ioctl(masterFD, TIOCSWINSZ, &size)
        logDebug("PTY resized: \(cols)x\(rows)", context: "PTY")
    }

    // MARK: - Private Methods

    private func openPTY() -> Bool {
        // Open master
        masterFD = posix_openpt(O_RDWR | O_NOCTTY)
        guard masterFD >= 0 else { return false }

        // Grant and unlock
        guard grantpt(masterFD) == 0, unlockpt(masterFD) == 0 else {
            close(masterFD)
            masterFD = -1
            return false
        }

        // Get slave name
        guard let slaveName = ptsname(masterFD) else {
            close(masterFD)
            masterFD = -1
            return false
        }

        // Open slave
        slaveFD = open(slaveName, O_RDWR | O_NOCTTY)
        guard slaveFD >= 0 else {
            close(masterFD)
            masterFD = -1
            return false
        }

        // Set initial size
        resize(cols: cols, rows: rows)

        return true
    }

    private func closePTY() {
        if slaveFD >= 0 {
            close(slaveFD)
            slaveFD = -1
        }
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
    }

    private func forkAndExec() -> Bool {
        childPID = fork()

        if childPID < 0 {
            // Fork failed
            return false
        }

        if childPID == 0 {
            // Child process
            setupChildProcess()
            // If we get here, exec failed
            exit(1)
        }

        // Parent process
        // Close slave in parent
        close(slaveFD)
        slaveFD = -1

        return true
    }

    private func setupChildProcess() {
        // Create new session
        setsid()

        // Set controlling terminal
        _ = ioctl(slaveFD, TIOCSCTTY, 0)

        // Redirect standard streams
        dup2(slaveFD, STDIN_FILENO)
        dup2(slaveFD, STDOUT_FILENO)
        dup2(slaveFD, STDERR_FILENO)

        // Close extra FDs
        if slaveFD > STDERR_FILENO {
            close(slaveFD)
        }
        close(masterFD)

        // Change directory
        if let dir = workingDirectory {
            chdir(dir)
        } else if let home = environment["HOME"] {
            chdir(home)
        }

        // Build environment array
        var envp: [UnsafeMutablePointer<CChar>?] = []
        var envStrings: [String] = []

        for (key, value) in environment {
            envStrings.append("\(key)=\(value)")
        }

        for str in envStrings {
            envp.append(strdup(str))
        }
        envp.append(nil)

        // Build arguments
        let shellName = (shell as NSString).lastPathComponent
        let argv: [UnsafeMutablePointer<CChar>?] = [
            strdup("-\(shellName)"),  // Login shell
            nil
        ]

        // Execute
        execve(shell, argv, envp)

        // If we get here, exec failed
        perror("execve")
        _exit(127)
    }

    private func setupReadHandler() {
        guard masterFD >= 0 else { return }

        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: .main)

        source.setEventHandler { [weak self] in
            self?.handleReadEvent()
        }

        source.setCancelHandler { [weak self] in
            self?.handleCancel()
        }

        source.resume()
        readSource = source
    }

    private func handleReadEvent() {
        guard masterFD >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = read(masterFD, &buffer, buffer.count)

        if bytesRead > 0 {
            let data = Data(buffer[0..<bytesRead])
            delegate?.ptyManager(self, didReceiveData: data)
        } else if bytesRead < 0 && errno != EAGAIN && errno != EINTR {
            // Error or EOF
            handleProcessTermination()
        }
    }

    private func handleCancel() {
        logDebug("Read source cancelled", context: "PTY")
    }

    private func handleProcessTermination() {
        var status: Int32 = 0
        let result = waitpid(childPID, &status, WNOHANG)

        if result > 0 {
            let exitCode: Int32
            if WIFEXITED(status) {
                exitCode = WEXITSTATUS(status)
            } else if WIFSIGNALED(status) {
                exitCode = Int32(128 + WTERMSIG(status))
            } else {
                exitCode = -1
            }

            isRunning = false
            delegate?.ptyManager(self, processTerminated: exitCode)
        }
    }
}

// MARK: - Terminal Keys

/// Terminal key codes
public enum TerminalKey {
    case enter
    case tab
    case backspace
    case escape
    case delete

    case up, down, left, right
    case home, end
    case pageUp, pageDown
    case insert

    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    /// Get escape sequence for key
    func escapeSequence(modifiers: TerminalModifiers, applicationCursor: Bool) -> Data {
        let mod = modifiers.isEmpty ? "" : "1;\(modifiers.csiModifier)"

        let sequence: String
        switch self {
        case .enter: sequence = "\r"
        case .tab: sequence = modifiers.contains(.shift) ? "\u{1B}[Z" : "\t"
        case .backspace: sequence = "\u{7F}"
        case .escape: sequence = "\u{1B}"
        case .delete: sequence = "\u{1B}[3~"

        case .up:    sequence = applicationCursor ? "\u{1B}OA" : "\u{1B}[\(mod)A"
        case .down:  sequence = applicationCursor ? "\u{1B}OB" : "\u{1B}[\(mod)B"
        case .right: sequence = applicationCursor ? "\u{1B}OC" : "\u{1B}[\(mod)C"
        case .left:  sequence = applicationCursor ? "\u{1B}OD" : "\u{1B}[\(mod)D"

        case .home:   sequence = "\u{1B}[\(mod)H"
        case .end:    sequence = "\u{1B}[\(mod)F"
        case .pageUp: sequence = "\u{1B}[5\(mod.isEmpty ? "" : ";\(mod)")~"
        case .pageDown: sequence = "\u{1B}[6\(mod.isEmpty ? "" : ";\(mod)")~"
        case .insert: sequence = "\u{1B}[2~"

        case .f1:  sequence = "\u{1B}OP"
        case .f2:  sequence = "\u{1B}OQ"
        case .f3:  sequence = "\u{1B}OR"
        case .f4:  sequence = "\u{1B}OS"
        case .f5:  sequence = "\u{1B}[15~"
        case .f6:  sequence = "\u{1B}[17~"
        case .f7:  sequence = "\u{1B}[18~"
        case .f8:  sequence = "\u{1B}[19~"
        case .f9:  sequence = "\u{1B}[20~"
        case .f10: sequence = "\u{1B}[21~"
        case .f11: sequence = "\u{1B}[23~"
        case .f12: sequence = "\u{1B}[24~"
        }

        return Data(sequence.utf8)
    }
}

/// Terminal modifiers
public struct TerminalModifiers: OptionSet {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift   = TerminalModifiers(rawValue: 1 << 0)
    public static let alt     = TerminalModifiers(rawValue: 1 << 1)
    public static let control = TerminalModifiers(rawValue: 1 << 2)
    public static let meta    = TerminalModifiers(rawValue: 1 << 3)

    /// CSI modifier parameter
    var csiModifier: Int {
        var m = 1
        if contains(.shift)   { m += 1 }
        if contains(.alt)     { m += 2 }
        if contains(.control) { m += 4 }
        if contains(.meta)    { m += 8 }
        return m
    }
}
