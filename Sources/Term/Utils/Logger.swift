import Foundation
import os.log

/// Централизованный логгер для Term
class Logger {
    static let shared = Logger()

    private let osLog: OSLog
    private let fileHandle: FileHandle?
    private let logFile: URL
    private let dateFormatter: DateFormatter

    private init() {
        osLog = OSLog(subsystem: "com.term.app", category: "general")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Создаём лог-файл в ~/Library/Logs/Term/
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Term")

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let today = DateFormatter()
        today.dateFormat = "yyyy-MM-dd"
        logFile = logsDir.appendingPathComponent("term-\(today.string(from: Date())).log")

        // Открываем файл для записи
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: logFile)
        fileHandle?.seekToEndOfFile()

        info("Logger initialized", context: "Logger")
        info("Log file: \(logFile.path)", context: "Logger")
    }

    deinit {
        try? fileHandle?.close()
    }

    // MARK: - Public API

    func debug(_ message: String, context: String = "App", file: String = #file, line: Int = #line) {
        log(level: .debug, message: message, context: context, file: file, line: line)
    }

    func info(_ message: String, context: String = "App", file: String = #file, line: Int = #line) {
        log(level: .info, message: message, context: context, file: file, line: line)
    }

    func warning(_ message: String, context: String = "App", file: String = #file, line: Int = #line) {
        log(level: .warning, message: message, context: context, file: file, line: line)
    }

    func error(_ message: String, context: String = "App", file: String = #file, line: Int = #line) {
        log(level: .error, message: message, context: context, file: file, line: line)
    }

    func error(_ message: String, error: Error, context: String = "App", file: String = #file, line: Int = #line) {
        let fullMessage = "\(message): \(error.localizedDescription)"
        log(level: .error, message: fullMessage, context: context, file: file, line: line)
    }

    // MARK: - Private

    private enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"

        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }

        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            }
        }
    }

    private func log(level: Level, message: String, context: String, file: String, line: Int) {
        let timestamp = dateFormatter.string(from: Date())
        let filename = (file as NSString).lastPathComponent

        // Форматированная строка для файла
        let logLine = "[\(timestamp)] [\(level.rawValue)] [\(context)] \(message) (\(filename):\(line))\n"

        // Пишем в файл
        if let data = logLine.data(using: .utf8) {
            fileHandle?.write(data)
        }

        // Пишем в os_log (видно в Console.app)
        os_log("%{public}@ [%{public}@] %{public}@", log: osLog, type: level.osLogType, level.emoji, context, message)

        // Дублируем в stderr для отладки
        #if DEBUG
        fputs(logLine, stderr)
        #endif
    }
}

// MARK: - Convenience global functions

func logDebug(_ message: String, context: String = "App", file: String = #file, line: Int = #line) {
    Logger.shared.debug(message, context: context, file: file, line: line)
}

func logInfo(_ message: String, context: String = "App", file: String = #file, line: Int = #line) {
    Logger.shared.info(message, context: context, file: file, line: line)
}

func logWarning(_ message: String, context: String = "App", file: String = #file, line: Int = #line) {
    Logger.shared.warning(message, context: context, file: file, line: line)
}

func logError(_ message: String, context: String = "App", file: String = #file, line: Int = #line) {
    Logger.shared.error(message, context: context, file: file, line: line)
}

func logError(_ message: String, error: Error, context: String = "App", file: String = #file, line: Int = #line) {
    Logger.shared.error(message, error: error, context: context, file: file, line: line)
}
