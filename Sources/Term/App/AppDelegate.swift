import AppKit
import SwiftTerm

class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [TerminalWindowController] = []
    var preferencesWindow: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logInfo("Application launching...", context: "AppDelegate")

        // Загружаем настройки
        Settings.shared.load()
        logInfo("Settings loaded: theme=\(Settings.shared.theme.name), font=\(Settings.shared.fontFamily), size=\(Settings.shared.fontSize)", context: "AppDelegate")

        // Создаём первое окно
        logInfo("Creating first window", context: "AppDelegate")
        _ = createNewWindow()

        // Активируем приложение
        NSApp.activate(ignoringOtherApps: true)
        logInfo("Application launched successfully", context: "AppDelegate")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        logInfo("Last window closed, will terminate", context: "AppDelegate")
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        logInfo("Application terminating, saving settings...", context: "AppDelegate")
        Settings.shared.save()
        logInfo("Settings saved, goodbye!", context: "AppDelegate")
    }

    // MARK: - Window Management

    func createNewWindow() -> TerminalWindowController {
        logInfo("Creating new terminal window", context: "AppDelegate")
        let controller = TerminalWindowController()
        windows.append(controller)
        controller.showWindow(nil)
        logInfo("Window created, total windows: \(windows.count)", context: "AppDelegate")
        return controller
    }

    @objc func newWindow() {
        logDebug("Menu: New Window", context: "AppDelegate")
        _ = createNewWindow()
    }

    @objc func newTab() {
        logDebug("Menu: New Tab", context: "AppDelegate")
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.addNewTab()
        } else {
            _ = createNewWindow()
        }
    }

    @objc func closeTab() {
        logDebug("Menu: Close Tab", context: "AppDelegate")
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.closeCurrentTab()
        }
    }

    @objc func closeWindow() {
        logDebug("Menu: Close Window", context: "AppDelegate")
        NSApp.keyWindow?.close()
    }

    @objc func nextTab() {
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.selectNextTab()
        }
    }

    @objc func previousTab() {
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.selectPreviousTab()
        }
    }

    // MARK: - Split

    @objc func splitHorizontally() {
        logDebug("Menu: Split Horizontally", context: "AppDelegate")
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.splitCurrentPane(horizontal: true)
        }
    }

    @objc func splitVertically() {
        logDebug("Menu: Split Vertically", context: "AppDelegate")
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.splitCurrentPane(horizontal: false)
        }
    }

    // MARK: - Edit

    @objc func clearBuffer() {
        logDebug("Menu: Clear Buffer", context: "AppDelegate")
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.clearCurrentTerminal()
        }
    }

    // MARK: - Find

    @objc func showFind() {
        logDebug("Menu: Find", context: "AppDelegate")
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.showFindBar()
        }
    }

    @objc func findNext() {
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.findNext()
        }
    }

    @objc func findPrevious() {
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.findPrevious()
        }
    }

    // MARK: - View

    @objc func zoomIn() {
        Settings.shared.fontSize += 1
        logDebug("Zoom In: fontSize=\(Settings.shared.fontSize)", context: "AppDelegate")
    }

    @objc func zoomOut() {
        if Settings.shared.fontSize > 8 {
            Settings.shared.fontSize -= 1
            logDebug("Zoom Out: fontSize=\(Settings.shared.fontSize)", context: "AppDelegate")
        }
    }

    @objc func resetZoom() {
        Settings.shared.fontSize = 14
        logDebug("Reset Zoom: fontSize=14", context: "AppDelegate")
    }

    // MARK: - App Menu

    @objc func showAbout() {
        logDebug("Menu: About", context: "AppDelegate")
        let alert = NSAlert()
        alert.messageText = "Term"
        alert.informativeText = "A minimal terminal emulator for macOS\n\nBuilt with SwiftTerm\n\nLogs: ~/Library/Logs/Term/"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func showPreferences() {
        logDebug("Menu: Preferences", context: "AppDelegate")
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController()
        }
        preferencesWindow?.showWindow(nil)
        preferencesWindow?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Cleanup

    func windowWillClose(_ controller: TerminalWindowController) {
        logInfo("Window closing", context: "AppDelegate")
        windows.removeAll { $0 === controller }
        logInfo("Remaining windows: \(windows.count)", context: "AppDelegate")
    }
}
