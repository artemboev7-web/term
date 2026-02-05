import AppKit

class PreferencesWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.init(window: window)

        window.title = "Preferences"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        window.center()

        let prefsView = PreferencesView(frame: NSRect(x: 0, y: 0, width: 500, height: 450))
        window.contentView = prefsView
    }
}

class PreferencesView: NSView {
    private var fontPopup: NSPopUpButton!
    private var fontSizeField: NSTextField!
    private var themePopup: NSPopUpButton!
    private var vibrancyCheckbox: NSButton!
    private var shellField: NSTextField!

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
        layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0).cgColor

        let contentWidth: CGFloat = 400
        let startX = (bounds.width - contentWidth) / 2
        var y = bounds.height - 50

        // Title
        let titleLabel = createLabel("Preferences", size: 18, bold: true)
        titleLabel.frame = NSRect(x: startX, y: y, width: contentWidth, height: 24)
        addSubview(titleLabel)

        y -= 50

        // --- Appearance Section ---
        let appearanceLabel = createSectionLabel("Appearance")
        appearanceLabel.frame = NSRect(x: startX, y: y, width: contentWidth, height: 20)
        addSubview(appearanceLabel)

        y -= 35

        // Theme
        let themeLabel = createLabel("Theme")
        themeLabel.frame = NSRect(x: startX, y: y, width: 100, height: 22)
        addSubview(themeLabel)

        themePopup = NSPopUpButton()
        themePopup.frame = NSRect(x: startX + 110, y: y, width: 200, height: 26)
        for theme in Theme.allThemes {
            themePopup.addItem(withTitle: theme.name)
        }
        themePopup.selectItem(withTitle: Settings.shared.theme.name)
        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        stylePopup(themePopup)
        addSubview(themePopup)

        y -= 35

        // Font
        let fontLabel = createLabel("Font")
        fontLabel.frame = NSRect(x: startX, y: y, width: 100, height: 22)
        addSubview(fontLabel)

        fontPopup = NSPopUpButton()
        fontPopup.frame = NSRect(x: startX + 110, y: y, width: 160, height: 26)

        // Add available fonts
        for (fontName, displayName) in Settings.availableFonts {
            if NSFont(name: fontName, size: 14) != nil {
                fontPopup.addItem(withTitle: displayName)
            }
        }

        // Select current font
        if let index = Settings.availableFonts.firstIndex(where: { $0.name == Settings.shared.fontFamily }) {
            fontPopup.selectItem(at: index)
        }
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged)
        stylePopup(fontPopup)
        addSubview(fontPopup)

        // Font size
        fontSizeField = NSTextField()
        fontSizeField.frame = NSRect(x: startX + 280, y: y + 2, width: 50, height: 22)
        fontSizeField.stringValue = "\(Settings.shared.fontSize)"
        fontSizeField.alignment = .center
        fontSizeField.bezelStyle = .roundedBezel
        fontSizeField.target = self
        fontSizeField.action = #selector(fontSizeChanged)
        styleTextField(fontSizeField)
        addSubview(fontSizeField)

        let ptLabel = createLabel("pt", size: 12)
        ptLabel.frame = NSRect(x: startX + 335, y: y, width: 30, height: 22)
        addSubview(ptLabel)

        y -= 35

        // Vibrancy
        vibrancyCheckbox = NSButton(checkboxWithTitle: "Enable blur/vibrancy effect", target: self, action: #selector(vibrancyChanged))
        vibrancyCheckbox.frame = NSRect(x: startX + 110, y: y, width: 250, height: 22)
        vibrancyCheckbox.state = Settings.shared.vibrancy ? .on : .off
        styleCheckbox(vibrancyCheckbox)
        addSubview(vibrancyCheckbox)

        y -= 50

        // --- Shell Section ---
        let shellLabel = createSectionLabel("Shell")
        shellLabel.frame = NSRect(x: startX, y: y, width: contentWidth, height: 20)
        addSubview(shellLabel)

        y -= 35

        // Shell path
        let shellPathLabel = createLabel("Path")
        shellPathLabel.frame = NSRect(x: startX, y: y, width: 100, height: 22)
        addSubview(shellPathLabel)

        shellField = NSTextField()
        shellField.frame = NSRect(x: startX + 110, y: y, width: 250, height: 22)
        shellField.stringValue = Settings.shared.shell
        shellField.bezelStyle = .roundedBezel
        shellField.target = self
        shellField.action = #selector(shellChanged)
        styleTextField(shellField)
        addSubview(shellField)

        y -= 60

        // --- Buttons ---
        let buttonY = CGFloat(20)

        // Reset button
        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetDefaults))
        resetButton.frame = NSRect(x: startX, y: buttonY, width: 130, height: 32)
        resetButton.bezelStyle = .rounded
        addSubview(resetButton)

        // Save button
        let saveButton = NSButton(title: "Save & Close", target: self, action: #selector(saveAndClose))
        saveButton.frame = NSRect(x: startX + contentWidth - 120, y: buttonY, width: 120, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        addSubview(saveButton)

        // Theme preview
        addThemePreview(at: NSRect(x: startX + 320, y: bounds.height - 200, width: 80, height: 60))
    }

    private func addThemePreview(at rect: NSRect) {
        let preview = NSView(frame: rect)
        preview.wantsLayer = true
        preview.layer?.backgroundColor = Settings.shared.theme.background.cgColor
        preview.layer?.cornerRadius = 6
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = Settings.shared.theme.border.cgColor

        // Color dots
        let colors = [
            Settings.shared.theme.red,
            Settings.shared.theme.green,
            Settings.shared.theme.yellow,
            Settings.shared.theme.blue,
            Settings.shared.theme.magenta,
            Settings.shared.theme.cyan
        ]

        let dotSize: CGFloat = 8
        let spacing: CGFloat = 4
        let startX = (rect.width - (CGFloat(colors.count) * dotSize + CGFloat(colors.count - 1) * spacing)) / 2

        for (index, color) in colors.enumerated() {
            let dot = NSView(frame: NSRect(
                x: startX + CGFloat(index) * (dotSize + spacing),
                y: (rect.height - dotSize) / 2,
                width: dotSize,
                height: dotSize
            ))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = color.cgColor
            dot.layer?.cornerRadius = dotSize / 2
            preview.addSubview(dot)
        }

        addSubview(preview)
    }

    // MARK: - Styling

    private func createLabel(_ text: String, size: CGFloat = 13, bold: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = NSColor(white: 0.9, alpha: 1.0)
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        return label
    }

    private func createSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = NSColor(white: 0.5, alpha: 1.0)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        return label
    }

    private func stylePopup(_ popup: NSPopUpButton) {
        popup.appearance = NSAppearance(named: .darkAqua)
    }

    private func styleTextField(_ field: NSTextField) {
        field.appearance = NSAppearance(named: .darkAqua)
    }

    private func styleCheckbox(_ checkbox: NSButton) {
        checkbox.appearance = NSAppearance(named: .darkAqua)
        checkbox.contentTintColor = NSColor(white: 0.9, alpha: 1.0)
    }

    // MARK: - Actions

    @objc private func themeChanged() {
        guard let themeName = themePopup.selectedItem?.title,
              let theme = Theme.named(themeName) else { return }
        Settings.shared.theme = theme
    }

    @objc private func fontChanged() {
        guard let selectedIndex = fontPopup.indexOfSelectedItem as Int?,
              selectedIndex >= 0 && selectedIndex < Settings.availableFonts.count else { return }
        Settings.shared.fontFamily = Settings.availableFonts[selectedIndex].name
    }

    @objc private func fontSizeChanged() {
        if let size = Int(fontSizeField.stringValue), size >= 8, size <= 72 {
            Settings.shared.fontSize = size
        } else {
            fontSizeField.stringValue = "\(Settings.shared.fontSize)"
        }
    }

    @objc private func vibrancyChanged() {
        Settings.shared.vibrancy = vibrancyCheckbox.state == .on
    }

    @objc private func shellChanged() {
        let path = shellField.stringValue.trimmingCharacters(in: .whitespaces)
        if !path.isEmpty {
            Settings.shared.shell = path
        }
    }

    @objc private func resetDefaults() {
        Settings.shared.theme = .v0Dark
        Settings.shared.fontFamily = "SF Mono"
        Settings.shared.fontSize = 14
        Settings.shared.vibrancy = true
        Settings.shared.shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        // Update UI
        themePopup.selectItem(withTitle: Settings.shared.theme.name)
        if let index = Settings.availableFonts.firstIndex(where: { $0.name == Settings.shared.fontFamily }) {
            fontPopup.selectItem(at: index)
        }
        fontSizeField.stringValue = "\(Settings.shared.fontSize)"
        vibrancyCheckbox.state = Settings.shared.vibrancy ? .on : .off
        shellField.stringValue = Settings.shared.shell
    }

    @objc private func saveAndClose() {
        Settings.shared.save()
        window?.close()
    }
}
