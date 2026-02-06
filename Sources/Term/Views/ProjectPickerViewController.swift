import AppKit

// MARK: - Project Picker View Controller

/// Shows list of available projects and lets user select one to connect
class ProjectPickerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onProjectSelected: ((Project, String) -> Void)?  // (project, sessionId)
    var onLogout: (() -> Void)?

    private var projects: [Project] = []
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var connectButton: NSButton!
    private var logoutButton: NSButton!
    private var spinner: NSProgressIndicator!
    private var statusLabel: NSTextField!

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 400))
        container.wantsLayer = true

        let theme = Settings.shared.theme

        // Title
        let titleLabel = NSTextField(labelWithString: "Select Project")
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = theme.foreground
        titleLabel.frame = NSRect(x: 20, y: 360, width: 300, height: 28)
        container.addSubview(titleLabel)

        // User info
        let userLabel = NSTextField(labelWithString: AuthManager.shared.currentUser?.username ?? "")
        userLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        userLabel.textColor = theme.foreground.withAlphaComponent(0.5)
        userLabel.isBezeled = false
        userLabel.isEditable = false
        userLabel.drawsBackground = false
        userLabel.alignment = .right
        userLabel.frame = NSRect(x: 250, y: 365, width: 180, height: 18)
        container.addSubview(userLabel)

        // Table view for projects
        tableView = NSTableView()
        tableView.style = .plain
        tableView.rowHeight = 48
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(connectAction)
        tableView.target = self

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Project"
        nameColumn.width = 400
        tableView.addTableColumn(nameColumn)

        scrollView = NSScrollView(frame: NSRect(x: 20, y: 56, width: 410, height: 296))
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .bezelBorder
        container.addSubview(scrollView)

        // Connect button
        connectButton = NSButton(frame: NSRect(x: 290, y: 14, width: 140, height: 30))
        connectButton.title = "Connect"
        connectButton.bezelStyle = .rounded
        connectButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        connectButton.target = self
        connectButton.action = #selector(connectAction)
        connectButton.keyEquivalent = "\r"
        connectButton.isEnabled = false
        container.addSubview(connectButton)

        // Logout button
        logoutButton = NSButton(frame: NSRect(x: 20, y: 14, width: 80, height: 30))
        logoutButton.title = "Logout"
        logoutButton.bezelStyle = .rounded
        logoutButton.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        logoutButton.target = self
        logoutButton.action = #selector(logoutAction)
        container.addSubview(logoutButton)

        // Spinner
        spinner = NSProgressIndicator(frame: NSRect(x: 210, y: 170, width: 32, height: 32))
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        container.addSubview(spinner)

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = theme.foreground.withAlphaComponent(0.5)
        statusLabel.frame = NSRect(x: 100, y: 18, width: 180, height: 16)
        statusLabel.alignment = .center
        container.addSubview(statusLabel)

        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        loadProjects()
    }

    // MARK: - Load Projects

    private func loadProjects() {
        spinner.startAnimation(nil)
        statusLabel.stringValue = "Loading projects..."

        Task {
            do {
                let loadedProjects = try await APIClient.shared.getProjects()
                await MainActor.run {
                    self.projects = loadedProjects
                    self.tableView.reloadData()
                    self.spinner.stopAnimation(nil)
                    self.statusLabel.stringValue = "\(loadedProjects.count) project(s)"
                }
            } catch {
                await MainActor.run {
                    self.spinner.stopAnimation(nil)
                    self.statusLabel.stringValue = "Error: \(error.localizedDescription)"
                    logError("Failed to load projects: \(error)", context: "ProjectPicker")
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func connectAction() {
        let row = tableView.selectedRow
        guard row >= 0, row < projects.count else { return }

        let project = projects[row]
        connectButton.isEnabled = false
        statusLabel.stringValue = "Creating session..."
        spinner.startAnimation(nil)

        Task {
            do {
                let session = try await APIClient.shared.createSession(
                    projectPath: project.path,
                    provider: "claude",
                    model: "sonnet",
                    mode: "terminal"
                )
                await MainActor.run {
                    spinner.stopAnimation(nil)
                    onProjectSelected?(project, session.id)
                }
            } catch {
                await MainActor.run {
                    spinner.stopAnimation(nil)
                    connectButton.isEnabled = true
                    statusLabel.stringValue = "Error: \(error.localizedDescription)"
                    logError("Failed to create session: \(error)", context: "ProjectPicker")
                }
            }
        }
    }

    @objc private func logoutAction() {
        AuthManager.shared.logout()
        onLogout?()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return projects.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let project = projects[row]
        let theme = Settings.shared.theme

        let cellView = NSTableCellView()

        // Project name
        let nameLabel = NSTextField(labelWithString: project.displayName)
        nameLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        nameLabel.textColor = theme.foreground
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(nameLabel)

        // Path + branch
        var detail = project.path
        if let branch = project.gitBranch {
            detail += "  \(branch)"
        }
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        detailLabel.textColor = theme.foreground.withAlphaComponent(0.4)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 6),
            detailLabel.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
        ])

        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        connectButton.isEnabled = tableView.selectedRow >= 0
    }
}
