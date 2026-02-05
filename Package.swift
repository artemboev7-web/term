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
            path: "Sources/Term"
        )
    ]
)
