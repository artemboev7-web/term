import AppKit

// MARK: - Login Window Controller

/// Window controller for the login → project picker flow
class LoginWindowController: NSWindowController {
    var onConnect: ((Project, String) -> Void)?  // (project, sessionId)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.init(window: window)
        setupWindow()

        // Decide initial VC based on auth state
        if AuthManager.shared.hasValidSession {
            showProjectPicker()
        } else {
            showLogin()
        }
    }

    private func setupWindow() {
        guard let window = window else { return }

        window.title = "Connect to Server"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.backgroundColor = Settings.shared.theme.background
        window.isMovableByWindowBackground = true
        window.center()
        window.hasShadow = true

        // Not resizable
        window.minSize = NSSize(width: 360, height: 320)
    }

    // MARK: - Flow

    private func showLogin() {
        let loginVC = LoginViewController()
        loginVC.onLoginSuccess = { [weak self] _ in
            self?.showProjectPicker()
        }
        contentViewController = loginVC

        // Resize window for login
        window?.setContentSize(NSSize(width: 360, height: 320))
        window?.center()
    }

    private func showProjectPicker() {
        let pickerVC = ProjectPickerViewController()
        pickerVC.onProjectSelected = { [weak self] project, sessionId in
            self?.onConnect?(project, sessionId)
            self?.close()
        }
        pickerVC.onLogout = { [weak self] in
            self?.showLogin()
        }
        contentViewController = pickerVC

        // Resize window for project picker
        window?.setContentSize(NSSize(width: 450, height: 400))
        window?.center()
    }
}
