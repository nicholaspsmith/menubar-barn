// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Barn",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Barn", targets: ["Barn"]),
        .library(name: "BarnCore", targets: ["BarnCore"]),
    ],
    dependencies: [
        .package(path: "../StatusItemKit"),
        .package(path: "../HotkeyKit"),
    ],
    targets: [
        .target(name: "BarnCore"),
        .executableTarget(
            name: "Barn",
            dependencies: [
                "BarnCore",
                .product(name: "StatusItemKit", package: "StatusItemKit"),
                .product(name: "HotkeyKit", package: "HotkeyKit"),
            ]
        ),
        .testTarget(name: "BarnCoreTests", dependencies: ["BarnCore"]),
    ]
)
