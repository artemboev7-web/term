import AppKit
import SwiftTerm

class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [TerminalWindowController] = []
    var preferencesWindow: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Загружаем настройки
        Settings.shared.load()

        // Создаём первое окно
        createNewWindow()

        // Активируем приложение
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Settings.shared.save()
    }

    // MARK: - Window Management

    func createNewWindow() -> TerminalWindowController {
        let controller = TerminalWindowController()
        windows.append(controller)
        controller.showWindow(nil)
        return controller
    }

    @objc func newWindow() {
        _ = createNewWindow()
    }

    @objc func newTab() {
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.addNewTab()
        } else {
            _ = createNewWindow()
        }
    }

    @objc func closeTab() {
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.closeCurrentTab()
        }
    }

    @objc func closeWindow() {
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
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.splitCurrentPane(horizontal: true)
        }
    }

    @objc func splitVertically() {
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.splitCurrentPane(horizontal: false)
        }
    }

    // MARK: - Edit

    @objc func clearBuffer() {
        if let controller = NSApp.keyWindow?.windowController as? TerminalWindowController {
            controller.clearCurrentTerminal()
        }
    }

    // MARK: - View

    @objc func zoomIn() {
        Settings.shared.fontSize += 1
        // fontSize didSet posts notification automatically
    }

    @objc func zoomOut() {
        if Settings.shared.fontSize > 8 {
            Settings.shared.fontSize -= 1
        }
    }

    @objc func resetZoom() {
        Settings.shared.fontSize = 14
    }

    // MARK: - App Menu

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Term"
        alert.informativeText = "A minimal terminal emulator for macOS\n\nBuilt with SwiftTerm"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func showPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController()
        }
        preferencesWindow?.showWindow(nil)
        preferencesWindow?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Cleanup

    func windowWillClose(_ controller: TerminalWindowController) {
        windows.removeAll { $0 === controller }
    }
}

// Note: Notification.Name extensions are in Settings.swift
