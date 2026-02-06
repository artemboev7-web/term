import AppKit

// MARK: - Login View Controller

/// Login screen for codeboev.tech remote connection
class LoginViewController: NSViewController {
    var onLoginSuccess: ((UserInfo) -> Void)?

    private var serverField: NSTextField!
    private var usernameField: NSTextField!
    private var passwordField: NSSecureTextField!
    private var loginButton: NSButton!
    private var spinner: NSProgressIndicator!
    private var errorLabel: NSTextField!

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 320))
        container.wantsLayer = true

        let theme = Settings.shared.theme

        // Title
        let titleLabel = makeLabel("codeboev.tech", size: 20, bold: true)
        titleLabel.textColor = theme.foreground
        titleLabel.frame = NSRect(x: 30, y: 260, width: 300, height: 30)
        container.addSubview(titleLabel)

        let subtitleLabel = makeLabel("Remote Terminal", size: 13, bold: false)
        subtitleLabel.textColor = theme.foreground.withAlphaComponent(0.6)
        subtitleLabel.frame = NSRect(x: 30, y: 238, width: 300, height: 20)
        container.addSubview(subtitleLabel)

        // Server URL
        let serverLabel = makeLabel("Server", size: 11, bold: false)
        serverLabel.textColor = theme.foreground.withAlphaComponent(0.7)
        serverLabel.frame = NSRect(x: 30, y: 206, width: 300, height: 16)
        container.addSubview(serverLabel)

        serverField = makeTextField(placeholder: "https://codeboev.tech")
        serverField.stringValue = AuthManager.shared.serverURL
        serverField.frame = NSRect(x: 30, y: 180, width: 300, height: 24)
        container.addSubview(serverField)

        // Username
        let userLabel = makeLabel("Username", size: 11, bold: false)
        userLabel.textColor = theme.foreground.withAlphaComponent(0.7)
        userLabel.frame = NSRect(x: 30, y: 152, width: 300, height: 16)
        container.addSubview(userLabel)

        usernameField = makeTextField(placeholder: "username")
        usernameField.frame = NSRect(x: 30, y: 126, width: 300, height: 24)
        container.addSubview(usernameField)

        // Password
        let passLabel = makeLabel("Password", size: 11, bold: false)
        passLabel.textColor = theme.foreground.withAlphaComponent(0.7)
        passLabel.frame = NSRect(x: 30, y: 98, width: 300, height: 16)
        container.addSubview(passLabel)

        passwordField = NSSecureTextField(frame: NSRect(x: 30, y: 72, width: 300, height: 24))
        passwordField.placeholderString = "password"
        passwordField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        passwordField.bezelStyle = .roundedBezel
        passwordField.target = self
        passwordField.action = #selector(loginAction)
        container.addSubview(passwordField)

        // Login button
        loginButton = NSButton(frame: NSRect(x: 30, y: 30, width: 300, height: 30))
        loginButton.title = "Connect"
        loginButton.bezelStyle = .rounded
        loginButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        loginButton.target = self
        loginButton.action = #selector(loginAction)
        loginButton.keyEquivalent = "\r"
        container.addSubview(loginButton)

        // Spinner
        spinner = NSProgressIndicator(frame: NSRect(x: 165, y: 34, width: 16, height: 16))
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        spinner.controlSize = .small
        container.addSubview(spinner)

        // Error label
        errorLabel = makeLabel("", size: 11, bold: false)
        errorLabel.textColor = NSColor.systemRed
        errorLabel.frame = NSRect(x: 30, y: 4, width: 300, height: 20)
        errorLabel.alignment = .center
        container.addSubview(errorLabel)

        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Focus username field
        view.window?.makeFirstResponder(usernameField)
    }

    // MARK: - Actions

    @objc private func loginAction() {
        let server = serverField.stringValue.trimmingCharacters(in: .whitespaces)
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
        let password = passwordField.stringValue

        guard !username.isEmpty else {
            showError("Enter username")
            return
        }
        guard !password.isEmpty else {
            showError("Enter password")
            return
        }

        // Update server URL
        if !server.isEmpty {
            AuthManager.shared.serverURL = server
        }

        setLoading(true)
        errorLabel.stringValue = ""

        Task {
            do {
                let user = try await AuthManager.shared.login(username: username, password: password)
                await MainActor.run {
                    setLoading(false)
                    onLoginSuccess?(user)
                }
            } catch {
                await MainActor.run {
                    setLoading(false)
                    showError(error.localizedDescription)
                }
            }
        }
    }

    private func setLoading(_ loading: Bool) {
        loginButton.isEnabled = !loading
        usernameField.isEnabled = !loading
        passwordField.isEnabled = !loading
        serverField.isEnabled = !loading

        if loading {
            loginButton.title = ""
            spinner.startAnimation(nil)
        } else {
            loginButton.title = "Connect"
            spinner.stopAnimation(nil)
        }
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String, size: CGFloat, bold: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold
            ? NSFont.systemFont(ofSize: size, weight: .semibold)
            : NSFont.systemFont(ofSize: size, weight: .regular)
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        return label
    }

    private func makeTextField(placeholder: String) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        field.bezelStyle = .roundedBezel
        return field
    }
}
