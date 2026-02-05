// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Term",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "Term",
            dependencies: ["SwiftTerm"],
            path: "Sources/Term",
            sources: [
                "App/TermApp.swift",
                "App/AppDelegate.swift",
                "Windows/TerminalWindowController.swift",
                "Windows/PreferencesWindowController.swift",
                "Views/TerminalViewController.swift",
                "Views/TerminalPaneView.swift",
                "Views/SearchBarView.swift",
                "Settings/Settings.swift",
                "Utils/Logger.swift"
            ]
        )
    ]
)
