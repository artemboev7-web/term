import AppKit

@main
struct TermApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate

        // Создаём меню до запуска
        setupMainMenu()

        app.run()
    }

    static func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "About Term", action: #selector(AppDelegate.showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences...", action: #selector(AppDelegate.showPreferences), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Term", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Term", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Shell menu
        let shellMenuItem = NSMenuItem()
        mainMenu.addItem(shellMenuItem)
        let shellMenu = NSMenu(title: "Shell")
        shellMenuItem.submenu = shellMenu

        shellMenu.addItem(withTitle: "New Window", action: #selector(AppDelegate.newWindow), keyEquivalent: "n")
        shellMenu.addItem(withTitle: "New Tab", action: #selector(AppDelegate.newTab), keyEquivalent: "t")
        shellMenu.addItem(NSMenuItem.separator())
        shellMenu.addItem(withTitle: "Split Horizontally", action: #selector(AppDelegate.splitHorizontally), keyEquivalent: "d")
        shellMenu.addItem(withTitle: "Split Vertically", action: #selector(AppDelegate.splitVertically), keyEquivalent: "d").keyEquivalentModifierMask = [.command, .shift]
        shellMenu.addItem(NSMenuItem.separator())
        shellMenu.addItem(withTitle: "Close Tab", action: #selector(AppDelegate.closeTab), keyEquivalent: "w")
        shellMenu.addItem(withTitle: "Close Window", action: #selector(AppDelegate.closeWindow), keyEquivalent: "w").keyEquivalentModifierMask = [.command, .shift]

        // Edit menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Find...", action: #selector(AppDelegate.showFind), keyEquivalent: "f")
        editMenu.addItem(withTitle: "Find Next", action: #selector(AppDelegate.findNext), keyEquivalent: "g")
        editMenu.addItem(withTitle: "Find Previous", action: #selector(AppDelegate.findPrevious), keyEquivalent: "g").keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Clear Buffer", action: #selector(AppDelegate.clearBuffer), keyEquivalent: "k")

        // View menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        viewMenu.addItem(withTitle: "Zoom In", action: #selector(AppDelegate.zoomIn), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(AppDelegate.zoomOut), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Reset Zoom", action: #selector(AppDelegate.resetZoom), keyEquivalent: "0")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f").keyEquivalentModifierMask = [.command, .control]

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu

        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Next Tab", action: #selector(AppDelegate.nextTab), keyEquivalent: "]").keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(withTitle: "Previous Tab", action: #selector(AppDelegate.previousTab), keyEquivalent: "[").keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}
