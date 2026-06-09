// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SEGKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SEGKit", targets: ["SEGKit"]),
    ],
    targets: [
        .target(
            name: "SEGKit",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
            ]
        ),
        .testTarget(name: "SEGKitTests", dependencies: ["SEGKit"]),
    ]
)
