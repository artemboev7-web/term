import AppKit
import SwiftTerm

class TerminalViewController: NSViewController {
    private var splitView: NSSplitView!
    private var terminalPanes: [TerminalPaneView] = []
    private var activePaneIndex = 0
    private let vcId = UUID().uuidString.prefix(8)

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
        addTerminalPane()
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
        let pane = TerminalPaneView()
        pane.delegate = self
        terminalPanes.append(pane)
        splitView.addArrangedSubview(pane)
        logDebug("Terminal pane added, total panes: \(terminalPanes.count)", context: "TerminalVC")
        return pane
    }

    func split(horizontal: Bool) {
        logInfo("Splitting \(horizontal ? "horizontally" : "vertically") in VC \(vcId)", context: "TerminalVC")
        splitView.isVertical = !horizontal
        let newPane = addTerminalPane()

        // Равномерное распределение
        splitView.adjustSubviews()

        // Фокус на новую панель
        activePaneIndex = terminalPanes.count - 1
        newPane.focus()
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
    }
}
