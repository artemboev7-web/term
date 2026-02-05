import AppKit
import SwiftTerm

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var terminalView: LocalProcessTerminalView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Создаём окно
        let windowRect = NSRect(x: 100, y: 100, width: 800, height: 600)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Term"
        window.minSize = NSSize(width: 400, height: 300)

        // Создаём терминал
        terminalView = LocalProcessTerminalView(frame: windowRect)
        terminalView.autoresizingMask = [.width, .height]

        // Настройка внешнего вида
        configureTerminal()

        // Запускаем shell
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView.startProcess(executable: shell, execName: shell)

        // Добавляем в окно
        window.contentView = terminalView
        window.makeKeyAndOrderFront(nil)
        window.center()

        // Активируем приложение
        NSApp.activate(ignoringOtherApps: true)
    }

    func configureTerminal() {
        // Шрифт
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

        // Цвета (темная тема)
        terminalView.nativeBackgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        terminalView.nativeForegroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)

        // Cursor
        terminalView.caretColor = NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
    }
}
