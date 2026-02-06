// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Term",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Term",
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
                "Utils/Logger.swift",
                // Terminal emulator (custom, no dependencies)
                "Terminal/TerminalCell.swift",
                "Terminal/TerminalBuffer.swift",
                "Terminal/TerminalParser.swift",
                "Terminal/TerminalEmulator.swift",
                "Terminal/PTYManager.swift",
                "Terminal/InputHandler.swift",
                // Network (data source abstraction + remote)
                "Network/TerminalDataSource.swift",
                "Network/LocalDataSource.swift",
                "Network/WebSocketDataSource.swift",
                "Network/APIClient.swift",
                "Network/AuthManager.swift",
                "Network/ServerModels.swift",
                // Login / Project Picker UI
                "Views/LoginViewController.swift",
                "Views/ProjectPickerViewController.swift",
                "Windows/LoginWindowController.swift",
                // Metal renderer
                "Metal/ShaderTypes.swift",
                "Metal/MetalRenderer.swift",
                "Metal/GlyphAtlas.swift",
                "Metal/CellGrid.swift",
                "Metal/MetalTerminalView.swift",
                "Metal/DirtyTracking.swift"
            ],
            resources: [
                .copy("Metal/Shaders.metal")
            ]
        )
    ]
)
