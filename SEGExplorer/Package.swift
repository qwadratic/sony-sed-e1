// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SEGExplorer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../SEGKit"),  // sibling directory at repo root
    ],
    targets: [
        .executableTarget(
            name: "SEGExplorer",
            dependencies: ["SEGKit"]
        ),
    ]
)
