import AppKit
import SwiftTerm

class TerminalWindowController: NSWindowController, NSWindowDelegate {
    private var tabViewController: NSTabViewController!
    private var tabCount = 0

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.init(window: window)

        setupWindow()
        setupTabViewController()
        addNewTab()
    }

    private func setupWindow() {
        guard let window = window else { return }

        window.delegate = self
        window.title = "Term"
        window.minSize = NSSize(width: 400, height: 300)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Settings.shared.theme.background
        window.isMovableByWindowBackground = true

        // Toolbar style для tabs
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar()
        window.toolbar?.showsBaselineSeparator = false

        window.center()
    }

    private func setupTabViewController() {
        tabViewController = NSTabViewController()
        tabViewController.tabStyle = .unspecified

        // Используем window tabs вместо NSTabView
        window?.tabbingMode = .preferred

        contentViewController = tabViewController
    }

    // MARK: - Tab Management

    func addNewTab() {
        tabCount += 1
        let terminalVC = TerminalViewController()
        terminalVC.title = "Terminal \(tabCount)"

        let tabItem = NSTabViewItem(viewController: terminalVC)
        tabItem.label = "Terminal \(tabCount)"

        tabViewController.addTabViewItem(tabItem)
        tabViewController.selectedTabViewItemIndex = tabViewController.tabViewItems.count - 1

        // Создаём новую window tab если уже есть tabs
        if tabViewController.tabViewItems.count > 1 {
            if let newWindow = window?.addTabbedWindow(with: terminalVC) {
                newWindow.makeKeyAndOrderFront(nil)
            }
        }

        updateWindowTitle()
    }

    func closeCurrentTab() {
        guard tabViewController.tabViewItems.count > 0 else {
            window?.close()
            return
        }

        let index = tabViewController.selectedTabViewItemIndex
        if index >= 0 && index < tabViewController.tabViewItems.count {
            tabViewController.removeTabViewItem(tabViewController.tabViewItems[index])
        }

        if tabViewController.tabViewItems.isEmpty {
            window?.close()
        } else {
            updateWindowTitle()
        }
    }

    func selectNextTab() {
        let count = tabViewController.tabViewItems.count
        if count > 1 {
            let next = (tabViewController.selectedTabViewItemIndex + 1) % count
            tabViewController.selectedTabViewItemIndex = next
        }
    }

    func selectPreviousTab() {
        let count = tabViewController.tabViewItems.count
        if count > 1 {
            let prev = (tabViewController.selectedTabViewItemIndex - 1 + count) % count
            tabViewController.selectedTabViewItemIndex = prev
        }
    }

    // MARK: - Split Panes

    func splitCurrentPane(horizontal: Bool) {
        guard let currentVC = tabViewController.tabViewItems[safe: tabViewController.selectedTabViewItemIndex]?.viewController as? TerminalViewController else {
            return
        }
        currentVC.split(horizontal: horizontal)
    }

    // MARK: - Terminal Actions

    func clearCurrentTerminal() {
        guard let currentVC = tabViewController.tabViewItems[safe: tabViewController.selectedTabViewItemIndex]?.viewController as? TerminalViewController else {
            return
        }
        currentVC.clearBuffer()
    }

    // MARK: - Window Title

    private func updateWindowTitle() {
        if let currentVC = tabViewController.tabViewItems[safe: tabViewController.selectedTabViewItemIndex]?.viewController as? TerminalViewController {
            window?.title = currentVC.title ?? "Term"
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.windowWillClose(self)
        }
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
