// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HebrewLayoutFixer",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "HebrewLayoutFixer",
            path: "Sources/HebrewLayoutFixer"
        )
    ]
)
