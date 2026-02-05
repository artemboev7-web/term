import AppKit
import SwiftTerm

class TerminalViewController: NSViewController {
    private var splitView: NSSplitView!
    private var terminalPanes: [TerminalPaneView] = []
    private var activePaneIndex = 0

    override func loadView() {
        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]

        view = splitView

        // Создаём первую панель
        addTerminalPane()

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
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Pane Management

    private func addTerminalPane() -> TerminalPaneView {
        let pane = TerminalPaneView()
        pane.delegate = self
        terminalPanes.append(pane)
        splitView.addArrangedSubview(pane)
        return pane
    }

    func split(horizontal: Bool) {
        splitView.isVertical = !horizontal
        let newPane = addTerminalPane()

        // Равномерное распределение
        splitView.adjustSubviews()

        // Фокус на новую панель
        activePaneIndex = terminalPanes.count - 1
        newPane.focus()
    }

    func closePane(at index: Int) {
        guard terminalPanes.count > 1 else { return }

        let pane = terminalPanes.remove(at: index)
        pane.removeFromSuperview()

        if activePaneIndex >= terminalPanes.count {
            activePaneIndex = terminalPanes.count - 1
        }

        terminalPanes[safe: activePaneIndex]?.focus()
    }

    // MARK: - Actions

    func clearBuffer() {
        terminalPanes[safe: activePaneIndex]?.clear()
    }

    // MARK: - Settings

    @objc private func handleFontChange() {
        for pane in terminalPanes {
            pane.updateFont()
        }
    }

    @objc private func handleThemeChange() {
        for pane in terminalPanes {
            pane.updateTheme()
        }
    }
}

// MARK: - TerminalPaneViewDelegate

extension TerminalViewController: TerminalPaneViewDelegate {
    func paneDidBecomeActive(_ pane: TerminalPaneView) {
        if let index = terminalPanes.firstIndex(where: { $0 === pane }) {
            activePaneIndex = index
        }
    }

    func paneDidClose(_ pane: TerminalPaneView) {
        if let index = terminalPanes.firstIndex(where: { $0 === pane }) {
            closePane(at: index)
        }
    }

    func pane(_ pane: TerminalPaneView, didUpdateTitle title: String) {
        self.title = title
    }
}
