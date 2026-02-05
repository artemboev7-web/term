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

    // v0 style: subtle glow layer for cursor
    private var glowLayer: CALayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        // v0 style background
        layer?.backgroundColor = Settings.shared.theme.background.cgColor

        // Subtle inner shadow / border effect
        layer?.borderWidth = 0.5
        layer?.borderColor = Settings.shared.theme.border.cgColor

        // Создаём терминал
        terminalView = LocalProcessTerminalView(frame: bounds)
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(terminalView)

        // Constraints with small padding
        let padding: CGFloat = 8
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding)
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
        let theme = settings.theme

        // Шрифт - v0 style uses slightly lighter weight
        if let font = NSFont(name: "SF Mono", size: CGFloat(settings.fontSize)) {
            terminalView.font = font
        } else if let font = NSFont(name: "JetBrains Mono", size: CGFloat(settings.fontSize)) {
            terminalView.font = font
        } else {
            terminalView.font = NSFont.monospacedSystemFont(
                ofSize: CGFloat(settings.fontSize),
                weight: .regular
            )
        }

        // v0 style colors
        terminalView.nativeBackgroundColor = theme.background
        terminalView.nativeForegroundColor = theme.foreground
        terminalView.caretColor = theme.cursor
        terminalView.selectedTextBackgroundColor = theme.selection

        // Apply ANSI colors
        applyAnsiColors(theme)
    }

    private func applyAnsiColors(_ theme: Theme) {
        // SwiftTerm uses its own Color type for ANSI palette
        // We set colors via the terminal's installColors method
        let terminal = terminalView.getTerminal()

        // ANSI 16 colors: 0-7 normal, 8-15 bright
        let nsColors: [NSColor] = [
            theme.black, theme.red, theme.green, theme.yellow,
            theme.blue, theme.magenta, theme.cyan, theme.white,
            theme.brightBlack, theme.brightRed, theme.brightGreen, theme.brightYellow,
            theme.brightBlue, theme.brightMagenta, theme.brightCyan, theme.brightWhite
        ]

        // Convert NSColor to SwiftTerm Color and install
        var colors: [Color] = []
        for nsColor in nsColors {
            if let rgb = nsColor.usingColorSpace(.deviceRGB) {
                let color = Color(
                    red: UInt16(rgb.redComponent * 65535),
                    green: UInt16(rgb.greenComponent * 65535),
                    blue: UInt16(rgb.blueComponent * 65535)
                )
                colors.append(color)
            }
        }

        if colors.count == 16 {
            terminal.installPalette(colors: colors)
        }
    }

    private func startShell() {
        let shell = Settings.shared.shell
        let environment = ProcessInfo.processInfo.environment

        var env: [String] = []
        for (key, value) in environment {
            env.append("\(key)=\(value)")
        }

        // Добавляем TERM с 256 colors
        env.append("TERM=xterm-256color")
        env.append("COLORTERM=truecolor")

        // Force color output
        env.append("CLICOLOR=1")
        env.append("CLICOLOR_FORCE=1")

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
        window?.makeFirstResponder(terminalView)
        delegate?.paneDidBecomeActive(self)

        // v0 style: subtle highlight on active pane
        layer?.borderColor = Settings.shared.theme.cursor.withAlphaComponent(0.3).cgColor
    }

    func blur() {
        isActive = false
        layer?.borderColor = Settings.shared.theme.border.cgColor
    }

    func clear() {
        // Отправляем Ctrl+L для clear
        terminalView.send(txt: "\u{0C}")
    }

    func updateFont() {
        let settings = Settings.shared
        if let font = NSFont(name: "SF Mono", size: CGFloat(settings.fontSize)) {
            terminalView.font = font
        } else {
            terminalView.font = NSFont.monospacedSystemFont(
                ofSize: CGFloat(settings.fontSize),
                weight: .regular
            )
        }
    }

    func updateTheme() {
        let theme = Settings.shared.theme

        layer?.backgroundColor = theme.background.cgColor
        layer?.borderColor = isActive ? theme.cursor.withAlphaComponent(0.3).cgColor : theme.border.cgColor

        terminalView.nativeBackgroundColor = theme.background
        terminalView.nativeForegroundColor = theme.foreground
        terminalView.caretColor = theme.cursor
        terminalView.selectedTextBackgroundColor = theme.selection

        applyAnsiColors(theme)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        focus()
    }

    override var acceptsFirstResponder: Bool {
        return true
    }
}

// MARK: - LocalProcessTerminalViewDelegate

extension TerminalPaneView: LocalProcessTerminalViewDelegate {
    func processTerminated(source: TerminalView, exitCode: Int32?) {
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
