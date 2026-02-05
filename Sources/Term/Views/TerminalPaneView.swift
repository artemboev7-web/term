import AppKit
import SwiftTerm

protocol TerminalPaneViewDelegate: AnyObject {
    func paneDidBecomeActive(_ pane: TerminalPaneView)
    func paneDidClose(_ pane: TerminalPaneView)
    func pane(_ pane: TerminalPaneView, didUpdateTitle title: String)
}

class TerminalPaneView: NSView {
    weak var delegate: TerminalPaneViewDelegate?

    private var terminalView: LocalProcessTerminalView!
    private var isActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Создаём терминал
        terminalView = LocalProcessTerminalView(frame: bounds)
        terminalView.autoresizingMask = [.width, .height]
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(terminalView)

        // Constraints
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // Настройка
        applySettings()

        // Запуск shell
        startShell()

        // Обработка завершения процесса
        terminalView.processDelegate = self
    }

    private func applySettings() {
        let settings = Settings.shared

        // Шрифт
        terminalView.font = NSFont.monospacedSystemFont(
            ofSize: CGFloat(settings.fontSize),
            weight: .regular
        )

        // Цвета
        terminalView.nativeBackgroundColor = settings.theme.background
        terminalView.nativeForegroundColor = settings.theme.foreground
        terminalView.caretColor = settings.theme.cursor
        terminalView.selectedTextBackgroundColor = settings.theme.selection
    }

    private func startShell() {
        let shell = Settings.shared.shell
        let environment = ProcessInfo.processInfo.environment

        var env: [String] = []
        for (key, value) in environment {
            env.append("\(key)=\(value)")
        }

        // Добавляем TERM
        env.append("TERM=xterm-256color")

        terminalView.startProcess(
            executable: shell,
            args: [shell, "-l"], // Login shell
            environment: env,
            execName: (shell as NSString).lastPathComponent
        )
    }

    // MARK: - Public Methods

    func focus() {
        isActive = true
        terminalView.becomeFirstResponder()
        delegate?.paneDidBecomeActive(self)
    }

    func clear() {
        // Отправляем Ctrl+L для clear
        terminalView.send(txt: "\u{0C}")
    }

    func updateFont() {
        terminalView.font = NSFont.monospacedSystemFont(
            ofSize: CGFloat(Settings.shared.fontSize),
            weight: .regular
        )
    }

    func updateTheme() {
        let theme = Settings.shared.theme
        terminalView.nativeBackgroundColor = theme.background
        terminalView.nativeForegroundColor = theme.foreground
        terminalView.caretColor = theme.cursor
        terminalView.selectedTextBackgroundColor = theme.selection
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        focus()
    }
}

// MARK: - LocalProcessTerminalViewDelegate

extension TerminalPaneView: LocalProcessTerminalViewDelegate {
    func processTerminated(_ source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.paneDidClose(self)
        }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Размер изменился
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        delegate?.pane(self, didUpdateTitle: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Директория изменилась
    }
}
