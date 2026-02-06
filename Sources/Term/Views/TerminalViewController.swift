import AppKit

class TerminalViewController: NSViewController {
    private var splitView: NSSplitView!
    private var terminalPanes: [TerminalPaneView] = []
    private var activePaneIndex = 0
    private let vcId = UUID().uuidString.prefix(8)

    /// Optional data source for remote mode; when set, new panes use this factory
    var dataSourceFactory: (() -> TerminalDataSource)?

    override func loadView() {
        logInfo("Loading TerminalViewController \(vcId)", context: "TerminalVC")
        // Container view with padding for v0-style border
        let container = NSView()
        container.wantsLayer = true

        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        // v0 style: subtle divider
        splitView.setValue(NSColor(white: 0.15, alpha: 1.0), forKey: "dividerColor")

        container.addSubview(splitView)

        // Small padding for aesthetic
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
            splitView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -1),
            splitView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 1),
            splitView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -1)
        ])

        view = container

        // Создаём первую панель
        logDebug("Creating first terminal pane", context: "TerminalVC")
        _ = addTerminalPane()
        logInfo("TerminalViewController \(vcId) loaded with 1 pane", context: "TerminalVC")

        // Подписка на изменение настроек
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFontChange),
            name: .fontSizeChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: .themeChanged,
            object: nil
        )
    }

    deinit {
        logInfo("TerminalViewController \(vcId) deallocated", context: "TerminalVC")
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Pane Management

    private func addTerminalPane() -> TerminalPaneView {
        logDebug("Adding terminal pane to VC \(vcId)", context: "TerminalVC")
        let pane: TerminalPaneView
        if let factory = dataSourceFactory {
            pane = TerminalPaneView(dataSource: factory())
        } else {
            pane = TerminalPaneView()
        }
        pane.delegate = self
        terminalPanes.append(pane)
        splitView.addArrangedSubview(pane)
        logDebug("Terminal pane added, total panes: \(terminalPanes.count)", context: "TerminalVC")
        return pane
    }

    func split(horizontal: Bool) {
        logInfo("Splitting \(horizontal ? "horizontally" : "vertically") in VC \(vcId)", context: "TerminalVC")

        // If only 1 pane, simply set orientation and add new pane
        if terminalPanes.count <= 1 {
            splitView.isVertical = !horizontal
            let newPane = addTerminalPane()
            splitView.adjustSubviews()
            activePaneIndex = terminalPanes.count - 1
            newPane.focus()
        } else {
            // Multiple panes exist: wrap active pane + new pane in a nested NSSplitView
            // to avoid changing orientation for all existing panes
            let activePane = terminalPanes[activePaneIndex]
            let activeIndex = splitView.arrangedSubviews.firstIndex(of: activePane) ?? 0

            // Create nested split view
            let nestedSplit = NSSplitView()
            nestedSplit.isVertical = !horizontal
            nestedSplit.dividerStyle = .thin
            nestedSplit.setValue(NSColor(white: 0.15, alpha: 1.0), forKey: "dividerColor")

            // Replace active pane with nested split
            activePane.removeFromSuperview()
            splitView.insertArrangedSubview(nestedSplit, at: activeIndex)

            // Add panes to nested split
            nestedSplit.addArrangedSubview(activePane)

            let newPane: TerminalPaneView
            if let factory = dataSourceFactory {
                newPane = TerminalPaneView(dataSource: factory())
            } else {
                newPane = TerminalPaneView()
            }
            newPane.delegate = self
            terminalPanes.append(newPane)
            nestedSplit.addArrangedSubview(newPane)
            nestedSplit.adjustSubviews()

            activePaneIndex = terminalPanes.count - 1
            newPane.focus()
        }

        logInfo("Split complete, active pane: \(activePaneIndex)", context: "TerminalVC")
    }

    func closePane(at index: Int) {
        logInfo("Closing pane \(index) in VC \(vcId)", context: "TerminalVC")
        guard terminalPanes.count > 1 else {
            logDebug("Cannot close last pane", context: "TerminalVC")
            return
        }

        let pane = terminalPanes.remove(at: index)
        pane.removeFromSuperview()

        if activePaneIndex >= terminalPanes.count {
            activePaneIndex = terminalPanes.count - 1
        }

        terminalPanes[safe: activePaneIndex]?.focus()
        logDebug("Pane closed, remaining: \(terminalPanes.count), active: \(activePaneIndex)", context: "TerminalVC")
    }

    // MARK: - Actions

    func clearBuffer() {
        terminalPanes[safe: activePaneIndex]?.clear()
    }

    func focusTerminal() {
        terminalPanes[safe: activePaneIndex]?.focus()
    }

    // MARK: - Search

    func search(for query: String) -> (count: Int, current: Int) {
        guard let pane = terminalPanes[safe: activePaneIndex] else {
            return (0, 0)
        }
        return pane.search(for: query)
    }

    func findNext() -> (count: Int, current: Int) {
        guard let pane = terminalPanes[safe: activePaneIndex] else {
            return (0, 0)
        }
        return pane.findNext()
    }

    func findPrevious() -> (count: Int, current: Int) {
        guard let pane = terminalPanes[safe: activePaneIndex] else {
            return (0, 0)
        }
        return pane.findPrevious()
    }

    func clearSearch() {
        terminalPanes[safe: activePaneIndex]?.clearSearch()
    }

    // MARK: - Settings

    @objc private func handleFontChange() {
        for pane in terminalPanes {
            pane.updateFont()
        }
    }

    @objc private func handleThemeChange() {
        view.layer?.backgroundColor = Settings.shared.theme.background.cgColor
        for pane in terminalPanes {
            pane.updateTheme()
        }
    }
}

// MARK: - TerminalPaneViewDelegate

extension TerminalViewController: TerminalPaneViewDelegate {
    func paneDidBecomeActive(_ pane: TerminalPaneView) {
        if let index = terminalPanes.firstIndex(where: { $0 === pane }) {
            logDebug("Pane \(index) became active in VC \(vcId)", context: "TerminalVC")
            activePaneIndex = index
        }
    }

    func paneDidClose(_ pane: TerminalPaneView) {
        logInfo("Pane requested close in VC \(vcId)", context: "TerminalVC")
        if let index = terminalPanes.firstIndex(where: { $0 === pane }) {
            closePane(at: index)
        }
    }

    func pane(_ pane: TerminalPaneView, didUpdateTitle title: String) {
        logDebug("Title updated: \(title)", context: "TerminalVC")
        self.title = title

        // Update the tab label so native macOS tabs show the correct title
        if let tabVC = parent as? NSTabViewController,
           let tabItem = tabVC.tabViewItems.first(where: { $0.viewController === self }) {
            tabItem.label = title
        }
    }
}
