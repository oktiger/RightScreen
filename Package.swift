// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RightScreen",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RightScreen", targets: ["RightScreen"])
    ],
    targets: [
        .executableTarget(
            name: "RightScreen",
            path: "RightScreen",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "RightScreenTests",
            dependencies: ["RightScreen"],
            path: "Tests/RightScreenTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
