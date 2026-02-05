import AppKit

class PreferencesWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.init(window: window)

        window.title = "Preferences"
        window.center()

        let prefsView = PreferencesView()
        window.contentView = prefsView
    }
}

class PreferencesView: NSView {
    private var fontSizeField: NSTextField!
    private var shellField: NSTextField!
    private var themePopup: NSPopUpButton!
    private var cursorBlinkCheckbox: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let padding: CGFloat = 20
        var y = bounds.height - 50

        // Font Size
        let fontLabel = createLabel("Font Size:")
        fontLabel.frame = NSRect(x: padding, y: y, width: 100, height: 22)
        addSubview(fontLabel)

        fontSizeField = NSTextField()
        fontSizeField.frame = NSRect(x: padding + 110, y: y, width: 60, height: 22)
        fontSizeField.stringValue = "\(Settings.shared.fontSize)"
        fontSizeField.target = self
        fontSizeField.action = #selector(fontSizeChanged)
        addSubview(fontSizeField)

        let fontStepper = NSStepper()
        fontStepper.frame = NSRect(x: padding + 175, y: y, width: 19, height: 22)
        fontStepper.minValue = 8
        fontStepper.maxValue = 72
        fontStepper.integerValue = Settings.shared.fontSize
        fontStepper.target = self
        fontStepper.action = #selector(fontStepperChanged(_:))
        addSubview(fontStepper)

        y -= 40

        // Shell
        let shellLabel = createLabel("Shell:")
        shellLabel.frame = NSRect(x: padding, y: y, width: 100, height: 22)
        addSubview(shellLabel)

        shellField = NSTextField()
        shellField.frame = NSRect(x: padding + 110, y: y, width: 250, height: 22)
        shellField.stringValue = Settings.shared.shell
        shellField.target = self
        shellField.action = #selector(shellChanged)
        addSubview(shellField)

        y -= 40

        // Theme
        let themeLabel = createLabel("Theme:")
        themeLabel.frame = NSRect(x: padding, y: y, width: 100, height: 22)
        addSubview(themeLabel)

        themePopup = NSPopUpButton()
        themePopup.frame = NSRect(x: padding + 110, y: y, width: 150, height: 22)
        for theme in Theme.allThemes {
            themePopup.addItem(withTitle: theme.name)
        }
        themePopup.selectItem(withTitle: Settings.shared.theme.name)
        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        addSubview(themePopup)

        y -= 40

        // Cursor Blink
        cursorBlinkCheckbox = NSButton(checkboxWithTitle: "Cursor Blink", target: self, action: #selector(cursorBlinkChanged))
        cursorBlinkCheckbox.frame = NSRect(x: padding + 110, y: y, width: 150, height: 22)
        cursorBlinkCheckbox.state = Settings.shared.cursorBlink ? .on : .off
        addSubview(cursorBlinkCheckbox)

        y -= 60

        // Save button
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.frame = NSRect(x: bounds.width - padding - 80, y: padding, width: 80, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        addSubview(saveButton)
    }

    private func createLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
    }

    @objc private func fontSizeChanged() {
        if let size = Int(fontSizeField.stringValue), size >= 8, size <= 72 {
            Settings.shared.fontSize = size
        }
    }

    @objc private func fontStepperChanged(_ sender: NSStepper) {
        fontSizeField.stringValue = "\(sender.integerValue)"
        Settings.shared.fontSize = sender.integerValue
    }

    @objc private func shellChanged() {
        Settings.shared.shell = shellField.stringValue
    }

    @objc private func themeChanged() {
        if let themeName = themePopup.selectedItem?.title,
           let theme = Theme.named(themeName) {
            Settings.shared.theme = theme
        }
    }

    @objc private func cursorBlinkChanged() {
        Settings.shared.cursorBlink = cursorBlinkCheckbox.state == .on
    }

    @objc private func save() {
        Settings.shared.save()
        window?.close()
    }
}
