import AppKit

class TerminalWindowController: NSWindowController, NSWindowDelegate {
    private var tabViewController: NSTabViewController!
    private var tabCount = 0
    private let windowId = UUID().uuidString.prefix(8)
    private var searchBar: SearchBarView?
    private var searchBarConstraint: NSLayoutConstraint?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.init(window: window)

        logInfo("Creating window \(windowId)", context: "Window")
        setupWindow()
        setupTabViewController()
        addNewTab()
        logInfo("Window \(windowId) ready", context: "Window")

        // Deferred focus — ensure view hierarchy is fully established
        DispatchQueue.main.async { [weak self] in
            self?.focusActiveTerminal()
        }
    }

    private func setupWindow() {
        guard let window = window else { return }

        window.delegate = self
        window.title = "Term"
        window.minSize = NSSize(width: 400, height: 300)

        // v0 style: transparent titlebar, dark
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Settings.shared.theme.background
        window.isMovableByWindowBackground = true

        // Subtle shadow
        window.hasShadow = true

        // Rounded corners (macOS 11+)
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }

        // Optional: semi-transparent для glass effect
        window.isOpaque = true
        window.alphaValue = CGFloat(Settings.shared.windowOpacity)

        // Toolbar для native tabs
        window.toolbar = NSToolbar()
        window.toolbar?.showsBaselineSeparator = false

        // Native macOS tabs
        window.tabbingMode = .preferred

        window.center()

        // Subscribe to theme changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: .themeChanged,
            object: nil
        )
    }

    @objc private func handleThemeChange() {
        window?.backgroundColor = Settings.shared.theme.background
    }

    private func setupTabViewController() {
        tabViewController = NSTabViewController()
        tabViewController.tabStyle = .unspecified
        contentViewController = tabViewController
    }

    // MARK: - Tab Management

    func addNewTab() {
        tabCount += 1
        logInfo("Adding tab #\(tabCount) to window \(windowId)", context: "Window")

        let terminalVC = TerminalViewController()
        terminalVC.title = "zsh"

        let tabItem = NSTabViewItem(viewController: terminalVC)
        tabItem.label = "zsh"

        tabViewController.addTabViewItem(tabItem)
        tabViewController.selectedTabViewItemIndex = tabViewController.tabViewItems.count - 1

        updateWindowTitle()
        logDebug("Tab added, total tabs: \(tabViewController.tabViewItems.count)", context: "Window")
    }

    func closeCurrentTab() {
        logInfo("Closing tab in window \(windowId)", context: "Window")

        guard tabViewController.tabViewItems.count > 0 else {
            logDebug("No tabs left, closing window", context: "Window")
            window?.close()
            return
        }

        let index = tabViewController.selectedTabViewItemIndex
        if index >= 0 && index < tabViewController.tabViewItems.count {
            tabViewController.removeTabViewItem(tabViewController.tabViewItems[index])
            logDebug("Tab \(index) removed, remaining: \(tabViewController.tabViewItems.count)", context: "Window")
        }

        if tabViewController.tabViewItems.isEmpty {
            logDebug("All tabs closed, closing window", context: "Window")
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
        logInfo("Split \(horizontal ? "horizontal" : "vertical") in window \(windowId)", context: "Window")

        guard let currentVC = tabViewController.tabViewItems[safe: tabViewController.selectedTabViewItemIndex]?.viewController as? TerminalViewController else {
            logWarning("No current view controller for split", context: "Window")
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

    // MARK: - Search

    func showFindBar() {
        guard searchBar == nil else {
            searchBar?.focus()
            return
        }

        guard let contentView = window?.contentView else { return }

        logInfo("Showing find bar in window \(windowId)", context: "Window")

        let bar = SearchBarView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.delegate = self
        contentView.addSubview(bar)

        let heightConstraint = bar.heightAnchor.constraint(equalToConstant: 36)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: contentView.topAnchor),
            bar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            heightConstraint
        ])

        searchBar = bar
        searchBarConstraint = heightConstraint

        // Animate in
        bar.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            bar.animator().alphaValue = 1
        }

        bar.focus()
    }

    func hideFindBar() {
        guard let bar = searchBar else { return }

        logDebug("Hiding find bar", context: "Window")

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            bar.animator().alphaValue = 0
        }, completionHandler: {
            bar.removeFromSuperview()
            self.searchBar = nil
            self.searchBarConstraint = nil

            // Return focus to terminal
            if let currentVC = self.tabViewController.tabViewItems[safe: self.tabViewController.selectedTabViewItemIndex]?.viewController as? TerminalViewController {
                currentVC.focusTerminal()
            }
        })
    }

    func findNext() {
        if let currentVC = tabViewController.tabViewItems[safe: tabViewController.selectedTabViewItemIndex]?.viewController as? TerminalViewController {
            _ = currentVC.findNext()
        }
    }

    func findPrevious() {
        if let currentVC = tabViewController.tabViewItems[safe: tabViewController.selectedTabViewItemIndex]?.viewController as? TerminalViewController {
            _ = currentVC.findPrevious()
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        logInfo("Window \(windowId) closing", context: "Window")
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.windowWillClose(self)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        logDebug("Window \(windowId) became key", context: "Window")
        focusActiveTerminal()
    }

    private func focusActiveTerminal() {
        if let currentVC = tabViewController.tabViewItems[safe: tabViewController.selectedTabViewItemIndex]?.viewController as? TerminalViewController {
            currentVC.focusTerminal()
        }
    }

    deinit {
        logInfo("Window \(windowId) deallocated", context: "Window")
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - SearchBarDelegate

extension TerminalWindowController: SearchBarDelegate {
    func searchBar(_ searchBar: SearchBarView, didSearchFor query: String) {
        if let currentVC = tabViewController.tabViewItems[safe: tabViewController.selectedTabViewItemIndex]?.viewController as? TerminalViewController {
            let (count, current) = currentVC.search(for: query)
            searchBar.updateResults(count: count, current: current)
        }
    }

    func searchBarDidRequestNext(_ searchBar: SearchBarView) {
        if let currentVC = tabViewController.tabViewItems[safe: tabViewController.selectedTabViewItemIndex]?.viewController as? TerminalViewController {
            let (count, current) = currentVC.findNext()
            searchBar.updateResults(count: count, current: current)
        }
    }

    func searchBarDidRequestPrevious(_ searchBar: SearchBarView) {
        if let currentVC = tabViewController.tabViewItems[safe: tabViewController.selectedTabViewItemIndex]?.viewController as? TerminalViewController {
            let (count, current) = currentVC.findPrevious()
            searchBar.updateResults(count: count, current: current)
        }
    }

    func searchBarDidClose(_ searchBar: SearchBarView) {
        hideFindBar()
        if let currentVC = tabViewController.tabViewItems[safe: tabViewController.selectedTabViewItemIndex]?.viewController as? TerminalViewController {
            currentVC.clearSearch()
        }
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
