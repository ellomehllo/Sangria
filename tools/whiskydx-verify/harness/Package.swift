// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Harness",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../../WhiskyKit")
    ],
    targets: [
        .executableTarget(
            name: "Harness",
            dependencies: [.product(name: "WhiskyKit", package: "WhiskyKit")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
